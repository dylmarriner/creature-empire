local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local ActionPipeline = require("../../src/shared/Gameplay/ActionPipeline")
local GameActions = require("../../src/shared/Gameplay/GameActions")
local Snapshot = require("../../src/shared/Gameplay/Snapshot")

local function run()
    local profile = Fixtures.profile()
    profile.inventory.item_wood = 20

    local failed = ActionPipeline.run(profile, function(draft)
        draft.inventory.item_wood = 0
        return { ok = false, code = "insufficient_resources", message = "no" }
    end)
    Expect.falsy(failed.committed, "failed result not committed")
    Expect.equal(failed.profile, profile, "original profile returned")
    Expect.equal(profile.inventory.item_wood, 20, "failed mutation discarded")
    Expect.equal(failed.result.code, "insufficient_resources", "domain error surfaced")

    local thrown = ActionPipeline.run(profile, function(draft)
        draft.inventory.item_wood = 1
        error("boom")
    end)
    Expect.falsy(thrown.committed, "thrown mutation not committed")
    Expect.equal(thrown.result.code, "internal_error", "thrown mutation is internal error")
    Expect.truthy(string.find(thrown.failure, "boom") ~= nil, "failure detail kept for logs")
    Expect.equal(profile.inventory.item_wood, 20, "thrown mutation discarded")

    local corrupt = ActionPipeline.run(profile, function(draft)
        draft.currencies.coins = -100
        return { ok = true, value = nil }
    end)
    Expect.falsy(corrupt.committed, "invariant violation not committed")
    Expect.equal(corrupt.result.code, "internal_error", "invariant violation is internal error")
    Expect.equal(profile.currencies.coins, 0, "invariant violation discarded")

    local committed = ActionPipeline.run(profile, function(draft)
        draft.inventory.item_wood += 5
        return { ok = true, value = true }
    end)
    Expect.truthy(committed.committed, "successful mutation committed")
    Expect.truthy(committed.profile ~= profile, "commit returns the draft")
    Expect.equal(committed.profile.inventory.item_wood, 25, "draft carries mutation")
    Expect.equal(profile.inventory.item_wood, 20, "original untouched until caller swaps")
    Expect.equal(committed.completedObjectives[1], "objective_gather_wood", "objectives evaluated")
    Expect.equal(committed.profile.currencies.coins, 10, "objective reward in commit")

    -- Game action handlers.
    local context = { now = 1000, generateId = Expect.idSequence("id") }
    local claimNothing = ActionPipeline.run(committed.profile, function(draft)
        return GameActions.handlers.ClaimProduction(draft, {}, context)
    end)
    Expect.equal(claimNothing.result.code, "nothing_to_claim", "claim with no buildings")

    local game = Fixtures.profile()
    game.inventory.item_wood = 20
    game.inventory.item_stone = 30
    Fixtures.addCreature(game, "rockhorn_1", "creature_rockhorn")
    local placed = ActionPipeline.run(game, function(draft)
        return GameActions.handlers.PlaceBuilding(
            draft,
            { definitionId = "building_mine", cellX = 0, cellZ = 0, rotation = 0 },
            context
        )
    end)
    Expect.truthy(placed.committed, "placement committed")
    local mineId = placed.result.value.id
    game = placed.profile

    local assigned = ActionPipeline.run(game, function(draft)
        return GameActions.handlers.AssignCreature(
            draft,
            { creatureId = "rockhorn_1", buildingId = mineId },
            context
        )
    end)
    Expect.truthy(assigned.committed, "assignment committed")
    game = assigned.profile

    local tooSoon = ActionPipeline.run(game, function(draft)
        return GameActions.handlers.ClaimProduction(draft, { buildingId = mineId }, context)
    end)
    Expect.equal(tooSoon.result.code, "nothing_to_claim", "claim before any cycle")

    local later = { now = 1120, generateId = context.generateId }
    local claimed = ActionPipeline.run(game, function(draft)
        return GameActions.handlers.ClaimProduction(draft, {}, later)
    end)
    Expect.truthy(claimed.committed, "claim all committed")
    Expect.equal(claimed.profile.inventory.item_copper_ore, 15, "two minutes of ore")

    local snapshot = Snapshot.build(claimed.profile, 1120)
    Expect.equal(snapshot.serverTime, 1120, "snapshot time")
    Expect.near(snapshot.rates[mineId], 7.5, 1e-9, "snapshot rate")
    Expect.equal(snapshot.storageCapacity, 200, "snapshot storage")
    Expect.equal(snapshot.creatureCount, 1, "snapshot creature count")
    Expect.truthy(snapshot.objective ~= nil, "snapshot objective")
    Expect.truthy(snapshot.profile ~= claimed.profile, "snapshot copies the profile")
end

return run
