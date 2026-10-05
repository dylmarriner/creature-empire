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

-- "5m 03s", "1h 02m" or "12s".
function Format.duration(seconds: number): string
    local total = math.max(0, math.floor(seconds))
    local hours = total // 3600
    local minutes = (total % 3600) // 60
    local secs = total % 60
    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm %02ds", minutes, secs)
    end
    return `{secs}s`
end

-- "Vigor 16 / Might 16 / Focus 16"
function Format.genes(genes: { vigor: number, might: number, focus: number }): string
    return `Vigor {genes.vigor} / Might {genes.might} / Focus {genes.focus}`
end

function Format.rate(cyclesPerMinute: number): string
    return string.format("%.1f/min", cyclesPerMinute)
end

return table.freeze(Format)
