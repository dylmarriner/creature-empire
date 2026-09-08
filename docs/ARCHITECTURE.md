# Architecture

## Runtime model

Creature Empire is a Rojo-managed Roblox project. Git contains source; Rojo maps it into Roblox services.

```text
ReplicatedStorage
├── Shared      <- src/shared
└── Packages    <- Wally Packages

ServerScriptService
└── Server      <- src/server

StarterPlayer
└── StarterPlayerScripts
    └── Client  <- src/client
```

## Authority

All state with gameplay or economic value is server-authoritative. A client may request an action such as `AssignCreature` or `PlaceBuilding`; the server owns validation and resulting mutation.

The client never provides authoritative currency balances, production quantities, prices, creature stats, or reward multipliers.

## Domain boundaries

Static definitions and owned instances are separate. `creature_rockhorn` identifies a species definition; an owned Rockhorn later receives a generated instance ID. The same separation applies to building definitions and placed building instances.

The planned server domains are:

- PlayerDataService: schema, load/save/migration and session ownership.
- InventoryService: validated item mutations.
- CreatureService: ownership, capture and assignment eligibility.
- BuildingService: plot placement, removal, upgrades and spatial rules.
- ProductionService: elapsed-time production and claims.
- EconomyService: currency and transaction-level checks.

Those services are not scaffolded as empty modules. They will be introduced when their behavior is implemented and tested.

## Networking

The shared action contract currently declares:

- `AssignCreature`
- `PlaceBuilding`
- `UpgradeBuilding`
- `ClaimProduction`
- `CaptureCreature`

The server creates semantic RemoteEvents from that contract. Future handlers must validate payload shape, identifier existence, ownership, bounds, cooldowns, finite numeric values, and replay-sensitive operations before changing state.

## Pure domain logic

Production and grid normalization are intentionally independent of Roblox Instances. This allows deterministic testing on CI and keeps the core rules portable.

## Persistence rule

Saved data describes domain records. Roblox Instance references, transient object IDs, and client-only state never become persisted identity.
