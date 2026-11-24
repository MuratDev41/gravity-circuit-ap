# Gravity Circuit Archipelago: README and Install Guide

Version 1.1.1 · for Gravity Circuit 1.2.2 (Steam; Windows, or Linux / Steam Deck through Proton) · Archipelago 0.6.4 or newer

This zip contains:

| File | What it is |
|---|---|
| `gravity_circuit.apworld` | The Archipelago world. Whoever generates the multiworld needs it. |
| `Gravity Circuit.yaml` | Your player settings. Edit the name and options, then send it to the host. |
| `mod\` | The game mod. It goes into the game's save folder. |
| `Install Mod.bat` / `Uninstall Mod.bat` | Double-click to install or remove the mod. |
| `install.ps1` | The script the .bat files run. |
| `install.sh` | The installer for Linux and Steam Deck (Proton). |

---

## 1. Install the APWorld (whoever generates the seed)
1. Install [Archipelago](https://github.com/ArchipelagoMW/Archipelago/releases) 0.6.4 or newer.
2. Double-click `gravity_circuit.apworld`, or copy it into `C:\ProgramData\Archipelago\custom_worlds\`.
3. Restart the Archipelago Launcher.

## 2. Make your player YAML
1. Open `Gravity Circuit.yaml` in a text editor.
2. Change `name:` to your slot name. Keep it 16 characters or fewer, with no spaces at the ends.
3. Change any options you like. Each option is explained in the file.
4. Send the YAML to whoever is hosting, or put it in `C:\ProgramData\Archipelago\Players\` and generate yourself.

## 3. Install the game mod (every Gravity Circuit player)
1. Close Gravity Circuit.
2. Double-click **`Install Mod.bat`**.
   - This copies `main.lua` and the `archipelago` folder into `%APPDATA%\Gravity Circuit\`.
   - The game files in Steam are **not** changed. Updating or verifying the game in Steam won't remove the mod.
3. Start Gravity Circuit from Steam as normal. You should see `AP: Not connected | F9: connection` at the top of the screen.

If Windows says the script is blocked, right-click the zip → *Properties* → tick *Unblock* before extracting, then extract again.

### Linux and Steam Deck (Proton)
1. Start Gravity Circuit from Steam once, so its Proton prefix exists, then close it.
2. In a terminal in the extracted folder, run `sh install.sh`.
   - It finds `steamapps/compatdata/858710/` in your Steam libraries and copies the mod into the game's save
     folder inside that prefix. If it can't find it, pass the folder yourself:
     `sh install.sh "/path/to/compatdata/858710/pfx/drive_c/users/steamuser/AppData/Roaming/Gravity Circuit"`.
3. Start the game from Steam as normal.

Enter the server address as usual; `wss://` works under Proton too. To remove the mod, run
`sh install.sh --uninstall`.

## 4. Connect and play
1. In game, press **F9**.
2. Fill in:
   - **Server:** the address and port of the room, for example `archipelago.gg:38281`.
   - **Slot:** your slot name from the YAML.
   - **Password:** the room password, if any.
3. Press **Enter**. The top line changes to `AP: Connected as <slot>`. Once connected, that line hides after a
   few seconds; it comes back while the game is paused, while disconnected, or with F9 open.
4. On the title screen, start a **NEW GAME in an empty save slot**. The message "This save is now linked to Archipelago slot …" appears.
   - Only that save takes part in Archipelago. Your normal saves are never changed.
     If you load one, the mod shows a warning and stays off for it.
5. Play. Checks are sent and items arrive as you go. The connection details are remembered, so next time the game reconnects on its own.

Useful to know:
- **Locked stages:** they play an error sound on the stage select and show "LOCKED" until you receive that stage's **Access** item. You start with at least one.
- **The Fortress:** opens after the number of Circuit bosses set in your YAML (`bosses_required`). With
  `fortress_access`, Fortress 1 and 2 are opened by their own Access items instead, and only Fortress 3 waits for the
  bosses. Only the 8 Circuit stage bosses count toward `bosses_required`; Fortress 1 and 2 don't.
- **Goal:** beat the final boss in Fortress 3.
- **Shopsanity (on by default):** Nega's burst shop and the Nurse's chip shop sell checks instead of their usual items.
  - Highlight a slot and the shop's description box says what it sends and to whom; the item name is coloured
    purple for progression, blue for useful, red for a trap and cyan for filler.
  - Opening a shop hints any progression items still for sale there.
  - Nega's boss bursts go on sale after that boss is beaten. The Nurse's chips cost rescue tokens and credits, as usual.
- **Filler items:**
  - 50 to 1000 Credits and Rescue Tokens (spend them at the Nurse) take effect immediately.
  - Health Refill, Full Health Refill and Burst Refill wait until you're in a stage, then apply one at a time.
- **Traps (optional, `trap_chance`; pick them with `enabled_traps`):** they wait until you're in a stage.
  - Damage Trap takes 8 HP but always leaves you at 1 HP or more.
  - Credit Leak Trap takes 250 credits.
  - Knockback Trap knocks you back like a hit, without damage.
  - Burst Drain Trap empties your bursts. With Burst Link, the shared ones stay.
  - Palette Trap changes every colour for 20 seconds; Pixelate Trap pixelates the screen for 15; Earthquake Trap
    shakes it for 8; Flip Trap turns it upside down for 10.
- **Data chip markers (`data_chip_markers`, on by default):** with `random_data_chips`, enemies whose chip check isn't
  done yet show an Archipelago icon above them.
- **Boss health (optional, `boss_health`):** bosses get random health per stage: `weak` 12-24, `strong` 36-48,
  `chaotic` 8-48 (vanilla is 32). The final boss keeps its own.
- **Music shuffle (optional, `music_shuffle`):** `shuffled` swaps stage themes among themselves and boss themes among
  themselves; `mixed` swaps them all together. Intros, jingles, the hub and the final boss themes stay.
- **Burst Link (optional, `burst_link`):** the first 2 bursts of your bar are shared with your team, so using one
  uses it for everyone and earning one gives it to everyone. Bursts from Burst Boosters stay your own.
  - `gravity_circuit`: shared with other Gravity Circuit players who also chose it.
  - `silk_link`: shared with Silksong players using Silk Link. One burst is 4 of the 9 Silk in their base spool.
- **Knockback Link (optional, `knockback_link`):** when a hit knocks you back, everyone with Knockback Link (in any
  game that supports it) gets knocked back the same way, and the other way round. A received knockback staggers
  Kai like a hit but takes no health.
- **Palette randomizer (optional, `palette_randomizer`):** recolours Kai (`kai`), or Kai, enemies, bosses and NPCs
  (`everything`), with hues picked from the seed. Stages and the HUD keep their colours.
- **F9 settings:** DeathLink, Knockback Link, Burst Link and the palette can follow your YAML or be set in the panel;
  auto-connect can be turned off. Both are saved in `archipelago\connection.json`.
- **Offline play:** you can play without a connection. Checks are kept in your save and sent the next time you connect.
- **Messages** appear in the bottom-left in the game's font, coloured like the Archipelago text client: your name in
  magenta, other players in yellow, items by class, locations in green.

## 5. Uninstall
Double-click **`Uninstall Mod.bat`**. Your saves and connection settings are kept.

## Troubleshooting
- **The overlay doesn't show up.** Make sure `%APPDATA%\Gravity Circuit\main.lua` exists, then run `Install Mod.bat` again.
- **"Nothing is accepting connections at …".** The port is wrong, or the server is down. `archipelago.gg` rooms get
  a new port when they wake up: reload the room page and copy the address again. For a server on someone's PC, they
  need to forward the port, and you need their public IP.
- **"Could not find the server …".** The host name has a typo.
- **"… did not answer in time".** A firewall or missing port forwarding is blocking you.
- **"There is no slot named …".** The slot name must match the YAML exactly (it's case-sensitive).
- **A bad address or a refused connection** stops automatic reconnecting; fix it with F9 and press Enter.
- **"This save belongs to slot … of another seed".** You loaded a save from an older game. Start a new game in an empty slot.
- **Log file:** `%APPDATA%\Gravity Circuit\archipelago\ap_log.txt` (on Linux, the same path inside the Proton prefix).
  Include it when you report a problem.
- **Force a connection method:** add `"transport": "socket"` (or `"winhttp"`) to
  `archipelago\connection.json`. The default, `"auto"`, uses sockets first and falls back to WinHTTP.

## Known limitations
- The remixed "Master Levels", Circuit Mode, Boss Rush and NG+ aren't supported.

## Credits
- Gravity Circuit by Domesticated Ant Games. This package contains no game files: the mod loads your own copy of the game.
- Archipelago by the Archipelago team (https://archipelago.gg).
- Shop sprites for other games' items: KaitoKid's ArchipelagoUtilities asset database
  (https://github.com/agilbert1412/ArchipelagoUtilities), downloaded when needed.
- APWorld and mod by Murat Kaan Tekeli.
