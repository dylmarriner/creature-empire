local BreedingDomain = require("../../src/shared/Creatures/BreedingDomain")
local CapacityDomain = require("../../src/shared/Economy/CapacityDomain")
local CreatureDefinitions = require("../../src/shared/Creatures/CreatureDefinitions")
local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local GameConfig = require("../../src/shared/Config/GameConfig")
local GeneticsDomain = require("../../src/shared/Creatures/GeneticsDomain")
local MutationDefinitions = require("../../src/shared/Creatures/MutationDefinitions")
local ProductionDomain = require("../../src/shared/Economy/ProductionDomain")
local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local TableUtil = require("../../src/shared/Util/TableUtil")

local NOW = 10000

local function parent(
    speciesId: string,
    vigor: number?,
    might: number?,
    focus: number?,
    generation: number?
)
    return {
        speciesId = speciesId,
        generation = generation or 0,
        genes = { vigor = vigor or 16, might = might or 16, focus = focus or 16 },
    }
end

local ROCKHORN = "creature_rockhorn"
local EMBERCUB = "creature_embercub"

local function genetics()
    -- Determinism: same parents and seed always give the same baby.
    local a = parent(ROCKHORN, 10, 20, 30)
    local b = parent(EMBERCUB, 1, 2, 3)
    local first = GeneticsDomain.offspring(a, b, 777)
    local second = GeneticsDomain.offspring(a, b, 777)
    Expect.equal(first.speciesId, second.speciesId, "same seed, same species")
    Expect.equal(first.genes.vigor, second.genes.vigor, "same seed, same vigor")
    Expect.equal(first.genes.might, second.genes.might, "same seed, same might")
    Expect.equal(first.genes.focus, second.genes.focus, "same seed, same focus")
    Expect.equal(first.mutationId, second.mutationId, "same seed, same mutation")

    -- Over many seeds.
    local hybrids = 0
    local mutations = 0
    local trials = 6000
    local hybridId = CreatureDefinitions.hybridFor(ROCKHORN, EMBERCUB)
    local seenParents = {}
    for seed = 1, trials do
        local baby = GeneticsDomain.offspring(a, b, seed)
        Expect.truthy(
            baby.speciesId == ROCKHORN or baby.speciesId == EMBERCUB or baby.speciesId == hybridId,
            "baby is a parent species or the pair's hybrid"
        )
        seenParents[baby.speciesId] = true
        if baby.speciesId == hybridId then
            hybrids += 1
        end
        if baby.mutationId ~= nil then
            mutations += 1
            Expect.truthy(MutationDefinitions.ById[baby.mutationId] ~= nil, "known mutation")
        end
        for _, name in ipairs(GeneticsDomain.GENE_NAMES) do
            Expect.truthy(
                baby.genes[name] >= GameConfig.GENE_MIN and baby.genes[name] <= GameConfig.GENE_MAX,
                `{name} stays in range`
            )
            Expect.equal(baby.genes[name] % 1, 0, `{name} is an integer`)
        end
        Expect.equal(baby.generation, 1, "child of generation 0 parents is generation 1")
        Expect.equal(baby.lineage.speciesA, ROCKHORN, "lineage records parent A")
        Expect.equal(baby.lineage.speciesB, EMBERCUB, "lineage records parent B")
    end
    local hybridRate = hybrids / trials
    Expect.near(hybridRate, GameConfig.BREEDING_HYBRID_CHANCE, 0.03, "hybrid rate")
    Expect.near(mutations / trials, GameConfig.BREEDING_MUTATION_CHANCE, 0.012, "mutation rate")
    Expect.truthy(
        seenParents[ROCKHORN] and seenParents[EMBERCUB],
        "either parent's species can win"
    )

    -- Without a mutation, each gene is one parent's value within the drift.
    for seed = 1, 500 do
        local baby = GeneticsDomain.offspring(a, b, seed)
        if baby.mutationId == nil then
            for _, name in ipairs(GeneticsDomain.GENE_NAMES) do
                local nearA = math.abs(baby.genes[name] - a.genes[name])
                    <= GameConfig.BREEDING_GENE_DRIFT
                local nearB = math.abs(baby.genes[name] - b.genes[name])
                    <= GameConfig.BREEDING_GENE_DRIFT
                Expect.truthy(nearA or nearB, `{name} comes from a parent`)
            end
        end
    end

    -- Same species and hybrid parents never produce a new hybrid.
    for seed = 1, 500 do
        Expect.equal(
            GeneticsDomain.offspring(parent(ROCKHORN), parent(ROCKHORN), seed).speciesId,
            ROCKHORN,
            "same species breeds true"
        )
        local magmaback = "creature_magmaback"
        local baby = GeneticsDomain.offspring(parent(magmaback), parent(ROCKHORN), seed)
        Expect.truthy(
            baby.speciesId == magmaback or baby.speciesId == ROCKHORN,
            "a hybrid parent yields no further hybrid"
        )
    end

    -- Generation and clamping.
    Expect.equal(
        GeneticsDomain.offspring(parent(ROCKHORN, 16, 16, 16, 4), parent(EMBERCUB), 5).generation,
        5,
        "generation is the older parent's plus one"
    )
    Expect.equal(
        GeneticsDomain.offspring(
            parent(ROCKHORN, 16, 16, 16, GameConfig.BREEDING_MAX_GENERATION),
            parent(EMBERCUB),
            5
        ).generation,
        GameConfig.BREEDING_MAX_GENERATION,
        "generation is capped"
    )
    for seed = 1, 300 do
        local top = GeneticsDomain.offspring(
            parent(ROCKHORN, 31, 31, 31),
            parent(EMBERCUB, 31, 31, 31),
            seed
        )
        local bottom =
            GeneticsDomain.offspring(parent(ROCKHORN, 0, 0, 0), parent(EMBERCUB, 0, 0, 0), seed)
        for _, name in ipairs(GeneticsDomain.GENE_NAMES) do
            Expect.truthy(top.genes[name] <= 31, "genes clamp at the top")
            Expect.truthy(bottom.genes[name] >= 0, "genes clamp at the bottom")
        end
    end

    -- Every base pair can produce its hybrid.
    for index, firstId in ipairs(CreatureDefinitions.WildIds) do
        for second = index + 1, #CreatureDefinitions.WildIds do
            local secondId = CreatureDefinitions.WildIds[second]
            local wanted = CreatureDefinitions.hybridFor(firstId, secondId)
            local found = false
            for seed = 1, 300 do
                if
                    GeneticsDomain.offspring(parent(firstId), parent(secondId), seed).speciesId
                    == wanted
                then
                    found = true
                    break
                end
            end
            Expect.truthy(found, `{firstId} + {secondId} can produce {wanted}`)
        end
    end

    -- Mutations trade strengths: zero-sum, with something gained and something lost.
    for _, id in ipairs(MutationDefinitions.Ids) do
        local shift = MutationDefinitions.ById[id].geneShift
        Expect.equal(shift.vigor + shift.might + shift.focus, 0, `{id} is zero-sum`)
        local up, down = false, false
        for _, name in ipairs(GeneticsDomain.GENE_NAMES) do
            up = up or shift[name] > 0
            down = down or shift[name] < 0
        end
        Expect.truthy(up and down, `{id} is a trade-off`)
    end
    local seenMutations = {}
    for seed = 1, 100000 do
        local baby = GeneticsDomain.offspring(parent(ROCKHORN), parent(ROCKHORN), seed)
        if baby.mutationId ~= nil then
            seenMutations[baby.mutationId] = true
        end
    end
    for _, id in ipairs(MutationDefinitions.Ids) do
        Expect.truthy(seenMutations[id], `{id} can occur`)
    end

    -- Hatch time grows with generation up to a cap.
    Expect.equal(
        GeneticsDomain.hatchSeconds(parent(ROCKHORN), parent(EMBERCUB)),
        GameConfig.BREEDING_HATCH_BASE_SECONDS,
        "generation 0 hatches fastest"
    )
    Expect.truthy(
        GeneticsDomain.hatchSeconds(parent(ROCKHORN, 16, 16, 16, 3), parent(EMBERCUB))
            > GeneticsDomain.hatchSeconds(parent(ROCKHORN), parent(EMBERCUB)),
        "older lineages take longer"
    )
    Expect.equal(
        GeneticsDomain.hatchSeconds(parent(ROCKHORN, 16, 16, 16, 20), parent(EMBERCUB)),
        GameConfig.BREEDING_HATCH_MAX_SECONDS,
        "hatch time is capped"
    )

    -- Vigor changes output relative to neutral only.
    Expect.equal(GeneticsDomain.vigorMultiplier({ genes = { vigor = 16 } }), 1, "neutral is 1")
    Expect.near(
        GeneticsDomain.vigorMultiplier({ genes = { vigor = 31 } }),
        1.075,
        1e-9,
        "max vigor"
    )
    Expect.near(GeneticsDomain.vigorMultiplier({ genes = { vigor = 0 } }), 0.92, 1e-9, "min vigor")
    Expect.equal(GeneticsDomain.vigorMultiplier({}), 1, "no genes counts as neutral")

    Expect.truthy(GeneticsDomain.validSnapshot(parent(ROCKHORN)), "valid snapshot")
    Expect.falsy(GeneticsDomain.validSnapshot(parent("creature_nope")), "unknown species")
    Expect.falsy(GeneticsDomain.validSnapshot(parent(ROCKHORN, 40)), "gene out of range")
    Expect.falsy(GeneticsDomain.validSnapshot({ speciesId = ROCKHORN }), "missing fields")
    Expect.falsy(GeneticsDomain.validSnapshot(nil), "nil snapshot")
end

local function denProfile(denLevel: number?): any
    local profile = Fixtures.profile(NOW - 10)
    Fixtures.addBuilding(profile, "b_den", "building_breeding_den", { level = denLevel or 1 })
    profile.currencies.coins = 1000
    profile.inventory.item_food = 100
    Fixtures.addCreature(profile, "c_a", ROCKHORN, nil, 3)
    Fixtures.addCreature(profile, "c_b", EMBERCUB, nil, 5)
    Fixtures.addCreature(profile, "c_c", "creature_mossling", nil, 3)
    Fixtures.addCreature(profile, "c_d", "creature_voltfox", nil, 3)
    return profile
end

local function expectRefused(profile: any, code: string, label: string, ...: any)
    local before = TableUtil.deepCopy(profile)
    Expect.errorCode(BreedingDomain.start(profile, ...), code, label)
    Expect.equal(profile.currencies.coins, before.currencies.coins, `{label}: coins untouched`)
    Expect.equal(next(profile.eggs), nil, `{label}: no egg`)
    Expect.equal(profile.creatures.c_a.breedReadyAt, nil, `{label}: no cooldown`)
end

local function starting()
    local profile = denProfile()
    Expect.equal(CapacityDomain.breedingSlots(profile), 1, "one slot at level 1")
    local started =
        Expect.ok(BreedingDomain.start(profile, "c_a", "c_b", NOW, "e_1", 4242), "start breeding")
    local egg = profile.eggs.e_1
    Expect.truthy(egg ~= nil, "egg stored")
    Expect.equal(egg.seed, 4242, "seed stored")
    Expect.equal(egg.createdAt, NOW, "created time stored")
    Expect.equal(egg.hatchesAt, NOW + GameConfig.BREEDING_HATCH_BASE_SECONDS, "hatch time stored")
    Expect.equal(egg.parentA.speciesId, ROCKHORN, "parent A snapshot")
    Expect.equal(egg.parentB.speciesId, EMBERCUB, "parent B snapshot")
    Expect.equal(started.cost.coins, 100, "generation 0 coin cost")
    Expect.equal(profile.currencies.coins, 900, "coins paid")
    Expect.equal(profile.inventory.item_food, 90, "food paid")
    local rest = NOW + GameConfig.BREEDING_COOLDOWN_SECONDS
    Expect.equal(profile.creatures.c_a.breedReadyAt, rest, "parent A rests")
    Expect.equal(profile.creatures.c_b.breedReadyAt, rest, "parent B rests")
    Expect.truthy(profile.creatures.c_a ~= nil and profile.creatures.c_b ~= nil, "parents are kept")
    Expect.truthy(ProfileSchema.validate(profile), "profile with an egg validates")

    -- One slot, one egg.
    Expect.errorCode(
        BreedingDomain.start(profile, "c_c", "c_d", NOW, "e_2", 1),
        "breeding_slots_full",
        "second egg needs another slot"
    )
    -- A resting parent cannot be reused until the cooldown ends.
    local two = denProfile(2)
    Expect.ok(BreedingDomain.start(two, "c_a", "c_b", NOW, "e_1", 1), "first egg")
    Expect.errorCode(
        BreedingDomain.start(two, "c_a", "c_c", NOW + 60, "e_2", 2),
        "not_ready",
        "parent still resting"
    )
    Expect.equal(CapacityDomain.breedingSlots(two), 2, "two slots at level 2")
    Expect.ok(
        BreedingDomain.start(two, "c_c", "c_d", NOW + 60, "e_2", 3),
        "second egg in a second slot"
    )
    Expect.ok(
        BreedingDomain.start(
            (function()
                local later = denProfile(2)
                later.creatures.c_a.breedReadyAt = NOW
                return later
            end)(),
            "c_a",
            "c_b",
            NOW,
            "e_9",
            9
        ),
        "a parent whose rest has ended can breed again"
    )

    -- Cost grows with generation.
    local deep = denProfile()
    deep.creatures.c_a.generation = 3
    local deepStarted =
        Expect.ok(BreedingDomain.start(deep, "c_a", "c_b", NOW, "e_1", 5), "deep lineage")
    Expect.equal(deepStarted.cost.coins, 400, "coins scale with generation")
    Expect.equal(deep.inventory.item_food, 60, "food scales with generation")
end

local function refusals()
    local base = denProfile()
    local function fresh(change: ((any) -> ())?): any
        local profile = TableUtil.deepCopy(base)
        if change ~= nil then
            change(profile)
        end
        return profile
    end

    expectRefused(
        fresh(function(p)
            p.buildings.b_den = nil
        end),
        "not_unlocked",
        "no den",
        "c_a",
        "c_b",
        NOW,
        "e_1",
        1
    )
    expectRefused(fresh(), "invalid_request", "same creature twice", "c_a", "c_a", NOW, "e_1", 1)
    expectRefused(fresh(), "creature_not_owned", "unowned creature", "c_a", "c_zzz", NOW, "e_1", 1)
    expectRefused(
        fresh(function(p)
            p.creatures.c_a.assignedBuildingId = "b_mine"
        end),
        "not_ready",
        "assigned parent",
        "c_a",
        "c_b",
        NOW,
        "e_1",
        1
    )
    expectRefused(
        fresh(function(p)
            p.creatures.c_a.level = 2
        end),
        "not_ready",
        "low level parent",
        "c_a",
        "c_b",
        NOW,
        "e_1",
        1
    )
    expectRefused(
        fresh(function(p)
            p.creatures.c_b.breedReadyAt = NOW + 5
        end),
        "not_ready",
        "resting parent",
        "c_a",
        "c_b",
        NOW,
        "e_1",
        1
    )
    expectRefused(
        fresh(function(p)
            p.currencies.coins = 99
        end),
        "insufficient_resources",
        "not enough coins",
        "c_a",
        "c_b",
        NOW,
        "e_1",
        1
    )
    expectRefused(
        fresh(function(p)
            p.inventory.item_food = 9
        end),
        "insufficient_resources",
        "not enough food",
        "c_a",
        "c_b",
        NOW,
        "e_1",
        1
    )
    expectRefused(fresh(), "invalid_request", "negative seed", "c_a", "c_b", NOW, "e_1", -1)
    expectRefused(fresh(), "invalid_request", "fractional seed", "c_a", "c_b", NOW, "e_1", 1.5)
    expectRefused(fresh(), "invalid_request", "oversized seed", "c_a", "c_b", NOW, "e_1", 2 ^ 32)
    expectRefused(fresh(), "invalid_request", "empty egg id", "c_a", "c_b", NOW, "", 1)
    expectRefused(fresh(), "invalid_request", "non-string parent", "c_a", 5, NOW, "e_1", 1)

    -- The refusal for a food shortfall is checked before anything is paid.
    local broke = fresh(function(p)
        p.inventory.item_food = 9
    end)
    local coinsBefore = broke.currencies.coins
    BreedingDomain.start(broke, "c_a", "c_b", NOW, "e_1", 1)
    Expect.equal(broke.currencies.coins, coinsBefore, "no coins taken when food is short")
end

local function hatching()
    local profile = denProfile()
    Expect.ok(BreedingDomain.start(profile, "c_a", "c_b", NOW, "e_1", 31337), "start")
    local egg = TableUtil.deepCopy(profile.eggs.e_1)

    Expect.errorCode(
        BreedingDomain.hatch(profile, "e_1", egg.hatchesAt - 1, "c_new"),
        "not_ready",
        "too early"
    )
    Expect.errorCode(
        BreedingDomain.hatch(profile, "e_missing", egg.hatchesAt, "c_new"),
        "egg_not_found",
        "no such egg"
    )
    Expect.truthy(profile.eggs.e_1 ~= nil, "a refused hatch keeps the egg")

    -- The parents can be released while the egg incubates; the baby is unchanged.
    local expected = GeneticsDomain.offspring(egg.parentA, egg.parentB, egg.seed)
    profile.creatures.c_a = nil
    profile.creatures.c_b = nil

    local hatched = Expect.ok(BreedingDomain.hatch(profile, "e_1", egg.hatchesAt, "c_new"), "hatch")
    local baby = profile.creatures.c_new
    Expect.truthy(baby ~= nil, "baby added")
    Expect.equal(hatched.creature, baby, "result returns the baby")
    Expect.equal(baby.speciesId, expected.speciesId, "species follows the seed")
    Expect.equal(baby.genes.vigor, expected.genes.vigor, "vigor follows the seed")
    Expect.equal(baby.genes.might, expected.genes.might, "might follows the seed")
    Expect.equal(baby.genes.focus, expected.genes.focus, "focus follows the seed")
    Expect.equal(baby.mutationId, expected.mutationId, "mutation follows the seed")
    Expect.equal(baby.generation, 1, "generation")
    Expect.equal(baby.level, 1, "starts at level 1")
    Expect.equal(baby.bornAt, egg.hatchesAt, "birth time is the hatch time")
    Expect.equal(baby.assignedBuildingId, nil, "idle")
    Expect.equal(baby.lineage.speciesA, ROCKHORN, "lineage")
    Expect.equal(profile.eggs.e_1, nil, "egg consumed")
    Expect.truthy(ProfileSchema.validate(profile), "profile with a newborn validates")

    Expect.errorCode(
        BreedingDomain.hatch(profile, "e_1", egg.hatchesAt + 10, "c_other"),
        "egg_not_found",
        "an egg hatches once"
    )

    -- Habitats must have room, and nothing is consumed when they do not.
    local crowded = denProfile()
    Expect.ok(BreedingDomain.start(crowded, "c_a", "c_b", NOW, "e_1", 5), "start")
    for index = 1, 3 do
        Fixtures.addCreature(crowded, `c_extra_{index}`, ROCKHORN)
    end
    Expect.equal(CapacityDomain.creatureCount(crowded), 7, "more creatures than the base capacity")
    Expect.errorCode(
        BreedingDomain.hatch(crowded, "e_1", NOW + 99999, "c_new"),
        "creature_capacity_full",
        "no room to hatch"
    )
    Expect.truthy(crowded.eggs.e_1 ~= nil, "the egg waits for room")

    -- Damaged or hand-edited eggs are refused, never thrown on.
    local damaged = denProfile()
    damaged.eggs.e_1 = { id = "e_1", seed = -5 }
    Expect.errorCode(
        BreedingDomain.hatch(damaged, "e_1", NOW, "c_new"),
        "invalid_request",
        "damaged egg"
    )
    damaged.eggs.e_1 =
        { id = "e_1", seed = 5, createdAt = 0, hatchesAt = 0, parentA = "x", parentB = {} }
    Expect.errorCode(
        BreedingDomain.hatch(damaged, "e_1", NOW, "c_new"),
        "invalid_request",
        "egg with bad parents"
    )

    local collision = denProfile()
    Expect.ok(BreedingDomain.start(collision, "c_a", "c_b", NOW, "e_1", 5), "start")
    Expect.errorCode(
        BreedingDomain.hatch(collision, "e_1", NOW + 99999, "c_a"),
        "duplicate_creature_instance",
        "id collision"
    )
end

local function productionEffect()
    local function ratesFor(vigor: number): number
        local profile = Fixtures.profile(NOW)
        Fixtures.addCreature(profile, "c_w", ROCKHORN)
        profile.creatures.c_w.genes.vigor = vigor
        Fixtures.addStaffedBuilding(profile, "b_mine", "building_mine", { "c_w" })
        return ProductionDomain.cyclesPerMinute(profile, profile.buildings.b_mine)
    end

    local neutral = ratesFor(16)
    local strong = ratesFor(31)
    local weak = ratesFor(0)
    Expect.near(strong / neutral, 1.075, 1e-9, "max vigor output")
    Expect.near(weak / neutral, 0.92, 1e-9, "min vigor output")

    -- A creature with neutral genes is exactly as productive as before genes existed:
    -- 6 cycles/min x 1.25 mining affinity x 1.0 level bonus x 1.0 building level.
    Expect.near(neutral, 6 * 1.25, 1e-9, "neutral creatures are unchanged")

    -- A hybrid works both of its parents' trades at the hybrid rate.
    local profile = Fixtures.profile(NOW)
    Fixtures.addCreature(profile, "c_h", "creature_magmaback")
    Fixtures.addStaffedBuilding(profile, "b_mine", "building_mine", { "c_h" })
    Fixtures.addCreature(profile, "c_h2", "creature_magmaback")
    Fixtures.addStaffedBuilding(profile, "b_furnace", "building_furnace", { "c_h2" })
    Expect.near(
        ProductionDomain.cyclesPerMinute(profile, profile.buildings.b_mine),
        6 * 1.15,
        1e-9,
        "a hybrid mines at its hybrid rate"
    )
    Expect.truthy(
        ProductionDomain.cyclesPerMinute(profile, profile.buildings.b_furnace) > 0,
        "and smelts too"
    )
end

local function run()
    genetics()
    starting()
    refusals()
    hatching()
    productionEffect()
end

return run
