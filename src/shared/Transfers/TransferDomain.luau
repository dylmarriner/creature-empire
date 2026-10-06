-- Pure state machine for ledger records: the shared, cross-server source of truth for a
-- two-party transfer (a trade, a gift, later a marketplace sale).
--
--   pending ──complete──▶ completed   (point of no return: each party receives the other's offer)
--      └─────cancel────▶ cancelled    (each party gets its own offer back)
--
-- Every function is a transform for an atomic store update: it takes the stored record (or nil)
-- and returns `(nextRecord, result)`. A nil `nextRecord` means "write nothing". Because the
-- store applies the transform atomically, `complete` and `cancel` can race and exactly one wins.
-- Transforms may be re-run by the store on contention, so they are free of side effects.
local TableUtil = require("../Util/TableUtil")

local TransferDomain = {}

local function ok(value: any)
    return { ok = true, value = value }
end

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

local function isUserId(value: any): boolean
    return type(value) == "number" and value % 1 == 0 and value > 0 and value < 2 ^ 53
end

function TransferDomain.offerKey(userId: number): string
    return tostring(userId)
end

-- Builds a pending record. `offers` maps each party's user id (as a string) to its payload.
function TransferDomain.newRecord(
    id: string,
    kind: string,
    partyA: { userId: number, offer: any },
    partyB: { userId: number, offer: any },
    now: number
): any
    return {
        id = id,
        kind = kind,
        state = "pending",
        parties = { partyA.userId, partyB.userId },
        offers = {
            [TransferDomain.offerKey(partyA.userId)] = TableUtil.deepCopy(partyA.offer),
            [TransferDomain.offerKey(partyB.userId)] = TableUtil.deepCopy(partyB.offer),
        },
        createdAt = now,
    }
end

-- Shape check for a record about to be published. Payload contents are validated by the
-- profile schema when each party holds its offer, so only the envelope is checked here.
function TransferDomain.validateRecord(record: any): (boolean, string?)
    if type(record) ~= "table" then
        return false, "record must be a table"
    end
    if type(record.id) ~= "string" or record.id == "" then
        return false, "record id must be a non-empty string"
    end
    if type(record.kind) ~= "string" or record.kind == "" then
        return false, "record kind must be a non-empty string"
    end
    if record.state ~= "pending" then
        return false, "new records must be pending"
    end
    if type(record.createdAt) ~= "number" or record.createdAt % 1 ~= 0 or record.createdAt < 0 then
        return false, "createdAt must be a non-negative integer"
    end
    if type(record.parties) ~= "table" or #record.parties ~= 2 then
        return false, "a transfer has exactly two parties"
    end
    local first, second = record.parties[1], record.parties[2]
    if not isUserId(first) or not isUserId(second) or first == second then
        return false, "parties must be two different user ids"
    end
    if type(record.offers) ~= "table" then
        return false, "offers must be a table"
    end
    for _, userId in ipairs(record.parties) do
        if type(record.offers[TransferDomain.offerKey(userId)]) ~= "table" then
            return false, "every party needs an offer"
        end
    end
    return true
end

function TransferDomain.isParty(record: any, userId: number): boolean
    if type(record) ~= "table" or type(record.parties) ~= "table" then
        return false
    end
    return record.parties[1] == userId or record.parties[2] == userId
end

-- The offer `userId` receives when the record completes: the other party's.
function TransferDomain.counterpartOffer(record: any, userId: number): any
    for _, partyId in ipairs(record.parties) do
        if partyId ~= userId then
            return record.offers[TransferDomain.offerKey(partyId)]
        end
    end
    return nil
end

-- Publishes a new pending record. Republishing an existing record is idempotent, except that
-- a cancelled one (including a tombstone left by crash recovery) refuses: its publisher must
-- restore its offer instead.
function TransferDomain.publish(old: any, record: any): (any, any)
    local valid, reason = TransferDomain.validateRecord(record)
    if not valid then
        return nil, err("invalid_request", reason or "invalid transfer record")
    end

    if old == nil then
        return TableUtil.deepCopy(record), ok(record)
    end

    if old.state == "cancelled" then
        return nil, err("transfer_not_pending", "transfer was cancelled")
    end

    return nil, ok(old)
end

-- Moves a pending record to completed.
function TransferDomain.complete(old: any, now: number): (any, any)
    if old == nil then
        return nil, err("transfer_not_found", "transfer does not exist")
    end

    if old.state == "completed" then
        return nil, ok(old)
    end

    if old.state ~= "pending" then
        return nil, err("transfer_not_pending", "transfer was cancelled")
    end

    local nextRecord = TableUtil.deepCopy(old)
    nextRecord.state = "completed"
    nextRecord.completedAt = now
    return nextRecord, ok(nextRecord)
end

-- Moves a pending record to cancelled. A missing record becomes a cancelled tombstone so a late
-- publish from a server that crashed or lost its session lock cannot resurrect the transfer.
-- A completed record cannot be cancelled: that race is decided in favour of whoever wrote first.
function TransferDomain.cancel(old: any, id: string, now: number): (any, any)
    if old == nil then
        local tombstone = {
            id = id,
            kind = "tombstone",
            state = "cancelled",
            parties = {},
            offers = {},
            createdAt = now,
            cancelledAt = now,
        }
        return tombstone, ok(tombstone)
    end

    if old.state == "cancelled" then
        return nil, ok(old)
    end

    if old.state == "completed" then
        return nil, err("transfer_conflict", "transfer already completed")
    end

    local nextRecord = TableUtil.deepCopy(old)
    nextRecord.state = "cancelled"
    nextRecord.cancelledAt = now
    return nextRecord, ok(nextRecord)
end

return table.freeze(TransferDomain)
