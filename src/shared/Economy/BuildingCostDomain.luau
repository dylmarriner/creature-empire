local BuildingDefinitions = require("../Buildings/BuildingDefinitions")
local InventoryDomain = require("./InventoryDomain")

local function ok(value: any)
    return { ok = true, value = value }
end

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

local function getDefinition(buildingDefinitionId: any)
    if type(buildingDefinitionId) ~= "string" then
        return nil
    end

    return BuildingDefinitions.ById[buildingDefinitionId]
end

local function canAfford(profile: any, buildingDefinitionId: string)
    local definition = getDefinition(buildingDefinitionId)
    if definition == nil or type(definition.cost) ~= "table" then
        return err("invalid_request", "building definition is unknown or has no valid cost")
    end

    return ok(InventoryDomain.canAfford(profile, definition.cost))
end

local function purchase(profile: any, buildingDefinitionId: string)
    local definition = getDefinition(buildingDefinitionId)
    if definition == nil or type(definition.cost) ~= "table" then
        return err("invalid_request", "building definition is unknown or has no valid cost")
    end

    return InventoryDomain.applyCost(profile, definition.cost)
end

return table.freeze({
    canAfford = canAfford,
    purchase = purchase,
})
