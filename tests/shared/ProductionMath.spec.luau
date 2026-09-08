local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JestGlobals = require(ReplicatedStorage.Packages.JestGlobals)
local ProductionMath = require(ReplicatedStorage.Shared.Economy.ProductionMath)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("ProductionMath", function()
    it("calculates deterministic elapsed-time production", function()
        expect(ProductionMath.calculateOutput(10, 1, 1, 1, 120)).toBe(20)
    end)

    it("caps offline production to eight hours by default", function()
        expect(ProductionMath.clampElapsedSeconds(12 * 60 * 60)).toBe(8 * 60 * 60)
    end)
end)
