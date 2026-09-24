local GameConfig = require("../Config/GameConfig")
local BuildingDefinitions = require("./BuildingDefinitions")
local CapacityDomain = require("../Economy/CapacityDomain")
local InventoryDomain = require("../Economy/InventoryDomain")
local CurrencyDomain = require("../Economy/CurrencyDomain")
local ProductionDomain = require("../Economy/ProductionDomain")
local NumberUtil = require("../Util/NumberUtil")

local function ok(value: any)
    return { ok = true, value = value }
end

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

-- Canonical cost of raising a building to `targetLevel`.
-- Items scale geometrically from the base build cost; energy is required from
-- UPGRADE_ENERGY_FROM_LEVEL onwards; coins scale quadratically.
local function costFor(definitionId: any, targetLevel: any)
    local definition = if type(definitionId) == "string"
        then BuildingDefinitions.ById[definitionId]
        else nil
    if
        definition == nil
        or not NumberUtil.isInteger(targetLevel)
        or targetLevel < 2
        or targetLevel > GameConfig.MAX_BUILDING_LEVEL
    then
        return nil
    end

    local growth = GameConfig.UPGRADE_ITEM_COST_GROWTH ^ (targetLevel - 1)
    local items = {}
    for itemId, quantity in pairs(definition.cost) do
        items[itemId] = math.ceil(quantity * growth - 1e-9)
    end

    if targetLevel >= GameConfig.UPGRADE_ENERGY_FROM_LEVEL then
        local energy = GameConfig.UPGRADE_ENERGY_COST_PER_LEVEL
            * (targetLevel - GameConfig.UPGRADE_ENERGY_FROM_LEVEL + 1)
        items.item_energy = (items.item_energy or 0) + energy
    end

    local coins = GameConfig.UPGRADE_COIN_COST_BASE * (targetLevel - 1) ^ 2

    return { items = items, coins = coins }
end

local function canPay(profile: any, cost: any): boolean
    return InventoryDomain.canAfford(profile, cost.items)
        and type(profile.currencies) == "table"
        and NumberUtil.isNonNegativeInteger(profile.currencies.coins)
        and profile.currencies.coins >= cost.coins
end

local function upgrade(profile: any, buildingId: any, now: number)
    if type(profile) ~= "table" or type(profile.buildings) ~= "table" then
        return err("invalid_request", "profile buildings are invalid")
    end

    local building = if type(buildingId) == "string" then profile.buildings[buildingId] else nil
    if type(building) ~= "table" then
        return err("building_not_owned", "building is not owned by this profile")
    end

    local definition = BuildingDefinitions.ById[building.definitionId]
    if definition == nil or not NumberUtil.isPositiveInteger(building.level) then
        return err("invalid_request", "owned building record is invalid")
    end

    if building.level >= GameConfig.MAX_BUILDING_LEVEL then
        return err("max_level_reached", "building is already at maximum level")
    end

    if not CapacityDomain.hasUtility(profile, "workbench") then
        return err("not_unlocked", "build a Workbench to unlock upgrades")
    end

    local targetLevel = building.level + 1
    local cost = costFor(building.definitionId, targetLevel)
    if cost == nil then
        return err("invalid_request", "upgrade cost is unavailable")
    end

    if not canPay(profile, cost) then
        return err("insufficient_resources", "not enough resources to upgrade")
    end

    -- Production earned at the old level is settled before the rate changes. Settlement can
    -- consume processing inputs, so affordability is checked again afterwards.
    local settled = ProductionDomain.settle(profile, buildingId, now)
    if settled.ok ~= true then
        return settled
    end

    if not canPay(profile, cost) then
        return err("insufficient_resources", "not enough resources to upgrade")
    end

    local paid = InventoryDomain.applyCost(profile, cost.items)
    if paid.ok ~= true then
        return paid
    end

    if cost.coins > 0 then
        local spent = CurrencyDomain.spend(profile, "coins", cost.coins)
        if spent.ok ~= true then
            return spent
        end
    end

    building.level = targetLevel
    return ok({ level = targetLevel, cost = cost })
end

return table.freeze({
    costFor = costFor,
    upgrade = upgrade,
})
