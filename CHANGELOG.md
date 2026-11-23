# Changelog

## 1.0.0
- Knockback Link (`knockback_link` in the YAML, or the F9 panel): getting knocked back by a hit knocks back
  everyone with Knockback Link, in the same direction. A received knockback staggers Kai like a hit but takes no
  health. One per second each way.
- Burst Link (`burst_link` in the YAML): the base burst bar, the first 2 bursts, is shared with your team.
  `gravity_circuit` shares it with other Gravity Circuit players, `silk_link` with Silksong's Silk Link
  (1 burst = 4 Silk). Bursts from Burst Boosters stay your own. The F9 panel can override it.
- F9 panel redone: Connection and Settings sections, a Connect/Disconnect button, mouse support, and DeathLink,
  Knockback and Burst Link settings (Use YAML or a fixed choice) that apply right away.
- Shopsanity slots are coloured by item class, frame and background.
- Gravity Circuit's own items in the shops use the sprite database too. Items without a sprite show an
  Archipelago icon.
- Fixed chip-shop sprites showing dimmed before the chip was bought.

## 0.12.0
- WebSocket compression (`permessage-deflate`), so the server no longer warns about it.
- `wss://` works everywhere, including Linux / Steam Deck (Proton), through Schannel. The socket connection is
  now the default and WinHTTP the fallback.
- Data chip pickups, received filler items and traps no longer print a message.
- Shopsanity slots holding another game's item show that item's sprite, from KaitoKid's ArchipelagoUtilities
  asset database. Sprites are downloaded per game and cached in `archipelago\sprites\`.

## 0.11.0
- "Data Chip - Nega" now requires all 8 stage Access items. The chip is inside the HQ healing tube, which only
  opens after all 64 rescues.
- Item messages moved to the bottom left and use the game's font (smaller than the game's own text), coloured like
  the Archipelago text client. The connection line moved to the top; it hides a few seconds after connecting and
  shows again when disconnected, paused or with F9 open.
- Shopsanity: the shop's description box shows what the selected slot sends and to whom.
- Money cache pickups and applied refills no longer print a message.
- Fixed checkpoint refills not filling the new segment after receiving a Burst Booster.
- Clearer connection errors. Pasted addresses are cleaned up, and a bad address or a refused connection no
  longer retries forever.
- Server messages are decoded off the main thread, data packages are cached, and the log is written in batches,
  to cut down on hitches.
- Linux / Steam Deck (Proton): falls back to LuaSocket (ws:// only) when WinHTTP websockets are unavailable.
  `install.sh` installs the mod into the Proton prefix.
- PopTracker (pack 0.7.0): hub NPC data chips show as Inspect until the rescue that brings the NPC to HQ is checked.

## 0.10.1
- Rescue Token items are progression when shopsanity is on, and the Nurse's shop logic counts them on top of the
  tokens from rescue bots. The PopTracker pack tracks them.

## 0.10.0
- New option `fortress_access` (off by default): Fortress 1 and Fortress 2 are opened by "Fortress 1 Access" and
  "Fortress 2 Access" items, and only Fortress 3 needs `bosses_required` Circuit bosses. The stage select shows all
  three Fortress stages and locks each one separately.
- The PopTracker pack tracks the new items and setting.
- Fixed generation failing when `money_caches` or `small_money_caches` is off (since 0.9.1).

## 0.9.2
- "Fortress 2 - Small Cache 11" and "Fortress 2 - Small Cache 12" now require the Air Jumper chip on Normal
  logic.

## 0.9.1
- "Highway - Money Cache 1" now requires the Air Jumper chip on Normal logic.

## 0.9.0
- Renamed the Archipelago game to "Gravity Circuit (MuratDev's Implementation)". Seeds generated under the old name
  must be regenerated.

## 0.8.1
- "Data Chip - Prim" no longer requires Power Plant Access and a boss clear; Prim is always in the hub.

## 0.8.0
- The client reports Kai's position; the PopTracker pack can zoom in and follow him.
- PopTracker pins are sized per map so they stay readable.

## 0.7.0
- PopTracker stage maps rendered by the game, with every check pinned at its real position.
- The client reports the current map; the PopTracker tab follows the player. Hinted locations are highlighted.

## 0.6.0
- Filler variety: 50–1000 Credits, Rescue Token, Health Refill, Full Health Refill, Burst Refill.
- Optional traps (`trap_chance`): Damage Trap (never lethal) and Credit Leak Trap.
- Fixed rescue tokens being lost on load under shopsanity.

## 0.5.0
- Shopsanity: every slot in Nega's burst shop and the Nurse's chip shop is a check. The shop shows what each slot
  sends, and progression items are hinted.

## 0.4.0
- Data chips as checks: NPC, boss and miniboss chips (`data_chips`) and enemy chips (`random_data_chips`).

## 0.3.0
- Small pickup boxes as checks (`small_money_caches`).

## 0.2.0
- Big money crates as checks (`money_caches`).

## 0.1.0
- Initial release: APWorld with stage regions and checkpoint subregions, and an in-game client that connects to the
  Archipelago server directly.
