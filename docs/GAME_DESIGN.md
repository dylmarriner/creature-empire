# Game Design

## Product fantasy

Build an expanding empire powered by creatures that are individually useful. Exploration discovers new workers and opportunities; the empire turns those discoveries into production, progression, and visible status.

## Core loop

1. Explore.
2. Gather resources and discover creatures.
3. Capture or tame useful creatures.
4. Assign creatures to jobs.
5. Produce resources.
6. Build and upgrade infrastructure.
7. Unlock stronger regions and production chains.
8. Repeat with better creatures and greater specialization.

The key test is simple: obtaining a creature and assigning it to improve the empire must feel satisfying before breeding, trading, rarity spectacle, or monetization are added.

## First playable content

### Resources

- `item_wood`
- `item_stone`
- `item_copper_ore`
- `item_copper_bar`
- `item_food`
- `item_energy`

### Creatures

- Rockhorn (`creature_rockhorn`): mining, earth.
- Embercub (`creature_embercub`): smelting, fire.
- Mossling (`creature_mossling`): farming, nature.
- Voltfox (`creature_voltfox`): power generation, electric.
- Timberpaw (`creature_timberpaw`): logging, nature.
- Aquafin (`creature_aquafin`): water work, water.

### Structures

- Mine (`building_mine`)
- Lumber Mill (`building_lumber_mill`)
- Farm (`building_farm`)
- Furnace (`building_furnace`)
- Generator (`building_generator`)
- Warehouse (`building_warehouse`)
- Creature Habitat (`building_creature_habitat`)
- Workbench (`building_workbench`)

## MVP boundaries

The first playable milestone includes a persistent plot, one exploration zone, manual gathering, creature ownership/capture, work assignment, production, building, upgrades, inventory, currency, saving, capped offline progression, and basic UI.

The following are intentionally later systems: breeding/genetics, mutations, deep combat, trading, marketplace, guilds, seasons, creator tools, AI-assisted creation, and published player experiences.

## Design principles

- Creatures must provide gameplay value, not merely rarity labels.
- Automation should replace repetition gradually rather than remove play immediately.
- Exploration must unlock meaningful production options.
- Player empires should become visually and mechanically distinct over time.
- Social comparison is useful; forced competitive spending is not.
- Progression must work without purchases.
