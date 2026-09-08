local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local CreatureOwnershipDomain = require("../../src/shared/Creatures/CreatureOwnershipDomain")

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

local function sequenceGenerator(values: { any })
    local index = 0
    return function()
        index += 1
        return values[index]
    end
end

local function run()
    local profile = ProfileSchema.createDefault(100)

    local starter = CreatureOwnershipDomain.grantStarter(
        profile,
        sequenceGenerator({ "creature_instance_starter" })
    )
    expectOk(starter, "starter grant")
    expectEqual(starter.value.id, "creature_instance_starter", "starter id")
    expectEqual(starter.value.speciesId, "creature_rockhorn", "starter species")
    expectEqual(starter.value.level, 1, "starter level")
    expectEqual(starter.value.experience, 0, "starter experience")
    expectEqual(#starter.value.traits, 0, "starter traits")
    expectEqual(
        profile.creatures.creature_instance_starter,
        starter.value,
        "starter persisted in profile"
    )
    expectEqual(profile.unlocks.starter_creature_granted, true, "starter marker persisted")

    local duplicateStarter = CreatureOwnershipDomain.grantStarter(
        profile,
        sequenceGenerator({ "unused_starter_id" })
    )
    expectErrorCode(duplicateStarter, "starter_already_granted", "duplicate starter rejected")
    expectEqual(profile.creatures.unused_starter_id, nil, "duplicate starter does not generate ownership")

    local captured = CreatureOwnershipDomain.capture(
        profile,
        "creature_embercub",
        true,
        sequenceGenerator({ "creature_instance_capture" })
    )
    expectOk(captured, "capture Embercub")
    expectEqual(captured.value.id, "creature_instance_capture", "capture id")
    expectEqual(captured.value.speciesId, "creature_embercub", "capture species")

    local sameSpeciesAgain = CreatureOwnershipDomain.capture(
        profile,
        "creature_embercub",
        true,
        sequenceGenerator({ "creature_instance_capture_2" })
    )
    expectOk(sameSpeciesAgain, "capture second Embercub")
    expectEqual(
        sameSpeciesAgain.value.speciesId,
        captured.value.speciesId,
        "same-species ownership allowed"
    )
    expectEqual(
        sameSpeciesAgain.value.id == captured.value.id,
        false,
        "same-species instances have unique ids"
    )

    local ineligible = CreatureOwnershipDomain.capture(
        profile,
        "creature_mossling",
        false,
        sequenceGenerator({ "must_not_be_used" })
    )
    expectErrorCode(ineligible, "capture_not_eligible", "ineligible capture rejected")
    expectEqual(profile.creatures.must_not_be_used, nil, "ineligible capture does not mutate ownership")

    local unknownSpecies = CreatureOwnershipDomain.capture(
        profile,
        "creature_unknown",
        true,
        sequenceGenerator({ "unknown_capture" })
    )
    expectErrorCode(unknownSpecies, "invalid_request", "unknown species rejected")
    expectEqual(profile.creatures.unknown_capture, nil, "unknown species does not mutate ownership")

    local duplicateId = CreatureOwnershipDomain.capture(
        profile,
        "creature_aquafin",
        true,
        sequenceGenerator({ "creature_instance_capture" })
    )
    expectErrorCode(duplicateId, "duplicate_creature_instance", "duplicate instance id rejected")
    expectEqual(
        profile.creatures.creature_instance_capture.speciesId,
        "creature_embercub",
        "duplicate id does not overwrite owned creature"
    )

    local invalidGeneratedId = CreatureOwnershipDomain.capture(
        profile,
        "creature_aquafin",
        true,
        sequenceGenerator({ "" })
    )
    expectErrorCode(invalidGeneratedId, "invalid_generated_id", "empty generated id rejected")

    local nonStringGeneratedId = CreatureOwnershipDomain.capture(
        profile,
        "creature_aquafin",
        true,
        sequenceGenerator({ 42 })
    )
    expectErrorCode(nonStringGeneratedId, "invalid_generated_id", "non-string generated id rejected")

    local invalidGenerator = CreatureOwnershipDomain.capture(profile, "creature_aquafin", true, nil)
    expectErrorCode(invalidGenerator, "invalid_request", "missing id generator rejected")

    local malformedProfile = ProfileSchema.createDefault(100)
    malformedProfile.creatures = nil
    local malformedResult = CreatureOwnershipDomain.capture(
        malformedProfile,
        "creature_aquafin",
        true,
        sequenceGenerator({ "malformed_profile_capture" })
    )
    expectErrorCode(malformedResult, "invalid_request", "malformed creature profile rejected")
end

return run
