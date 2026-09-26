local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local ActionPipeline = require("../../src/shared/Gameplay/ActionPipeline")
local GameActions = require("../../src/shared/Gameplay/GameActions")
local AnalyticsEvents = require("../../src/shared/Gameplay/AnalyticsEvents")
local ProductionEstimate = require("../../src/shared/Gameplay/ProductionEstimate")
local Snapshot = require("../../src/shared/Gameplay/Snapshot")
local EmpireStats = require("../../src/shared/Progression/EmpireStats")
local CreatureOwnershipDomain = require("../../src/shared/Creatures/CreatureOwnershipDomain")

local function commit(profile: any, mutate: (any) -> any)
    local outcome = ActionPipeline.run(profile, mutate)
    Expect.truthy(outcome.committed, "mutation committed")
    return outcome
end

local function run()
    -- Empire stats.
    local empty = Fixtures.profile()
    local emptyStats = EmpireStats.summarize(empty)
    Expect.equal(emptyStats.empireLevel, 0, "empty empire level")
    Expect.equal(emptyStats.buildings, 0, "empty building count")
    Expect.equal(emptyStats.creatures, 0, "empty creature count")

    local built = Fixtures.profile()
    Fixtures.addCreature(built, "rockhorn_1", "creature_rockhorn")
    Fixtures.addBuilding(built, "mine_1", "building_mine", { level = 3 })
    Fixtures.addBuilding(built, "farm_1", "building_farm", { x = 10, level = 2 })
    local stats = EmpireStats.summarize(built)
    Expect.equal(stats.empireLevel, 5, "empire level sums building levels")
    Expect.equal(stats.buildings, 2, "building count")
    Expect.equal(stats.creatures, 1, "creature count")

    -- Production estimates.
    local mine = { lastClaimedAt = 1000 }
    Expect.equal(ProductionEstimate.pendingCycles(mine, 7.5, 1060, 28800), 7, "one minute")
    Expect.equal(ProductionEstimate.pendingCycles(mine, 7.5, 900, 28800), 0, "future claim time")
    Expect.equal(ProductionEstimate.pendingCycles(mine, 0, 5000, 28800), 0, "idle building")
    Expect.equal(
        ProductionEstimate.pendingCycles(mine, 6, 1000 + 12 * 3600, 28800),
        2880,
        "estimate respects offline cap"
    )

    local staffed = Fixtures.profile()
    Fixtures.addCreature(staffed, "rockhorn_1", "creature_rockhorn")
    Fixtures.addStaffedBuilding(staffed, "mine_1", "building_mine", { "rockhorn_1" })
    Fixtures.addBuilding(staffed, "mine_2", "building_mine", { x = 10 })
    local snapshot = Snapshot.build(staffed, 1000)
    local cycles, ready = ProductionEstimate.summarize(snapshot, 1120)
    Expect.equal(cycles, 15, "total pending cycles")
    Expect.equal(ready, 1, "only staffed buildings are ready")

    -- Analytics: first join logs funnel step 1.
    local fresh = Fixtures.profile()
    local joined = commit(fresh, function(draft)
        return CreatureOwnershipDomain.grantStarter(draft, Expect.idSequence("c"))
    end)
    local joinEvents = AnalyticsEvents.fromCommit(fresh, joined.profile, joined.completedObjectives)
    Expect.equal(#joinEvents, 1, "one join event")
    Expect.equal(joinEvents[1].kind, "funnel", "join is a funnel event")
    Expect.equal(joinEvents[1].step, 1, "join is step 1")

    -- Objective completion logs its funnel step and an onboarding coin source.
    local gatherer = joined.profile
    local gathered = commit(gatherer, function(draft)
        draft.inventory.item_wood = 20
        return { ok = true, value = nil }
    end)
    local objectiveEvents =
        AnalyticsEvents.fromCommit(gatherer, gathered.profile, gathered.completedObjectives)
    Expect.equal(#objectiveEvents, 2, "funnel and reward events")
    Expect.equal(objectiveEvents[1].step, 2, "first objective is step 2")
    Expect.equal(objectiveEvents[2].kind, "economy", "reward is an economy event")
    Expect.equal(objectiveEvents[2].flow, "Source", "reward is a source")
    Expect.equal(objectiveEvents[2].transactionType, "Onboarding", "reward is onboarding")
    Expect.equal(objectiveEvents[2].amount, 10, "reward amount")
    Expect.equal(objectiveEvents[2].endingBalance, 10, "reward ending balance")

    -- Selling is a gameplay source tagged with the item sold.
    local seller = gathered.profile
    local sold = commit(seller, function(draft)
        return GameActions.handlers.SellResource(
            draft,
            { itemId = "item_wood", quantity = 5 },
            { now = 1000, generateId = Expect.idSequence("x") }
        )
    end)
    local sellEvents = AnalyticsEvents.fromCommit(seller, sold.profile, sold.completedObjectives)
    Expect.equal(#sellEvents, 1, "one sell event")
    Expect.equal(sellEvents[1].flow, "Source", "sale is a source")
    Expect.equal(sellEvents[1].transactionType, "Gameplay", "sale is gameplay")
    Expect.equal(sellEvents[1].amount, 5, "sale amount")
    Expect.equal(sellEvents[1].endingBalance, 15, "sale ending balance")
    Expect.equal(sellEvents[1].itemSku, "item_wood", "sale sku")

    -- Upgrading is a gameplay sink tagged with the building, not the items spent.
    local upgrader = Fixtures.profile()
    upgrader.unlocks.objective_gather_wood = true
    upgrader.inventory.item_wood = 100
    upgrader.inventory.item_stone = 100
    upgrader.currencies.coins = 100
    Fixtures.addBuilding(upgrader, "mine_1", "building_mine")
    Fixtures.addBuilding(upgrader, "bench_1", "building_workbench", { x = 10 })
    for _, objectiveId in ipairs({
        "objective_gather_stone",
        "objective_build_mine",
    }) do
        upgrader.unlocks[objectiveId] = true
    end
    local upgraded = commit(upgrader, function(draft)
        return GameActions.handlers.UpgradeBuilding(
            draft,
            { buildingId = "mine_1" },
            { now = 1000, generateId = Expect.idSequence("x") }
        )
    end)
    local upgradeEvents =
        AnalyticsEvents.fromCommit(upgrader, upgraded.profile, upgraded.completedObjectives)
    Expect.equal(upgradeEvents[1].flow, "Sink", "upgrade is a sink")
    Expect.equal(upgradeEvents[1].amount, 40, "upgrade coin cost")
    Expect.equal(upgradeEvents[1].itemSku, "building_mine", "upgrade sku is the building")

    -- Mutations without coin or progression changes log nothing.
    local quiet = commit(upgraded.profile, function(draft)
        draft.inventory.item_food = 1
        return { ok = true, value = nil }
    end)
    Expect.equal(
        #AnalyticsEvents.fromCommit(upgraded.profile, quiet.profile, quiet.completedObjectives),
        0,
        "no events for unrelated changes"
    )
end

return run
