local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local InventoryDomain = require("../../src/shared/Economy/InventoryDomain")

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

local function run()
    local profile = ProfileSchema.createDefault(100)
    profile.inventory.item_copper_ore = 20

    local exchange = InventoryDomain.applyTransaction(
        profile,
        { item_copper_ore = 10 },
        { item_copper_bar = 10 }
    )
    expectOk(exchange, "valid exchange")
    expectEqual(profile.inventory.item_copper_ore, 10, "ore removed")
    expectEqual(profile.inventory.item_copper_bar, 10, "bars added")

    local insufficientProfile = ProfileSchema.createDefault(100)
    insufficientProfile.inventory.item_copper_ore = 5
    local insufficient = InventoryDomain.applyTransaction(
        insufficientProfile,
        { item_copper_ore = 10 },
        { item_copper_bar = 10 }
    )
    expectErrorCode(insufficient, "insufficient_resources", "insufficient removal rejected")
    expectEqual(insufficientProfile.inventory.item_copper_ore, 5, "insufficient removal unchanged")
    expectEqual(insufficientProfile.inventory.item_copper_bar, nil, "insufficient addition absent")

    local unknownAdditionProfile = ProfileSchema.createDefault(100)
    unknownAdditionProfile.inventory.item_copper_ore = 20
    local unknownAddition = InventoryDomain.applyTransaction(
        unknownAdditionProfile,
        { item_copper_ore = 10 },
        { item_unknown = 10 }
    )
    expectErrorCode(unknownAddition, "invalid_request", "unknown addition rejected")
    expectEqual(unknownAdditionProfile.inventory.item_copper_ore, 20, "unknown addition removal unchanged")
    expectEqual(unknownAdditionProfile.inventory.item_unknown, nil, "unknown addition not written")

    local invalidBalanceProfile = ProfileSchema.createDefault(100)
    invalidBalanceProfile.inventory.item_copper_ore = 20
    invalidBalanceProfile.inventory.item_copper_bar = -1
    local invalidBalance = InventoryDomain.applyTransaction(
        invalidBalanceProfile,
        { item_copper_ore = 10 },
        { item_copper_bar = 10 }
    )
    expectErrorCode(invalidBalance, "invalid_request", "invalid output balance rejected")
    expectEqual(invalidBalanceProfile.inventory.item_copper_ore, 20, "invalid output removal unchanged")
    expectEqual(invalidBalanceProfile.inventory.item_copper_bar, -1, "invalid output balance unchanged")

    local sameItemProfile = ProfileSchema.createDefault(100)
    sameItemProfile.inventory.item_copper_ore = 20
    local sameItem = InventoryDomain.applyTransaction(
        sameItemProfile,
        { item_copper_ore = 7 },
        { item_copper_ore = 3 }
    )
    expectOk(sameItem, "same item transaction")
    expectEqual(sameItemProfile.inventory.item_copper_ore, 16, "same item final balance")
end

return run
