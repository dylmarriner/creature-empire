--[[
    PlayerDataService owns the player profile session lifecycle:
    load + lock on join, autosave, save + release on leave and on server shutdown.

    Profiles are only ever replaced wholesale by ActionService after a validated
    transactional commit; nothing else mutates them.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ProfileSchema = require(Shared.Profiles.ProfileSchema)
local ProfileIntegrity = require(Shared.Profiles.ProfileIntegrity)
local TableUtil = require(Shared.Util.TableUtil)

local ProfileStore = require("../Persistence/ProfileStore")
local MemoryStore = require("../Persistence/MemoryStore")
local DataStoreAdapter = require("../Persistence/DataStoreAdapter")
local Logger = require("./Logger")

local DATASTORE_NAME = "PlayerProfiles_v1"
local AUTOSAVE_INTERVAL_SECONDS = 90
local SHUTDOWN_TIMEOUT_SECONDS = 25

local KICK_LOAD_FAILED =
    "We couldn't load your save data. Nothing was lost - please rejoin in a minute."
local KICK_INVALID =
    "Your save data could not be read safely. Nothing was overwritten - please contact support."
local KICK_SESSION_LOST = "Your save data was opened on another server. Please rejoin."

local logger = Logger.new("PlayerData")

export type Session = {
    player: Player,
    userId: number,
    key: string,
    profile: any,
    saving: boolean,
    released: boolean,
}

local PlayerDataService = {}
PlayerDataService.__index = PlayerDataService

export type PlayerDataService = typeof(setmetatable(
    {} :: {
        _store: ProfileStore.ProfileStore,
        _sessions: { [Player]: Session },
        _loading: { [Player]: boolean },
        _onLoaded: (player: Player) -> (),
        _onReleased: (player: Player) -> (),
        _clock: () -> number,
        _shuttingDown: boolean,
        usingMemoryStore: boolean,
    },
    PlayerDataService
))

local function keyFor(userId: number): string
    return `player_{userId}`
end

-- Chooses the persistent store. Live servers always use DataStores; Studio falls back to an
-- in-memory store only when API access is disabled, and says so loudly.
local function createStoreAdapter(): (ProfileStore.StoreAdapter, boolean)
    local success, dataStoreOrError = pcall(function()
        return DataStoreService:GetDataStore(DATASTORE_NAME)
    end)

    if success and RunService:IsStudio() then
        local probeOk, probeError = pcall(function()
            return dataStoreOrError:GetAsync("studio_access_probe")
        end)
        if not probeOk then
            success = false
            dataStoreOrError = probeError
        end
    end

    if success then
        return DataStoreAdapter.new(dataStoreOrError), false
    end

    if RunService:IsStudio() then
        logger.warn(
            "DataStore unavailable in Studio; using in-memory profiles that will not persist",
            {
                reason = tostring(dataStoreOrError),
            }
        )
        return MemoryStore.new(), true
    end

    -- In a live server the adapter is still created so every load fails loudly and players
    -- are kicked rather than handed an unsaved default profile.
    logger.error("DataStore unavailable", { reason = tostring(dataStoreOrError) })
    return {
        update = function(_key: string, _transform: (any) -> any, _userIds: { number }?)
            return false, "DataStore unavailable"
        end,
    },
        false
end

function PlayerDataService.new(options: {
    clock: () -> number,
    onLoaded: (player: Player) -> (),
    onReleased: (player: Player) -> (),
}): PlayerDataService
    local adapter, usingMemoryStore = createStoreAdapter()
    local jobId = if game.JobId ~= ""
        then game.JobId
        else `studio_{HttpService:GenerateGUID(false)}`

    local self = setmetatable({
        _store = ProfileStore.new({
            store = adapter,
            schema = ProfileSchema,
            jobId = jobId,
            clock = options.clock,
            wait = function(seconds: number)
                task.wait(seconds)
            end,
        }),
        _sessions = {},
        _loading = {},
        _onLoaded = options.onLoaded,
        _onReleased = options.onReleased,
        _clock = options.clock,
        _shuttingDown = false,
        usingMemoryStore = usingMemoryStore,
    }, PlayerDataService)

    return self
end

function PlayerDataService.getProfile(self: PlayerDataService, player: Player): any
    local session = self._sessions[player]
    return if session ~= nil then session.profile else nil
end

-- Replaces the committed profile. Only ActionService calls this, after validation.
function PlayerDataService.setProfile(self: PlayerDataService, player: Player, profile: any)
    local session = self._sessions[player]
    if session ~= nil and not session.released then
        session.profile = profile
    end
end

function PlayerDataService.isLoaded(self: PlayerDataService, player: Player): boolean
    return self._sessions[player] ~= nil
end

function PlayerDataService._save(self: PlayerDataService, session: Session, release: boolean)
    while session.saving do
        task.wait(0.1)
    end
    if session.released then
        return
    end

    session.saving = true
    local snapshot = TableUtil.deepCopy(session.profile)
    snapshot.lastSeenAt = math.max(snapshot.lastSeenAt, self._clock())

    local status, detail = self._store:save(session.key, session.userId, snapshot, release)
    session.saving = false

    if status == "saved" then
        if release then
            session.released = true
        end
        return
    end

    if status == "session_lost" then
        session.released = true
        logger.warn(
            "session lock lost; stopping writes for this profile",
            { userId = session.userId }
        )
        if session.player.Parent == Players then
            session.player:Kick(KICK_SESSION_LOST)
        end
    else
        logger.error("profile save failed", {
            userId = session.userId,
            status = status,
            detail = detail or "none",
            release = release,
        })
    end
end

function PlayerDataService._load(self: PlayerDataService, player: Player)
    if self._sessions[player] ~= nil or self._loading[player] then
        return
    end
    self._loading[player] = true

    local userId = player.UserId
    local key = keyFor(userId)
    local status, profile, detail = self._store:load(key, userId)
    self._loading[player] = nil

    if status ~= "loaded" and status ~= "created" then
        logger.warn(
            "profile load refused",
            { userId = userId, status = status, detail = detail or "none" }
        )
        if player.Parent == Players then
            player:Kick(if status == "invalid" then KICK_INVALID else KICK_LOAD_FAILED)
        end
        return
    end

    local repairs = ProfileIntegrity.repair(profile)
    if repairs > 0 then
        logger.warn(
            "repaired profile assignment references",
            { userId = userId, repairs = repairs }
        )
    end

    local session: Session = {
        player = player,
        userId = userId,
        key = key,
        profile = profile,
        saving = false,
        released = false,
    }
    self._sessions[player] = session

    if player.Parent ~= Players then
        -- The player left while the profile was loading; release the lock straight away.
        self:_release(player)
        return
    end

    logger.info("profile loaded", { userId = userId, created = status == "created" })
    self._onLoaded(player)
end

function PlayerDataService._release(self: PlayerDataService, player: Player)
    local session = self._sessions[player]
    if session == nil then
        return
    end

    self:_save(session, true)
    if self._sessions[player] == session then
        self._sessions[player] = nil
        self._onReleased(player)
    end
end

function PlayerDataService.start(self: PlayerDataService)
    Players.PlayerAdded:Connect(function(player)
        self:_load(player)
    end)

    Players.PlayerRemoving:Connect(function(player)
        self:_release(player)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(self._load, self, player)
    end

    task.spawn(function()
        while not self._shuttingDown do
            task.wait(AUTOSAVE_INTERVAL_SECONDS)
            for _, session in pairs(self._sessions) do
                if not session.released then
                    task.spawn(self._save, self, session, false)
                end
            end
        end
    end)

    game:BindToClose(function()
        self._shuttingDown = true
        local pending = 0
        for player in pairs(self._sessions) do
            pending += 1
            task.spawn(function()
                self:_release(player)
                pending -= 1
            end)
        end

        local deadline = os.clock() + SHUTDOWN_TIMEOUT_SECONDS
        while pending > 0 and os.clock() < deadline do
            task.wait(0.1)
        end
        if pending > 0 then
            logger.error("shutdown finished with unsaved profiles", { pending = pending })
        end
    end)
end

return PlayerDataService
