local Expect = require("../support/Expect")
local GameConfig = require("../../src/shared/Config/GameConfig")
local ItemDefinitions = require("../../src/shared/Items/ItemDefinitions")
local CreatureDefinitions = require("../../src/shared/Creatures/CreatureDefinitions")
local BuildingDefinitions = require("../../src/shared/Buildings/BuildingDefinitions")
local ResourceNodeDefinitions = require("../../src/shared/World/ResourceNodeDefinitions")
local ObjectiveDefinitions = require("../../src/shared/Progression/ObjectiveDefinitions")
local NumberUtil = require("../../src/shared/Util/NumberUtil")

local function expectKnownItems(map: { [string]: number }, label: string)
    for itemId, quantity in pairs(map) do
        Expect.truthy(ItemDefinitions.ById[itemId] ~= nil, `{label} references {itemId}`)
        Expect.truthy(NumberUtil.isPositiveInteger(quantity), `{label} {itemId} quantity`)
    end
end

local function run()
    Expect.equal(#ItemDefinitions.Ids, GameConfig.INITIAL_RESOURCE_COUNT, "resource count")
    Expect.equal(#CreatureDefinitions.WildIds, GameConfig.WILD_SPECIES_COUNT, "wild species count")
    Expect.equal(
        #CreatureDefinitions.Ids,
        GameConfig.WILD_SPECIES_COUNT + GameConfig.HYBRID_SPECIES_COUNT,
        "creature count"
    )
    Expect.equal(#BuildingDefinitions.Ids, GameConfig.INITIAL_BUILDING_COUNT, "building count")

    for id, item in pairs(ItemDefinitions.ById) do
        Expect.equal(item.id, id, "item id matches key")
        Expect.truthy(NumberUtil.isPositiveInteger(item.sellPrice), `{id} sell price`)
    end

    local workTypes = {}
    for id, building in pairs(BuildingDefinitions.ById) do
        Expect.equal(building.id, id, "building id matches key")
        expectKnownItems(building.cost, `{id} cost`)
        Expect.truthy(NumberUtil.isPositiveInteger(building.maxCount), `{id} maxCount`)
        Expect.truthy(
            building.footprint.x >= 1
                and building.footprint.z >= 1
                and building.footprint.x <= GameConfig.PLOT_SIZE_CELLS
                and building.footprint.z <= GameConfig.PLOT_SIZE_CELLS,
            `{id} footprint fits plot`
        )
        -- Every building must be affordable with base storage.
        for itemId, quantity in pairs(building.cost) do
            Expect.truthy(
                quantity <= GameConfig.BASE_STORAGE_CAPACITY,
                `{id} {itemId} cost fits base storage`
            )
        end

        if building.kind == "production" then
            Expect.truthy(type(building.workType) == "string", `{id} work type`)
            Expect.truthy(NumberUtil.isPositiveInteger(building.maxWorkers), `{id} workers`)
            Expect.truthy(building.cyclesPerMinute > 0, `{id} rate`)
            expectKnownItems(building.inputs, `{id} inputs`)
            expectKnownItems(building.outputs, `{id} outputs`)
            Expect.truthy(next(building.outputs) ~= nil, `{id} has outputs`)
            workTypes[building.workType] = true
        else
            Expect.equal(building.kind, "utility", `{id} kind`)
            Expect.equal(building.maxWorkers, 0, `{id} utility has no workers`)
            Expect.truthy(type(building.utility) == "string", `{id} utility role`)
        end
    end

    local staffed = {}
    for id, species in pairs(CreatureDefinitions.ById) do
        Expect.equal(species.id, id, "species id matches key")
        if species.hybridOf == nil then
            Expect.truthy(
                species.captureChance > 0 and species.captureChance <= 1,
                `{id} capture chance`
            )
            Expect.truthy(species.spawnWeight > 0, `{id} spawn weight`)
        else
            Expect.equal(species.captureChance, 0, `{id} hybrids cannot be captured`)
            Expect.equal(species.spawnWeight, 0, `{id} hybrids do not spawn`)
        end
        local useful = false
        for workType, affinity in pairs(species.workAffinity) do
            Expect.truthy(affinity > 0, `{id} {workType} affinity`)
            if workTypes[workType] then
                useful = true
                staffed[workType] = true
            end
        end
        Expect.truthy(useful, `{id} can work at least one building`)
    end

    for workType in pairs(workTypes) do
        Expect.truthy(staffed[workType], `{workType} buildings have a capable species`)
    end

    -- Every pair of different base species has exactly one hybrid, and every hybrid belongs
    -- to exactly one pair.
    local pairCount = 0
    local hybridCount = 0
    for index, firstId in ipairs(CreatureDefinitions.WildIds) do
        for second = index + 1, #CreatureDefinitions.WildIds do
            local secondId = CreatureDefinitions.WildIds[second]
            local hybridId = CreatureDefinitions.hybridFor(firstId, secondId)
            Expect.truthy(hybridId ~= nil, `{firstId} + {secondId} has a hybrid`)
            Expect.equal(
                CreatureDefinitions.hybridFor(secondId, firstId),
                hybridId,
                `{firstId} + {secondId} is order independent`
            )
            local hybrid = CreatureDefinitions.ById[hybridId]
            Expect.equal(hybrid.hybridOf[1], firstId, `{hybridId} first parent`)
            Expect.equal(hybrid.hybridOf[2], secondId, `{hybridId} second parent`)
            -- Generalists: both parents' trades, each below a specialist's own 1.25.
            local first = CreatureDefinitions.ById[firstId]
            local second2 = CreatureDefinitions.ById[secondId]
            Expect.truthy(
                hybrid.workAffinity[first.primaryWork] ~= nil
                    and hybrid.workAffinity[second2.primaryWork] ~= nil,
                `{hybridId} works both parents' trades`
            )
            for workType, affinity in pairs(hybrid.workAffinity) do
                Expect.truthy(affinity < 1.25, `{hybridId} {workType} is below a specialist`)
            end
            pairCount += 1
        end
    end
    for _, id in ipairs(CreatureDefinitions.Ids) do
        if CreatureDefinitions.ById[id].hybridOf ~= nil then
            hybridCount += 1
        end
    end
    Expect.equal(pairCount, 15, "fifteen species pairs")
    Expect.equal(hybridCount, pairCount, "one hybrid per pair")
    Expect.equal(
        CreatureDefinitions.hybridFor("creature_rockhorn", "creature_rockhorn"),
        nil,
        "same species has no hybrid"
    )
    Expect.equal(
        CreatureDefinitions.hybridFor("creature_magmaback", "creature_rockhorn"),
        nil,
        "hybrids do not breed further hybrids"
    )

    for id, node in pairs(ResourceNodeDefinitions.ById) do
        Expect.equal(node.id, id, "node id matches key")
        Expect.truthy(ItemDefinitions.ById[node.itemId] ~= nil, `{id} item`)
        Expect.truthy(NumberUtil.isPositiveInteger(node.yield), `{id} yield`)
        Expect.truthy(node.cooldownSeconds > 0, `{id} cooldown`)
    end

    for index, objective in ipairs(ObjectiveDefinitions.Ordered) do
        Expect.equal(objective.order, index, `{objective.id} order`)
        Expect.truthy(
            NumberUtil.isNonNegativeInteger(objective.rewardCoins),
            `{objective.id} reward`
        )
        local condition = objective.condition
        if condition.kind == "inventory" then
            Expect.truthy(ItemDefinitions.ById[condition.itemId] ~= nil, `{objective.id} item`)
        elseif condition.kind == "building" or condition.kind == "worker" then
            Expect.truthy(
                BuildingDefinitions.ById[condition.definitionId] ~= nil,
                `{objective.id} building`
            )
        elseif condition.kind == "buildingLevel" then
            Expect.truthy(condition.level <= GameConfig.MAX_BUILDING_LEVEL, `{objective.id} level`)
        else
            Expect.equal(condition.kind, "creatures", `{objective.id} condition kind`)
        end
    end

    Expect.truthy(table.isfrozen(BuildingDefinitions.ById.building_mine.cost), "definitions frozen")
end

return run
