# Economy

## Economic objective

The economy should make creature acquisition and empire improvement reinforce each other. Resources exist to create decisions and progression, not to inflate into meaningless trillions during the tutorial.

## Initial currencies

The profile schema defines:

- Coins: standard earned currency.
- Gems: premium/special currency reserved for later monetization and rewards design.

Pure server-domain mutation logic now exists for both currencies. Currency operations accept only the canonical `coins` and `gems` IDs, require finite positive integer amounts, reject insufficient balances without mutation, and distinguish unknown currencies from insufficient funds.

These pure mutations are not yet exposed directly to clients and are not yet backed by a production DataStore service.

## Initial resources

- Wood
- Stone
- Copper Ore
- Copper Bar
- Food
- Energy

Inventory mutation logic validates item IDs against `src/shared/Items/ItemDefinitions.luau`. Add/remove operations require finite positive integer quantities and cannot drive balances negative. Zero balances are removed from the persisted inventory map.

Multi-resource costs are atomic: the complete cost is validated and checked for affordability before any resource is consumed. A failed cost therefore cannot leave the player with a half-completed transaction.

## Canonical building costs

Static building costs live in `src/shared/Buildings/BuildingDefinitions.luau` and are consumed through `BuildingCostDomain`.

A building-purchase request identifies the building definition only. The server-side domain looks up the canonical cost itself and delegates the deduction to the atomic inventory-cost operation. Callers do not provide authoritative prices or resource deductions.

For example, `building_mine` currently costs exactly:

- 20 Wood
- 30 Stone

If the player cannot afford the complete cost, nothing is deducted.

## Production

Production is elapsed-time simulation:

```text
output = base rate per minute
       × building multiplier
       × worker multiplier
       × trait multiplier
       × elapsed minutes
```

Output is server-calculated. The current pure math floors fractional output to a non-negative integer and rejects negative, NaN, or infinite inputs.

Offline elapsed time is capped at 8 hours (28,800 seconds).

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

Implemented pure domain behavior:

- profile currency defaults and validation,
- inventory add/remove,
- atomic resource costs,
- Coins/Gems add and spend,
- canonical building-cost affordability and purchase checks.

Not yet implemented:

- DataStore-backed profile persistence,
- session locking/ownership,
- Roblox-facing `InventoryService` / `EconomyService`,
- remote request handlers,
- production reward claiming,
- building placement and ownership creation.

## Monetization principles

The MVP must be enjoyable without purchases. Early monetization should favour cosmetics, clearly bounded convenience, account/social features, and private-world features. Extreme production multipliers that turn useful creatures into a payment check are specifically contrary to the game design.
