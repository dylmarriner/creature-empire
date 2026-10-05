-- Kill switches for the post-launch systems. Every flag defaults to off so a system ships dark
-- and is enabled (or disabled again) live without publishing a new place version. The server
-- reads overrides from a DataStore; this module is the pure, tested half.
local DEFAULTS = table.freeze({
    breeding = false,
    expeditions = false,
    store = false,
    trading = false,
    marketplace = false,
    guilds = false,
})

local FeatureFlags = {}
FeatureFlags.__index = FeatureFlags

FeatureFlags.Defaults = DEFAULTS

export type FeatureFlags = typeof(setmetatable(
    {} :: { _overrides: { [string]: boolean } },
    FeatureFlags
))

function FeatureFlags.new(): FeatureFlags
    return setmetatable({ _overrides = {} }, FeatureFlags)
end

-- Whether `name` is on. An unknown name is a programming error, not a disabled feature.
function FeatureFlags.isEnabled(self: FeatureFlags, name: string): boolean
    local default = DEFAULTS[name]
    assert(default ~= nil, `unknown feature flag: {tostring(name)}`)

    local override = self._overrides[name]
    if override ~= nil then
        return override
    end
    return default
end

-- Replaces the whole override set from stored data (so removing a flag from the store restores
-- its default). Only known names with boolean values are accepted; anything else is ignored and
-- counted. Returns (accepted, rejected).
function FeatureFlags.applyOverrides(self: FeatureFlags, stored: any): (number, number)
    local overrides = {}
    local accepted = 0
    local rejected = 0

    if type(stored) == "table" then
        for name, value in pairs(stored) do
            if type(name) == "string" and DEFAULTS[name] ~= nil and type(value) == "boolean" then
                overrides[name] = value
                accepted += 1
            else
                rejected += 1
            end
        end
    elseif stored ~= nil then
        rejected += 1
    end

    self._overrides = overrides
    return accepted, rejected
end

-- The effective value of every flag, for logging.
function FeatureFlags.snapshot(self: FeatureFlags): { [string]: boolean }
    local result = {}
    for name in pairs(DEFAULTS) do
        result[name] = self:isEnabled(name)
    end
    return result
end

return FeatureFlags
