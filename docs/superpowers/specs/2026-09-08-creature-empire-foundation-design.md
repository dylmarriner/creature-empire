# Creature Empire Foundation Design

## Status

Approved concept, prepared for repository scaffolding and first implementation plan.

## Product Goal

Creature Empire is a Roblox-first multiplayer game that combines empire-building automation with creature collection, work assignment, exploration, progression, and later breeding, trading, combat, social play, and creator-made experiences.

The first commercial product is a complete Roblox game. The architecture must keep game rules and persisted state data-driven so the project can later support creator tools and, if justified by traction, a standalone implementation without redesigning the core domain model.

## Core Player Loop

1. Explore a shared or instanced world.
2. Gather resources and discover creatures.
3. Capture or tame creatures.
4. Assign creatures to useful jobs in the player's empire.
5. Produce resources through buildings and creature work affinities.
6. Build, upgrade, and automate the empire.
7. Unlock new regions and stronger production chains.
8. Discover creatures with better work, combat, trait, or genetic value.
9. Repeat with increasing specialization and social status.

The MVP succeeds only if obtaining a creature and assigning it to improve the empire feels rewarding without relying on trading, breeding, battle passes, or large content volume.

## First Playable Scope

The first playable vertical slice contains:

- one persistent player plot,
- one exploration zone,
- six creatures,
- six resource types,
- eight production or utility structures,
- manual resource gathering,
- creature capture,
- creature ownership,
- creature work assignment,
- production simulation,
- building placement and upgrades,
- inventory,
- currency,
- persistence,
- capped offline progression,
- basic UI,
- plot visiting after the solo loop is stable.

Initial creatures:

- Rockhorn: mining / tank / earth,
- Embercub: smelting / fire damage / fire,
- Mossling: farming / healing / nature,
- Voltfox: power generation / lightning / electric,
- Timberpaw: logging / physical damage / nature,
- Aquafin: fishing or water collection / water damage / water.

Initial resources:

- Wood,
- Stone,
- Copper Ore,
- Copper Bar,
- Food,
- Energy.

Initial structures:

- Mine,
- Lumber Mill,
- Farm,
- Furnace,
- Generator,
- Warehouse,
- Creature Habitat,
- Workbench.

Breeding, genetics, mutations, combat depth, trading, marketplace, guilds, seasons, AI creation, and user-created experiences are explicitly outside the first playable milestone.

## Repository Strategy

The repository is a Rojo-managed Roblox project. Source files live in Git and sync into Roblox Studio through Rojo.

The toolchain is pinned so local development and CI use the same versions. The initial tool set is:

- Rokit for toolchain management,
- Rojo for filesystem-to-Studio synchronization and place builds,
- Wally for package management,
- Selene for Luau linting,
- StyLua for formatting,
- Jest Roblox for unit tests,
- GitHub Actions for automated validation.

No framework such as Knit is required for the initial scaffold. The project will use small explicit services and controllers first. A framework may be introduced later only if repeated boilerplate proves it earns its complexity.

## Repository Layout

```text
creature-empire/
├── README.md
├── .gitignore
├── default.project.json
├── rokit.toml
├── wally.toml
├── selene.toml
├── stylua.toml
├── .github/
│   └── workflows/
│       └── ci.yml
├── docs/
│   ├── GAME_DESIGN.md
│   ├── ARCHITECTURE.md
│   ├── ROADMAP.md
│   ├── ECONOMY.md
│   ├── CREATURE_SYSTEM.md
│   ├── DATA_MODEL.md
│   └── superpowers/
│       ├── specs/
│       └── plans/
├── src/
│   ├── shared/
│   │   ├── Config/
│   │   ├── Types/
│   │   ├── Creatures/
│   │   ├── Buildings/
│   │   ├── Items/
│   │   ├── Economy/
│   │   └── Net/
│   ├── server/
│   │   ├── Services/
│   │   │   ├── PlayerDataService.luau
│   │   │   ├── InventoryService.luau
│   │   │   ├── CreatureService.luau
│   │   │   ├── BuildingService.luau
│   │   │   ├── ProductionService.luau
│   │   │   └── EconomyService.luau
│   │   └── init.server.luau
│   └── client/
│       ├── Controllers/
│       │   ├── InteractionController.luau
│       │   ├── BuildController.luau
│       │   ├── CreatureController.luau
│       │   └── UIController.luau
│       └── init.client.luau
└── tests/
    ├── shared/
    └── server/
```

Directories that would otherwise be empty are created only when their first real file is added. No placeholder modules, TODO files, fake implementations, or dead code are added solely to make the tree look populated.

## Architectural Rules

### 1. Server authority

The server owns all state that has gameplay or economic value.

Clients may request an action such as assigning a creature to a mine, placing a building, claiming offline production, or purchasing an upgrade. The server validates ownership, prerequisites, bounds, cooldowns, available resources, and resulting state before accepting the action.

The client never sends authoritative values such as currency balances, output amounts, creature stats, prices, or production multipliers.

### 2. Data-driven domain definitions

Static game definitions are separated from player-owned instances.

Examples:

- `CreatureSpecies` defines a species such as Rockhorn.
- `CreatureInstance` defines one owned Rockhorn with its own level, traits, genetics, mutation, and assignment.
- `BuildingDefinition` defines the Mine type.
- `BuildingInstance` defines one player's placed Mine with position, level, state, and assigned workers.

Production recipes, work affinities, building costs, upgrade tables, and item definitions are declarative shared data rather than scattered conditionals.

### 3. Stable identifiers

Persisted entities use stable string identifiers rather than display names or Roblox Instance references.

Examples:

- `creature_rockhorn`,
- `building_mine`,
- `item_copper_ore`,
- `recipe_copper_bar`.

Owned instances use generated unique IDs.

### 4. Persistence stores data, not Roblox instances

Player plots are saved as structured records that describe placed objects. They are reconstructed when needed.

Persisted data must never depend on Studio object references, transient Instance IDs, or client-only state.

### 5. Simulation over physical bookkeeping

Production is calculated mathematically from building definitions, assigned workers, upgrades, and elapsed time. Worker animation is presentation only.

The server does not require a creature to physically walk to every ore node and simulate every pickaxe strike in order to produce resources.

### 6. Explicit boundaries

Each service owns one domain:

- PlayerDataService: load, migrate, validate, save, and session ownership of player data.
- InventoryService: item balances and validated inventory mutations.
- CreatureService: creature ownership, capture, state, and assignment eligibility.
- BuildingService: plot placement, removal, upgrades, ownership, and spatial validation.
- ProductionService: production calculations, worker contribution, claim logic, and offline progression.
- EconomyService: currency costs, rewards, and transaction-level checks.

Services expose narrow methods rather than directly mutating one another's internal tables.

## Initial Data Model

The saved profile begins with a schema version and a compact domain model.

```luau
export type PlayerProfile = {
    schemaVersion: number,
    currencies: {
        coins: number,
        gems: number,
    },
    inventory: { [string]: number },
    creatures: { [string]: CreatureInstance },
    buildings: { [string]: BuildingInstance },
    unlocks: { [string]: boolean },
    lastSeenAt: number,
}
```

The initial creature instance shape is:

```luau
export type CreatureInstance = {
    id: string,
    speciesId: string,
    level: number,
    experience: number,
    traits: { string },
    mutationId: string?,
    assignedBuildingId: string?,
}
```

Genetics are deliberately omitted from the first persistence schema until breeding is implemented. This prevents speculative schema complexity while preserving a clean migration path.

The initial building instance shape is:

```luau
export type BuildingInstance = {
    id: string,
    definitionId: string,
    level: number,
    position: { x: number, y: number, z: number },
    rotation: number,
    assignedCreatureIds: { string },
    lastClaimedAt: number,
}
```

## Networking Model

Network endpoints are declared centrally under `src/shared/Net` and mapped into `ReplicatedStorage` by Rojo.

Requests are semantic actions rather than generic mutation channels. Examples:

- AssignCreature,
- PlaceBuilding,
- UpgradeBuilding,
- ClaimProduction,
- CaptureCreature.

Each request has a server-side validator and rate limit appropriate to the action.

The network layer must reject malformed payloads, unknown identifiers, stale ownership assumptions, impossible positions, negative quantities, NaN or infinity numeric values, and replay-sensitive requests where applicable.

## Production Model

Production is based on elapsed time rather than frame loops.

A production result is conceptually:

```text
output = baseRate
       × buildingLevelMultiplier
       × workerAffinityMultiplier
       × traitMultiplier
       × elapsedMinutes
```

The server clamps elapsed time for offline production. The initial maximum offline window is 8 hours.

Claims are calculated from authoritative server timestamps and persisted `lastClaimedAt` values.

## Error Handling

Expected gameplay failures return typed domain results rather than throwing uncontrolled errors.

Examples:

- insufficient resources,
- creature already assigned,
- building capacity full,
- invalid placement,
- item not unlocked,
- production already claimed.

Unexpected infrastructure failures are logged with enough context to diagnose the fault while avoiding sensitive player data in logs.

Persistence failures must not silently overwrite a known-good profile with defaults.

## Security and Exploit Resistance

The project assumes every client can be modified by an attacker.

Required protections include:

- server-authoritative balances,
- server-authoritative creature ownership,
- server-authoritative building placement,
- validation of all RemoteEvent and RemoteFunction inputs,
- rate limits on abuse-prone requests,
- transaction-style mutations for economy operations,
- no secret or privileged values shipped to the client,
- no client-calculated rewards accepted by the server.

## Testing Strategy

Pure domain logic is written so it can be tested without a live player session wherever possible.

Initial unit-test targets are:

- resource cost validation,
- inventory add/remove behavior,
- production-rate calculation,
- offline-time clamping,
- creature work-affinity calculation,
- building placement-grid normalization,
- schema validation and migration behavior,
- malformed network input rejection.

Integration tests cover the smallest complete server flows, beginning with:

1. create/load profile,
2. grant starter creature through a test fixture,
3. place a Mine,
4. assign Rockhorn,
5. advance a deterministic clock,
6. claim production,
7. verify inventory and timestamps,
8. save and reload the profile.

CI must fail on formatting, lint, test, or Rojo build errors.

## Initial Documentation Set

The scaffold creates focused documentation rather than one enormous design dump:

- `README.md`: setup, commands, project summary, and repository navigation.
- `docs/GAME_DESIGN.md`: player experience, loop, content pillars, and MVP boundaries.
- `docs/ARCHITECTURE.md`: runtime boundaries, authority model, networking, and persistence.
- `docs/ROADMAP.md`: ordered implementation phases and exit criteria.
- `docs/ECONOMY.md`: currencies, resource sinks/sources, production rules, and monetization principles.
- `docs/CREATURE_SYSTEM.md`: species model, work roles, capture, progression, and future breeding constraints.
- `docs/DATA_MODEL.md`: stable IDs, persisted schemas, migrations, and ownership rules.

## Development Phases

### Phase 1: Repository foundation

Deliver a reproducible Rojo project with pinned tools, package management, linting, formatting, tests, CI, documentation, domain types, and server/client bootstraps.

### Phase 2: Economy primitives

Deliver inventory, currency, item definitions, resource costs, and transaction-safe mutations.

### Phase 3: Creature ownership

Deliver species definitions, owned creature instances, starter/capture flow, and assignment eligibility.

### Phase 4: Building and production loop

Deliver plot placement, Mine/Furnace/Farm-style definitions, worker assignment, deterministic production, claims, and offline progression.

### Phase 5: Playable vertical slice

Deliver the first exploration zone, six creatures, eight structures, UI, tutorial flow, saving, and a complete progression path.

### Phase 6: Social validation

Add plot visiting and only the social features proven necessary by playtesting.

Later systems such as breeding, mutations, trading, marketplace, combat expansion, guilds, seasons, creator tools, AI-assisted creation, and published player experiences receive separate specifications and implementation plans.

## Monetization Constraint

The MVP is designed to be enjoyable without purchases.

Early monetization should favor cosmetics, account convenience, private/social features, and clearly bounded premium benefits. Core creature usefulness, fair progression, and competitive integrity must not depend on purchasing extreme production multipliers.

## Success Criteria for the Foundation Scaffold

The repository foundation is complete when:

- a fresh clone can install the pinned toolchain,
- dependencies install reproducibly,
- `rojo build` produces a valid Roblox place file,
- formatting and lint checks pass,
- the test runner executes at least one meaningful domain test,
- CI runs the same checks on pushes and pull requests,
- server and client bootstraps load without runtime errors,
- core domain types and IDs have one canonical definition location,
- the architecture and MVP boundaries are documented,
- no placeholder gameplay implementation is presented as finished functionality.
