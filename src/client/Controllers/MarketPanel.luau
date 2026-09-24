-- Sell resources for coins at canonical server prices.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemDefinitions = require(Shared.Items.ItemDefinitions)

local Theme = require("../UI/Theme")
local Widgets = require("../UI/Widgets")

local MarketPanel = {}
MarketPanel.__index = MarketPanel

export type MarketPanel = typeof(setmetatable({} :: { _hud: any, _actions: any }, MarketPanel))

function MarketPanel.new(hud: any, actions: any): MarketPanel
    return setmetatable({ _hud = hud, _actions = actions }, MarketPanel)
end

function MarketPanel._sell(self: MarketPanel, itemId: string, quantity: number)
    self._actions:send(
        "SellResource",
        { itemId = itemId, quantity = quantity },
        function(result: any)
            if result.ok and type(result.value) == "table" then
                self._hud.toasts:show("gain", `Sold for {result.value.coins} coins`)
            end
        end
    )
end

function MarketPanel._render(self: MarketPanel, content: ScrollingFrame, snapshot: any)
    local profile = snapshot.profile
    Widgets.label({
        parent = content,
        text = "Coins pay for building upgrades. Keep what you need to build!",
        wrap = true,
        autoHeight = true,
        color = Theme.TextMuted,
        textSize = 13,
        order = 0,
    })

    for index, itemId in ipairs(ItemDefinitions.Ids) do
        local definition = ItemDefinitions.ById[itemId]
        local held = profile.inventory[itemId] or 0

        local row = Widgets.frame({
            name = itemId,
            parent = content,
            size = UDim2.new(1, -8, 0, 64),
            color = Theme.Surface,
            order = index,
        })
        Widgets.label({
            parent = row,
            text = `{definition.displayName} x{held}   ({definition.sellPrice} coin each)`,
            size = UDim2.new(1, -16, 0, 24),
            position = UDim2.fromOffset(8, 4),
        })
        Widgets.button({
            parent = row,
            text = "Sell 10",
            size = UDim2.fromOffset(100, 28),
            position = UDim2.fromOffset(8, 30),
            enabled = held >= 10,
            textSize = 13,
            onActivated = function()
                self:_sell(itemId, 10)
            end,
        })
        Widgets.button({
            parent = row,
            text = "Sell all",
            size = UDim2.fromOffset(100, 28),
            position = UDim2.fromOffset(116, 30),
            enabled = held > 0,
            color = Theme.Warning,
            textSize = 13,
            onActivated = function()
                self:_sell(itemId, held)
            end,
        })
    end
end

function MarketPanel.toggle(self: MarketPanel)
    self._hud:togglePanel("market", "Market", function(content: ScrollingFrame, snapshot: any)
        self:_render(content, snapshot)
    end)
end

return MarketPanel
