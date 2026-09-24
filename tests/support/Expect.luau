-- Minimal assertion helpers for the Lune pure-domain test runner.
local Expect = {}

local function describe(value: any): string
    if type(value) == "string" then
        return `"{value}"`
    end
    return tostring(value)
end

function Expect.equal(actual: any, expected: any, label: string)
    if actual ~= expected then
        error(`{label}: expected {describe(expected)}, got {describe(actual)}`, 2)
    end
end

function Expect.truthy(value: any, label: string)
    if not value then
        error(`{label}: expected truthy value, got {describe(value)}`, 2)
    end
end

function Expect.falsy(value: any, label: string)
    if value then
        error(`{label}: expected falsy value, got {describe(value)}`, 2)
    end
end

function Expect.ok(result: any, label: string): any
    if type(result) ~= "table" or result.ok ~= true then
        local code = if type(result) == "table" then result.code else nil
        local message = if type(result) == "table" then result.message else nil
        error(`{label}: expected ok result, got {describe(code)} ({describe(message)})`, 2)
    end
    return result.value
end

function Expect.errorCode(result: any, expectedCode: string, label: string)
    if type(result) ~= "table" or result.ok ~= false then
        error(`{label}: expected error {expectedCode}, got ok result`, 2)
    end
    if result.code ~= expectedCode then
        error(`{label}: expected error {expectedCode}, got {describe(result.code)}`, 2)
    end
end

function Expect.near(actual: number, expected: number, tolerance: number, label: string)
    if math.abs(actual - expected) > tolerance then
        error(`{label}: expected {expected} +/- {tolerance}, got {actual}`, 2)
    end
end

-- Returns a generator producing "<prefix>_1", "<prefix>_2", ...
function Expect.idSequence(prefix: string): () -> string
    local index = 0
    return function()
        index += 1
        return `{prefix}_{index}`
    end
end

return Expect
