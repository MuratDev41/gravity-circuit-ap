# Changelog

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
