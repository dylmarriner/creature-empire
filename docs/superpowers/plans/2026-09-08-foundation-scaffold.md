# Creature Empire Foundation Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold a reproducible Roblox/Rojo repository with canonical Creature Empire domain definitions, pure production/grid logic, server/client bootstraps, automated validation, and focused project documentation.

**Architecture:** Roblox Studio remains the runtime, while Git/Rojo is the source of truth. Gameplay rules that do not require Roblox Instances live in pure shared Luau modules so they can be tested outside a live player session. Valuable gameplay state remains server-authoritative; this scaffold defines contracts and real domain primitives without pretending persistence, capture, placement, or economy services are already implemented.

**Tech Stack:** Luau, Roblox, Rojo 7.7.0, Rokit, Wally 0.3.2, Selene 0.31.0, StyLua 2.5.2, Lune 0.10.5 for CI-safe pure-domain tests, Jest Roblox 3.20.0 for in-engine tests, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-08-creature-empire-foundation-design.md`

## Global Constraints

- The project is Roblox-first and Rojo-managed.
- The server owns all state with gameplay or economic value.
- Static definitions are separate from player-owned instances.
- Persisted identifiers are stable strings, never display names or Roblox Instance references.
- Production is elapsed-time simulation, not physical bookkeeping.
- Maximum offline-production window is 8 hours.
- No Knit or equivalent framework in the foundation scaffold.
- No placeholder modules, TODO/FIXME files, fake implementations, or dead code just to populate directories.
- Breeding, genetics, mutations, deep combat, trading, marketplace, guilds, seasons, AI creation, and UGC are outside this scaffold.

---

### Task 1: Reproducible Roblox project and toolchain

**Files:**
- Create: `.gitignore`
- Create: `default.project.json`
- Create: `rokit.toml`
- Create: `wally.toml`
- Create: `selene.toml`
- Create: `stylua.toml`

**Interfaces:**
- Produces: Rojo mappings for `ReplicatedStorage/Shared`, `ReplicatedStorage/Packages`, `ServerScriptService/Server`, and `StarterPlayerScripts/Client`.
- Produces: pinned CLI commands `rojo`, `wally`, `selene`, `stylua`, and `lune`.

- [ ] **Step 1: Add the pinned toolchain**

```toml
[tools]
rojo = "rojo-rbx/rojo@7.7.0"
wally = "UpliftGames/wally@0.3.2"
selene = "Kampfkarren/selene@0.31.0"
stylua = "JohnnyMorganz/stylua@2.5.2"
lune = "lune-org/lune@0.10.5"
```

- [ ] **Step 2: Add Wally dev dependencies**

```toml
[package]
name = "dylmarriner/creature-empire"
description = "Creature Empire Roblox game"
version = "0.1.0"
realm = "shared"
registry = "https://github.com/UpliftGames/wally-index"

[dependencies]

[server-dependencies]

[dev-dependencies]
Jest = "roblox/jest@=3.20.0"
JestGlobals = "roblox/jest-globals@=3.20.0"
```

- [ ] **Step 3: Map source and packages with Rojo**

`default.project.json` must map source folders without exposing server-only source to clients, and must create a minimal Workspace baseplate/spawn so `rojo build` produces a directly openable place.

- [ ] **Step 4: Add strict formatter/linter configuration**

Run after implementation:

```bash
stylua --check src tests
selene src tests
```

- [ ] **Step 5: Install and build**

```bash
rokit install
wally install
rojo build default.project.json --output CreatureEmpire.rbxlx
```

Expected: all commands exit 0 and the place file is produced.

- [ ] **Step 6: Commit**

```bash
git add .gitignore default.project.json rokit.toml wally.toml selene.toml stylua.toml
git commit -m "build: scaffold Roblox toolchain"
```

### Task 2: Canonical domain definitions and pure math

**Files:**
- Create: `src/shared/Config/GameConfig.luau`
- Create: `src/shared/Types/DomainTypes.luau`
- Create: `src/shared/Items/ItemDefinitions.luau`
- Create: `src/shared/Creatures/CreatureDefinitions.luau`
- Create: `src/shared/Buildings/BuildingDefinitions.luau`
- Create: `src/shared/Buildings/GridMath.luau`
- Create: `src/shared/Economy/ProductionMath.luau`
- Create: `src/shared/Net/ActionNames.luau`

**Interfaces:**
- Produces: `GameConfig.OFFLINE_PRODUCTION_CAP_SECONDS`, `GameConfig.BUILD_GRID_SIZE`.
- Produces: canonical stable IDs for six resources, six creatures, and eight structures.
- Produces: `ProductionMath.clampElapsedSeconds(elapsedSeconds)` and `ProductionMath.calculateOutput(baseRatePerMinute, buildingMultiplier, workerMultiplier, traitMultiplier, elapsedSeconds)`.
- Produces: `GridMath.snapCoordinate(value, gridSize)` and `GridMath.snapPosition(position, gridSize)`.

- [ ] **Step 1: Write the production tests first**

Test that 10 units/minute at all multipliers = 1 for 120 seconds yields 20 units, and that offline time is capped to 28,800 seconds.

- [ ] **Step 2: Verify the tests fail before the module exists**

```bash
lune run tests/run
```

Expected: non-zero exit because `ProductionMath` is not implemented.

- [ ] **Step 3: Implement only the pure functions and data definitions required by the spec**

`ProductionMath.calculateOutput` rejects non-finite or negative inputs and floors output to a non-negative integer. `GridMath` rejects non-positive grid sizes.

- [ ] **Step 4: Re-run pure-domain tests**

```bash
lune run tests/run
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/shared tests
git commit -m "feat: add canonical domain definitions"
```

### Task 3: Runtime bootstraps and explicit network contract

**Files:**
- Create: `src/server/init.server.luau`
- Create: `src/client/init.client.luau`

**Interfaces:**
- Consumes: `GameConfig`, `ActionNames`, and canonical definition modules.
- Produces: a server bootstrap that validates domain-definition counts and creates the semantic RemoteEvent container from server-owned action names.
- Produces: a client bootstrap that reads the shared contract but performs no authoritative mutation.

- [ ] **Step 1: Implement server bootstrap validation**

At startup, assert exactly six initial creatures, six resource items, and eight structures. Create `ReplicatedStorage/Remotes` server-side and create one `RemoteEvent` per action name if absent.

- [ ] **Step 2: Implement client bootstrap discovery**

The client waits for `ReplicatedStorage/Shared` and `ReplicatedStorage/Remotes`, verifies every declared action has a RemoteEvent, and does not calculate or mutate currency/resources.

- [ ] **Step 3: Build the place**

```bash
rojo build default.project.json --output CreatureEmpire.rbxlx
```

Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add src/server src/client
git commit -m "feat: add server and client bootstraps"
```

### Task 4: Tests and CI gate

**Files:**
- Create: `tests/run.luau`
- Create: `tests/shared/ProductionMath.spec.luau`
- Create: `tests/shared/GridMath.spec.luau`
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: deterministic pure-domain tests executable on Linux with Lune.
- Produces: Jest-compatible `.spec.luau` coverage for Roblox runtime expansion.
- Produces: CI gate for formatting, lint, tests, dependency installation, and Rojo build.

- [ ] **Step 1: Make the pure runner execute meaningful behavior**

The runner must verify production calculation, 8-hour clamping, and grid snapping. It exits non-zero on assertion failure.

- [ ] **Step 2: Keep Jest specs aligned with the same domain behavior**

Use `JestGlobals.describe`, `it`, and `expect`; do not introduce mocks for pure math.

- [ ] **Step 3: Add GitHub Actions validation**

On pushes and pull requests to `main`:

```bash
rokit install
wally install
stylua --check src tests
selene src tests
lune run tests/run
rojo build default.project.json --output CreatureEmpire.rbxlx
```

- [ ] **Step 4: Run the local-equivalent gate**

Expected: all five checks exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests .github/workflows/ci.yml
git commit -m "ci: validate Creature Empire foundation"
```

### Task 5: Project documentation

**Files:**
- Create: `README.md`
- Create: `docs/GAME_DESIGN.md`
- Create: `docs/ARCHITECTURE.md`
- Create: `docs/ROADMAP.md`
- Create: `docs/ECONOMY.md`
- Create: `docs/CREATURE_SYSTEM.md`
- Create: `docs/DATA_MODEL.md`

**Interfaces:**
- Produces: a single documented setup path and explicit MVP boundaries.
- Produces: source-of-truth descriptions matching the stable IDs and schemas in code.

- [ ] **Step 1: Document setup and validation commands in README**

Required commands:

```bash
rokit install
wally install
rojo serve
lune run tests/run
stylua --check src tests
selene src tests
rojo build default.project.json --output CreatureEmpire.rbxlx
```

- [ ] **Step 2: Document the game and architecture without claiming unbuilt systems exist**

Every future system must be labelled as future scope rather than current functionality.

- [ ] **Step 3: Cross-check docs against definitions**

Verify six creature IDs, six item IDs, eight building IDs, 8-hour offline cap, and the server-authority rule match code exactly.

- [ ] **Step 4: Commit**

```bash
git add README.md docs
git commit -m "docs: document Creature Empire foundation"
```

## Foundation Verification

Run the complete gate from a fresh clone:

```bash
rokit install
wally install
stylua --check src tests
selene src tests
lune run tests/run
rojo build default.project.json --output CreatureEmpire.rbxlx
```

The scaffold passes only when every command exits 0, the place builds, the pure-domain tests execute real production/grid behavior, and the repository contains no placeholder implementation presented as complete gameplay.
