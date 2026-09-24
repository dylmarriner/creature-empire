local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")

local Fixtures = {}

function Fixtures.profile(now: number?): any
    return ProfileSchema.createDefault(now or 1000)
end

function Fixtures.addCreature(
    profile: any,
    id: string,
    speciesId: string,
    assignedBuildingId: string?,
    level: number?
)
    profile.creatures[id] = {
        id = id,
        speciesId = speciesId,
        level = level or 1,
        experience = 0,
        traits = {},
        mutationId = nil,
        assignedBuildingId = assignedBuildingId,
    }
    return profile.creatures[id]
end

function Fixtures.addBuilding(
    profile: any,
    id: string,
    definitionId: string,
    options: {
        x: number?,
        z: number?,
        rotation: number?,
        level: number?,
        lastClaimedAt: number?,
        workers: { string }?,
    }?
)
    local resolved = options or {}
    profile.buildings[id] = {
        id = id,
        definitionId = definitionId,
        level = resolved.level or 1,
        position = { x = resolved.x or 0, y = 0, z = resolved.z or 0 },
        rotation = resolved.rotation or 0,
        assignedCreatureIds = resolved.workers or {},
        lastClaimedAt = resolved.lastClaimedAt or 1000,
    }
    return profile.buildings[id]
end

-- Adds a building and assigns the given creature ids to it (two-sided).
function Fixtures.addStaffedBuilding(
    profile: any,
    id: string,
    definitionId: string,
    workers: { string },
    options: any?
)
    local resolved = options or {}
    resolved.workers = table.clone(workers)
    local building = Fixtures.addBuilding(profile, id, definitionId, resolved)
    for _, creatureId in ipairs(workers) do
        profile.creatures[creatureId].assignedBuildingId = id
    end
    return building
end

return Fixtures
