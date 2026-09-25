local GameConfig = {
    SCHEMA_VERSION = 1,
    OFFLINE_PRODUCTION_CAP_SECONDS = 8 * 60 * 60,
    BUILD_GRID_SIZE = 4,
    INITIAL_RESOURCE_COUNT = 6,
    INITIAL_CREATURE_COUNT = 6,
    INITIAL_BUILDING_COUNT = 8,

    -- Plot layout. Buildings are persisted in plot-local grid cells.
    PLOT_SIZE_CELLS = 30,
    VALID_ROTATIONS = table.freeze({ 0, 90, 180, 270 }),

    -- Storage and creature capacity.
    BASE_STORAGE_CAPACITY = 200,
    WAREHOUSE_STORAGE_PER_LEVEL = 300,
    BASE_CREATURE_CAPACITY = 4,
    HABITAT_CREATURE_CAPACITY_PER_LEVEL = 4,

    -- Building progression.
    MAX_BUILDING_LEVEL = 5,
    BUILDING_LEVEL_OUTPUT_BONUS = 0.5,
    UPGRADE_ITEM_COST_GROWTH = 1.6,
    UPGRADE_COIN_COST_BASE = 40,
    UPGRADE_ENERGY_COST_PER_LEVEL = 10,
    UPGRADE_ENERGY_FROM_LEVEL = 3,
    REMOVE_REFUND_RATIO = 0.5,

    -- Creature progression.
    MAX_CREATURE_LEVEL = 10,
    CREATURE_LEVEL_OUTPUT_BONUS = 0.05,
    CREATURE_EXPERIENCE_PER_LEVEL = 50,

    -- Market.
    MAX_SELL_QUANTITY = 100000,
}

return table.freeze(GameConfig)
