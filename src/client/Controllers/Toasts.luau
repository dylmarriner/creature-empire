-- Transient notification stack in the top centre of the screen.
local TweenService = game:GetService("TweenService")

local Theme = require("../UI/Theme")
local Widgets = require("../UI/Widgets")

local MAX_TOASTS = 5
local LIFETIME_SECONDS = 3.5

local COLORS = {
    gain = Theme.Accent,
    objective = Theme.Coin,
    error = Theme.Danger,
    info = Theme.SurfaceRaised,
}

local Toasts = {}
Toasts.__index = Toasts

export type Toasts = typeof(setmetatable(
    {} :: {
        _container: Frame,
        _order: number,
    },
    Toasts
))

function Toasts.new(screen: ScreenGui): Toasts
    local container = Widgets.frame({
        name = "Toasts",
        parent = screen,
        size = UDim2.fromOffset(420, 300),
        position = UDim2.new(0.5, 0, 0, 64),
        anchor = Vector2.new(0.5, 0),
        transparency = 1,
        rounded = false,
    })
    local layout = Widgets.list(container, Enum.FillDirection.Vertical, 6)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

    return setmetatable({ _container = container, _order = 0 }, Toasts)
end

function Toasts.show(self: Toasts, kind: string, text: string)
    self._order += 1

    local toasts = {}
    for _, child in ipairs(self._container:GetChildren()) do
        if child:IsA("Frame") then
            table.insert(toasts, child)
        end
    end
    table.sort(toasts, function(a, b)
        return a.LayoutOrder < b.LayoutOrder
    end)
    while #toasts >= MAX_TOASTS do
        local oldest = table.remove(toasts, 1)
        if oldest ~= nil then
            oldest:Destroy()
        end
    end

    local toast = Widgets.frame({
        name = "Toast",
        parent = self._container,
        size = UDim2.new(1, 0, 0, 34),
        color = COLORS[kind] or Theme.SurfaceRaised,
        transparency = 0.1,
        order = self._order,
    })
    local label = Widgets.label({
        parent = toast,
        text = text,
        size = UDim2.fromScale(1, 1),
        alignX = Enum.TextXAlignment.Center,
        bold = true,
        wrap = true,
        textSize = 15,
    })

    task.delay(LIFETIME_SECONDS, function()
        if toast.Parent == nil then
            return
        end
        local fade = TweenInfo.new(0.4)
        TweenService:Create(toast, fade, { BackgroundTransparency = 1 }):Play()
        local tween = TweenService:Create(label, fade, { TextTransparency = 1 })
        tween.Completed:Connect(function()
            toast:Destroy()
        end)
        tween:Play()
    end)
end

return Toasts
