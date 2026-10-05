local ActionPipeline = require("../../src/shared/Gameplay/ActionPipeline")
local ActionSchemas = require("../../src/shared/Net/ActionSchemas")
local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local GameActions = require("../../src/shared/Gameplay/GameActions")
local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local Snapshot = require("../../src/shared/Gameplay/Snapshot")
local TableUtil = require("../../src/shared/Util/TableUtil")

local NOW = 50000

local function context(overrides: any?): any
    local result = {
        now = NOW,
        generateId = Expect.idSequence("id"),
        isFeatureEnabled = function(name: string)
            return name == "breeding"
        end,
        randomSeed = function()
            return 12345
        end,
    }
    for key, value in pairs(overrides or {}) do
        result[key] = value
    end
    return result
end

local function act(profile: any, actionName: string, payload: any, ctx: any): any
    return ActionPipeline.run(profile, function(draft)
        return GameActions.handlers[actionName](draft, payload, ctx)
    end)
end

local function run()
    -- Payload schemas.
    local valid, start =
        ActionSchemas.validate("StartBreeding", { creatureIdA = "c_1", creatureIdB = "c_2" })
    Expect.truthy(valid, "valid breeding payload")
    Expect.equal(start.creatureIdA, "c_1", "sanitized parent A")
    Expect.falsy(
        (ActionSchemas.validate("StartBreeding", { creatureIdA = "c_1" })),
        "missing parent rejected"
    )
    Expect.falsy(
        (
            ActionSchemas.validate(
                "StartBreeding",
                { creatureIdA = "c_1", creatureIdB = "c_2", seed = 5 }
            )
        ),
        "a client-supplied seed is rejected"
    )
    Expect.truthy((ActionSchemas.validate("HatchEgg", { eggId = "e_1" })), "valid hatch payload")
    Expect.falsy((ActionSchemas.validate("HatchEgg", { eggId = 5 })), "non-string egg id rejected")
    Expect.equal(ActionSchemas.scopeFor("StartBreeding"), "profile", "breeding mutates the profile")
    Expect.equal(ActionSchemas.scopeFor("HatchEgg"), "profile", "hatching mutates the profile")

    -- The den cannot be placed while the flag is off.
    local profile = Fixtures.profile(NOW - 100)
    profile.inventory.item_wood = 100
    profile.inventory.item_stone = 100
    profile.inventory.item_food = 100
    profile.currencies.coins = 1000
    Fixtures.addCreature(profile, "c_a", "creature_rockhorn", nil, 3)
    Fixtures.addCreature(profile, "c_b", "creature_embercub", nil, 3)

    local placePayload =
        { definitionId = "building_breeding_den", cellX = 0, cellZ = 0, rotation = 0 }
    local off = context({
        isFeatureEnabled = function()
            return false
        end,
    })
    local blocked = act(profile, "PlaceBuilding", placePayload, off)
    Expect.falsy(blocked.committed, "den not placed while the flag is off")
    Expect.equal(blocked.result.code, "not_unlocked", "refused as not unlocked")
    Expect.equal(
        act(profile, "PlaceBuilding", placePayload, {
            now = NOW,
            generateId = Expect.idSequence("id"),
        }).result.code,
        "not_unlocked",
        "a context with no flag support counts as off"
    )

    -- Ordinary buildings are unaffected by the flag.
    local mine = act(profile, "PlaceBuilding", {
        definitionId = "building_mine",
        cellX = 10,
        cellZ = 10,
        rotation = 0,
    }, off)
    Expect.truthy(mine.committed, "other buildings do not need a flag")

    -- With the flag on the den is placed and breeding works end to end.
    local placed = act(profile, "PlaceBuilding", placePayload, context())
    Expect.truthy(placed.committed, "den placed once the flag is on")
    profile = placed.profile

    Expect.equal(
        act(profile, "StartBreeding", { creatureIdA = "c_a", creatureIdB = "c_b" }, off).result.code,
        "not_unlocked",
        "breeding refused while the flag is off"
    )
    Expect.equal(
        act(profile, "StartBreeding", { creatureIdA = "c_a", creatureIdB = "c_b" }, {
            now = NOW,
            generateId = Expect.idSequence("id"),
            isFeatureEnabled = function()
                return true
            end,
        }).result.code,
        "internal_error",
        "breeding needs a server seed"
    )

    local ids = Expect.idSequence("e")
    local bred = act(
        profile,
        "StartBreeding",
        { creatureIdA = "c_a", creatureIdB = "c_b" },
        context({
            generateId = ids,
        })
    )
    Expect.truthy(bred.committed, "breeding committed")
    profile = bred.profile
    local egg = profile.eggs.e_1
    Expect.truthy(egg ~= nil, "egg uses the server-generated id")
    Expect.equal(egg.seed, 12345, "egg uses the server-chosen seed")

    -- The snapshot tells the client what is available and how many slots exist.
    local snapshot = Snapshot.build(profile, NOW, { breeding = true, trading = false })
    Expect.equal(snapshot.breedingSlots, 1, "snapshot reports breeding slots")
    Expect.equal(snapshot.features.breeding, true, "snapshot reports the flag")
    Expect.equal(snapshot.features.trading, false, "snapshot reports other flags")
    Expect.truthy(snapshot.profile.eggs.e_1 ~= nil, "snapshot carries eggs")
    Expect.equal(next(Snapshot.build(profile, NOW).features), nil, "no flags means none reported")

    -- Eggs survive a save and reload.
    local reloaded = assert(ProfileSchema.migrate(TableUtil.deepCopy(profile)))
    Expect.equal(reloaded.eggs.e_1.seed, 12345, "egg round-trips through migration")
    Expect.equal(reloaded.creatures.c_a.breedReadyAt, NOW + 1800, "cooldown round-trips")

    -- Hatching still works after the flag is switched off, so no egg is ever stranded.
    local early = act(profile, "HatchEgg", { eggId = "e_1" }, off)
    Expect.equal(early.result.code, "not_ready", "an egg is not ready at once")
    local later = context({
        now = egg.hatchesAt,
        isFeatureEnabled = function()
            return false
        end,
        generateId = Expect.idSequence("c"),
    })
    local hatched = act(profile, "HatchEgg", { eggId = "e_1" }, later)
    Expect.truthy(hatched.committed, "hatched with the flag off")
    Expect.truthy(hatched.profile.creatures.c_1 ~= nil, "the baby uses the server-generated id")
    Expect.equal(hatched.profile.eggs.e_1, nil, "egg consumed")
end

return run
