local ObjectiveDefinitions = require("./ObjectiveDefinitions")
local CapacityDomain = require("../Economy/CapacityDomain")
local CurrencyDomain = require("../Economy/CurrencyDomain")
local NumberUtil = require("../Util/NumberUtil")

local function isComplete(profile: any, objectiveId: string): boolean
    return type(profile.unlocks) == "table" and profile.unlocks[objectiveId] == true
end

-- Returns (current, target) progress for an objective's condition.
local function progress(profile: any, condition: any): (number, number)
    if type(profile) ~= "table" then
        return 0, 1
    end

    local kind = condition.kind
    if kind == "inventory" then
        local balance = if type(profile.inventory) == "table"
            then profile.inventory[condition.itemId]
            else nil
        local held = if NumberUtil.isNonNegativeInteger(balance) then balance else 0
        return math.min(held, condition.quantity), condition.quantity
    elseif kind == "creatures" then
        return math.min(CapacityDomain.creatureCount(profile), condition.quantity),
            condition.quantity
    end

    if type(profile.buildings) ~= "table" then
        return 0, 1
    end

    if kind == "building" or kind == "worker" then
        for _, building in pairs(profile.buildings) do
            if type(building) == "table" and building.definitionId == condition.definitionId then
                if
                    kind == "building"
                    or (
                        type(building.assignedCreatureIds) == "table"
                        and #building.assignedCreatureIds > 0
                    )
                then
                    return 1, 1
                end
            end
        end
        return 0, 1
    elseif kind == "buildingLevel" then
        local best = 0
        for _, building in pairs(profile.buildings) do
            if type(building) == "table" and NumberUtil.isPositiveInteger(building.level) then
                best = math.max(best, building.level)
            end
        end
        return math.min(best, condition.level), condition.level
    end

    return 0, 1
end

local function currentObjective(profile: any)
    for _, objective in ipairs(ObjectiveDefinitions.Ordered) do
        if not isComplete(profile, objective.id) then
            return objective
        end
    end
    return nil
end

-- Completes every satisfied objective in order, granting coin rewards, and stops at the
-- first unmet one. Returns the list of newly completed objective ids.
local function evaluate(profile: any): { string }
    local completed = {}
    if type(profile) ~= "table" or type(profile.unlocks) ~= "table" then
        return completed
    end

    for _, objective in ipairs(ObjectiveDefinitions.Ordered) do
        if not isComplete(profile, objective.id) then
            local current, target = progress(profile, objective.condition)
            if current < target then
                break
            end

            if objective.rewardCoins > 0 then
                local rewarded = CurrencyDomain.add(profile, "coins", objective.rewardCoins)
                if rewarded.ok ~= true then
                    break
                end
            end
            profile.unlocks[objective.id] = true
            table.insert(completed, objective.id)
        end
    end

    return completed
end

return table.freeze({
    progress = progress,
    currentObjective = currentObjective,
    evaluate = evaluate,
})
