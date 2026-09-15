# Creature Empire

Creature Empire is a Roblox-first multiplayer game combining empire-building automation with creature collection. Creatures are useful workers, not decorative inventory: players explore, obtain creatures, assign them to jobs, produce resources, build infrastructure, and unlock stronger production chains.

The repository is intentionally building **one complete game before a creator platform**. Breeding, trading, marketplace systems, guilds, deep combat, AI-assisted creation, and user-created experiences are later phases, not unfinished promises hiding in the first milestone.

## Current foundation

The repository currently contains:

- a Rojo-managed Roblox project,
- a Rokit-pinned development toolchain,
- Wally package management,
- six canonical resource IDs,
- six initial creature species definitions,
- eight initial building definitions,
- versioned profile construction, validation, and migration,
- validated inventory and currency mutation domains,
- atomic inventory exchange and canonical multi-resource costs,
- generated-ID creature ownership,
- one-time starter Rockhorn grants,
- eligibility-gated creature capture ownership,
- authoritative 4-stud grid building placement inside +/-64-stud plot bounds,
- generated building instance IDs with collision rejection,
- atomic two-sided creature/building work assignment,
- deterministic elapsed-time production preview, claim, and settlement,
- summed canonical creature work affinities,
- Furnace Copper Ore input consumption and Copper Bar output,
- three canonical production-building levels and upgrade costs,
- an 8-hour offline-production cap,
- semantic network action names,
- server/client bootstraps,
- Lune pure-domain tests including the Phase 4 Mine/Furnace acceptance chain,
- Jest Roblox test specs for in-engine expansion,
- formatting, linting, test, and Rojo-build CI.

The Phase 4 production implementation is in final verification. Persistence, exploration encounters, Roblox-facing service/remote integration, UI, tutorial flow, and the playable world are subsequent implementation phases.

## Current production chain

The first deterministic automation chain is:

```text
Rockhorn -> Mine -> Copper Ore -> Furnace + Embercub -> Copper Bar
```

Valuable state remains server-owned. Construction prices, generated IDs, work compatibility, worker capacity, production rates, creature affinities, upgrade multipliers/costs, elapsed timestamps, processing inputs, and output quantities come from canonical server-side definitions and domains.

Production rate changes settle the old state before assignment/unassignment or an upgrade is applied, so new workers and new levels cannot retroactively increase earlier elapsed production.

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

Jest Roblox is installed as a Wally development dependency.

## Development

Live-sync source into Roblox Studio:

```bash
rojo serve
```

Build a place file:

```bash
rojo build default.project.json --output CreatureEmpire.rbxlx
```

Run the pure-domain tests:

```bash
lune run tests/run
```

Run the static checks:

```bash
stylua --check src tests
selene src tests
```

Before treating a branch as valid, all four validation categories must pass on the exact branch head: formatting, lint, pure-domain tests, and Rojo build.

## Repository map

```text
src/shared/       canonical definitions, types, pure domain logic, network contract
src/server/       server-authoritative runtime bootstrap and future services
src/client/       presentation/input bootstrap and future controllers
tests/            pure-domain runner, integration acceptance specs, Roblox Jest specs
docs/             game, architecture, economy, creature and data-model documentation
docs/superpowers/ approved design specifications and implementation plans
```

## Core rule

The client is untrusted. Currency, resource output, creature ownership, building placement, production rewards, upgrades, and other valuable state are validated and mutated by the server. Client requests express intent; they do not dictate outcomes.

## Source of truth

The approved foundation design is:

`docs/superpowers/specs/2026-09-08-creature-empire-foundation-design.md`

Phase-specific designs and implementation plans live under:

`docs/superpowers/`
