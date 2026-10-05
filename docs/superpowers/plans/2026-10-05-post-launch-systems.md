# Post-Launch Systems Plan: Breeding, Combat, Monetization, Trading, Marketplace, Guilds

**Goal:** add the six systems the roadmap defers (phases 7–13) without breaking the invariants the first release is built on: one server-authoritative mutation path, pure testable domains, session-locked profiles, and "never overwrite known-good data".

**Status:** proposed. Nothing here is implemented. Open questions are at the end and need an owner decision before the phases that depend on them.

## Constraints from the existing design

- **Every rule is a pure shared domain** invoked through `ActionService` → `ActionPipeline` (copy → mutate → objectives → schema validation → commit). New systems follow this; engine code is a thin adapter.
- **Persisted shape changes are the dangerous part.** `OPERATIONS.md` notes an older build rejects profiles it cannot validate, so a rollback after a schema bump kicks players. Therefore **all new profile fields are added in one migration (schema v2) that ships alone**, before any gameplay uses them.
- **The profile pipeline is single-player.** Trading, the marketplace and guilds touch more than one player or shared state, which the pipeline cannot do atomically. They need the shared ledger and guild store described below, not extensions of the profile pipeline.
- **Already reserved in v1:** `creature.traits`, `creature.mutationId`, `currencies.gems`, a `building.kind` field, and the `unlocks` map. Breeding and monetization build on these instead of replacing them.

## Delivery order and dependencies

| Phase | System | Depends on | Size |
| --- | --- | --- | --- |
| 7 | Schema v2 + migration + shared ledger and RNG foundations | — | Medium |
| 8 | Breeding and genetics | 7 | Large |
| 9 | Combat (PvE expeditions) | 7, 8 (genes feed stats) | Large |
| 10 | Monetization | 7 (receipt log); best after 8–9 so the catalog is known | Medium |
| 11 | Trading (player to player) | 7 (escrow + ledger) | Large |
| 12 | Marketplace | 11 | Very large |
| 13 | Guilds | 7 | Large |

Phases 11→12 are strictly sequential. Phase 13 is independent of 11–12 and can run in parallel with them. Each phase ends with its own playtest gate and ships separately; no phase is merged with a gameplay change that also alters persisted shape.

## Phase 7: Foundations

### Schema v2 (one migration for everything below)

```luau
-- CreatureInstance additions
genes: { vigor: number, might: number, focus: number },  -- integers 0..31
generation: number,                  -- 0 = wild/starter
lineage: { speciesA: string, speciesB: string }?, -- display only; parents may be released
bornAt: number,                      -- server Unix seconds

-- PlayerProfile additions
eggs: { [string]: Egg },             -- breeding (phase 8)
expeditions: { [string]: Expedition }, -- combat (phase 9)
escrow: { [string]: EscrowEntry },   -- items held out of play for an open transfer (11, 12)
receivedTransfers: { [string]: number }, -- transferId -> claimedAt; idempotent claims (11, 12)
purchases: { [string]: number },     -- receiptId -> processedAt, trimmed to the newest 200 (10)
passes: { [string]: boolean },       -- owned game passes (10)
guildId: string?,                    -- cache only; the guild record is the truth (13)
stats: { [string]: number },         -- counters for analytics and objectives
```

- `migrate` v1 → v2 is explicit, deterministic and idempotent. Existing creatures receive **fixed neutral genes (16/16/16)** and `generation = 0`, so launch players are neither advantaged nor punished. The new maps start empty.
- `ProfileIntegrity` gains repair rules: an egg or expedition referencing a missing creature is cleaned up; an escrow entry with no matching ledger record is **kept and flagged**, never deleted (it may hold a player's item).
- Tests: v1 fixtures migrate and validate; migrating twice is a no-op; a v2 profile is rejected by the v1 validator (documents the rollback hazard).
- **Release step:** ship this phase on its own, soak it for at least a week on live, and only then ship gameplay. Document in `OPERATIONS.md` that rollback below this build is unsupported.

### Shared infrastructure

- **`Util/SeededRandom`**: a small deterministic PRNG (splitmix/PCG) seeded from a stored integer. Breeding results and combat are pure functions of `(inputs, seed)`, so tests are exact and players cannot re-roll by leaving.
- **`Persistence/LedgerStore`**: a DataStore (`Transfers_v1`) of transfer records, written only via `UpdateAsync` with a compare-state transform. Pure state machine in `Transfers/TransferDomain`, adapter behind the same abstract `update(key, transform)` interface `ProfileStore` uses, so it runs against `MemoryStore` under Lune.
- **Anti-dupe transfer protocol** (used by trading and the marketplace):
  1. *Escrow:* the sender's profile moves the offered items into `profile.escrow[transferId]` in one validated, saved commit. Items now exist in exactly one place.
  2. *Publish:* the server writes `open` to the ledger (idempotent on `transferId`). If the process dies here, load-time reconciliation re-publishes the escrow entry or restores it.
  3. *Claim:* the recipient's profile adds the items and records `receivedTransfers[transferId]` in a saved commit. Only then does the server flip the ledger `open → claimed` (atomic; losing a race to `cancelled` aborts the claim before step 3 commits).
  4. *Settle:* the sender clears its escrow entry once the ledger says `claimed`, or restores it if the ledger says `cancelled`.
  A crash at any point leaves the item in escrow, in the ledger, or already claimed, never duplicated and never lost. The load-time reconciler repeats step 3's flip and step 4 until the ledger and profile agree.
- **`Config/FeatureFlags`**: per-system kill switches readable from a DataStore or MessagingService so trading, marketplace, breeding, or a store product can be disabled live without a publish.

## Phase 8: Breeding and genetics

**Rule:** creatures are workers first. Breeding is a way to improve workers, not a separate minigame.

- **New building `building_breeding_den`** (kind `breeding`, maxCount 1, upgrades add slots). Added via `BuildingDefinitions`; the definitions integrity test must be extended, because it currently requires every building to be a production building with a capable species.
- **Eligibility:** two creatures the player owns, both idle (not assigned or on an expedition), level ≥ 3, each off a 30-minute breeding cooldown, plus habitat capacity for the hatchling.
- **Egg creation is deterministic.** The pipeline stores `Egg { id, parentA, parentB (snapshots), seed, createdAt, hatchesAt }`. The result is computed at hatch from the stored seed and snapshots, so releasing a parent or leaving does not change it.
- **Genes:** each of the 3 genes comes from either parent (50/50), then ±0–2 drift, clamped to 0..31. Genes scale stats modestly: work output +0.5% per `vigor` point (max +15.5%, below the +25% species affinity), combat stats from `might` and `focus` (phase 9).
- **Species:** same-species parents → that species. Different species → a `HybridDefinitions` table of fixed recipes (for example Embercub × Voltfox → a new species) and otherwise a 50/50 pick of a parent. New species must have a work role, preserving the creature-system principle.
- **Mutation:** 3% base chance sets `mutationId` from `MutationDefinitions` (colour variant plus a small bonus). Mutation never makes a creature strictly better than a normal one at everything.
- **Costs and pacing:** coins plus resources, hatch times of 5–60 minutes by generation; gems may speed up hatching (phase 10). Coins and resources are sinks, so breeding also drains the economy.
- **Actions:** `StartBreeding { creatureIdA, creatureIdB }`, `HatchEgg { eggId }`. Eggs hatch on claim, like production, so offline eggs are ready on return.
- **UI:** Breeding Den panel (pick parents, preview gene ranges, egg timers), hatched-creature reveal, gene display on the creature panel.
- **Tests:** deterministic inheritance by seed, distribution checks over many seeds, ineligible parents, capacity, cooldowns, release-of-parent-after-egg, migration of genes onto v1 creatures.

## Phase 9: Combat (PvE expeditions)

**Scope decision:** asynchronous, server-simulated PvE. No PvP and no real-time player control in this phase, because both multiply exploit surface and need netcode the first release deliberately avoids.

- **Expeditions:** the player sends a party of 1–3 idle creatures to a Wilds encounter (tiered by player level). The creatures are **away** for the duration (10–60 minutes) and cannot work, so combat has a real cost against production.
- **Resolution:** a pure `CombatDomain.simulate(party, encounter, seed)` runs turn-based auto-battle: element advantage table across the five existing elements (earth, fire, nature, electric, water), stats from species base + level + genes, one species ability each. The result (win/lose, rounds, loot, XP, per-creature damage log) is computed when the expedition is claimed from the stored seed, so it is reproducible and cannot be re-rolled.
- **Outcomes:** wins grant rare resources, creature XP and coins; losses grant a small consolation and no creature is ever lost or permanently injured. Tier unlocks come from the objective chain (extended with combat objectives).
- **Why not PvP/real-time:** defer until playtest shows demand. Anything PvP adds matchmaking, anti-cheat and fairness work that belongs in its own spec.
- **Actions:** `StartExpedition { encounterId, creatureIds }`, `ClaimExpedition { expeditionId }`.
- **UI:** encounter list with element hints, party picker, expedition timers, battle-log replay on claim.
- **Tests:** simulation determinism, element matrix coverage, balance tests asserting each encounter tier is winnable by an appropriately levelled party and not by an under-levelled one, party eligibility, cannot assign or breed an away creature.

## Phase 10: Monetization

Roblox policy points to respect: purchases go through `MarketplaceService`; paid random rewards require disclosed odds, so **the plan has no paid randomness**; gems are non-tradable (phase 11) so the economy cannot become a currency-exchange route.

- **Gems** become a real currency. Sources: purchase, a few objective rewards. Sinks (proposed): extra plot expansion, extra Breeding Den slots, breeding/expedition speed-ups, cosmetics for creatures and plots.
- **Products** (the catalogue is an owner decision, see open questions): developer products for gem packs; game passes such as a larger creature capacity, a larger offline cap (8h → 12h) and a cosmetic bundle. Nothing sold grants stats that cannot also be earned.
- **Receipt handling** (`Services/PurchaseService`): `ProcessReceipt` must be idempotent and survive server hops. Grant inside the pipeline, record `purchases[receiptId]` in the same commit, **save**, and only then return `PurchaseGranted`. If the profile is not loaded or the save fails, return `NotProcessedYet`. A repeated receipt id returns `PurchaseGranted` without granting again.
- **Passes** are checked on join and cached in `profile.passes`; effects are read from the profile in the domains (offline cap, capacity), not from `MarketplaceService`, so they stay deterministic and testable.
- **UI:** shop panel, gem balance, purchase confirmation toasts. Prices come from Roblox, never from the client.
- **Analytics:** purchase funnel and gem source/sink events into `AnalyticsEvents`, with sink/source balance checked in tests.
- **Tests:** duplicate receipt, receipt before profile load, save failure, crash between grant and save (nothing granted twice), pass effect on offline cap.

## Phase 11: Trading

- **Scope:** player-to-player, both online. Tradable: resources, coins, creatures. Not tradable: gems, assigned or away creatures, creatures with an open egg or expedition, the last creature the player owns (matching the release rule).
- **Flow:** `TradeRequest` → the target accepts → each side adds offers → both lock → a short confirmation delay with the final contents re-displayed → both confirm. Any change after locking resets locks. The server owns the session; the client only sends intent.
- **Execution** uses the escrow/ledger protocol from phase 7 even when both players share a server. Settling is idempotent and reconciles after a crash on either side.
- **Safeguards:** account-age and playtime gate (proposed: 7 days or 2 hours played), max 20 items per side, coin-value sanity warning for very lopsided trades, per-player trade rate limit, daily value cap for new accounts, structured trade log (userIds, item ids, never chat) for support.
- **Actions:** `TradeRequest`, `TradeAccept`, `TradeSetOffer`, `TradeLock`, `TradeConfirm`, `TradeCancel`.
- **Tests:** full happy path, cancel at each step, one side disconnects mid-trade, profile load failure, crash simulation at every protocol step (run the transfer under fault injection and assert conservation of items), double-confirm, and an offered item removed from the profile mid-trade.

## Phase 12: Marketplace

- **Model:** coin-priced listings for resources and creatures, cross-server. Listing = a phase 11 ledger transfer that is open to anyone at a stated price. Buying escrows the buyer's coins, flips the listing `open → sold` atomically, then the buyer claims the item and the seller claims the coins through the same inbox protocol.
- **Coin sink:** 5% sale fee burned on sale, and a small listing fee, both configurable. Per-item price floors and ceilings (derived from `ECONOMY.md` sell prices) block wash trading and price manipulation.
- **Index:** a MemoryStore sorted map for browsing and search is a *cache*. The DataStore listing is the source of truth, and the index is rebuilt from it if lost. Listings expire after 48 hours and return to the seller's inbox.
- **Limits:** 10 active listings per player, rate limits on browse and buy, trade-eligibility gate from phase 11.
- **Budget:** DataStore and MemoryStore request budgets are the main risk. Browse results are paginated and cached per server for a short TTL, and the feature flag from phase 7 can disable it live.
- **Actions:** `ListItem`, `CancelListing`, `BuyListing`, `BrowseListings`, `ClaimInbox`.
- **Tests:** concurrent buyers on one listing (exactly one wins), buy vs cancel race, expiry return, seller offline when sold, buyer disconnect after payment, fault-injection conservation tests as in phase 11, price bounds.

## Phase 13: Guilds

- **Storage:** a separate `Guilds_v1` DataStore record (`UpdateAsync`) holds name, roster, roles, level and contribution totals. `profile.guildId` is a cache, and a mismatch is resolved in favour of the guild record on join.
- **Features:** create (coin cost; one guild per player), invite, join, leave, kick, promote/demote (leader, officer, member), 30 members to start.
- **Names and text:** guild names, tags and descriptions **must pass Roblox `TextService` filtering** before they are stored or shown, and are re-checked for display. Names are unique case-insensitively.
- **Progression:** members contribute resources to guild projects; completing projects levels the guild, which gives members a capped production bonus (proposed +1% per level, max +10%). The bonus is read into `ProductionMath` as an input, never trusted from the client.
- **Cross-server:** roster changes are best-effort pushed via `MessagingService`, with the DataStore as truth and refresh-on-open as the fallback.
- **Actions:** `GuildCreate`, `GuildInvite`, `GuildAccept`, `GuildLeave`, `GuildKick`, `GuildSetRole`, `GuildContribute`.
- **Tests:** role permission matrix, leader leaving with no successor, concurrent joins at capacity, kicked player's stale cache, name uniqueness races.

## Cross-cutting work

- **Remotes:** each action above gets a schema and rate limit in `ActionSchemas`; multi-party actions are *session* scope with handlers that touch the profile only through the pipeline.
- **Exploit review per phase:** every phase gets an adversarial pass before merge covering dupe attempts, rate abuse, malformed payloads and crash/rejoin timing.
- **Objectives:** extend the objective chain only with additive objectives that cannot make a returning player's current step regress.
- **Analytics and ops:** new events per system; `OPERATIONS.md` gains a section per phase (feature flags, ledger reconciliation, support tooling), and `scripts/player-data.luau` is extended to inspect escrow, inbox and purchases and to export a player's transfer history for support and erasure requests.
- **Docs:** update `README.md`, `ROADMAP.md`, `DATA_MODEL.md`, `ARCHITECTURE.md` and `ECONOMY.md` in the same PR as each phase.

## Verification per phase

`./scripts/validate.sh` (stylua, selene, type-check, Lune tests, Rojo build) plus the phase-specific specs above, then a test-experience playtest with at least two players, with phases 11–12 tested on **two servers** and with deliberate mid-trade disconnects.

## Open questions (need an owner decision)

1. **Monetization catalogue:** which gem pack sizes and prices, which game passes, and are the proposed gem sinks acceptable? Nothing in phase 10 can be built until this is set.
2. **Combat scope:** is PvE-only (no PvP) right for now?
3. **Trade eligibility:** keep the 7-day or 2-hour gate, or a different rule? Should marketplace fees be 5%?
4. **Staging:** ship the first release as it stands and add these phases after it, which is the recommendation here. Or hold the release until some of them are done?
5. **Creature trading:** tradable creatures with genes make rare creatures valuable and so a target for scams. Confirm creatures are tradable, or restrict the marketplace to resources at first.
6. **Hybrid species:** how many new species should breeding add, and who designs them? Each needs art, a work role and balance.
