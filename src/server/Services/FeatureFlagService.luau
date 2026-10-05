-- Keeps the feature flags in step with the `FeatureFlags_v1` DataStore (key `flags`, a table of
-- flag name -> boolean). A read failure keeps the last known flags, so a DataStore outage can
-- never switch a system on; the first failure and the recovery are logged once each.
local DataStoreService = game:GetService("DataStoreService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FeatureFlags = require(Shared.Config.FeatureFlags)

local Logger = require("./Logger")

local DATASTORE_NAME = "FeatureFlags_v1"
local FLAGS_KEY = "flags"
local POLL_SECONDS = 60

local logger = Logger.new("FeatureFlags")

local FeatureFlagService = {}
FeatureFlagService.__index = FeatureFlagService

export type FeatureFlagService = typeof(setmetatable(
    {} :: {
        _flags: FeatureFlags.FeatureFlags,
        _store: DataStore?,
        _failing: boolean,
    },
    FeatureFlagService
))

function FeatureFlagService.new(): FeatureFlagService
    local success, store = pcall(function()
        return DataStoreService:GetDataStore(DATASTORE_NAME)
    end)

    return setmetatable({
        _flags = FeatureFlags.new(),
        _store = if success then store else nil,
        _failing = false,
    }, FeatureFlagService)
end

function FeatureFlagService.isEnabled(self: FeatureFlagService, name: string): boolean
    return self._flags:isEnabled(name)
end

function FeatureFlagService.snapshot(self: FeatureFlagService): { [string]: boolean }
    return self._flags:snapshot()
end

-- One read of the stored flags. Returns whether the read succeeded.
function FeatureFlagService.refresh(self: FeatureFlagService): boolean
    local store = self._store
    if store == nil then
        return false
    end

    local success, stored = pcall(function()
        return store:GetAsync(FLAGS_KEY)
    end)

    if not success then
        if not self._failing then
            self._failing = true
            logger.warn("could not read feature flags; keeping the last known values", {
                reason = tostring(stored),
            })
        end
        return false
    end

    if self._failing then
        self._failing = false
        logger.info("feature flag reads recovered")
    end

    local accepted, rejected = self._flags:applyOverrides(stored)
    if rejected > 0 then
        logger.warn("ignored invalid feature flag entries", { rejected = rejected })
    end
    logger.info("feature flags loaded", { overrides = accepted })
    return true
end

function FeatureFlagService.start(self: FeatureFlagService)
    task.spawn(function()
        while true do
            self:refresh()
            task.wait(POLL_SECONDS)
        end
    end)
end

return FeatureFlagService
