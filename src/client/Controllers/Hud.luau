-- The always-on HUD: resources, objective tracker, action bar, loading overlay and a single
-- modal panel host shared by every menu.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemDefinitions = require(Shared.Items.ItemDefinitions)

local Theme = require("../UI/Theme")
local Widgets = require("../UI/Widgets")
local Toasts = require("./Toasts")

export type PanelRenderer = (content: ScrollingFrame, snapshot: any) -> ()

-- The HUD is laid out for this viewport width and scaled down uniformly on smaller screens.
local DESIGN_WIDTH = 1000
local MIN_SCALE = 0.55

local Hud = {}
Hud.__index = Hud

export type Hud = typeof(setmetatable(
    {} :: {
        screen: ScreenGui,
        root: Frame,
        toasts: Toasts.Toasts,
        _resources: Frame,
        _objective: Frame,
        _actionBar: Frame,
        _pending: TextLabel,
        _loading: Frame,
        _panel: Frame,
        _panelTitle: TextLabel,
        _panelContent: ScrollingFrame,
        _panelName: string?,
        _panelRenderer: PanelRenderer?,
        _snapshot: any,
    },
    Hud
))

function Hud.new(playerGui: PlayerGui): Hud
    local screen = Instance.new("ScreenGui")
    screen.Name = "CreatureEmpireHud"
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = playerGui

    -- Every HUD element lives under `root`. Scaling the root by `s` while sizing it to 1/s of
    -- the screen keeps anchored elements at the screen edges.
    local root = Widgets.frame({
        name = "Root",
        parent = screen,
        size = UDim2.fromScale(1, 1),
        transparency = 1,
        rounded = false,
    })
    local uiScale = Instance.new("UIScale")
    uiScale.Parent = root

    local function applyScale()
        local camera = Workspace.CurrentCamera
        local width = if camera ~= nil then camera.ViewportSize.X else DESIGN_WIDTH
        local scale = math.clamp(width / DESIGN_WIDTH, MIN_SCALE, 1)
        uiScale.Scale = scale
        root.Size = UDim2.fromScale(1 / scale, 1 / scale)
    end
    applyScale()
    local camera = Workspace.CurrentCamera
    if camera ~= nil then
        camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
    end

    local resources = Widgets.frame({
        name = "Resources",
        parent = root,
        size = UDim2.fromOffset(210, 0),
        position = UDim2.fromOffset(12, 12),
        color = Theme.Background,
        transparency = 0.15,
    })
    resources.AutomaticSize = Enum.AutomaticSize.Y
    Widgets.padding(resources)
    Widgets.list(resources, Enum.FillDirection.Vertical, 2)

    local objective = Widgets.frame({
        name = "Objective",
        parent = root,
        size = UDim2.fromOffset(290, 0),
        position = UDim2.new(1, -12, 0, 12),
        anchor = Vector2.new(1, 0),
        color = Theme.Background,
        transparency = 0.15,
    })
    objective.AutomaticSize = Enum.AutomaticSize.Y
    Widgets.padding(objective)
    Widgets.list(objective, Enum.FillDirection.Vertical, 4)

    local actionBar = Widgets.frame({
        name = "ActionBar",
        parent = root,
        size = UDim2.fromOffset(0, 44),
        position = UDim2.new(0.5, 0, 1, -12),
        anchor = Vector2.new(0.5, 1),
        transparency = 1,
        rounded = false,
    })
    actionBar.AutomaticSize = Enum.AutomaticSize.X
    local barLayout = Widgets.list(actionBar, Enum.FillDirection.Horizontal, 8)
    barLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local pending = Widgets.label({
        name = "Pending",
        parent = root,
        text = "",
        size = UDim2.fromOffset(420, 24),
        position = UDim2.new(0.5, 0, 1, -60),
        textSize = 15,
        bold = true,
        color = Theme.Coin,
        alignX = Enum.TextXAlignment.Center,
    })
    pending.AnchorPoint = Vector2.new(0.5, 1)
    pending.TextStrokeTransparency = 0.5
    pending.Visible = false

    local panel = Widgets.frame({
        name = "Panel",
        parent = root,
        size = UDim2.new(0, 380, 0.62, 0),
        position = UDim2.new(1, -12, 0.5, 20),
        anchor = Vector2.new(1, 0.5),
        color = Theme.Background,
        transparency = 0.05,
    })
    panel.Visible = false
    local panelSize = Instance.new("UISizeConstraint")
    panelSize.MinSize = Vector2.new(260, 240)
    panelSize.MaxSize = Vector2.new(380, 560)
    panelSize.Parent = panel

    local panelTitle = Widgets.label({
        name = "Title",
        parent = panel,
        text = "",
        size = UDim2.new(1, -60, 0, 36),
        position = UDim2.fromOffset(12, 4),
        textSize = 19,
        bold = true,
    })

    local panelContent = Widgets.scroll({
        name = "Content",
        parent = panel,
        size = UDim2.new(1, -16, 1, -48),
        position = UDim2.fromOffset(8, 42),
    })
    Widgets.list(panelContent, Enum.FillDirection.Vertical, 6)
    Widgets.padding(panelContent, 4)

    local loading = Widgets.frame({
        name = "Loading",
        parent = root,
        size = UDim2.fromScale(1, 1),
        color = Theme.Background,
        rounded = false,
    })
    loading.ZIndex = 10
    local loadingLabel = Widgets.label({
        parent = loading,
        text = "Loading your empire...",
        size = UDim2.fromScale(1, 1),
        alignX = Enum.TextXAlignment.Center,
        textSize = 24,
        bold = true,
    })
    loadingLabel.ZIndex = 11

    local self = setmetatable({
        screen = screen,
        root = root,
        toasts = Toasts.new(root),
        _resources = resources,
        _objective = objective,
        _actionBar = actionBar,
        _pending = pending,
        _loading = loading,
        _panel = panel,
        _panelTitle = panelTitle,
        _panelContent = panelContent,
        _panelName = nil,
        _panelRenderer = nil,
        _snapshot = nil,
    }, Hud)

    Widgets.button({
        name = "Close",
        parent = panel,
        text = "X",
        size = UDim2.fromOffset(32, 32),
        position = UDim2.new(1, -8, 0, 6),
        anchor = Vector2.new(1, 0),
        color = Theme.SurfaceRaised,
        onActivated = function()
            self:closePanel()
        end,
    })

    return self
end

function Hud.addAction(self: Hud, text: string, order: number, onActivated: () -> ()): TextButton
    return Widgets.button({
        name = text,
        parent = self._actionBar,
        text = text,
        size = UDim2.fromOffset(112, 42),
        order = order,
        onActivated = onActivated,
    })
end

-- Shows the estimated unclaimed production above the action bar.
function Hud.setPending(self: Hud, cycles: number, buildings: number)
    self._pending.Visible = cycles > 0
    if cycles > 0 then
        local noun = if buildings == 1 then "building" else "buildings"
        self._pending.Text = `About {cycles} cycles ready in {buildings} {noun} - Claim All`
    end
end

function Hud.panelName(self: Hud): string?
    return if self._panel.Visible then self._panelName else nil
end

function Hud.openPanel(self: Hud, name: string, title: string, renderer: PanelRenderer)
    self._panelName = name
    self._panelRenderer = renderer
    self._panelTitle.Text = title
    self._panel.Visible = true
    self:refreshPanel()
end

function Hud.togglePanel(self: Hud, name: string, title: string, renderer: PanelRenderer)
    if self:panelName() == name then
        self:closePanel()
    else
        self:openPanel(name, title, renderer)
    end
end

function Hud.setPanelTitle(self: Hud, title: string)
    self._panelTitle.Text = title
end

function Hud.closePanel(self: Hud)
    self._panel.Visible = false
    self._panelName = nil
    self._panelRenderer = nil
    Widgets.clear(self._panelContent)
end

function Hud.refreshPanel(self: Hud)
    local renderer = self._panelRenderer
    if renderer == nil or not self._panel.Visible or self._snapshot == nil then
        return
    end
    Widgets.clear(self._panelContent)
    renderer(self._panelContent, self._snapshot)
end

function Hud._renderResources(self: Hud, snapshot: any)
    local frame = self._resources
    Widgets.clear(frame)
    local profile = snapshot.profile

    Widgets.label({
        parent = frame,
        text = `Coins  {profile.currencies.coins}`,
        color = Theme.Coin,
        bold = true,
        textSize = 17,
        order = 1,
    })
    Widgets.label({
        parent = frame,
        text = `Gems  {profile.currencies.gems}`,
        color = Theme.Gem,
        bold = true,
        order = 2,
    })

    for index, itemId in ipairs(ItemDefinitions.Ids) do
        local quantity = profile.inventory[itemId] or 0
        local full = quantity >= snapshot.storageCapacity
        Widgets.label({
            parent = frame,
            text = `{ItemDefinitions.ById[itemId].displayName}  {quantity}/{snapshot.storageCapacity}`,
            color = if full then Theme.Warning else Theme.Text,
            order = 10 + index,
        })
    end

    Widgets.label({
        parent = frame,
        text = `Creatures  {snapshot.creatureCount}/{snapshot.creatureCapacity}`,
        color = Theme.TextMuted,
        order = 100,
    })
end

function Hud._renderObjective(self: Hud, snapshot: any)
    local frame = self._objective
    Widgets.clear(frame)
    local objective = snapshot.objective

    if objective == nil then
        Widgets.label({
            parent = frame,
            text = "Empire established!",
            bold = true,
            textSize = 17,
            color = Theme.Coin,
            order = 1,
        })
        Widgets.label({
            parent = frame,
            text = "Keep expanding, upgrading and capturing creatures.",
            wrap = true,
            autoHeight = true,
            color = Theme.TextMuted,
            order = 2,
        })
        return
    end

    Widgets.label({
        parent = frame,
        text = `Objective {objective.order}/{snapshot.objectiveCount}`,
        color = Theme.TextMuted,
        textSize = 13,
        order = 1,
    })
    Widgets.label({ parent = frame, text = objective.title, bold = true, textSize = 17, order = 2 })
    Widgets.label({
        parent = frame,
        text = objective.description,
        wrap = true,
        autoHeight = true,
        color = Theme.TextMuted,
        order = 3,
    })
    Widgets.label({
        parent = frame,
        text = `Progress {objective.current}/{objective.target}    Reward {objective.rewardCoins} coins`,
        color = Theme.Coin,
        textSize = 14,
        order = 4,
    })
end

function Hud.update(self: Hud, snapshot: any)
    self._snapshot = snapshot
    self._loading.Visible = false
    self:_renderResources(snapshot)
    self:_renderObjective(snapshot)
    self:refreshPanel()
end

return Hud
