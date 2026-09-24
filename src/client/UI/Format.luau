local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemDefinitions = require(Shared.Items.ItemDefinitions)
local TableUtil = require(Shared.Util.TableUtil)

local Format = {}

function Format.itemName(itemId: string): string
    local definition = ItemDefinitions.ById[itemId]
    return if definition ~= nil then definition.displayName else itemId
end

-- "20 Wood, 30 Stone" in canonical item order.
function Format.items(items: { [string]: number }): string
    local parts = {}
    for _, itemId in ipairs(ItemDefinitions.Ids) do
        local quantity = items[itemId]
        if quantity ~= nil and quantity > 0 then
            table.insert(parts, `{quantity} {Format.itemName(itemId)}`)
        end
    end
    for _, itemId in ipairs(TableUtil.sortedKeys(items)) do
        if ItemDefinitions.ById[itemId] == nil then
            table.insert(parts, `{items[itemId]} {itemId}`)
        end
    end
    return if #parts > 0 then table.concat(parts, ", ") else "nothing"
end

function Format.rate(cyclesPerMinute: number): string
    return string.format("%.1f/min", cyclesPerMinute)
end

return table.freeze(Format)
