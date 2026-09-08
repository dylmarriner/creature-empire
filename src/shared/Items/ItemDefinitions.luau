local ids = table.freeze({
    "item_wood",
    "item_stone",
    "item_copper_ore",
    "item_copper_bar",
    "item_food",
    "item_energy",
})

local byId = {
    item_wood = { id = "item_wood", displayName = "Wood", category = "resource" },
    item_stone = { id = "item_stone", displayName = "Stone", category = "resource" },
    item_copper_ore = { id = "item_copper_ore", displayName = "Copper Ore", category = "resource" },
    item_copper_bar = { id = "item_copper_bar", displayName = "Copper Bar", category = "resource" },
    item_food = { id = "item_food", displayName = "Food", category = "resource" },
    item_energy = { id = "item_energy", displayName = "Energy", category = "resource" },
}

for _, id in ipairs(ids) do
    assert(byId[id] ~= nil, `Missing item definition for {id}`)
end

return table.freeze({
    Ids = ids,
    ById = table.freeze(byId),
})
