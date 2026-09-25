# Roadmap

## Phase 1: Repository foundation

**Status: Complete**

Pinned toolchain, Wally, formatting/lint checks, pure-domain tests, Rojo build, canonical IDs/types/definitions, server/client bootstraps, documented architecture and MVP boundaries.

## Phase 2: Economy primitives

**Status: Complete**

Inventory balances, currency balances, cost validation, atomic resource removal/addition, starter profile construction, profile schema validation, and migration tests.

## Phase 3: Creature ownership

**Status: Complete**

Owned creature instances, generated IDs, one-time starter Rockhorn grant, capture ownership handling, capture eligibility gating, and work-assignment eligibility validation.

## Phase 4: Building and production loop

**Status: Complete**

Implemented plot grid placement with rotation, bounds, overlap and per-type limits; building costs, Workbench-gated upgrades and removal refunds; two-sided worker assignment and unassignment; recipe-cycle production with worker affinity and level multipliers; processing inputs; storage limits; fractional-progress-preserving claims; and the 8-hour offline cap.

Exit criterion met: `tests/integration/VerticalSlice.spec.luau` runs Rockhorn → Mine → Copper Ore → Furnace → Copper Bar server-side with a deterministic clock, then saves, reloads on another server and claims capped offline production.

## Phase 5: Playable vertical slice

**Status: Complete, pending a Studio playtest pass**

Implemented the Wilds exploration zone, gathering interactions, the six creatures with capture, the eight structures, habitat and storage capacity, creature levels, the market, a 19-step objective chain, session-locked persistence, a rate-limited validated network layer, plot rendering, and the HUD, build, building, creature and market UI.

Exit criterion met in simulation: the integration test plays a new profile from manual gathering through every objective to a level-3 building using only game actions. It must still be confirmed by hand in Studio and on a published test place; see the playtest checklist in [`OPERATIONS.md`](OPERATIONS.md).

## Phase 6: Social validation

**Status: Not started**

All players share one server world, so plots can already be visited on foot. Explicit plot visiting (teleport to a friend's plot, visitor labels) and any other social systems are added only when playtesting justifies them.

## Later specifications

Breeding/genetics, mutations, combat expansion, trading, marketplace, guilds, seasons, monetization, creator tools, AI-assisted creation, and UGC publishing each require their own design and implementation plan.
