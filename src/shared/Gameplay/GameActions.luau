local ActionNames = require("../Net/ActionNames")
local ActionSchemas = require("../Net/ActionSchemas")
local PlacementDomain = require("../Buildings/PlacementDomain")
local UpgradeDomain = require("../Buildings/UpgradeDomain")
local WorkAssignmentDomain = require("../Creatures/WorkAssignmentDomain")
local CreatureOwnershipDomain = require("../Creatures/CreatureOwnershipDomain")
local ProductionDomain = require("../Economy/ProductionDomain")
local MarketDomain = require("../Economy/MarketDomain")
local BreedingDomain = require("../Creatures/BreedingDomain")
local BuildingDefinitions = require("../Buildings/BuildingDefinitions")

export type ActionContext = {
    now: number,
    generateId: () -> string,
    -- Whether a live feature flag is on. A missing function counts as off.
    isFeatureEnabled: ((name: string) -> boolean)?,
    -- A fresh seed in [0, 2^32) for randomness that must be fixed once rolled (eggs).
    randomSeed: (() -> number)?,
}

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

local function featureEnabled(context: ActionContext, name: string): boolean
    return context.isFeatureEnabled ~= nil and context.isFeatureEnabled(name) == true
end

-- Handlers receive a draft profile, a schema-sanitized payload and server-owned context.
-- They return a domain result; the action pipeline commits the draft only on success.
local handlers = {}

handlers[ActionNames.AssignCreature] = function(profile: any, payload: any, context: ActionContext)
    return WorkAssignmentDomain.assign(profile, payload.creatureId, payload.buildingId, context.now)
end

handlers[ActionNames.UnassignCreature] = function(
    profile: any,
    payload: any,
    context: ActionContext
)
    return WorkAssignmentDomain.unassign(profile, payload.creatureId, context.now)
end

handlers[ActionNames.ReleaseCreature] = function(
    profile: any,
    payload: any,
    _context: ActionContext
)
    return CreatureOwnershipDomain.release(profile, payload.creatureId)
end

handlers[ActionNames.PlaceBuilding] = function(profile: any, payload: any, context: ActionContext)
    local definition = BuildingDefinitions.ById[payload.definitionId]
    if
        definition ~= nil
        and definition.featureFlag ~= nil
        and not featureEnabled(context, definition.featureFlag)
    then
        return err("not_unlocked", `{definition.displayName} is not available yet`)
    end

    return PlacementDomain.place(
        profile,
        payload.definitionId,
        payload.cellX,
        payload.cellZ,
        payload.rotation,
        context.now,
        context.generateId
    )
end

handlers[ActionNames.UpgradeBuilding] = function(profile: any, payload: any, context: ActionContext)
    return UpgradeDomain.upgrade(profile, payload.buildingId, context.now)
end

handlers[ActionNames.RemoveBuilding] = function(profile: any, payload: any, context: ActionContext)
    return PlacementDomain.remove(profile, payload.buildingId, context.now)
end

handlers[ActionNames.ClaimProduction] = function(profile: any, payload: any, context: ActionContext)
    if payload.buildingId ~= nil then
        local settled = ProductionDomain.settle(profile, payload.buildingId, context.now)
        if settled.ok ~= true then
            return settled
        end
        if settled.value.cycles == 0 and settled.value.limitedBy == nil then
            return err("nothing_to_claim", "nothing is ready to claim yet")
        end
        return settled
    end

    local claimed = ProductionDomain.claimAll(profile, context.now)
    if claimed.ok ~= true then
        return claimed
    end

    local summary = claimed.value
    if summary.cycles == 0 and not summary.storageLimited and not summary.inputLimited then
        return err("nothing_to_claim", "nothing is ready to claim yet")
    end
    return claimed
end

handlers[ActionNames.StartBreeding] = function(profile: any, payload: any, context: ActionContext)
    if not featureEnabled(context, "breeding") then
        return err("not_unlocked", "breeding is not available yet")
    end
    if context.randomSeed == nil then
        return err("internal_error", "no random source for this action")
    end

    return BreedingDomain.start(
        profile,
        payload.creatureIdA,
        payload.creatureIdB,
        context.now,
        context.generateId(),
        context.randomSeed()
    )
end

-- Hatching stays available when the flag is switched off, so eggs already laid are never lost.
handlers[ActionNames.HatchEgg] = function(profile: any, payload: any, context: ActionContext)
    return BreedingDomain.hatch(profile, payload.eggId, context.now, context.generateId())
end

handlers[ActionNames.SellResource] = function(profile: any, payload: any, _context: ActionContext)
    return MarketDomain.sell(profile, payload.itemId, payload.quantity)
end

for _, actionName in pairs(ActionNames) do
    if ActionSchemas.scopeFor(actionName) == "profile" then
        assert(handlers[actionName] ~= nil, `Missing action handler for {actionName}`)
    else
        assert(handlers[actionName] == nil, `{actionName} is a session action`)
    end
end

return table.freeze({
    handlers = table.freeze(handlers),
})
