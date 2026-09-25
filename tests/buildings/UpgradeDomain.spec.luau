local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local UpgradeDomain = require("../../src/shared/Buildings/UpgradeDomain")

local function run()
    local level2 = assert(UpgradeDomain.costFor("building_mine", 2))
    Expect.equal(level2.items.item_wood, 32, "level 2 wood")
    Expect.equal(level2.items.item_stone, 48, "level 2 stone")
    Expect.equal(level2.items.item_energy, nil, "level 2 needs no energy")
    Expect.equal(level2.coins, 40, "level 2 coins")

    local level3 = assert(UpgradeDomain.costFor("building_mine", 3))
    Expect.equal(level3.items.item_wood, 52, "level 3 wood")
    Expect.equal(level3.items.item_stone, 77, "level 3 stone")
    Expect.equal(level3.items.item_energy, 10, "level 3 energy")
    Expect.equal(level3.coins, 160, "level 3 coins")

    local level5 = assert(UpgradeDomain.costFor("building_mine", 5))
    Expect.equal(level5.items.item_energy, 30, "level 5 energy")
    Expect.equal(level5.coins, 640, "level 5 coins")

    Expect.equal(UpgradeDomain.costFor("building_mine", 1), nil, "no cost for level 1")
    Expect.equal(UpgradeDomain.costFor("building_mine", 6), nil, "no cost above max level")
    Expect.equal(UpgradeDomain.costFor("building_unknown", 2), nil, "no cost for unknown")

    local noBench = Fixtures.profile()
    noBench.inventory.item_wood = 100
    noBench.inventory.item_stone = 100
    noBench.currencies.coins = 100
    Fixtures.addBuilding(noBench, "mine_1", "building_mine")
    Expect.errorCode(
        UpgradeDomain.upgrade(noBench, "mine_1", 1000),
        "not_unlocked",
        "workbench required"
    )

    local profile = Fixtures.profile()
    profile.inventory.item_wood = 100
    profile.inventory.item_stone = 100
    profile.currencies.coins = 100
    Fixtures.addCreature(profile, "rockhorn_1", "creature_rockhorn")
    Fixtures.addStaffedBuilding(profile, "mine_1", "building_mine", { "rockhorn_1" })
    Fixtures.addBuilding(profile, "bench_1", "building_workbench", { x = 10 })

    local upgraded = Expect.ok(UpgradeDomain.upgrade(profile, "mine_1", 1060), "upgrade mine")
    Expect.equal(upgraded.level, 2, "new level")
    Expect.equal(profile.buildings.mine_1.level, 2, "level persisted")
    Expect.equal(profile.inventory.item_wood, 68, "wood charged")
    Expect.equal(profile.inventory.item_stone, 100 + 7 - 48, "stone charged after settlement")
    Expect.equal(profile.inventory.item_copper_ore, 7, "old-rate production settled")
    Expect.equal(profile.currencies.coins, 60, "coins charged")

    Expect.errorCode(
        UpgradeDomain.upgrade(profile, "mine_1", 1060),
        "insufficient_resources",
        "cannot afford level 3"
    )
    Expect.equal(profile.buildings.mine_1.level, 2, "failed upgrade keeps level")
    Expect.equal(profile.currencies.coins, 60, "failed upgrade keeps coins")

    local poorCoins = Fixtures.profile()
    poorCoins.inventory.item_wood = 100
    poorCoins.inventory.item_stone = 100
    poorCoins.currencies.coins = 39
    Fixtures.addBuilding(poorCoins, "mine_1", "building_mine")
    Fixtures.addBuilding(poorCoins, "bench_1", "building_workbench", { x = 10 })
    Expect.errorCode(
        UpgradeDomain.upgrade(poorCoins, "mine_1", 1000),
        "insufficient_resources",
        "coins required"
    )
    Expect.equal(poorCoins.inventory.item_wood, 100, "coin shortfall does not charge items")

    local maxed = Fixtures.profile()
    Fixtures.addBuilding(maxed, "mine_1", "building_mine", { level = 5 })
    Fixtures.addBuilding(maxed, "bench_1", "building_workbench", { x = 10 })
    Expect.errorCode(UpgradeDomain.upgrade(maxed, "mine_1", 1000), "max_level_reached", "max level")
    Expect.errorCode(
        UpgradeDomain.upgrade(maxed, "missing", 1000),
        "building_not_owned",
        "missing building"
    )
end

return run
