local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local ProductionDomain = require("../../src/shared/Economy/ProductionDomain")

local function staffedMine(now: number?)
    local profile = Fixtures.profile()
    Fixtures.addCreature(profile, "rockhorn_1", "creature_rockhorn")
    Fixtures.addStaffedBuilding(profile, "mine_1", "building_mine", { "rockhorn_1" }, {
        lastClaimedAt = now or 1000,
    })
    return profile
end

local function run()
    -- Rate: 6 cycles/min x level 1 x Rockhorn 1.25 = 7.5 cycles/min.
    local profile = staffedMine()
    Expect.near(
        ProductionDomain.cyclesPerMinute(profile, profile.buildings.mine_1),
        7.5,
        1e-9,
        "staffed mine rate"
    )

    local settled = Expect.ok(ProductionDomain.settle(profile, "mine_1", 1060), "settle one minute")
    Expect.equal(settled.cycles, 7, "whole cycles in one minute")
    Expect.equal(profile.inventory.item_copper_ore, 7, "ore produced")
    Expect.equal(profile.inventory.item_stone, 7, "stone produced")
    Expect.equal(settled.limitedBy, nil, "not limited")
    -- 7 cycles take 56 seconds; the remaining 4 seconds of progress carry over.
    Expect.equal(profile.buildings.mine_1.lastClaimedAt, 1056, "fractional progress carried")
    Expect.equal(profile.creatures.rockhorn_1.experience, 7, "worker gains experience per cycle")

    local second =
        Expect.ok(ProductionDomain.settle(profile, "mine_1", 1064), "settle carried time")
    Expect.equal(second.cycles, 1, "carried progress completes a cycle")
    Expect.equal(profile.buildings.mine_1.lastClaimedAt, 1064, "clock advanced to cycle boundary")

    local tooSoon = Expect.ok(ProductionDomain.settle(profile, "mine_1", 1065), "settle too soon")
    Expect.equal(tooSoon.cycles, 0, "no cycle completes in one second")
    Expect.equal(profile.buildings.mine_1.lastClaimedAt, 1064, "unfinished progress is kept")

    -- Frequent claims never produce more than one long claim.
    local frequent = staffedMine()
    for now = 1005, 1600, 5 do
        Expect.ok(ProductionDomain.settle(frequent, "mine_1", now), "frequent claim")
    end
    local single = staffedMine()
    Expect.ok(ProductionDomain.settle(single, "mine_1", 1600), "single claim")
    Expect.truthy(
        frequent.inventory.item_copper_ore <= single.inventory.item_copper_ore,
        "frequent claims cannot out-produce a single claim"
    )
    Expect.truthy(
        single.inventory.item_copper_ore - frequent.inventory.item_copper_ore <= 1,
        "frequent claims lose at most one cycle"
    )

    -- Idle buildings do not bank time.
    local idle = Fixtures.profile()
    Fixtures.addBuilding(idle, "mine_1", "building_mine", { lastClaimedAt = 1000 })
    local idleSettled = Expect.ok(ProductionDomain.settle(idle, "mine_1", 5000), "idle settle")
    Expect.equal(idleSettled.cycles, 0, "idle building produces nothing")
    Expect.equal(idle.buildings.mine_1.lastClaimedAt, 5000, "idle clock resets")

    -- Storage limits output and discards the remaining time.
    local offline = staffedMine()
    local capped =
        Expect.ok(ProductionDomain.settle(offline, "mine_1", 1000 + 12 * 3600), "long offline")
    Expect.equal(capped.limitedBy, "storage", "long offline limited by storage")
    Expect.equal(offline.inventory.item_copper_ore, 200, "ore capped at storage")
    Expect.equal(offline.inventory.item_stone, 200, "stone capped at storage")
    Expect.equal(offline.buildings.mine_1.lastClaimedAt, 1000 + 12 * 3600, "limited clock resets")

    -- Offline time beyond eight hours is discarded when storage is large enough.
    local generator = Fixtures.profile()
    Fixtures.addCreature(generator, "voltfox_1", "creature_voltfox")
    Fixtures.addStaffedBuilding(generator, "generator_1", "building_generator", { "voltfox_1" })
    Fixtures.addBuilding(generator, "warehouse_1", "building_warehouse", { x = 10, level = 5 })
    Fixtures.addBuilding(generator, "warehouse_2", "building_warehouse", { x = 20, level = 5 })
    local capSettled = Expect.ok(
        ProductionDomain.settle(generator, "generator_1", 1000 + 12 * 3600),
        "generator offline"
    )
    -- 5 x 1.25 = 6.25 cycles/min for 480 capped minutes.
    Expect.equal(capSettled.cycles, 3000, "offline production capped at eight hours")
    Expect.equal(capSettled.limitedBy, nil, "offline cap is not a storage limit")
    Expect.equal(generator.inventory.item_energy, 3000, "energy produced")

    local shortOffline = Fixtures.profile()
    Fixtures.addCreature(shortOffline, "voltfox_1", "creature_voltfox")
    Fixtures.addStaffedBuilding(shortOffline, "generator_1", "building_generator", { "voltfox_1" })
    Fixtures.addBuilding(shortOffline, "warehouse_1", "building_warehouse", { x = 10, level = 5 })
    local short = Expect.ok(
        ProductionDomain.settle(shortOffline, "generator_1", 1000 + 4 * 3600),
        "four hours offline"
    )
    Expect.equal(short.cycles, 1500, "four hours of production")

    -- Processing buildings are limited by their inputs.
    local furnace = Fixtures.profile()
    Fixtures.addCreature(furnace, "embercub_1", "creature_embercub")
    Fixtures.addStaffedBuilding(furnace, "furnace_1", "building_furnace", { "embercub_1" })
    furnace.inventory.item_copper_ore = 10
    local smelted = Expect.ok(ProductionDomain.settle(furnace, "furnace_1", 1600), "smelt")
    Expect.equal(smelted.cycles, 10, "smelting limited by ore")
    Expect.equal(smelted.limitedBy, "input", "input limited")
    Expect.equal(furnace.inventory.item_copper_ore, nil, "ore consumed")
    Expect.equal(furnace.inventory.item_copper_bar, 10, "bars produced")
    Expect.equal(furnace.buildings.furnace_1.lastClaimedAt, 1600, "input-limited clock resets")

    -- claimAll settles extractors before processors.
    local chain = Fixtures.profile()
    Fixtures.addCreature(chain, "rockhorn_1", "creature_rockhorn")
    Fixtures.addCreature(chain, "embercub_1", "creature_embercub")
    Fixtures.addStaffedBuilding(chain, "a_furnace", "building_furnace", { "embercub_1" })
    Fixtures.addStaffedBuilding(chain, "z_mine", "building_mine", { "rockhorn_1" }, { x = 10 })
    local summary = Expect.ok(ProductionDomain.claimAll(chain, 1060), "claim all")
    Expect.equal(summary.buildings, 2, "both buildings settled")
    Expect.equal(summary.produced.item_copper_ore, 7, "mine produced ore")
    Expect.equal(summary.produced.item_copper_bar, 5, "furnace used fresh ore")
    Expect.equal(chain.inventory.item_copper_ore, 2, "remaining ore")
    Expect.equal(chain.inventory.item_copper_bar, 5, "bars in inventory")

    -- Level and worker multipliers.
    local leveled = staffedMine()
    leveled.buildings.mine_1.level = 3
    Expect.near(
        ProductionDomain.cyclesPerMinute(leveled, leveled.buildings.mine_1),
        15,
        1e-9,
        "level 3 doubles output"
    )
    leveled.creatures.rockhorn_1.level = 5
    Expect.near(
        ProductionDomain.cyclesPerMinute(leveled, leveled.buildings.mine_1),
        18,
        1e-9,
        "creature level bonus"
    )

    local twoWorkers = staffedMine()
    Fixtures.addCreature(twoWorkers, "rockhorn_2", "creature_rockhorn", "mine_1")
    table.insert(twoWorkers.buildings.mine_1.assignedCreatureIds, "rockhorn_2")
    Expect.near(
        ProductionDomain.cyclesPerMinute(twoWorkers, twoWorkers.buildings.mine_1),
        15,
        1e-9,
        "workers stack"
    )

    local inconsistent = staffedMine()
    inconsistent.creatures.rockhorn_1.assignedBuildingId = "elsewhere"
    Expect.equal(
        ProductionDomain.cyclesPerMinute(inconsistent, inconsistent.buildings.mine_1),
        0,
        "one-sided assignment does not produce"
    )

    -- Clock skew never produces output.
    local skewed = staffedMine(5000)
    local skew = Expect.ok(ProductionDomain.settle(skewed, "mine_1", 4000), "future claim time")
    Expect.equal(skew.cycles, 0, "future lastClaimedAt produces nothing")
    Expect.equal(skewed.buildings.mine_1.lastClaimedAt, 4000, "future clock is corrected")

    -- Utility buildings settle as a no-op.
    local utility = Fixtures.profile()
    Fixtures.addBuilding(utility, "warehouse_1", "building_warehouse")
    local utilitySettled =
        Expect.ok(ProductionDomain.settle(utility, "warehouse_1", 5000), "utility settle")
    Expect.equal(utilitySettled.cycles, 0, "utility produces nothing")

    Expect.errorCode(
        ProductionDomain.settle(utility, "missing", 5000),
        "building_not_owned",
        "missing building"
    )
    Expect.errorCode(
        ProductionDomain.settle(utility, "warehouse_1", -1),
        "invalid_request",
        "negative time"
    )
    Expect.errorCode(
        ProductionDomain.claimAll(Fixtures.profile(), 5000),
        "nothing_to_claim",
        "no production buildings"
    )
end

return run
