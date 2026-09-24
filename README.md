# Creature Empire

Creature Empire is a Roblox-first multiplayer game combining empire-building automation with creature collection. Creatures are useful workers, not decorative inventory: players explore, obtain creatures, assign them to jobs, produce resources, build infrastructure, and unlock stronger production chains.

The repository is intentionally building **one complete game before a creator platform**. Breeding, trading, marketplace systems, guilds, deep combat, AI-assisted creation, and user-created experiences are later phases, not unfinished promises hiding in the first milestone.

## What is implemented

The first playable vertical slice (roadmap phases 1–5):

- **World**: a shared server world with a spawn, a plot district and the Wilds exploration zone (trees, rocks, wandering wild creatures), all built from code at server start.
- **Plots**: every player gets a 30×30-cell plot; buildings are persisted as plot-local grid cells and re-rendered from data.
- **Gathering**: server-owned ProximityPrompts on trees and rocks with per-player cooldowns and range checks.
- **Creatures**: six species, a one-time starter Rockhorn, server-rolled capture chances, habitat capacity, release, experience and levels.
- **Buildings**: eight structures with grid placement, rotation, overlap/bounds checks, per-type limits, upgrades to level 5 (Workbench-gated, coin + resource + energy costs) and removal with a partial refund.
- **Production**: recipe cycles driven by assigned workers' affinities and levels, processing inputs (Furnace), storage limits (Warehouses), deterministic claims that never lose fractional progress, and an 8-hour offline cap.
- **Economy**: canonical resource sell prices for coins; coins fund upgrades.
- **Progression**: a 19-step objective chain from first wood to a level-3 building, with coin rewards.
- **Persistence**: session-locked DataStore profiles with retries, lock takeover, autosave, save-on-leave and shutdown saves. Invalid or unreadable data is never overwritten with defaults.
- **Networking**: semantic RemoteEvents with strict payload schemas, per-player token-bucket rate limits and a transactional mutation pipeline.
- **UI**: code-built HUD (resources, objective tracker, toasts), build menu with a live placement preview (mouse, keyboard and touch), building, creature and market panels, and home/Wilds travel.

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for status and [`docs/OPERATIONS.md`](docs/OPERATIONS.md) for launch and live-operations steps.

## Toolchain

Install Rokit first, then from the repository root run:

```bash
rokit install
wally install
```

Pinned project tools:

- Rojo 7.7.0
- Wally 0.3.2
- Selene 0.31.0
- StyLua 2.5.2
- Lune 0.10.5
- luau-lsp 1.70.0

## Development

Live-sync source into Roblox Studio:

```bash
rojo serve
```

Build a place file:

```bash
rojo build default.project.json --output CreatureEmpire.rbxlx
```

Run the pure-domain, persistence and integration tests:

```bash
lune run tests/run
```

Run the static checks:

```bash
stylua --check src tests
selene src tests
./scripts/typecheck.sh
```

`scripts/typecheck.sh` type-checks all source against the Roblox API with luau-lsp. `src/server` and `src/client` are checked in strict mode.

Before treating a branch as valid, all five validation categories must pass: formatting, lint, type-check, tests, and Rojo build. CI runs the same checks on every push and pull request to `main`.

## Repository map

```text
src/shared/Config       tunable game constants
src/shared/Items        resource definitions and sell prices
src/shared/Creatures    species, ownership, capture, assignment, levels
src/shared/Buildings    building definitions, placement, upgrades, grid math
src/shared/Economy      inventory, currency, capacity, production, market
src/shared/World        world layout, gathering nodes
src/shared/Progression  objective chain
src/shared/Profiles     profile schema, migration, integrity repair
src/shared/Net          action names, payload schemas, rate limiter, remote names
src/shared/Gameplay     action handlers, transactional pipeline, client snapshot
src/server/Persistence  session-locked profile store and store adapters
src/server/Services     player data, actions, network, plots, world, logging
src/client/Controllers  state, action requests, HUD, build, panels
src/client/UI           theme, widgets, formatting
tests/                  Lune runner, specs, fixtures and the vertical-slice integration test
docs/                   game, architecture, economy, creature, data-model and operations docs
docs/superpowers/       approved design specifications and implementation plans
```

## Core rule

The client is untrusted. Currency, resource output, creature ownership, building placement, production rewards, and other valuable state are validated and mutated by the server. Client requests express intent; they do not dictate outcomes.

## Source of truth

The approved foundation design is:

`docs/superpowers/specs/2026-09-08-creature-empire-foundation-design.md`

The production loop and vertical slice implementation plan is:

`docs/superpowers/plans/2026-09-24-production-loop-and-vertical-slice.md`
