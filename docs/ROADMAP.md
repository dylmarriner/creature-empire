# Roadmap

## Phase 1: Repository foundation

Exit criteria:

- pinned toolchain installs,
- Wally dependencies install,
- formatting/lint checks pass,
- pure-domain tests pass,
- Rojo place builds,
- canonical IDs/types/definitions exist,
- server/client bootstraps load,
- architecture and MVP boundaries are documented.

## Phase 2: Economy primitives

Implement inventory balances, currency balances, cost validation, atomic resource removal/addition, starter profile construction, profile schema validation, and migration tests.

Exit when resource transactions cannot create negative balances and all mutation APIs return explicit domain results.

## Phase 3: Creature ownership

Implement owned creature instances, generated IDs, starter creature grant, capture eligibility, capture result handling, and work-assignment validation.

Exit when a server-owned profile can gain a Rockhorn and reject invalid or duplicate ownership mutations.

## Phase 4: Building and production loop

Implement plot grid placement, building costs/upgrades, worker assignment, deterministic output calculation, claims, input consumption for processing buildings, and the 8-hour offline cap.

Exit when the complete Rockhorn -> Mine -> Copper Ore -> Furnace -> Copper Bar chain works server-authoritatively.

## Phase 5: Playable vertical slice

Implement the first exploration zone, gathering interactions, the six initial creatures, eight structures, UI, tutorial flow, persistence, and one complete progression path.

Exit when a new player can progress from manual gathering to a functioning creature-powered automated empire without developer intervention.

## Phase 6: Social validation

Add plot visiting and only the social systems justified by playtesting.

## Later specifications

Breeding/genetics, mutations, combat expansion, trading, marketplace, guilds, seasons, monetization expansion, creator tools, AI-assisted creation, and UGC publishing each require their own design and implementation plan.
