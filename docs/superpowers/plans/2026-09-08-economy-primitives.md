# Creature Empire Economy Primitives Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the first server-authoritative economy domain: profile defaults/migration/validation, inventory mutation, currency mutation, and atomic resource-cost transactions.

**Architecture:** Keep all mutation logic in pure shared Luau modules with explicit result values so it can be exercised by Lune and later wrapped by Roblox server services. Profiles are plain serializable records; all balances are finite non-negative integers. Multi-item costs are prevalidated before any mutation so failed transactions never partially consume resources.

**Tech Stack:** Luau, Roblox, Rojo 7.7.0, Lune 0.10.5, Selene 0.31.0, StyLua 2.5.2, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-08-creature-empire-foundation-design.md`

## Global Constraints

- Server owns all gameplay/economic state; clients never supply authoritative balances or rewards.
- Persisted schema version remains `1` in this phase.
- Profiles contain only serializable data and stable string IDs.
- Balances and quantities must be finite, non-negative integers.
- Unknown item IDs and unknown currency IDs are rejected.
- Failed transactions must not partially mutate profiles.
- Migration must be deterministic and idempotent.
- No DataStore integration yet; this phase builds the pure domain the future `PlayerDataService`, `InventoryService`, and `EconomyService` will wrap.
- No TODO/FIXME, stubs, or placeholder services.

---

### Task 1: Profile defaults, validation, and migration

**Files:**
- Create: `src/shared/Profiles/ProfileSchema.luau`
- Test: `tests/economy/ProfileSchema.spec.luau`
- Modify: `tests/run.luau`

**Interfaces:**
- Produces: `ProfileSchema.CURRENT_VERSION: number`
- Produces: `ProfileSchema.createDefault(now: number): PlayerProfile`
- Produces: `ProfileSchema.validate(profile: any): (boolean, string?)`
- Produces: `ProfileSchema.migrate(profile: any): (PlayerProfile?, string?)`

- [ ] **Step 1: Write failing tests** for a version-1 default profile, rejection of negative/non-integer balances, rejection of unknown inventory IDs, and idempotent migration of a valid version-1 profile.

```luau
local profile = ProfileSchema.createDefault(100)
expectEqual(profile.schemaVersion, 1, "default schema version")
expectEqual(profile.currencies.coins, 0, "default coins")
expectEqual(profile.lastSeenAt, 100, "default last seen")

local invalid = ProfileSchema.createDefault(100)
invalid.currencies.coins = -1
expectFalse(ProfileSchema.validate(invalid), "negative currency rejected")

local migrated = assert(ProfileSchema.migrate(profile))
expectTrue(migrated ~= profile, "migration returns copy")
expectEqual(migrated.schemaVersion, 1, "idempotent migration")
```

- [ ] **Step 2: Verify RED** with the PR CI. Expected: pure-domain tests fail because `ProfileSchema` does not exist.

- [ ] **Step 3: Implement the minimum pure module.** `createDefault` returns fresh nested tables every call. Validation checks schema/version, currencies, inventory, owned collections, unlock booleans, and `lastSeenAt` without accepting NaN, infinity, fractional quantities, negative quantities, or unknown inventory IDs. `migrate` deep-copies a valid current-version profile and rejects unsupported versions.

- [ ] **Step 4: Verify GREEN** with `lune run tests/run`, then formatting/lint/build through CI.

### Task 2: Inventory mutations

**Files:**
- Create: `src/shared/Economy/InventoryDomain.luau`
- Test: `tests/economy/InventoryDomain.spec.luau`
- Modify: `tests/run.luau`

**Interfaces:**
- Produces: `InventoryDomain.add(profile, itemId, quantity): DomainResult<number>`
- Produces: `InventoryDomain.remove(profile, itemId, quantity): DomainResult<number>`
- Produces: `InventoryDomain.canAfford(profile, cost): boolean`
- Produces: `InventoryDomain.applyCost(profile, cost): DomainResult<boolean>`

- [ ] **Step 1: Write failing tests** proving add/remove behavior, rejection of zero/fractional/negative quantities and unknown items, insufficient-resource rejection, and atomic multi-item cost application.

```luau
expectOkValue(InventoryDomain.add(profile, "item_wood", 10), 10, "add wood")
expectOkValue(InventoryDomain.remove(profile, "item_wood", 4), 6, "remove wood")

profile.inventory.item_wood = 20
profile.inventory.item_stone = 5
local result = InventoryDomain.applyCost(profile, { item_wood = 10, item_stone = 10 })
expectErrorCode(result, "insufficient_resources", "cost rejected")
expectEqual(profile.inventory.item_wood, 20, "failed cost is atomic")
expectEqual(profile.inventory.item_stone, 5, "failed cost leaves all items")
```

- [ ] **Step 2: Verify RED**. Expected: tests fail because `InventoryDomain` is absent.

- [ ] **Step 3: Implement minimum mutation logic.** All quantities are positive integers. `applyCost` validates the whole cost table first, then affordability, then mutates in one pass. Zero balances are removed from the inventory map to keep persisted profiles compact.

- [ ] **Step 4: Verify GREEN** through the complete CI gate.

### Task 3: Currency mutations

**Files:**
- Create: `src/shared/Economy/CurrencyDomain.luau`
- Test: `tests/economy/CurrencyDomain.spec.luau`
- Modify: `tests/run.luau`
- Modify: `src/shared/Types/DomainTypes.luau`

**Interfaces:**
- Currency IDs: `coins`, `gems`
- Produces: `CurrencyDomain.add(profile, currencyId, amount): DomainResult<number>`
- Produces: `CurrencyDomain.spend(profile, currencyId, amount): DomainResult<number>`

- [ ] **Step 1: Write failing tests** for valid earning/spending, unknown currency rejection, invalid amounts, and insufficient funds without mutation.

```luau
expectOkValue(CurrencyDomain.add(profile, "coins", 50), 50, "earn coins")
expectOkValue(CurrencyDomain.spend(profile, "coins", 20), 30, "spend coins")
local failed = CurrencyDomain.spend(profile, "coins", 100)
expectErrorCode(failed, "insufficient_currency", "overspend rejected")
expectEqual(profile.currencies.coins, 30, "overspend does not mutate")
```

- [ ] **Step 2: Verify RED** for the new behavior.

- [ ] **Step 3: Implement minimal currency mutation** and add `insufficient_currency` / `unknown_currency` error codes to the domain union.

- [ ] **Step 4: Verify GREEN** through the complete CI gate.

### Task 4: Canonical building-cost transaction integration

**Files:**
- Create: `src/shared/Economy/BuildingCostDomain.luau`
- Test: `tests/economy/BuildingCostDomain.spec.luau`
- Modify: `tests/run.luau`
- Modify: `docs/ECONOMY.md`
- Modify: `docs/DATA_MODEL.md`

**Interfaces:**
- Consumes: `BuildingDefinitions.ById`, `InventoryDomain.applyCost`
- Produces: `BuildingCostDomain.canAfford(profile, buildingDefinitionId): DomainResult<boolean>`
- Produces: `BuildingCostDomain.purchase(profile, buildingDefinitionId): DomainResult<boolean>`

- [ ] **Step 1: Write failing tests** proving a Mine consumes exactly 20 Wood + 30 Stone, unknown building IDs are rejected, and unaffordable purchases leave every balance untouched.

```luau
profile.inventory.item_wood = 20
profile.inventory.item_stone = 30
expectOkValue(BuildingCostDomain.purchase(profile, "building_mine"), true, "purchase mine")
expectEqual(profile.inventory.item_wood or 0, 0, "mine consumes wood")
expectEqual(profile.inventory.item_stone or 0, 0, "mine consumes stone")
```

- [ ] **Step 2: Verify RED**.

- [ ] **Step 3: Implement the thin canonical-cost wrapper.** It must read costs from `BuildingDefinitions`, never accept a client-provided cost table, and delegate mutation atomically to `InventoryDomain`.

- [ ] **Step 4: Update docs** to describe implemented mutation guarantees while still marking DataStore-backed persistence/services as future work.

- [ ] **Step 5: Run final gate:** Wally install, StyLua, Selene, Lune tests, Rojo build.

## Phase Exit Criteria

- Default profiles are fresh, valid schema-v1 records.
- Current-version migration is deterministic and returns an independent copy.
- Inventory/currency mutation rejects malformed requests and cannot drive balances negative.
- Multi-resource costs are atomic.
- Building purchases use server-owned canonical definition costs rather than caller-supplied values.
- Pure-domain tests cover success and failure paths.
- Formatting, lint, tests, and Rojo build all pass in GitHub Actions.
