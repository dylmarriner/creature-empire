# Operations

How to take Creature Empire from this repository to a live Roblox experience and keep it healthy.

## One-time experience setup

1. Build the place: `rojo build default.project.json --output CreatureEmpire.rbxlx`, open it in Studio and publish it to a new experience (or `rojo serve` into an existing place).
2. **Game Settings → Security**: enable *Enable Studio Access to API Services* on the test place only if you want Studio sessions to read and write real DataStores. Without it, Studio uses a non-persistent in-memory store and logs a warning.
3. **Game Settings → Places → Max players**: 12–16 is recommended. Plots are laid out in rows of four and extend north as needed; the ground is sized for about 24 plots.
4. **Game Settings → Avatar**: any settings work; the game does not depend on avatar scale.
5. Keep a separate **test experience** for pre-release playtests so test data never touches the live DataStore.

## Release checklist

Run for every release:

1. CI is green on the release commit: formatting, lint, type-check, tests and Rojo build.
2. Publish to the test experience and complete the playtest checklist below with at least two players.
3. Confirm the server log shows `server started` with `memoryStore=false` on the test experience.
4. Publish to the live experience. Use *Shut down all servers* (or migrate to latest update) so every server runs one version.

## Playtest checklist

Each item should be verified in a live test server, not only in Studio:

- Joining shows the loading screen, then the HUD; a Rockhorn is granted once and the first objective is shown.
- Chopping trees and breaking rocks in the Wilds adds resources, respects the cooldown, and stops at the storage limit.
- Placing a Mine: the ghost follows the pointer, turns red on overlap or outside the plot, rotates with R, and the building appears where the ghost was. Repeat on a touch device using the on-screen buttons.
- Selecting a building opens its panel; assigning, unassigning, claiming, upgrading (after a Workbench) and removing all work and update the HUD.
- Capturing wild creatures succeeds and fails at roughly the listed chances, respects habitat capacity, and the creature respawns.
- The market sells at the listed prices.
- Leaving and rejoining (same and different server) restores everything; production accumulated while offline is claimable and capped.
- Home and Wilds travel buttons work.
- Rapid clicking produces `rate_limited` toasts rather than errors.

## Monitoring

Server logs are structured lines prefixed `[CreatureEmpire:<scope>]` with `key=value` context. Watch the Developer Console / error reports for:

| Log line | Meaning | Action |
| --- | --- | --- |
| `profile load refused status=invalid` | stored data failed validation; the player was kicked and the data left untouched | inspect the record, write an explicit migration or repair |
| `profile load refused status=error` | DataStore outage or budget exhaustion | check Roblox status; players can rejoin |
| `profile save failed` | a save exhausted its retries | investigate DataStore health; the next autosave retries |
| `session lock lost` | another server took over a profile | expected occasionally on fast server hops; frequent occurrences mean servers are slow to release |
| `action failed unexpectedly` | a domain bug threw or produced an invalid profile; the mutation was discarded | reproduce from the action name and fix |
| `repaired profile assignment references` | load-time integrity repair removed dangling references | expected to be rare; a trend points at a bug |
| `rejected client request` | malformed or rate-limited requests | a high count for one user suggests an exploit client |

Logs never contain profile contents or balances.

## Data requests

Roblox may forward *Right to Erasure* requests. Delete the player's record with the Open Cloud DataStore API (or in a Studio command bar with API access):

- universe: the live experience
- datastore: `PlayerProfiles_v1`
- key: `player_<userId>`

Records carry the user id as key metadata, which is what Roblox's tooling expects.

## Changing persisted data

- Balance changes to definitions and `GameConfig` need no migration as long as IDs are unchanged.
- Renaming or removing an item, species, building or objective ID requires a new schema version with an explicit, tested migration in `ProfileSchema.migrate`.
- Changing the stored record format requires bumping `RECORD_FORMAT` in `ProfileStore` with a reader for the previous format.

## Rollback

Publishing a previous place version rolls back code only. Data written by a newer version stays in place; the older version rejects any profile it cannot validate instead of overwriting it, so affected players are kicked with a support message until the newer version is restored. Avoid releases that change persisted data shape and gameplay at the same time.
