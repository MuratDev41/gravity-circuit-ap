# Development Notes

Technical notes on how the randomizer hooks into Gravity Circuit 1.2.2 (Steam build 2026-05-31).

## The game

- `GravityCircuit.exe` is a fused LÖVE 11.4 executable: the game's Lua source is a zip appended to the exe and runs
  on LuaJIT. Nothing in the install is modified by this project.
- The save folder is `%APPDATA%\Gravity Circuit\` (LÖVE identity "Gravity Circuit"). Saves are `profile\slotN.sav`
  (base64 of bitser) and are synced by Steam Auto-Cloud.
- Map files (`content/maps/*.gcl`) are base64-encoded bitser data; `tools/bitser.py` decodes them.

## Loading the client

`conf.lua` sets `t.appendidentity = false`, so LÖVE searches the save folder before the game source. The client's
`main.lua`, installed into the save folder, therefore runs instead of the game's. It loads `archipelago/*` and then
runs the original `main.lua` by briefly switching the identity to append mode.

The game reassigns `love.update` and `love.draw` while booting (`__loadStaticCode` → `__initialAssetLoad` →
`__update`), and its run loop (`lua/libs/tick/tick.lua`) looks them up every frame. The client keeps the real
callbacks in a side table and serves wrappers through a metatable on `love`. Game hooks are installed lazily, once
the globals they patch exist.

## Networking

The client talks to the Archipelago server directly. WinHTTP's WebSocket API (through the LuaJIT FFI) provides
`ws://` and `wss://`. It runs in two `love.thread`s, because WinHTTP allows one send and one receive in flight and
receives block. The reader owns the receive loop; the writer sends queued frames and is the only thread that frees
the handles. Without a scheme, `wss` is tried first and then `ws`, like the official clients.

WinHTTP cannot negotiate `permessage-deflate`, so the server logs a compression warning. Connections still work.

## Game internals used

| Area | Detail |
|---|---|
| Stages | `MapData.OFFICIAL_MAPS`: OPTIC, PATCH, COOLER, ELEC, SHIFT, WAVE, BREAK, CIPHER, FINAL_1–3, OPENING, HUB |
| Boss clears | `BOSS_CLEAR_FLAGS.kai[0..11]`, set by `missionCompleteScreen` |
| Fortress | appears when `GAMEDATA.progressFlags.bossesCleared() >= 8`; 9 adds Fortress 2 and 10 adds Fortress 3. The client reports a higher count to the stage select while the Fortress is open, and 10 under `fortress_access` |
| Boosters | `GAMEDATA.increaseMaxHealth/Burst` set `HEALTH/BURST_BOOSTER_PICKUP_<STAGE>`; `countBoosterPickups` recomputes max stats |
| Rescues | `GAMEDATA.addRescue` → `GAMEDATA.player.rescues[STAGE][1..8]` |
| Palette chips | `armor.unlockByPickup(n)`: 1–8 stages, 9 hub, 10 NG+ only (excluded) |
| Bursts | ids 1–20; `bossUnlock` puts two per boss on sale (`unlockToShopBasedOnStage`); `burstAttacks.unlock(id)` grants |
| Chips | ids 1–20 (2 = Air Jumper); researched with credits and rescue tokens; `chips.unlock(id)` grants |
| Money caches | `LARGE_PICKUP_BOX` / `SMALL_PICKUP_BOX`; runtime `self.ID` is the map object id |
| Data chips | `DataChip.collect` writes `GAMEDATA.player.dataChips[id]`; the MISC category is commented out in the game |
| Shop purchase | `shopScreen.dbCallback` → `item.unlock(id)`, then the dialogue runs `GIVE_EQUIP_UNLOCK` → `UI.equippableUnlockNotification`, which grants the item |

## Checks and items

- Checks are detected from save state where possible (boss flags, rescues, data chips), so progress made while
  offline is sent on the next connection. Boosters, palette chips, caches and shop slots are hooked at the moment of
  pickup or purchase.
- Item state is rebuilt from the full received list, so it is idempotent. One-shot effects (credits, traps, refills)
  are tracked as totals in the save.
- The game recounts rescue tokens on load as rescues minus the cost of owned chips, which is wrong once chips arrive
  as items. The client derives tokens as rescues + token items − tokens spent at the Nurse.
- Refills and the damage trap wait until Kai is playable in a stage (no hub, cutscene, dialogue, pause or game over).
- Under shopsanity, buying a slot swaps `item.unlock` for sending the check, and the single follow-up grant popup is
  skipped. Story gifts (Flying Strike, Energy Absorber) are unaffected.

## Logic

- Pickup sections come from map object positions against the stage's checkpoints (`tools/gen_money_caches.py` uses
  the same split).
- Data chip sources come from the NPC and boss scripts (`tools/gen_data_chips.py`). Rescue-gated hub NPCs also need
  one boss clear; Kernel's chip needs the Fortress 1 boss; the Researcher needs ten bosses cleared (all eight Circuit
  bosses plus Fortress 1 and 2, which under `fortress_access` means both Fortress Access items). Prim is always in
  the hub, because the ELEC rescue condition in `prim-bot-npc.lua` only shows the paint easel.
- Enemy chips are logical in any stage containing that enemy; variants are resolved from map object parameters.
- Nurse chips cost 64 tokens in total, one per rescue bot. Logic grants 8 tokens per enterable stage and places chips
  cheapest first.
- Seeds generated under a different game name are rejected by the client with `InvalidGame`.

## Tracker integration

- The client writes `gravity_circuit_stage_<team>_<slot>` (current map id) and `gravity_circuit_pos_<team>_<slot>`
  (`"MAPID,x,y"`, throttled) to data storage.
- The PopTracker pack watches both. It switches tabs with `UiHint("ActivateTab")`, follows Kai with
  `UiHint("Zoom <map>")` and `UiHint("Pan <map>")`, and highlights hinted locations from `_read_hints_<team>_<slot>`.
- PopTracker scales pins by the unzoomed fit scale only, so pins keep a fixed screen size. They are sized per map.
- The Universal Tracker regenerates from slot data (`ut_can_gen_without_yaml`) and does not roll starting stages.

## PopTracker maps

Stage maps are rendered by the game itself. When `archipelago/export_maps.flag` exists in the save folder,
`client/archipelago/mapexport.lua` loads every official map at the title screen, attaches its tilesets the way
`MapManager:fixLoadingDebug` does, draws each cell with `Map:drawCellLayer` onto a half-scale canvas and writes a PNG.
`tools/pt_maps.py` stitches, crops and scales the cells. Colours are unshaded, because the game recolours tiles with a
palette shader at runtime. These images are derived from the game and must not be redistributed.

## Limitations

- Windows only (WinHTTP).
- Master Levels (remix maps), Circuit Mode, Boss Rush and NG+ are not supported.
