# Gravity Circuit Archipelago: README and Install Guide

Version 0.9.2 · for Gravity Circuit 1.2.2 (Steam, Windows) · Archipelago 0.6.4 or newer

This zip contains:

| File | What it is |
|---|---|
| `gravity_circuit.apworld` | The Archipelago world. Whoever generates the multiworld needs it. |
| `Gravity Circuit.yaml` | Your player settings. Edit the name and options, then send it to the host. |
| `mod\` | The game mod. It goes into the game's save folder. |
| `Install Mod.bat` / `Uninstall Mod.bat` | Double-click to install or remove the mod. |
| `install.ps1` | The script the .bat files run. |

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
3. Start Gravity Circuit from Steam as normal. You should see `AP: Not connected | F9: connection` in the bottom-left corner.

If Windows says the script is blocked, right-click the zip → *Properties* → tick *Unblock* before extracting, then extract again.

## 4. Connect and play
1. In game, press **F9**.
2. Fill in:
   - **Server:** the address and port of the room, for example `archipelago.gg:38281`.
   - **Slot:** your slot name from the YAML.
   - **Password:** the room password, if any.
3. Press **Enter**. The bottom-left changes to `AP: Connected as <slot>`.
4. On the title screen, start a **NEW GAME in an empty save slot**. The message "This save is now linked to Archipelago slot …" appears.
   - Only that save takes part in Archipelago. Your normal saves are never changed.
     If you load one, the mod shows a warning and stays off for it.
5. Play. Checks are sent and items arrive as you go. The connection details are remembered, so next time the game reconnects on its own.

Useful to know:
- **Locked stages:** they play an error sound on the stage select and show "LOCKED" until you receive that stage's **Access** item. You start with at least one.
- **The Fortress:** opens after the number of Circuit bosses set in your YAML (`bosses_required`).
- **Goal:** beat the final boss in Fortress 3.
- **Shopsanity (on by default):** Nega's burst shop and the Nurse's chip shop sell checks instead of their usual items.
  - Highlight a slot to see what it sends and to whom, and whether it's progression, useful or a trap.
  - Opening a shop hints any progression items still for sale there.
  - Nega's boss bursts go on sale after that boss is beaten. The Nurse's chips cost rescue tokens and credits, as usual.
- **Filler items:**
  - 50 to 1000 Credits and Rescue Tokens (spend them at the Nurse) take effect immediately.
  - Health Refill, Full Health Refill and Burst Refill wait until you're in a stage, then apply one at a time.
- **Traps (optional, `trap_chance`):**
  - Damage Trap takes 8 HP but always leaves you at 1 HP or more.
  - Credit Leak Trap takes 250 credits.
- **Offline play:** you can play without a connection. Checks are kept in your save and sent the next time you connect.

## 5. Uninstall
Double-click **`Uninstall Mod.bat`**. Your saves and connection settings are kept.

## Troubleshooting
- **The overlay doesn't show up.** Make sure `%APPDATA%\Gravity Circuit\main.lua` exists, then run `Install Mod.bat` again.
- **"Could not connect".** Check the server address and port. `archipelago.gg` rooms change port when the room restarts.
- **"Connection refused: InvalidSlot".** The slot name must match the YAML exactly (it's case-sensitive).
- **"This save belongs to slot … of another seed".** You loaded a save from an older game. Start a new game in an empty slot.
- **Log file:** `%APPDATA%\Gravity Circuit\archipelago\ap_log.txt`. Include it when you report a problem.

## Known limitations
- Windows only.
- The server shows a warning that the client doesn't support websocket compression. It still works.
- The remixed "Master Levels", Circuit Mode, Boss Rush and NG+ aren't supported.

## Credits
- Gravity Circuit by Domesticated Ant Games. This package contains no game files: the mod loads your own copy of the game.
- Archipelago by the Archipelago team (https://archipelago.gg).
- APWorld and mod by Murat Kaan Tekeli.
