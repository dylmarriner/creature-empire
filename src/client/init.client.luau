--[[
    Client bootstrap. The client renders authoritative snapshots and sends intent-only
    action requests; it never computes or reports balances, rewards or outcomes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActionNames = require(Shared.Net.ActionNames)
local RemoteNames = require(Shared.Net.RemoteNames)

local StateController = require("@self/Controllers/StateController")
local ActionClient = require("@self/Controllers/ActionClient")
local Hud = require("@self/Controllers/Hud")
local BuildController = require("@self/Controllers/BuildController")
local BuildingPanel = require("@self/Controllers/BuildingPanel")
local CreaturePanel = require("@self/Controllers/CreaturePanel")
local MarketPanel = require("@self/Controllers/MarketPanel")
local Format = require("@self/UI/Format")

local remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder

local function waitForRemote(name: string): RemoteEvent
    local remote = remotes:WaitForChild(name)
    assert(remote:IsA("RemoteEvent"), `{name} must be a RemoteEvent`)
    return remote
end

for _, actionName in pairs(ActionNames) do
    waitForRemote(actionName)
end
local snapshotRemote = waitForRemote(RemoteNames.StateSnapshot)
local resultRemote = waitForRemote(RemoteNames.ActionResult)
local notifyRemote = waitForRemote(RemoteNames.Notify)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local hud = Hud.new(playerGui)
local state = StateController.new(snapshotRemote)
local actions = ActionClient.new(remotes, function(message: string)
    hud.toasts:show("error", message)
end)

local build = BuildController.new(hud, state, actions)
local buildingPanel = BuildingPanel.new(hud, state, actions, build)
local creaturePanel = CreaturePanel.new(hud, actions)
local marketPanel = MarketPanel.new(hud, actions)

hud:addAction("Build", 1, function()
    build:cancel()
    build:openMenu()
end)
hud:addAction("Creatures", 2, function()
    creaturePanel:toggle()
end)
hud:addAction("Market", 3, function()
    marketPanel:toggle()
end)
hud:addAction("Claim All", 4, function()
    actions:send("ClaimProduction", {}, function(result: any)
        if not result.ok or type(result.value) ~= "table" then
            return
        end
        local produced = result.value.produced or {}
        if next(produced) ~= nil then
            hud.toasts:show("gain", `Collected {Format.items(produced)}`)
        end
        if result.value.storageLimited then
            hud.toasts:show("error", "Some storage is full. Build or upgrade a Warehouse.")
        end
    end)
end)
hud:addAction("Home", 5, function()
    actions:send("Travel", { destination = "home" })
end)
hud:addAction("Wilds", 6, function()
    actions:send("Travel", { destination = "wilds" })
end)

state:onChanged(function(snapshot: any)
    hud:update(snapshot)
end)

notifyRemote.OnClientEvent:Connect(function(message: any)
    if type(message) == "table" and type(message.text) == "string" then
        hud.toasts:show(
            if type(message.kind) == "string" then message.kind else "info",
            message.text
        )
    end
end)

state:start()
actions:start(resultRemote)
build:start()
buildingPanel:start()

-- The server pushes a snapshot once the profile loads; ask again in case this client
-- started listening after that push.
task.spawn(function()
    while state:get() == nil do
        actions:send("RequestSync", {}, function() end)
        task.wait(5)
    end
end)
