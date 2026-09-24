# Architecture

## Runtime model

Creature Empire is a Rojo-managed Roblox project. Git contains source; Rojo maps it into Roblox services.

```text
ReplicatedStorage
├── Shared      <- src/shared   (pure, data-driven domain logic and contracts)
└── Remotes     <- created by the server at startup

ServerScriptService
└── Server      <- src/server   (Script + service modules)

StarterPlayer
└── StarterPlayerScripts
    └── Client  <- src/client   (LocalScript + controller modules)

Workspace
├── World       <- built by WorldService at startup
└── Plots       <- one model per loaded player, rendered by PlotService
```

The world is generated from code with a fixed seed, so the place file carries no hand-edited geometry that could drift from Git.

Wally currently has no runtime dependencies, so the Rojo project does not map a `Packages` directory. When the game gains a real runtime package, `Packages` will be mapped into `ReplicatedStorage` at that point.

## Authority

All state with gameplay or economic value is server-authoritative. A client may request an action such as `AssignCreature` or `PlaceBuilding`; the server owns validation and the resulting mutation.

The client never provides authoritative currency balances, production quantities, prices, creature stats, capture outcomes or reward multipliers. The only client-supplied numbers are grid cells, a rotation and a sell quantity, all range-checked and re-validated by the domain.

## Server services

```text
init.server.luau        wiring and join-time starter grant
Services/PlayerDataService   session lifecycle: load+lock, autosave, save+release, shutdown
Services/ActionService       the single entry point for profile mutation
Services/NetworkService      remotes, request validation, rate limits, replication
Services/PlotService         plot allocation, building rendering, respawn at plot
Services/WorldService        world geometry, gathering nodes, wild creatures, capture
Services/Logger              structured logging without player data
Persistence/ProfileStore     session-locked load/save over an abstract store (pure)
Persistence/DataStoreAdapter Roblox DataStore adapter with request-budget waits
Persistence/MemoryStore      in-memory adapter for tests and Studio without API access
```

The originally planned InventoryService, CreatureService, BuildingService, ProductionService and EconomyService are not separate Roblox services. Their rules live in pure shared domains (`InventoryDomain`, `CreatureOwnershipDomain`, `WorkAssignmentDomain`, `PlacementDomain`, `UpgradeDomain`, `ProductionDomain`, `MarketDomain`, `CurrencyDomain`) and are invoked only through `ActionService`. This keeps every rule testable without an engine and leaves exactly one mutation path.

## Transactional mutation pipeline

Every profile change — remote actions, gathering, capture, the starter grant — runs through `Gameplay/ActionPipeline`:

1. deep-copy the committed profile,
2. run the domain mutation on the copy inside `pcall`,
3. on an ok result, evaluate objectives and grant rewards,
4. validate the full profile schema,
5. commit by swapping the session profile, then replicate and re-render.

A thrown error, a failed domain result or a schema violation discards the copy, so a partially applied mutation can never be saved. Unexpected failures are logged with the action name and user id only.

Domain mutations never yield, and Luau runs each event handler to completion, so actions from one player cannot interleave.

## Networking

Client → server actions are RemoteEvents under `ReplicatedStorage.Remotes`, named by `Shared/Net/ActionNames`:

| Action | Payload | Scope |
| --- | --- | --- |
| `AssignCreature` | `creatureId`, `buildingId` | profile |
| `UnassignCreature` | `creatureId` | profile |
| `ReleaseCreature` | `creatureId` | profile |
| `PlaceBuilding` | `definitionId`, `cellX`, `cellZ`, `rotation` | profile |
| `UpgradeBuilding` | `buildingId` | profile |
| `RemoveBuilding` | `buildingId` | profile |
| `ClaimProduction` | optional `buildingId` (omitted = claim all) | profile |
| `SellResource` | `itemId`, `quantity` | profile |
| `RequestSync` | none | session |
| `Travel` | `destination` (`home` or `wilds`) | session |

Each request is `(requestId, payload)`. The server processes it in this order:

1. `requestId` must be a non-negative integer,
2. per-player global and per-action token buckets (`Shared/Net/ActionSchemas` rates),
3. strict payload schema: no unknown or non-string keys, ids are 1–64 characters of `[A-Za-z0-9_-]`, integers are finite and in range, enums are from an allow-list,
4. profile actions run through `ActionService`; session actions run a registered handler that never touches the profile.

Server → client RemoteEvents (`Shared/Net/RemoteNames`):

- `ActionResult(requestId, actionName, { ok, code?, message?, value? })`
- `StateSnapshot(snapshot)` — the player's own profile plus derived display values (rates, capacities, current objective), sent after every commit
- `Notify({ kind, text })` — world interaction feedback

Capture and gathering are world interactions on server-owned ProximityPrompts. The server re-checks character range, per-player cooldowns, habitat capacity and rolls capture chances itself, so there is no client-invokable capture or gather remote.

## Pure domain logic

Everything under `src/shared` is independent of Roblox Instances and runs under Lune on CI. `WorldLayout` holds the plot and zone geometry as plain numbers so the server renderer and the client placement preview share one convention.

## Persistence

See [`DATA_MODEL.md`](DATA_MODEL.md) for the stored record format and the session-lock protocol.

Saved data describes domain records. Roblox Instance references, transient object IDs, and client-only state never become persisted identity.
