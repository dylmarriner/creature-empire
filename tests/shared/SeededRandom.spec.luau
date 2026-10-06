local Expect = require("../support/Expect")
local SeededRandom = require("../../src/shared/Util/SeededRandom")

-- Reference sequences generated with the canonical JavaScript mulberry32 implementation.
local REFERENCE = {
    { seed = 0, values = { 1144304738, 1416247, 958946056, 627933444, 2007157716 } },
    { seed = 1, values = { 2693262067, 11749833, 2265367787, 4213581821, 4159151403 } },
    { seed = 12345, values = { 4207900869, 1317490944, 2079646450, 3513001552, 2187978186 } },
    {
        seed = 4294967295,
        values = { 3850105811, 813802916, 3073704848, 4054706436, 3630262831 },
    },
}

local function run()
    for _, reference in ipairs(REFERENCE) do
        local random = SeededRandom.new(reference.seed)
        for index, expected in ipairs(reference.values) do
            Expect.equal(random:nextUint32(), expected, `seed {reference.seed} value {index}`)
        end
    end

    Expect.equal(SeededRandom.seedFromString(""), 2166136261, "empty string hash")
    Expect.equal(SeededRandom.seedFromString("a"), 3826002220, "single character hash")
    Expect.equal(SeededRandom.seedFromString("egg_1"), 920729950, "id hash")

    -- Same seed, same sequence; state round-trips.
    local first = SeededRandom.new(99)
    local second = SeededRandom.new(99)
    for _ = 1, 50 do
        Expect.equal(first:nextUint32(), second:nextUint32(), "same seed matches")
    end

    local resumed = SeededRandom.new(first:getState())
    for _ = 1, 20 do
        Expect.equal(first:nextUint32(), resumed:nextUint32(), "resumed state matches")
    end

    -- Bounds.
    local bounded = SeededRandom.new(7)
    local seen = {}
    for _ = 1, 2000 do
        local value = bounded:nextInt(3, 6)
        Expect.truthy(value >= 3 and value <= 6 and value % 1 == 0, "nextInt in bounds")
        seen[value] = true
        local unit = bounded:nextFloat()
        Expect.truthy(unit >= 0 and unit < 1, "nextFloat in [0, 1)")
    end
    for value = 3, 6 do
        Expect.truthy(seen[value], `nextInt reaches {value}`)
    end
    Expect.equal(SeededRandom.new(1):nextInt(5, 5), 5, "degenerate range")

    -- Rough uniformity: a thousand rolls of a fair coin land well away from the extremes.
    local coin = SeededRandom.new(2024)
    local heads = 0
    for _ = 1, 1000 do
        if coin:chance(0.5) then
            heads += 1
        end
    end
    Expect.truthy(heads > 440 and heads < 560, `fair coin is roughly even ({heads})`)

    local never = SeededRandom.new(5)
    local always = SeededRandom.new(5)
    for _ = 1, 100 do
        Expect.falsy(never:chance(0), "chance(0) never succeeds")
        Expect.truthy(always:chance(1), "chance(1) always succeeds")
    end

    -- Weighted picks follow the weights and never choose a zero weight.
    local weighted = SeededRandom.new(11)
    local counts = { 0, 0, 0 }
    for _ = 1, 3000 do
        local index = weighted:pickWeighted({ 1, 0, 3 })
        counts[index] += 1
    end
    Expect.equal(counts[2], 0, "zero weight never picked")
    Expect.truthy(counts[3] > counts[1] * 2, "heavier weight picked more often")

    Expect.truthy(SeededRandom.new(3):pick({ "a", "b", "c" }) ~= nil, "pick returns an element")

    -- Invalid input is refused.
    Expect.falsy(pcall(SeededRandom.new, -1), "negative seed refused")
    Expect.falsy(pcall(SeededRandom.new, 1.5), "fractional seed refused")
    Expect.falsy(pcall(SeededRandom.new, 4294967296), "seed beyond 32 bits refused")
    Expect.falsy(
        pcall(function()
            SeededRandom.new(1):nextInt(5, 4)
        end),
        "inverted range refused"
    )
    Expect.falsy(
        pcall(function()
            SeededRandom.new(1):pickWeighted({ 0, 0 })
        end),
        "all-zero weights refused"
    )
end

return run
