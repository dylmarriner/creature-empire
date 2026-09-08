local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local WorkAssignmentMutationDomain = require("../../src/shared/Creatures/WorkAssignmentMutationDomain")

local function expectEqual(actual: any, expected: any, label: string)
    if actual ~= expected then
        error(`{label}: expected {expected}, got {actual}`)
    end
end

local function expectOk(result: any, label: string)
    if result.ok ~= true then
        error(`{label}: expected ok result, got {result.code}`)
    end
end

local function expectErrorCode(result: any, code: string, label: string)
    if result.ok ~= false then
        error(`{label}: expected error result`)
    end
    expectEqual(result.code, code, label)
end

local function addCreature(profile: any, id: string, speciesId: string, buildingId: string?)
    profile.creatures[id] = {
        id = id,
        speciesId = speciesId,
        level = 1,
        experience = 0,
        traits = {},
        mutationId = nil,
        assignedBuildingId = buildingId,
    }
end

local function addMine(profile: any, workers: { string }?, lastClaimedAt: number?)
    profile.buildings.mine_1 = {
        id = "mine_1",
        definitionId = "building_mine",
        level = 1,
        position = { x = 0, y = 0, z = 0 },
        rotation = 0,
        assignedCreatureIds = workers or {},
        lastClaimedAt = lastClaimedAt or 100,
    }
end

local function run()
    local profile = ProfileSchema.createDefault(100)
    addCreature(profile, "rockhorn_1", "creature_rockhorn", nil)
    addMine(profile, {}, 100)

    local assigned = WorkAssignmentMutationDomain.assign(profile, "rockhorn_1", "mine_1", 160)
    expectOk(assigned, "assign Rockhorn")
    expectEqual(profile.creatures.rockhorn_1.assignedBuildingId, "mine_1", "creature back-reference")
    expectEqual(profile.buildings.mine_1.assignedCreatureIds[1], "rockhorn_1", "building worker reference")
    expectEqual(profile.buildings.mine_1.lastClaimedAt, 160, "assignment settles old baseline")

    local invalidProfile = ProfileSchema.createDefault(100)
    addCreature(invalidProfile, "ember_1", "creature_embercub", nil)
    addMine(invalidProfile, {}, 100)
    local invalid = WorkAssignmentMutationDomain.assign(invalidProfile, "ember_1", "mine_1", 160)
    expectErrorCode(invalid, "incompatible_work", "incompatible assignment rejected")
    expectEqual(invalidProfile.creatures.ember_1.assignedBuildingId, nil, "failed assignment creature unchanged")
    expectEqual(#invalidProfile.buildings.mine_1.assignedCreatureIds, 0, "failed assignment building unchanged")
    expectEqual(invalidProfile.buildings.mine_1.lastClaimedAt, 100, "failed assignment timestamp unchanged")

    local producingProfile = ProfileSchema.createDefault(100)
    addCreature(producingProfile, "rockhorn_1", "creature_rockhorn", nil)
    addMine(producingProfile, {}, 100)
    expectOk(
        WorkAssignmentMutationDomain.assign(producingProfile, "rockhorn_1", "mine_1", 100),
        "assign before unassign"
    )
    local unassigned = WorkAssignmentMutationDomain.unassign(producingProfile, "rockhorn_1", 220)
    expectOk(unassigned, "unassign Rockhorn")
    expectEqual(producingProfile.inventory.item_copper_ore, 15, "unassign settles old worker output")
    expectEqual(producingProfile.creatures.rockhorn_1.assignedBuildingId, nil, "unassign creature cleared")
    expectEqual(#producingProfile.buildings.mine_1.assignedCreatureIds, 0, "unassign building cleared")
    expectEqual(producingProfile.buildings.mine_1.lastClaimedAt, 220, "unassign timestamp advanced")

    local corruptProfile = ProfileSchema.createDefault(100)
    addCreature(corruptProfile, "rockhorn_1", "creature_rockhorn", "mine_1")
    addMine(corruptProfile, {}, 100)
    local corrupt = WorkAssignmentMutationDomain.unassign(corruptProfile, "rockhorn_1", 220)
    expectErrorCode(corrupt, "invalid_request", "one-sided unassign rejected")
    expectEqual(corruptProfile.creatures.rockhorn_1.assignedBuildingId, "mine_1", "corrupt creature unchanged")
    expectEqual(corruptProfile.buildings.mine_1.lastClaimedAt, 100, "corrupt timestamp unchanged")

    local badTimeProfile = ProfileSchema.createDefault(100)
    addCreature(badTimeProfile, "rockhorn_1", "creature_rockhorn", nil)
    addMine(badTimeProfile, {}, 100)
    local badTime = WorkAssignmentMutationDomain.assign(badTimeProfile, "rockhorn_1", "mine_1", -1)
    expectErrorCode(badTime, "invalid_request", "invalid assignment time rejected")
end

return run
