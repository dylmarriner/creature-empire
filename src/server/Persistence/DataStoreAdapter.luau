-- Store adapter backed by a Roblox GlobalDataStore. All yielding and error handling for
-- DataStore calls lives here; ProfileStore only sees success/failure.
local DataStoreService = game:GetService("DataStoreService")

local BUDGET_WAIT_LIMIT_SECONDS = 10

local DataStoreAdapter = {}

local function waitForBudget()
    local waited = 0
    while
        DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
            < 1
        and waited < BUDGET_WAIT_LIMIT_SECONDS
    do
        waited += task.wait(0.5)
    end
end

function DataStoreAdapter.new(dataStore: DataStore)
    local adapter = {}

    function adapter.update(
        key: string,
        transform: (old: any) -> any,
        userIds: { number }?
    ): (boolean, string?)
        waitForBudget()
        local success, result = pcall(function()
            return dataStore:UpdateAsync(key, function(old: any, _keyInfo: DataStoreKeyInfo?)
                local nextValue = transform(old)
                if nextValue == nil then
                    return nil
                end
                return nextValue, userIds
            end)
        end)

        if not success then
            return false, tostring(result)
        end
        return true, nil
    end

    return adapter
end

return DataStoreAdapter
