-- Breeding: two idle creatures are paired in a Breeding Den, which lays an egg. The egg is a
-- stored record (parent snapshots, a seed and a hatch time) and the baby it hatches into is
-- computed from those by `GeneticsDomain.offspring`, so it is fixed when the egg is laid.
--
-- Rules, all checked before anything changes:
--   * a Breeding Den exists and has a free egg slot (one slot per den level),
--   * two different, owned, idle creatures at level 3 or higher, each off its breeding cooldown,
--   * the coins and food are paid. Cost grows with the older parent's generation.
-- Both parents keep working; they only go on cooldown. Hatching needs room in the habitats.
local CapacityDomain = require("../Economy/CapacityDomain")
local CreatureDefinitions = require("./CreatureDefinitions")
local CurrencyDomain = require("../Economy/CurrencyDomain")
local GameConfig = require("../Config/GameConfig")
local GeneticsDomain = require("./GeneticsDomain")
local InventoryDomain = require("../Economy/InventoryDomain")
local NumberUtil = require("../Util/NumberUtil")

local BreedingDomain = {}

local function ok(value: any)
    return { ok = true, value = value }
end

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

local function isSeed(value: any): boolean
    return NumberUtil.isNonNegativeInteger(value) and value < 2 ^ 32
end

-- What starting an egg with these parents costs: { coins, items }.
function BreedingDomain.costFor(parentA: any, parentB: any): any
    local generation = math.max(parentA.generation, parentB.generation)
    local scale = 1 + generation
    return {
        coins = GameConfig.BREEDING_COIN_COST_BASE * scale,
        items = { item_food = GameConfig.BREEDING_FOOD_COST_BASE * scale },
    }
end

local function eggCount(profile: any): number
    local count = 0
    for _ in pairs(profile.eggs) do
        count += 1
    end
    return count
end

-- Why `creature` cannot breed right now, or nil when it can. Also used by the client to list
-- usable parents, so the menu and the server agree.
local function ineligibleReason(creature: any, now: number): string?
    if creature.assignedBuildingId ~= nil then
        return "unassign it from its building first"
    end
    if creature.level < GameConfig.BREEDING_MIN_PARENT_LEVEL then
        return `it must be level {GameConfig.BREEDING_MIN_PARENT_LEVEL} to breed`
    end
    if creature.breedReadyAt ~= nil and creature.breedReadyAt > now then
        return "it is still resting from breeding"
    end
    return nil
end

BreedingDomain.parentIneligibleReason = ineligibleReason

-- Lays an egg from two creatures. `eggId` is a fresh id and `seed` an integer in [0, 2^32)
-- chosen by the server; the client never supplies either.
function BreedingDomain.start(
    profile: any,
    creatureIdA: any,
    creatureIdB: any,
    now: any,
    eggId: any,
    seed: any
)
    if type(profile) ~= "table" or type(profile.creatures) ~= "table" then
        return err("invalid_request", "profile is invalid")
    end
    if type(profile.eggs) ~= "table" then
        return err("invalid_request", "profile eggs are invalid")
    end
    if
        type(creatureIdA) ~= "string"
        or type(creatureIdB) ~= "string"
        or not NumberUtil.isNonNegativeInteger(now)
        or type(eggId) ~= "string"
        or eggId == ""
        or not isSeed(seed)
    then
        return err("invalid_request", "breeding request is invalid")
    end
    if creatureIdA == creatureIdB then
        return err("invalid_request", "pick two different creatures")
    end
    if profile.eggs[eggId] ~= nil then
        return err("invalid_request", "egg id already exists")
    end

    local slots = CapacityDomain.breedingSlots(profile)
    if slots == 0 then
        return err("not_unlocked", "build a Breeding Den to breed creatures")
    end
    if eggCount(profile) >= slots then
        return err(
            "breeding_slots_full",
            "every egg slot is in use; hatch an egg or upgrade the den"
        )
    end

    local first = profile.creatures[creatureIdA]
    local second = profile.creatures[creatureIdB]
    if type(first) ~= "table" or type(second) ~= "table" then
        return err("creature_not_owned", "you do not own both creatures")
    end
    for _, creature in ipairs({ first, second }) do
        local species = CreatureDefinitions.ById[creature.speciesId]
        local reason = ineligibleReason(creature, now)
        if species == nil or type(creature.genes) ~= "table" then
            return err("invalid_request", "owned creature record is invalid")
        end
        if reason ~= nil then
            return err("not_ready", `{species.displayName}: {reason}`)
        end
    end

    local cost = BreedingDomain.costFor(first, second)
    if
        profile.currencies.coins < cost.coins or not InventoryDomain.canAfford(profile, cost.items)
    then
        return err("insufficient_resources", "not enough coins or food to breed")
    end

    local paid = InventoryDomain.applyCost(profile, cost.items)
    if paid.ok ~= true then
        return paid
    end
    local spent = CurrencyDomain.spend(profile, "coins", cost.coins)
    if spent.ok ~= true then
        return spent
    end

    local parentA = GeneticsDomain.snapshot(first)
    local parentB = GeneticsDomain.snapshot(second)
    local egg = {
        id = eggId,
        parentA = parentA,
        parentB = parentB,
        seed = seed,
        createdAt = now,
        hatchesAt = now + GeneticsDomain.hatchSeconds(parentA, parentB),
    }
    profile.eggs[eggId] = egg

    local restUntil = now + GameConfig.BREEDING_COOLDOWN_SECONDS
    first.breedReadyAt = restUntil
    second.breedReadyAt = restUntil

    return ok({ egg = egg, cost = cost })
end

local function validEgg(egg: any, eggId: string): boolean
    return type(egg) == "table"
        and egg.id == eggId
        and isSeed(egg.seed)
        and NumberUtil.isNonNegativeInteger(egg.createdAt)
        and NumberUtil.isNonNegativeInteger(egg.hatchesAt)
        and GeneticsDomain.validSnapshot(egg.parentA)
        and GeneticsDomain.validSnapshot(egg.parentB)
end

-- Hatches a ready egg into a new creature. `creatureId` is a fresh id from the server.
function BreedingDomain.hatch(profile: any, eggId: any, now: any, creatureId: any)
    if type(profile) ~= "table" or type(profile.eggs) ~= "table" then
        return err("invalid_request", "profile is invalid")
    end
    if
        type(eggId) ~= "string"
        or not NumberUtil.isNonNegativeInteger(now)
        or type(creatureId) ~= "string"
        or creatureId == ""
    then
        return err("invalid_request", "hatch request is invalid")
    end

    local egg = profile.eggs[eggId]
    if egg == nil then
        return err("egg_not_found", "that egg does not exist")
    end
    if not validEgg(egg, eggId) then
        return err("invalid_request", "that egg is damaged")
    end
    if now < egg.hatchesAt then
        return err("not_ready", "the egg has not hatched yet")
    end
    if profile.creatures[creatureId] ~= nil then
        return err("duplicate_creature_instance", "generated creature id already exists")
    end
    if not CapacityDomain.hasCreatureSpace(profile) then
        return err("creature_capacity_full", "your habitats are full")
    end

    local baby = GeneticsDomain.offspring(egg.parentA, egg.parentB, egg.seed)
    local creature = {
        id = creatureId,
        speciesId = baby.speciesId,
        level = 1,
        experience = 0,
        traits = {},
        mutationId = baby.mutationId,
        assignedBuildingId = nil,
        genes = baby.genes,
        generation = baby.generation,
        lineage = baby.lineage,
        bornAt = now,
    }

    profile.creatures[creatureId] = creature
    profile.eggs[eggId] = nil
    return ok({ creature = creature, eggId = eggId })
end

return table.freeze(BreedingDomain)
