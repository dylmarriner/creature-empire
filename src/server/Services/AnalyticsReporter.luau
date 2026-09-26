--[[
    Forwards gameplay telemetry to Roblox AnalyticsService: the onboarding funnel (first
    join and each objective) and coin sources/sinks. Events are derived by the pure
    Shared.Gameplay.AnalyticsEvents module; this adapter only maps them to engine calls.
    Analytics failures are logged and never affect gameplay.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnalyticsEvents = require(Shared.Gameplay.AnalyticsEvents)

local Logger = require("./Logger")

local logger = Logger.new("Analytics")

local FLOW_TYPES = {
    Source = Enum.AnalyticsEconomyFlowType.Source,
    Sink = Enum.AnalyticsEconomyFlowType.Sink,
}

local TRANSACTION_TYPES = {
    Gameplay = Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
    Onboarding = Enum.AnalyticsEconomyTransactionType.Onboarding.Name,
}

local AnalyticsReporter = {}

local function send(player: Player, event: AnalyticsEvents.Event)
    if event.kind == "funnel" then
        AnalyticsService:LogOnboardingFunnelStepEvent(player, event.step, event.name)
    else
        AnalyticsService:LogEconomyEvent(
            player,
            FLOW_TYPES[event.flow],
            event.currency,
            event.amount,
            event.endingBalance,
            TRANSACTION_TYPES[event.transactionType],
            event.itemSku
        )
    end
end

-- Reports every event implied by a committed profile change.
function AnalyticsReporter.reportCommit(
    player: Player,
    previous: any,
    profile: any,
    completedObjectives: { string }
)
    for _, event in ipairs(AnalyticsEvents.fromCommit(previous, profile, completedObjectives)) do
        local ok, failure = pcall(send :: any, player, event)
        if not ok then
            logger.warn("analytics event failed", {
                userId = player.UserId,
                kind = event.kind,
                detail = tostring(failure),
            })
        end
    end
end

return AnalyticsReporter
