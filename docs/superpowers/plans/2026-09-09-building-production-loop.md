# Building and Production Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Phase 4 so a server-owned profile can place a Mine and Furnace, assign Rockhorn/Embercub atomically, produce and claim Copper Ore/Copper Bars deterministically, consume Furnace input, upgrade production buildings, and enforce the 8-hour offline cap.

**Architecture:** Keep the implementation as pure Luau domains under `src/shared` so all valuable state transitions remain deterministic and Lune-testable. Reuse existing GridMath, BuildingCostDomain, WorkAssignmentDomain, InventoryDomain, ProductionMath, and canonical definitions. Settlement happens before any worker/rate change so elapsed production is never retroactively calculated with new state.

**Tech Stack:** Luau, Lune 0.10.5, Rojo 7.7.0, Selene 0.31.0, StyLua 2.5.2, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-09-building-production-loop-design.md`

## Global Constraints

- Server authority owns all building IDs, timestamps, costs, rates, affinities, multipliers, output quantities, and resulting state.
- Reuse `GameConfig.BUILD_GRID_SIZE = 4` and `OFFLINE_PRODUCTION_CAP_SECONDS = 8 * 60 * 60`.
- Add `GameConfig.PLOT_HALF_EXTENT = 64`.
- No physical worker simulation, persistence infrastructure, networking handlers, UI, exploration, or input-buffer subsystem in Phase 4.
- Every expected gameplay failure returns a typed domain result.
- Every task is developed RED -> GREEN and must pass StyLua, Selene, Lune, and Rojo build before Phase 4 is marked complete.

---

### Task 1: Atomic inventory transaction and canonical production upgrade data

**Files:**
- Modify: `src/shared/Economy/InventoryDomain.luau`
- Modify: `src/shared/Buildings/BuildingDefinitions.luau`
- Modify: `src/shared/Config/GameConfig.luau`
- Modify: `src/shared/Types/DomainTypes.luau`
- Create: `tests/economy/InventoryTransactionDomain.spec.luau`
- Modify: `tests/run.luau`

**Interfaces:**
- Produces `InventoryDomain.applyTransaction(profile, removals, additions) -> DomainResult<boolean>`.
- Adds canonical `levelMultipliers` and `upgradeCosts` to production definitions.
- Adds `GameConfig.PLOT_HALF_EXTENT = 64`.
- Adds `duplicate_building_instance` and `max_level_reached` domain errors.

- [ ] **Step 1: Write failing atomic transaction tests**

Cover:

```text
remove 10 Copper Ore + add 10 Copper Bars succeeds atomically
insufficient removal rejects with no inventory mutation
unknown item in additions rejects with no removal
invalid existing output balance rejects with no removal
same item appearing in removals and additions resolves from the original balance atomically
```

- [ ] **Step 2: Register the spec and confirm RED**

Add the spec to `tests/run.luau`. Expected failure: `InventoryDomain.applyTransaction` is nil/missing.

- [ ] **Step 3: Implement `applyTransaction`**

Rules:

```text
profile.inventory must be a table
removals/additions must be tables
all keys must be canonical item IDs
all quantities must be positive finite integers
all current balances must be finite non-negative integers
compute every final balance in memory before mutation
reject insufficient removals before mutation
reject invalid/overflow/non-integer final balances before mutation
write all final balances only after complete validation
zero final balances are removed from the inventory table
```

- [ ] **Step 4: Add Phase 4 canonical data**

`GameConfig`:

```luau
PLOT_HALF_EXTENT = 64
```

Production building multiplier curve:

```luau
levelMultipliers = { 1.0, 1.25, 1.6 }
```

Upgrade costs:

```text
Mine L2 {stone=40, copper_bar=10}; L3 {stone=80, copper_bar=30}
Lumber Mill L2 {wood=40, copper_bar=10}; L3 {wood=80, copper_bar=30}
Farm L2 {wood=30, food=20}; L3 {wood=60, food=50}
Furnace L2 {stone=60, copper_bar=15}; L3 {stone=120, copper_bar=40}
Generator L2 {stone=50, copper_bar=20}; L3 {stone=100, copper_bar=50}
```

Utilities receive no `levelMultipliers`/`upgradeCosts` in Phase 4.

- [ ] **Step 5: Extend error-code type**

Add:

```luau
| "duplicate_building_instance"
| "max_level_reached"
```

- [ ] **Step 6: Run full CI and require GREEN**

- [ ] **Step 7: Commit**

```text
feat: add production transaction primitives
```

---

### Task 2: Building placement domain

**Files:**
- Create: `src/shared/Buildings/BuildingPlacementDomain.luau`
- Create: `tests/buildings/BuildingPlacementDomain.spec.luau`
- Modify: `tests/run.luau`

**Interfaces:**
- Consumes `BuildingDefinitions.ById`, `BuildingCostDomain.purchase`, `GridMath.snapPosition`, `GameConfig.BUILD_GRID_SIZE`, `GameConfig.PLOT_HALF_EXTENT`.
- Produces `BuildingPlacementDomain.place(profile, definitionId, desiredPosition, rotation, generateId, now) -> DomainResult<BuildingInstance>`.

- [ ] **Step 1: Write failing placement tests**

Cover:

```text
valid Mine placement snaps x/z to 4-stud grid, costs resources, creates level-1 instance
new building starts with no workers and lastClaimedAt=now
unknown definition rejects without cost
bad generated ID rejects without cost
collision with existing instance ID rejects as duplicate_building_instance without cost
off-plot snapped position rejects as invalid_placement without cost
occupied snapped grid origin rejects as invalid_placement without cost
non-ground y rejects as invalid_placement
rotation outside 0/90/180/270 rejects as invalid_placement
insufficient construction resources rejects without building mutation
```

- [ ] **Step 2: Register spec and confirm RED for missing module**

- [ ] **Step 3: Implement placement validation**

Validation order:

1. profile/building table, canonical definition, numeric finite position, valid rotation, finite non-negative integer `now`, generator function,
2. snap desired position with `GridMath.snapPosition`,
3. require snapped `y == 0`, x/z within inclusive ±64,
4. reject any existing building at same snapped x/y/z,
5. invoke generator and require non-empty string,
6. reject generated ID collision,
7. call `BuildingCostDomain.purchase`,
8. create building record:

```luau
{
    id = generatedId,
    definitionId = definitionId,
    level = 1,
    position = snappedPosition,
    rotation = rotation,
    assignedCreatureIds = {},
    lastClaimedAt = now,
}
```

No failure after purchase may remain possible.

- [ ] **Step 4: Run full CI and require GREEN**

- [ ] **Step 5: Commit**

```text
feat: add building placement domain
```

---

### Task 3: Deterministic production claim and settlement

**Files:**
- Create: `src/shared/Economy/ProductionDomain.luau`
- Create: `tests/economy/ProductionDomain.spec.luau`
- Modify: `tests/run.luau`

**Interfaces:**
- Consumes `ProductionMath`, `InventoryDomain.applyTransaction`, `BuildingDefinitions`, `CreatureDefinitions`, `GameConfig.OFFLINE_PRODUCTION_CAP_SECONDS`.
- Produces:
  - `ProductionDomain.preview(profile, buildingInstanceId, now) -> DomainResult<ProductionPreview>`
  - `ProductionDomain.claim(profile, buildingInstanceId, now) -> DomainResult<ProductionClaim>`
  - `ProductionDomain.settle(profile, buildingInstanceId, now) -> DomainResult<ProductionClaim>`

Preview/claim result shape:

```luau
{
    outputItemId = string,
    outputQuantity = number,
    inputItemId = string?,
    inputQuantity = number,
    elapsedSeconds = number,
    clampedElapsedSeconds = number,
}
```

- [ ] **Step 1: Write failing production tests**

Cover:

```text
Mine + one Rockhorn + 120 seconds => 15 Copper Ore
Mine + two Rockhorns => affinity sum drives output
zero workers => nothing_to_claim
negative clock delta => invalid_request
8+ hours elapsed clamps to exactly 8 hours
level 2 Mine uses 1.25 building multiplier
Furnace + Embercub + 120 sec + 50 ore => 10 bars / consumes 10 ore
Furnace output is input-limited when available ore is below calculated capacity
claim adds output and updates lastClaimedAt to authoritative now
claim with zero whole output returns nothing_to_claim and preserves timestamp
settle with zero output succeeds and advances timestamp
corrupt worker relationship, unknown species, invalid level, or malformed production definition fails closed
```

- [ ] **Step 2: Register spec and confirm RED for missing `ProductionDomain`**

- [ ] **Step 3: Implement authoritative preview**

Validation:

```text
profile/buildings/creatures/inventory tables exist
building instance exists and ID matches
canonical definition exists and kind == production
baseRatePerMinute is positive finite
outputItemId is canonical
level is a positive integer with a canonical multiplier
lastClaimedAt and now are finite non-negative integers; now >= lastClaimedAt
assignedCreatureIds is dense and unique
workers exist, point back to this building, have canonical species, and positive affinity for workType
workerMultiplier = sum(affinity)
traitMultiplier = 1.0
elapsed is clamped using ProductionMath and GameConfig cap
raw output is whole-unit ProductionMath output
processing output is limited by current authoritative input balance/inputPerOutput
```

- [ ] **Step 4: Implement claim/settle mutations**

`claim`:
- if outputQuantity <= 0 return `nothing_to_claim` with no mutation,
- otherwise `applyTransaction` removes input and adds output atomically,
- update `lastClaimedAt = now` only after transaction success.

`settle`:
- same preview/transaction rules,
- if output is zero, still update `lastClaimedAt = now` and return success with quantity zero,
- used only by server-owned rate-change operations.

- [ ] **Step 5: Run full CI and require GREEN**

- [ ] **Step 6: Commit**

```text
feat: add deterministic production claims
```

---

### Task 4: Atomic worker assignment/unassignment mutation

**Files:**
- Create: `src/shared/Creatures/WorkAssignmentMutationDomain.luau`
- Create: `tests/creatures/WorkAssignmentMutationDomain.spec.luau`
- Modify: `tests/run.luau`

**Interfaces:**
- Consumes `WorkAssignmentDomain.validate` and `ProductionDomain.settle`.
- Produces:
  - `assign(profile, creatureInstanceId, buildingInstanceId, now) -> DomainResult<boolean>`
  - `unassign(profile, creatureInstanceId, now) -> DomainResult<boolean>`

- [ ] **Step 1: Write failing mutation tests**

Cover:

```text
valid assignment writes both creature.assignedBuildingId and building.assignedCreatureIds
assignment settles building before changing worker multiplier
no-worker assignment sets production baseline to assignment time
eligibility failure leaves both sides and timestamp unchanged
unassign settles old worker production then removes both sides
unassign rejects one-sided/corrupt relationships with no mutation
invalid now or missing ownership rejects
```

- [ ] **Step 2: Register and confirm RED**

- [ ] **Step 3: Implement assign**

1. validate `now`,
2. call `WorkAssignmentDomain.validate`,
3. call `ProductionDomain.settle` at old worker state,
4. append ID to building worker list,
5. set creature back-reference.

All mutation preconditions must be validated before settlement.

- [ ] **Step 4: Implement unassign**

Validate exact two-sided relationship and unique list membership before settlement. After successful settlement, remove the list entry and clear the creature back-reference.

- [ ] **Step 5: Run full CI and require GREEN**

- [ ] **Step 6: Commit**

```text
feat: add atomic worker assignment
```

---

### Task 5: Building upgrade domain

**Files:**
- Create: `src/shared/Buildings/BuildingUpgradeDomain.luau`
- Create: `tests/buildings/BuildingUpgradeDomain.spec.luau`
- Modify: `tests/run.luau`

**Interfaces:**
- Consumes canonical definition `upgradeCosts`/`levelMultipliers`, `InventoryDomain.canAfford`, `InventoryDomain.applyCost`, `ProductionDomain.settle`.
- Produces `BuildingUpgradeDomain.upgrade(profile, buildingInstanceId, now) -> DomainResult<number>` where value is new level.

- [ ] **Step 1: Write failing upgrade tests**

Cover:

```text
Mine level 1 -> 2 pays exact canonical resources
insufficient resources rejects with no settlement/cost/level change
unknown/non-owned building rejects
utility building rejects max_level_reached
level 3 production building rejects max_level_reached
upgrade settles production at old multiplier before level increment
corrupt canonical level data fails invalid_request
```

- [ ] **Step 2: Register and confirm RED**

- [ ] **Step 3: Implement upgrade**

Validation order:

1. profile/building ownership and timestamp,
2. canonical definition and current level,
3. next-level multiplier and cost exist and are valid,
4. `InventoryDomain.canAfford` next-level cost,
5. settle old production state,
6. apply canonical cost,
7. increment building level.

Design upgrade costs so settlement cannot consume an item required by that same upgrade cost; canonical Phase 4 costs satisfy this invariant.

- [ ] **Step 4: Run full CI and require GREEN**

- [ ] **Step 5: Commit**

```text
feat: add production building upgrades
```

---

### Task 6: Phase 4 integration chain and documentation

**Files:**
- Create: `tests/integration/BuildingProductionLoop.spec.luau`
- Modify: `tests/run.luau`
- Modify: `docs/ROADMAP.md`
- Modify: `docs/ECONOMY.md`
- Modify: `docs/CREATURE_SYSTEM.md`
- Modify: `README.md`

**Interfaces:**
- Exercises the public pure-domain APIs from Tasks 1-5 without direct fixture mutation except initial inventory seeding and server-owned capture fixture.

- [ ] **Step 1: Write deterministic end-to-end test**

Flow:

```text
profile now=100
seed Wood=20, Stone=80
grant Rockhorn
place Mine at now=100
assign Rockhorn at now=100
claim Mine at now=220 => 15 Copper Ore
place Furnace at now=220 => consumes remaining 50 Stone + 15 Copper Ore
capture Embercub
assign Embercub to Furnace at now=220
claim Mine at now=340 => 15 Copper Ore
claim Furnace at now=340 => 10 Copper Bars, consumes 10 Copper Ore
final Copper Ore=5, Copper Bar=10
```

Also assert exact building/creature relationships and claim timestamps.

- [ ] **Step 2: Run integration test and fix only genuine domain gaps**

The integration spec must use public domain APIs and must not hand-write building assignment state.

- [ ] **Step 3: Update docs**

Document:

- grid placement and plot bounds,
- construction costs and generated building IDs,
- atomic two-sided worker assignment,
- production formula and summed affinities,
- three-level production multiplier curve,
- processing input consumption,
- 8-hour cap,
- claim vs settlement semantics,
- current-inventory processing limitation,
- Phase 4 complete only after final CI.

- [ ] **Step 4: Final branch CI**

Require all four validation categories green on the exact documentation head.

- [ ] **Step 5: Review diff against Phase 4 exit criteria**

Confirm:

```text
building placement is server-owned and cost-authoritative
same-cell and off-plot placement are rejected
generated building IDs cannot be invalid/collide
worker assignment mutates both sides only after validation
rate changes settle old production state
offline time clamps at 8h
Mine produces Copper Ore from Rockhorn affinity
Furnace consumes Copper Ore and creates Copper Bars from Embercub affinity
upgrade levels/costs are canonical
zero-output claims cannot erase fractional elapsed time
processing transactions cannot partially remove inputs
no Phase 5 persistence/UI/world functionality is falsely claimed
```

- [ ] **Step 6: Mark Phase 4 complete and commit**

```text
docs: complete building production phase
```

---

## Plan Self-Review

- Spec coverage: placement, costs, upgrades, assignment mutation, production, claims, input consumption, settlement, offline cap, and the required Mine/Furnace integration chain all have explicit tasks.
- Scope boundary: no persistence infrastructure, networking, exploration, UI, physical worker simulation, or speculative input-buffer schema is introduced.
- Type consistency: all new public interfaces are named once and reused in later tasks.
- Atomicity: construction validates all post-cost failure conditions first; Furnace inventory exchange is prevalidated as one transaction; worker/rate changes validate before settlement/mutation.
- Placeholder scan: no TODO/TBD/stub steps are present.
