-- Deterministic pseudo-random numbers (mulberry32). Breeding and combat are pure functions of
-- their inputs plus a stored seed, so a result can be recomputed exactly and a player cannot
-- re-roll it by leaving and rejoining. Not suitable for anything security-sensitive.
local TWO_32 = 4294967296

local SeededRandom = {}
SeededRandom.__index = SeededRandom

export type SeededRandom = typeof(setmetatable({} :: { _state: number }, SeededRandom))

-- 32-bit integer multiply on unsigned operands, exact in double precision.
local function imul(a: number, b: number): number
    local high = a // 65536
    local low = a % 65536
    return (low * b + ((high * b) % 65536) * 65536) % TWO_32
end

local function isSeed(value: any): boolean
    return type(value) == "number" and value % 1 == 0 and value >= 0 and value < TWO_32
end

-- FNV-1a over the UTF-8 bytes, for deriving a seed from an id such as an egg or expedition id.
function SeededRandom.seedFromString(text: string): number
    local hash = 2166136261
    for index = 1, #text do
        hash = imul(bit32.bxor(hash, string.byte(text, index)), 16777619)
    end
    return hash
end

-- `seed` must be an integer in [0, 2^32). The state is the seed itself and can be saved with
-- `getState` and resumed with `new`.
function SeededRandom.new(seed: number): SeededRandom
    assert(isSeed(seed), "seed must be an integer in [0, 2^32)")
    return setmetatable({ _state = seed }, SeededRandom)
end

function SeededRandom.getState(self: SeededRandom): number
    return self._state
end

-- Next unsigned 32-bit integer.
function SeededRandom.nextUint32(self: SeededRandom): number
    self._state = (self._state + 0x6D2B79F5) % TWO_32
    local t = self._state
    t = imul(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
    t = bit32.bxor(t, (t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % TWO_32)
    return bit32.bxor(t, bit32.rshift(t, 14))
end

-- Uniform float in [0, 1).
function SeededRandom.nextFloat(self: SeededRandom): number
    return self:nextUint32() / TWO_32
end

-- Uniform integer in [min, max], both inclusive.
function SeededRandom.nextInt(self: SeededRandom, min: number, max: number): number
    assert(
        type(min) == "number" and type(max) == "number" and min % 1 == 0 and max % 1 == 0,
        "bounds must be integers"
    )
    assert(max >= min, "max must not be below min")
    return min + math.floor(self:nextFloat() * (max - min + 1))
end

-- True with probability `probability` (clamped to [0, 1]).
function SeededRandom.chance(self: SeededRandom, probability: number): boolean
    return self:nextFloat() < probability
end

-- Uniform element of a non-empty array.
function SeededRandom.pick<T>(self: SeededRandom, items: { T }): T
    assert(#items > 0, "cannot pick from an empty list")
    return items[self:nextInt(1, #items)]
end

-- Index into `weights` (an array of non-negative numbers) chosen proportionally to weight.
function SeededRandom.pickWeighted(self: SeededRandom, weights: { number }): number
    local total = 0
    for _, weight in ipairs(weights) do
        assert(type(weight) == "number" and weight >= 0, "weights must be non-negative numbers")
        total += weight
    end
    assert(total > 0, "at least one weight must be positive")

    local roll = self:nextFloat() * total
    local running = 0
    local last = 1
    for index, weight in ipairs(weights) do
        if weight > 0 then
            last = index
            running += weight
            if roll < running then
                return index
            end
        end
    end
    return last
end

return SeededRandom
