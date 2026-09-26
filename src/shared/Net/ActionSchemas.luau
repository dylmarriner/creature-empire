local GameConfig = require("../Config/GameConfig")
local ActionNames = require("./ActionNames")
local NumberUtil = require("../Util/NumberUtil")
local TableUtil = require("../Util/TableUtil")

local MAX_ID_LENGTH = 64
local MAX_REQUEST_ID = 2 ^ 31 - 1
local MAX_USER_ID = 2 ^ 53 - 1

local function idField(name: string, optional: boolean?)
    return { name = name, kind = "id", optional = optional == true }
end

local function integerField(name: string, min: number, max: number, optional: boolean?)
    return { name = name, kind = "integer", min = min, max = max, optional = optional == true }
end

local function enumField(name: string, values: { string })
    local allowed = {}
    for _, value in ipairs(values) do
        allowed[value] = true
    end
    return { name = name, kind = "enum", allowed = allowed, optional = false }
end

-- Payload shape per action. `rate` is a token bucket: `burst` requests at once, refilled at
-- `perSecond`. `scope` is "profile" for actions that mutate the profile through GameActions
-- and "session" for actions the server handles without touching the profile.
local schemas = {
    [ActionNames.AssignCreature] = {
        fields = { idField("creatureId"), idField("buildingId") },
        rate = { burst = 8, perSecond = 4 },
        scope = "profile",
    },
    [ActionNames.UnassignCreature] = {
        fields = { idField("creatureId") },
        rate = { burst = 8, perSecond = 4 },
        scope = "profile",
    },
    [ActionNames.ReleaseCreature] = {
        fields = { idField("creatureId") },
        rate = { burst = 4, perSecond = 1 },
        scope = "profile",
    },
    [ActionNames.PlaceBuilding] = {
        fields = {
            idField("definitionId"),
            integerField("cellX", 0, GameConfig.PLOT_SIZE_CELLS),
            integerField("cellZ", 0, GameConfig.PLOT_SIZE_CELLS),
            integerField("rotation", 0, 270),
        },
        rate = { burst = 5, perSecond = 2 },
        scope = "profile",
    },
    [ActionNames.UpgradeBuilding] = {
        fields = { idField("buildingId") },
        rate = { burst = 5, perSecond = 2 },
        scope = "profile",
    },
    [ActionNames.RemoveBuilding] = {
        fields = { idField("buildingId") },
        rate = { burst = 4, perSecond = 1 },
        scope = "profile",
    },
    [ActionNames.ClaimProduction] = {
        fields = { idField("buildingId", true) },
        rate = { burst = 5, perSecond = 2 },
        scope = "profile",
    },
    [ActionNames.SellResource] = {
        fields = { idField("itemId"), integerField("quantity", 1, GameConfig.MAX_SELL_QUANTITY) },
        rate = { burst = 10, perSecond = 4 },
        scope = "profile",
    },
    [ActionNames.RequestSync] = {
        fields = {},
        rate = { burst = 3, perSecond = 0.5 },
        scope = "session",
    },
    [ActionNames.Travel] = {
        -- "plot" visits another player's plot and requires targetUserId.
        fields = {
            enumField("destination", { "home", "wilds", "plot" }),
            integerField("targetUserId", 1, MAX_USER_ID, true),
        },
        rate = { burst = 1, perSecond = 0.25 },
        scope = "session",
    },
}

for _, actionName in pairs(ActionNames) do
    assert(schemas[actionName] ~= nil, `Missing action schema for {actionName}`)
end

local function isValidId(value: any): boolean
    return type(value) == "string"
        and #value > 0
        and #value <= MAX_ID_LENGTH
        and string.match(value, "^[%w_%-]+$") ~= nil
end

local function isValidRequestId(value: any): boolean
    return NumberUtil.isNonNegativeInteger(value) and value <= MAX_REQUEST_ID
end

-- Validates an untrusted remote payload. Returns (true, sanitizedPayload) or (false, reason).
-- The sanitized payload is a fresh table containing only declared fields.
local function validate(actionName: any, payload: any): (boolean, any)
    local schema = if type(actionName) == "string" then schemas[actionName] else nil
    if schema == nil then
        return false, "unknown action"
    end

    if payload == nil then
        payload = {}
    end
    if type(payload) ~= "table" then
        return false, "payload must be a table"
    end

    local declared = {}
    for _, field in ipairs(schema.fields) do
        declared[field.name] = field
    end

    for key in pairs(payload) do
        if type(key) ~= "string" or declared[key] == nil then
            return false, "payload contains an unexpected field"
        end
    end

    local sanitized = {}
    for _, field in ipairs(schema.fields) do
        local value = payload[field.name]
        if value == nil then
            if not field.optional then
                return false, `{field.name} is required`
            end
        elseif field.kind == "id" then
            if not isValidId(value) then
                return false, `{field.name} must be a valid id`
            end
            sanitized[field.name] = value
        elseif field.kind == "integer" then
            if not NumberUtil.isInteger(value) or value < field.min or value > field.max then
                return false, `{field.name} must be an integer in range`
            end
            sanitized[field.name] = value
        elseif field.kind == "enum" then
            if type(value) ~= "string" or field.allowed[value] ~= true then
                return false, `{field.name} is not an allowed value`
            end
            sanitized[field.name] = value
        end
    end

    return true, sanitized
end

local function rateFor(actionName: string)
    local schema = schemas[actionName]
    return if schema ~= nil then schema.rate else nil
end

local function scopeFor(actionName: string): string?
    local schema = schemas[actionName]
    return if schema ~= nil then schema.scope else nil
end

return TableUtil.deepFreeze({
    MAX_ID_LENGTH = MAX_ID_LENGTH,
    isValidId = isValidId,
    isValidRequestId = isValidRequestId,
    validate = validate,
    rateFor = rateFor,
    scopeFor = scopeFor,
})
