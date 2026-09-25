local GameConfig = require("../Config/GameConfig")
local CapacityDomain = require("../Economy/CapacityDomain")
local ProductionDomain = require("../Economy/ProductionDomain")
local ObjectiveDefinitions = require("../Progression/ObjectiveDefinitions")
local ObjectiveDomain = require("../Progression/ObjectiveDomain")
local TableUtil = require("../Util/TableUtil")

-- Builds the replicated view of a player's own profile plus derived values the client
-- needs for presentation. Everything here is display data; the server never reads it back.
local function build(profile: any, now: number)
    local rates = {}
    for buildingId, building in pairs(profile.buildings) do
        rates[buildingId] = ProductionDomain.cyclesPerMinute(profile, building)
    end

    local objective = ObjectiveDomain.currentObjective(profile)
    local objectiveView = nil
    if objective ~= nil then
        local current, target = ObjectiveDomain.progress(profile, objective.condition)
        objectiveView = {
            id = objective.id,
            title = objective.title,
            description = objective.description,
            rewardCoins = objective.rewardCoins,
            current = current,
            target = target,
            order = objective.order,
        }
    end

    return {
        serverTime = now,
        offlineCapSeconds = GameConfig.OFFLINE_PRODUCTION_CAP_SECONDS,
        profile = TableUtil.deepCopy(profile),
        rates = rates,
        storageCapacity = CapacityDomain.storageCapacity(profile),
        creatureCapacity = CapacityDomain.creatureCapacity(profile),
        creatureCount = CapacityDomain.creatureCount(profile),
        objective = objectiveView,
        objectiveCount = #ObjectiveDefinitions.Ordered,
    }
end

return table.freeze({
    build = build,
})
