local GameConfig = require("../Config/GameConfig")
local NumberUtil = require("../Util/NumberUtil")

local function experienceToNextLevel(level: number): number
    return GameConfig.CREATURE_EXPERIENCE_PER_LEVEL * level
end

local function outputMultiplier(level: any): number
    if not NumberUtil.isPositiveInteger(level) then
        return 1
    end

    local clamped = math.min(level, GameConfig.MAX_CREATURE_LEVEL)
    return 1 + (clamped - 1) * GameConfig.CREATURE_LEVEL_OUTPUT_BONUS
end

-- Adds experience and applies level-ups. Returns the number of levels gained.
local function addExperience(creature: any, amount: number): number
    if
        type(creature) ~= "table"
        or not NumberUtil.isPositiveInteger(amount)
        or not NumberUtil.isPositiveInteger(creature.level)
        or not NumberUtil.isNonNegativeInteger(creature.experience)
    then
        return 0
    end

    if creature.level >= GameConfig.MAX_CREATURE_LEVEL then
        creature.experience = 0
        return 0
    end

    local gained = 0
    local experience = creature.experience + amount
    while creature.level < GameConfig.MAX_CREATURE_LEVEL do
        local required = experienceToNextLevel(creature.level)
        if experience < required then
            break
        end
        experience -= required
        creature.level += 1
        gained += 1
    end

    if creature.level >= GameConfig.MAX_CREATURE_LEVEL then
        experience = 0
    end

    creature.experience = experience
    return gained
end

return table.freeze({
    experienceToNextLevel = experienceToNextLevel,
    outputMultiplier = outputMultiplier,
    addExperience = addExperience,
})
