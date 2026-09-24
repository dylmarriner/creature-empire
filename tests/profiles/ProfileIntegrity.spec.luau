local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local ProfileIntegrity = require("../../src/shared/Profiles/ProfileIntegrity")

local function run()
    local healthy = Fixtures.profile()
    Fixtures.addCreature(healthy, "rockhorn_1", "creature_rockhorn")
    Fixtures.addStaffedBuilding(healthy, "mine_1", "building_mine", { "rockhorn_1" })
    Expect.equal(ProfileIntegrity.repair(healthy), 0, "healthy profile untouched")
    Expect.equal(healthy.buildings.mine_1.assignedCreatureIds[1], "rockhorn_1", "worker kept")

    local broken = Fixtures.profile()
    Fixtures.addCreature(broken, "rockhorn_1", "creature_rockhorn", "mine_1")
    Fixtures.addCreature(broken, "rockhorn_2", "creature_rockhorn", "mine_1")
    Fixtures.addCreature(broken, "rockhorn_3", "creature_rockhorn", "mine_1")
    Fixtures.addCreature(broken, "embercub_1", "creature_embercub", "mine_1")
    Fixtures.addCreature(broken, "orphan", "creature_mossling", "missing_building")
    Fixtures.addCreature(broken, "one_sided", "creature_rockhorn", "mine_2")
    Fixtures.addBuilding(broken, "mine_1", "building_mine", {
        workers = { "rockhorn_1", "rockhorn_1", "ghost", "embercub_1", "rockhorn_2", "rockhorn_3" },
    })
    Fixtures.addBuilding(broken, "mine_2", "building_mine", { x = 10 })

    local fixes = ProfileIntegrity.repair(broken)
    Expect.truthy(fixes > 0, "repairs reported")
    local workers = broken.buildings.mine_1.assignedCreatureIds
    Expect.equal(#workers, 2, "capacity respected")
    Expect.equal(workers[1], "rockhorn_1", "first valid worker")
    Expect.equal(workers[2], "rockhorn_2", "second valid worker")
    Expect.equal(broken.creatures.rockhorn_3.assignedBuildingId, nil, "overflow worker released")
    Expect.equal(
        broken.creatures.embercub_1.assignedBuildingId,
        nil,
        "incompatible worker released"
    )
    Expect.equal(broken.creatures.orphan.assignedBuildingId, nil, "orphan released")
    Expect.equal(broken.creatures.one_sided.assignedBuildingId, nil, "one-sided released")
    Expect.equal(ProfileIntegrity.repair(broken), 0, "repair is idempotent")
end

return run
