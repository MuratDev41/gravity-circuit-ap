# Gravity Circuit Archipelago

An [Archipelago](https://archipelago.gg) multiworld randomizer for **Gravity Circuit** (Steam, v1.2.2).

The game connects to the Archipelago server by itself. There is no external client and the game executable is never
modified: the client is loaded from the game's save folder.

- **Archipelago game name:** `Gravity Circuit (MuratDev's Implementation)`
- **Requires:** Archipelago 0.6.4+, Gravity Circuit 1.2.2 on Windows

## Features

- **Stage access:** the stage select is locked per stage until its Access item is found.
- **Regions:** each stage is split into checkpoint subregions that follow the game's checkpoint menu.
- **Checks:** up to 593 in total.
  - Bosses, rescue bots, boosters and palette chips (92 base).
  - Optional: big and small money caches, data chips, and shopsanity for Nega's and the Nurse's shops.
- **Items:** stage Access, boss Burst Techniques, booster chips (Air Jumper is progression), health and burst
  upgrades, armor paints, varied filler, and optional traps.
- **Overlay:** in-game connection panel (F9), message feed and check counter.
- **Shopsanity:** shops show what each slot sends and hint progression items.
- **Multiworld:** DeathLink, offline play (checks are sent on reconnect) and Universal Tracker support.
- **PopTracker pack:** real stage maps, autotracking, map following and hint highlighting.

## Repository layout

```
apworld/gravity_circuit/   Archipelago world (options, regions, rules, data)
client/                    In-game client, installed into %APPDATA%\Gravity Circuit\
  main.lua                 Loader that runs before the game's own main.lua
  archipelago/             Protocol client, game hooks, overlay, WinHTTP websocket
packaging/                 Files shipped in the release zip (installer, player guide, YAML template)
tools/                     Build script and generators for data, caches, data chips and the PopTracker pack
tests/                     Data consistency tests
docs/DEVELOPMENT.md        How the client hooks into the game
```

## Installing (players)

Download the release zip and follow its `README.md`. In short:

1. Add `gravity_circuit.apworld` to Archipelago's `custom_worlds`.
2. Run `Install Mod.bat`.
3. In game, press **F9**, enter the server, slot and password, then start a new game in an empty save slot.

## Building

Requires Python 3.10+.

```bash
python tools/build.py
```

This regenerates `client/archipelago/data.lua` and writes `dist/gravity_circuit.apworld` and
`dist/GravityCircuit-Archipelago-<version>.zip`.

To install the client from the repository for testing:

```bash
powershell -ExecutionPolicy Bypass -File packaging/install.ps1
```

### Regenerating game data

These generators read your installed copy of the game. Set `GRAVITY_CIRCUIT_EXE` if it isn't in the default Steam
location.

```bash
python tools/gen_money_caches.py
python tools/gen_data_chips.py
```

### PopTracker pack

The stage maps are rendered by the game:

1. Create an empty `%APPDATA%\Gravity Circuit\archipelago\export_maps.flag` file.
2. Start the game once. It exports all maps and closes itself.
3. Build the pack. It needs Pillow.

```bash
python tools/build.py --poptracker
```

The resulting pack contains images derived from the game, so keep it for personal use.

## Testing

```bash
python -m unittest discover tests
```

## Credits

Gravity Circuit is by Domesticated Ant Games. This project contains no game files. Developed by Murat Kaan Tekeli.

## License

[MIT](LICENSE) © 2026 Murat Kaan Tekeli. The license covers this project's code only. Gravity Circuit and its assets
belong to Domesticated Ant Games and are not covered by it.
