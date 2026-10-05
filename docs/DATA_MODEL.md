# Data Model

## Stable identity

Persisted content uses stable string IDs. Display text is presentation and can change without migrations.

Examples: `creature_rockhorn`, `building_mine`, `item_copper_ore`, `objective_build_mine`.

Player-owned instances receive server-generated IDs: `c_<guid>` for creatures and `b_<guid>` for buildings.

## Profile schema version 2

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
    eggs: { [string]: { id: string } },          -- breeding (phase 8); that system owns the fields
    expeditions: { [string]: { id: string } },   -- combat (phase 9); that system owns the fields
    transfers: { [string]: TransferJournalEntry }, -- escrowed offers not yet settled
    purchases: { [string]: number },             -- receiptId -> processedAt (monetization)
    passes: { [string]: boolean },               -- owned game passes
    guildId: string?,                            -- cache; the guild record is the truth
    stats: { [string]: number },                 -- counters for analytics and objectives
    lastSeenAt: number,
}
```

Version 2 added every field the post-launch systems need in one migration, so those systems ship without further schema changes. Eggs and expeditions are only required to be tables filed under their own `id`; their domains add optional fields and validate them, which needs no new version.

An egg (owned by the breeding system) is `{ id, parentA, parentB, seed, createdAt, hatchesAt }`, where each parent is a snapshot `{ speciesId, generation, mutationId?, genes }`. The baby is computed from the snapshots and seed at hatch time.

Version 1 profiles upgrade on load (`ProfileSchema.migrate`, verified first by the frozen `ProfileSchemaV1` validator): every existing creature gets neutral genes (16/16/16), generation 0 and `bornAt = lastSeenAt`, and the new maps start empty. The upgrade is pure and deterministic, and migrating a v2 profile is a validated copy. A v2 profile is refused by a v1 build, so the release that adds v2 cannot be rolled back (see `OPERATIONS.md`).

`src/shared/Profiles/ProfileSchema.luau` owns the schema lifecycle:

- `createDefault(now)` creates a fresh profile with independent nested tables,
- `validate(profile)` rejects malformed or unsupported profiles,
- `migrate(profile)` validates the current schema and returns an independent deep copy.

Unsupported versions are rejected rather than guessed into a shape that merely looks plausible. Migrations must be explicit, deterministic, idempotent and tested before any persisted shape changes.

The `unlocks` map holds one-time markers: `starter_creature_granted` and one `objective_*` key per completed objective. No schema change was needed for the vertical slice.

## Creature instance

```luau
export type CreatureInstance = {
    id: string,
    speciesId: string,
    level: number,          -- 1..10
    experience: number,     -- progress toward the next level
    traits: { string },
    mutationId: string?,
    assignedBuildingId: string?,
    genes: { vigor: number, might: number, focus: number }, -- integers 0..31
    generation: number,     -- 0 for wild, starter and pre-breeding creatures
    lineage: { speciesA: string, speciesB: string }?, -- display only
    bornAt: number,         -- profile clock when the creature was created
    breedReadyAt: number?,  -- resting after breeding until this server time
}
```

## Building instance

```luau
export type BuildingInstance = {
    id: string,
    definitionId: string,
    level: number,          -- 1..5
    position: { x: number, y: number, z: number },
    rotation: number,       -- 0, 90, 180 or 270
    assignedCreatureIds: { string },
    lastClaimedAt: number,  -- server Unix seconds
}
```

`position` is the building's minimum corner in **plot-local grid cells** (`y` is always 0). It is independent of where the player's plot happens to be in a given server, so plots can be allocated to any slot and re-rendered from data.

## Invariants

- Currency and inventory balances are finite non-negative integers; inventory keys are canonical item IDs; currency keys are `coins` and `gems`.
- Mutation APIs require positive integer deltas and reject malformed input before changing the profile.
- Multi-resource costs are prevalidated in full before anything is deducted.
- Worker assignment is two-sided: a creature's `assignedBuildingId` and the building's `assignedCreatureIds` always agree. Load-time integrity repair removes any reference that does not.
- Every committed mutation passes full schema validation (see the transactional pipeline in `ARCHITECTURE.md`).

## Transfers

A transfer moves offers (items, coins, whole creatures) between two players. Each party escrows its offer in `profile.transfers[transferId]` (`{ id, createdAt, offer }`), which removes it from live data in one validated commit; the shared ledger record (`Transfers_v1`, key `transfer_<id>`) then decides the outcome:

```luau
{
    id = string,
    kind = string,
    state = "pending" | "completed" | "cancelled",
    parties = { userIdA, userIdB },
    offers = { [tostring(userId)]: TransferPayload },
    createdAt = number, completedAt = number?, cancelledAt = number?,
}
```

A journal entry exists exactly while an offer is unsettled. Settling a completed record gives the offer away and takes the counterpart's in one commit; settling a cancelled one restores the offer. Both are idempotent, which is what makes crash recovery safe. A cancelled record with no parties is a tombstone left when recovery finds an escrowed offer that was never published. See `ARCHITECTURE.md` for the step order.

A held creature is a full `CreatureInstance` inside the entry and is absent from `profile.creatures`, so an item is never in two live places.

## Stored record

Profiles are stored in the DataStore `PlayerProfiles_v1` under the key `player_<userId>`, with the user id attached to the key for data-privacy tooling:

```luau
{
    format = 1,
    profile = PlayerProfile,
    session = { jobId = string, lockedAt = number } | nil,
}
```

## Session locking

`src/server/Persistence/ProfileStore.luau` implements the protocol over an abstract `update(key, transform)` store; `DataStoreAdapter` binds it to `UpdateAsync`.

- **Load** writes this server's `jobId` and the time into `session`. A missing record creates a default profile. An unknown record format or a profile that fails migration is **refused without writing**, and the player is kicked with a message; a known-good profile is never replaced with defaults.
- A lock held by another server is waited on (5 attempts with increasing delays). A lock older than 30 minutes is treated as abandoned. On the final attempt the lock is taken over; the previous holder's next save sees the foreign `jobId`, is refused, and that server stops writing and kicks its copy of the player. Two servers can therefore never interleave writes.
- **Save** only writes while this server holds the lock, only writes schema-valid profiles, refreshes `lockedAt`, and retries transient failures. Leaving and shutdown saves release the lock.
- Autosave runs every 90 seconds; saves for one player are serialised.
- A failed release save (on leave) is retried up to four times with backoff before the session is dropped and the loss is logged. While a release is in flight, commits for that session are refused, and a rejoin on the same server waits for the release to land before loading.
- During shutdown, new joins are refused, in-flight loads release their lock as soon as they finish, and the server waits (up to 25 seconds) for every load and release to complete.
- A DataStore outage during load kicks the player instead of starting them on an unsaved profile.

In Studio without API access the server falls back to `MemoryStore` and logs a warning. Live servers never use the memory store.

## Persistence constraints

- Save structured data, never Roblox Instance references.
- Never silently replace a known-good profile with defaults after a load failure.
- Validate finite numeric values and non-negative balances.
- Persist server time for production claims; never trust client clocks.
- Session ownership must prevent two servers from concurrently mutating the same profile.
