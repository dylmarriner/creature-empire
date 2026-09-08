local CreatureDefinitions = require("./CreatureDefinitions")

local STARTER_SPECIES_ID = "creature_rockhorn"
local STARTER_UNLOCK_ID = "starter_creature_granted"

local function ok(value: any)
    return { ok = true, value = value }
end

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

local function createOwnedInstance(profile: any, speciesId: any, generateId: any)
    if type(profile) ~= "table" or type(profile.creatures) ~= "table" then
        return err("invalid_request", "profile creatures are invalid")
    end

    if type(speciesId) ~= "string" or CreatureDefinitions.ById[speciesId] == nil then
        return err("invalid_request", "unknown creature species")
    end

    if type(generateId) ~= "function" then
        return err("invalid_request", "id generator is required")
    end

    local instanceId = generateId()
    if type(instanceId) ~= "string" or instanceId == "" then
        return err("invalid_generated_id", "generated creature id is invalid")
    end

    if profile.creatures[instanceId] ~= nil then
        return err("duplicate_creature_instance", "generated creature id already exists")
    end

    local creature = {
        id = instanceId,
        speciesId = speciesId,
        level = 1,
        experience = 0,
        traits = {},
        mutationId = nil,
        assignedBuildingId = nil,
    }

    profile.creatures[instanceId] = creature
    return ok(creature)
end

local function grantStarter(profile: any, generateId: any)
    if type(profile) ~= "table" or type(profile.unlocks) ~= "table" then
        return err("invalid_request", "profile unlocks are invalid")
    end

    if profile.unlocks[STARTER_UNLOCK_ID] == true then
        return err("starter_already_granted", "starter creature has already been granted")
    end

    local result = createOwnedInstance(profile, STARTER_SPECIES_ID, generateId)
    if result.ok ~= true then
        return result
    end

    profile.unlocks[STARTER_UNLOCK_ID] = true
    return result
end

local function capture(profile: any, speciesId: any, eligible: any, generateId: any)
    if type(eligible) ~= "boolean" then
        return err("invalid_request", "capture eligibility must be a boolean")
    end

    if eligible ~= true then
        return err("capture_not_eligible", "capture is not currently eligible")
    end

    return createOwnedInstance(profile, speciesId, generateId)
end

return table.freeze({
    STARTER_SPECIES_ID = STARTER_SPECIES_ID,
    STARTER_UNLOCK_ID = STARTER_UNLOCK_ID,
    grantStarter = grantStarter,
    capture = capture,
})
