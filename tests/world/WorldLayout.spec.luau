local Expect = require("../support/Expect")
local GameConfig = require("../../src/shared/Config/GameConfig")
local BuildingDefinitions = require("../../src/shared/Buildings/BuildingDefinitions")
local WorldLayout = require("../../src/shared/World/WorldLayout")

local function run()
    -- Plot slots never overlap and keep the configured gap.
    local firstX, firstZ = WorldLayout.plotCornerXZ(1)
    local secondX, secondZ = WorldLayout.plotCornerXZ(2)
    Expect.equal(secondZ, firstZ, "same row")
    Expect.equal(
        secondX - firstX,
        WorldLayout.PLOT_STUDS + WorldLayout.PLOT_GAP_STUDS,
        "column spacing"
    )
    local _, nextRowZ = WorldLayout.plotCornerXZ(WorldLayout.PLOT_COLUMNS + 1)
    Expect.equal(
        nextRowZ - firstZ,
        WorldLayout.PLOT_STUDS + WorldLayout.PLOT_GAP_STUDS,
        "row spacing"
    )

    -- The idle pen holds the largest possible creature roster inside the gap between rows.
    local habitat = BuildingDefinitions.ById.building_creature_habitat
    local maxCreatures = GameConfig.BASE_CREATURE_CAPACITY
        + habitat.maxCount
            * GameConfig.MAX_BUILDING_LEVEL
            * GameConfig.HABITAT_CREATURE_CAPACITY_PER_LEVEL
    local lastX, lastZ = WorldLayout.penSlotXZ(maxCreatures)
    Expect.truthy(lastX > 0 and lastX < WorldLayout.PLOT_STUDS, "pen stays within plot width")
    Expect.truthy(lastZ > WorldLayout.PLOT_STUDS, "pen is outside the buildable plot")
    Expect.truthy(
        lastZ + WorldLayout.PEN_SPACING / 2 < WorldLayout.PLOT_STUDS + WorldLayout.PLOT_GAP_STUDS,
        "pen fits before the next plot row"
    )

    local slotX, slotZ = WorldLayout.penSlotXZ(WorldLayout.PEN_COLUMNS + 1)
    Expect.equal(slotX, WorldLayout.PEN_SPACING / 2, "pen wraps to a new row")
    Expect.equal(
        slotZ,
        WorldLayout.PLOT_STUDS + WorldLayout.PEN_EDGE_OFFSET + WorldLayout.PEN_SPACING,
        "second pen row"
    )

    local cellX, cellZ = WorldLayout.cellAt(9, 3.9)
    Expect.equal(cellX, 2, "cell x")
    Expect.equal(cellZ, 0, "cell z")
end

return run
