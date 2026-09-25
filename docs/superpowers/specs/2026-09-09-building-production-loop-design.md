# Building and Production Loop Design

> **Superseded.** This Phase 4 design was merged in PR #3 alongside a parallel implementation in PR #4. The two implemented the same rules with incompatible data shapes; PR #4's implementation (grid-cell placement, recipe-cycle production, five upgrade levels) was kept because the server, client and integration tests depend on it. See `docs/superpowers/plans/2026-09-24-production-loop-and-vertical-slice.md`. `InventoryDomain.applyTransaction` from this design remains in use.

## Status

Approved Phase 4 implementation design derived from the approved foundation specification and the user instruction to continue implementation after merging Phase 3.

## Goal

Deliver a pure, server-authoritative building and production domain that can place buildings on the player plot, pay canonical construction/upgrade costs, assign creatures atomically, calculate deterministic elapsed-time production, consume Furnace input, enforce the 8-hour offline cap, and complete the Rockhorn -> Mine -> Copper Ore -> Furnace -> Copper Bar chain.

## Scope

Phase 4 includes:

- grid-snapped plot placement,
- plot-bound and occupied-cell validation,
- generated building instance IDs,
- canonical construction costs,
- canonical production-level multipliers and upgrade costs,
- atomic two-sided creature assignment/unassignment,
- deterministic production preview and claim,
- worker-affinity aggregation,
- input-limited processing buildings,
- settlement before worker/rate changes,
- 8-hour offline elapsed-time clamp,
- integration tests for the Mine/Furnace chain.

Phase 4 does not add persistence infrastructure, exploration encounters, UI, tutorials, remotes, rate limiting, building models, creator systems, or a physical worker simulation. Those remain later runtime/playable-slice work.

## Existing Primitives Reused

The implementation must reuse rather than duplicate:

- `GameConfig.BUILD_GRID_SIZE = 4`,
- `GameConfig.OFFLINE_PRODUCTION_CAP_SECONDS = 8 * 60 * 60`,
- `GridMath.snapPosition`,
- `BuildingCostDomain.purchase`,
- `InventoryDomain` validated inventory mutation,
- `ProductionMath.clampElapsedSeconds`,
- `ProductionMath.calculateOutput`,
- `WorkAssignmentDomain.validate`,
- canonical `CreatureDefinitions` and `BuildingDefinitions`.

## Placement Model

The initial plot is a square ground-plane grid centered at the origin.

Add `GameConfig.PLOT_HALF_EXTENT = 64`. Valid snapped building origins satisfy:

```text
-64 <= x <= 64
z <= 64
z >= -64
y == 0
```

Placement uses one occupied grid origin per building in Phase 4. Building footprints are intentionally not introduced until Studio models and actual footprint requirements exist. This avoids speculative spatial metadata while still preventing identical-cell overlap.

A placement request supplies:

- canonical building definition ID,
- desired numeric position,
- quarter-turn rotation (`0`, `90`, `180`, `270`),
- server-owned generated ID callback,
- authoritative integer timestamp.

The domain snaps the position to the canonical 4-stud grid, validates bounds/occupancy/rotation/ID, verifies the player can pay the canonical definition cost, performs the cost, and only then creates the building record. All failure paths before purchase leave inventory/buildings unchanged.

New buildings start at level 1, no workers, and `lastClaimedAt = now`.

## Upgrade Model

Production building definitions gain canonical level data. Phase 4 supports three production levels:

```text
Level 1: 1.00x
Level 2: 1.25x
Level 3: 1.60x
```

The five production buildings use the same multiplier curve, while each definition owns its own canonical upgrade costs. Utility buildings remain non-upgradeable in Phase 4 because they do not yet have implemented level effects.

Upgrade costs:

- Mine: L2 = 40 Stone + 10 Copper Bars; L3 = 80 Stone + 30 Copper Bars.
- Lumber Mill: L2 = 40 Wood + 10 Copper Bars; L3 = 80 Wood + 30 Copper Bars.
- Farm: L2 = 30 Wood + 20 Food; L3 = 60 Wood + 50 Food.
- Furnace: L2 = 60 Stone + 15 Copper Bars; L3 = 120 Stone + 40 Copper Bars.
- Generator: L2 = 50 Stone + 20 Copper Bars; L3 = 100 Stone + 50 Copper Bars.

Before changing a production rate, the upgrade operation settles production at the old rate to the authoritative `now`. Insufficient upgrade resources are rejected before settlement so an unsuccessful upgrade request does not mutate the profile.

## Worker Assignment Mutation

`WorkAssignmentDomain.validate` remains the eligibility source of truth.

A new mutation domain performs the actual relationship update:

```text
assign:
1. validate request and timestamp,
2. validate assignment eligibility,
3. settle target-building production at the old worker state,
4. append creature ID to building.assignedCreatureIds,
5. set creature.assignedBuildingId.

unassign:
1. validate ownership and exact two-sided relationship,
2. settle target-building production at the old worker state,
3. remove creature ID from building.assignedCreatureIds,
4. clear creature.assignedBuildingId.
```

All validation occurs before settlement/mutation. Settlement is required so elapsed time is never retroactively calculated using a newly added/removed worker multiplier.

## Production Model

A production building is valid only when its canonical definition has:

- positive finite `baseRatePerMinute`,
- canonical output item,
- supported work type,
- valid current level multiplier,
- dense/unique/consistent assigned creature IDs,
- every assigned creature having a positive affinity for the building work type.

Worker multiplier is the sum of assigned workers' canonical work affinities. Zero workers means zero output.

Trait multiplier remains `1.0` in Phase 4 because trait effects are not yet specified.

Elapsed seconds are `now - building.lastClaimedAt`, rejected if negative, and clamped to `GameConfig.OFFLINE_PRODUCTION_CAP_SECONDS`.

Raw whole-unit output uses `ProductionMath.calculateOutput`.

For processing buildings such as Furnace:

```text
claimable output = min(raw output, floor(available input / inputPerOutput))
input consumed = claimable output * inputPerOutput
```

Input and output inventory changes are applied atomically. Production never accepts client-authored output quantities, timestamps, rates, affinities, multipliers, or costs.

`claim` returns `nothing_to_claim` without advancing `lastClaimedAt` when whole-unit output is zero, preserving sub-unit elapsed time.

A separate `settle` operation is used internally before worker/upgrade rate changes. It advances `lastClaimedAt` to `now` after a valid settlement even when output is zero, because old-rate elapsed time must not carry into the new state.

Processing uses inventory available at claim/settlement time. Phase 4 intentionally does not model per-building input buffers or historical inventory timestamps.

## Atomic Inventory Exchange

Extend `InventoryDomain` with a generic atomic transaction:

```luau
applyTransaction(profile, removals, additions) -> DomainResult<boolean>
```

It validates every item ID, positive whole quantity, existing balance, removal sufficiency, and resulting balances before mutating anything. This is used by Furnace claims so input removal cannot succeed if output addition would fail.

## Error Handling

Reuse existing errors where possible and add only:

- `duplicate_building_instance`,
- `invalid_generated_id` (already exists and is reused for building IDs),
- `max_level_reached`.

Use `invalid_placement` for off-plot, occupied-cell, bad rotation, and invalid snapped-ground placement.
Use `building_not_owned`, `creature_not_owned`, `incompatible_work`, `building_capacity_full`, `insufficient_resources`, `nothing_to_claim`, and `invalid_request` consistently with existing domains.

## Integration Chain

The deterministic Phase 4 regression flow is:

1. create profile at time 100,
2. seed 20 Wood and 80 Stone,
3. grant starter Rockhorn,
4. place Mine at time 100, consuming 20 Wood + 30 Stone,
5. assign Rockhorn at time 100,
6. at time 220 claim 15 Copper Ore,
7. place Furnace at time 220, consuming 50 Stone + 15 Copper Ore,
8. authorize/capture Embercub,
9. assign Embercub to Furnace at time 220,
10. at time 340 claim another 15 Copper Ore from Mine,
11. at time 340 claim 10 Copper Bars from Furnace, consuming 10 Copper Ore.

Expected remaining inventory after step 11 is 5 Copper Ore and 10 Copper Bars.

This flow proves construction cost authority, ownership, assignment, deterministic elapsed production, canonical affinities, processing input consumption, and two distinct production buildings without requiring a live Roblox session.

## Testing

Every behavior is developed red-green under the existing Lune test runner. The final branch gate remains:

```text
stylua --check src tests
selene src tests
lune run tests/run
rojo build default.project.json --output CreatureEmpire.rbxlx
```

Phase 4 is complete only when the integration chain and focused failure tests pass through all four CI stages.
