local TableUtil = require("../Util/TableUtil")

local ids = {
    "item_wood",
    "item_stone",
    "item_copper_ore",
    "item_copper_bar",
    "item_food",
    "item_energy",
}

local byId = {
    item_wood = {
        id = "item_wood",
        displayName = "Wood",
        category = "resource",
        sellPrice = 1,
    },
    item_stone = {
        id = "item_stone",
        displayName = "Stone",
        category = "resource",
        sellPrice = 1,
    },
    item_copper_ore = {
        id = "item_copper_ore",
        displayName = "Copper Ore",
        category = "resource",
        sellPrice = 2,
    },
    item_copper_bar = {
        id = "item_copper_bar",
        displayName = "Copper Bar",
        category = "resource",
        sellPrice = 6,
    },
    item_food = {
        id = "item_food",
        displayName = "Food",
        category = "resource",
        sellPrice = 2,
    },
    item_energy = {
        id = "item_energy",
        displayName = "Energy",
        category = "resource",
        sellPrice = 3,
    },
}

for _, id in ipairs(ids) do
    assert(byId[id] ~= nil, `Missing item definition for {id}`)
end

return TableUtil.deepFreeze({
    Ids = ids,
    ById = byId,
})
