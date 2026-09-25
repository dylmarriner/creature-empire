local BuildingDefinitions = require("./BuildingDefinitions")
local InventoryDomain = require("../Economy/InventoryDomain")
local ProductionDomain = require("../Economy/ProductionDomain")
local ItemDefinitions = require("../Items/ItemDefinitions")

local function ok(value: any)
    return { ok = true, value = value }
end

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

local function isFiniteNumber(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isNonNegativeInteger(value: any): boolean
    return isFiniteNumber(value) and value >= 0 and value % 1 == 0
end

local function isPositiveInteger(value: any): boolean
    return isNonNegativeInteger(value) and value > 0
end

local function multiplierCount(value: any): number?
    if type(value) ~= "table" then
        return nil
    end

    local count = 0
    for key, multiplier in pairs(value) do
        if
            type(key) ~= "number"
            or key < 1
            or key % 1 ~= 0
            or not isFiniteNumber(multiplier)
            or multiplier <= 0
        then
            return nil
        end
        count += 1
    end

    for index = 1, count do
        if not isFiniteNumber(value[index]) or value[index] <= 0 then
            return nil
        end
    end

    return count
end

local function validUpgradeCost(cost: any): boolean
    if type(cost) ~= "table" or next(cost) == nil then
        return false
    end

    for itemId, quantity in pairs(cost) do
        if
            type(itemId) ~= "string"
            or ItemDefinitions.ById[itemId] == nil
            or not isPositiveInteger(quantity)
        then
            return false
        end
    end

    return true
end

local function upgrade(profile: any, buildingInstanceId: any, now: any)
    if
        type(profile) ~= "table"
        or type(profile.buildings) ~= "table"
        or type(buildingInstanceId) ~= "string"
        or buildingInstanceId == ""
        or not isNonNegativeInteger(now)
    then
        return err("invalid_request", "building upgrade request is invalid")
    end

    local building = profile.buildings[buildingInstanceId]
    if building == nil then
        return err("building_not_owned", "building is not owned by this profile")
    end
    if type(building) ~= "table" or building.id ~= buildingInstanceId then
        return err("invalid_request", "owned building record is invalid")
    end

    local definitionId = building.definitionId
    local definition = if type(definitionId) == "string"
        then BuildingDefinitions.ById[definitionId]
        else nil
    if definition == nil then
        return err("invalid_request", "owned building definition is invalid")
    end
    if definition.kind ~= "production" then
        return err("max_level_reached", "building has no Phase 4 upgrades")
    end

    local maxLevel = multiplierCount(definition.levelMultipliers)
    if maxLevel == nil or maxLevel < 1 or type(definition.upgradeCosts) ~= "table" then
        return err("invalid_request", "building upgrade definition is invalid")
    end
    if not isPositiveInteger(building.level) or building.level > maxLevel then
        return err("invalid_request", "owned building level is invalid")
    end
    if building.level == maxLevel then
        return err("max_level_reached", "building is already at maximum level")
    end

    local nextLevel = building.level + 1
    local cost = definition.upgradeCosts[nextLevel]
    if not validUpgradeCost(cost) then
        return err("invalid_request", "building upgrade cost is invalid")
    end
    if definition.inputItemId ~= nil and cost[definition.inputItemId] ~= nil then
        return err("invalid_request", "upgrade cost conflicts with settlement input")
    end

    if not InventoryDomain.canAfford(profile, cost) then
        return err("insufficient_resources", "insufficient resources for building upgrade")
    end

    local settlement = ProductionDomain.settle(profile, buildingInstanceId, now)
    if settlement.ok ~= true then
        return settlement
    end

    local payment = InventoryDomain.applyCost(profile, cost)
    if payment.ok ~= true then
        return err("invalid_request", "prevalidated building upgrade payment failed")
    end

    building.level = nextLevel
    return ok(nextLevel)
end

return table.freeze({
    upgrade = upgrade,
})
