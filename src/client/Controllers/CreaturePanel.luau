-- Lists owned creatures with their level, job and quick actions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureDefinitions = require(Shared.Creatures.CreatureDefinitions)
local CreatureProgression = require(Shared.Creatures.CreatureProgression)
local BuildingDefinitions = require(Shared.Buildings.BuildingDefinitions)
local GameConfig = require(Shared.Config.GameConfig)
local TableUtil = require(Shared.Util.TableUtil)

local Theme = require("../UI/Theme")
local Widgets = require("../UI/Widgets")

local CreaturePanel = {}
CreaturePanel.__index = CreaturePanel

export type CreaturePanel = typeof(setmetatable(
    {} :: {
        _hud: any,
        _actions: any,
        _confirmRelease: string?,
    },
    CreaturePanel
))

function CreaturePanel.new(hud: any, actions: any): CreaturePanel
    return setmetatable({ _hud = hud, _actions = actions, _confirmRelease = nil }, CreaturePanel)
end

function CreaturePanel._render(self: CreaturePanel, content: ScrollingFrame, snapshot: any)
    local profile = snapshot.profile
    self._hud:setPanelTitle(`Creatures {snapshot.creatureCount}/{snapshot.creatureCapacity}`)

    Widgets.label({
        parent = content,
        text = "Capture wild creatures in the Wilds. Assign workers from a building's panel.",
        wrap = true,
        autoHeight = true,
        color = Theme.TextMuted,
        textSize = 13,
        order = 0,
    })

    for index, creatureId in ipairs(TableUtil.sortedKeys(profile.creatures)) do
        local creature = profile.creatures[creatureId]
        local species = CreatureDefinitions.ById[creature.speciesId]
        local assigned = creature.assignedBuildingId
        local building = if assigned ~= nil then profile.buildings[assigned] else nil
        local buildingName = if building ~= nil
            then BuildingDefinitions.ById[building.definitionId].displayName
            else nil

        local card = Widgets.frame({
            name = creatureId,
            parent = content,
            size = UDim2.new(1, -8, 0, 0),
            color = Theme.Surface,
            order = index,
        })
        card.AutomaticSize = Enum.AutomaticSize.Y
        Widgets.padding(card)
        Widgets.list(card, Enum.FillDirection.Vertical, 3)

        local experienceText = if creature.level >= GameConfig.MAX_CREATURE_LEVEL
            then "max level"
            else `{creature.experience}/{CreatureProgression.experienceToNextLevel(
                creature.level
            )} xp`
        Widgets.label({
            parent = card,
            text = `{species.displayName}  Lv {creature.level}  ({experienceText})`,
            bold = true,
            order = 1,
        })

        local affinities = {}
        for workType, affinity in pairs(species.workAffinity) do
            table.insert(affinities, `{workType} x{affinity}`)
        end
        table.sort(affinities)
        Widgets.label({
            parent = card,
            text = `{species.element} - {table.concat(affinities, ", ")}`,
            color = Theme.TextMuted,
            textSize = 13,
            order = 2,
        })
        Widgets.label({
            parent = card,
            text = if buildingName ~= nil then `Working at {buildingName}` else "Idle",
            color = if buildingName ~= nil then Theme.Accent else Theme.Warning,
            textSize = 13,
            order = 3,
        })

        if assigned ~= nil then
            Widgets.button({
                parent = card,
                text = "Unassign",
                size = UDim2.fromOffset(110, 28),
                color = Theme.SurfaceRaised,
                textSize = 13,
                order = 4,
                onActivated = function()
                    self._actions:send("UnassignCreature", { creatureId = creatureId })
                end,
            })
        elseif snapshot.creatureCount > 1 then
            local confirming = self._confirmRelease == creatureId
            Widgets.button({
                parent = card,
                text = if confirming then "Confirm release" else "Release",
                size = UDim2.fromOffset(140, 28),
                color = Theme.Danger,
                textSize = 13,
                order = 4,
                onActivated = function()
                    if not confirming then
                        self._confirmRelease = creatureId
                        self._hud:refreshPanel()
                        return
                    end
                    self._confirmRelease = nil
                    self._actions:send("ReleaseCreature", { creatureId = creatureId })
                end,
            })
        end
    end
end

function CreaturePanel.toggle(self: CreaturePanel)
    self._confirmRelease = nil
    self._hud:togglePanel("creatures", "Creatures", function(content: ScrollingFrame, snapshot: any)
        self:_render(content, snapshot)
    end)
end

return CreaturePanel
