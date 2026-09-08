local BuildingDefinitions = require("../Buildings/BuildingDefinitions")
local CreatureDefinitions = require("../Creatures/CreatureDefinitions")
local ItemDefinitions = require("../Items/ItemDefinitions")
local GameConfig = require("../Config/GameConfig")
local InventoryDomain = require("./InventoryDomain")
local ProductionMath = require("./ProductionMath")

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

local function inventoryBalance(inventory: any, itemId: string): number?
    local value = inventory[itemId]
    if value == nil then
        return 0
    end
    if not isNonNegativeInteger(value) then
        return nil
    end
    return value
end

local function preview(profile: any, buildingInstanceId: any, now: any)
    if
        type(profile) ~= "table"
        or type(profile.buildings) ~= "table"
        or type(profile.creatures) ~= "table"
        or type(profile.inventory) ~= "table"
        or type(buildingInstanceId) ~= "string"
        or buildingInstanceId == ""
        or not isNonNegativeInteger(now)
    then
        return err("invalid_request", "production request is invalid")
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
    if definition == nil or definition.kind ~= "production" then
        return err("invalid_request", "building is not a valid production building")
    end

    if not isFiniteNumber(definition.baseRatePerMinute) or definition.baseRatePerMinute <= 0 then
        return err("invalid_request", "building production rate is invalid")
    end
    if
        type(definition.outputItemId) ~= "string"
        or ItemDefinitions.ById[definition.outputItemId] == nil
    then
        return err("invalid_request", "building output item is invalid")
    end
    if type(definition.workType) ~= "string" or definition.workType == "" then
        return err("invalid_request", "building work type is invalid")
    end
    if type(definition.levelMultipliers) ~= "table" or not isPositiveInteger(building.level) then
        return err("invalid_request", "building production level is invalid")
    end

    local buildingMultiplier = definition.levelMultipliers[building.level]
    if not isFiniteNumber(buildingMultiplier) or buildingMultiplier <= 0 then
        return err("invalid_request", "building level multiplier is invalid")
    end
    if not isNonNegativeInteger(building.lastClaimedAt) or now < building.lastClaimedAt then
        return err("invalid_request", "production timestamp is invalid")
    end

    local workerCount = denseStringArrayLength(building.assignedCreatureIds)
    if workerCount == nil then
        return err("invalid_request", "building worker list is invalid")
    end
    if not isNonNegativeInteger(definition.maxWorkers) or workerCount > definition.maxWorkers then
        return err("invalid_request", "building worker capacity state is invalid")
    end

    local seen = {}
    local workerMultiplier = 0
    for index = 1, workerCount do
        local workerId = building.assignedCreatureIds[index]
        if seen[workerId] then
            return err("invalid_request", "building worker list contains duplicate ids")
        end
        seen[workerId] = true

        local worker = profile.creatures[workerId]
        if type(worker) ~= "table" or worker.id ~= workerId then
            return err("invalid_request", "building references an invalid owned creature")
        end
        if worker.assignedBuildingId ~= buildingInstanceId then
            return err("invalid_request", "building worker relationship is inconsistent")
        end

        local speciesId = worker.speciesId
        local species = if type(speciesId) == "string"
            then CreatureDefinitions.ById[speciesId]
            else nil
        if species == nil or type(species.workAffinity) ~= "table" then
            return err("invalid_request", "building worker species is invalid")
        end

        local affinity = species.workAffinity[definition.workType]
        if not isFiniteNumber(affinity) or affinity <= 0 then
            return err("invalid_request", "building worker affinity is invalid")
        end
        workerMultiplier += affinity
    end

    local elapsedSeconds = now - building.lastClaimedAt
    local clampedElapsedSeconds = ProductionMath.clampElapsedSeconds(
        elapsedSeconds,
        GameConfig.OFFLINE_PRODUCTION_CAP_SECONDS
    )
    local rawOutput = ProductionMath.calculateOutput(
        definition.baseRatePerMinute,
        buildingMultiplier,
        workerMultiplier,
        1,
        clampedElapsedSeconds
    )

    local inputItemId = nil
    local inputQuantity = 0
    local outputQuantity = rawOutput
    if definition.inputItemId ~= nil or definition.inputPerOutput ~= nil then
        if
            type(definition.inputItemId) ~= "string"
            or ItemDefinitions.ById[definition.inputItemId] == nil
            or not isPositiveInteger(definition.inputPerOutput)
        then
            return err("invalid_request", "building production input is invalid")
        end

        local availableInput = inventoryBalance(profile.inventory, definition.inputItemId)
        if availableInput == nil then
            return err("invalid_request", "production input balance is invalid")
        end

        local inputLimitedOutput = math.floor(availableInput / definition.inputPerOutput)
        outputQuantity = math.min(rawOutput, inputLimitedOutput)
        inputItemId = definition.inputItemId
        inputQuantity = outputQuantity * definition.inputPerOutput
    end

    return ok({
        outputItemId = definition.outputItemId,
        outputQuantity = outputQuantity,
        inputItemId = inputItemId,
        inputQuantity = inputQuantity,
        elapsedSeconds = elapsedSeconds,
        clampedElapsedSeconds = clampedElapsedSeconds,
    })
end

local function applyPreview(profile: any, buildingInstanceId: string, now: number, allowZero: boolean)
    local result = preview(profile, buildingInstanceId, now)
    if result.ok ~= true then
        return result
    end

    local value = result.value
    if value.outputQuantity <= 0 then
        if not allowZero then
            return err("nothing_to_claim", "production has no whole-unit output to claim")
        end
        profile.buildings[buildingInstanceId].lastClaimedAt = now
        return result
    end

    local removals = {}
    if value.inputItemId ~= nil then
        removals[value.inputItemId] = value.inputQuantity
    end
    local additions = {
        [value.outputItemId] = value.outputQuantity,
    }

    local transaction = InventoryDomain.applyTransaction(profile, removals, additions)
    if transaction.ok ~= true then
        return transaction
    end

    profile.buildings[buildingInstanceId].lastClaimedAt = now
    return result
end

local function claim(profile: any, buildingInstanceId: any, now: any)
    if type(buildingInstanceId) ~= "string" or not isNonNegativeInteger(now) then
        return err("invalid_request", "production claim request is invalid")
    end
    return applyPreview(profile, buildingInstanceId, now, false)
end

local function settle(profile: any, buildingInstanceId: any, now: any)
    if type(buildingInstanceId) ~= "string" or not isNonNegativeInteger(now) then
        return err("invalid_request", "production settlement request is invalid")
    end
    return applyPreview(profile, buildingInstanceId, now, true)
end

return table.freeze({
    preview = preview,
    claim = claim,
    settle = settle,
})
