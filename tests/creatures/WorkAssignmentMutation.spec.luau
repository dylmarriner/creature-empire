local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local WorkAssignmentDomain = require("../../src/shared/Creatures/WorkAssignmentDomain")
local CreatureOwnershipDomain = require("../../src/shared/Creatures/CreatureOwnershipDomain")

local function run()
    local profile = Fixtures.profile()
    Fixtures.addCreature(profile, "rockhorn_1", "creature_rockhorn")
    Fixtures.addCreature(profile, "rockhorn_2", "creature_rockhorn")
    Fixtures.addCreature(profile, "rockhorn_3", "creature_rockhorn")
    Fixtures.addBuilding(profile, "mine_1", "building_mine", { lastClaimedAt = 900 })

    Expect.ok(WorkAssignmentDomain.assign(profile, "rockhorn_1", "mine_1", 1000), "assign first")
    Expect.equal(profile.creatures.rockhorn_1.assignedBuildingId, "mine_1", "creature side")
    Expect.equal(profile.buildings.mine_1.assignedCreatureIds[1], "rockhorn_1", "building side")
    Expect.equal(profile.buildings.mine_1.lastClaimedAt, 1000, "idle time not banked")

    Expect.ok(WorkAssignmentDomain.assign(profile, "rockhorn_2", "mine_1", 1060), "assign second")
    Expect.equal(profile.inventory.item_copper_ore, 7, "first worker's output settled")
    Expect.equal(#profile.buildings.mine_1.assignedCreatureIds, 2, "two workers")

    Expect.errorCode(
        WorkAssignmentDomain.assign(profile, "rockhorn_3", "mine_1", 1060),
        "building_capacity_full",
        "capacity enforced"
    )
    Expect.equal(profile.creatures.rockhorn_3.assignedBuildingId, nil, "rejected worker untouched")

    Expect.ok(WorkAssignmentDomain.unassign(profile, "rockhorn_1", 1120), "unassign")
    Expect.equal(profile.creatures.rockhorn_1.assignedBuildingId, nil, "creature released")
    Expect.equal(#profile.buildings.mine_1.assignedCreatureIds, 1, "one worker remains")
    Expect.equal(profile.buildings.mine_1.assignedCreatureIds[1], "rockhorn_2", "remaining worker")
    Expect.equal(profile.inventory.item_copper_ore, 7 + 16, "two-worker output settled")

    Expect.errorCode(
        WorkAssignmentDomain.unassign(profile, "rockhorn_1", 1120),
        "creature_not_assigned",
        "idle creature"
    )
    Expect.errorCode(
        WorkAssignmentDomain.unassign(profile, "missing", 1120),
        "creature_not_owned",
        "missing creature"
    )

    local dangling = Fixtures.profile()
    Fixtures.addCreature(dangling, "rockhorn_1", "creature_rockhorn", "gone")
    Expect.ok(WorkAssignmentDomain.unassign(dangling, "rockhorn_1", 1000), "dangling cleared")
    Expect.equal(
        dangling.creatures.rockhorn_1.assignedBuildingId,
        nil,
        "dangling reference removed"
    )

    -- Release rules.
    Expect.errorCode(
        CreatureOwnershipDomain.release(profile, "rockhorn_2"),
        "creature_already_assigned",
        "assigned creature cannot be released"
    )
    Expect.ok(CreatureOwnershipDomain.release(profile, "rockhorn_3"), "release idle creature")
    Expect.equal(profile.creatures.rockhorn_3, nil, "released creature removed")

    local single = Fixtures.profile()
    Fixtures.addCreature(single, "rockhorn_1", "creature_rockhorn")
    Expect.errorCode(
        CreatureOwnershipDomain.release(single, "rockhorn_1"),
        "invalid_request",
        "last creature kept"
    )

    -- Capture respects habitat capacity.
    local full = Fixtures.profile()
    for index = 1, 4 do
        Fixtures.addCreature(full, `creature_{index}`, "creature_mossling")
    end
    Expect.errorCode(
        CreatureOwnershipDomain.capture(full, "creature_voltfox", true, Expect.idSequence("new")),
        "creature_capacity_full",
        "base capacity is four"
    )
    Fixtures.addBuilding(full, "habitat_1", "building_creature_habitat")
    Expect.ok(
        CreatureOwnershipDomain.capture(full, "creature_voltfox", true, Expect.idSequence("new")),
        "habitat adds capacity"
    )
end

return run
