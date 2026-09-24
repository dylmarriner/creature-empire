-- Sends semantic action requests and routes their results. Requests carry intent only;
-- the server decides every outcome.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActionNames = require(Shared.Net.ActionNames)

local REQUEST_TIMEOUT_SECONDS = 15

export type Result = { ok: boolean, code: string?, message: string?, value: any }
export type Callback = (result: Result) -> ()

local ActionClient = {}
ActionClient.__index = ActionClient

export type ActionClient = typeof(setmetatable(
    {} :: {
        _remotes: Folder,
        _nextId: number,
        _pending: { [number]: Callback },
        _onError: (message: string) -> (),
    },
    ActionClient
))

function ActionClient.new(remotes: Folder, onError: (message: string) -> ()): ActionClient
    return setmetatable({
        _remotes = remotes,
        _nextId = 0,
        _pending = {},
        _onError = onError,
    }, ActionClient)
end

-- Fires `actionName`. Failed results are reported through onError unless `callback`
-- handles them; the callback always receives the result.
function ActionClient.send(
    self: ActionClient,
    actionName: string,
    payload: { [string]: any }?,
    callback: Callback?
)
    assert(ActionNames[actionName] ~= nil, `unknown action {actionName}`)
    self._nextId += 1
    local requestId = self._nextId

    self._pending[requestId] = function(result: Result)
        if not result.ok then
            self._onError(result.message or "That didn't work.")
        end
        if callback ~= nil then
            callback(result)
        end
    end

    local remote = self._remotes:FindFirstChild(actionName) :: RemoteEvent
    remote:FireServer(requestId, payload or {})

    task.delay(REQUEST_TIMEOUT_SECONDS, function()
        self._pending[requestId] = nil
    end)
end

function ActionClient.start(self: ActionClient, resultRemote: RemoteEvent)
    resultRemote.OnClientEvent:Connect(function(requestId: any, _actionName: any, result: any)
        if type(requestId) ~= "number" or type(result) ~= "table" then
            return
        end
        local callback = self._pending[requestId]
        if callback ~= nil then
            self._pending[requestId] = nil
            callback(result)
        end
    end)
end

return ActionClient
