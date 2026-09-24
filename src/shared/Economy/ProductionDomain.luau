local GameConfig = require("../Config/GameConfig")
local BuildingDefinitions = require("../Buildings/BuildingDefinitions")
local CreatureDefinitions = require("../Creatures/CreatureDefinitions")
local CreatureProgression = require("../Creatures/CreatureProgression")
local CapacityDomain = require("./CapacityDomain")
local InventoryDomain = require("./InventoryDomain")
local ProductionMath = require("./ProductionMath")
local NumberUtil = require("../Util/NumberUtil")
local TableUtil = require("../Util/TableUtil")

local EPSILON = 1e-9

local function ok(value: any)
    return { ok = true, value = value }
end

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

local function levelMultiplier(level: number): number
    local clamped = math.clamp(level, 1, GameConfig.MAX_BUILDING_LEVEL)
    return 1 + (clamped - 1) * GameConfig.BUILDING_LEVEL_OUTPUT_BONUS
end

local function isProductionDefinition(definition: any): boolean
    return definition ~= nil
        and definition.kind == "production"
        and type(definition.workType) == "string"
        and NumberUtil.isFiniteNumber(definition.cyclesPerMinute)
        and type(definition.outputs) == "table"
end

-- Sum of the affinity-weighted contribution of every consistently assigned worker.
local function workerMultiplier(profile: any, building: any, workType: string): number
    local total = 0
    if type(building.assignedCreatureIds) ~= "table" then
        return total
    end

    for _, creatureId in ipairs(building.assignedCreatureIds) do
        local creature = profile.creatures[creatureId]
        if type(creature) == "table" and creature.assignedBuildingId == building.id then
            local species = CreatureDefinitions.ById[creature.speciesId]
            local affinity = if species ~= nil then species.workAffinity[workType] else nil
            if NumberUtil.isFiniteNumber(affinity) and affinity > 0 then
                total += affinity * CreatureProgression.outputMultiplier(creature.level)
            end
        end
    end

    return total
end

local function cyclesPerMinute(profile: any, building: any): number
    if
        type(profile) ~= "table"
        or type(profile.creatures) ~= "table"
        or type(building) ~= "table"
    then
        return 0
    end

    local definition = BuildingDefinitions.ById[building.definitionId]
    if
        not isProductionDefinition(definition) or not NumberUtil.isPositiveInteger(building.level)
    then
        return 0
    end

    return definition.cyclesPerMinute
        * levelMultiplier(building.level)
        * workerMultiplier(profile, building, definition.workType)
end

local function emptySettlement(buildingId: string)
    return {
        buildingId = buildingId,
        cycles = 0,
        produced = {},
        consumed = {},
        limitedBy = nil :: string?,
    }
end

-- Settles elapsed production for one building at its current rate.
--
-- Time is only consumed for whole cycles actually produced, so frequent claims never lose
-- fractional progress. Elapsed time beyond the offline cap is discarded. When output is
-- limited by missing inputs or full storage, or the building has no workers, the building
-- is idle and its clock resets to `now` instead of banking time.
local function settle(profile: any, buildingId: any, now: number)
    if
        type(profile) ~= "table"
        or type(profile.buildings) ~= "table"
        or type(profile.creatures) ~= "table"
        or type(profile.inventory) ~= "table"
        or type(buildingId) ~= "string"
    then
        return err("invalid_request", "settlement request is invalid")
    end

    if not NumberUtil.isNonNegativeInteger(now) then
        return err("invalid_request", "settlement time is invalid")
    end

    local building = profile.buildings[buildingId]
    if type(building) ~= "table" or building.id ~= buildingId then
        return err("building_not_owned", "building is not owned by this profile")
    end

    local definition = BuildingDefinitions.ById[building.definitionId]
    if definition == nil then
        return err("invalid_request", "owned building definition is invalid")
    end

    local settlement = emptySettlement(buildingId)
    if not isProductionDefinition(definition) then
        return ok(settlement)
    end

    local lastClaimedAt = building.lastClaimedAt
    if not NumberUtil.isNonNegativeInteger(lastClaimedAt) or lastClaimedAt > now then
        building.lastClaimedAt = now
        return ok(settlement)
    end

    local rate = cyclesPerMinute(profile, building)
    if rate <= 0 then
        building.lastClaimedAt = now
        return ok(settlement)
    end

    local elapsed = ProductionMath.clampElapsedSeconds(
        now - lastClaimedAt,
        GameConfig.OFFLINE_PRODUCTION_CAP_SECONDS
    )
    local cycles = ProductionMath.calculateOutput(rate, 1, 1, 1, elapsed)
    local limitedBy: string? = nil

    for itemId, perCycle in pairs(definition.inputs) do
        local balance = profile.inventory[itemId]
        local available = if NumberUtil.isNonNegativeInteger(balance) then balance else 0
        local maxCycles = math.floor(available / perCycle)
        if maxCycles < cycles then
            cycles = maxCycles
            limitedBy = "input"
        end
    end

    for itemId, perCycle in pairs(definition.outputs) do
        local maxCycles = math.floor(CapacityDomain.storageSpace(profile, itemId) / perCycle)
        if maxCycles < cycles then
            cycles = maxCycles
            limitedBy = "storage"
        end
    end

    if limitedBy ~= nil then
        building.lastClaimedAt = now
    else
        local ratePerSecond = rate / 60
        local consumedSeconds = math.min(elapsed, math.ceil(cycles / ratePerSecond - EPSILON))
        building.lastClaimedAt = now - (elapsed - consumedSeconds)
    end

    settlement.limitedBy = limitedBy
    if cycles <= 0 then
        return ok(settlement)
    end

    for _, itemId in ipairs(TableUtil.sortedKeys(definition.inputs)) do
        local quantity = definition.inputs[itemId] * cycles
        local removed = InventoryDomain.remove(profile, itemId, quantity)
        if removed.ok ~= true then
            return removed
        end
        settlement.consumed[itemId] = quantity
    end

    for _, itemId in ipairs(TableUtil.sortedKeys(definition.outputs)) do
        local quantity = definition.outputs[itemId] * cycles
        local added = InventoryDomain.add(profile, itemId, quantity)
        if added.ok ~= true then
            return added
        end
        settlement.produced[itemId] = quantity
    end

    for _, creatureId in ipairs(building.assignedCreatureIds) do
        local creature = profile.creatures[creatureId]
        if type(creature) == "table" and creature.assignedBuildingId == buildingId then
            CreatureProgression.addExperience(creature, cycles)
        end
    end

    settlement.cycles = cycles
    return ok(settlement)
end

local function hasInputs(definition: any): boolean
    return definition ~= nil
        and type(definition.inputs) == "table"
        and next(definition.inputs) ~= nil
end

-- Settles every production building. Extractors settle before processors so freshly
-- mined ore is available to furnaces in the same claim.
local function claimAll(profile: any, now: number)
    if type(profile) ~= "table" or type(profile.buildings) ~= "table" then
        return err("invalid_request", "profile buildings are invalid")
    end

    local extractors = {}
    local processors = {}
    for _, buildingId in ipairs(TableUtil.sortedKeys(profile.buildings)) do
        local building = profile.buildings[buildingId]
        local definition = if type(building) == "table"
            then BuildingDefinitions.ById[building.definitionId]
            else nil
        if isProductionDefinition(definition) then
            if hasInputs(definition) then
                table.insert(processors, buildingId)
            else
                table.insert(extractors, buildingId)
            end
        end
    end

    local summary = {
        buildings = 0,
        cycles = 0,
        produced = {},
        consumed = {},
        storageLimited = false,
        inputLimited = false,
    }

    local function settleEach(buildingIds: { string })
        for _, buildingId in ipairs(buildingIds) do
            local result = settle(profile, buildingId, now)
            if result.ok ~= true then
                return result
            end

            local settlement = result.value
            summary.buildings += 1
            summary.cycles += settlement.cycles
            for itemId, quantity in pairs(settlement.produced) do
                summary.produced[itemId] = (summary.produced[itemId] or 0) + quantity
            end
            for itemId, quantity in pairs(settlement.consumed) do
                summary.consumed[itemId] = (summary.consumed[itemId] or 0) + quantity
            end
            if settlement.limitedBy == "storage" then
                summary.storageLimited = true
            elseif settlement.limitedBy == "input" then
                summary.inputLimited = true
            end
        end
        return nil
    end

    local failure = settleEach(extractors) or settleEach(processors)
    if failure ~= nil then
        return failure
    end

    if summary.buildings == 0 then
        return err("nothing_to_claim", "you have no production buildings")
    end

    return ok(summary)
end

return table.freeze({
    levelMultiplier = levelMultiplier,
    cyclesPerMinute = cyclesPerMinute,
    settle = settle,
    claimAll = claimAll,
})
