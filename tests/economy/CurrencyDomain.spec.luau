local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local CurrencyDomain = require("../../src/shared/Economy/CurrencyDomain")

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

    expectOkValue(CurrencyDomain.add(profile, "coins", 50), 50, "earn coins")
    expectEqual(profile.currencies.coins, 50, "earning mutates coins")

    expectOkValue(CurrencyDomain.spend(profile, "coins", 20), 30, "spend coins")
    expectEqual(profile.currencies.coins, 30, "spending mutates coins")

    expectOkValue(CurrencyDomain.add(profile, "gems", 5), 5, "earn gems")
    expectEqual(profile.currencies.gems, 5, "earning mutates gems")

    local overspend = CurrencyDomain.spend(profile, "coins", 100)
    expectErrorCode(overspend, "insufficient_currency", "overspend rejected")
    expectEqual(profile.currencies.coins, 30, "overspend leaves coins")

    expectErrorCode(CurrencyDomain.add(profile, "credits", 1), "unknown_currency", "unknown currency rejected")
    expectErrorCode(CurrencyDomain.add(profile, "coins", 0), "invalid_request", "zero earn rejected")
    expectErrorCode(CurrencyDomain.add(profile, "coins", -1), "invalid_request", "negative earn rejected")
    expectErrorCode(CurrencyDomain.spend(profile, "coins", 1.5), "invalid_request", "fractional spend rejected")
    expectEqual(profile.currencies.coins, 30, "invalid requests leave coins")
end

return run
