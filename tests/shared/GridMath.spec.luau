local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JestGlobals = require(ReplicatedStorage.Packages.JestGlobals)
local GridMath = require(ReplicatedStorage.Shared.Buildings.GridMath)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("GridMath", function()
    it("snaps positions to the configured build grid", function()
        local snapped = GridMath.snapPosition({ x = 7.9, y = 0.1, z = -9.2 }, 4)

        expect(snapped.x).toBe(8)
        expect(snapped.y).toBe(0)
        expect(snapped.z).toBe(-8)
    end)
end)
