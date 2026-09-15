# Roadmap

## Phase 1: Repository foundation

**Status: Complete**

Exit criteria:

- pinned toolchain installs,
- Wally dependencies install,
- formatting/lint checks pass,
- pure-domain tests pass,
- Rojo place builds,
- canonical IDs/types/definitions exist,
- server/client bootstraps load,
- architecture and MVP boundaries are documented.

## Phase 2: Economy primitives

**Status: Complete**

Implemented inventory balances, currency balances, cost validation, atomic resource removal/addition, starter profile construction, profile schema validation, and migration tests.

Exit criteria are satisfied when resource transactions cannot create negative balances and all mutation APIs return explicit domain results.

## Phase 3: Creature ownership

**Status: Complete**

Implemented owned creature instances, generated IDs, one-time starter Rockhorn grant, capture ownership handling, capture eligibility gating, and work-assignment eligibility validation.

Phase 3 deliberately validates assignment without mutating the creature/building relationship. The two-sided worker assignment mutation is implemented in Phase 4.

Exit criteria are satisfied: a server-owned profile can gain a Rockhorn and invalid or duplicate ownership mutations are rejected with explicit domain results.

## Phase 4: Building and production loop

**Status: In verification**

Implemented pure server-authoritative domains for:

- 4-stud grid placement inside inclusive +/-64-stud plot bounds,
- canonical construction costs and server-generated building instance IDs,
- same-origin collision rejection,
- atomic two-sided creature/building worker assignment and unassignment,
- deterministic elapsed-time production claims,
- summed canonical creature work affinities,
- three production levels using multipliers 1.0 / 1.25 / 1.6,
- canonical production-building upgrade costs,
- processing input consumption through atomic inventory exchange,
- claim-versus-settlement semantics for rate changes,
- an 8-hour offline-production cap.

The deterministic acceptance chain is:

```text
Rockhorn -> Mine -> Copper Ore -> Furnace + Embercub -> Copper Bar
```

Phase 4 is complete only when the registered end-to-end acceptance spec and the full formatting, lint, Lune, and Rojo validation gate pass on the exact final branch head.

## Phase 5: Playable vertical slice

Implement the first exploration zone, gathering interactions, the six initial creatures, eight structures, UI, tutorial flow, persistence, and one complete progression path.

Exit when a new player can progress from manual gathering to a functioning creature-powered automated empire without developer intervention.

## Phase 6: Social validation

Add plot visiting and only the social systems justified by playtesting.

## Later specifications

Breeding/genetics, mutations, combat expansion, trading, marketplace, guilds, seasons, monetization expansion, creator tools, AI-assisted creation, and UGC publishing each require their own design and implementation plan.
