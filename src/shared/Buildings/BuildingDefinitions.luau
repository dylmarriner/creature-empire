local ids = table.freeze({
    "building_mine",
    "building_lumber_mill",
    "building_farm",
    "building_furnace",
    "building_generator",
    "building_warehouse",
    "building_creature_habitat",
    "building_workbench",
})

local byId = {
    building_mine = {
        id = "building_mine",
        displayName = "Mine",
        kind = "production",
        cost = { item_wood = 20, item_stone = 30 },
        workType = "mining",
        maxWorkers = 2,
        baseRatePerMinute = 6,
        outputItemId = "item_copper_ore",
    },
    building_lumber_mill = {
        id = "building_lumber_mill",
        displayName = "Lumber Mill",
        kind = "production",
        cost = { item_wood = 30, item_stone = 10 },
        workType = "logging",
        maxWorkers = 2,
        baseRatePerMinute = 8,
        outputItemId = "item_wood",
    },
    building_farm = {
        id = "building_farm",
        displayName = "Farm",
        kind = "production",
        cost = { item_wood = 25, item_stone = 5 },
        workType = "farming",
        maxWorkers = 2,
        baseRatePerMinute = 6,
        outputItemId = "item_food",
    },
    building_furnace = {
        id = "building_furnace",
        displayName = "Furnace",
        kind = "production",
        cost = { item_stone = 50, item_copper_ore = 15 },
        workType = "smelting",
        maxWorkers = 1,
        baseRatePerMinute = 4,
        outputItemId = "item_copper_bar",
        inputItemId = "item_copper_ore",
        inputPerOutput = 1,
    },
    building_generator = {
        id = "building_generator",
        displayName = "Generator",
        kind = "production",
        cost = { item_stone = 30, item_copper_bar = 20 },
        workType = "power",
        maxWorkers = 1,
        baseRatePerMinute = 5,
        outputItemId = "item_energy",
    },
    building_warehouse = {
        id = "building_warehouse",
        displayName = "Warehouse",
        kind = "utility",
        cost = { item_wood = 80, item_stone = 40 },
        maxWorkers = 0,
    },
    building_creature_habitat = {
        id = "building_creature_habitat",
        displayName = "Creature Habitat",
        kind = "utility",
        cost = { item_wood = 60, item_stone = 30, item_food = 20 },
        maxWorkers = 0,
    },
    building_workbench = {
        id = "building_workbench",
        displayName = "Workbench",
        kind = "utility",
        cost = { item_wood = 30, item_stone = 20 },
        maxWorkers = 0,
    },
}

for _, id in ipairs(ids) do
    assert(byId[id] ~= nil, `Missing building definition for {id}`)
end

return table.freeze({
    Ids = ids,
    ById = table.freeze(byId),
})
