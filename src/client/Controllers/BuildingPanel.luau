-- Selecting an owned building opens its panel: production, workers, claim, upgrade, remove.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local BuildingDefinitions = require(Shared.Buildings.BuildingDefinitions)
local CreatureDefinitions = require(Shared.Creatures.CreatureDefinitions)
local UpgradeDomain = require(Shared.Buildings.UpgradeDomain)
local CapacityDomain = require(Shared.Economy.CapacityDomain)
local InventoryDomain = require(Shared.Economy.InventoryDomain)
local TableUtil = require(Shared.Util.TableUtil)

local Theme = require("../UI/Theme")
local Widgets = require("../UI/Widgets")
local Format = require("../UI/Format")

local BuildingPanel = {}
BuildingPanel.__index = BuildingPanel

export type BuildingPanel = typeof(setmetatable(
    {} :: {
        _hud: any,
        _state: any,
        _actions: any,
        _build: any,
        _buildingId: string?,
        _readyLabel: TextLabel?,
        _confirmRemove: boolean,
    },
    BuildingPanel
))

function BuildingPanel.new(hud: any, state: any, actions: any, build: any): BuildingPanel
    return setmetatable({
        _hud = hud,
        _state = state,
        _actions = actions,
        _build = build,
        _buildingId = nil,
        _readyLabel = nil,
        _confirmRemove = false,
    }, BuildingPanel)
end

local function ownPlotBuildings(): Folder?
    local plots = Workspace:FindFirstChild("Plots")
    if plots == nil then
        return nil
    end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
            local buildings = plot:FindFirstChild("Buildings")
            if buildings ~= nil and buildings:IsA("Folder") then
                return buildings
            end
        end
    end
    return nil
end

-- Pending whole cycles since the last claim, as an estimate from replicated data.
local function pendingCycles(snapshot: any, building: any, rate: number, serverNow: number): number
    local elapsed = math.clamp(serverNow - building.lastClaimedAt, 0, snapshot.offlineCapSeconds)
    return math.max(0, math.floor(rate / 60 * elapsed + 1e-9))
end

local function section(parent: Instance, text: string, order: number)
    Widgets.label({
        parent = parent,
        text = text,
        bold = true,
        color = Theme.TextMuted,
        textSize = 14,
        order = order,
    })
end

function BuildingPanel._render(self: BuildingPanel, content: ScrollingFrame, snapshot: any)
    local profile = snapshot.profile
    local buildingId = self._buildingId
    local building = if buildingId ~= nil then profile.buildings[buildingId] else nil
    if building == nil then
        self._hud:closePanel()
        return
    end

    local definition = BuildingDefinitions.ById[building.definitionId]
    self._hud:setPanelTitle(`{definition.displayName}  Lv {building.level}`)
    local order = 0
    local function nextOrder(): number
        order += 1
        return order
    end

    Widgets.label({
        parent = content,
        text = definition.description,
        wrap = true,
        autoHeight = true,
        color = Theme.TextMuted,
        order = nextOrder(),
    })

    if definition.kind == "production" then
        local rate = snapshot.rates[building.id] or 0
        Widgets.label({
            parent = content,
            text = `Rate: {Format.rate(rate)} (Lv {building.level} bonus x{1 + (building.level - 1) * GameConfig.BUILDING_LEVEL_OUTPUT_BONUS})`,
            order = nextOrder(),
        })
        Widgets.label({
            parent = content,
            text = `Each cycle makes {Format.items(definition.outputs)}`,
            wrap = true,
            autoHeight = true,
            order = nextOrder(),
        })
        if next(definition.inputs) ~= nil then
            Widgets.label({
                parent = content,
                text = `Each cycle uses {Format.items(definition.inputs)}`,
                wrap = true,
                autoHeight = true,
                color = Theme.Warning,
                order = nextOrder(),
            })
        end
        self._readyLabel = Widgets.label({
            parent = content,
            text = "",
            color = Theme.Coin,
            bold = true,
            order = nextOrder(),
        })
        self:_updateReady()

        section(
            content,
            `Workers {#building.assignedCreatureIds}/{definition.maxWorkers}`,
            nextOrder()
        )
        for _, creatureId in ipairs(building.assignedCreatureIds) do
            local creature = profile.creatures[creatureId]
            if creature ~= nil then
                local species = CreatureDefinitions.ById[creature.speciesId]
                local row = Widgets.frame({
                    name = creatureId,
                    parent = content,
                    size = UDim2.new(1, -8, 0, 34),
                    color = Theme.Surface,
                    order = nextOrder(),
                })
                Widgets.label({
                    parent = row,
                    text = `{species.displayName} Lv {creature.level}`,
                    size = UDim2.new(1, -110, 1, 0),
                    position = UDim2.fromOffset(10, 0),
                })
                Widgets.button({
                    parent = row,
                    text = "Unassign",
                    size = UDim2.fromOffset(96, 26),
                    position = UDim2.new(1, -6, 0.5, 0),
                    anchor = Vector2.new(1, 0.5),
                    color = Theme.SurfaceRaised,
                    textSize = 13,
                    onActivated = function()
                        self._actions:send("UnassignCreature", { creatureId = creatureId })
                    end,
                })
            end
        end

        if #building.assignedCreatureIds < definition.maxWorkers then
            local candidates = 0
            for _, creatureId in ipairs(TableUtil.sortedKeys(profile.creatures)) do
                local creature = profile.creatures[creatureId]
                local species = CreatureDefinitions.ById[creature.speciesId]
                local affinity = if species ~= nil
                    then species.workAffinity[definition.workType]
                    else nil
                if creature.assignedBuildingId == nil and affinity ~= nil and affinity > 0 then
                    candidates += 1
                    Widgets.button({
                        parent = content,
                        text = `Assign {species.displayName} Lv {creature.level} (x{affinity})`,
                        size = UDim2.new(1, -8, 0, 30),
                        color = Theme.AccentDark,
                        textSize = 13,
                        order = nextOrder(),
                        onActivated = function()
                            self._actions:send(
                                "AssignCreature",
                                { creatureId = creatureId, buildingId = building.id }
                            )
                        end,
                    })
                end
            end
            if candidates == 0 then
                Widgets.label({
                    parent = content,
                    text = `No idle creature can do {definition.workType} work. Capture one in the Wilds.`,
                    wrap = true,
                    autoHeight = true,
                    color = Theme.TextMuted,
                    textSize = 13,
                    order = nextOrder(),
                })
            end
        end

        Widgets.button({
            parent = content,
            text = "Claim",
            size = UDim2.new(1, -8, 0, 34),
            order = nextOrder(),
            onActivated = function()
                self._actions:send(
                    "ClaimProduction",
                    { buildingId = building.id },
                    function(result: any)
                        if result.ok and type(result.value) == "table" then
                            local produced = result.value.produced or {}
                            if next(produced) ~= nil then
                                self._hud.toasts:show("gain", `Claimed {Format.items(produced)}`)
                            end
                            if result.value.limitedBy == "storage" then
                                self._hud.toasts:show(
                                    "error",
                                    "Storage is full. Build or upgrade a Warehouse."
                                )
                            elseif result.value.limitedBy == "input" then
                                self._hud.toasts:show(
                                    "error",
                                    `Out of {Format.items(definition.inputs)} inputs.`
                                )
                            end
                        end
                    end
                )
            end,
        })
    elseif definition.utility == "storage" then
        Widgets.label({
            parent = content,
            text = `Adds {GameConfig.WAREHOUSE_STORAGE_PER_LEVEL * building.level} storage per resource.`,
            wrap = true,
            autoHeight = true,
            order = nextOrder(),
        })
    elseif definition.utility == "habitat" then
        Widgets.label({
            parent = content,
            text = `Houses {GameConfig.HABITAT_CREATURE_CAPACITY_PER_LEVEL * building.level} extra creatures.`,
            wrap = true,
            autoHeight = true,
            order = nextOrder(),
        })
    end

    section(content, "Upgrade", nextOrder())
    if building.level >= GameConfig.MAX_BUILDING_LEVEL then
        Widgets.label({
            parent = content,
            text = "Maximum level reached.",
            color = Theme.TextMuted,
            order = nextOrder(),
        })
    else
        local cost = UpgradeDomain.costFor(building.definitionId, building.level + 1)
        local hasBench = CapacityDomain.hasUtility(profile, "workbench")
        local affordable = cost ~= nil
            and InventoryDomain.canAfford(profile, cost.items)
            and profile.currencies.coins >= cost.coins
        if cost ~= nil then
            Widgets.label({
                parent = content,
                text = `Lv {building.level + 1}: {Format.items(cost.items)}, {cost.coins} coins`,
                wrap = true,
                autoHeight = true,
                color = if affordable then Theme.Text else Theme.Danger,
                textSize = 13,
                order = nextOrder(),
            })
        end
        Widgets.button({
            parent = content,
            text = if not hasBench
                then "Needs a Workbench"
                elseif affordable then "Upgrade"
                else "Can't afford",
            size = UDim2.new(1, -8, 0, 34),
            enabled = hasBench and affordable,
            order = nextOrder(),
            onActivated = function()
                self._actions:send(
                    "UpgradeBuilding",
                    { buildingId = building.id },
                    function(result: any)
                        if result.ok then
                            self._hud.toasts:show("gain", `{definition.displayName} upgraded!`)
                        end
                    end
                )
            end,
        })
    end

    local refund = {}
    for itemId, quantity in pairs(definition.cost) do
        refund[itemId] = math.floor(quantity * GameConfig.REMOVE_REFUND_RATIO)
    end
    Widgets.button({
        parent = content,
        text = if self._confirmRemove
            then "Tap again to confirm removal"
            else `Remove (refund {Format.items(refund)})`,
        size = UDim2.new(1, -8, 0, 34),
        color = Theme.Danger,
        textSize = 13,
        order = nextOrder(),
        onActivated = function()
            if not self._confirmRemove then
                self._confirmRemove = true
                self._hud:refreshPanel()
                return
            end
            self._confirmRemove = false
            self._actions:send("RemoveBuilding", { buildingId = building.id })
        end,
    })
end

function BuildingPanel._updateReady(self: BuildingPanel)
    local label = self._readyLabel
    local snapshot = self._state:get()
    local buildingId = self._buildingId
    if label == nil or label.Parent == nil or snapshot == nil or buildingId == nil then
        return
    end
    local building = snapshot.profile.buildings[buildingId]
    if building == nil then
        return
    end
    local rate = snapshot.rates[buildingId] or 0
    if rate <= 0 then
        label.Text = "Idle: assign a worker to start production."
        return
    end
    local cycles = pendingCycles(snapshot, building, rate, self._state:serverNow())
    label.Text = `Ready to claim: about {cycles} cycles`
end

function BuildingPanel.open(self: BuildingPanel, buildingId: string)
    self._buildingId = buildingId
    self._confirmRemove = false
    self._hud:openPanel("building", "Building", function(content: ScrollingFrame, snapshot: any)
        self:_render(content, snapshot)
    end)
end

function BuildingPanel._select(self: BuildingPanel, ray: Ray)
    local buildings = ownPlotBuildings()
    if buildings == nil then
        return
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { buildings }
    local hit = Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
    if hit == nil then
        return
    end
    local buildingId = hit.Instance:GetAttribute("BuildingId")
    if type(buildingId) == "string" then
        self:open(buildingId)
    end
end

function BuildingPanel.start(self: BuildingPanel)
    UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
        if processed or self._build:isPlacing() then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local camera = Workspace.CurrentCamera
            if camera ~= nil then
                local mouse = UserInputService:GetMouseLocation()
                self:_select(camera:ViewportPointToRay(mouse.X, mouse.Y))
            end
        end
    end)

    UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processed: boolean)
        if processed or self._build:isPlacing() then
            return
        end
        local camera = Workspace.CurrentCamera
        if camera ~= nil then
            self:_select(camera:ScreenPointToRay(position.X, position.Y))
        end
    end)

    task.spawn(function()
        while true do
            task.wait(1)
            if self._hud:panelName() == "building" then
                self:_updateReady()
            end
        end
    end)
end

return BuildingPanel
