-- Shared transfer ledger over an abstract atomic-update store (the same adapter shape
-- ProfileStore uses), so the protocol runs against MemoryStore in tests and a DataStore live.
--
-- Every call returns a DomainResult. `store_unavailable` means the outcome is UNKNOWN (the write
-- may or may not have landed); callers must treat it as uncertain, never as a refusal, and
-- recover by reading the record again.
local TransferDomain = require("./TransferDomain")

local KEY_PREFIX = "transfer_"

export type StoreAdapter = {
    update: (
        key: string,
        transform: (old: any) -> any,
        userIds: { number }?
    ) -> (boolean, string?),
}

export type LedgerStore = {
    _store: StoreAdapter,
    _clock: () -> number,
}

local LedgerStore = {}
LedgerStore.__index = LedgerStore

function LedgerStore.new(store: StoreAdapter, clock: () -> number): LedgerStore
    return setmetatable({ _store = store, _clock = clock }, LedgerStore) :: any
end

local function keyFor(id: string): string
    return KEY_PREFIX .. id
end

-- Runs a domain transform atomically. The transform may be retried by the store, so only the
-- last run's result is kept.
local function apply(
    self: LedgerStore,
    id: string,
    transform: (old: any) -> (any, any),
    userIds: { number }?
): any
    local result: any = nil

    local success, storeError = self._store.update(keyFor(id), function(old: any): any
        local nextValue, outcome = transform(old)
        result = outcome
        return nextValue
    end, userIds)

    if not success then
        return {
            ok = false,
            code = "store_unavailable",
            message = storeError or "ledger store update failed",
        }
    end

    return result
end

function LedgerStore.publish(self: LedgerStore, record: any): any
    local userIds = if type(record) == "table" and type(record.parties) == "table"
        then table.clone(record.parties)
        else nil
    local id = if type(record) == "table" then record.id else nil
    if type(id) ~= "string" then
        return { ok = false, code = "invalid_request", message = "record id is required" }
    end
    return apply(self, id, function(old)
        return TransferDomain.publish(old, record)
    end, userIds)
end

function LedgerStore.complete(self: LedgerStore, id: string, userIds: { number }?): any
    return apply(self, id, function(old)
        return TransferDomain.complete(old, self._clock())
    end, userIds)
end

function LedgerStore.cancel(self: LedgerStore, id: string, userIds: { number }?): any
    return apply(self, id, function(old)
        return TransferDomain.cancel(old, id, self._clock())
    end, userIds)
end

-- Reads a record without writing. Result value is the record, or nil when none exists.
function LedgerStore.get(self: LedgerStore, id: string): any
    local record: any = nil
    local success, storeError = self._store.update(keyFor(id), function(old: any): any
        record = old
        return nil
    end, nil)

    if not success then
        return {
            ok = false,
            code = "store_unavailable",
            message = storeError or "ledger store read failed",
        }
    end

    return { ok = true, value = record }
end

return LedgerStore
