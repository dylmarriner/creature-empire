local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local InventoryDomain = require("../../src/shared/Economy/InventoryDomain")

local function expectEqual(actual: any, expected: any, label: string)
    if actual ~= expected then
        error(`{label}: expected {expected}, got {actual}`)
    end
end

local function expectOkValue(result: any, expected: any, label: string)
    if result.ok ~= true then
        error(`{label}: expected ok result, got {result.code}`)
    end
    expectEqual(result.value, expected, label)
end

local function expectErrorCode(result: any, expectedCode: string, label: string)
    if result.ok ~= false then
        error(`{label}: expected error result`)
    end
    expectEqual(result.code, expectedCode, label)
end

local function run()
    local profile = ProfileSchema.createDefault(100)

    expectOkValue(InventoryDomain.add(profile, "item_wood", 10), 10, "add wood")
    expectEqual(profile.inventory.item_wood, 10, "add mutates inventory")

    expectOkValue(InventoryDomain.remove(profile, "item_wood", 4), 6, "remove wood")
    expectEqual(profile.inventory.item_wood, 6, "remove mutates inventory")

    expectErrorCode(InventoryDomain.add(profile, "item_unknown", 1), "invalid_request", "unknown item rejected")
    expectErrorCode(InventoryDomain.add(profile, "item_wood", 0), "invalid_request", "zero add rejected")
    expectErrorCode(InventoryDomain.add(profile, "item_wood", -1), "invalid_request", "negative add rejected")
    expectErrorCode(InventoryDomain.add(profile, "item_wood", 1.5), "invalid_request", "fractional add rejected")
    expectEqual(profile.inventory.item_wood, 6, "invalid add leaves balance")

    expectErrorCode(
        InventoryDomain.remove(profile, "item_wood", 7),
        "insufficient_resources",
        "insufficient remove rejected"
    )
    expectEqual(profile.inventory.item_wood, 6, "insufficient remove leaves balance")

    expectOkValue(InventoryDomain.remove(profile, "item_wood", 6), 0, "remove final wood")
    expectEqual(profile.inventory.item_wood, nil, "zero balance removed from inventory")

    profile.inventory.item_wood = 20
    profile.inventory.item_stone = 5
    expectEqual(InventoryDomain.canAfford(profile, { item_wood = 10, item_stone = 5 }), true, "affordable cost")
    expectEqual(InventoryDomain.canAfford(profile, { item_wood = 10, item_stone = 10 }), false, "unaffordable cost")

    local failedCost = InventoryDomain.applyCost(profile, { item_wood = 10, item_stone = 10 })
    expectErrorCode(failedCost, "insufficient_resources", "multi-item cost rejected")
    expectEqual(profile.inventory.item_wood, 20, "failed cost keeps wood")
    expectEqual(profile.inventory.item_stone, 5, "failed cost keeps stone")

    local invalidCost = InventoryDomain.applyCost(profile, { item_wood = 10, item_unknown = 1 })
    expectErrorCode(invalidCost, "invalid_request", "invalid cost rejected")
    expectEqual(profile.inventory.item_wood, 20, "invalid cost keeps wood")
    expectEqual(profile.inventory.item_stone, 5, "invalid cost keeps stone")

    local paidCost = InventoryDomain.applyCost(profile, { item_wood = 10, item_stone = 5 })
    expectOkValue(paidCost, true, "multi-item cost applied")
    expectEqual(profile.inventory.item_wood, 10, "cost consumes wood")
    expectEqual(profile.inventory.item_stone, nil, "cost removes zero stone balance")
end

return run
