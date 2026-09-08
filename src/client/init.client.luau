local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActionNames = require(Shared.Net.ActionNames)
local remotes = ReplicatedStorage:WaitForChild("Remotes")

for _, actionName in pairs(ActionNames) do
    local remote = remotes:WaitForChild(actionName)
    assert(remote:IsA("RemoteEvent"), `{actionName} must be a RemoteEvent`)
end

print("Creature Empire client foundation initialized")
