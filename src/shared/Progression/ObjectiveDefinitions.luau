local TableUtil = require("../Util/TableUtil")

-- The tutorial and first progression path, completed strictly in order. Conditions are
-- derived from profile state so completion never depends on client-reported events.
--
-- Condition kinds:
--   inventory     { itemId, quantity }        hold at least `quantity` of an item
--   building      { definitionId }            own at least one building of a definition
--   worker        { definitionId }            a building of a definition has a worker
--   creatures     { quantity }                own at least `quantity` creatures
--   buildingLevel { level }                   any building at or above `level`
local objectives = {
    {
        id = "objective_gather_wood",
        title = "Gather Wood",
        description = "Chop trees in the Wilds until you hold 20 Wood.",
        condition = { kind = "inventory", itemId = "item_wood", quantity = 20 },
        rewardCoins = 10,
    },
    {
        id = "objective_gather_stone",
        title = "Gather Stone",
        description = "Break rocks in the Wilds until you hold 30 Stone.",
        condition = { kind = "inventory", itemId = "item_stone", quantity = 30 },
        rewardCoins = 10,
    },
    {
        id = "objective_build_mine",
        title = "Build a Mine",
        description = "Open the Build menu and place a Mine on your plot.",
        condition = { kind = "building", definitionId = "building_mine" },
        rewardCoins = 20,
    },
    {
        id = "objective_staff_mine",
        title = "Put Rockhorn to Work",
        description = "Select your Mine and assign your Rockhorn as a worker.",
        condition = { kind = "worker", definitionId = "building_mine" },
        rewardCoins = 20,
    },
    {
        id = "objective_capture_creature",
        title = "Capture a Creature",
        description = "Find a wild creature in the Wilds and capture it.",
        condition = { kind = "creatures", quantity = 2 },
        rewardCoins = 25,
    },
    {
        id = "objective_build_lumber_mill",
        title = "Build a Lumber Mill",
        description = "Automate wood with a Lumber Mill.",
        condition = { kind = "building", definitionId = "building_lumber_mill" },
        rewardCoins = 25,
    },
    {
        id = "objective_staff_lumber_mill",
        title = "Hire a Logger",
        description = "Assign a Timberpaw to your Lumber Mill.",
        condition = { kind = "worker", definitionId = "building_lumber_mill" },
        rewardCoins = 25,
    },
    {
        id = "objective_build_farm",
        title = "Build a Farm",
        description = "Farms produce Food once a Mossling or Aquafin tends them.",
        condition = { kind = "building", definitionId = "building_farm" },
        rewardCoins = 25,
    },
    {
        id = "objective_staff_farm",
        title = "Plant the Fields",
        description = "Capture a Mossling or Aquafin and assign it to your Farm.",
        condition = { kind = "worker", definitionId = "building_farm" },
        rewardCoins = 25,
    },
    {
        id = "objective_build_furnace",
        title = "Build a Furnace",
        description = "Furnaces smelt Copper Ore into Copper Bars.",
        condition = { kind = "building", definitionId = "building_furnace" },
        rewardCoins = 30,
    },
    {
        id = "objective_staff_furnace",
        title = "Light the Furnace",
        description = "Assign an Embercub to your Furnace.",
        condition = { kind = "worker", definitionId = "building_furnace" },
        rewardCoins = 30,
    },
    {
        id = "objective_smelt_copper",
        title = "Smelt Copper",
        description = "Claim production until you hold 10 Copper Bars.",
        condition = { kind = "inventory", itemId = "item_copper_bar", quantity = 10 },
        rewardCoins = 40,
    },
    {
        id = "objective_build_habitat",
        title = "Build a Creature Habitat",
        description = "Your creatures need room. A Habitat raises your creature limit.",
        condition = { kind = "building", definitionId = "building_creature_habitat" },
        rewardCoins = 60,
    },
    {
        id = "objective_build_workbench",
        title = "Build a Workbench",
        description = "A Workbench unlocks building upgrades.",
        condition = { kind = "building", definitionId = "building_workbench" },
        rewardCoins = 40,
    },
    {
        id = "objective_upgrade_building",
        title = "Upgrade a Building",
        description = "Upgrade any building to level 2.",
        condition = { kind = "buildingLevel", level = 2 },
        rewardCoins = 50,
    },
    {
        id = "objective_build_generator",
        title = "Build a Generator",
        description = "Generators produce Energy for advanced upgrades.",
        condition = { kind = "building", definitionId = "building_generator" },
        rewardCoins = 50,
    },
    {
        id = "objective_staff_generator",
        title = "Harness Lightning",
        description = "Assign a Voltfox to your Generator.",
        condition = { kind = "worker", definitionId = "building_generator" },
        rewardCoins = 60,
    },
    {
        id = "objective_build_warehouse",
        title = "Build a Warehouse",
        description = "Warehouses raise your storage limit.",
        condition = { kind = "building", definitionId = "building_warehouse" },
        rewardCoins = 60,
    },
    {
        id = "objective_reach_level_three",
        title = "Master Builder",
        description = "Upgrade any building to level 3.",
        condition = { kind = "buildingLevel", level = 3 },
        rewardCoins = 100,
    },
}

local byId = {}
for index, objective in ipairs(objectives) do
    assert(byId[objective.id] == nil, `Duplicate objective {objective.id}`)
    objective.order = index
    byId[objective.id] = objective
end

return TableUtil.deepFreeze({
    Ordered = objectives,
    ById = byId,
})
