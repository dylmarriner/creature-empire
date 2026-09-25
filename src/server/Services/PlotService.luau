--[[
    PlotService allocates a plot slot to each loaded player and renders their persisted
    buildings from profile data. Rendering is presentation only: Instances are rebuilt from
    the profile and are never read back as state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local BuildingDefinitions = require(Shared.Buildings.BuildingDefinitions)
local CreatureDefinitions = require(Shared.Creatures.CreatureDefinitions)
local PlacementDomain = require(Shared.Buildings.PlacementDomain)
local WorldLayout = require(Shared.World.WorldLayout)

local CELL = GameConfig.BUILD_GRID_SIZE
local PLOT_STUDS = WorldLayout.PLOT_STUDS
local BASE_TOP = WorldLayout.PLOT_BASE_TOP

local PlotService = {}
PlotService.__index = PlotService

type PlotRecord = {
    index: number,
    model: Model,
    buildings: Folder,
    corner: Vector3,
    signatures: { [string]: string },
    characterConnection: RBXScriptConnection?,
}

export type PlotService = typeof(setmetatable(
    {} :: {
        _folder: Folder,
        _plots: { [Player]: PlotRecord },
        _usedSlots: { [number]: boolean },
    },
    PlotService
))

local function toColor(color: { r: number, g: number, b: number }): Color3
    return Color3.fromRGB(color.r, color.g, color.b)
end

local function makePart(props: {
    name: string,
    size: Vector3,
    cframe: CFrame,
    color: Color3,
    material: Enum.Material?,
    shape: Enum.PartType?,
    canCollide: boolean?,
    parent: Instance,
}): Part
    local part = Instance.new("Part")
    part.Name = props.name
    part.Anchored = true
    part.Size = props.size
    part.CFrame = props.cframe
    part.Color = props.color
    part.Material = props.material or Enum.Material.SmoothPlastic
    part.Shape = props.shape or Enum.PartType.Block
    part.CanCollide = if props.canCollide == nil then true else props.canCollide
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = props.parent
    return part
end

local function makeBillboard(adornee: BasePart, lines: { string }, offsetY: number)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Label"
    billboard.Adornee = adornee
    billboard.AlwaysOnTop = false
    billboard.LightInfluence = 0
    billboard.MaxDistance = 140
    billboard.Size = UDim2.fromOffset(200, 22 * #lines)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)

    for index, text in ipairs(lines) do
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 0, 22)
        label.Position = UDim2.fromOffset(0, (index - 1) * 22)
        label.Font = if index == 1 then Enum.Font.GothamBold else Enum.Font.Gotham
        label.TextSize = if index == 1 then 18 else 14
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.4
        label.Text = text
        label.Parent = billboard
    end

    billboard.Parent = adornee
end

function PlotService.new(): PlotService
    local folder = Workspace:FindFirstChild("Plots")
    if folder == nil then
        folder = Instance.new("Folder")
        folder.Name = "Plots"
        folder.Parent = Workspace
    end

    return setmetatable({
        _folder = folder :: Folder,
        _plots = {},
        _usedSlots = {},
    }, PlotService)
end

function PlotService.cornerFor(_self: PlotService, player: Player): Vector3?
    local attribute = player:GetAttribute("PlotCorner")
    return if typeof(attribute) == "Vector3" then attribute else nil
end

function PlotService._allocateSlot(self: PlotService): number
    local index = 1
    while self._usedSlots[index] do
        index += 1
    end
    self._usedSlots[index] = true
    return index
end

function PlotService.assign(self: PlotService, player: Player)
    if self._plots[player] ~= nil then
        return
    end

    local index = self:_allocateSlot()
    local cornerX, cornerZ = WorldLayout.plotCornerXZ(index)
    local corner = Vector3.new(cornerX, 0, cornerZ)

    local model = Instance.new("Model")
    model.Name = `Plot_{index}`
    model:SetAttribute("OwnerUserId", player.UserId)
    model:SetAttribute("PlotIndex", index)

    local center = corner + Vector3.new(PLOT_STUDS / 2, 0, PLOT_STUDS / 2)
    local base = makePart({
        name = "Base",
        size = Vector3.new(PLOT_STUDS, 1, PLOT_STUDS),
        cframe = CFrame.new(center.X, BASE_TOP - 0.5, center.Z),
        color = Color3.fromRGB(96, 140, 78),
        material = Enum.Material.Grass,
        parent = model,
    })
    base:SetAttribute("OwnerUserId", player.UserId)

    -- Low border so plot bounds are readable while building.
    local borderColor = Color3.fromRGB(200, 186, 150)
    local half = PLOT_STUDS / 2
    for _, edge in ipairs({
        { Vector3.new(0, 0, -half), Vector3.new(PLOT_STUDS, 0.6, 0.6) },
        { Vector3.new(0, 0, half), Vector3.new(PLOT_STUDS, 0.6, 0.6) },
        { Vector3.new(-half, 0, 0), Vector3.new(0.6, 0.6, PLOT_STUDS) },
        { Vector3.new(half, 0, 0), Vector3.new(0.6, 0.6, PLOT_STUDS) },
    }) do
        makePart({
            name = "Border",
            size = edge[2],
            cframe = CFrame.new(center + edge[1] + Vector3.new(0, BASE_TOP + 0.3, 0)),
            color = borderColor,
            canCollide = false,
            parent = model,
        })
    end

    local sign = makePart({
        name = "Sign",
        size = Vector3.new(1, 1, 1),
        cframe = CFrame.new(corner + Vector3.new(PLOT_STUDS / 2, BASE_TOP + 0.5, -2)),
        color = borderColor,
        canCollide = false,
        parent = model,
    })
    sign.Transparency = 1
    makeBillboard(sign, { `{player.DisplayName}'s Empire` }, 10)

    local buildings = Instance.new("Folder")
    buildings.Name = "Buildings"
    buildings.Parent = model

    model.PrimaryPart = base
    model.Parent = self._folder

    self._plots[player] = {
        index = index,
        model = model,
        buildings = buildings,
        corner = corner,
        signatures = {},
        characterConnection = nil,
    }

    player:SetAttribute("PlotCorner", corner)
    player:SetAttribute("PlotIndex", index)

    self._plots[player].characterConnection = player.CharacterAdded:Connect(function(character)
        self:_moveToPlot(player, character)
    end)
    if player.Character ~= nil then
        self:_moveToPlot(player, player.Character)
    end
end

-- Spawn just outside the plot's south edge, facing into it, so buildings can never cover it.
local function spawnCFrame(record: PlotRecord): CFrame
    local spawnPoint = record.corner + Vector3.new(PLOT_STUDS / 2, BASE_TOP + 4, -6)
    return CFrame.lookAt(spawnPoint, spawnPoint + Vector3.new(0, 0, 1))
end

function PlotService._moveToPlot(self: PlotService, player: Player, character: Model)
    local record = self._plots[player]
    if record == nil then
        return
    end
    task.spawn(function()
        -- CharacterAdded can fire before the character is parented or has its root part, so
        -- wait (bounded) until it is in the world before moving it.
        local deadline = os.clock() + 10
        while not character:IsDescendantOf(Workspace) and os.clock() < deadline do
            task.wait(0.1)
        end
        local root = character:WaitForChild("HumanoidRootPart", math.max(0, deadline - os.clock()))
        if
            root == nil
            or not character:IsDescendantOf(Workspace)
            or self._plots[player] ~= record
        then
            return
        end
        -- Let the engine's own spawn placement finish before overriding it.
        task.wait()
        character:PivotTo(spawnCFrame(record))
    end)
end

-- Moves the player's character to their plot. Returns false when they have no plot or
-- character yet.
function PlotService.sendHome(self: PlotService, player: Player): boolean
    local character = player.Character
    if self._plots[player] == nil or character == nil then
        return false
    end
    self:_moveToPlot(player, character)
    return true
end

function PlotService.release(self: PlotService, player: Player)
    local record = self._plots[player]
    if record == nil then
        return
    end
    self._plots[player] = nil
    self._usedSlots[record.index] = nil
    if record.characterConnection ~= nil then
        record.characterConnection:Disconnect()
    end
    record.model:Destroy()
end

local function signatureFor(building: any): string
    return table.concat({
        building.definitionId,
        tostring(building.level),
        tostring(building.position.x),
        tostring(building.position.z),
        tostring(building.rotation),
        table.concat(building.assignedCreatureIds, ","),
    }, "|")
end

function PlotService._buildModel(
    _self: PlotService,
    player: Player,
    record: PlotRecord,
    building: any,
    profile: any
)
    local definition = BuildingDefinitions.ById[building.definitionId]
    if definition == nil then
        return
    end

    local width, depth = PlacementDomain.footprintFor(definition, building.rotation)
    local height = 5 + definition.footprint.x + building.level
    local center = record.corner
        + Vector3.new(
            (building.position.x + width / 2) * CELL,
            BASE_TOP,
            (building.position.z + depth / 2) * CELL
        )
    local rotation = CFrame.Angles(0, math.rad(building.rotation), 0)
    local color = toColor(definition.color)

    local model = Instance.new("Model")
    model.Name = building.id
    model:SetAttribute("BuildingId", building.id)
    model:SetAttribute("DefinitionId", building.definitionId)
    model:SetAttribute("OwnerUserId", player.UserId)

    local body = makePart({
        name = "Body",
        size = Vector3.new(
            definition.footprint.x * CELL - 0.8,
            height,
            definition.footprint.z * CELL - 0.8
        ),
        cframe = CFrame.new(center + Vector3.new(0, height / 2, 0)) * rotation,
        color = color,
        parent = model,
    })
    body:SetAttribute("BuildingId", building.id)
    body:SetAttribute("OwnerUserId", player.UserId)

    local roof = makePart({
        name = "Roof",
        size = Vector3.new(definition.footprint.x * CELL, 1, definition.footprint.z * CELL),
        cframe = CFrame.new(center + Vector3.new(0, height + 0.5, 0)) * rotation,
        color = color:Lerp(Color3.new(0, 0, 0), 0.35),
        parent = model,
    })
    roof:SetAttribute("BuildingId", building.id)
    roof:SetAttribute("OwnerUserId", player.UserId)

    local workerText = if definition.maxWorkers > 0
        then `Workers {#building.assignedCreatureIds}/{definition.maxWorkers}`
        else definition.description
    makeBillboard(
        body,
        { `{definition.displayName}  Lv {building.level}`, workerText },
        height / 2 + 3
    )

    -- Assigned workers stand along the front of the building (presentation only).
    for index, creatureId in ipairs(building.assignedCreatureIds) do
        local creature = profile.creatures[creatureId]
        local species = if creature ~= nil
            then CreatureDefinitions.ById[creature.speciesId]
            else nil
        if species ~= nil then
            local offset = Vector3.new((index - 1.5) * 3.5, 1.5, -(depth * CELL) / 2 - 2)
            makePart({
                name = "Worker",
                size = Vector3.new(2.6, 2.6, 2.6),
                cframe = CFrame.new(center + offset),
                color = toColor(species.color),
                material = Enum.Material.SmoothPlastic,
                shape = Enum.PartType.Ball,
                canCollide = false,
                parent = model,
            })
        end
    end

    model.PrimaryPart = body
    model.Parent = record.buildings
end

-- Brings the rendered plot in line with the profile, rebuilding only changed buildings.
function PlotService.render(self: PlotService, player: Player, profile: any)
    local record = self._plots[player]
    if record == nil then
        return
    end

    for buildingId, building in pairs(profile.buildings) do
        local signature = signatureFor(building)
        if record.signatures[buildingId] ~= signature then
            local existing = record.buildings:FindFirstChild(buildingId)
            if existing ~= nil then
                existing:Destroy()
            end
            self:_buildModel(player, record, building, profile)
            record.signatures[buildingId] = signature
        end
    end

    for buildingId in pairs(record.signatures) do
        if profile.buildings[buildingId] == nil then
            local existing = record.buildings:FindFirstChild(buildingId)
            if existing ~= nil then
                existing:Destroy()
            end
            record.signatures[buildingId] = nil
        end
    end
end

function PlotService.start(self: PlotService)
    Players.PlayerRemoving:Connect(function(player)
        self:release(player)
    end)
end

return PlotService
