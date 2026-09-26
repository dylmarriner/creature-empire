--[[
    Server bootstrap. Wires the server-authoritative services together:

        NetworkService.createRemotes   remote contract exists before anything else runs
        PlayerDataService              session-locked load/save of player profiles
        ActionService                  transactional profile mutation + commit fan-out
        NetworkService                 validated, rate-limited client actions
        PlotService                    plot allocation and building rendering
        WorldService                   the Wilds: gathering nodes and wild creatures
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ItemDefinitions = require(Shared.Items.ItemDefinitions)
local CreatureDefinitions = require(Shared.Creatures.CreatureDefinitions)
local CreatureOwnershipDomain = require(Shared.Creatures.CreatureOwnershipDomain)
local BuildingDefinitions = require(Shared.Buildings.BuildingDefinitions)
local ProductionMath = require(Shared.Economy.ProductionMath)
local ObjectiveDefinitions = require(Shared.Progression.ObjectiveDefinitions)
local ActionNames = require(Shared.Net.ActionNames)
local WorldLayout = require(Shared.World.WorldLayout)

local Logger = require("@self/Services/Logger")
local PlayerDataService = require("@self/Services/PlayerDataService")
local ActionService = require("@self/Services/ActionService")
local NetworkService = require("@self/Services/NetworkService")
local PlotService = require("@self/Services/PlotService")
local WorldService = require("@self/Services/WorldService")
local LeaderboardService = require("@self/Services/LeaderboardService")
local AnalyticsReporter = require("@self/Services/AnalyticsReporter")

assert(
    #ItemDefinitions.Ids == GameConfig.INITIAL_RESOURCE_COUNT,
    "resource definition count mismatch"
)
assert(
    #CreatureDefinitions.Ids == GameConfig.INITIAL_CREATURE_COUNT,
    "creature definition count mismatch"
)
assert(
    #BuildingDefinitions.Ids == GameConfig.INITIAL_BUILDING_COUNT,
    "building definition count mismatch"
)
assert(
    ProductionMath.DEFAULT_OFFLINE_CAP_SECONDS == GameConfig.OFFLINE_PRODUCTION_CAP_SECONDS,
    "offline production cap mismatch"
)

local logger = Logger.new("Server")

-- Authoritative server clock: whole UTC seconds.
local function now(): number
    return os.time()
end

local remotes = NetworkService.createRemotes()

local plotService = PlotService.new()
local network: NetworkService.NetworkService
local actionService: ActionService.ActionService
local playerData: PlayerDataService.PlayerDataService

playerData = PlayerDataService.new({
    clock = now,
    onLoaded = function(player: Player)
        plotService:assign(player)

        -- Join-time grant runs through the same transactional pipeline as every action.
        local profile = playerData:getProfile(player)
        if profile.unlocks[CreatureOwnershipDomain.STARTER_UNLOCK_ID] ~= true then
            local result = actionService:mutate(player, "GrantStarter", function(draft)
                return CreatureOwnershipDomain.grantStarter(draft, function()
                    return actionService:generateId("c")
                end)
            end)
            if result.ok then
                network:notify(player, "gain", "A Rockhorn has joined your empire!")
            end
        end

        local loaded = playerData:getProfile(player)
        LeaderboardService.update(player, loaded)
        plotService:render(player, loaded)
        network:sendSnapshot(player, loaded)
        player:SetAttribute("ProfileLoaded", true)
    end,
    onReleased = function(player: Player)
        plotService:release(player)
    end,
})

actionService = ActionService.new({ playerData = playerData, clock = now })
network = NetworkService.new({
    remotes = remotes,
    actionService = actionService,
    playerData = playerData,
})

actionService:onCommitted(
    function(player: Player, profile: any, context: ActionService.CommitContext)
        plotService:render(player, profile)
        network:sendSnapshot(player, profile)
        LeaderboardService.update(player, profile)
        AnalyticsReporter.reportCommit(
            player,
            context.previous,
            profile,
            context.completedObjectives
        )
        for _, objectiveId in ipairs(context.completedObjectives) do
            local objective = ObjectiveDefinitions.ById[objectiveId]
            if objective ~= nil then
                network:notify(
                    player,
                    "objective",
                    `Objective complete: {objective.title} (+{objective.rewardCoins} coins)`
                )
            end
        end
    end
)

network:setSessionHandler(ActionNames.Travel, function(player: Player, payload: any)
    if not playerData:isLoaded(player) then
        return { ok = false, code = "not_ready", message = "your profile is still loading" }
    end

    if payload.destination == "home" then
        if plotService:sendHome(player) then
            return { ok = true }
        end
    elseif payload.destination == "plot" then
        local host = if payload.targetUserId ~= nil
            then Players:GetPlayerByUserId(payload.targetUserId)
            else nil
        if host == nil or host == player then
            return {
                ok = false,
                code = "invalid_request",
                message = "that empire isn't here right now",
            }
        end
        if plotService:sendToPlotOf(player, host) then
            return { ok = true }
        end
    else
        local character = player.Character
        if character ~= nil then
            local center = WorldLayout.WILDS_CENTER
            local entrance = Vector3.new(center.x, 4, center.z + WorldLayout.WILDS_RADIUS - 12)
            character:PivotTo(CFrame.lookAt(entrance, entrance + Vector3.new(0, 0, -1)))
            return { ok = true }
        end
    end

    return { ok = false, code = "not_ready", message = "you can't travel right now" }
end)

local worldService = WorldService.new({ actionService = actionService, network = network })

network:start()
plotService:start()
worldService:start()
playerData:start()

logger.info("server started", {
    memoryStore = playerData.usingMemoryStore,
    objectives = #ObjectiveDefinitions.Ordered,
})
