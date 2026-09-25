local Expect = require("../support/Expect")
local Fixtures = require("../support/Fixtures")
local PlacementDomain = require("../../src/shared/Buildings/PlacementDomain")

local function richProfile()
    local profile = Fixtures.profile()
    profile.inventory.item_wood = 1000
    profile.inventory.item_stone = 1000
    profile.inventory.item_food = 1000
    profile.inventory.item_copper_ore = 1000
    profile.inventory.item_copper_bar = 1000
    return profile
end

local function run()
    local profile = Fixtures.profile()
    profile.inventory.item_wood = 25
    profile.inventory.item_stone = 30

    local placed = Expect.ok(
        PlacementDomain.place(profile, "building_mine", 0, 0, 0, 1000, Expect.idSequence("b")),
        "place mine"
    )
    Expect.equal(placed.id, "b_1", "generated id")
    Expect.equal(placed.definitionId, "building_mine", "definition")
    Expect.equal(placed.level, 1, "starts at level 1")
    Expect.equal(placed.lastClaimedAt, 1000, "claim clock starts at placement")
    Expect.equal(#placed.assignedCreatureIds, 0, "no workers")
    Expect.equal(profile.buildings.b_1, placed, "persisted")
    Expect.equal(profile.inventory.item_wood, 5, "wood deducted")
    Expect.equal(profile.inventory.item_stone, nil, "stone deducted")

    local rich = richProfile()
    Expect.ok(
        PlacementDomain.place(rich, "building_mine", 0, 0, 0, 1000, Expect.idSequence("m")),
        "first mine"
    )
    Expect.errorCode(
        PlacementDomain.place(rich, "building_mine", 2, 2, 0, 1000, Expect.idSequence("x")),
        "invalid_placement",
        "overlap rejected"
    )
    Expect.ok(
        PlacementDomain.place(rich, "building_lumber_mill", 3, 0, 0, 1000, Expect.idSequence("l")),
        "adjacent placement allowed"
    )

    Expect.errorCode(
        PlacementDomain.checkPlacement(rich, "building_farm", 27, 10, 0),
        "invalid_placement",
        "out of bounds rejected"
    )
    Expect.ok(PlacementDomain.checkPlacement(rich, "building_farm", 26, 10, 0), "edge fits")
    Expect.errorCode(
        PlacementDomain.checkPlacement(rich, "building_farm", -1, 10, 0),
        "invalid_placement",
        "negative cell rejected"
    )
    Expect.errorCode(
        PlacementDomain.checkPlacement(rich, "building_farm", 10.5, 10, 0),
        "invalid_placement",
        "fractional cell rejected"
    )
    Expect.errorCode(
        PlacementDomain.checkPlacement(rich, "building_farm", 10, 10, 45),
        "invalid_placement",
        "non-quarter rotation rejected"
    )
    Expect.errorCode(
        PlacementDomain.checkPlacement(rich, "building_unknown", 10, 10, 0),
        "invalid_request",
        "unknown definition rejected"
    )

    -- Warehouse is 4x3; a quarter turn makes it 3x4.
    Expect.errorCode(
        PlacementDomain.checkPlacement(rich, "building_warehouse", 27, 20, 0),
        "invalid_placement",
        "unrotated warehouse too wide"
    )
    Expect.ok(
        PlacementDomain.checkPlacement(rich, "building_warehouse", 27, 20, 90),
        "rotated warehouse fits"
    )
    local width, depth = PlacementDomain.footprintFor({ footprint = { x = 4, z = 3 } }, 270)
    Expect.equal(width, 3, "rotated width")
    Expect.equal(depth, 4, "rotated depth")

    -- Rotated neighbours are checked with their rotated footprint.
    local rotated = richProfile()
    Expect.ok(
        PlacementDomain.place(rotated, "building_warehouse", 0, 0, 90, 1000, Expect.idSequence("w")),
        "rotated warehouse"
    )
    Expect.errorCode(
        PlacementDomain.checkPlacement(rotated, "building_workbench", 1, 3, 0),
        "invalid_placement",
        "overlaps rotated footprint"
    )
    Expect.ok(
        PlacementDomain.checkPlacement(rotated, "building_workbench", 3, 0, 0),
        "beside rotated footprint"
    )

    -- Limits and costs.
    local limited = richProfile()
    Expect.ok(
        PlacementDomain.place(limited, "building_workbench", 0, 0, 0, 1000, Expect.idSequence("wb")),
        "first workbench"
    )
    Expect.errorCode(
        PlacementDomain.place(limited, "building_workbench", 5, 5, 0, 1000, Expect.idSequence("wc")),
        "building_limit_reached",
        "second workbench rejected"
    )

    local poor = Fixtures.profile()
    poor.inventory.item_wood = 19
    poor.inventory.item_stone = 30
    Expect.errorCode(
        PlacementDomain.place(poor, "building_mine", 0, 0, 0, 1000, Expect.idSequence("p")),
        "insufficient_resources",
        "unaffordable rejected"
    )
    Expect.equal(poor.inventory.item_wood, 19, "failed placement keeps wood")
    Expect.equal(next(poor.buildings), nil, "failed placement creates nothing")

    local badId = richProfile()
    Expect.errorCode(
        PlacementDomain.place(badId, "building_mine", 0, 0, 0, 1000, function()
            return ""
        end),
        "invalid_generated_id",
        "empty id rejected"
    )
    Expect.equal(badId.inventory.item_wood, 1000, "invalid id does not charge")

    -- Removal settles, releases workers and refunds half the base cost.
    local removal = Fixtures.profile()
    removal.inventory.item_wood = 100
    removal.inventory.item_stone = 100
    Fixtures.addCreature(removal, "rockhorn_1", "creature_rockhorn")
    Fixtures.addStaffedBuilding(removal, "mine_1", "building_mine", { "rockhorn_1" })
    local removed = Expect.ok(PlacementDomain.remove(removal, "mine_1", 1060), "remove mine")
    Expect.equal(removal.buildings.mine_1, nil, "building removed")
    Expect.equal(removal.creatures.rockhorn_1.assignedBuildingId, nil, "worker released")
    Expect.equal(removed.refund.item_wood, 10, "wood refund")
    Expect.equal(removed.refund.item_stone, 15, "stone refund")
    Expect.equal(removal.inventory.item_wood, 110, "wood refunded")
    Expect.equal(removal.inventory.item_stone, 100 + 7 + 15, "stone refunded plus settled output")
    Expect.equal(removal.inventory.item_copper_ore, 7, "settled before removal")

    Expect.errorCode(
        PlacementDomain.remove(removal, "mine_1", 1060),
        "building_not_owned",
        "remove missing building"
    )
end

return run
