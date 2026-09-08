local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ItemDefinitions = require(Shared.Items.ItemDefinitions)
local CreatureDefinitions = require(Shared.Creatures.CreatureDefinitions)
local BuildingDefinitions = require(Shared.Buildings.BuildingDefinitions)
local ProductionMath = require(Shared.Economy.ProductionMath)
local ActionNames = require(Shared.Net.ActionNames)

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

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if remotes == nil then
    remotes = Instance.new("Folder")
    remotes.Name = "Remotes"
    remotes.Parent = ReplicatedStorage
end

for _, actionName in pairs(ActionNames) do
    local existing = remotes:FindFirstChild(actionName)
    if existing == nil then
        local remote = Instance.new("RemoteEvent")
        remote.Name = actionName
        remote.Parent = remotes
    else
        assert(existing:IsA("RemoteEvent"), `{actionName} must be a RemoteEvent`)
    end
end

print("Creature Empire server foundation initialized")
