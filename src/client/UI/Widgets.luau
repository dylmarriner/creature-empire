-- Small constructors for code-built UI. Every widget is a plain Roblox Instance.
local Theme = require("./Theme")

local Widgets = {}

local function applyCorner(instance: GuiObject)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.Corner
    corner.Parent = instance
end

function Widgets.padding(parent: Instance, amount: number?)
    local value = UDim.new(0, amount or Theme.Padding)
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = value
    padding.PaddingBottom = value
    padding.PaddingLeft = value
    padding.PaddingRight = value
    padding.Parent = parent
    return padding
end

function Widgets.list(parent: Instance, direction: Enum.FillDirection?, spacing: number?)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = direction or Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, spacing or 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = parent
    return layout
end

function Widgets.frame(props: {
    name: string,
    parent: Instance,
    size: UDim2,
    position: UDim2?,
    anchor: Vector2?,
    color: Color3?,
    transparency: number?,
    rounded: boolean?,
    order: number?,
}): Frame
    local frame = Instance.new("Frame")
    frame.Name = props.name
    frame.Size = props.size
    frame.Position = props.position or UDim2.new()
    frame.AnchorPoint = props.anchor or Vector2.zero
    frame.BackgroundColor3 = props.color or Theme.Surface
    frame.BackgroundTransparency = props.transparency or 0
    frame.BorderSizePixel = 0
    frame.LayoutOrder = props.order or 0
    if props.rounded ~= false then
        applyCorner(frame)
    end
    frame.Parent = props.parent
    return frame
end

function Widgets.scroll(
    props: { name: string, parent: Instance, size: UDim2, position: UDim2? }
): ScrollingFrame
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = props.name
    scroll.Size = props.size
    scroll.Position = props.position or UDim2.new()
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.CanvasSize = UDim2.new()
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.Parent = props.parent
    return scroll
end

function Widgets.label(props: {
    name: string?,
    parent: Instance,
    text: string,
    size: UDim2?,
    position: UDim2?,
    textSize: number?,
    bold: boolean?,
    color: Color3?,
    alignX: Enum.TextXAlignment?,
    wrap: boolean?,
    order: number?,
    autoHeight: boolean?,
}): TextLabel
    local label = Instance.new("TextLabel")
    label.Name = props.name or "Label"
    label.BackgroundTransparency = 1
    label.Size = props.size or UDim2.new(1, 0, 0, 20)
    label.Position = props.position or UDim2.new()
    label.Font = if props.bold then Theme.FontBold else Theme.Font
    label.TextSize = props.textSize or 15
    label.TextColor3 = props.color or Theme.Text
    label.TextXAlignment = props.alignX or Enum.TextXAlignment.Left
    label.TextWrapped = props.wrap == true
    label.RichText = false
    label.LayoutOrder = props.order or 0
    label.Text = props.text
    if props.autoHeight then
        label.AutomaticSize = Enum.AutomaticSize.Y
    end
    label.Parent = props.parent
    return label
end

function Widgets.button(props: {
    name: string?,
    parent: Instance,
    text: string,
    size: UDim2?,
    position: UDim2?,
    anchor: Vector2?,
    color: Color3?,
    textSize: number?,
    enabled: boolean?,
    order: number?,
    onActivated: () -> (),
}): TextButton
    local enabled = props.enabled ~= false
    local button = Instance.new("TextButton")
    button.Name = props.name or "Button"
    button.Size = props.size or UDim2.fromOffset(120, 36)
    button.Position = props.position or UDim2.new()
    button.AnchorPoint = props.anchor or Vector2.zero
    button.BackgroundColor3 = if enabled then props.color or Theme.Accent else Theme.Disabled
    button.BorderSizePixel = 0
    button.AutoButtonColor = enabled
    button.Font = Theme.FontBold
    button.TextSize = props.textSize or 15
    button.TextColor3 = Theme.Text
    button.Text = props.text
    button.LayoutOrder = props.order or 0
    applyCorner(button)
    button.Activated:Connect(function()
        if enabled then
            props.onActivated()
        end
    end)
    button.Parent = props.parent
    return button
end

-- Removes every GuiObject child, keeping layouts and padding.
function Widgets.clear(container: Instance)
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

return Widgets
