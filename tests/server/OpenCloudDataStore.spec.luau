local Expect = require("../support/Expect")
local OpenCloudDataStore = require("../../scripts/lib/OpenCloudDataStore")
local ProfileKeys = require("../../src/shared/Profiles/ProfileKeys")

local function run()
    local request = OpenCloudDataStore.entryRequest(
        "DELETE",
        "123456",
        ProfileKeys.DATASTORE_NAME,
        ProfileKeys.keyFor(42),
        "secret"
    )
    Expect.equal(request.method, "DELETE", "method")
    Expect.equal(
        request.url,
        "https://apis.roblox.com/datastores/v1/universes/123456/standard-datastores/datastore/entries/entry?datastoreName=PlayerProfiles_v1&entryKey=player_42",
        "entry url"
    )
    Expect.equal(request.headers["x-api-key"], "secret", "api key header")

    local encoded = OpenCloudDataStore.entryRequest("GET", "1", "Store Name", "a&b=c", "k")
    Expect.truthy(
        string.find(encoded.url, "datastoreName=Store%20Name&entryKey=a%26b%3Dc", 1, true) ~= nil,
        "query values are percent-encoded"
    )

    Expect.truthy(OpenCloudDataStore.isNumericId("42"), "numeric id")
    Expect.falsy(OpenCloudDataStore.isNumericId("0"), "zero id")
    Expect.falsy(OpenCloudDataStore.isNumericId("4a"), "non-numeric id")
    Expect.falsy(OpenCloudDataStore.isNumericId(nil), "missing id")
    Expect.falsy(
        pcall(OpenCloudDataStore.entryRequest, "GET", "abc", "s", "k", "key"),
        "bad universe"
    )

    Expect.equal(ProfileKeys.keyFor(7), "player_7", "profile key format")
end

return run
