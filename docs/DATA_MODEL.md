# Data Model

## Stable identity

Persisted content uses stable string IDs. Display text is presentation and can change without migrations.

Examples:

- `creature_rockhorn`
- `building_mine`
- `item_copper_ore`

Player-owned creature and building instances receive generated unique IDs.

## Profile schema version 1

```luau
export type PlayerProfile = {
    schemaVersion: number,
    currencies: {
        coins: number,
        gems: number,
    },
    inventory: { [string]: number },
    creatures: { [string]: CreatureInstance },
    buildings: { [string]: BuildingInstance },
    unlocks: { [string]: boolean },
    lastSeenAt: number,
}
```

`schemaVersion` begins at 1. Migrations must be explicit and tested before any persisted shape changes.

`src/shared/Profiles/ProfileSchema.luau` now owns the pure schema lifecycle for version 1:

- `createDefault(now)` creates a fresh profile with independent nested tables,
- `validate(profile)` rejects malformed or unsupported profiles,
- `migrate(profile)` validates the current schema and returns an independent deep copy.

The current migration path is intentionally small because there is only one schema version. Unsupported versions are rejected rather than guessed into a shape that merely looks plausible.

## Balance invariants

Currency and inventory balances are finite non-negative integers.

Inventory item keys must be canonical IDs from `ItemDefinitions`. Currency keys are limited to `coins` and `gems`. Mutation APIs require positive integer deltas and reject malformed quantities before changing the profile.

Resource-cost transactions prevalidate every item and every balance before mutation, making multi-resource deductions atomic.

## Creature instance

```luau
export type CreatureInstance = {
    id: string,
    speciesId: string,
    level: number,
    experience: number,
    traits: { string },
    mutationId: string?,
    assignedBuildingId: string?,
}
```

## Building instance

```luau
export type BuildingInstance = {
    id: string,
    definitionId: string,
    level: number,
    position: { x: number, y: number, z: number },
    rotation: number,
    assignedCreatureIds: { string },
    lastClaimedAt: number,
}
```

## Persistence constraints

- Save structured data, never Roblox Instance references.
- Never silently replace a known-good profile with defaults after a load failure.
- Validate finite numeric values and non-negative balances.
- Persist server time for production claims; do not trust client clocks.
- Session ownership must prevent two servers from concurrently mutating the same profile.
- Schema migrations must be deterministic and idempotent.
- Unknown schema versions are rejected until an explicit migration exists.

## Current implementation boundary

The pure profile schema and economy mutation domain are implemented and covered by the Linux-safe domain test runner.

Production persistence is still future work. There is not yet a DataStore-backed `PlayerDataService`, session ownership/locking, autosave/retry policy, or Roblox lifecycle integration. Those systems must wrap the validated pure profile domain rather than duplicating schema or mutation rules in service code.
