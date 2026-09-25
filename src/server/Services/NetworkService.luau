--[[
    NetworkService owns every RemoteEvent. Client requests pass, in order, through
    request-id validation, per-player rate limits, strict payload schemas and the
    transactional ActionService. Clients never send balances, prices, rates or rewards.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActionNames = require(Shared.Net.ActionNames)
local RemoteNames = require(Shared.Net.RemoteNames)
local ActionSchemas = require(Shared.Net.ActionSchemas)
local RateLimiter = require(Shared.Net.RateLimiter)
local GameActions = require(Shared.Gameplay.GameActions)
local Snapshot = require(Shared.Gameplay.Snapshot)

local Logger = require("./Logger")

local logger = Logger.new("Network")

local GLOBAL_BURST = 30
local GLOBAL_PER_SECOND = 10
local ID_PREFIX_BY_ACTION = {
    [ActionNames.PlaceBuilding] = "b",
}

local NetworkService = {}
NetworkService.__index = NetworkService

export type SessionHandler = (
    player: Player,
    payload: any
) -> { ok: boolean, code: string?, message: string? }

export type NetworkService = typeof(setmetatable(
    {} :: {
        _remotes: Folder,
        _actionService: any,
        _playerData: any,
        _limiter: RateLimiter.RateLimiter,
        _rejections: { [Player]: number },
        _sessionHandlers: { [string]: SessionHandler },
    },
    NetworkService
))

local function ensureRemote(folder: Folder, name: string): RemoteEvent
    local existing = folder:FindFirstChild(name)
    if existing ~= nil then
        assert(existing:IsA("RemoteEvent"), `{name} must be a RemoteEvent`)
        return existing
    end
    local remote = Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = folder
    return remote
end

-- Creates the Remotes folder and every RemoteEvent. Called before any other service starts
-- so clients waiting on the contract never time out.
function NetworkService.createRemotes(): Folder
    local folder = ReplicatedStorage:FindFirstChild("Remotes")
    if folder == nil then
        folder = Instance.new("Folder")
        folder.Name = "Remotes"
        folder.Parent = ReplicatedStorage
    end
    assert(folder:IsA("Folder"), "Remotes must be a Folder")

    for _, actionName in pairs(ActionNames) do
        ensureRemote(folder, actionName)
    end
    for _, remoteName in pairs(RemoteNames) do
        ensureRemote(folder, remoteName)
    end

    return folder
end

function NetworkService.new(
    options: { remotes: Folder, actionService: any, playerData: any }
): NetworkService
    return setmetatable({
        _remotes = options.remotes,
        _actionService = options.actionService,
        _playerData = options.playerData,
        _limiter = RateLimiter.new(os.clock),
        _rejections = {},
        _sessionHandlers = {},
    }, NetworkService)
end

-- Registers the handler for an action whose schema scope is "session".
function NetworkService.setSessionHandler(
    self: NetworkService,
    actionName: string,
    handler: SessionHandler
)
    assert(ActionSchemas.scopeFor(actionName) == "session", `{actionName} is not a session action`)
    self._sessionHandlers[actionName] = handler
end

function NetworkService._remote(self: NetworkService, name: string): RemoteEvent
    return self._remotes:FindFirstChild(name) :: RemoteEvent
end

local function publicResult(result: any)
    return {
        ok = result.ok == true,
        code = result.code,
        message = result.message,
        value = if result.ok == true and type(result.value) == "table" then result.value else nil,
    }
end

function NetworkService.sendResult(
    self: NetworkService,
    player: Player,
    requestId: number,
    actionName: string,
    result: any
)
    self:_remote(RemoteNames.ActionResult)
        :FireClient(player, requestId, actionName, publicResult(result))
end

function NetworkService.sendSnapshot(self: NetworkService, player: Player, profile: any?)
    local resolved = profile or self._playerData:getProfile(player)
    if resolved == nil then
        return
    end
    local snapshot = Snapshot.build(resolved, self._actionService:now())
    self:_remote(RemoteNames.StateSnapshot):FireClient(player, snapshot)
end

function NetworkService.notify(self: NetworkService, player: Player, kind: string, text: string)
    self:_remote(RemoteNames.Notify):FireClient(player, { kind = kind, text = text })
end

function NetworkService._reject(self: NetworkService, player: Player, reason: string)
    local count = (self._rejections[player] or 0) + 1
    self._rejections[player] = count
    -- Log the first rejection and then every 50th so spam cannot flood the logs.
    if count == 1 or count % 50 == 0 then
        logger.warn(
            "rejected client request",
            { userId = player.UserId, reason = reason, count = count }
        )
    end
end

function NetworkService._handle(
    self: NetworkService,
    player: Player,
    actionName: string,
    requestId: any,
    payload: any
)
    if not ActionSchemas.isValidRequestId(requestId) then
        self:_reject(player, "invalid request id")
        return
    end

    local userKey = tostring(player.UserId)
    local rate = ActionSchemas.rateFor(actionName)
    if
        rate == nil
        or not self._limiter:allow(`{userKey}:*`, GLOBAL_BURST, GLOBAL_PER_SECOND)
        or not self._limiter:allow(`{userKey}:{actionName}`, rate.burst, rate.perSecond)
    then
        self:_reject(player, `rate limited {actionName}`)
        self:sendResult(player, requestId, actionName, {
            ok = false,
            code = "rate_limited",
            message = "you're doing that too fast",
        })
        return
    end

    local valid, sanitized = ActionSchemas.validate(actionName, payload)
    if not valid then
        self:_reject(player, `invalid payload for {actionName}: {sanitized}`)
        self:sendResult(player, requestId, actionName, {
            ok = false,
            code = "invalid_request",
            message = "that request was not valid",
        })
        return
    end

    if ActionSchemas.scopeFor(actionName) == "session" then
        local sessionHandler = self._sessionHandlers[actionName]
        local result = if sessionHandler ~= nil
            then sessionHandler(player, sanitized)
            else {
                ok = false,
                code = "invalid_request",
                message = "that action is unavailable",
            }
        self:sendResult(player, requestId, actionName, result)
        return
    end

    local handler = GameActions.handlers[actionName]
    local actionService = self._actionService
    local idPrefix = ID_PREFIX_BY_ACTION[actionName] or "x"
    local result = actionService:mutate(player, actionName, function(draft)
        return handler(draft, sanitized, {
            now = actionService:now(),
            generateId = function()
                return actionService:generateId(idPrefix)
            end,
        })
    end)

    self:sendResult(player, requestId, actionName, result)
end

function NetworkService.start(self: NetworkService)
    self:setSessionHandler(ActionNames.RequestSync, function(player: Player, _payload: any)
        self:sendSnapshot(player)
        return { ok = true }
    end)

    for _, actionName in pairs(ActionNames) do
        local remote = self:_remote(actionName)
        remote.OnServerEvent:Connect(function(player: Player, requestId: any, payload: any)
            self:_handle(player, actionName, requestId, payload)
        end)
    end

    -- Server-to-client remotes get a listener too, so events fired at them by a modified client
    -- are dropped instead of queueing on the server.
    for _, remoteName in pairs(RemoteNames) do
        self:_remote(remoteName).OnServerEvent:Connect(function(player: Player)
            self:_reject(player, `client fired server-to-client remote {remoteName}`)
        end)
    end

    Players.PlayerRemoving:Connect(function(player)
        self._limiter:forgetPrefix(`{player.UserId}:`)
        self._rejections[player] = nil
    end)
end

return NetworkService
