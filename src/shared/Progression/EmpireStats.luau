local CapacityDomain = require("../Economy/CapacityDomain")
local NumberUtil = require("../Util/NumberUtil")

-- Public empire summary shown on the player list and in the visit menu. Derived entirely
-- from the profile, so it can never drift from saved state.
export type Summary = {
    empireLevel: number,
    buildings: number,
    creatures: number,
}

local function summarize(profile: any): Summary
    local empireLevel = 0
    local buildings = 0
    if type(profile) == "table" and type(profile.buildings) == "table" then
        for _, building in pairs(profile.buildings) do
            if type(building) == "table" and NumberUtil.isPositiveInteger(building.level) then
                buildings += 1
                empireLevel += building.level
            end
        end
    end

    return {
        empireLevel = empireLevel,
        buildings = buildings,
        creatures = CapacityDomain.creatureCount(profile),
    }
end

return table.freeze({
    summarize = summarize,
})
