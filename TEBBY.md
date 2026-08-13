# TEBBY.md - pickle_slapboxing

## Overview

`pickle_slapboxing` is a FiveM resource (Lua, `fx_version "cerulean"`, GTA5) that implements a 1v1 slap-boxing minigame. Players place a physical prop (a slap table) in the world using an inventory item, sit on opposite sides, charge up slaps by button-mashing, and deal damage to their opponent via an ox_lib skill check. Spectators can watch a live health-bar HUD and bet money on either fighter. Supports ESX, QBCore, and a standalone stub for custom frameworks. Requires `ox_lib`.

## Code design

### Architecture

The resource is split across three layers:

| Layer | Folder / files | Role |
|---|---|---|
| **Config** | `config.lua` | All tunable values: slap timing, damage, skill-check sizes, item-to-table mapping, table models/offsets |
| **Bridge** | `bridge/esx/`, `bridge/qb/`, `bridge/standalone/` | Framework abstraction; each sub-folder has `client.lua` and `server.lua`; the right pair loads based on `GetResourceState` guards at the top of each file |
| **Modules** | `modules/table/`, `modules/match/`, `modules/display/` | Actual gameplay logic split into client and server scripts |
| **Core** | `core/shared.lua`, `core/client.lua` | Shared utility functions (`v3`, `GetRandomInt`, `CreateProp`, `PlayAnim`, `CreateBlip`, etc.) |
| **Locales** | `locales/locale.lua`, `locales/translations/*.lua` | `_L(key, ...)` helper + translation tables keyed by language code |
| **NUI** | `nui/index.html`, `nui/assets/` | Minimal health-bar HUD shown to spectators during an active match; driven by `SendNUIMessage` |

### Main flows

1. **Table placement** (`modules/table/server.lua`): A player uses the `slaptable` inventory item → `RegisterUsableItem` callback fires → `lib.callback.await('pickle_slapboxing:requestPlayerData')` fetches player position/heading from client → `CreateTable()` builds a data record stored in `SlapTables` (a server-side Lua table) and synced to all clients via `GlobalState.SlapTables`.

2. **Joining / match loop** (`modules/table/client.lua`, `modules/match/client.lua`): The client proximity thread (`modules/table/client.lua`) iterates `GlobalState.SlapTables` every tick, spawns/removes prop entities, draws markers at `home`, `away`, and `menu` interaction points, and fires server events when a player interacts. The server event `pickle_slapboxing:joinMatch` teleports the player to their seat position and starts `MatchThread`.

3. **Slap resolution** (`modules/match/client.lua` + `modules/match/server.lua`): The slapping player runs an `ox_lib` progress circle (button-mashing phase) followed by a `lib.skillCheck`. The press count (capped at `Config.Slapping.MaxPresses`) is sent to the server as `presses`, converted to a `power` ratio (0–1), multiplied by `Config.Slapping.MaxDamage`, and subtracted from the opponent's stored `health`. If health drops ≤ 0, `EndMatch` is called which pays bettors, optionally kills the loser (`Config.Slapping.DeathChance`), and resets the table's data.

4. **Betting** (`modules/table/client.lua` menu → `modules/match/server.lua`): Bets are stored per-table in `SlapTables[index].bets.home` and `SlapTables[index].bets.away`. Payout is proportional share of the losing pool, distributed after the match ends.

5. **NUI scoreboard** (`modules/display/client.lua`): A `DisplayHandler` function toggles the HUD on/off based on whether the local player is within 10 m of an active match. `pickle_slapboxing:updateStats` events update the health bars in real time.

### GlobalState sync pattern

All table state lives in the server-side `SlapTables` Lua table. After every mutation the server does `GlobalState.SlapTables = SlapTables`. Clients read `GlobalState.SlapTables` directly — there is no per-client callback sync; the built-in FiveM `GlobalState` replication is the only sync mechanism.

## Important files

| Path | Why it matters |
|---|---|
| `fxmanifest.lua` | Resource manifest; declares `fx_version`, script load order, NUI page, and file globs |
| `config.lua` | All operator-tunable settings: damage numbers, timings, table models, item-to-table mapping, `CanRemoveTable` policy |
| `core/shared.lua` | Shared helper functions (`v3`, `GetRandomInt`) used by both client and server |
| `core/client.lua` | Client utility functions (`CreateProp`, `PlayAnim`, `CreateBlip`, `PlayEffect`, etc.) |
| `locales/locale.lua` | `_L()` helper; missing keys return `ERR_TRANSLATE_<name>_404` |
| `locales/translations/en.lua` | Default (English) locale; the source of truth for all string keys |
| `bridge/esx/client.lua` | ESX client bridge (`ShowNotification`, `ShowHelpNotification`, `CanAccessGroup`, etc.) |
| `bridge/esx/server.lua` | ESX server bridge (`AddItem`, `RemoveItem`, `Search`, `RegisterUsableItem`, etc.) |
| `bridge/qb/client.lua` | QBCore client bridge |
| `bridge/qb/server.lua` | QBCore server bridge |
| `bridge/standalone/client.lua` | Fallback stub — prints a warning if neither ESX nor QBCore is found |
| `bridge/standalone/server.lua` | Fallback stub (same guard) |
| `modules/table/server.lua` | Table creation/destruction, usable item registration, `GenerateTableData`, `DestroyTable` |
| `modules/table/client.lua` | Client proximity loop, entity spawning/removal, marker rendering, interaction dispatch |
| `modules/match/server.lua` | Match start/end, slap resolution, payout/refund logic, `playerDropped` cleanup |
| `modules/match/client.lua` | Slap charging loop, skill check, animation events, match camera |
| `modules/display/client.lua` | NUI health-bar toggle and update logic |
| `nui/index.html` | NUI markup for the spectator HUD |
| `nui/assets/js/main.js` | NUI JS — handles `toggleUI` and `updateStats` messages from Lua |
| `_INSTALL/Items/ox_inventory.lua` | ox_inventory item definition for `slaptable` (must be added manually) |
| `_INSTALL/Items/esx_limit.sql` | ESX item SQL (weight-based variant also available) |
| `_INSTALL/Items/qbcore.lua` | QBCore shared item definition |

## Intended behaviors

- **`Config.CanRemoveTable` ownership check** (`config.lua`): By default, only the player who placed the table (`source == data.source`) may remove it. This is deliberate — the function is fully exposed so servers can customise the policy, but the default intentionally prevents other players from picking up someone else's table.

- **Anti-cheat power clamp** (`modules/match/server.lua`, `pickle_slapboxing:attemptSlapPlayer`): If `power > 1.0` the server clamps it to `1.0`. If `power > 2.0` (clearly impossible via legitimate mashing — would require `presses > 2 * MaxPresses`) the server sets `power = 0.01` ("the weakest slap of all time"). This is an intentional punishment for macro/exploit attempts and is **not** a bug.

- **`MinPressDist` randomisation** (`config.lua`): `Config.Slapping.MinPressDist = math.random(70, 80)` is evaluated once at resource start and stays constant for that session. This is intentional to make macro detection slightly unpredictable between restarts.

- **Bridge early-return guards**: Each bridge file checks `GetResourceState(...)` at the top and returns immediately if the framework isn't started. All three bridge pairs load in the manifest glob (`bridge/**/client.lua`); only the correct one will execute past its guard. This is by design — not dead code.

- **`table_already_placed` locale key exists but is never triggered in the current code**: The string is defined in all translation files but no server-side check enforces a one-table-per-player limit. This appears to be a planned (but unimplemented) feature remnant, not a bug in the enforcement logic.

- **QBCore bank balance comments**: `bridge/qb/server.lua` contains `-- If anyone knows how to get/add/remove bank balance for QBCore, let me know.` on the `bank` branch. These branches fall back to `cash`. This is a known limitation documented by the author, not a bug.

- **`serverID` in table menu** (`modules/table/client.lua`, `TableMenu`): The variable `serverID` is used to check whether the local player already has a bet. This variable is expected to be provided by the framework bridge (e.g. `GetPlayerServerId(PlayerId())`); its absence would cause a nil error. If it is not defined in the active bridge, that is a bridge implementation gap, not a core logic bug.

## Common issues & fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| Locale strings show as `ERR_TRANSLATE_<key>_404` | `Config.Language` doesn't match a translation file key, or the resource folder was renamed | Set `Config.Language = "en"` (or correct key); ensure resource folder is named `pickle_slapboxing` exactly |
| Table item does nothing when used | Item not registered in inventory (`_INSTALL/Items/`) or `ox_lib` not started before the resource | Import the correct `_INSTALL/Items/` file for your inventory; check `server.cfg` start order (`ox_lib` first) |
| Players can remove each other's tables | `Config.CanRemoveTable` default only allows the placer — if overridden incorrectly, anyone can remove | Review the `CanRemoveTable` function in `config.lua`; restore the `source == data.source` check |
| Match ends instantly on join | Player drops or disconnects during a match → `EndMatch` is triggered by `playerDropped`; also fires if health is already ≤ 0 in `GenerateTableData` (it initialises at `Config.Slapping.DefaultHealth`) | Confirm `Config.Slapping.DefaultHealth` is a positive number (default `100`) |
| Bet payout produces 0 or NaN | Bet placed but `totals.win` is 0 (no winning side had bets) — `PayoutMatch` divides by `totals.win` | Ensure at least one player bets on the winning side; the division-by-zero case is a latent bug when the winning pool is empty |
| NUI health bar not showing for spectators | Player is > 10 m from the table, or `DisplayHandler` isn't updating because `GlobalState.SlapTables` sync lags | Move closer; if persistent, check `ox_lib` version compatibility |
| Framework bridge not loading | Folder/resource name wrong, or `es_extended`/`qb-core` resource name differs from expected | Bridge guards use `GetResourceState('es_extended')` and `GetResourceState('qb-core')` — your framework resource must have exactly these names |
| `serverID` is nil / menu errors | The variable is referenced in `modules/table/client.lua` but is not defined in any current bridge file | Define `serverID = GetPlayerServerId(PlayerId())` in the relevant bridge client file or at the top of `modules/table/client.lua` |

## Conventions

- **Lua 5.4** (`lua54 'yes'` in manifest) — use Lua 5.4 syntax; bitwise operators and `<const>` are available.
- **Naming**: functions are `PascalCase` (`CreateTable`, `EndMatch`, `SlapPlayer`); local variables are `camelCase` or `snake_case`; config keys are `PascalCase` under the `Config` global.
- **Events**: all net events are prefixed `pickle_slapboxing:` (e.g. `pickle_slapboxing:attemptSlapPlayer`). Keep this prefix on any new events.
- **Bridge pattern**: every framework-specific function must have the same signature across all bridge files. Client bridges provide: `ShowNotification(text)`, `ShowHelpNotification(text)`, `ServerCallback(name, cb, ...)`, `GetPlayersInArea(coords, radius)`, `CanAccessGroup(data)`. Server bridges provide: `ShowNotification(target, text)`, `Search(source, name)`, `AddItem(source, name, amount)`, `RemoveItem(source, name, amount)`, `RegisterUsableItem(name, cb)`, `RegisterCallback(name, cb)`, `CanAccessGroup(source, data)`, `GetIdentifier(source)`.
- **GlobalState sync**: after mutating `SlapTables` on the server, always re-assign `GlobalState.SlapTables = SlapTables` to push the change to all clients.
- **Locale keys**: all player-facing strings go in `locales/translations/en.lua` (and sibling locale files). Never hardcode display strings in module files. Missing keys produce the `ERR_TRANSLATE_*_404` sentinel — watch for these in testing.
- **No persistent storage**: this resource has no database. All table/match state is in-memory (`SlapTables`) and lost on resource restart. This is intentional — tables placed before a restart will be gone.
- **Script load order** (from `fxmanifest.lua`): shared scripts load first (`ox_lib init`, `config.lua`, `locales`, `bridge/**/shared.lua`, `core/shared.lua`), then client/server scripts. Any new shared utility must go in `core/shared.lua` or a `*/shared.lua` file, not in a client/server-only file.
