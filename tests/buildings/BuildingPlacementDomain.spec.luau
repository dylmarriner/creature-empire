local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local BuildingPlacementDomain = require("../../src/shared/Buildings/BuildingPlacementDomain")

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

local function expectErrorCode(result: any, code: string, label: string)
    if result.ok ~= false then
        error(`{label}: expected error result`)
    end
    expectEqual(result.code, code, label)
end

local function generator(value: any)
    return function()
        return value
    end
end

local function fundedProfile()
    local profile = ProfileSchema.createDefault(100)
    profile.inventory.item_wood = 200
    profile.inventory.item_stone = 200
    profile.inventory.item_copper_ore = 200
    return profile
end

local function run()
    local profile = fundedProfile()
    local placed = BuildingPlacementDomain.place(
        profile,
        "building_mine",
        { x = 5.9, y = 0, z = -9.2 },
        90,
        generator("building_instance_mine"),
        100
    )
    expectOk(placed, "valid placement")
    expectEqual(placed.value.id, "building_instance_mine", "generated building id")
    expectEqual(placed.value.position.x, 4, "snapped x")
    expectEqual(placed.value.position.y, 0, "snapped y")
    expectEqual(placed.value.position.z, -8, "snapped z")
    expectEqual(placed.value.rotation, 90, "rotation retained")
    expectEqual(placed.value.level, 1, "initial level")
    expectEqual(#placed.value.assignedCreatureIds, 0, "initial worker list")
    expectEqual(placed.value.lastClaimedAt, 100, "initial claim timestamp")
    expectEqual(profile.inventory.item_wood, 180, "Mine wood cost")
    expectEqual(profile.inventory.item_stone, 170, "Mine stone cost")
    expectEqual(profile.buildings.building_instance_mine, placed.value, "building stored")

    local unknownProfile = fundedProfile()
    local unknown = BuildingPlacementDomain.place(
        unknownProfile,
        "building_unknown",
        { x = 0, y = 0, z = 0 },
        0,
        generator("building_unknown_instance"),
        100
    )
    expectErrorCode(unknown, "invalid_request", "unknown definition rejected")
    expectEqual(unknownProfile.inventory.item_wood, 200, "unknown definition no wood cost")
    expectEqual(next(unknownProfile.buildings), nil, "unknown definition no building")

    local invalidIdProfile = fundedProfile()
    local invalidId = BuildingPlacementDomain.place(
        invalidIdProfile,
        "building_mine",
        { x = 0, y = 0, z = 0 },
        0,
        generator(""),
        100
    )
    expectErrorCode(invalidId, "invalid_generated_id", "invalid generated id rejected")
    expectEqual(invalidIdProfile.inventory.item_wood, 200, "invalid id no cost")

    local duplicateIdProfile = fundedProfile()
    duplicateIdProfile.buildings.building_taken = {
        id = "building_taken",
        definitionId = "building_mine",
        level = 1,
        position = { x = 20, y = 0, z = 20 },
        rotation = 0,
        assignedCreatureIds = {},
        lastClaimedAt = 100,
    }
    local duplicateId = BuildingPlacementDomain.place(
        duplicateIdProfile,
        "building_mine",
        { x = 0, y = 0, z = 0 },
        0,
        generator("building_taken"),
        100
    )
    expectErrorCode(duplicateId, "duplicate_building_instance", "duplicate building id rejected")
    expectEqual(duplicateIdProfile.inventory.item_wood, 200, "duplicate id no cost")

    local offPlotProfile = fundedProfile()
    local offPlot = BuildingPlacementDomain.place(
        offPlotProfile,
        "building_mine",
        { x = 68, y = 0, z = 0 },
        0,
        generator("building_off_plot"),
        100
    )
    expectErrorCode(offPlot, "invalid_placement", "off plot rejected")
    expectEqual(offPlotProfile.inventory.item_wood, 200, "off plot no cost")

    local occupiedProfile = fundedProfile()
    occupiedProfile.buildings.building_existing = {
        id = "building_existing",
        definitionId = "building_mine",
        level = 1,
        position = { x = 4, y = 0, z = 8 },
        rotation = 0,
        assignedCreatureIds = {},
        lastClaimedAt = 100,
    }
    local occupied = BuildingPlacementDomain.place(
        occupiedProfile,
        "building_mine",
        { x = 5.9, y = 0, z = 9.2 },
        0,
        generator("building_occupied"),
        100
    )
    expectErrorCode(occupied, "invalid_placement", "occupied origin rejected")
    expectEqual(occupiedProfile.inventory.item_wood, 200, "occupied origin no cost")

    local elevatedProfile = fundedProfile()
    local elevated = BuildingPlacementDomain.place(
        elevatedProfile,
        "building_mine",
        { x = 0, y = 4, z = 0 },
        0,
        generator("building_elevated"),
        100
    )
    expectErrorCode(elevated, "invalid_placement", "elevated placement rejected")
    expectEqual(elevatedProfile.inventory.item_wood, 200, "elevated no cost")

    local rotationProfile = fundedProfile()
    local badRotation = BuildingPlacementDomain.place(
        rotationProfile,
        "building_mine",
        { x = 0, y = 0, z = 0 },
        45,
        generator("building_bad_rotation"),
        100
    )
    expectErrorCode(badRotation, "invalid_placement", "bad rotation rejected")
    expectEqual(rotationProfile.inventory.item_wood, 200, "bad rotation no cost")

    local poorProfile = ProfileSchema.createDefault(100)
    poorProfile.inventory.item_wood = 19
    poorProfile.inventory.item_stone = 30
    local poor = BuildingPlacementDomain.place(
        poorProfile,
        "building_mine",
        { x = 0, y = 0, z = 0 },
        0,
        generator("building_poor"),
        100
    )
    expectErrorCode(poor, "insufficient_resources", "insufficient resources rejected")
    expectEqual(poorProfile.inventory.item_wood, 19, "insufficient resources unchanged")
    expectEqual(next(poorProfile.buildings), nil, "insufficient resources no building")
end

return run
