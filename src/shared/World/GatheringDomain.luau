local ResourceNodeDefinitions = require("./ResourceNodeDefinitions")
local CapacityDomain = require("../Economy/CapacityDomain")
local InventoryDomain = require("../Economy/InventoryDomain")

local function ok(value: any)
    return { ok = true, value = value }
end

local function err(code: string, message: string)
    return { ok = false, code = code, message = message }
end

-- Grants the canonical yield of a gathering node, limited by free storage.
-- Range and cooldown checks belong to the server world service.
local function gather(profile: any, nodeDefinitionId: any)
    local definition = if type(nodeDefinitionId) == "string"
        then ResourceNodeDefinitions.ById[nodeDefinitionId]
        else nil
    if definition == nil then
        return err("invalid_request", "resource node is unknown")
    end

    if type(profile) ~= "table" or type(profile.inventory) ~= "table" then
        return err("invalid_request", "profile inventory is invalid")
    end

    local quantity =
        math.min(definition.yield, CapacityDomain.storageSpace(profile, definition.itemId))
    if quantity <= 0 then
        return err("storage_full", "storage is full; build or upgrade a Warehouse")
    end

    local added = InventoryDomain.add(profile, definition.itemId, quantity)
    if added.ok ~= true then
        return added
    end

    return ok({ itemId = definition.itemId, quantity = quantity })
end

return table.freeze({
    gather = gather,
})
