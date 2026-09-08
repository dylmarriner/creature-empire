local CreatureDefinitions = require("./CreatureDefinitions")
local BuildingDefinitions = require("../Buildings/BuildingDefinitions")

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

local function denseStringArrayLength(value: any): number?
    if type(value) ~= "table" then
        return nil
    end

    local count = 0
    for key, item in pairs(value) do
        if
            type(key) ~= "number"
            or key < 1
            or key % 1 ~= 0
            or type(item) ~= "string"
            or item == ""
        then
            return nil
        end
        count += 1
    end

    for index = 1, count do
        if type(value[index]) ~= "string" or value[index] == "" then
            return nil
        end
    end

    return count
end

local function validateExistingWorkers(profile: any, buildingInstanceId: string, workerIds: any)
    local workerCount = denseStringArrayLength(workerIds)
    if workerCount == nil then
        return nil, "building worker list is invalid"
    end

    local seen = {}
    for index = 1, workerCount do
        local workerId = workerIds[index]
        if seen[workerId] then
            return nil, "building worker list contains duplicate ids"
        end
        seen[workerId] = true

        local worker = profile.creatures[workerId]
        if type(worker) ~= "table" or worker.id ~= workerId then
            return nil, "building references a creature the profile does not own"
        end
        if
            type(worker.speciesId) ~= "string"
            or CreatureDefinitions.ById[worker.speciesId] == nil
        then
            return nil, "building references a creature with an invalid species"
        end
        if worker.assignedBuildingId ~= buildingInstanceId then
            return nil, "building worker assignment is inconsistent"
        end
    end

    return workerCount, nil
end

local function existingWorkersSupportWork(profile: any, workerIds: any, workerCount: number, workType: string)
    for index = 1, workerCount do
        local worker = profile.creatures[workerIds[index]]
        local workerDefinition = CreatureDefinitions.ById[worker.speciesId]
        if type(workerDefinition.workAffinity) ~= "table" then
            return false
        end

        local affinity = workerDefinition.workAffinity[workType]
        if not isFiniteNumber(affinity) or affinity <= 0 then
            return false
        end
    end

    return true
end

local function validate(profile: any, creatureInstanceId: any, buildingInstanceId: any)
    if
        type(profile) ~= "table"
        or type(profile.creatures) ~= "table"
        or type(profile.buildings) ~= "table"
        or type(creatureInstanceId) ~= "string"
        or creatureInstanceId == ""
        or type(buildingInstanceId) ~= "string"
        or buildingInstanceId == ""
    then
        return err("invalid_request", "assignment request is invalid")
    end

    local creature = profile.creatures[creatureInstanceId]
    if creature == nil then
        return err("creature_not_owned", "creature is not owned by this profile")
    end

    local building = profile.buildings[buildingInstanceId]
    if building == nil then
        return err("building_not_owned", "building is not owned by this profile")
    end

    if type(creature) ~= "table" or creature.id ~= creatureInstanceId then
        return err("invalid_request", "owned creature record is invalid")
    end

    local speciesId = creature.speciesId
    local speciesDefinition = if type(speciesId) == "string"
        then CreatureDefinitions.ById[speciesId]
        else nil
    if speciesDefinition == nil then
        return err("invalid_request", "owned creature species is invalid")
    end

    if type(building) ~= "table" or building.id ~= buildingInstanceId then
        return err("invalid_request", "owned building record is invalid")
    end

    local definitionId = building.definitionId
    local buildingDefinition = if type(definitionId) == "string"
        then BuildingDefinitions.ById[definitionId]
        else nil
    if buildingDefinition == nil then
        return err("invalid_request", "owned building definition is invalid")
    end

    if creature.assignedBuildingId ~= nil then
        if type(creature.assignedBuildingId) ~= "string" or creature.assignedBuildingId == "" then
            return err("invalid_request", "creature assignment state is invalid")
        end
        return err("creature_already_assigned", "creature is already assigned")
    end

    local workerCount, workerListError =
        validateExistingWorkers(profile, buildingInstanceId, building.assignedCreatureIds)
    if workerCount == nil then
        return err("invalid_request", workerListError or "building worker list is invalid")
    end

    for index = 1, workerCount do
        if building.assignedCreatureIds[index] == creatureInstanceId then
            return err("invalid_request", "creature assignment is inconsistent")
        end
    end

    local workType = buildingDefinition.workType
    if type(workType) ~= "string" or workType == "" then
        return err("incompatible_work", "building does not accept creature workers")
    end

    if
        not existingWorkersSupportWork(
            profile,
            building.assignedCreatureIds,
            workerCount,
            workType
        )
    then
        return err("invalid_request", "building contains a worker incompatible with its work type")
    end

    local maxWorkers = buildingDefinition.maxWorkers
    if not isNonNegativeInteger(maxWorkers) then
        return err("invalid_request", "building worker capacity is invalid")
    end
    if workerCount >= maxWorkers then
        return err("building_capacity_full", "building worker capacity is full")
    end

    if type(speciesDefinition.workAffinity) ~= "table" then
        return err("invalid_request", "creature work affinities are invalid")
    end

    local affinity = speciesDefinition.workAffinity[workType]
    if not isFiniteNumber(affinity) or affinity <= 0 then
        return err("incompatible_work", "creature is incompatible with this work type")
    end

    return ok(true)
end

return table.freeze({
    validate = validate,
})
