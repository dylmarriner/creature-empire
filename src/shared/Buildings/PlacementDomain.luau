local GameConfig = require("../Config/GameConfig")
local BuildingDefinitions = require("./BuildingDefinitions")
local InventoryDomain = require("../Economy/InventoryDomain")
local ProductionDomain = require("../Economy/ProductionDomain")
local NumberUtil = require("../Util/NumberUtil")
local TableUtil = require("../Util/TableUtil")

local function ok(value: any)
    return { ok = true, value = value }
end

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

local function isValidRotation(rotation: any): boolean
    for _, valid in ipairs(GameConfig.VALID_ROTATIONS) do
        if rotation == valid then
            return true
        end
    end
    return false
end

-- Footprint in grid cells after rotation. Quarter turns swap the axes.
local function footprintFor(definition: any, rotation: number): (number, number)
    local footprint = definition.footprint
    if rotation == 90 or rotation == 270 then
        return footprint.z, footprint.x
    end
    return footprint.x, footprint.z
end

local function rectsOverlap(
    ax: number,
    az: number,
    aw: number,
    ad: number,
    bx: number,
    bz: number,
    bw: number,
    bd: number
): boolean
    return ax < bx + bw and bx < ax + aw and az < bz + bd and bz < az + ad
end

local function countOfDefinition(profile: any, definitionId: string): number
    local count = 0
    for _, building in pairs(profile.buildings) do
        if type(building) == "table" and building.definitionId == definitionId then
            count += 1
        end
    end
    return count
end

-- Validates a placement without mutating the profile. Shared by the server (authoritative)
-- and the client (placement preview).
local function checkPlacement(
    profile: any,
    definitionId: any,
    cellX: any,
    cellZ: any,
    rotation: any,
    ignoreBuildingId: string?
)
    if type(profile) ~= "table" or type(profile.buildings) ~= "table" then
        return err("invalid_request", "profile buildings are invalid")
    end

    local definition = if type(definitionId) == "string"
        then BuildingDefinitions.ById[definitionId]
        else nil
    if definition == nil then
        return err("invalid_request", "building definition is unknown")
    end

    if not isValidRotation(rotation) then
        return err("invalid_placement", "rotation must be a quarter turn")
    end

    if not NumberUtil.isInteger(cellX) or not NumberUtil.isInteger(cellZ) then
        return err("invalid_placement", "placement cell must be an integer grid cell")
    end

    local width, depth = footprintFor(definition, rotation)
    local plotSize = GameConfig.PLOT_SIZE_CELLS
    if cellX < 0 or cellZ < 0 or cellX + width > plotSize or cellZ + depth > plotSize then
        return err("invalid_placement", "building must fit inside your plot")
    end

    for otherId, other in pairs(profile.buildings) do
        if otherId ~= ignoreBuildingId and type(other) == "table" then
            local otherDefinition = BuildingDefinitions.ById[other.definitionId]
            if otherDefinition ~= nil and type(other.position) == "table" then
                local otherWidth, otherDepth = footprintFor(
                    otherDefinition,
                    if isValidRotation(other.rotation) then other.rotation else 0
                )
                if
                    rectsOverlap(
                        cellX,
                        cellZ,
                        width,
                        depth,
                        other.position.x,
                        other.position.z,
                        otherWidth,
                        otherDepth
                    )
                then
                    return err("invalid_placement", "building overlaps another building")
                end
            end
        end
    end

    return ok(definition)
end

local function place(
    profile: any,
    definitionId: any,
    cellX: any,
    cellZ: any,
    rotation: any,
    now: number,
    generateId: any
)
    local check = checkPlacement(profile, definitionId, cellX, cellZ, rotation, nil)
    if check.ok ~= true then
        return check
    end
    local definition = check.value

    if countOfDefinition(profile, definition.id) >= definition.maxCount then
        return err(
            "building_limit_reached",
            `you can own at most {definition.maxCount} {definition.displayName}`
        )
    end

    if not NumberUtil.isNonNegativeInteger(now) then
        return err("invalid_request", "placement time is invalid")
    end

    if not InventoryDomain.canAfford(profile, definition.cost) then
        return err("insufficient_resources", "not enough resources to build")
    end

    if type(generateId) ~= "function" then
        return err("invalid_request", "id generator is required")
    end

    local buildingId = generateId()
    if type(buildingId) ~= "string" or buildingId == "" then
        return err("invalid_generated_id", "generated building id is invalid")
    end
    if profile.buildings[buildingId] ~= nil then
        return err("invalid_generated_id", "generated building id already exists")
    end

    local paid = InventoryDomain.applyCost(profile, definition.cost)
    if paid.ok ~= true then
        return paid
    end

    local building = {
        id = buildingId,
        definitionId = definition.id,
        level = 1,
        position = { x = cellX, y = 0, z = cellZ },
        rotation = rotation,
        assignedCreatureIds = {},
        lastClaimedAt = now,
    }
    profile.buildings[buildingId] = building

    return ok(building)
end

-- Removes a building: settles its production, releases its workers and refunds part of
-- its base cost. Upgrade spending is not refunded.
local function remove(profile: any, buildingId: any, now: number)
    if type(profile) ~= "table" or type(profile.buildings) ~= "table" then
        return err("invalid_request", "profile buildings are invalid")
    end

    local building = if type(buildingId) == "string" then profile.buildings[buildingId] else nil
    if type(building) ~= "table" then
        return err("building_not_owned", "building is not owned by this profile")
    end

    local definition = BuildingDefinitions.ById[building.definitionId]
    if definition == nil then
        return err("invalid_request", "owned building definition is invalid")
    end

    local settled = ProductionDomain.settle(profile, buildingId, now)
    if settled.ok ~= true then
        return settled
    end

    if type(building.assignedCreatureIds) == "table" then
        for _, creatureId in ipairs(building.assignedCreatureIds) do
            local creature = profile.creatures[creatureId]
            if type(creature) == "table" and creature.assignedBuildingId == buildingId then
                creature.assignedBuildingId = nil
            end
        end
    end

    profile.buildings[buildingId] = nil

    local refund = {}
    for _, itemId in ipairs(TableUtil.sortedKeys(definition.cost)) do
        local quantity = math.floor(definition.cost[itemId] * GameConfig.REMOVE_REFUND_RATIO)
        if quantity > 0 then
            local added = InventoryDomain.add(profile, itemId, quantity)
            if added.ok ~= true then
                return added
            end
            refund[itemId] = quantity
        end
    end

    return ok({ refund = refund, settlement = settled.value })
end

return table.freeze({
    footprintFor = footprintFor,
    isValidRotation = isValidRotation,
    countOfDefinition = countOfDefinition,
    checkPlacement = checkPlacement,
    place = place,
    remove = remove,
})
