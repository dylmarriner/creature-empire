local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local ProfileSchemaV1 = require("../../src/shared/Profiles/ProfileSchemaV1")
local TableUtil = require("../../src/shared/Util/TableUtil")

-- A profile exactly as the first release stored it: schema version 1, no genetics fields.
local function v1Profile(): any
    return {
        schemaVersion = 1,
        currencies = { coins = 120, gems = 3 },
        inventory = { item_wood = 7 },
        creatures = {
            c_a = {
                id = "c_a",
                speciesId = "creature_rockhorn",
                level = 4,
                experience = 20,
                traits = {},
                assignedBuildingId = "b_mine",
            },
            c_b = {
                id = "c_b",
                speciesId = "creature_mossling",
                level = 1,
                experience = 0,
                traits = {},
            },
        },
        buildings = {
            b_mine = {
                id = "b_mine",
                definitionId = "building_mine",
                level = 2,
                position = { x = 4, y = 0, z = 8 },
                rotation = 90,
                assignedCreatureIds = { "c_a" },
                lastClaimedAt = 900,
            },
        },
        unlocks = { starter_creature_granted = true },
        lastSeenAt = 1234,
    }
end

local function expectNeutralGenes(creature: any, label: string)
    Expect.equal(creature.genes.vigor, 16, `{label} vigor`)
    Expect.equal(creature.genes.might, 16, `{label} might`)
    Expect.equal(creature.genes.focus, 16, `{label} focus`)
    Expect.equal(creature.generation, 0, `{label} generation`)
end

local function run()
    local old = v1Profile()
    Expect.truthy(ProfileSchemaV1.validate(old), "fixture is a valid v1 profile")
    Expect.falsy(ProfileSchema.validate(old), "the v2 validator refuses a v1 profile")

    local snapshot = TableUtil.deepCopy(old)
    local migrated, reason = ProfileSchema.migrate(old)
    Expect.truthy(migrated ~= nil, `v1 profile migrates ({reason})`)
    Expect.truthy(ProfileSchema.validate(migrated), "migrated profile is valid v2")
    Expect.equal(migrated.schemaVersion, 2, "migrated version")
    Expect.truthy(migrated ~= old, "migration returns a new table")
    Expect.equal(old.schemaVersion, 1, "migration does not mutate its input")
    Expect.equal(old.creatures.c_a.genes, nil, "input creatures are untouched")
    Expect.truthy(
        TableUtil.deepCopy(old).currencies.coins == snapshot.currencies.coins,
        "input values are untouched"
    )

    Expect.equal(migrated.currencies.coins, 120, "coins preserved")
    Expect.equal(migrated.currencies.gems, 3, "gems preserved")
    Expect.equal(migrated.inventory.item_wood, 7, "inventory preserved")
    Expect.equal(migrated.buildings.b_mine.level, 2, "buildings preserved")
    Expect.equal(migrated.creatures.c_a.level, 4, "creature level preserved")
    Expect.equal(migrated.creatures.c_a.assignedBuildingId, "b_mine", "assignment preserved")
    Expect.equal(migrated.unlocks.starter_creature_granted, true, "unlocks preserved")
    Expect.equal(migrated.lastSeenAt, 1234, "lastSeenAt preserved")
    expectNeutralGenes(migrated.creatures.c_a, "c_a")
    expectNeutralGenes(migrated.creatures.c_b, "c_b")
    Expect.equal(migrated.creatures.c_a.bornAt, 1234, "bornAt uses lastSeenAt")
    Expect.equal(migrated.creatures.c_a.lineage, nil, "no lineage")

    for _, name in ipairs({ "eggs", "expeditions", "transfers", "purchases", "passes", "stats" }) do
        Expect.truthy(type(migrated[name]) == "table", `{name} map added`)
        Expect.equal(next(migrated[name]), nil, `{name} starts empty`)
    end
    Expect.equal(migrated.guildId, nil, "no guild")

    -- Deterministic and idempotent.
    local again = assert(ProfileSchema.migrate(old))
    Expect.equal(again.creatures.c_a.bornAt, migrated.creatures.c_a.bornAt, "deterministic")
    local twice = assert(ProfileSchema.migrate(migrated))
    Expect.equal(twice.schemaVersion, 2, "migrating v2 keeps v2")
    Expect.equal(twice.creatures.c_a.generation, 0, "migrating v2 changes nothing")
    Expect.truthy(twice ~= migrated, "migrating v2 still returns a copy")

    -- Old data that was already invalid stays refused; nothing is repaired by guessing.
    local corrupt = v1Profile()
    corrupt.creatures.c_a.level = -1
    local refused, why = ProfileSchema.migrate(corrupt)
    Expect.equal(refused, nil, "corrupt v1 refused")
    Expect.truthy(why ~= nil, "corrupt v1 has a reason")

    local future = v1Profile()
    future.schemaVersion = 3
    Expect.equal(ProfileSchema.migrate(future), nil, "future versions refused")
    Expect.equal(ProfileSchema.migrate("nonsense"), nil, "non-table refused")
    Expect.equal(ProfileSchema.migrate(nil), nil, "nil refused")

    -- Rollback hazard: the frozen v1 validator rejects a v2 profile, which is why an older
    -- build kicks (and never overwrites) a player whose profile was saved by a newer one.
    Expect.falsy(ProfileSchemaV1.validate(migrated), "the v1 validator refuses v2")

    -- New fields are validated strictly.
    local function mutated(change: (profile: any) -> ()): any
        local profile = Fixtures.profile(500)
        Fixtures.addCreature(profile, "c_1", "creature_rockhorn")
        change(profile)
        return profile
    end

    Expect.truthy(ProfileSchema.validate(mutated(function() end)), "baseline v2 profile is valid")
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            p.creatures.c_1.genes.vigor = 32
        end)),
        "gene above max rejected"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            p.creatures.c_1.genes.might = -1
        end)),
        "gene below min rejected"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            p.creatures.c_1.genes.focus = 1.5
        end)),
        "fractional gene rejected"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            p.creatures.c_1.genes.luck = 3
        end)),
        "unknown gene rejected"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            p.creatures.c_1.genes = nil
        end)),
        "missing genes rejected"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            p.creatures.c_1.generation = -1
        end)),
        "negative generation rejected"
    )
    Expect.truthy(
        ProfileSchema.validate(mutated(function(p)
            p.creatures.c_1.lineage =
                { speciesA = "creature_rockhorn", speciesB = "creature_voltfox" }
        end)),
        "lineage accepted"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            p.creatures.c_1.lineage = { speciesA = "creature_rockhorn" }
        end)),
        "partial lineage rejected"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            p.eggs.egg_1 = { id = "egg_other" }
        end)),
        "egg filed under another id rejected"
    )
    Expect.truthy(
        ProfileSchema.validate(mutated(function(p)
            p.eggs.egg_1 = { id = "egg_1", anything = "later systems own this" }
        end)),
        "egg with extra fields accepted"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            p.purchases.receipt_1 = -5
        end)),
        "negative purchase timestamp rejected"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            p.passes.pass_1 = false
        end)),
        "false pass flag rejected"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            p.guildId = ""
        end)),
        "empty guild id rejected"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            p.stats.kills = 1.5
        end)),
        "fractional stat rejected"
    )

    local transferEntry = {
        id = "t_1",
        createdAt = 10,
        offer = {
            items = { item_wood = 3 },
            coins = 5,
            creatures = {
                c_9 = {
                    id = "c_9",
                    speciesId = "creature_rockhorn",
                    level = 1,
                    experience = 0,
                    traits = {},
                    genes = { vigor = 1, might = 2, focus = 3 },
                    generation = 1,
                    bornAt = 0,
                },
            },
        },
    }
    Expect.truthy(
        ProfileSchema.validate(mutated(function(p)
            p.transfers.t_1 = TableUtil.deepCopy(transferEntry)
        end)),
        "well-formed transfer journal entry accepted"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            local entry = TableUtil.deepCopy(transferEntry)
            entry.offer.items.item_wood = 0
            p.transfers.t_1 = entry
        end)),
        "zero-quantity offered item rejected"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            local entry = TableUtil.deepCopy(transferEntry)
            entry.offer.items.item_unknown = 1
            p.transfers.t_1 = entry
        end)),
        "unknown offered item rejected"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            local entry = TableUtil.deepCopy(transferEntry)
            entry.offer.creatures.c_9.assignedBuildingId = "b_1"
            p.transfers.t_1 = entry
        end)),
        "escrowed creature cannot be assigned"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            local entry = TableUtil.deepCopy(transferEntry)
            entry.id = "t_other"
            p.transfers.t_1 = entry
        end)),
        "journal entry filed under another id rejected"
    )
    Expect.falsy(
        ProfileSchema.validate(mutated(function(p)
            local entry = TableUtil.deepCopy(transferEntry)
            entry.offer.surprise = true
            p.transfers.t_1 = entry
        end)),
        "unknown payload key rejected"
    )
end

return run
