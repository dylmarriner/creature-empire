local GameConfig = require("../Config/GameConfig")

-- World-space layout shared by the server (authoritative rendering) and the client
-- (placement preview). Plots sit north (+Z) of the spawn; the Wilds lie south (-Z).
local PLOT_STUDS = GameConfig.PLOT_SIZE_CELLS * GameConfig.BUILD_GRID_SIZE
local PLOT_GAP_STUDS = 24
local PLOT_COLUMNS = 4
local PLOTS_START_Z = 60

local WorldLayout = {
    PLOT_STUDS = PLOT_STUDS,
    PLOT_BASE_TOP = 0.2,
    PLOT_COLUMNS = PLOT_COLUMNS,

    SPAWN_POSITION = { x = 0, y = 0, z = 0 },
    WILDS_CENTER = { x = 0, z = -300 },
    WILDS_RADIUS = 170,
    GROUND_SIZE = { x = 1400, z = 1400 },
}

-- Minimum-corner (x, z) of plot slot `index` (1-based). Slots fill rows of PLOT_COLUMNS.
function WorldLayout.plotCornerXZ(index: number): (number, number)
    local column = (index - 1) % PLOT_COLUMNS
    local row = (index - 1) // PLOT_COLUMNS
    local rowWidth = PLOT_COLUMNS * PLOT_STUDS + (PLOT_COLUMNS - 1) * PLOT_GAP_STUDS
    local x = -rowWidth / 2 + column * (PLOT_STUDS + PLOT_GAP_STUDS)
    local z = PLOTS_START_Z + row * (PLOT_STUDS + PLOT_GAP_STUDS)
    return x, z
end

-- Converts a plot-local world offset (studs from the plot corner) to the grid cell holding it.
function WorldLayout.cellAt(localX: number, localZ: number): (number, number)
    return math.floor(localX / GameConfig.BUILD_GRID_SIZE),
        math.floor(localZ / GameConfig.BUILD_GRID_SIZE)
end

return table.freeze(WorldLayout)
