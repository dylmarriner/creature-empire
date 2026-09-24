# Economy

## Economic objective

The economy should make creature acquisition and empire improvement reinforce each other. Resources exist to create decisions and progression, not to inflate into meaningless trillions during the tutorial.

All numbers below live in `src/shared/Config/GameConfig.luau`, `src/shared/Items/ItemDefinitions.luau` and `src/shared/Buildings/BuildingDefinitions.luau`. Balance is expected to change through playtesting; IDs are stable.

## Currencies

- **Coins**: earned from objectives and selling resources; spent on building upgrades.
- **Gems**: present in the schema and validated, but with no sources or sinks yet. Reserved for a later, separately designed monetization/reward plan.

Currency operations accept only `coins` and `gems`, require finite positive integer amounts and reject insufficient balances without mutation.

## Resources

| Item | Sources | Sinks | Sell price |
| --- | --- | --- | --- |
| Wood | trees (3 per chop), Lumber Mill | construction, upgrades | 1 |
| Stone | rocks (3 per break), Mine | construction, upgrades | 1 |
| Copper Ore | Mine | Furnace input, Furnace cost | 2 |
| Copper Bar | Furnace | Generator cost | 6 |
| Food | Farm | Creature Habitat cost | 2 |
| Energy | Generator | upgrades to level 3+ | 3 |

Inventory keys must be canonical item IDs; balances are finite non-negative integers; zero balances are removed from the map. Multi-resource costs are validated in full before anything is deducted.

## Storage

Each resource has a storage limit: **200 + 300 per Warehouse level**. Production and gathering never raise a balance above the limit. Refunds and rewards may, so the limit caps income rather than confiscating owned resources.

## Buildings

| Building | Cost | Footprint | Max | Work | Workers | Cycle | Per cycle |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Mine | 20 Wood, 30 Stone | 3×3 | 4 | mining | 2 | 6/min | +1 Copper Ore, +1 Stone |
| Lumber Mill | 30 Wood, 10 Stone | 3×3 | 4 | logging | 2 | 8/min | +1 Wood |
| Farm | 25 Wood, 5 Stone | 4×4 | 4 | farming | 2 | 6/min | +1 Food |
| Furnace | 50 Stone, 15 Copper Ore | 3×3 | 3 | smelting | 1 | 4/min | −1 Copper Ore, +1 Copper Bar |
| Generator | 30 Stone, 20 Copper Bar | 2×2 | 3 | power | 1 | 5/min | +1 Energy |
| Warehouse | 80 Wood, 40 Stone | 4×3 | 2 | — | — | — | +300 storage per level |
| Creature Habitat | 60 Wood, 30 Stone, 20 Food | 4×4 | 3 | — | — | — | +4 creature capacity per level |
| Workbench | 30 Wood, 20 Stone | 2×2 | 1 | — | — | — | unlocks upgrades |

A building request names only the definition and a placement. The server looks up the canonical cost and deducts it atomically.

Removing a building settles its production, releases its workers and refunds **50%** (floored) of its base cost. Upgrade spending is not refunded.

## Upgrades

Upgrades require a Workbench and raise a building to at most level 5. The cost of reaching level `L`:

- items: each base-cost item × 1.6^(L−1), rounded up,
- energy: 10 × (L − 2) from level 3,
- coins: 40 × (L − 1)².

For example the Mine costs 32 Wood, 48 Stone and 40 coins for level 2, and 52 Wood, 77 Stone, 10 Energy and 160 coins for level 3.

Production buildings gain +50% output per level above 1. Warehouses and Habitats scale their bonus by level.

## Production

Production is elapsed-time simulation in whole recipe cycles:

```text
cycles per minute = building cyclesPerMinute
                  × (1 + 0.5 × (building level − 1))
                  × Σ over workers (species affinity × (1 + 0.05 × (creature level − 1)))
```

A production building with no workers is idle. Claims (`ProductionDomain.settle`) are server-calculated:

- elapsed time is `now − lastClaimedAt`, capped at 8 hours (28,800 seconds);
- whole cycles are floored; the clock advances only by the time those cycles took, so frequent claims never lose fractional progress and can never out-produce one long claim;
- cycles are limited by available inputs and by free storage for every output; when limited, the building was effectively idle and its clock resets to now instead of banking time;
- time beyond the offline cap is discarded;
- assigned workers gain one experience point per cycle.

Claim-all settles extractors before processors, so ore mined during the same claim can be smelted.

Assigning, unassigning, upgrading or removing a building first settles it at its old rate.

## Market

`SellResource` converts resources to coins at the canonical sell price above. The client sends only the item and quantity (1–100,000); prices never come from the client.

## Objectives

A 19-step objective chain (`src/shared/Progression/ObjectiveDefinitions.luau`) teaches the loop and pays 10–100 coins per step, 705 coins in total. Objectives complete strictly in order and are derived from profile state, so completion never depends on client-reported events. Rewards are granted once, inside the same transaction as the action that satisfied them.

## Monetization principles

The MVP must be enjoyable without purchases. Early monetization should favour cosmetics, clearly bounded convenience, account/social features, and private-world features. Extreme production multipliers that turn useful creatures into a payment check are specifically contrary to the game design. No monetization is implemented in this milestone.
