local ProfileSchema = require("../Profiles/ProfileSchema")
local ObjectiveDomain = require("../Progression/ObjectiveDomain")
local TableUtil = require("../Util/TableUtil")

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

export type PipelineOutcome = {
    profile: any,
    result: any,
    committed: boolean,
    completedObjectives: { string },
    failure: string?,
}

-- Runs a mutation transactionally against a deep copy of the profile.
--
-- The draft is committed only when the mutation returns an ok result, objective rewards
-- have been applied, and the resulting profile still passes schema validation. A thrown
-- error, a failed result, or an invariant violation leaves the original profile untouched.
local function run(profile: any, mutate: (draft: any) -> any): PipelineOutcome
    local draft = TableUtil.deepCopy(profile)
    local success, result = pcall(mutate, draft)

    if not success then
        return {
            profile = profile,
            result = err("internal_error", "something went wrong; please try again"),
            committed = false,
            completedObjectives = {},
            failure = tostring(result),
        }
    end

    if type(result) ~= "table" or result.ok ~= true then
        local failed = if type(result) == "table"
            then result
            else err("internal_error", "something went wrong; please try again")
        return {
            profile = profile,
            result = failed,
            committed = false,
            completedObjectives = {},
            failure = nil,
        }
    end

    local completed = ObjectiveDomain.evaluate(draft)

    local valid, reason = ProfileSchema.validate(draft)
    if not valid then
        return {
            profile = profile,
            result = err("internal_error", "something went wrong; please try again"),
            committed = false,
            completedObjectives = {},
            failure = `mutation produced an invalid profile: {reason}`,
        }
    end

    return {
        profile = draft,
        result = result,
        committed = true,
        completedObjectives = completed,
        failure = nil,
    }
end

return table.freeze({
    run = run,
})
