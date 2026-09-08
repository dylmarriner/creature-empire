# Creature Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Phase 3 creature ownership so a server-owned profile can receive a generated-ID starter Rockhorn, capture valid species without accepting client-authored identity, reject invalid/duplicate ownership mutations, and validate creature-to-building work assignment eligibility.

**Architecture:** Keep Phase 3 as pure, server-authoritative domain logic under `src/shared/Creatures` so it remains deterministic and Lune-testable. Creature creation receives an injected server-owned ID generator; the domain validates its output before mutating the profile. Assignment eligibility is a separate pure validator that reads canonical creature/building definitions and existing owned instances without performing Phase 4 worker-assignment mutation.

**Tech Stack:** Luau, Lune 0.10.5, Rojo 7.7.0, Selene 0.31.0, StyLua 2.5.2, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-08-creature-empire-foundation-design.md`

## Global Constraints

- All state with gameplay or economic value is server-authoritative.
- Static species/building definitions remain separate from player-owned instances.
- Persisted species IDs use stable canonical strings; owned creatures use generated unique instance IDs.
- The client never supplies authoritative balances, prices, creature stats, rewards, or generated ownership identity.
- Expected gameplay failures return typed domain results instead of throwing uncontrolled errors.
- Breeding, genetics, mutations, trading, marketplace, deep combat, and creator systems remain outside Phase 3.
- Phase 3 does not perform building placement, production claims, or final worker-assignment mutation; those belong to Phase 4.
- Every branch must pass StyLua, Selene, Lune pure-domain tests, and Rojo build before merge.

---

### Task 1: Creature ownership and generated instance IDs

**Files:**
- Create: `src/shared/Creatures/CreatureOwnershipDomain.luau`
- Create: `tests/creatures/CreatureOwnershipDomain.spec.luau`
- Modify: `src/shared/Types/DomainTypes.luau`
- Modify: `tests/run.luau`

**Interfaces:**
- Consumes: `CreatureDefinitions.ById`, profile shape from `ProfileSchema`.
- Produces:
  - `CreatureOwnershipDomain.grantStarter(profile, generateId) -> DomainResult<CreatureInstance>`
  - `CreatureOwnershipDomain.capture(profile, speciesId, eligible, generateId) -> DomainResult<CreatureInstance>`
  - generator signature: `() -> any`; the domain accepts only a non-empty string not already present in `profile.creatures`.
  - starter species is canonical `creature_rockhorn`.
  - starter grant marker is `profile.unlocks.starter_creature_granted = true`.

- [ ] **Step 1: Write the failing ownership tests**

Create `tests/creatures/CreatureOwnershipDomain.spec.luau` covering:

```luau
local ProfileSchema = require("../../src/shared/Profiles/ProfileSchema")
local CreatureOwnershipDomain = require("../../src/shared/Creatures/CreatureOwnershipDomain")

local function sequenceGenerator(values)
    local index = 0
    return function()
        index += 1
        return values[index]
    end
end

local profile = ProfileSchema.createDefault(100)
local starter = CreatureOwnershipDomain.grantStarter(profile, sequenceGenerator({ "creature_instance_starter" }))
assert(starter.ok == true)
assert(starter.value.id == "creature_instance_starter")
assert(starter.value.speciesId == "creature_rockhorn")
assert(starter.value.level == 1)
assert(starter.value.experience == 0)
assert(#starter.value.traits == 0)
assert(profile.creatures.creature_instance_starter == starter.value)
assert(profile.unlocks.starter_creature_granted == true)

local duplicateStarter = CreatureOwnershipDomain.grantStarter(profile, sequenceGenerator({ "unused" }))
assert(duplicateStarter.ok == false)
assert(duplicateStarter.code == "starter_already_granted")

local captured = CreatureOwnershipDomain.capture(
    profile,
    "creature_embercub",
    true,
    sequenceGenerator({ "creature_instance_capture" })
)
assert(captured.ok == true)
assert(captured.value.speciesId == "creature_embercub")

local ineligible = CreatureOwnershipDomain.capture(
    profile,
    "creature_mossling",
    false,
    sequenceGenerator({ "must_not_be_used" })
)
assert(ineligible.ok == false)
assert(ineligible.code == "capture_not_eligible")
assert(profile.creatures.must_not_be_used == nil)

local unknownSpecies = CreatureOwnershipDomain.capture(
    profile,
    "creature_unknown",
    true,
    sequenceGenerator({ "unknown_capture" })
)
assert(unknownSpecies.ok == false)
assert(unknownSpecies.code == "invalid_request")

local duplicateId = CreatureOwnershipDomain.capture(
    profile,
    "creature_aquafin",
    true,
    sequenceGenerator({ "creature_instance_capture" })
)
assert(duplicateId.ok == false)
assert(duplicateId.code == "duplicate_creature_instance")

local invalidGeneratedId = CreatureOwnershipDomain.capture(
    profile,
    "creature_aquafin",
    true,
    sequenceGenerator({ "" })
)
assert(invalidGeneratedId.ok == false)
assert(invalidGeneratedId.code == "invalid_generated_id")
```

Also verify capture permits owning two different instances of the same species when generated IDs differ. Species duplication is valid; instance-ID duplication is not.

- [ ] **Step 2: Register the failing spec in `tests/run.luau`**

Add:

```luau
local runCreatureOwnershipDomainSpec = require("./creatures/CreatureOwnershipDomain.spec")
```

and invoke it after the economy specs.

- [ ] **Step 3: Run CI and confirm RED for the missing domain module**

Expected pure-domain failure: `could not resolve child component "CreatureOwnershipDomain"` after format/lint are clean.

- [ ] **Step 4: Extend typed error codes**

Add these exact values to `DomainErrorCode`:

```luau
| "starter_already_granted"
| "capture_not_eligible"
| "duplicate_creature_instance"
| "invalid_generated_id"
| "creature_not_owned"
| "building_not_owned"
| "incompatible_work"
```

- [ ] **Step 5: Implement minimal ownership domain**

`CreatureOwnershipDomain.luau` must:

```luau
local CreatureDefinitions = require("./CreatureDefinitions")

local STARTER_SPECIES_ID = "creature_rockhorn"
local STARTER_UNLOCK_ID = "starter_creature_granted"

local function createOwnedInstance(profile: any, speciesId: string, generateId: any)
    if type(profile) ~= "table" or type(profile.creatures) ~= "table" then
        return { ok = false, code = "invalid_request", message = "profile creatures are invalid" }
    end
    if CreatureDefinitions.ById[speciesId] == nil then
        return { ok = false, code = "invalid_request", message = "unknown creature species" }
    end
    if type(generateId) ~= "function" then
        return { ok = false, code = "invalid_request", message = "id generator is required" }
    end

    local instanceId = generateId()
    if type(instanceId) ~= "string" or instanceId == "" then
        return { ok = false, code = "invalid_generated_id", message = "generated creature id is invalid" }
    end
    if profile.creatures[instanceId] ~= nil then
        return { ok = false, code = "duplicate_creature_instance", message = "generated creature id already exists" }
    end

    local creature = {
        id = instanceId,
        speciesId = speciesId,
        level = 1,
        experience = 0,
        traits = {},
        mutationId = nil,
        assignedBuildingId = nil,
    }
    profile.creatures[instanceId] = creature
    return { ok = true, value = creature }
end
```

`grantStarter` validates `profile.unlocks`, rejects an existing marker before invoking the generator, creates one Rockhorn, then sets the marker only after creation succeeds.

`capture` validates `eligible == true` before invoking the generator. It does not calculate capture chance; world encounter/proximity/cooldown logic is intentionally deferred to the playable vertical slice.

- [ ] **Step 6: Run full CI and require GREEN**

Required: formatting, lint, Lune tests, Rojo build all pass.

- [ ] **Step 7: Commit Task 1**

Commit message:

```text
feat: add creature ownership domain
```

---

### Task 2: Work-assignment eligibility validation

**Files:**
- Create: `src/shared/Creatures/WorkAssignmentDomain.luau`
- Create: `tests/creatures/WorkAssignmentDomain.spec.luau`
- Modify: `tests/run.luau`

**Interfaces:**
- Consumes: `CreatureDefinitions.ById`, `BuildingDefinitions.ById`, owned `profile.creatures`, owned `profile.buildings`.
- Produces: `WorkAssignmentDomain.validate(profile, creatureInstanceId, buildingInstanceId) -> DomainResult<boolean>`.
- No assignment mutation is performed in Phase 3.

- [ ] **Step 1: Write the failing eligibility tests**

Construct a valid owned Rockhorn and owned Mine directly in a fresh profile fixture and assert:

```luau
local result = WorkAssignmentDomain.validate(profile, "creature_instance_1", "building_instance_1")
assert(result.ok == true)
assert(result.value == true)
```

Add exact failure cases:

```text
unknown creature instance -> creature_not_owned
unknown building instance -> building_not_owned
creature.assignedBuildingId already set -> creature_already_assigned
building assignedCreatureIds count >= canonical maxWorkers -> building_capacity_full
Embercub -> Mine -> incompatible_work
Rockhorn -> utility Warehouse -> incompatible_work
malformed canonical IDs/state -> invalid_request
building list already contains creature while creature says unassigned -> invalid_request
```

- [ ] **Step 2: Register the failing spec in `tests/run.luau`**

Add the require and call after the ownership spec.

- [ ] **Step 3: Run CI and confirm RED for missing `WorkAssignmentDomain`**

Do not implement until format/lint are clean and the pure test reaches the intended missing-module failure.

- [ ] **Step 4: Implement eligibility validation**

Validation order must be deterministic:

1. profile shape and IDs are strings,
2. creature instance exists,
3. building instance exists,
4. owned records point to canonical species/building definitions,
5. creature is not already assigned,
6. building assignment list is dense and does not already contain the creature,
7. canonical `maxWorkers` is a non-negative integer and current workers are below capacity,
8. building has a canonical `workType`,
9. species has a positive numeric affinity for that work type.

Return `{ ok = true, value = true }` only after every check passes.

Do not trust `maxWorkers`, `workType`, or affinities from owned instance records. Those values come exclusively from `BuildingDefinitions` and `CreatureDefinitions`.

- [ ] **Step 5: Run full CI and require GREEN**

Required: format, lint, pure-domain tests, Rojo build.

- [ ] **Step 6: Commit Task 2**

Commit message:

```text
feat: validate creature work assignment
```

---

### Task 3: Phase 3 documentation and regression hardening

**Files:**
- Modify: `docs/CREATURE_SYSTEM.md`
- Modify: `docs/ROADMAP.md`
- Modify: `README.md`
- Test: existing `tests/creatures/*.spec.luau`

**Interfaces:**
- Documents the exact behavior implemented by Tasks 1-2.
- Does not claim that network handlers, persistence, encounter simulation, or assignment mutation exist yet.

- [ ] **Step 1: Update `docs/CREATURE_SYSTEM.md`**

Document:

- starter Rockhorn grant uses `starter_creature_granted`,
- every owned instance starts at level 1 / experience 0 / empty traits,
- capture accepts only canonical species and a server-owned eligibility decision,
- generated instance IDs must be non-empty and unique per profile,
- same-species duplicates are allowed when instance IDs differ,
- assignment eligibility validates both ownership sides, canonical capacity, current assignment state, and species work affinity,
- actual assignment mutation remains Phase 4.

- [ ] **Step 2: Update `docs/ROADMAP.md`**

Mark Phase 1 and Phase 2 complete. Mark Phase 3 complete only after the final CI gate is green, and phrase its delivered scope as ownership/capture/starter/eligibility rather than claiming Phase 4 worker mutation.

- [ ] **Step 3: Update `README.md`**

Move inventory/currency mutation and creature ownership/capture eligibility from “subsequent phases” into the current foundation list. Keep persistence, final building placement/assignment, production claiming, and playable world listed as subsequent.

- [ ] **Step 4: Final regression gate**

Run the branch CI from the final documentation commit and require all four categories to pass.

- [ ] **Step 5: Review diff against Phase 3 exit criteria**

Confirm:

```text
starter Rockhorn can be granted exactly once
capture creates valid owned instances
multiple same-species instances are allowed
unknown species cannot be captured
generated IDs cannot be empty or collide
ineligible capture cannot mutate ownership
assignment requires owned creature + owned building
already-assigned creatures are rejected
full buildings are rejected
wrong work affinities are rejected
no Phase 4 mutation is falsely claimed
```

- [ ] **Step 6: Commit Task 3**

Commit message:

```text
docs: complete creature ownership phase
```

---

## Plan Self-Review

- Spec coverage: Phase 3 starter ownership, capture flow, generated instance identity, duplicate rejection, and assignment eligibility are each covered by explicit tasks.
- Scope boundary: no persistence implementation, encounter simulation, worker-assignment mutation, building placement, or production claiming is pulled forward from Phases 4-5.
- Type consistency: every new error code is named once and reused exactly by tests/interfaces.
- Security: generated IDs and capture eligibility are caller dependencies intended to be supplied by server-owned code; no client-authored identity or canonical work/capacity values are accepted.
- Placeholder scan: no TODO/TBD/stub steps are present.
