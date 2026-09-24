local GameConfig = require("../Config/GameConfig")
local BuildingDefinitions = require("../Buildings/BuildingDefinitions")
local NumberUtil = require("../Util/NumberUtil")

local function utilityLevels(profile: any, utility: string): number
    local total = 0
    if type(profile) ~= "table" or type(profile.buildings) ~= "table" then
        return total
    end

    for _, building in pairs(profile.buildings) do
        if type(building) == "table" and type(building.definitionId) == "string" then
            local definition = BuildingDefinitions.ById[building.definitionId]
            if
                definition ~= nil
                and definition.utility == utility
                and NumberUtil.isPositiveInteger(building.level)
            then
                total += building.level
            end
        end
    end

    return total
end

-- Per-item storage limit. Production and gathering never raise a balance above it;
-- refunds and rewards may, so the limit caps income rather than ownership.
local function storageCapacity(profile: any): number
    return GameConfig.BASE_STORAGE_CAPACITY
        + utilityLevels(profile, "storage") * GameConfig.WAREHOUSE_STORAGE_PER_LEVEL
end

local function storageSpace(profile: any, itemId: string): number
    local balance = 0
    if type(profile) == "table" and type(profile.inventory) == "table" then
        local current = profile.inventory[itemId]
        if NumberUtil.isNonNegativeInteger(current) then
            balance = current
        end
    end

    return math.max(0, storageCapacity(profile) - balance)
end

local function creatureCapacity(profile: any): number
    return GameConfig.BASE_CREATURE_CAPACITY
        + utilityLevels(profile, "habitat") * GameConfig.HABITAT_CREATURE_CAPACITY_PER_LEVEL
end

local function creatureCount(profile: any): number
    local count = 0
    if type(profile) == "table" and type(profile.creatures) == "table" then
        for _ in pairs(profile.creatures) do
            count += 1
        end
    end
    return count
end

local function hasCreatureSpace(profile: any): boolean
    return creatureCount(profile) < creatureCapacity(profile)
end

local function hasUtility(profile: any, utility: string): boolean
    return utilityLevels(profile, utility) > 0
end

return table.freeze({
    storageCapacity = storageCapacity,
    storageSpace = storageSpace,
    creatureCapacity = creatureCapacity,
    creatureCount = creatureCount,
    hasCreatureSpace = hasCreatureSpace,
    hasUtility = hasUtility,
})
