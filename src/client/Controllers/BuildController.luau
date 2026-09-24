-- Build menu and placement mode. The ghost preview uses the shared PlacementDomain for
-- instant feedback, but only the server's PlaceBuilding validation decides the result.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local BuildingDefinitions = require(Shared.Buildings.BuildingDefinitions)
local PlacementDomain = require(Shared.Buildings.PlacementDomain)
local InventoryDomain = require(Shared.Economy.InventoryDomain)
local WorldLayout = require(Shared.World.WorldLayout)

local Theme = require("../UI/Theme")
local Widgets = require("../UI/Widgets")
local Format = require("../UI/Format")

local CELL = GameConfig.BUILD_GRID_SIZE
local VALID_COLOR = Color3.fromRGB(90, 220, 120)
local INVALID_COLOR = Color3.fromRGB(230, 80, 70)

local BuildController = {}
BuildController.__index = BuildController

export type BuildController = typeof(setmetatable(
    {} :: {
        _hud: any,
        _state: any,
        _actions: any,
        _definitionId: string?,
        _rotation: number,
        _cellX: number,
        _cellZ: number,
        _valid: boolean,
        _pointer: Vector2?,
        _ghost: Part?,
        _controls: Frame?,
        _renderConnection: RBXScriptConnection?,
        _placing: boolean,
    },
    BuildController
))

function BuildController.new(hud: any, state: any, actions: any): BuildController
    return setmetatable({
        _hud = hud,
        _state = state,
        _actions = actions,
        _definitionId = nil,
        _rotation = 0,
        _cellX = 0,
        _cellZ = 0,
        _valid = false,
        _pointer = nil,
        _ghost = nil,
        _controls = nil,
        _renderConnection = nil,
        _placing = false,
    }, BuildController)
end

function BuildController.isPlacing(self: BuildController): boolean
    return self._definitionId ~= nil
end

local function plotCorner(): Vector3?
    local corner = Players.LocalPlayer:GetAttribute("PlotCorner")
    return if typeof(corner) == "Vector3" then corner else nil
end

function BuildController._renderMenu(self: BuildController, content: ScrollingFrame, snapshot: any)
    local profile = snapshot.profile
    for index, definitionId in ipairs(BuildingDefinitions.Ids) do
        local definition = BuildingDefinitions.ById[definitionId]
        local owned = PlacementDomain.countOfDefinition(profile, definitionId)
        local affordable = InventoryDomain.canAfford(profile, definition.cost)
        local underLimit = owned < definition.maxCount

        local card = Widgets.frame({
            name = definitionId,
            parent = content,
            size = UDim2.new(1, -8, 0, 0),
            color = Theme.Surface,
            order = index,
        })
        card.AutomaticSize = Enum.AutomaticSize.Y
        Widgets.padding(card)
        Widgets.list(card, Enum.FillDirection.Vertical, 3)

        Widgets.label({
            parent = card,
            text = `{definition.displayName}   ({owned}/{definition.maxCount})`,
            bold = true,
            textSize = 16,
            order = 1,
        })
        Widgets.label({
            parent = card,
            text = definition.description,
            wrap = true,
            autoHeight = true,
            color = Theme.TextMuted,
            textSize = 13,
            order = 2,
        })
        Widgets.label({
            parent = card,
            text = `Cost: {Format.items(definition.cost)}`,
            color = if affordable then Theme.Text else Theme.Danger,
            textSize = 13,
            wrap = true,
            autoHeight = true,
            order = 3,
        })
        Widgets.button({
            parent = card,
            text = if not underLimit
                then "Limit reached"
                elseif affordable then "Place"
                else "Can't afford",
            size = UDim2.fromOffset(130, 30),
            enabled = affordable and underLimit,
            order = 4,
            onActivated = function()
                self:beginPlacement(definitionId)
            end,
        })
    end
end

function BuildController.openMenu(self: BuildController)
    self._hud:togglePanel("build", "Build", function(content: ScrollingFrame, snapshot: any)
        self:_renderMenu(content, snapshot)
    end)
end

function BuildController._createControls(self: BuildController)
    local controls = Widgets.frame({
        name = "PlacementControls",
        parent = self._hud.screen,
        size = UDim2.fromOffset(0, 44),
        position = UDim2.new(0.5, 0, 1, -64),
        anchor = Vector2.new(0.5, 1),
        transparency = 1,
        rounded = false,
    })
    controls.AutomaticSize = Enum.AutomaticSize.X
    Widgets.list(controls, Enum.FillDirection.Horizontal, 8)

    Widgets.button({
        parent = controls,
        text = "Rotate (R)",
        size = UDim2.fromOffset(120, 40),
        color = Theme.SurfaceRaised,
        order = 1,
        onActivated = function()
            self:rotate()
        end,
    })
    Widgets.button({
        parent = controls,
        text = "Place",
        size = UDim2.fromOffset(120, 40),
        order = 2,
        onActivated = function()
            self:confirm()
        end,
    })
    Widgets.button({
        parent = controls,
        text = "Cancel (Q)",
        size = UDim2.fromOffset(120, 40),
        color = Theme.Danger,
        order = 3,
        onActivated = function()
            self:cancel()
        end,
    })

    self._controls = controls
end

function BuildController.beginPlacement(self: BuildController, definitionId: string)
    self:cancel()
    if plotCorner() == nil then
        self._hud.toasts:show("error", "Your plot is not ready yet.")
        return
    end

    self._hud:closePanel()
    self._definitionId = definitionId
    self._rotation = 0
    self._pointer = nil

    local ghost = Instance.new("Part")
    ghost.Name = "PlacementGhost"
    ghost.Anchored = true
    ghost.CanCollide = false
    ghost.CanQuery = false
    ghost.CanTouch = false
    ghost.Transparency = 0.45
    ghost.Material = Enum.Material.ForceField
    ghost.Parent = Workspace
    self._ghost = ghost

    self:_createControls()
    self._renderConnection = RunService.RenderStepped:Connect(function()
        self:_update()
    end)
    self._hud.toasts:show("info", "Point at your plot to place. R rotates, Q cancels.")
end

function BuildController.cancel(self: BuildController)
    self._definitionId = nil
    if self._renderConnection ~= nil then
        self._renderConnection:Disconnect()
        self._renderConnection = nil
    end
    if self._ghost ~= nil then
        self._ghost:Destroy()
        self._ghost = nil
    end
    if self._controls ~= nil then
        self._controls:Destroy()
        self._controls = nil
    end
end

function BuildController.rotate(self: BuildController)
    self._rotation = (self._rotation + 90) % 360
end

function BuildController.confirm(self: BuildController)
    local definitionId = self._definitionId
    if definitionId == nil or self._placing then
        return
    end
    if not self._valid then
        self._hud.toasts:show("error", "You can't place that there.")
        return
    end

    self._placing = true
    local definition = BuildingDefinitions.ById[definitionId]
    self._actions:send("PlaceBuilding", {
        definitionId = definitionId,
        cellX = self._cellX,
        cellZ = self._cellZ,
        rotation = self._rotation,
    }, function(result: any)
        self._placing = false
        if result.ok then
            self._hud.toasts:show("gain", `{definition.displayName} built!`)
            self:cancel()
        end
    end)
end

-- Intersects the pointer ray with the plot's build plane.
function BuildController._pointerOnPlot(self: BuildController, corner: Vector3): Vector3?
    local camera = Workspace.CurrentCamera
    if camera == nil then
        return nil
    end
    -- Touch positions are screen coordinates (below the GUI inset); the mouse location is in
    -- viewport coordinates.
    local ray: Ray
    local touch = self._pointer
    if touch ~= nil then
        ray = camera:ScreenPointToRay(touch.X, touch.Y)
    else
        local mouse = UserInputService:GetMouseLocation()
        ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
    end
    if math.abs(ray.Direction.Y) < 1e-4 then
        return nil
    end
    local distance = (corner.Y + WorldLayout.PLOT_BASE_TOP - ray.Origin.Y) / ray.Direction.Y
    if distance <= 0 then
        return nil
    end
    return ray.Origin + ray.Direction * distance
end

function BuildController._update(self: BuildController)
    local definitionId = self._definitionId
    local ghost = self._ghost
    local corner = plotCorner()
    local profile = self._state:profile()
    if definitionId == nil or ghost == nil or corner == nil or profile == nil then
        return
    end

    local definition = BuildingDefinitions.ById[definitionId]
    local width, depth = PlacementDomain.footprintFor(definition, self._rotation)
    local hit = self:_pointerOnPlot(corner)
    if hit == nil then
        return
    end

    local plotCells = GameConfig.PLOT_SIZE_CELLS
    local cellX =
        math.clamp(math.floor((hit.X - corner.X) / CELL - width / 2 + 0.5), 0, plotCells - width)
    local cellZ =
        math.clamp(math.floor((hit.Z - corner.Z) / CELL - depth / 2 + 0.5), 0, plotCells - depth)
    self._cellX = cellX
    self._cellZ = cellZ

    local check =
        PlacementDomain.checkPlacement(profile, definitionId, cellX, cellZ, self._rotation)
    local affordable = InventoryDomain.canAfford(profile, definition.cost)
    self._valid = check.ok == true and affordable

    local height = 5 + definition.footprint.x
    local center = corner
        + Vector3.new(
            (cellX + width / 2) * CELL,
            WorldLayout.PLOT_BASE_TOP + height / 2,
            (cellZ + depth / 2) * CELL
        )
    ghost.Size = Vector3.new(
        definition.footprint.x * CELL - 0.8,
        height,
        definition.footprint.z * CELL - 0.8
    )
    ghost.CFrame = CFrame.new(center) * CFrame.Angles(0, math.rad(self._rotation), 0)
    ghost.Color = if self._valid then VALID_COLOR else INVALID_COLOR
end

function BuildController.start(self: BuildController)
    UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
        if self._definitionId == nil then
            return
        end
        if input.KeyCode == Enum.KeyCode.R then
            self:rotate()
        elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Escape then
            self:cancel()
        elseif not processed then
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                self._pointer = nil
                self:confirm()
            elseif input.UserInputType == Enum.UserInputType.Touch then
                -- Touch moves the ghost; the on-screen Place button confirms.
                self._pointer = Vector2.new(input.Position.X, input.Position.Y)
            end
        end
    end)

    UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
        if self._definitionId == nil or processed then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            self._pointer = nil
        elseif input.UserInputType == Enum.UserInputType.Touch then
            self._pointer = Vector2.new(input.Position.X, input.Position.Y)
        end
    end)
end

return BuildController
