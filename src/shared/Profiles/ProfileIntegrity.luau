local BuildingDefinitions = require("../Buildings/BuildingDefinitions")
local CreatureDefinitions = require("../Creatures/CreatureDefinitions")
local NumberUtil = require("../Util/NumberUtil")
local TableUtil = require("../Util/TableUtil")

-- Repairs cross-record assignment references in a schema-valid profile.
--
-- Schema validation checks each record in isolation; this pass makes the creature/building
-- worker relationship two-sided again. It only ever removes references (never grants
-- resources or ownership), is deterministic, and is idempotent. Returns the number of
-- references removed so callers can log unexpected drift.
local function repair(profile: any): number
    local fixes = 0

    for _, buildingId in ipairs(TableUtil.sortedKeys(profile.buildings)) do
        local building = profile.buildings[buildingId]
        local definition = BuildingDefinitions.ById[building.definitionId]
        local workType = definition.workType
        local maxWorkers = if NumberUtil.isNonNegativeInteger(definition.maxWorkers)
            then definition.maxWorkers
            else 0

        local kept = {}
        local seen = {}
        for _, creatureId in ipairs(building.assignedCreatureIds) do
            local creature = profile.creatures[creatureId]
            local species = if creature ~= nil
                then CreatureDefinitions.ById[creature.speciesId]
                else nil
            local affinity = if species ~= nil and workType ~= nil
                then species.workAffinity[workType]
                else nil

            local valid = not seen[creatureId]
                and creature ~= nil
                and creature.assignedBuildingId == buildingId
                and NumberUtil.isFiniteNumber(affinity)
                and affinity > 0
                and #kept < maxWorkers

            if valid then
                seen[creatureId] = true
                table.insert(kept, creatureId)
            else
                fixes += 1
            end
        end

        if #kept ~= #building.assignedCreatureIds then
            building.assignedCreatureIds = kept
        end
    end

    for _, creatureId in ipairs(TableUtil.sortedKeys(profile.creatures)) do
        local creature = profile.creatures[creatureId]
        local buildingId = creature.assignedBuildingId
        if buildingId ~= nil then
            local building = profile.buildings[buildingId]
            local listed = false
            if building ~= nil then
                for _, workerId in ipairs(building.assignedCreatureIds) do
                    if workerId == creatureId then
                        listed = true
                        break
                    end
                end
            end

            if not listed then
                creature.assignedBuildingId = nil
                fixes += 1
            end
        end
    end

    return fixes
end

return table.freeze({
    repair = repair,
})
