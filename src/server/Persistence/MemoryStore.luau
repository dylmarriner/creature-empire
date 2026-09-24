-- In-memory store adapter with DataStore-like copy semantics. Used by tests and as the
-- explicit Studio fallback when DataStore access is disabled. Never used in live servers.
local MemoryStore = {}

local function deepCopy(value: any): any
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[deepCopy(key)] = deepCopy(child)
    end
    return copy
end

export type MemoryStore = {
    update: (
        key: string,
        transform: (old: any) -> any,
        userIds: { number }?
    ) -> (boolean, string?),
    read: (key: string) -> any,
    write: (key: string, value: any) -> (),
    setFailure: (message: string?) -> (),
}

function MemoryStore.new(): MemoryStore
    local records: { [string]: any } = {}
    local failure: string? = nil

    local store = {}

    function store.update(
        key: string,
        transform: (old: any) -> any,
        _userIds: { number }?
    ): (boolean, string?)
        if failure ~= nil then
            return false, failure
        end
        local nextValue = transform(deepCopy(records[key]))
        if nextValue ~= nil then
            records[key] = deepCopy(nextValue)
        end
        return true, nil
    end

    function store.read(key: string): any
        return deepCopy(records[key])
    end

    function store.write(key: string, value: any)
        records[key] = deepCopy(value)
    end

    function store.setFailure(message: string?)
        failure = message
    end

    return store
end

return MemoryStore
