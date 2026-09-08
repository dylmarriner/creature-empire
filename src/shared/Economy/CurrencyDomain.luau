local VALID_CURRENCIES = table.freeze({
    coins = true,
    gems = true,
})

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

local function isNonNegativeInteger(value: any): boolean
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value >= 0
        and value % 1 == 0
end

local function validateTarget(profile: any, currencyId: any)
    if type(profile) ~= "table" or type(profile.currencies) ~= "table" then
        return false, "invalid_request", "profile currencies are invalid"
    end

    if type(currencyId) ~= "string" or VALID_CURRENCIES[currencyId] ~= true then
        return false, "unknown_currency", "currency id is unknown"
    end

    if not isNonNegativeInteger(profile.currencies[currencyId]) then
        return false, "invalid_request", "currency balance is invalid"
    end

    return true
end

local function add(profile: any, currencyId: string, amount: number)
    local valid, code, message = validateTarget(profile, currencyId)
    if not valid then
        return err(code, message)
    end

    if not isPositiveInteger(amount) then
        return err("invalid_request", "amount must be a positive integer")
    end

    local nextBalance = profile.currencies[currencyId] + amount
    if not isNonNegativeInteger(nextBalance) then
        return err("invalid_request", "resulting currency balance is invalid")
    end

    profile.currencies[currencyId] = nextBalance
    return ok(nextBalance)
end

local function spend(profile: any, currencyId: string, amount: number)
    local valid, code, message = validateTarget(profile, currencyId)
    if not valid then
        return err(code, message)
    end

    if not isPositiveInteger(amount) then
        return err("invalid_request", "amount must be a positive integer")
    end

    local current = profile.currencies[currencyId]
    if current < amount then
        return err("insufficient_currency", "insufficient currency balance")
    end

    local nextBalance = current - amount
    profile.currencies[currencyId] = nextBalance
    return ok(nextBalance)
end

return table.freeze({
    add = add,
    spend = spend,
})
