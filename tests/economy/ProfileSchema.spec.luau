local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")

local function expectEqual(actual: any, expected: any, label: string)
    if actual ~= expected then
        error(`{label}: expected {expected}, got {actual}`)
    end
end

local function expectTrue(value: boolean, label: string)
    if not value then
        error(`{label}: expected true`)
    end
end

local function expectFalse(value: boolean, label: string)
    if value then
        error(`{label}: expected false`)
    end
end

local function run()
    local profile = ProfileSchema.createDefault(100)
    expectEqual(profile.schemaVersion, 1, "default schema version")
    expectEqual(profile.currencies.coins, 0, "default coins")
    expectEqual(profile.currencies.gems, 0, "default gems")
    expectEqual(profile.lastSeenAt, 100, "default last seen")
    expectTrue(ProfileSchema.validate(profile), "default profile validates")

    local secondProfile = ProfileSchema.createDefault(200)
    profile.inventory.item_wood = 5
    expectEqual(secondProfile.inventory.item_wood, nil, "default profiles do not share inventory")

    local negativeCurrency = ProfileSchema.createDefault(100)
    negativeCurrency.currencies.coins = -1
    expectFalse(ProfileSchema.validate(negativeCurrency), "negative currency rejected")

    local fractionalCurrency = ProfileSchema.createDefault(100)
    fractionalCurrency.currencies.coins = 1.5
    expectFalse(ProfileSchema.validate(fractionalCurrency), "fractional currency rejected")

    local unknownInventory = ProfileSchema.createDefault(100)
    unknownInventory.inventory.item_unknown = 1
    expectFalse(ProfileSchema.validate(unknownInventory), "unknown inventory item rejected")

    local negativeInventory = ProfileSchema.createDefault(100)
    negativeInventory.inventory.item_wood = -1
    expectFalse(ProfileSchema.validate(negativeInventory), "negative inventory rejected")

    local validCreatureProfile = ProfileSchema.createDefault(100)
    validCreatureProfile.creatures.creature_instance_1 = {
        id = "creature_instance_1",
        speciesId = "creature_rockhorn",
        level = 1,
        experience = 0,
        traits = {},
    }
    expectTrue(ProfileSchema.validate(validCreatureProfile), "known creature species accepted")

    local unknownCreatureProfile = ProfileSchema.createDefault(100)
    unknownCreatureProfile.creatures.creature_instance_1 = {
        id = "creature_instance_1",
        speciesId = "creature_unknown",
        level = 1,
        experience = 0,
        traits = {},
    }
    expectFalse(ProfileSchema.validate(unknownCreatureProfile), "unknown creature species rejected")

    local sparseTraitsProfile = ProfileSchema.createDefault(100)
    sparseTraitsProfile.creatures.creature_instance_1 = {
        id = "creature_instance_1",
        speciesId = "creature_rockhorn",
        level = 1,
        experience = 0,
        traits = { [2] = "trait_sparse" },
    }
    expectFalse(ProfileSchema.validate(sparseTraitsProfile), "sparse creature traits rejected")

    local validBuildingProfile = ProfileSchema.createDefault(100)
    validBuildingProfile.buildings.building_instance_1 = {
        id = "building_instance_1",
        definitionId = "building_mine",
        level = 1,
        position = { x = 0, y = 0, z = 0 },
        rotation = 0,
        assignedCreatureIds = {},
        lastClaimedAt = 100,
    }
    expectTrue(ProfileSchema.validate(validBuildingProfile), "known building definition accepted")

    local unknownBuildingProfile = ProfileSchema.createDefault(100)
    unknownBuildingProfile.buildings.building_instance_1 = {
        id = "building_instance_1",
        definitionId = "building_unknown",
        level = 1,
        position = { x = 0, y = 0, z = 0 },
        rotation = 0,
        assignedCreatureIds = {},
        lastClaimedAt = 100,
    }
    expectFalse(
        ProfileSchema.validate(unknownBuildingProfile),
        "unknown building definition rejected"
    )

    local sparseAssignmentProfile = ProfileSchema.createDefault(100)
    sparseAssignmentProfile.buildings.building_instance_1 = {
        id = "building_instance_1",
        definitionId = "building_mine",
        level = 1,
        position = { x = 0, y = 0, z = 0 },
        rotation = 0,
        assignedCreatureIds = { [2] = "creature_instance_1" },
        lastClaimedAt = 100,
    }
    expectFalse(
        ProfileSchema.validate(sparseAssignmentProfile),
        "sparse building assignments rejected"
    )

    local migrated = assert(ProfileSchema.migrate(profile))
    expectTrue(migrated ~= profile, "migration returns independent profile")
    expectTrue(migrated.inventory ~= profile.inventory, "migration deep copies inventory")
    expectEqual(migrated.schemaVersion, 1, "migration keeps current version")
    expectEqual(migrated.inventory.item_wood, 5, "migration preserves inventory")

    migrated.inventory.item_wood = 9
    expectEqual(profile.inventory.item_wood, 5, "migration does not alias source inventory")

    local unsupported = ProfileSchema.createDefault(100)
    unsupported.schemaVersion = 99
    local unsupportedResult = ProfileSchema.migrate(unsupported)
    expectEqual(unsupportedResult, nil, "unsupported schema rejected")
end

return run
