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

    -- Objective rewards and validation run inside the same error boundary as the mutation.
    local evaluated, completedOrError = pcall(ObjectiveDomain.evaluate, draft)
    if not evaluated then
        return {
            profile = profile,
            result = err("internal_error", "something went wrong; please try again"),
            committed = false,
            completedObjectives = {},
            failure = `objective evaluation failed: {tostring(completedOrError)}`,
        }
    end
    local completed = completedOrError

    local validated, valid, reason = pcall(ProfileSchema.validate, draft)
    if not validated or not valid then
        local detail = if validated
            then `mutation produced an invalid profile: {reason}`
            else `profile validation failed: {tostring(valid)}`
        return {
            profile = profile,
            result = err("internal_error", "something went wrong; please try again"),
            committed = false,
            completedObjectives = {},
            failure = detail,
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
