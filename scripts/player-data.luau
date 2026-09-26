--[[
    Inspect or delete a player's saved profile through Roblox Open Cloud.

    Usage:
        lune run scripts/player-data get <userId>
        lune run scripts/player-data delete <userId> --confirm

    Environment:
        ROBLOX_API_KEY      Open Cloud API key with DataStore read (get) or delete (delete)
                            permission for the experience
        ROBLOX_UNIVERSE_ID  numeric universe id of the experience

    `delete` fulfils Right to Erasure requests. It permanently removes the player's record
    and requires --confirm.
]]

local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

local OpenCloudDataStore = require("./lib/OpenCloudDataStore")
local ProfileKeys = require("../src/shared/Profiles/ProfileKeys")

local USAGE = [[
Usage:
  lune run scripts/player-data get <userId>
  lune run scripts/player-data delete <userId> --confirm

Requires ROBLOX_API_KEY and ROBLOX_UNIVERSE_ID in the environment.]]

local function fail(message: string): never
    stdio.ewrite(`{message}\n`)
    process.exit(1)
    error(message)
end

local command = process.args[1]
local userId = process.args[2]
if (command ~= "get" and command ~= "delete") or not OpenCloudDataStore.isNumericId(userId) then
    fail(USAGE)
end
if command == "delete" and process.args[3] ~= "--confirm" then
    fail("delete permanently removes the player's data; re-run with --confirm")
end

local apiKey = process.env.ROBLOX_API_KEY
local universeId = process.env.ROBLOX_UNIVERSE_ID
if apiKey == nil or apiKey == "" then
    fail("ROBLOX_API_KEY is not set")
end
if not OpenCloudDataStore.isNumericId(universeId) then
    fail("ROBLOX_UNIVERSE_ID must be set to the numeric universe id")
end

local key = ProfileKeys.keyFor(tonumber(userId) :: number)
local request = OpenCloudDataStore.entryRequest(
    if command == "get" then "GET" else "DELETE",
    universeId,
    ProfileKeys.DATASTORE_NAME,
    key,
    apiKey
)

local sent, response = pcall(net.request, {
    url = request.url,
    method = request.method,
    headers = request.headers,
})
if not sent then
    fail(`Could not reach Open Cloud: {string.match(tostring(response), "^[^\n]*")}`)
end

if response.statusCode == 404 then
    print(`No saved profile for user {userId} ({key}).`)
    process.exit(if command == "delete" then 0 else 2)
end

if not response.ok then
    fail(
        `Open Cloud request failed: {response.statusCode} {response.statusMessage}\n{response.body}`
    )
end

if command == "get" then
    local decoded = serde.decode("json", response.body)
    print(serde.encode("json", decoded, true))
else
    print(`Deleted saved profile for user {userId} ({key}).`)
end
