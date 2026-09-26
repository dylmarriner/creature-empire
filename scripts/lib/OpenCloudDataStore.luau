-- Request construction for the Roblox Open Cloud standard DataStore entry API (v1).
-- Pure so it can be tested without network access.
local OpenCloudDataStore = {}

local BASE_URL = "https://apis.roblox.com/datastores/v1/universes"

export type Request = {
    method: string,
    url: string,
    headers: { [string]: string },
}

local function encode(value: string): string
    return (
        string.gsub(value, "[^%w%-_%.~]", function(character)
            return string.format("%%%02X", string.byte(character))
        end)
    )
end

function OpenCloudDataStore.isNumericId(value: any): boolean
    return type(value) == "string" and string.match(value, "^%d+$") ~= nil and value ~= "0"
end

function OpenCloudDataStore.entryRequest(
    method: "GET" | "DELETE",
    universeId: string,
    datastoreName: string,
    entryKey: string,
    apiKey: string
): Request
    assert(OpenCloudDataStore.isNumericId(universeId), "universe id must be numeric")
    assert(datastoreName ~= "" and entryKey ~= "" and apiKey ~= "", "request fields are required")
    return {
        method = method,
        url = `{BASE_URL}/{universeId}/standard-datastores/datastore/entries/entry?datastoreName={encode(
            datastoreName
        )}&entryKey={encode(entryKey)}`,
        headers = { ["x-api-key"] = apiKey },
    }
end

return OpenCloudDataStore
