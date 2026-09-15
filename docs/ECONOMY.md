# Economy

## Economic objective

The economy should make creature acquisition and empire improvement reinforce each other. Resources exist to create decisions and progression, not to inflate into meaningless trillions during the tutorial.

## Initial currencies

The profile schema defines:

- Coins: standard earned currency.
- Gems: premium/special currency reserved for later monetization and rewards design.

Pure server-domain mutation logic exists for both currencies. Currency operations accept only the canonical `coins` and `gems` IDs, require finite positive integer amounts, reject insufficient balances without mutation, and distinguish unknown currencies from insufficient funds.

These pure mutations are not yet exposed directly to clients and are not yet backed by a production DataStore service.

## Initial resources

- Wood
- Stone
- Copper Ore
- Copper Bar
- Food
- Energy

Inventory mutation logic validates item IDs against `src/shared/Items/ItemDefinitions.luau`. Add/remove operations require finite positive integer quantities and cannot drive balances negative. Zero balances are removed from the inventory map.

`InventoryDomain.applyTransaction` supports atomic removal and addition in one operation. It validates every affected balance and computes the complete final inventory state before mutating anything, so processing cannot remove an input if the output side or any other part of the transaction is invalid.

Multi-resource costs are also atomic: the complete cost is validated and checked for affordability before any resource is consumed.

## Building construction

Static building costs live in `src/shared/Buildings/BuildingDefinitions.luau` and are authoritative. Callers identify the definition they want to place; they do not provide prices.

`BuildingPlacementDomain.place`:

- validates a canonical building definition,
- snaps the requested position to the 4-stud build grid,
- requires ground-plane placement,
- enforces inclusive x/z plot bounds of +/-64 studs,
- rejects an occupied snapped origin,
- obtains a non-empty server-generated instance ID,
- rejects generated-ID collisions,
- charges the canonical construction cost atomically,
- creates a level-1 owned building only after all earlier validation succeeds.

For example:

- Mine: 20 Wood + 30 Stone
- Furnace: 50 Stone + 15 Copper Ore

A rejected placement cannot consume construction resources.

## Production

Production is authoritative elapsed-time simulation:

```text
output = base rate per minute
       x building level multiplier
       x summed worker affinity
       x trait multiplier
       x elapsed minutes
```

The Phase 4 trait multiplier is fixed at `1.0`. Worker contribution is the sum of each assigned creature's canonical positive affinity for the building work type. Assigned worker relationships must be valid in both directions before production is accepted.

Whole-unit output is calculated through `ProductionMath`; fractional output is not granted early. A normal zero-output `claim` returns `nothing_to_claim` and does not advance `lastClaimedAt`, so fractional elapsed time is not erased.

Offline elapsed time is capped at 8 hours (28,800 seconds) before output is calculated.

## Claim and settlement semantics

`ProductionDomain.claim` is the player-facing economic mutation primitive for accrued production. When output is positive it atomically applies processing inputs/outputs, then advances the building's authoritative `lastClaimedAt` timestamp.

`ProductionDomain.settle` uses the same calculation but may succeed with zero whole-unit output and still advance the timestamp. Settlement is reserved for server-owned rate changes such as worker assignment/unassignment and upgrades. This prevents a new worker or new level from being retroactively applied to time that elapsed under the old production state.

## Processing buildings

A production definition may specify `inputItemId` and `inputPerOutput`. The Furnace consumes one Copper Ore per Copper Bar.

Processing output is limited by both calculated production capacity and the input currently present in authoritative inventory at claim/settlement time. Input removal and output addition occur in one atomic inventory transaction.

Phase 4 does not implement a separate building input buffer or queued recipe inventory. This means the current Furnace model processes against the player's current inventory when a claim or settlement occurs. A dedicated input-buffer subsystem, if desired later, requires its own design rather than being implied by the existing implementation.

## Production upgrades

Production buildings have three canonical levels with multipliers:

```text
Level 1: 1.00
Level 2: 1.25
Level 3: 1.60
```

Upgrade costs live in each canonical production definition. `BuildingUpgradeDomain.upgrade` validates affordability first, settles production at the old level, charges the canonical cost, then increments the level. Utility buildings have no Phase 4 upgrade curve and reject upgrade attempts as `max_level_reached`.

## Worker-driven economic state

Worker assignment is a state transition, not a client-side hint. `WorkAssignmentMutationDomain` validates ownership, capacity, work compatibility, and relationship consistency, settles the old production state, then updates both `creature.assignedBuildingId` and `building.assignedCreatureIds`.

Unassignment likewise validates the exact two-sided relationship, settles the old worker rate, then removes both references.

## Sources and sinks

Early sources:

- manual gathering,
- creature-powered production,
- exploration rewards,
- progression rewards.

Early sinks:

- building construction,
- building upgrades,
- crafting/processing inputs,
- later expansion costs.

Economy work must measure source/sink rates before introducing broad multipliers.

## Current implementation boundary

Implemented pure domain behavior now includes:

- profile currency defaults and validation,
- inventory add/remove and atomic exchange,
- atomic resource costs,
- Coins/Gems add and spend,
- canonical building construction costs,
- authoritative grid placement and building ownership creation,
- atomic two-sided worker assignment/unassignment,
- deterministic production preview, claim, and settlement,
- Furnace input consumption,
- canonical three-level production upgrades,
- 8-hour offline-production clamping.

Not yet implemented:

- DataStore-backed profile persistence,
- session locking/ownership,
- Roblox-facing persistence/economy/building services,
- remote request handlers,
- physical worker movement simulation,
- per-building processing input buffers,
- Phase 5 exploration/UI/tutorial world flow.

## Monetization principles

The MVP must be enjoyable without purchases. Early monetization should favour cosmetics, clearly bounded convenience, account/social features, and private-world features. Extreme production multipliers that turn useful creatures into a payment check are specifically contrary to the game design.
