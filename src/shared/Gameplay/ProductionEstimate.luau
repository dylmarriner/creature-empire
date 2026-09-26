-- Display-only estimates of unclaimed production from replicated snapshot data. The server
-- settles the authoritative amount on claim, applying input and storage limits.
local ProductionEstimate = {}

-- Whole cycles a building has accrued since its last claim at `now`.
function ProductionEstimate.pendingCycles(
    building: any,
    cyclesPerMinute: number,
    now: number,
    offlineCapSeconds: number
): number
    if
        type(building) ~= "table"
        or type(building.lastClaimedAt) ~= "number"
        or cyclesPerMinute <= 0
    then
        return 0
    end
    local elapsed = math.clamp(now - building.lastClaimedAt, 0, offlineCapSeconds)
    return math.max(0, math.floor(cyclesPerMinute / 60 * elapsed + 1e-9))
end

-- Total accrued cycles and the number of buildings with at least one cycle ready.
function ProductionEstimate.summarize(snapshot: any, now: number): (number, number)
    local cycles = 0
    local ready = 0
    if type(snapshot) ~= "table" or type(snapshot.profile) ~= "table" then
        return cycles, ready
    end

    for buildingId, building in pairs(snapshot.profile.buildings) do
        local rate = snapshot.rates[buildingId] or 0
        local pending =
            ProductionEstimate.pendingCycles(building, rate, now, snapshot.offlineCapSeconds)
        if pending > 0 then
            cycles += pending
            ready += 1
        end
    end

    return cycles, ready
end

return table.freeze(ProductionEstimate)
