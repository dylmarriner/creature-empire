local Expect = require("../support/Expect")
local ProductionMath = require("../../src/shared/Economy/ProductionMath")
local GridMath = require("../../src/shared/Buildings/GridMath")

local function run()
    Expect.equal(ProductionMath.calculateOutput(10, 1, 1, 1, 120), 20, "base production")
    Expect.equal(
        ProductionMath.clampElapsedSeconds(12 * 60 * 60),
        8 * 60 * 60,
        "offline production cap"
    )
    Expect.equal(GridMath.snapCoordinate(5.9, 4), 4, "positive grid snap")
    Expect.equal(GridMath.snapCoordinate(-5.9, 4), -4, "negative grid snap")

    local snapped = GridMath.snapPosition({ x = 7.9, y = 0.1, z = -9.2 }, 4)
    Expect.equal(snapped.x, 8, "position x")
    Expect.equal(snapped.y, 0, "position y")
    Expect.equal(snapped.z, -8, "position z")

    Expect.truthy(not pcall(ProductionMath.calculateOutput, -1, 1, 1, 1, 60), "negative rate")
    Expect.truthy(not pcall(ProductionMath.calculateOutput, 0 / 0, 1, 1, 1, 60), "NaN rate")
    Expect.truthy(not pcall(ProductionMath.clampElapsedSeconds, math.huge), "infinite elapsed")
end

return run
