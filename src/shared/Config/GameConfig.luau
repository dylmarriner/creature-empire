local GameConfig = {
    SCHEMA_VERSION = 2,
    OFFLINE_PRODUCTION_CAP_SECONDS = 8 * 60 * 60,
    BUILD_GRID_SIZE = 4,
    INITIAL_RESOURCE_COUNT = 6,
    WILD_SPECIES_COUNT = 6,
    HYBRID_SPECIES_COUNT = 15,
    INITIAL_BUILDING_COUNT = 9,

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

    -- Genetics. Every creature carries three genes in [GENE_MIN, GENE_MAX]. Creatures that
    -- predate breeding (and wild or starter creatures) use the neutral value.
    GENE_MIN = 0,
    GENE_MAX = 31,
    NEUTRAL_GENE = 16,
    -- A worker's output changes by this much per vigor point above or below neutral, so a
    -- neutral creature is exactly as productive as before genes existed.
    VIGOR_OUTPUT_PER_POINT = 0.005,

    -- Breeding. Costs scale with the older parent's generation so deep lineages are not free.
    BREEDING_MIN_PARENT_LEVEL = 3,
    BREEDING_COOLDOWN_SECONDS = 30 * 60,
    BREEDING_COIN_COST_BASE = 100,
    BREEDING_FOOD_COST_BASE = 10,
    BREEDING_MAX_GENERATION = 10,
    BREEDING_HATCH_BASE_SECONDS = 5 * 60,
    BREEDING_HATCH_PER_GENERATION_SECONDS = 5 * 60,
    BREEDING_HATCH_MAX_SECONDS = 60 * 60,
    BREEDING_GENE_DRIFT = 2,
    BREEDING_HYBRID_CHANCE = 0.4,
    BREEDING_MUTATION_CHANCE = 0.03,
    BREEDING_MAX_SLOTS = 5,

    -- Market.
    MAX_SELL_QUANTITY = 100000,
}

return table.freeze(GameConfig)
