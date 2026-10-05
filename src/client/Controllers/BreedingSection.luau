-- The Breeding Den's part of the building panel: incubating eggs and the parent picker. It only
-- sends intent (StartBreeding, HatchEgg); the server checks every rule and owns the seed, so
-- the baby cannot be influenced from here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BreedingDomain = require(Shared.Creatures.BreedingDomain)
local CreatureDefinitions = require(Shared.Creatures.CreatureDefinitions)
local GameConfig = require(Shared.Config.GameConfig)
local InventoryDomain = require(Shared.Economy.InventoryDomain)
local MutationDefinitions = require(Shared.Creatures.MutationDefinitions)
local TableUtil = require(Shared.Util.TableUtil)

local Format = require("../UI/Format")
local Theme = require("../UI/Theme")
local Widgets = require("../UI/Widgets")

local BreedingSection = {}
BreedingSection.__index = BreedingSection

type Timer = { label: TextLabel, hatchesAt: number }

export type BreedingSection = typeof(setmetatable(
    {} :: {
        _hud: any,
        _state: any,
        _actions: any,
        _selected: { string },
        _timers: { Timer },
    },
    BreedingSection
))

function BreedingSection.new(hud: any, state: any, actions: any): BreedingSection
    return setmetatable({
        _hud = hud,
        _state = state,
        _actions = actions,
        _selected = {},
        _timers = {},
    }, BreedingSection)
end

-- Forget the chosen parents, for example when another building is opened.
function BreedingSection.reset(self: BreedingSection)
    self._selected = {}
end

local function speciesName(speciesId: string): string
    local species = CreatureDefinitions.ById[speciesId]
    return if species ~= nil then species.displayName else speciesId
end

local function remainingText(hatchesAt: number, now: number): string
    if now >= hatchesAt then
        return "Ready to hatch!"
    end
    return `Hatches in {Format.duration(hatchesAt - now)}`
end

function BreedingSection._toggle(self: BreedingSection, creatureId: string)
    local index = table.find(self._selected, creatureId)
    if index ~= nil then
        table.remove(self._selected, index)
    elseif #self._selected < 2 then
        table.insert(self._selected, creatureId)
    else
        -- Replace the older pick so the player never has to deselect first.
        table.remove(self._selected, 1)
        table.insert(self._selected, creatureId)
    end
    self._hud:refreshPanel()
end

function BreedingSection._renderEggs(
    self: BreedingSection,
    content: ScrollingFrame,
    profile: any,
    nextOrder: () -> number
)
    local now = self._state:serverNow()
    for _, eggId in ipairs(TableUtil.sortedKeys(profile.eggs)) do
        local egg = profile.eggs[eggId]
        local row = Widgets.frame({
            name = eggId,
            parent = content,
            size = UDim2.new(1, -8, 0, 0),
            color = Theme.Surface,
            order = nextOrder(),
        })
        row.AutomaticSize = Enum.AutomaticSize.Y
        Widgets.padding(row)
        Widgets.list(row, Enum.FillDirection.Vertical, 3)

        Widgets.label({
            parent = row,
            text = `Egg: {speciesName(egg.parentA.speciesId)} x {speciesName(egg.parentB.speciesId)}`,
            bold = true,
            order = 1,
        })
        local timer = Widgets.label({
            parent = row,
            text = remainingText(egg.hatchesAt, now),
            color = Theme.Coin,
            textSize = 13,
            order = 2,
        })
        table.insert(self._timers, { label = timer, hatchesAt = egg.hatchesAt })

        Widgets.button({
            parent = row,
            text = "Hatch",
            size = UDim2.fromOffset(110, 28),
            textSize = 13,
            order = 3,
            onActivated = function()
                self._actions:send("HatchEgg", { eggId = eggId }, function(result: any)
                    if not result.ok or type(result.value) ~= "table" then
                        return
                    end
                    local baby = result.value.creature
                    local text = `Hatched a {speciesName(baby.speciesId)}!`
                    local mutation = if baby.mutationId ~= nil
                        then MutationDefinitions.ById[baby.mutationId]
                        else nil
                    if mutation ~= nil then
                        text ..= ` It's {mutation.displayName}!`
                    end
                    self._hud.toasts:show("gain", text)
                end)
            end,
        })
    end
end

function BreedingSection._renderParents(
    self: BreedingSection,
    content: ScrollingFrame,
    snapshot: any,
    nextOrder: () -> number
)
    local profile = snapshot.profile
    local now = self._state:serverNow()

    -- Drop picks that are no longer usable (released, assigned or resting since).
    local kept = {}
    for _, creatureId in ipairs(self._selected) do
        local creature = profile.creatures[creatureId]
        if creature ~= nil and BreedingDomain.parentIneligibleReason(creature, now) == nil then
            table.insert(kept, creatureId)
        end
    end
    self._selected = kept

    local usable = 0
    local resting = 0
    for _, creatureId in ipairs(TableUtil.sortedKeys(profile.creatures)) do
        local creature = profile.creatures[creatureId]
        local reason = BreedingDomain.parentIneligibleReason(creature, now)
        if reason == nil then
            usable += 1
            local picked = table.find(self._selected, creatureId) ~= nil
            Widgets.button({
                parent = content,
                text = `{if picked then "[x] " else ""}{speciesName(creature.speciesId)} Lv {creature.level}   {Format.genes(
                    creature.genes
                )}`,
                size = UDim2.new(1, -8, 0, 30),
                color = if picked then Theme.Accent else Theme.SurfaceRaised,
                textSize = 12,
                order = nextOrder(),
                onActivated = function()
                    self:_toggle(creatureId)
                end,
            })
        elseif creature.breedReadyAt ~= nil and creature.breedReadyAt > now then
            resting += 1
        end
    end

    if usable < 2 then
        Widgets.label({
            parent = content,
            text = `Parents must be idle and Lv {GameConfig.BREEDING_MIN_PARENT_LEVEL}+. Level creatures up by working them.`,
            wrap = true,
            autoHeight = true,
            color = Theme.TextMuted,
            textSize = 13,
            order = nextOrder(),
        })
    end
    if resting > 0 then
        Widgets.label({
            parent = content,
            text = `{resting} creature(s) are resting after breeding.`,
            color = Theme.TextMuted,
            textSize = 13,
            order = nextOrder(),
        })
    end

    if #self._selected ~= 2 then
        return
    end

    local first = profile.creatures[self._selected[1]]
    local second = profile.creatures[self._selected[2]]
    local cost = BreedingDomain.costFor(first, second)
    local affordable = profile.currencies.coins >= cost.coins
        and InventoryDomain.canAfford(profile, cost.items)
    local eggCount = 0
    for _ in pairs(profile.eggs) do
        eggCount += 1
    end
    local hasSlot = eggCount < snapshot.breedingSlots

    Widgets.label({
        parent = content,
        text = `Cost: {cost.coins} coins, {Format.items(cost.items)}`,
        color = if affordable then Theme.Text else Theme.Danger,
        textSize = 13,
        order = nextOrder(),
    })
    Widgets.button({
        parent = content,
        text = if not hasSlot
            then "No free egg slot"
            elseif affordable then "Breed"
            else "Can't afford",
        size = UDim2.new(1, -8, 0, 34),
        enabled = affordable and hasSlot,
        order = nextOrder(),
        onActivated = function()
            local payload = { creatureIdA = self._selected[1], creatureIdB = self._selected[2] }
            self._actions:send("StartBreeding", payload, function(result: any)
                if result.ok then
                    self._selected = {}
                    self._hud.toasts:show("gain", "An egg is incubating!")
                end
            end)
        end,
    })
end

function BreedingSection.render(
    self: BreedingSection,
    content: ScrollingFrame,
    snapshot: any,
    nextOrder: () -> number
)
    local profile = snapshot.profile
    self._timers = {}

    local eggCount = 0
    for _ in pairs(profile.eggs) do
        eggCount += 1
    end

    Widgets.label({
        parent = content,
        text = `Eggs {eggCount}/{snapshot.breedingSlots}. Upgrade the den for more slots.`,
        wrap = true,
        autoHeight = true,
        order = nextOrder(),
    })
    self:_renderEggs(content, profile, nextOrder)

    Widgets.label({
        parent = content,
        text = "Choose two parents",
        bold = true,
        color = Theme.TextMuted,
        textSize = 14,
        order = nextOrder(),
    })
    self:_renderParents(content, snapshot, nextOrder)
end

-- Refreshes the "hatches in" text between snapshots.
function BreedingSection.updateTimers(self: BreedingSection)
    local now = self._state:serverNow()
    for _, timer in ipairs(self._timers) do
        if timer.label.Parent ~= nil then
            timer.label.Text = remainingText(timer.hatchesAt, now)
        end
    end
end

return BreedingSection
