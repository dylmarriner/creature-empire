local ItemDefinitions = require("../Items/ItemDefinitions")

local CURRENT_VERSION = 1

local function isFiniteInteger(value: any): boolean
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value % 1 == 0
end

local function isNonNegativeInteger(value: any): boolean
    return isFiniteInteger(value) and value >= 0
end

local function isStringArray(value: any): boolean
    if type(value) ~= "table" then
        return false
    end

    for index, item in ipairs(value) do
        if type(index) ~= "number" or type(item) ~= "string" then
            return false
        end
    end

    return true
end

local function validateCreature(creature: any): boolean
    if type(creature) ~= "table" then
        return false
    end

    if type(creature.id) ~= "string" or creature.id == "" then
        return false
    end

    if type(creature.speciesId) ~= "string" or creature.speciesId == "" then
        return false
    end

    if not isNonNegativeInteger(creature.level) or creature.level < 1 then
        return false
    end

    if not isNonNegativeInteger(creature.experience) then
        return false
    end

    if not isStringArray(creature.traits) then
        return false
    end

    if creature.mutationId ~= nil and type(creature.mutationId) ~= "string" then
        return false
    end

    if creature.assignedBuildingId ~= nil and type(creature.assignedBuildingId) ~= "string" then
        return false
    end

    return true
end

local function validatePosition(position: any): boolean
    return type(position) == "table"
        and isFiniteInteger(position.x)
        and isFiniteInteger(position.y)
        and isFiniteInteger(position.z)
end

local function validateBuilding(building: any): boolean
    if type(building) ~= "table" then
        return false
    end

    if type(building.id) ~= "string" or building.id == "" then
        return false
    end

    if type(building.definitionId) ~= "string" or building.definitionId == "" then
        return false
    end

    if not isNonNegativeInteger(building.level) or building.level < 1 then
        return false
    end

    if not validatePosition(building.position) then
        return false
    end

    if not isFiniteInteger(building.rotation) then
        return false
    end

    if not isStringArray(building.assignedCreatureIds) then
        return false
    end

    if not isNonNegativeInteger(building.lastClaimedAt) then
        return false
    end

    return true
end

local function deepCopy(value: any): any
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[deepCopy(key)] = deepCopy(child)
    end

    return copy
end

local function createDefault(now: number)
    assert(isNonNegativeInteger(now), "now must be a finite non-negative integer")

    return {
        schemaVersion = CURRENT_VERSION,
        currencies = {
            coins = 0,
            gems = 0,
        },
        inventory = {},
        creatures = {},
        buildings = {},
        unlocks = {},
        lastSeenAt = now,
    }
end

local function validate(profile: any): (boolean, string?)
    if type(profile) ~= "table" then
        return false, "profile must be a table"
    end

    if profile.schemaVersion ~= CURRENT_VERSION then
        return false, "unsupported schema version"
    end

    if type(profile.currencies) ~= "table" then
        return false, "currencies must be a table"
    end

    if
        not isNonNegativeInteger(profile.currencies.coins)
        or not isNonNegativeInteger(profile.currencies.gems)
    then
        return false, "currency balances must be finite non-negative integers"
    end

    for currencyId in pairs(profile.currencies) do
        if currencyId ~= "coins" and currencyId ~= "gems" then
            return false, "unknown currency id"
        end
    end

    if type(profile.inventory) ~= "table" then
        return false, "inventory must be a table"
    end

    for itemId, quantity in pairs(profile.inventory) do
        if type(itemId) ~= "string" or ItemDefinitions.ById[itemId] == nil then
            return false, "unknown inventory item"
        end
        if not isNonNegativeInteger(quantity) then
            return false, "inventory quantities must be finite non-negative integers"
        end
    end

    if type(profile.creatures) ~= "table" then
        return false, "creatures must be a table"
    end

    for id, creature in pairs(profile.creatures) do
        if type(id) ~= "string" or not validateCreature(creature) or creature.id ~= id then
            return false, "invalid creature record"
        end
    end

    if type(profile.buildings) ~= "table" then
        return false, "buildings must be a table"
    end

    for id, building in pairs(profile.buildings) do
        if type(id) ~= "string" or not validateBuilding(building) or building.id ~= id then
            return false, "invalid building record"
        end
    end

    if type(profile.unlocks) ~= "table" then
        return false, "unlocks must be a table"
    end

    for unlockId, unlocked in pairs(profile.unlocks) do
        if type(unlockId) ~= "string" or type(unlocked) ~= "boolean" then
            return false, "invalid unlock record"
        end
    end

    if not isNonNegativeInteger(profile.lastSeenAt) then
        return false, "lastSeenAt must be a finite non-negative integer"
    end

    return true
end

local function migrate(profile: any)
    local valid, reason = validate(profile)
    if not valid then
        return nil, reason
    end

    return deepCopy(profile)
end

return table.freeze({
    CURRENT_VERSION = CURRENT_VERSION,
    createDefault = createDefault,
    validate = validate,
    migrate = migrate,
})
