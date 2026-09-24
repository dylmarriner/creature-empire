-- Holds the latest authoritative snapshot of the local player's profile. The client never
-- edits it; it is replaced only by server StateSnapshot events.
local Workspace = game:GetService("Workspace")

local StateController = {}
StateController.__index = StateController

export type Listener = (snapshot: any) -> ()

export type StateController = typeof(setmetatable(
    {} :: {
        _remote: RemoteEvent,
        _snapshot: any,
        _listeners: { Listener },
    },
    StateController
))

function StateController.new(snapshotRemote: RemoteEvent): StateController
    return setmetatable({
        _remote = snapshotRemote,
        _snapshot = nil,
        _listeners = {},
    }, StateController)
end

function StateController.get(self: StateController): any
    return self._snapshot
end

function StateController.profile(self: StateController): any
    return if self._snapshot ~= nil then self._snapshot.profile else nil
end

-- Server-synchronised Unix time for display estimates such as pending production.
function StateController.serverNow(_self: StateController): number
    return Workspace:GetServerTimeNow()
end

function StateController.onChanged(self: StateController, listener: Listener)
    table.insert(self._listeners, listener)
    if self._snapshot ~= nil then
        task.spawn(listener, self._snapshot)
    end
end

function StateController.start(self: StateController)
    self._remote.OnClientEvent:Connect(function(snapshot: any)
        if type(snapshot) ~= "table" or type(snapshot.profile) ~= "table" then
            return
        end
        self._snapshot = snapshot
        for _, listener in ipairs(self._listeners) do
            task.spawn(listener, snapshot)
        end
    end)
end

return StateController
