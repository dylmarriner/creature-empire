local ProductionMath = {}

ProductionMath.DEFAULT_OFFLINE_CAP_SECONDS = 8 * 60 * 60

local function isFinite(value: number): boolean
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function assertNonNegativeFinite(value: number, name: string)
    assert(isFinite(value) and value >= 0, `{name} must be a non-negative finite number`)
end

function ProductionMath.clampElapsedSeconds(elapsedSeconds: number, capSeconds: number?): number
    assertNonNegativeFinite(elapsedSeconds, "elapsedSeconds")

    local cap = capSeconds or ProductionMath.DEFAULT_OFFLINE_CAP_SECONDS
    assert(isFinite(cap) and cap > 0, "capSeconds must be a positive finite number")

    return math.min(elapsedSeconds, cap)
end

function ProductionMath.calculateOutput(
    baseRatePerMinute: number,
    buildingMultiplier: number,
    workerMultiplier: number,
    traitMultiplier: number,
    elapsedSeconds: number
): number
    assertNonNegativeFinite(baseRatePerMinute, "baseRatePerMinute")
    assertNonNegativeFinite(buildingMultiplier, "buildingMultiplier")
    assertNonNegativeFinite(workerMultiplier, "workerMultiplier")
    assertNonNegativeFinite(traitMultiplier, "traitMultiplier")
    assertNonNegativeFinite(elapsedSeconds, "elapsedSeconds")

    local elapsedMinutes = elapsedSeconds / 60
    local output = baseRatePerMinute
        * buildingMultiplier
        * workerMultiplier
        * traitMultiplier
        * elapsedMinutes

    assert(isFinite(output), "calculated production output must be finite")

    return math.max(0, math.floor(output + 1e-9))
end

return table.freeze(ProductionMath)
