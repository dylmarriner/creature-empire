--[[
    ActionService is the single entry point for mutating a player's profile.

    Every mutation - remote actions, world interactions, join-time grants - runs through the
    transactional ActionPipeline against a copy of the profile. Only a validated commit
    replaces the session profile, after which subscribers (network replication, plot
    rendering) are notified.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActionPipeline = require(Shared.Gameplay.ActionPipeline)
local ObjectiveDefinitions = require(Shared.Progression.ObjectiveDefinitions)

local Logger = require("./Logger")

local logger = Logger.new("Actions")

-- `previous` is the profile before the commit; listeners must treat both as read-only.
export type CommitContext = {
    label: string,
    previous: any,
    completedObjectives: { string },
}
export type CommitListener = (player: Player, profile: any, context: CommitContext) -> ()

local ActionService = {}
ActionService.__index = ActionService

export type ActionService = typeof(setmetatable(
    {} :: {
        _playerData: any,
        _clock: () -> number,
        _listeners: { CommitListener },
    },
    ActionService
))

function ActionService.new(options: { playerData: any, clock: () -> number }): ActionService
    return setmetatable({
        _playerData = options.playerData,
        _clock = options.clock,
        _listeners = {},
    }, ActionService)
end

function ActionService.getProfile(self: ActionService, player: Player): any
    return self._playerData:getProfile(player)
end

function ActionService.now(self: ActionService): number
    return self._clock()
end

function ActionService.generateId(_self: ActionService, prefix: string): string
    local guid = string.lower(HttpService:GenerateGUID(false))
    return `{prefix}_{guid}`
end

function ActionService.onCommitted(self: ActionService, listener: CommitListener)
    table.insert(self._listeners, listener)
end

-- Runs `mutate(draft)` for `player`. Returns the domain result table.
function ActionService.mutate(
    self: ActionService,
    player: Player,
    label: string,
    mutate: (draft: any) -> any
)
    local profile = self._playerData:getProfile(player)
    if profile == nil then
        return { ok = false, code = "not_ready", message = "your profile is still loading" }
    end

    local outcome = ActionPipeline.run(profile, mutate)
    if outcome.failure ~= nil then
        logger.error("action failed unexpectedly", {
            action = label,
            userId = player.UserId,
            detail = outcome.failure,
        })
    end

    if outcome.committed then
        if not self._playerData:setProfile(player, outcome.profile) then
            -- The session is being saved and released; a commit now could never persist.
            return { ok = false, code = "not_ready", message = "your profile is being saved" }
        end
        for _, objectiveId in ipairs(outcome.completedObjectives) do
            local objective = ObjectiveDefinitions.ById[objectiveId]
            logger.info("objective completed", {
                userId = player.UserId,
                objective = objectiveId,
                order = if objective ~= nil then objective.order else -1,
            })
        end
        for _, listener in ipairs(self._listeners) do
            local ok, listenerError = pcall(listener :: any, player, outcome.profile, {
                label = label,
                previous = profile,
                completedObjectives = outcome.completedObjectives,
            })
            if not ok then
                logger.error(
                    "commit listener failed",
                    { action = label, detail = tostring(listenerError) }
                )
            end
        end
    end

    return outcome.result
end

return ActionService
