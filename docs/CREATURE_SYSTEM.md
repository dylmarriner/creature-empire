# Creature System

## Principle

Every creature should have a useful role in the player's world. Species rarity alone is not a progression system.

## Species definitions

Species use stable IDs and shared static definitions. The first six are:

| ID | Name | Element | Primary work |
| --- | --- | --- | --- |
| `creature_rockhorn` | Rockhorn | Earth | Mining |
| `creature_embercub` | Embercub | Fire | Smelting |
| `creature_mossling` | Mossling | Nature | Farming |
| `creature_voltfox` | Voltfox | Electric | Power |
| `creature_timberpaw` | Timberpaw | Nature | Logging |
| `creature_aquafin` | Aquafin | Water | Water work |

The current definitions give each species a 1.25 affinity multiplier for its primary work role. Balance values are expected to evolve through playtesting; IDs must remain stable once persisted.

## Owned instances

The initial persisted creature shape contains:

- unique instance ID,
- species ID,
- level,
- experience,
- trait IDs,
- optional mutation ID,
- optional assigned building ID.

Genetics are deliberately absent from schema version 1. Breeding has not been designed deeply enough to justify permanently shaping stored data around guesses.

## Assignment

Later assignment logic must verify:

- the player owns the creature,
- the player owns the target building,
- the creature is not assigned elsewhere,
- the building has worker capacity,
- the work role is supported,
- the request is server-validated.

## Future systems

Breeding, inherited genetics, mutations, combat builds, trading value, and creature marketplace behaviour are later specifications. They must extend the ownership model without changing stable species identity.
