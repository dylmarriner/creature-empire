local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local MarketDomain = require("../../src/shared/Economy/MarketDomain")
local CapacityDomain = require("../../src/shared/Economy/CapacityDomain")

local function run()
    local profile = Fixtures.profile()
    profile.inventory.item_wood = 15
    profile.inventory.item_copper_bar = 4

    local sold = Expect.ok(MarketDomain.sell(profile, "item_wood", 10), "sell wood")
    Expect.equal(sold.coins, 10, "wood price")
    Expect.equal(profile.inventory.item_wood, 5, "wood removed")
    Expect.equal(profile.currencies.coins, 10, "coins added")

    Expect.ok(MarketDomain.sell(profile, "item_copper_bar", 4), "sell bars")
    Expect.equal(profile.currencies.coins, 34, "bar price")
    Expect.equal(profile.inventory.item_copper_bar, nil, "bars sold out")

    Expect.errorCode(
        MarketDomain.sell(profile, "item_wood", 6),
        "insufficient_resources",
        "cannot oversell"
    )
    Expect.equal(profile.currencies.coins, 34, "failed sale keeps coins")
    Expect.errorCode(MarketDomain.sell(profile, "item_wood", 0), "invalid_request", "zero sale")
    Expect.errorCode(MarketDomain.sell(profile, "item_wood", 1.5), "invalid_request", "fraction")
    Expect.errorCode(
        MarketDomain.sell(profile, "item_wood", 100001),
        "invalid_request",
        "above max quantity"
    )
    Expect.errorCode(MarketDomain.sell(profile, "item_unknown", 1), "invalid_request", "unknown")

    local capacity = Fixtures.profile()
    Expect.equal(CapacityDomain.storageCapacity(capacity), 200, "base storage")
    Expect.equal(CapacityDomain.creatureCapacity(capacity), 4, "base creature capacity")
    Fixtures.addBuilding(capacity, "warehouse_1", "building_warehouse", { level = 2 })
    Fixtures.addBuilding(capacity, "habitat_1", "building_creature_habitat", { x = 10, level = 3 })
    Expect.equal(CapacityDomain.storageCapacity(capacity), 800, "warehouse levels add storage")
    Expect.equal(CapacityDomain.creatureCapacity(capacity), 16, "habitat levels add capacity")
    capacity.inventory.item_wood = 790
    Expect.equal(CapacityDomain.storageSpace(capacity, "item_wood"), 10, "remaining space")
    capacity.inventory.item_wood = 900
    Expect.equal(CapacityDomain.storageSpace(capacity, "item_wood"), 0, "space never negative")
    Expect.falsy(CapacityDomain.hasUtility(capacity, "workbench"), "no workbench")
end

return run
