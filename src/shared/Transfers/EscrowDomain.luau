-- Profile-side half of the transfer protocol. These are ordinary profile mutations, run through
-- the transactional ActionPipeline like any other.
--
-- A party "holds" its offer by moving it out of its live data into `profile.transfers[id]`, in
-- one validated commit. From then on the offer is inert: the ledger record decides whether it is
-- given to the other party (completed) or returned (cancelled). `settle*` and `restore` are
-- idempotent: with no journal entry there is nothing left to do, which is what makes
-- crash-recovery replays safe.
--
-- Receiving or restoring never refuses for capacity. Once a ledger record is completed or
-- cancelled the outcome is final, so refusing would strand the items; callers check room before
-- publishing instead.
local ItemDefinitions = require("../Items/ItemDefinitions")
local TableUtil = require("../Util/TableUtil")

local EscrowDomain = {}

local function ok(value: any)
    return { ok = true, value = value }
end

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

local function isPositiveInteger(value: any): boolean
    return type(value) == "number" and value % 1 == 0 and value >= 1 and value < 2 ^ 53
end

local function isNonNegativeInteger(value: any): boolean
    return type(value) == "number" and value % 1 == 0 and value >= 0 and value < 2 ^ 53
end

function EscrowDomain.emptyPayload(): any
    return { items = {}, coins = 0, creatures = {} }
end

-- Adds a payload's contents to a profile. A creature whose id already exists is given a fresh
-- id so it can never overwrite one the profile owns.
local function addPayload(profile: any, payload: any, generateId: (() -> string)?)
    for itemId, quantity in pairs(payload.items) do
        profile.inventory[itemId] = (profile.inventory[itemId] or 0) + quantity
    end

    profile.currencies.coins += payload.coins

    for _, creatureId in ipairs(TableUtil.sortedKeys(payload.creatures)) do
        local creature = TableUtil.deepCopy(payload.creatures[creatureId])
        creature.assignedBuildingId = nil

        local newId = creatureId
        if profile.creatures[newId] ~= nil then
            repeat
                assert(generateId ~= nil, "an id generator is required to receive creatures")
                newId = generateId()
            until type(newId) == "string" and newId ~= "" and profile.creatures[newId] == nil
        end

        creature.id = newId
        profile.creatures[newId] = creature
    end
end

-- Moves `offer` ({ items?, coins?, creatures? = { creatureId } }) into escrow under `id`.
-- Everything is checked before anything is changed. Returns the held payload.
function EscrowDomain.hold(profile: any, id: any, offer: any, now: any)
    if type(id) ~= "string" or id == "" then
        return err("invalid_request", "transfer id is required")
    end
    if not isNonNegativeInteger(now) then
        return err("invalid_request", "time must be a non-negative integer")
    end
    if type(profile) ~= "table" or type(offer) ~= "table" then
        return err("invalid_request", "offer is required")
    end
    if profile.transfers[id] ~= nil then
        return err("transfer_conflict", "this transfer is already escrowed")
    end

    local items = offer.items or {}
    local coins = offer.coins or 0
    local creatureIds = offer.creatures or {}
    if type(items) ~= "table" or type(creatureIds) ~= "table" then
        return err("invalid_request", "offer is malformed")
    end
    if not isNonNegativeInteger(coins) then
        return err("invalid_request", "coins must be a non-negative integer")
    end

    for itemId, quantity in pairs(items) do
        if type(itemId) ~= "string" or ItemDefinitions.ById[itemId] == nil then
            return err("invalid_request", "unknown item")
        end
        if not isPositiveInteger(quantity) then
            return err("invalid_request", "item quantities must be positive integers")
        end
        if (profile.inventory[itemId] or 0) < quantity then
            return err("insufficient_resources", "not enough of that item")
        end
    end

    if profile.currencies.coins < coins then
        return err("insufficient_currency", "not enough coins")
    end

    local seen = {}
    local count = 0
    for _, creatureId in ipairs(creatureIds) do
        if type(creatureId) ~= "string" or seen[creatureId] then
            return err("invalid_request", "creature ids must be unique strings")
        end
        seen[creatureId] = true
        count += 1

        local creature = profile.creatures[creatureId]
        if creature == nil then
            return err("creature_not_owned", "you do not own that creature")
        end
        if creature.assignedBuildingId ~= nil then
            return err("creature_already_assigned", "unassign that creature first")
        end
    end
    if count ~= #creatureIds then
        return err("invalid_request", "creature ids must be a list")
    end

    local payload = EscrowDomain.emptyPayload()
    for itemId, quantity in pairs(items) do
        local remaining = profile.inventory[itemId] - quantity
        profile.inventory[itemId] = if remaining > 0 then remaining else nil
        payload.items[itemId] = quantity
    end
    profile.currencies.coins -= coins
    payload.coins = coins
    for _, creatureId in ipairs(creatureIds) do
        payload.creatures[creatureId] = profile.creatures[creatureId]
        profile.creatures[creatureId] = nil
    end

    profile.transfers[id] = {
        id = id,
        createdAt = now,
        offer = TableUtil.deepCopy(payload),
    }

    return ok(payload)
end

-- Returns the held offer to the profile and clears the journal entry (the record was cancelled).
function EscrowDomain.restore(profile: any, id: any, generateId: any)
    if type(id) ~= "string" or type(profile) ~= "table" then
        return err("invalid_request", "transfer id is required")
    end

    local entry = profile.transfers[id]
    if entry == nil then
        return ok({ settled = false })
    end

    addPayload(profile, entry.offer, generateId)
    profile.transfers[id] = nil
    return ok({ settled = true })
end

-- Gives the held offer away and takes the counterpart's (the record completed), in one commit.
function EscrowDomain.settleCompleted(profile: any, id: any, counterpartOffer: any, generateId: any)
    if type(id) ~= "string" or type(profile) ~= "table" or type(counterpartOffer) ~= "table" then
        return err("invalid_request", "transfer id and counterpart offer are required")
    end

    local entry = profile.transfers[id]
    if entry == nil then
        return ok({ settled = false })
    end

    addPayload(profile, counterpartOffer, generateId)
    profile.transfers[id] = nil
    return ok({ settled = true })
end

return table.freeze(EscrowDomain)
