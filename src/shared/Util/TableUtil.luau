local TableUtil = {}

function TableUtil.deepCopy(value: any): any
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[TableUtil.deepCopy(key)] = TableUtil.deepCopy(child)
    end

    return copy
end

function TableUtil.sortedKeys(map: { [any]: any }): { any }
    local keys = {}
    for key in pairs(map) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

function TableUtil.deepFreeze<T>(value: T): T
    if type(value) == "table" and not table.isfrozen(value :: any) then
        for _, child in pairs(value :: any) do
            TableUtil.deepFreeze(child)
        end
        table.freeze(value :: any)
    end
    return value
end

return table.freeze(TableUtil)
