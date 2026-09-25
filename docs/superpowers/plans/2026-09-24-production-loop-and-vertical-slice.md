# Production Loop and Vertical Slice Implementation Plan

**Goal:** complete roadmap phases 4 and 5 — a server-authoritative building and production loop and a playable vertical slice with persistence, networking, world and UI.

**Status:** implemented.

## Decisions

- **Pure domains, one mutation path.** Game rules are pure modules in `src/shared` so they run under Lune on CI. Roblox services never mutate profiles directly; `ActionService` runs every change through `Gameplay/ActionPipeline` (copy → mutate → objectives → schema validation → commit).
- **Recipe cycles.** Building definitions replaced `baseRatePerMinute`/`outputItemId`/`inputItemId` with `cyclesPerMinute`, `inputs` and `outputs` maps. Output is still computed by `ProductionMath.calculateOutput`, with the worker multiplier summing each worker's affinity and level bonus.
- **Claims never lose or invent progress.** The claim clock advances only by the time whole cycles took; limited or idle buildings reset instead of banking time; offline time is capped at 8 hours.
- **Utility buildings have mechanical roles.** Warehouse raises storage, Creature Habitat raises creature capacity, Workbench unlocks upgrades.
- **World interactions are server prompts.** Gathering and capture use server-owned ProximityPrompts with server range checks, cooldowns and capture rolls, so `CaptureCreature` was removed from the remote contract.
- **Session-locked persistence built in-house.** `ProfileStore` implements locking, takeover and refusal of invalid data over an abstract store so it is fully testable; no framework dependency was added.
- **Plot-local grid cells.** Building positions persist as plot-local cells, making plot slot allocation per server irrelevant to saved data.
- **Objective chain in `unlocks`.** Progression markers reuse the existing `unlocks` map, so schema version 1 is unchanged.
- **Tests on Lune; types via luau-lsp.** The unrunnable Jest Roblox specs and dev-dependency were removed. Engine-facing code is type-checked in strict mode against the Roblox API in CI instead.
- **Aquafin irrigates farms** (farming 1.1) until water structures exist, so all six species are useful.

## Delivered

- Domains: `PlacementDomain`, `UpgradeDomain`, `ProductionDomain`, `CapacityDomain`, `MarketDomain`, `GatheringDomain`, `ObjectiveDomain`, `CreatureProgression`, `ProfileIntegrity`, assignment/unassignment and release mutations.
- Contracts: `ActionSchemas` (payload validation, rate limits, scopes), `RateLimiter`, `RemoteNames`, `GameActions`, `Snapshot`, `WorldLayout`.
- Server: `PlayerDataService`, `ActionService`, `NetworkService`, `PlotService`, `WorldService`, `Logger`, `ProfileStore`, `DataStoreAdapter`, `MemoryStore`.
- Client: state, action client, HUD, toasts, build menu and placement, building/creature/market panels, travel.
- Tests: 20 Lune specs including `integration/VerticalSlice`, which runs the Phase 4 chain with save/reload and plays a new profile through every objective.
- Tooling: `scripts/typecheck.sh`, luau-lsp pinned in Rokit, CI type-check step.

## Verification

- `stylua --check src tests`, `selene src tests`, `./scripts/typecheck.sh`, `lune run tests/run`, `rojo build` all pass.
- Remaining manual gate: the Studio/test-experience playtest checklist in `docs/OPERATIONS.md`.

## Reconciliation with PR #3

PR #3 (`feature/building-production-loop`) implemented Phase 4 in parallel as pure domains (`BuildingPlacementDomain`, `BuildingUpgradeDomain`, `WorkAssignmentMutationDomain`, and its own `ProductionDomain`) with stud-based placement around a centred plot, three upgrade levels and per-definition upgrade cost tables. When both were merged the implementations conflicted directly. This plan's implementation was kept because every runtime service, the client and the integration tests are built on it. From PR #3 the atomic `InventoryDomain.applyTransaction` (with its spec) and the added error codes were kept; its design and plan documents remain for history, marked superseded.
