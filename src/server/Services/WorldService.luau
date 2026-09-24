--[[
    WorldService builds the shared world and owns the Wilds exploration zone: gathering nodes
    and wild creature spawns. Interactions use server-owned ProximityPrompts; the server
    re-checks range, cooldowns and capture rolls, so no client input decides an outcome.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureDefinitions = require(Shared.Creatures.CreatureDefinitions)
local CreatureOwnershipDomain = require(Shared.Creatures.CreatureOwnershipDomain)
local CapacityDomain = require(Shared.Economy.CapacityDomain)
local ItemDefinitions = require(Shared.Items.ItemDefinitions)
local ResourceNodeDefinitions = require(Shared.World.ResourceNodeDefinitions)
local GatheringDomain = require(Shared.World.GatheringDomain)
local WorldLayout = require(Shared.World.WorldLayout)

local Logger = require("./Logger")

local logger = Logger.new("World")

local WORLD_SEED = 20260908
local TREE_COUNT = 34
local ROCK_COUNT = 26
local CREATURE_SPAWN_COUNT = 14
local PROMPT_RANGE = 12
local RANGE_TOLERANCE = 8
local CAPTURE_COOLDOWN_SECONDS = 2
local RESPAWN_MIN_SECONDS = 20
local RESPAWN_MAX_SECONDS = 40
local WANDER_RADIUS = 14

type CreatureSpawn = {
    id: string,
    origin: Vector3,
    part: Part?,
    speciesId: string?,
}

local WorldService = {}
WorldService.__index = WorldService

export type WorldService = typeof(setmetatable(
    {} :: {
        _actionService: any,
        _network: any,
        _random: Random,
        _worldRandom: Random,
        _folder: Folder,
        _cooldowns: { [Player]: { [string]: number } },
        _spawns: { CreatureSpawn },
    },
    WorldService
))

local function makePart(
    name: string,
    size: Vector3,
    cframe: CFrame,
    color: Color3,
    parent: Instance
): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.Size = size
    part.CFrame = cframe
    part.Color = color
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = parent
    return part
end

local function makePrompt(
    parent: BasePart,
    actionText: string,
    objectText: string,
    holdDuration: number
): ProximityPrompt
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = actionText
    prompt.ObjectText = objectText
    prompt.HoldDuration = holdDuration
    prompt.MaxActivationDistance = PROMPT_RANGE
    prompt.RequiresLineOfSight = false
    prompt.Parent = parent
    return prompt
end

local function makeLabel(adornee: BasePart, text: string, color: Color3, offsetY: number)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Label"
    billboard.Adornee = adornee
    billboard.Size = UDim2.fromOffset(160, 24)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
    billboard.MaxDistance = 90
    billboard.LightInfluence = 0

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 16
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.3
    label.Text = text
    label.Parent = billboard

    billboard.Parent = adornee
end

function WorldService.new(options: { actionService: any, network: any }): WorldService
    local folder = Instance.new("Folder")
    folder.Name = "World"
    folder.Parent = Workspace

    return setmetatable({
        _actionService = options.actionService,
        _network = options.network,
        _random = Random.new(),
        _worldRandom = Random.new(WORLD_SEED),
        _folder = folder,
        _cooldowns = {},
        _spawns = {},
    }, WorldService)
end

-- Returns true when the player's character is close enough to `part` to interact.
function WorldService._inRange(_self: WorldService, player: Player, part: BasePart): boolean
    local character = player.Character
    local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
    if root == nil or not root:IsA("BasePart") then
        return false
    end
    return (root.Position - part.Position).Magnitude <= PROMPT_RANGE + RANGE_TOLERANCE
end

-- Consumes a per-player cooldown. Returns false while the cooldown is still running.
function WorldService._consumeCooldown(
    self: WorldService,
    player: Player,
    key: string,
    seconds: number
): boolean
    local cooldowns = self._cooldowns[player]
    if cooldowns == nil then
        cooldowns = {}
        self._cooldowns[player] = cooldowns
    end
    local now = os.clock()
    local readyAt = cooldowns[key]
    if readyAt ~= nil and now < readyAt then
        return false
    end
    cooldowns[key] = now + seconds
    return true
end

function WorldService._randomWildsPoint(self: WorldService, margin: number): Vector3
    local center = WorldLayout.WILDS_CENTER
    local radius = WorldLayout.WILDS_RADIUS - margin
    local angle = self._worldRandom:NextNumber(0, math.pi * 2)
    local distance = math.sqrt(self._worldRandom:NextNumber()) * radius
    return Vector3.new(
        center.x + math.cos(angle) * distance,
        0,
        center.z + math.sin(angle) * distance
    )
end

function WorldService._buildTerrain(self: WorldService)
    local ground = makePart(
        "Ground",
        Vector3.new(WorldLayout.GROUND_SIZE.x, 2, WorldLayout.GROUND_SIZE.z),
        CFrame.new(0, -1, 0),
        Color3.fromRGB(108, 156, 86),
        self._folder
    )
    ground.Material = Enum.Material.Grass

    local center = WorldLayout.WILDS_CENTER
    local wilds = makePart(
        "WildsFloor",
        Vector3.new(WorldLayout.WILDS_RADIUS * 2, 0.2, WorldLayout.WILDS_RADIUS * 2),
        CFrame.new(center.x, 0.1, center.z) * CFrame.Angles(0, 0, math.rad(90)),
        Color3.fromRGB(82, 124, 64),
        self._folder
    )
    wilds.Shape = Enum.PartType.Cylinder
    wilds.Size = Vector3.new(0.2, WorldLayout.WILDS_RADIUS * 2, WorldLayout.WILDS_RADIUS * 2)
    wilds.Material = Enum.Material.LeafyGrass
    wilds.CanCollide = false

    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "Spawn"
    spawn.Anchored = true
    spawn.Neutral = true
    spawn.Size = Vector3.new(12, 1, 12)
    spawn.CFrame = CFrame.new(WorldLayout.SPAWN_POSITION.x, 0.5, WorldLayout.SPAWN_POSITION.z)
    spawn.Color = Color3.fromRGB(230, 220, 190)
    spawn.Duration = 0
    spawn.Parent = self._folder

    -- Path from the spawn to the Wilds.
    local pathLength = math.abs(center.z) - WorldLayout.WILDS_RADIUS + 10
    local path = makePart(
        "Path",
        Vector3.new(10, 0.2, pathLength),
        CFrame.new(center.x, 0.1, -pathLength / 2),
        Color3.fromRGB(196, 170, 120),
        self._folder
    )
    path.Material = Enum.Material.Ground
    path.CanCollide = false

    local archZ = center.z + WorldLayout.WILDS_RADIUS
    local archColor = Color3.fromRGB(120, 86, 52)
    makePart(
        "ArchLeft",
        Vector3.new(2, 14, 2),
        CFrame.new(center.x - 8, 7, archZ),
        archColor,
        self._folder
    )
    makePart(
        "ArchRight",
        Vector3.new(2, 14, 2),
        CFrame.new(center.x + 8, 7, archZ),
        archColor,
        self._folder
    )
    local beam = makePart(
        "ArchBeam",
        Vector3.new(20, 2, 2),
        CFrame.new(center.x, 14, archZ),
        archColor,
        self._folder
    )
    makeLabel(beam, "The Wilds", Color3.fromRGB(255, 240, 200), 3)
end

function WorldService._buildNode(self: WorldService, nodeDefinitionId: string, index: number)
    local definition = ResourceNodeDefinitions.ById[nodeDefinitionId]
    local position = self:_randomWildsPoint(10)
    local model = Instance.new("Model")
    model.Name = `{nodeDefinitionId}_{index}`

    local interactPart: Part
    if nodeDefinitionId == "node_tree" then
        interactPart = makePart(
            "Trunk",
            Vector3.new(2, 10, 2),
            CFrame.new(position + Vector3.new(0, 5, 0)),
            Color3.fromRGB(110, 76, 46),
            model
        )
        local leaves = makePart(
            "Leaves",
            Vector3.new(9, 9, 9),
            CFrame.new(position + Vector3.new(0, 12, 0)),
            Color3.fromRGB(64, 132, 56),
            model
        )
        leaves.Shape = Enum.PartType.Ball
        leaves.Material = Enum.Material.Grass
    else
        interactPart = makePart(
            "Rock",
            Vector3.new(5, 4, 5),
            CFrame.new(position + Vector3.new(0, 2, 0))
                * CFrame.Angles(0, self._worldRandom:NextNumber(0, math.pi), 0),
            Color3.fromRGB(130, 130, 136),
            model
        )
        interactPart.Material = Enum.Material.Slate
    end

    local nodeKey = model.Name
    local prompt = makePrompt(interactPart, definition.actionText, definition.displayName, 0.25)
    prompt.Triggered:Connect(function(player: Player)
        self:_gather(player, interactPart, nodeKey, nodeDefinitionId)
    end)

    model.Parent = self._folder
end

function WorldService._gather(
    self: WorldService,
    player: Player,
    part: BasePart,
    nodeKey: string,
    nodeDefinitionId: string
)
    local definition = ResourceNodeDefinitions.ById[nodeDefinitionId]
    if not self:_inRange(player, part) then
        return
    end
    if not self:_consumeCooldown(player, nodeKey, definition.cooldownSeconds) then
        self._network:notify(
            player,
            "info",
            `That {string.lower(definition.displayName)} needs a moment to recover.`
        )
        return
    end

    local result = self._actionService:mutate(player, "Gather", function(draft)
        return GatheringDomain.gather(draft, nodeDefinitionId)
    end)

    if result.ok then
        local item = ItemDefinitions.ById[result.value.itemId]
        self._network:notify(player, "gain", `+{result.value.quantity} {item.displayName}`)
    else
        self._network:notify(player, "error", result.message)
    end
end

function WorldService._pickSpecies(self: WorldService): string
    local total = 0
    for _, speciesId in ipairs(CreatureDefinitions.Ids) do
        total += CreatureDefinitions.ById[speciesId].spawnWeight
    end
    local roll = self._random:NextNumber(0, total)
    for _, speciesId in ipairs(CreatureDefinitions.Ids) do
        roll -= CreatureDefinitions.ById[speciesId].spawnWeight
        if roll <= 0 then
            return speciesId
        end
    end
    return CreatureDefinitions.Ids[1]
end

function WorldService._spawnCreature(self: WorldService, spawnPoint: CreatureSpawn)
    local speciesId = self:_pickSpecies()
    local species = CreatureDefinitions.ById[speciesId]
    local color = Color3.fromRGB(species.color.r, species.color.g, species.color.b)

    local part = makePart(
        `Wild_{spawnPoint.id}`,
        Vector3.new(3.2, 3.2, 3.2),
        CFrame.new(spawnPoint.origin + Vector3.new(0, 1.6, 0)),
        color,
        self._folder
    )
    part.Shape = Enum.PartType.Ball
    part.CanCollide = false
    part:SetAttribute("SpeciesId", speciesId)
    makeLabel(part, `Wild {species.displayName}`, color:Lerp(Color3.new(1, 1, 1), 0.5), 3)

    local prompt = makePrompt(part, "Capture", species.displayName, 0.75)
    prompt.Triggered:Connect(function(player: Player)
        self:_capture(player, spawnPoint, part)
    end)

    spawnPoint.part = part
    spawnPoint.speciesId = speciesId

    task.spawn(function()
        while spawnPoint.part == part and part.Parent ~= nil do
            local angle = self._random:NextNumber(0, math.pi * 2)
            local distance = self._random:NextNumber(0, WANDER_RADIUS)
            local target = spawnPoint.origin
                + Vector3.new(math.cos(angle) * distance, 1.6, math.sin(angle) * distance)
            local duration = self._random:NextNumber(2.5, 4.5)
            TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Sine), {
                CFrame = CFrame.new(target),
            }):Play()
            task.wait(duration + self._random:NextNumber(1, 3))
        end
    end)
end

function WorldService._despawn(self: WorldService, spawnPoint: CreatureSpawn)
    local part = spawnPoint.part
    spawnPoint.part = nil
    spawnPoint.speciesId = nil
    if part ~= nil then
        part:Destroy()
    end
    task.delay(self._random:NextNumber(RESPAWN_MIN_SECONDS, RESPAWN_MAX_SECONDS), function()
        if spawnPoint.part == nil then
            self:_spawnCreature(spawnPoint)
        end
    end)
end

function WorldService._capture(
    self: WorldService,
    player: Player,
    spawnPoint: CreatureSpawn,
    part: Part
)
    -- The creature may have been captured by someone else since the prompt was shown.
    if spawnPoint.part ~= part or spawnPoint.speciesId == nil then
        return
    end
    if not self:_inRange(player, part) then
        return
    end
    if not self:_consumeCooldown(player, "capture", CAPTURE_COOLDOWN_SECONDS) then
        return
    end

    local speciesId = spawnPoint.speciesId :: string
    local species = CreatureDefinitions.ById[speciesId]

    local profile = self._actionService:getProfile(player)
    if profile == nil then
        return
    end
    if not CapacityDomain.hasCreatureSpace(profile) then
        self._network:notify(
            player,
            "error",
            "Your habitats are full. Build or upgrade a Creature Habitat."
        )
        return
    end

    local succeeded = self._random:NextNumber() < species.captureChance
    if not succeeded then
        self._network:notify(player, "info", `The {species.displayName} broke free! Try again.`)
        return
    end

    local actionService = self._actionService
    local result = actionService:mutate(player, "Capture", function(draft)
        return CreatureOwnershipDomain.capture(draft, speciesId, true, function()
            return actionService:generateId("c")
        end)
    end)

    if result.ok then
        self._network:notify(player, "gain", `You captured a {species.displayName}!`)
        self:_despawn(spawnPoint)
    else
        self._network:notify(player, "error", result.message)
    end
end

function WorldService.start(self: WorldService)
    self:_buildTerrain()

    for index = 1, TREE_COUNT do
        self:_buildNode("node_tree", index)
    end
    for index = 1, ROCK_COUNT do
        self:_buildNode("node_rock", index)
    end

    for index = 1, CREATURE_SPAWN_COUNT do
        local spawnPoint: CreatureSpawn = {
            id = tostring(index),
            origin = self:_randomWildsPoint(20),
            part = nil,
            speciesId = nil,
        }
        table.insert(self._spawns, spawnPoint)
        self:_spawnCreature(spawnPoint)
    end

    Players.PlayerRemoving:Connect(function(player)
        self._cooldowns[player] = nil
    end)

    logger.info("world built", {
        trees = TREE_COUNT,
        rocks = ROCK_COUNT,
        creatureSpawns = CREATURE_SPAWN_COUNT,
    })
end

return WorldService
