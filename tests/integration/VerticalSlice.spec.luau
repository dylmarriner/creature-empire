-- End-to-end server flows over the pure domain, pipeline and persistence layers:
-- 1. the Phase 4 Rockhorn -> Mine -> Copper Ore -> Furnace -> Copper Bar chain with a
--    deterministic clock, save and reload;
-- 2. a scripted new player completing every objective without developer intervention.
local Expect = require("../support/Expect")
local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local ProfileStore = require("../../src/server/Persistence/ProfileStore")
local MemoryStore = require("../../src/server/Persistence/MemoryStore")
local ActionPipeline = require("../../src/shared/Gameplay/ActionPipeline")
local GameActions = require("../../src/shared/Gameplay/GameActions")
local CreatureOwnershipDomain = require("../../src/shared/Creatures/CreatureOwnershipDomain")
local CreatureDefinitions = require("../../src/shared/Creatures/CreatureDefinitions")
local GatheringDomain = require("../../src/shared/World/GatheringDomain")
local PlacementDomain = require("../../src/shared/Buildings/PlacementDomain")
local UpgradeDomain = require("../../src/shared/Buildings/UpgradeDomain")
local BuildingDefinitions = require("../../src/shared/Buildings/BuildingDefinitions")
local ObjectiveDomain = require("../../src/shared/Progression/ObjectiveDomain")
local ObjectiveDefinitions = require("../../src/shared/Progression/ObjectiveDefinitions")
local GameConfig = require("../../src/shared/Config/GameConfig")

local function newSession(store: any, clock: { now: number }, jobId: string)
    local profileStore = ProfileStore.new({
        store = store,
        schema = ProfileSchema,
        jobId = jobId,
        clock = function()
            return clock.now
        end,
        wait = function(seconds: number)
            clock.now += seconds
        end,
    })

    local session = { profile = nil :: any, store = profileStore, clock = clock }
    local generateId = Expect.idSequence(`{jobId}_id`)

    function session.load()
        local status, profile = profileStore:load("player_1", 1)
        Expect.truthy(status == "loaded" or status == "created", `load status {status}`)
        session.profile = profile
        -- Server join flow: grant the starter creature exactly once.
        if profile.unlocks[CreatureOwnershipDomain.STARTER_UNLOCK_ID] ~= true then
            session.mutate(function(draft)
                return CreatureOwnershipDomain.grantStarter(draft, generateId)
            end)
        end
    end

    function session.mutate(fn: (any) -> any)
        local outcome = ActionPipeline.run(session.profile, fn)
        if outcome.committed then
            session.profile = outcome.profile
        end
        return outcome.result
    end

    function session.act(actionName: string, payload: any)
        local handler = GameActions.handlers[actionName]
        return session.mutate(function(draft)
            return handler(draft, payload, { now = clock.now, generateId = generateId })
        end)
    end

    function session.gather(nodeId: string)
        clock.now += 3
        return session.mutate(function(draft)
            return GatheringDomain.gather(draft, nodeId)
        end)
    end

    function session.capture(speciesId: string)
        return session.mutate(function(draft)
            return CreatureOwnershipDomain.capture(draft, speciesId, true, generateId)
        end)
    end

    function session.save(release: boolean)
        local status = profileStore:save("player_1", 1, session.profile, release)
        Expect.equal(status, "saved", "save status")
    end

    return session
end

local function findBuilding(profile: any, definitionId: string): any
    for _, building in pairs(profile.buildings) do
        if building.definitionId == definitionId then
            return building
        end
    end
    return nil
end

local function phaseFourChain()
    local clock = { now = 10000 }
    local store = MemoryStore.new()
    local session = newSession(store, clock, "job_a")
    session.load()

    local starterId, starter = next(session.profile.creatures)
    Expect.equal(starter.speciesId, "creature_rockhorn", "starter Rockhorn granted")

    for _ = 1, 7 do
        Expect.ok(session.gather("node_tree"), "chop")
    end
    for _ = 1, 10 do
        Expect.ok(session.gather("node_rock"), "break rock")
    end

    local mine = Expect.ok(
        session.act(
            "PlaceBuilding",
            { definitionId = "building_mine", cellX = 0, cellZ = 0, rotation = 0 }
        ),
        "place Mine"
    )
    Expect.ok(
        session.act("AssignCreature", { creatureId = starterId, buildingId = mine.id }),
        "assign Rockhorn"
    )

    local assignedAt = clock.now
    clock.now += 600
    Expect.ok(session.act("ClaimProduction", { buildingId = mine.id }), "claim Mine")
    -- 7.5 cycles/min for 10 minutes.
    Expect.equal(session.profile.inventory.item_copper_ore, 75, "ore after ten minutes")
    Expect.equal(
        session.profile.buildings[mine.id].lastClaimedAt,
        assignedAt + 600,
        "claim clock advanced"
    )

    local embercub = Expect.ok(session.capture("creature_embercub"), "capture Embercub")
    for _ = 1, 10 do
        Expect.ok(session.gather("node_rock"), "stone for furnace")
    end
    local furnace = Expect.ok(
        session.act(
            "PlaceBuilding",
            { definitionId = "building_furnace", cellX = 4, cellZ = 0, rotation = 90 }
        ),
        "place Furnace"
    )
    Expect.ok(
        session.act("AssignCreature", { creatureId = embercub.id, buildingId = furnace.id }),
        "assign Embercub"
    )

    clock.now += 120
    local summary = Expect.ok(session.act("ClaimProduction", {}), "claim all")
    Expect.equal(summary.produced.item_copper_bar, 10, "furnace smelted two minutes of bars")
    Expect.truthy(session.profile.inventory.item_copper_bar == 10, "copper bars owned")

    -- Offline progression is capped and survives a save/reload across servers.
    session.save(true)
    local expected = session.profile
    clock.now += 12 * 3600
    local reloaded = newSession(store, clock, "job_b")
    reloaded.load()
    Expect.equal(
        reloaded.profile.inventory.item_copper_bar,
        expected.inventory.item_copper_bar,
        "inventory survives reload"
    )
    Expect.equal(
        reloaded.profile.buildings[mine.id].lastClaimedAt,
        expected.buildings[mine.id].lastClaimedAt,
        "timestamps survive reload"
    )
    Expect.equal(
        reloaded.profile.creatures[starterId].assignedBuildingId,
        mine.id,
        "assignments survive reload"
    )
    Expect.equal(
        reloaded.profile.unlocks[CreatureOwnershipDomain.STARTER_UNLOCK_ID],
        true,
        "starter not granted twice"
    )

    Expect.ok(reloaded.act("ClaimProduction", {}), "claim offline production")
    Expect.equal(
        reloaded.profile.inventory.item_copper_bar,
        GameConfig.BASE_STORAGE_CAPACITY,
        "offline production bounded by storage"
    )
end

-- A deterministic player that pursues the current objective using only game actions.
local function fullProgression()
    local clock = { now = 50000 }
    local store = MemoryStore.new()
    local session = newSession(store, clock, "job_bot")
    session.load()

    local producers = {}
    for _, definitionId in ipairs(BuildingDefinitions.Ids) do
        local definition = BuildingDefinitions.ById[definitionId]
        if definition.outputs ~= nil then
            for itemId in pairs(definition.outputs) do
                producers[itemId] = producers[itemId] or definitionId
            end
        end
    end

    local function held(itemId: string): number
        return session.profile.inventory[itemId] or 0
    end

    local function staffedProducer(itemId: string): boolean
        for _, building in pairs(session.profile.buildings) do
            local definition = BuildingDefinitions.ById[building.definitionId]
            if
                definition.outputs ~= nil
                and definition.outputs[itemId] ~= nil
                and #building.assignedCreatureIds > 0
            then
                return true
            end
        end
        return false
    end

    local function ensureItem(itemId: string, quantity: number)
        local guard = 0
        while held(itemId) < quantity do
            guard += 1
            assert(guard < 500, `could not obtain {quantity} {itemId}`)
            if itemId == "item_wood" and not staffedProducer(itemId) then
                session.gather("node_tree")
            elseif itemId == "item_stone" and not staffedProducer(itemId) then
                session.gather("node_rock")
            else
                assert(staffedProducer(itemId), `no staffed producer for {itemId}`)
                clock.now += 60
                session.act("ClaimProduction", {})
            end
        end
    end

    local function ensureCost(cost: { [string]: number })
        for itemId, quantity in pairs(cost) do
            ensureItem(itemId, quantity)
        end
        -- Earlier items may have been consumed by processors while waiting; re-check.
        for itemId, quantity in pairs(cost) do
            ensureItem(itemId, quantity)
        end
    end

    local function placeAnywhere(definitionId: string)
        ensureCost(BuildingDefinitions.ById[definitionId].cost)
        for cellZ = 0, GameConfig.PLOT_SIZE_CELLS - 1 do
            for cellX = 0, GameConfig.PLOT_SIZE_CELLS - 1 do
                local check =
                    PlacementDomain.checkPlacement(session.profile, definitionId, cellX, cellZ, 0)
                if check.ok then
                    return Expect.ok(
                        session.act("PlaceBuilding", {
                            definitionId = definitionId,
                            cellX = cellX,
                            cellZ = cellZ,
                            rotation = 0,
                        }),
                        `place {definitionId}`
                    )
                end
            end
        end
        error(`no room for {definitionId}`)
    end

    local function speciesFor(workType: string): string
        for _, speciesId in ipairs(CreatureDefinitions.Ids) do
            if CreatureDefinitions.ById[speciesId].primaryWork == workType then
                return speciesId
            end
        end
        for _, speciesId in ipairs(CreatureDefinitions.Ids) do
            if CreatureDefinitions.ById[speciesId].workAffinity[workType] ~= nil then
                return speciesId
            end
        end
        error(`no species for {workType}`)
    end

    local function staff(definitionId: string)
        local building = findBuilding(session.profile, definitionId) or placeAnywhere(definitionId)
        local workType = BuildingDefinitions.ById[definitionId].workType
        for creatureId, creature in pairs(session.profile.creatures) do
            local affinity = CreatureDefinitions.ById[creature.speciesId].workAffinity[workType]
            if creature.assignedBuildingId == nil and affinity ~= nil then
                return Expect.ok(
                    session.act(
                        "AssignCreature",
                        { creatureId = creatureId, buildingId = building.id }
                    ),
                    `staff {definitionId}`
                )
            end
        end
        local captured =
            Expect.ok(session.capture(speciesFor(workType)), `capture for {definitionId}`)
        return Expect.ok(
            session.act("AssignCreature", { creatureId = captured.id, buildingId = building.id }),
            `staff {definitionId}`
        )
    end

    local function upgradeTo(level: number)
        local mine = assert(findBuilding(session.profile, "building_mine"), "mine exists")
        while mine.level < level do
            local cost = assert(UpgradeDomain.costFor("building_mine", mine.level + 1))
            ensureCost(cost.items)
            Expect.truthy(session.profile.currencies.coins >= cost.coins, "coins from objectives")
            Expect.ok(session.act("UpgradeBuilding", { buildingId = mine.id }), "upgrade mine")
            mine = session.profile.buildings[mine.id]
        end
    end

    local handlers = {
        inventory = function(condition)
            ensureItem(condition.itemId, condition.quantity)
        end,
        building = function(condition)
            placeAnywhere(condition.definitionId)
        end,
        worker = function(condition)
            staff(condition.definitionId)
        end,
        creatures = function(condition)
            while session.profile and next(session.profile.creatures) ~= nil do
                local count = 0
                for _ in pairs(session.profile.creatures) do
                    count += 1
                end
                if count >= condition.quantity then
                    break
                end
                Expect.ok(session.capture("creature_timberpaw"), "capture creature")
            end
        end,
        buildingLevel = function(condition)
            upgradeTo(condition.level)
        end,
    }

    local steps = 0
    while true do
        local objective = ObjectiveDomain.currentObjective(session.profile)
        if objective == nil then
            break
        end
        steps += 1
        assert(steps <= #ObjectiveDefinitions.Ordered, `stuck on {objective.id}`)
        handlers[objective.condition.kind](objective.condition)
        Expect.truthy(
            session.profile.unlocks[objective.id] == true,
            `{objective.id} completed by its own action`
        )
    end

    for _, objective in ipairs(ObjectiveDefinitions.Ordered) do
        Expect.equal(session.profile.unlocks[objective.id], true, `{objective.id} complete`)
    end
    Expect.truthy(ProfileSchema.validate(session.profile), "final profile valid")

    session.save(true)
    local reloaded = newSession(store, clock, "job_check")
    reloaded.load()
    Expect.equal(
        reloaded.profile.currencies.coins,
        session.profile.currencies.coins,
        "progression persisted"
    )
end

local function run()
    phaseFourChain()
    fullProgression()
end

return run
