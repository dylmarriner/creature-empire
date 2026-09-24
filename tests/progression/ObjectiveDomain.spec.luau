local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local ObjectiveDomain = require("../../src/shared/Progression/ObjectiveDomain")
local ObjectiveDefinitions = require("../../src/shared/Progression/ObjectiveDefinitions")

local function run()
    local profile = Fixtures.profile()
    Expect.equal(
        ObjectiveDomain.currentObjective(profile).id,
        "objective_gather_wood",
        "first objective"
    )
    Expect.equal(#ObjectiveDomain.evaluate(profile), 0, "nothing completes on a new profile")

    profile.inventory.item_wood = 12
    local current, target =
        ObjectiveDomain.progress(profile, ObjectiveDefinitions.ById.objective_gather_wood.condition)
    Expect.equal(current, 12, "progress current")
    Expect.equal(target, 20, "progress target")

    profile.inventory.item_wood = 20
    local completed = ObjectiveDomain.evaluate(profile)
    Expect.equal(#completed, 1, "one objective completed")
    Expect.equal(completed[1], "objective_gather_wood", "wood objective completed")
    Expect.equal(profile.unlocks.objective_gather_wood, true, "completion persisted")
    Expect.equal(profile.currencies.coins, 10, "reward granted")
    Expect.equal(#ObjectiveDomain.evaluate(profile), 0, "rewards are granted once")
    Expect.equal(profile.currencies.coins, 10, "no double reward")

    -- Later objectives wait for earlier ones, then complete together.
    Fixtures.addBuilding(profile, "mine_1", "building_mine")
    Expect.equal(#ObjectiveDomain.evaluate(profile), 0, "mine waits for stone objective")
    profile.inventory.item_stone = 30
    local chained = ObjectiveDomain.evaluate(profile)
    Expect.equal(#chained, 2, "stone and mine complete together")
    Expect.equal(chained[2], "objective_build_mine", "mine objective second")
    Expect.equal(profile.currencies.coins, 40, "both rewards granted")
    Expect.equal(
        ObjectiveDomain.currentObjective(profile).id,
        "objective_staff_mine",
        "next objective"
    )

    local done = Fixtures.profile()
    for _, objective in ipairs(ObjectiveDefinitions.Ordered) do
        done.unlocks[objective.id] = true
    end
    Expect.equal(ObjectiveDomain.currentObjective(done), nil, "all objectives complete")
end

return run
