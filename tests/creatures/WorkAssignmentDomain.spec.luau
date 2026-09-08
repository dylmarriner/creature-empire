local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local WorkAssignmentDomain = require("../../src/shared/Creatures/WorkAssignmentDomain")

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

local function expectErrorCode(result: any, expectedCode: string, label: string)
    if result.ok ~= false then
        error(`{label}: expected error result`)
    end
    expectEqual(result.code, expectedCode, label)
end

local function addCreature(profile: any, id: string, speciesId: string, assignedBuildingId: string?)
    profile.creatures[id] = {
        id = id,
        speciesId = speciesId,
        level = 1,
        experience = 0,
        traits = {},
        mutationId = nil,
        assignedBuildingId = assignedBuildingId,
    }
end

local function addBuilding(
    profile: any,
    id: string,
    definitionId: string,
    assignedCreatureIds: { string }?
)
    profile.buildings[id] = {
        id = id,
        definitionId = definitionId,
        level = 1,
        position = { x = 0, y = 0, z = 0 },
        rotation = 0,
        assignedCreatureIds = assignedCreatureIds or {},
        lastClaimedAt = 100,
    }
end

local function createValidMiningProfile()
    local profile = ProfileSchema.createDefault(100)
    addCreature(profile, "creature_instance_1", "creature_rockhorn", nil)
    addBuilding(profile, "building_instance_1", "building_mine", {})
    return profile
end

local function run()
    local profile = createValidMiningProfile()
    local valid =
        WorkAssignmentDomain.validate(profile, "creature_instance_1", "building_instance_1")
    expectOk(valid, "Rockhorn can work Mine")
    expectEqual(valid.value, true, "valid assignment result")

    local missingCreature =
        WorkAssignmentDomain.validate(profile, "creature_instance_missing", "building_instance_1")
    expectErrorCode(missingCreature, "creature_not_owned", "missing creature rejected")

    local missingBuilding =
        WorkAssignmentDomain.validate(profile, "creature_instance_1", "building_instance_missing")
    expectErrorCode(missingBuilding, "building_not_owned", "missing building rejected")

    local assignedProfile = createValidMiningProfile()
    assignedProfile.creatures.creature_instance_1.assignedBuildingId = "building_elsewhere"
    local alreadyAssigned =
        WorkAssignmentDomain.validate(assignedProfile, "creature_instance_1", "building_instance_1")
    expectErrorCode(alreadyAssigned, "creature_already_assigned", "assigned creature rejected")

    local fullProfile = createValidMiningProfile()
    addCreature(fullProfile, "creature_worker_1", "creature_rockhorn", "building_instance_1")
    addCreature(fullProfile, "creature_worker_2", "creature_rockhorn", "building_instance_1")
    fullProfile.buildings.building_instance_1.assignedCreatureIds = {
        "creature_worker_1",
        "creature_worker_2",
    }
    local fullBuilding =
        WorkAssignmentDomain.validate(fullProfile, "creature_instance_1", "building_instance_1")
    expectErrorCode(fullBuilding, "building_capacity_full", "full building rejected")

    local incompatibleProfile = ProfileSchema.createDefault(100)
    addCreature(incompatibleProfile, "creature_instance_1", "creature_embercub", nil)
    addBuilding(incompatibleProfile, "building_instance_1", "building_mine", {})
    local incompatible = WorkAssignmentDomain.validate(
        incompatibleProfile,
        "creature_instance_1",
        "building_instance_1"
    )
    expectErrorCode(incompatible, "incompatible_work", "wrong work affinity rejected")

    local utilityProfile = createValidMiningProfile()
    utilityProfile.buildings.building_instance_1.definitionId = "building_warehouse"
    local utility =
        WorkAssignmentDomain.validate(utilityProfile, "creature_instance_1", "building_instance_1")
    expectErrorCode(utility, "incompatible_work", "utility building rejected")

    local unknownSpeciesProfile = createValidMiningProfile()
    unknownSpeciesProfile.creatures.creature_instance_1.speciesId = "creature_unknown"
    local unknownSpecies = WorkAssignmentDomain.validate(
        unknownSpeciesProfile,
        "creature_instance_1",
        "building_instance_1"
    )
    expectErrorCode(unknownSpecies, "invalid_request", "unknown owned species rejected")

    local unknownBuildingProfile = createValidMiningProfile()
    unknownBuildingProfile.buildings.building_instance_1.definitionId = "building_unknown"
    local unknownBuilding = WorkAssignmentDomain.validate(
        unknownBuildingProfile,
        "creature_instance_1",
        "building_instance_1"
    )
    expectErrorCode(unknownBuilding, "invalid_request", "unknown owned building rejected")

    local inconsistentProfile = createValidMiningProfile()
    inconsistentProfile.buildings.building_instance_1.assignedCreatureIds =
        { "creature_instance_1" }
    local inconsistent = WorkAssignmentDomain.validate(
        inconsistentProfile,
        "creature_instance_1",
        "building_instance_1"
    )
    expectErrorCode(inconsistent, "invalid_request", "one-sided assignment rejected")

    local staleWorkerProfile = createValidMiningProfile()
    staleWorkerProfile.buildings.building_instance_1.assignedCreatureIds = { "creature_missing" }
    local staleWorker = WorkAssignmentDomain.validate(
        staleWorkerProfile,
        "creature_instance_1",
        "building_instance_1"
    )
    expectErrorCode(staleWorker, "invalid_request", "stale worker reference rejected")

    local mismatchedWorkerProfile = createValidMiningProfile()
    addCreature(mismatchedWorkerProfile, "creature_worker_1", "creature_rockhorn", "building_other")
    mismatchedWorkerProfile.buildings.building_instance_1.assignedCreatureIds =
        { "creature_worker_1" }
    local mismatchedWorker = WorkAssignmentDomain.validate(
        mismatchedWorkerProfile,
        "creature_instance_1",
        "building_instance_1"
    )
    expectErrorCode(mismatchedWorker, "invalid_request", "mismatched worker reference rejected")

    local sparseProfile = createValidMiningProfile()
    sparseProfile.buildings.building_instance_1.assignedCreatureIds = {
        [2] = "creature_worker_1",
    }
    local sparse =
        WorkAssignmentDomain.validate(sparseProfile, "creature_instance_1", "building_instance_1")
    expectErrorCode(sparse, "invalid_request", "sparse worker list rejected")

    local malformedProfile = ProfileSchema.createDefault(100)
    malformedProfile.buildings = nil
    local malformed = WorkAssignmentDomain.validate(
        malformedProfile,
        "creature_instance_1",
        "building_instance_1"
    )
    expectErrorCode(malformed, "invalid_request", "malformed profile rejected")
end

return run
