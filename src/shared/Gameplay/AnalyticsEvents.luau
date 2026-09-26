local ObjectiveDefinitions = require("../Progression/ObjectiveDefinitions")
local CreatureOwnershipDomain = require("../Creatures/CreatureOwnershipDomain")
local ItemDefinitions = require("../Items/ItemDefinitions")
local TableUtil = require("../Util/TableUtil")

--[[
    Derives analytics events from a committed profile change. Pure and deterministic: the
    server adapter only forwards the returned descriptors to Roblox AnalyticsService.

    Onboarding funnel: step 1 is the first join (starter grant); objective N is step N + 1.
    Economy: coin sources and sinks, split into objective rewards (Onboarding) and the
    action's own net coin change (Gameplay), tagged with the item or building involved.
]]

export type FunnelEvent = { kind: "funnel", step: number, name: string }
export type EconomyEvent = {
    kind: "economy",
    flow: "Source" | "Sink",
    currency: string,
    amount: number,
    endingBalance: number,
    transactionType: "Gameplay" | "Onboarding",
    itemSku: string?,
}
export type Event = FunnelEvent | EconomyEvent

local COIN_CURRENCY = "coins"

local function coinsOf(profile: any): number
    if type(profile) == "table" and type(profile.currencies) == "table" then
        local coins = profile.currencies.coins
        if type(coins) == "number" then
            return coins
        end
    end
    return 0
end

-- What the player's coins were exchanged for: an upgraded building (upgrades also spend
-- items, so buildings are checked first), otherwise the first item whose balance fell.
local function itemSkuFor(before: any, after: any): string?
    for _, buildingId in ipairs(TableUtil.sortedKeys(after.buildings)) do
        local previous = before.buildings[buildingId]
        local current = after.buildings[buildingId]
        if previous ~= nil and current.level > previous.level then
            return current.definitionId
        end
    end
    for _, itemId in ipairs(ItemDefinitions.Ids) do
        local previous = before.inventory[itemId] or 0
        local current = after.inventory[itemId] or 0
        if current < previous then
            return itemId
        end
    end
    return nil
end

local function fromCommit(before: any, after: any, completedObjectives: { string }): { Event }
    local events: { Event } = {}

    local starterBefore = before.unlocks[CreatureOwnershipDomain.STARTER_UNLOCK_ID] == true
    local starterAfter = after.unlocks[CreatureOwnershipDomain.STARTER_UNLOCK_ID] == true
    if starterAfter and not starterBefore then
        table.insert(events, { kind = "funnel", step = 1, name = "Joined" } :: Event)
    end

    local objectiveCoins = 0
    for _, objectiveId in ipairs(completedObjectives) do
        local objective = ObjectiveDefinitions.ById[objectiveId]
        if objective ~= nil then
            table.insert(
                events,
                {
                    kind = "funnel",
                    step = objective.order + 1,
                    name = objective.title,
                } :: Event
            )
            objectiveCoins += objective.rewardCoins
        end
    end

    local coinsBefore = coinsOf(before)
    local coinsAfter = coinsOf(after)
    local actionDelta = coinsAfter - coinsBefore - objectiveCoins

    -- Order the balances as they happened: the action first, then objective rewards.
    local afterAction = coinsBefore + actionDelta
    if actionDelta ~= 0 then
        table.insert(
            events,
            {
                kind = "economy",
                flow = if actionDelta > 0 then "Source" else "Sink",
                currency = COIN_CURRENCY,
                amount = math.abs(actionDelta),
                endingBalance = afterAction,
                transactionType = "Gameplay",
                itemSku = itemSkuFor(before, after),
            } :: Event
        )
    end

    if objectiveCoins > 0 then
        table.insert(
            events,
            {
                kind = "economy",
                flow = "Source",
                currency = COIN_CURRENCY,
                amount = objectiveCoins,
                endingBalance = coinsAfter,
                transactionType = "Onboarding",
                itemSku = nil,
            } :: Event
        )
    end

    return events
end

return table.freeze({
    fromCommit = fromCommit,
})
