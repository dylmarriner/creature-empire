local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local BuildingCostDomain = require("../../src/shared/Economy/BuildingCostDomain")

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
    profile.inventory.item_wood = 20
    profile.inventory.item_stone = 30

    expectOkValue(BuildingCostDomain.canAfford(profile, "building_mine"), true, "mine is affordable")
    expectOkValue(BuildingCostDomain.purchase(profile, "building_mine"), true, "purchase mine")
    expectEqual(profile.inventory.item_wood, nil, "mine consumes exactly 20 wood")
    expectEqual(profile.inventory.item_stone, nil, "mine consumes exactly 30 stone")

    profile.inventory.item_wood = 20
    profile.inventory.item_stone = 29
    expectOkValue(BuildingCostDomain.canAfford(profile, "building_mine"), false, "mine is unaffordable")

    local failedPurchase = BuildingCostDomain.purchase(profile, "building_mine")
    expectErrorCode(failedPurchase, "insufficient_resources", "unaffordable mine rejected")
    expectEqual(profile.inventory.item_wood, 20, "failed purchase keeps wood")
    expectEqual(profile.inventory.item_stone, 29, "failed purchase keeps stone")

    local unknown = BuildingCostDomain.purchase(profile, "building_unknown")
    expectErrorCode(unknown, "invalid_request", "unknown building rejected")
    expectEqual(profile.inventory.item_wood, 20, "unknown building leaves wood")
    expectEqual(profile.inventory.item_stone, 29, "unknown building leaves stone")
end

return run
