# Economy

## Economic objective

The economy should make creature acquisition and empire improvement reinforce each other. Resources exist to create decisions and progression, not to inflate into meaningless trillions during the tutorial.

## Initial currencies

The profile schema reserves:

- Coins: standard earned currency.
- Gems: premium/special currency reserved for later monetization and rewards design.

Neither currency has implemented mutation logic in the foundation scaffold.

## Initial resources

- Wood
- Stone
- Copper Ore
- Copper Bar
- Food
- Energy

Static building costs live in `src/shared/Buildings/BuildingDefinitions.luau` so the server can later validate transactions against one canonical source.

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

## Monetization principles

The MVP must be enjoyable without purchases. Early monetization should favour cosmetics, clearly bounded convenience, account/social features, and private-world features. Extreme production multipliers that turn useful creatures into a payment check are specifically contrary to the game design.
