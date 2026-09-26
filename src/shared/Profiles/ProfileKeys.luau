-- Where player profiles are stored. Shared by the server and the operations tooling so the
-- key format has a single definition.
local ProfileKeys = {
    DATASTORE_NAME = "PlayerProfiles_v1",
}

function ProfileKeys.keyFor(userId: number): string
    return `player_{userId}`
end

return table.freeze(ProfileKeys)
