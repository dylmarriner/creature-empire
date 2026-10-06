--[[
    Runs the two-party transfer protocol. It owns the ORDER of steps, which is what keeps items
    from being duplicated or lost when a server crashes between steps:

      1. hold      both parties move their offer into escrow (profile commit)
      2. save      both profiles are saved. The ledger is published only after this, so a crash
                   can never leave a published record whose items are still live in a profile.
      3. publish   the pending record is written to the shared ledger
      4. complete  the record flips to completed (the point of no return)
      5. settle    each party, in one commit, gives away its offer and takes the other's

    Cancelling a pending record (stale, or on recovery) is the only other way out; settling a
    cancelled record restores each offer. Settling is idempotent, and `reconcile` re-runs it for
    every unsettled journal entry when a profile loads, so any crash converges.

    Persistence and clocks are injected so the whole protocol, including crashes at every step,
    is exercised by the Lune tests. This module has no engine dependencies, which is why it
    lives beside the other pure domains; the wiring to PlayerDataService and a real DataStore
    belongs to the first system that uses it, and only the server may call it.
]]
local EscrowDomain = require("./EscrowDomain")
local TableUtil = require("../Util/TableUtil")
local TransferDomain = require("./TransferDomain")

export type Ledger = {
    publish: (self: any, record: any) -> any,
    complete: (self: any, id: string, userIds: { number }?) -> any,
    cancel: (self: any, id: string, userIds: { number }?) -> any,
    get: (self: any, id: string) -> any,
}

-- Access to loaded profiles. `mutate` runs `fn(draft)` through the transactional pipeline and
-- returns its DomainResult, or nil when the player's profile is not loaded on this server.
-- `read` returns a read-only view of the committed profile (or nil). `save` persists it now.
export type ProfileAccess = {
    mutate: (userId: number, label: string, fn: (draft: any) -> any) -> any,
    read: (userId: number) -> any,
    save: (userId: number) -> boolean,
}

export type Options = {
    ledger: Ledger,
    profiles: ProfileAccess,
    clock: () -> number,
    generateId: () -> string,
    staleAfterSeconds: number?,
}

local DEFAULT_STALE_AFTER_SECONDS = 120

local TransferCoordinator = {}
TransferCoordinator.__index = TransferCoordinator

export type TransferCoordinator = typeof(setmetatable(
    {} :: {
        _ledger: Ledger,
        _profiles: ProfileAccess,
        _clock: () -> number,
        _generateId: () -> string,
        _staleAfter: number,
    },
    TransferCoordinator
))

local function ok(value: any)
    return { ok = true, value = value }
end

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

function TransferCoordinator.new(options: Options): TransferCoordinator
    return setmetatable({
        _ledger = options.ledger,
        _profiles = options.profiles,
        _clock = options.clock,
        _generateId = options.generateId,
        _staleAfter = options.staleAfterSeconds or DEFAULT_STALE_AFTER_SECONDS,
    }, TransferCoordinator) :: any
end

-- Returns the transfer's record (creating a cancelled tombstone if none exists) and whether
-- it is final. Result value is the record, or nil when the ledger could not be reached.
local function resolveRecord(self: TransferCoordinator, id: string, entryCreatedAt: number): any
    local fetched = self._ledger:get(id)
    if fetched.ok ~= true then
        return nil
    end

    local record = fetched.value
    local userIds = if record ~= nil then record.parties else nil

    if record == nil then
        -- Nothing was ever published. Tombstone it so a late publish from a crashed or
        -- superseded server cannot resurrect the transfer after the offer is restored.
        local cancelled = self._ledger:cancel(id, nil)
        if cancelled.ok ~= true then
            return nil
        end
        return cancelled.value
    end

    if record.state == "pending" and self._clock() - entryCreatedAt >= self._staleAfter then
        local cancelled = self._ledger:cancel(id, userIds)
        if cancelled.ok == true then
            return cancelled.value
        end
        if cancelled.code == "transfer_conflict" then
            -- Lost the race: it completed first. Read the final state.
            local reread = self._ledger:get(id)
            if reread.ok == true and reread.value ~= nil then
                return reread.value
            end
        end
        return nil
    end

    return record
end

-- Settles one journal entry for `userId` against the ledger's verdict. Result value:
--   { state = "none" }       nothing to settle
--   { state = "pending" }    still waiting on the ledger (or it could not be reached)
--   { state = "completed" }  swapped
--   { state = "cancelled" }  offer returned
function TransferCoordinator.settle(self: TransferCoordinator, userId: number, id: string): any
    local profile = self._profiles.read(userId)
    if profile == nil then
        return ok({ state = "pending" })
    end

    local entry = profile.transfers[id]
    if entry == nil then
        return ok({ state = "none" })
    end

    local record = resolveRecord(self, id, entry.createdAt)
    if record == nil or record.state == "pending" then
        return ok({ state = "pending" })
    end

    local mutation: any
    local state: string
    if record.state == "completed" and TransferDomain.isParty(record, userId) then
        state = "completed"
        local counterpart = TransferDomain.counterpartOffer(record, userId)
        mutation = self._profiles.mutate(userId, "TransferSettle", function(draft)
            return EscrowDomain.settleCompleted(draft, id, counterpart, self._generateId)
        end)
    else
        -- Cancelled, or completed without this user as a party: the offer comes back.
        state = "cancelled"
        mutation = self._profiles.mutate(userId, "TransferRestore", function(draft)
            return EscrowDomain.restore(draft, id, self._generateId)
        end)
    end

    if mutation == nil then
        return ok({ state = "pending" })
    end
    if mutation.ok ~= true then
        return mutation
    end

    self._profiles.save(userId)
    return ok({ state = state })
end

-- Settles every unsettled transfer a profile carries. Call when a profile finishes loading.
function TransferCoordinator.reconcile(self: TransferCoordinator, userId: number): any
    local profile = self._profiles.read(userId)
    if profile == nil then
        return ok({ settled = 0, pending = 0 })
    end

    local settled = 0
    local pending = 0
    for _, id in ipairs(TableUtil.sortedKeys(profile.transfers)) do
        local result = self:settle(userId, id)
        if result.ok ~= true or result.value.state == "pending" then
            pending += 1
        elseif result.value.state ~= "none" then
            settled += 1
        end
    end

    return ok({ settled = settled, pending = pending })
end

-- Restores a hold made by this call without involving the ledger. Only valid before anything
-- was published, so no other server can know about it.
local function releaseHold(self: TransferCoordinator, userId: number, id: string)
    self._profiles.mutate(userId, "TransferRestore", function(draft)
        return EscrowDomain.restore(draft, id, self._generateId)
    end)
    self._profiles.save(userId)
end

-- Atomically swaps `partyA.offer` for `partyB.offer` (either may be empty, making it a gift).
-- Both players must be loaded on this server. Result value is `{ state }` as for `settle`;
-- a state of "pending" means the ledger could not be reached and `reconcile` will finish it.
function TransferCoordinator.swap(
    self: TransferCoordinator,
    id: string,
    kind: string,
    partyA: { userId: number, offer: any },
    partyB: { userId: number, offer: any }
): any
    if type(id) ~= "string" or id == "" then
        return err("invalid_request", "transfer id is required")
    end
    if partyA.userId == partyB.userId then
        return err("invalid_request", "a transfer needs two different players")
    end

    local now = self._clock()

    local heldA = self._profiles.mutate(partyA.userId, "TransferHold", function(draft)
        return EscrowDomain.hold(draft, id, partyA.offer, now)
    end)
    if heldA == nil then
        return err("invalid_request", "player is not loaded")
    end
    if heldA.ok ~= true then
        return heldA
    end

    local heldB = self._profiles.mutate(partyB.userId, "TransferHold", function(draft)
        return EscrowDomain.hold(draft, id, partyB.offer, now)
    end)
    if heldB == nil or heldB.ok ~= true then
        releaseHold(self, partyA.userId, id)
        return heldB or err("invalid_request", "player is not loaded")
    end

    -- Escrow must be durable before anything is published.
    if not self._profiles.save(partyA.userId) or not self._profiles.save(partyB.userId) then
        releaseHold(self, partyA.userId, id)
        releaseHold(self, partyB.userId, id)
        return err("internal_error", "could not save; transfer abandoned")
    end

    local record = TransferDomain.newRecord(
        id,
        kind,
        { userId = partyA.userId, offer = heldA.value },
        { userId = partyB.userId, offer = heldB.value },
        now
    )

    -- From here the ledger may know about the transfer, so a failed or uncertain step is never
    -- undone by hand: settle reads the ledger's verdict and acts on that.
    local published = self._ledger:publish(record)
    if published.ok == true then
        self._ledger:complete(id, record.parties)
    end

    local resultA = self:settle(partyA.userId, id)
    local resultB = self:settle(partyB.userId, id)

    local stateA = if resultA.ok == true then resultA.value.state else "pending"
    local stateB = if resultB.ok == true then resultB.value.state else "pending"
    if stateA ~= stateB then
        -- Both parties read one ledger verdict, so a mismatch only means one side is still
        -- waiting to settle.
        return ok({ state = "pending" })
    end

    if stateA == "cancelled" then
        return err("transfer_not_pending", "transfer was cancelled")
    end
    return ok({ state = stateA })
end

return TransferCoordinator
