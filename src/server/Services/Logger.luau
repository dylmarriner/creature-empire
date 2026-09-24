-- Structured server logging. Log lines carry a scope and key/value context such as a
-- userId; never log profile contents, balances or other player data.
local Logger = {}

export type Context = { [string]: any }

export type Logger = {
    info: (message: string, context: Context?) -> (),
    warn: (message: string, context: Context?) -> (),
    error: (message: string, context: Context?) -> (),
}

local function format(scope: string, message: string, context: Context?): string
    local parts = { `[CreatureEmpire:{scope}] {message}` }
    if context ~= nil then
        local keys = {}
        for key in pairs(context) do
            table.insert(keys, key)
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            table.insert(parts, `{key}={tostring(context[key])}`)
        end
    end
    return table.concat(parts, " ")
end

function Logger.new(scope: string): Logger
    return {
        info = function(message: string, context: Context?)
            print(format(scope, message, context))
        end,
        warn = function(message: string, context: Context?)
            warn(format(scope, message, context))
        end,
        error = function(message: string, context: Context?)
            -- task.spawn so the error is reported with a stack trace without unwinding the caller.
            task.spawn(error, format(scope, message, context), 0)
        end,
    }
end

return Logger
