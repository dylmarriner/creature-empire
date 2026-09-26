-- Lists the other empires in this server and travels to their plots. Visiting is look-only:
-- building selection and every action still apply to the visitor's own profile.
local Players = game:GetService("Players")

local Theme = require("../UI/Theme")
local Widgets = require("../UI/Widgets")

local VisitPanel = {}
VisitPanel.__index = VisitPanel

export type VisitPanel = typeof(setmetatable({} :: { _hud: any, _actions: any }, VisitPanel))

function VisitPanel.new(hud: any, actions: any): VisitPanel
    return setmetatable({ _hud = hud, _actions = actions }, VisitPanel)
end

local function statValue(player: Player, name: string): number?
    local leaderstats = player:FindFirstChild("leaderstats")
    local value = if leaderstats ~= nil then leaderstats:FindFirstChild(name) else nil
    if value ~= nil and value:IsA("IntValue") then
        return value.Value
    end
    return nil
end

function VisitPanel._render(self: VisitPanel, content: ScrollingFrame, _snapshot: any)
    local hosts = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if
            player ~= Players.LocalPlayer
            and typeof(player:GetAttribute("PlotCorner")) == "Vector3"
        then
            table.insert(hosts, player)
        end
    end
    table.sort(hosts, function(a, b)
        return (statValue(a, "Empire") or 0) > (statValue(b, "Empire") or 0)
    end)

    if #hosts == 0 then
        Widgets.label({
            parent = content,
            text = "No other empires are in this server yet.",
            wrap = true,
            autoHeight = true,
            color = Theme.TextMuted,
            order = 0,
        })
        return
    end

    for index, host in ipairs(hosts) do
        local row = Widgets.frame({
            name = tostring(host.UserId),
            parent = content,
            size = UDim2.new(1, -8, 0, 56),
            color = Theme.Surface,
            order = index,
        })
        Widgets.label({
            parent = row,
            text = `{host.DisplayName}'s Empire`,
            bold = true,
            size = UDim2.new(1, -120, 0, 24),
            position = UDim2.fromOffset(10, 4),
        })
        local empire = statValue(host, "Empire")
        local creatures = statValue(host, "Creatures")
        Widgets.label({
            parent = row,
            text = `Empire level {empire or 0}   Creatures {creatures or 0}`,
            color = Theme.TextMuted,
            textSize = 13,
            size = UDim2.new(1, -120, 0, 20),
            position = UDim2.fromOffset(10, 28),
        })
        local userId = host.UserId
        Widgets.button({
            parent = row,
            text = "Visit",
            size = UDim2.fromOffset(96, 34),
            position = UDim2.new(1, -8, 0.5, 0),
            anchor = Vector2.new(1, 0.5),
            onActivated = function()
                self._actions:send(
                    "Travel",
                    { destination = "plot", targetUserId = userId },
                    function(result: any)
                        if result.ok then
                            self._hud:closePanel()
                        end
                    end
                )
            end,
        })
    end
end

function VisitPanel.toggle(self: VisitPanel)
    self._hud:togglePanel("visit", "Visit Empires", function(content: ScrollingFrame, snapshot: any)
        self:_render(content, snapshot)
    end)
end

return VisitPanel
