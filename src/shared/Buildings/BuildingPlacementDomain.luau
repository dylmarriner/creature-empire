local BuildingDefinitions = require("./BuildingDefinitions")
local GridMath = require("./GridMath")
local BuildingCostDomain = require("../Economy/BuildingCostDomain")
local GameConfig = require("../Config/GameConfig")

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

local function isPosition(value: any): boolean
    return type(value) == "table"
        and isFiniteNumber(value.x)
        and isFiniteNumber(value.y)
        and isFiniteNumber(value.z)
end

local function isRotation(value: any): boolean
    return value == 0 or value == 90 or value == 180 or value == 270
end

local function validateExistingOrigins(buildings: any, position: any): boolean
    for id, building in pairs(buildings) do
        if
            type(id) ~= "string"
            or type(building) ~= "table"
            or building.id ~= id
            or not isPosition(building.position)
        then
            return false
        end

        if
            building.position.x == position.x
            and building.position.y == position.y
            and building.position.z == position.z
        then
            return false
        end
    end

    return true
end

local function place(
    profile: any,
    definitionId: any,
    desiredPosition: any,
    rotation: any,
    generateId: any,
    now: any
)
    if
        type(profile) ~= "table"
        or type(profile.buildings) ~= "table"
        or type(definitionId) ~= "string"
        or BuildingDefinitions.ById[definitionId] == nil
        or not isPosition(desiredPosition)
        or type(generateId) ~= "function"
        or not isNonNegativeInteger(now)
    then
        return err("invalid_request", "building placement request is invalid")
    end

    if not isRotation(rotation) then
        return err("invalid_placement", "building rotation is invalid")
    end

    local snapped = GridMath.snapPosition(desiredPosition, GameConfig.BUILD_GRID_SIZE)
    if
        snapped.y ~= 0
        or math.abs(snapped.x) > GameConfig.PLOT_HALF_EXTENT
        or math.abs(snapped.z) > GameConfig.PLOT_HALF_EXTENT
    then
        return err("invalid_placement", "building position is outside the valid plot")
    end

    if not validateExistingOrigins(profile.buildings, snapped) then
        return err(
            "invalid_placement",
            "building origin is occupied or existing placement state is invalid"
        )
    end

    local instanceId = generateId()
    if type(instanceId) ~= "string" or instanceId == "" then
        return err("invalid_generated_id", "generated building id is invalid")
    end

    if profile.buildings[instanceId] ~= nil then
        return err("duplicate_building_instance", "generated building id already exists")
    end

    local purchase = BuildingCostDomain.purchase(profile, definitionId)
    if purchase.ok ~= true then
        return purchase
    end

    local building = {
        id = instanceId,
        definitionId = definitionId,
        level = 1,
        position = snapped,
        rotation = rotation,
        assignedCreatureIds = {},
        lastClaimedAt = now,
    }

    profile.buildings[instanceId] = building
    return ok(building)
end

return table.freeze({
    place = place,
})
