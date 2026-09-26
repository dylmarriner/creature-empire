--[[
    Maintains each player's `leaderstats` folder so the Roblox player list shows empire
    progress. Values are derived from the committed profile by Shared.Progression.EmpireStats
    and are display-only; nothing reads them back as state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EmpireStats = require(Shared.Progression.EmpireStats)

local LeaderboardService = {}

-- Stat display names, in player-list column order.
local EMPIRE_STAT = "Empire"
local CREATURES_STAT = "Creatures"

local function ensureValue(folder: Folder, name: string): IntValue
    local existing = folder:FindFirstChild(name)
    if existing ~= nil and existing:IsA("IntValue") then
        return existing
    end
    local value = Instance.new("IntValue")
    value.Name = name
    value.Parent = folder
    return value
end

function LeaderboardService.update(player: Player, profile: any)
    local folder = player:FindFirstChild("leaderstats")
    if folder == nil or not folder:IsA("Folder") then
        local created = Instance.new("Folder")
        created.Name = "leaderstats"
        -- Values are created before parenting so the player list builds its columns once.
        ensureValue(created, EMPIRE_STAT)
        ensureValue(created, CREATURES_STAT)
        created.Parent = player
        folder = created
    end

    local stats = EmpireStats.summarize(profile)
    ensureValue(folder :: Folder, EMPIRE_STAT).Value = stats.empireLevel
    ensureValue(folder :: Folder, CREATURES_STAT).Value = stats.creatures
end

return LeaderboardService
