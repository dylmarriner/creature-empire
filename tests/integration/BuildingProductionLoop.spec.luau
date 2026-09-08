local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local InventoryDomain = require("../../src/shared/Economy/InventoryDomain")
local CreatureOwnershipDomain = require("../../src/shared/Creatures/CreatureOwnershipDomain")
local BuildingPlacementDomain = require("../../src/shared/Buildings/BuildingPlacementDomain")
local WorkAssignmentMutationDomain = require("../../src/shared/Creatures/WorkAssignmentMutationDomain")
local ProductionDomain = require("../../src/shared/Economy/ProductionDomain")

local function expectEqual(actual: any, expected: any, label: string)
    if actual ~= expected then
        error(`{label}: expected {expected}, got {actual}`)
    end
end

local function expectOk(result: any, label: string)
    if result.ok ~= true then
        error(`{label}: expected ok result, got {result.code}`)
    end
end

local function generator(value: string)
    return function()
        return value
    end
end

local function run()
    local profile = ProfileSchema.createDefault(100)
    expectOk(InventoryDomain.add(profile, "item_wood", 20), "seed wood")
    expectOk(InventoryDomain.add(profile, "item_stone", 80), "seed stone")

    local starter = CreatureOwnershipDomain.grantStarter(profile, generator("rockhorn_1"))
    expectOk(starter, "grant starter Rockhorn")
    expectEqual(starter.value.speciesId, "creature_rockhorn", "starter species")

    local mine = BuildingPlacementDomain.place(
        profile,
        "building_mine",
        { x = 0, y = 0, z = 0 },
        0,
        generator("mine_1"),
        100
    )
    expectOk(mine, "place Mine")
    expectEqual(profile.inventory.item_wood, nil, "Mine consumes starter wood")
    expectEqual(profile.inventory.item_stone, 50, "Mine leaves fifty stone")

    expectOk(
        WorkAssignmentMutationDomain.assign(profile, "rockhorn_1", "mine_1", 100),
        "assign Rockhorn to Mine"
    )
    expectEqual(profile.creatures.rockhorn_1.assignedBuildingId, "mine_1", "Rockhorn assignment")
    expectEqual(profile.buildings.mine_1.assignedCreatureIds[1], "rockhorn_1", "Mine worker list")

    local firstOre = ProductionDomain.claim(profile, "mine_1", 220)
    expectOk(firstOre, "first Mine claim")
    expectEqual(firstOre.value.outputQuantity, 15, "first Mine output")
    expectEqual(profile.inventory.item_copper_ore, 15, "first Mine inventory")
    expectEqual(profile.buildings.mine_1.lastClaimedAt, 220, "first Mine timestamp")

    local furnace = BuildingPlacementDomain.place(
        profile,
        "building_furnace",
        { x = 4, y = 0, z = 0 },
        0,
        generator("furnace_1"),
        220
    )
    expectOk(furnace, "place Furnace")
    expectEqual(profile.inventory.item_stone, nil, "Furnace consumes remaining stone")
    expectEqual(profile.inventory.item_copper_ore, nil, "Furnace construction consumes first ore")

    local embercub = CreatureOwnershipDomain.capture(
        profile,
        "creature_embercub",
        true,
        generator("ember_1")
    )
    expectOk(embercub, "capture Embercub")

    expectOk(
        WorkAssignmentMutationDomain.assign(profile, "ember_1", "furnace_1", 220),
        "assign Embercub to Furnace"
    )
    expectEqual(profile.creatures.ember_1.assignedBuildingId, "furnace_1", "Embercub assignment")
    expectEqual(profile.buildings.furnace_1.assignedCreatureIds[1], "ember_1", "Furnace worker list")

    local secondOre = ProductionDomain.claim(profile, "mine_1", 340)
    expectOk(secondOre, "second Mine claim")
    expectEqual(secondOre.value.outputQuantity, 15, "second Mine output")
    expectEqual(profile.inventory.item_copper_ore, 15, "second Mine inventory")
    expectEqual(profile.buildings.mine_1.lastClaimedAt, 340, "second Mine timestamp")

    local bars = ProductionDomain.claim(profile, "furnace_1", 340)
    expectOk(bars, "Furnace claim")
    expectEqual(bars.value.outputQuantity, 10, "Furnace bar output")
    expectEqual(bars.value.inputQuantity, 10, "Furnace ore input")
    expectEqual(profile.inventory.item_copper_ore, 5, "final Copper Ore")
    expectEqual(profile.inventory.item_copper_bar, 10, "final Copper Bars")
    expectEqual(profile.buildings.furnace_1.lastClaimedAt, 340, "Furnace timestamp")
end

return run
