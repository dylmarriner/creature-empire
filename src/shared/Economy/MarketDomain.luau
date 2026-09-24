local GameConfig = require("../Config/GameConfig")
local ItemDefinitions = require("../Items/ItemDefinitions")
local InventoryDomain = require("./InventoryDomain")
local CurrencyDomain = require("./CurrencyDomain")
local NumberUtil = require("../Util/NumberUtil")

local function ok(value: any)
    return { ok = true, value = value }
end

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

-- Sells resources for coins at canonical prices. Prices never come from the caller.
local function sell(profile: any, itemId: any, quantity: any)
    if
        type(profile) ~= "table"
        or type(profile.inventory) ~= "table"
        or type(profile.currencies) ~= "table"
    then
        return err("invalid_request", "profile is invalid")
    end

    local definition = if type(itemId) == "string" then ItemDefinitions.ById[itemId] else nil
    if definition == nil or not NumberUtil.isPositiveInteger(definition.sellPrice) then
        return err("invalid_request", "item cannot be sold")
    end

    if not NumberUtil.isPositiveInteger(quantity) or quantity > GameConfig.MAX_SELL_QUANTITY then
        return err("invalid_request", "sell quantity is invalid")
    end

    local coins = profile.currencies.coins
    local earned = definition.sellPrice * quantity
    if not NumberUtil.isNonNegativeInteger(coins) or not NumberUtil.isInteger(coins + earned) then
        return err("invalid_request", "currency balance is invalid")
    end

    local removed = InventoryDomain.remove(profile, itemId, quantity)
    if removed.ok ~= true then
        return removed
    end

    local added = CurrencyDomain.add(profile, "coins", earned)
    if added.ok ~= true then
        return added
    end

    return ok({ itemId = itemId, quantity = quantity, coins = earned })
end

return table.freeze({
    sell = sell,
})
