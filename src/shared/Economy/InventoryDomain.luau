local ItemDefinitions = require("../Items/ItemDefinitions")

local function ok(value: any)
    return { ok = true, value = value }
end

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

local function isPositiveInteger(value: any): boolean
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value > 0
        and value % 1 == 0
end

local function isKnownItem(itemId: any): boolean
    return type(itemId) == "string" and ItemDefinitions.ById[itemId] ~= nil
end

local function validateCost(cost: any): boolean
    if type(cost) ~= "table" then
        return false
    end

    for itemId, quantity in pairs(cost) do
        if not isKnownItem(itemId) or not isPositiveInteger(quantity) then
            return false
        end
    end

    return true
end

local function add(profile: any, itemId: string, quantity: number)
    if type(profile) ~= "table" or type(profile.inventory) ~= "table" then
        return err("invalid_request", "profile inventory is invalid")
    end

    if not isKnownItem(itemId) or not isPositiveInteger(quantity) then
        return err("invalid_request", "item id and quantity must be valid")
    end

    local current = profile.inventory[itemId] or 0
    local nextBalance = current + quantity
    if not isPositiveInteger(nextBalance) then
        return err("invalid_request", "resulting inventory balance is invalid")
    end

    profile.inventory[itemId] = nextBalance
    return ok(nextBalance)
end

local function remove(profile: any, itemId: string, quantity: number)
    if type(profile) ~= "table" or type(profile.inventory) ~= "table" then
        return err("invalid_request", "profile inventory is invalid")
    end

    if not isKnownItem(itemId) or not isPositiveInteger(quantity) then
        return err("invalid_request", "item id and quantity must be valid")
    end

    local current = profile.inventory[itemId] or 0
    if current < quantity then
        return err("insufficient_resources", "insufficient item balance")
    end

    local nextBalance = current - quantity
    if nextBalance == 0 then
        profile.inventory[itemId] = nil
    else
        profile.inventory[itemId] = nextBalance
    end

    return ok(nextBalance)
end

local function canAfford(profile: any, cost: any): boolean
    if type(profile) ~= "table" or type(profile.inventory) ~= "table" or not validateCost(cost) then
        return false
    end

    for itemId, quantity in pairs(cost) do
        if (profile.inventory[itemId] or 0) < quantity then
            return false
        end
    end

    return true
end

local function applyCost(profile: any, cost: any)
    if type(profile) ~= "table" or type(profile.inventory) ~= "table" or not validateCost(cost) then
        return err("invalid_request", "cost is invalid")
    end

    if not canAfford(profile, cost) then
        return err("insufficient_resources", "insufficient resources for cost")
    end

    for itemId, quantity in pairs(cost) do
        local nextBalance = profile.inventory[itemId] - quantity
        if nextBalance == 0 then
            profile.inventory[itemId] = nil
        else
            profile.inventory[itemId] = nextBalance
        end
    end

    return ok(true)
end

return table.freeze({
    add = add,
    remove = remove,
    canAfford = canAfford,
    applyCost = applyCost,
})
