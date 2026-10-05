local ItemDefinitions = require("../Items/ItemDefinitions")
local CreatureDefinitions = require("../Creatures/CreatureDefinitions")
local BuildingDefinitions = require("../Buildings/BuildingDefinitions")
local GameConfig = require("../Config/GameConfig")
local ProfileSchemaV1 = require("./ProfileSchemaV1")

local CURRENT_VERSION = 2

local GENE_NAMES = table.freeze({ "vigor", "might", "focus" })

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

    local count = 0
    for index, item in pairs(value) do
        if
            type(index) ~= "number"
            or not isFiniteInteger(index)
            or index < 1
            or type(item) ~= "string"
        then
            return false
        end
        count += 1
    end

    for index = 1, count do
        if type(value[index]) ~= "string" then
            return false
        end
    end

    return true
end

-- Genes are exactly the three known keys, each an integer in [GENE_MIN, GENE_MAX].
local function validateGenes(genes: any): boolean
    if type(genes) ~= "table" then
        return false
    end

    for key in pairs(genes) do
        if table.find(GENE_NAMES, key) == nil then
            return false
        end
    end

    for _, name in ipairs(GENE_NAMES) do
        local value = genes[name]
        if
            not isFiniteInteger(value)
            or value < GameConfig.GENE_MIN
            or value > GameConfig.GENE_MAX
        then
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

    if
        type(creature.speciesId) ~= "string"
        or CreatureDefinitions.ById[creature.speciesId] == nil
    then
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

    if not validateGenes(creature.genes) then
        return false
    end

    if
        not isNonNegativeInteger(creature.generation) or not isNonNegativeInteger(creature.bornAt)
    then
        return false
    end

    if creature.lineage ~= nil then
        local lineage = creature.lineage
        if
            type(lineage) ~= "table"
            or type(lineage.speciesA) ~= "string"
            or type(lineage.speciesB) ~= "string"
        then
            return false
        end
        for key in pairs(lineage) do
            if key ~= "speciesA" and key ~= "speciesB" then
                return false
            end
        end
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

    if
        type(building.definitionId) ~= "string"
        or BuildingDefinitions.ById[building.definitionId] == nil
    then
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

-- A transfer payload is everything one party puts up: inventory items, coins and whole
-- creature records. Creatures held here are out of play: they are not in `profile.creatures`.
local function validatePayload(payload: any): boolean
    if type(payload) ~= "table" then
        return false
    end

    for key in pairs(payload) do
        if key ~= "items" and key ~= "coins" and key ~= "creatures" then
            return false
        end
    end

    if type(payload.items) ~= "table" or not isNonNegativeInteger(payload.coins) then
        return false
    end

    for itemId, quantity in pairs(payload.items) do
        if
            type(itemId) ~= "string"
            or ItemDefinitions.ById[itemId] == nil
            or not isFiniteInteger(quantity)
            or quantity < 1
        then
            return false
        end
    end

    if type(payload.creatures) ~= "table" then
        return false
    end

    for id, creature in pairs(payload.creatures) do
        if type(id) ~= "string" or not validateCreature(creature) or creature.id ~= id then
            return false
        end
        if creature.assignedBuildingId ~= nil then
            return false
        end
    end

    return true
end

-- One entry per transfer this profile has escrowed an offer for and not yet settled.
local function validateTransfers(transfers: any): boolean
    if type(transfers) ~= "table" then
        return false
    end

    for id, entry in pairs(transfers) do
        if
            type(id) ~= "string"
            or type(entry) ~= "table"
            or entry.id ~= id
            or not isNonNegativeInteger(entry.createdAt)
            or not validatePayload(entry.offer)
        then
            return false
        end
        for key in pairs(entry) do
            if key ~= "id" and key ~= "createdAt" and key ~= "offer" then
                return false
            end
        end
    end

    return true
end

-- Eggs and expeditions are owned by later systems, which validate their own fields. The
-- schema only guarantees each record is a table filed under its own id, so those systems can
-- add optional fields without another schema version.
local function validateRecordMap(records: any): boolean
    if type(records) ~= "table" then
        return false
    end

    for id, record in pairs(records) do
        if type(id) ~= "string" or type(record) ~= "table" or record.id ~= id then
            return false
        end
    end

    return true
end

local function validateCounterMap(counters: any): boolean
    if type(counters) ~= "table" then
        return false
    end

    for key, value in pairs(counters) do
        if type(key) ~= "string" or not isNonNegativeInteger(value) then
            return false
        end
    end

    return true
end

local function validateFlagMap(flags: any): boolean
    if type(flags) ~= "table" then
        return false
    end

    for key, value in pairs(flags) do
        if type(key) ~= "string" or value ~= true then
            return false
        end
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
        eggs = {},
        expeditions = {},
        transfers = {},
        purchases = {},
        passes = {},
        guildId = nil,
        stats = {},
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

    if not validateRecordMap(profile.eggs) then
        return false, "invalid egg record"
    end

    if not validateRecordMap(profile.expeditions) then
        return false, "invalid expedition record"
    end

    if not validateTransfers(profile.transfers) then
        return false, "invalid transfer record"
    end

    if not validateCounterMap(profile.purchases) then
        return false, "invalid purchase record"
    end

    if not validateFlagMap(profile.passes) then
        return false, "invalid pass record"
    end

    if profile.guildId ~= nil and (type(profile.guildId) ~= "string" or profile.guildId == "") then
        return false, "guildId must be a non-empty string"
    end

    if not validateCounterMap(profile.stats) then
        return false, "invalid stats record"
    end

    if not isNonNegativeInteger(profile.lastSeenAt) then
        return false, "lastSeenAt must be a finite non-negative integer"
    end

    return true
end

-- Upgrades a validated v1 profile to v2. Pure and deterministic: existing creatures get the
-- neutral genes and generation 0, and `bornAt` is the profile's last-seen time, so no player
-- is advantaged or disadvantaged by the upgrade. New maps start empty.
local function upgradeV1(profile: any): any
    local upgraded = deepCopy(profile)
    upgraded.schemaVersion = 2

    for _, creature in pairs(upgraded.creatures) do
        creature.genes = {
            vigor = GameConfig.NEUTRAL_GENE,
            might = GameConfig.NEUTRAL_GENE,
            focus = GameConfig.NEUTRAL_GENE,
        }
        creature.generation = 0
        creature.bornAt = upgraded.lastSeenAt
    end

    upgraded.eggs = {}
    upgraded.expeditions = {}
    upgraded.transfers = {}
    upgraded.purchases = {}
    upgraded.passes = {}
    upgraded.stats = {}

    return upgraded
end

-- Returns an independent, current-version copy of a stored profile, or (nil, reason). Each
-- supported version is verified by its own validator before any upgrade runs, so unknown or
-- malformed data is refused rather than guessed into shape. Running it on a current profile
-- is a validated copy, which makes migration idempotent.
local function migrate(profile: any)
    if type(profile) == "table" and profile.schemaVersion == ProfileSchemaV1.VERSION then
        local valid, reason = ProfileSchemaV1.validate(profile)
        if not valid then
            return nil, reason
        end

        local upgraded = upgradeV1(profile)
        local upgradedValid, upgradedReason = validate(upgraded)
        if not upgradedValid then
            return nil, upgradedReason
        end

        return upgraded
    end

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
