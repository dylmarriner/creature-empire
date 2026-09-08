local WorkAssignmentDomain = require("./WorkAssignmentDomain")
local ProductionDomain = require("../Economy/ProductionDomain")

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

local function findUniqueWorkerIndex(workerIds: any, creatureInstanceId: string): number?
    if type(workerIds) ~= "table" then
        return nil
    end

    local count = 0
    local foundIndex = nil
    for key, workerId in pairs(workerIds) do
        if
            type(key) ~= "number"
            or key < 1
            or key % 1 ~= 0
            or type(workerId) ~= "string"
            or workerId == ""
        then
            return nil
        end
        count += 1
        if workerId == creatureInstanceId then
            if foundIndex ~= nil then
                return nil
            end
            foundIndex = key
        end
    end

    for index = 1, count do
        if type(workerIds[index]) ~= "string" or workerIds[index] == "" then
            return nil
        end
    end

    return foundIndex
end

local function assign(profile: any, creatureInstanceId: any, buildingInstanceId: any, now: any)
    if not isNonNegativeInteger(now) then
        return err("invalid_request", "assignment timestamp is invalid")
    end

    local eligibility =
        WorkAssignmentDomain.validate(profile, creatureInstanceId, buildingInstanceId)
    if eligibility.ok ~= true then
        return eligibility
    end

    local settlement = ProductionDomain.settle(profile, buildingInstanceId, now)
    if settlement.ok ~= true then
        return settlement
    end

    local creature = profile.creatures[creatureInstanceId]
    local building = profile.buildings[buildingInstanceId]
    table.insert(building.assignedCreatureIds, creatureInstanceId)
    creature.assignedBuildingId = buildingInstanceId

    return ok(true)
end

local function unassign(profile: any, creatureInstanceId: any, now: any)
    if
        type(profile) ~= "table"
        or type(profile.creatures) ~= "table"
        or type(profile.buildings) ~= "table"
        or type(creatureInstanceId) ~= "string"
        or creatureInstanceId == ""
        or not isNonNegativeInteger(now)
    then
        return err("invalid_request", "unassignment request is invalid")
    end

    local creature = profile.creatures[creatureInstanceId]
    if creature == nil then
        return err("creature_not_owned", "creature is not owned by this profile")
    end
    if type(creature) ~= "table" or creature.id ~= creatureInstanceId then
        return err("invalid_request", "owned creature record is invalid")
    end

    local buildingInstanceId = creature.assignedBuildingId
    if type(buildingInstanceId) ~= "string" or buildingInstanceId == "" then
        return err("invalid_request", "creature is not assigned to a valid building")
    end

    local building = profile.buildings[buildingInstanceId]
    if building == nil then
        return err("building_not_owned", "assigned building is not owned by this profile")
    end
    if type(building) ~= "table" or building.id ~= buildingInstanceId then
        return err("invalid_request", "owned building record is invalid")
    end

    local workerIndex = findUniqueWorkerIndex(building.assignedCreatureIds, creatureInstanceId)
    if workerIndex == nil then
        return err("invalid_request", "creature/building assignment relationship is inconsistent")
    end

    local settlement = ProductionDomain.settle(profile, buildingInstanceId, now)
    if settlement.ok ~= true then
        return settlement
    end

    table.remove(building.assignedCreatureIds, workerIndex)
    creature.assignedBuildingId = nil
    return ok(true)
end

return table.freeze({
    assign = assign,
    unassign = unassign,
})
