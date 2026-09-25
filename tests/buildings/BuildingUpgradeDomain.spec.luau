local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local BuildingUpgradeDomain = require("../../src/shared/Buildings/BuildingUpgradeDomain")

local function expectEqual(actual: any, expected: any, label: string)
    if actual ~= expected then
        error(`{label}: expected {expected}, got {actual}`)
    end
end

local function expectOk(result: any, label: string)
    if result.ok ~= true then
        error(`{label}: expected ok result, got {result.code}`)
    end
end

local function expectErrorCode(result: any, code: string, label: string)
    if result.ok ~= false then
        error(`{label}: expected error result`)
    end
    expectEqual(result.code, code, label)
end

local function addRockhorn(profile: any, buildingId: string)
    profile.creatures.rockhorn_1 = {
        id = "rockhorn_1",
        speciesId = "creature_rockhorn",
        level = 1,
        experience = 0,
        traits = {},
        mutationId = nil,
        assignedBuildingId = buildingId,
    }
end

local function addBuilding(
    profile: any,
    id: string,
    definitionId: string,
    level: number,
    workers: { string }
)
    profile.buildings[id] = {
        id = id,
        definitionId = definitionId,
        level = level,
        position = { x = 0, y = 0, z = 0 },
        rotation = 0,
        assignedCreatureIds = workers,
        lastClaimedAt = 100,
    }
end

local function fundedMine()
    local profile = ProfileSchema.createDefault(100)
    profile.inventory.item_stone = 40
    profile.inventory.item_copper_bar = 10
    addRockhorn(profile, "mine_1")
    addBuilding(profile, "mine_1", "building_mine", 1, { "rockhorn_1" })
    return profile
end

local function run()
    local profile = fundedMine()
    local upgraded = BuildingUpgradeDomain.upgrade(profile, "mine_1", 100)
    expectOk(upgraded, "Mine level two upgrade")
    expectEqual(upgraded.value, 2, "Mine new level")
    expectEqual(profile.buildings.mine_1.level, 2, "Mine stored level")
    expectEqual(profile.inventory.item_stone, nil, "Mine upgrade stone cost")
    expectEqual(profile.inventory.item_copper_bar, nil, "Mine upgrade bar cost")

    local insufficient = fundedMine()
    insufficient.inventory.item_stone = 39
    local rejected = BuildingUpgradeDomain.upgrade(insufficient, "mine_1", 220)
    expectErrorCode(rejected, "insufficient_resources", "insufficient upgrade rejected")
    expectEqual(insufficient.buildings.mine_1.level, 1, "failed upgrade level unchanged")
    expectEqual(insufficient.buildings.mine_1.lastClaimedAt, 100, "failed upgrade not settled")
    expectEqual(insufficient.inventory.item_copper_ore, nil, "failed upgrade produces nothing")
    expectEqual(insufficient.inventory.item_stone, 39, "failed upgrade cost untouched")

    local settlement = fundedMine()
    local settledUpgrade = BuildingUpgradeDomain.upgrade(settlement, "mine_1", 220)
    expectOk(settledUpgrade, "upgrade settles old rate")
    expectEqual(settlement.inventory.item_copper_ore, 15, "old level output settled")
    expectEqual(settlement.buildings.mine_1.lastClaimedAt, 220, "upgrade settlement timestamp")
    expectEqual(settlement.buildings.mine_1.level, 2, "upgrade increments after settlement")

    local missing = BuildingUpgradeDomain.upgrade(ProfileSchema.createDefault(100), "missing", 100)
    expectErrorCode(missing, "building_not_owned", "missing building rejected")

    local utility = ProfileSchema.createDefault(100)
    addBuilding(utility, "warehouse_1", "building_warehouse", 1, {})
    local utilityUpgrade = BuildingUpgradeDomain.upgrade(utility, "warehouse_1", 100)
    expectErrorCode(utilityUpgrade, "max_level_reached", "utility upgrade rejected")

    local maxed = fundedMine()
    maxed.buildings.mine_1.level = 3
    local maxUpgrade = BuildingUpgradeDomain.upgrade(maxed, "mine_1", 100)
    expectErrorCode(maxUpgrade, "max_level_reached", "max production level rejected")

    local corrupt = fundedMine()
    corrupt.buildings.mine_1.level = 0
    local corruptUpgrade = BuildingUpgradeDomain.upgrade(corrupt, "mine_1", 100)
    expectErrorCode(corruptUpgrade, "invalid_request", "corrupt building level rejected")
end

return run
