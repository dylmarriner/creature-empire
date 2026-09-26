local Expect = require("../support/Expect")
local ActionSchemas = require("../../src/shared/Net/ActionSchemas")
local RateLimiter = require("../../src/shared/Net/RateLimiter")

local function run()
    local valid, assign =
        ActionSchemas.validate("AssignCreature", { creatureId = "c_1234-abcd", buildingId = "b_1" })
    Expect.truthy(valid, "valid assign payload")
    Expect.equal(assign.creatureId, "c_1234-abcd", "sanitized creature id")

    Expect.falsy(
        (ActionSchemas.validate("AssignCreature", { creatureId = "c_1" })),
        "missing field rejected"
    )
    Expect.falsy(
        (
            ActionSchemas.validate(
                "AssignCreature",
                { creatureId = "c_1", buildingId = "b", extra = 1 }
            )
        ),
        "unexpected field rejected"
    )
    Expect.falsy(
        (
            ActionSchemas.validate(
                "AssignCreature",
                { creatureId = "c_1", buildingId = "b", [1] = "x" }
            )
        ),
        "array key rejected"
    )
    Expect.falsy(
        (ActionSchemas.validate("AssignCreature", { creatureId = 5, buildingId = "b" })),
        "non-string id rejected"
    )
    Expect.falsy(
        (ActionSchemas.validate("AssignCreature", { creatureId = "", buildingId = "b" })),
        "empty id rejected"
    )
    Expect.falsy(
        (
            ActionSchemas.validate(
                "AssignCreature",
                { creatureId = string.rep("a", 65), buildingId = "b" }
            )
        ),
        "overlong id rejected"
    )
    Expect.falsy(
        (ActionSchemas.validate("AssignCreature", { creatureId = "c 1", buildingId = "b" })),
        "id with spaces rejected"
    )
    Expect.falsy((ActionSchemas.validate("AssignCreature", "payload")), "non-table rejected")
    Expect.falsy((ActionSchemas.validate("DeleteEverything", {})), "unknown action rejected")

    local placeOk, place = ActionSchemas.validate(
        "PlaceBuilding",
        { definitionId = "building_mine", cellX = 3, cellZ = 4, rotation = 90 }
    )
    Expect.truthy(placeOk, "valid placement payload")
    Expect.equal(place.rotation, 90, "rotation kept")
    Expect.falsy(
        (
            ActionSchemas.validate(
                "PlaceBuilding",
                { definitionId = "building_mine", cellX = 0 / 0, cellZ = 4, rotation = 0 }
            )
        ),
        "NaN rejected"
    )
    Expect.falsy(
        (
            ActionSchemas.validate(
                "PlaceBuilding",
                { definitionId = "building_mine", cellX = math.huge, cellZ = 4, rotation = 0 }
            )
        ),
        "infinity rejected"
    )
    Expect.falsy(
        (
            ActionSchemas.validate(
                "PlaceBuilding",
                { definitionId = "building_mine", cellX = -1, cellZ = 4, rotation = 0 }
            )
        ),
        "negative cell rejected"
    )
    Expect.falsy(
        (
            ActionSchemas.validate(
                "PlaceBuilding",
                { definitionId = "building_mine", cellX = 1.5, cellZ = 4, rotation = 0 }
            )
        ),
        "fractional cell rejected"
    )
    Expect.falsy(
        (ActionSchemas.validate("SellResource", { itemId = "item_wood", quantity = -5 })),
        "negative quantity rejected"
    )

    local claimAllOk, claimAll = ActionSchemas.validate("ClaimProduction", {})
    Expect.truthy(claimAllOk, "optional field may be omitted")
    Expect.equal(claimAll.buildingId, nil, "omitted optional field")
    Expect.truthy(
        (ActionSchemas.validate("ClaimProduction", { buildingId = "b_1" })),
        "optional id"
    )
    Expect.truthy((ActionSchemas.validate("RequestSync", nil)), "nil payload for empty schema")

    local travelOk, travel = ActionSchemas.validate("Travel", { destination = "wilds" })
    Expect.truthy(travelOk, "enum value accepted")
    Expect.equal(travel.destination, "wilds", "enum value kept")
    Expect.falsy(
        (ActionSchemas.validate("Travel", { destination = "moon" })),
        "enum value rejected"
    )
    Expect.falsy((ActionSchemas.validate("Travel", { destination = 1 })), "enum type rejected")
    Expect.equal(ActionSchemas.scopeFor("Travel"), "session", "travel is a session action")
    local visitOk, visit =
        ActionSchemas.validate("Travel", { destination = "plot", targetUserId = 12345 })
    Expect.truthy(visitOk, "plot visit accepted")
    Expect.equal(visit.targetUserId, 12345, "visit target kept")
    Expect.falsy(
        (ActionSchemas.validate("Travel", { destination = "plot", targetUserId = 0 })),
        "non-positive visit target rejected"
    )
    Expect.falsy(
        (ActionSchemas.validate("Travel", { destination = "plot", targetUserId = 1.5 })),
        "fractional visit target rejected"
    )
    local homeOk, home = ActionSchemas.validate("Travel", { destination = "home" })
    Expect.truthy(homeOk, "visit target is optional")
    Expect.equal(home.targetUserId, nil, "no visit target for home")
    Expect.equal(
        ActionSchemas.scopeFor("PlaceBuilding"),
        "profile",
        "placement is a profile action"
    )

    Expect.truthy(ActionSchemas.isValidRequestId(1), "request id")
    Expect.falsy(ActionSchemas.isValidRequestId(-1), "negative request id")
    Expect.falsy(ActionSchemas.isValidRequestId(0.5), "fractional request id")
    Expect.falsy(ActionSchemas.isValidRequestId("1"), "string request id")

    local now = 0
    local limiter = RateLimiter.new(function()
        return now
    end)
    Expect.truthy(limiter:allow("p:a", 2, 1), "first token")
    Expect.truthy(limiter:allow("p:a", 2, 1), "second token")
    Expect.falsy(limiter:allow("p:a", 2, 1), "burst exhausted")
    Expect.truthy(limiter:allow("p:b", 2, 1), "keys are independent")
    now = 1
    Expect.truthy(limiter:allow("p:a", 2, 1), "refilled after one second")
    Expect.falsy(limiter:allow("p:a", 2, 1), "only one token refilled")
    now = 100
    Expect.truthy(limiter:allow("p:a", 2, 1), "refill capped")
    Expect.truthy(limiter:allow("p:a", 2, 1), "refill capped at burst")
    Expect.falsy(limiter:allow("p:a", 2, 1), "burst cap applies")
    limiter:forgetPrefix("p:")
    Expect.truthy(limiter:allow("p:a", 1, 0), "forgotten bucket starts full")
end

return run
