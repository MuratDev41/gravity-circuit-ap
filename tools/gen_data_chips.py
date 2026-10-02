"""Generate apworld/gravity_circuit/data_chips.py from the game's data.

Data chips are the bestiary entries in content/data/collectibles/datachips.lua (45 enemy, 13 boss, 22 character;
the "misc" category is commented out in the game). Each chip is written with how it is obtained:

  ("boss",    STAGE)       dropped by the Circuit boss of STAGE
  ("region",  REGION)      obtained in a fixed region (Opening Stage, Hub, Fortress N)
  ("section", STAGE, N)    stage miniboss in checkpoint section N
  ("npc",     STAGE)       hub NPC that appears after rescues in STAGE and one boss clear
  ("late",    REGION)      story-gated: needs all 8 Circuit bosses and REGION
  ("enemy",   [STAGES])    random enemy drop, available in any listed stage

Chips that only appear after the goal (KAI, UNKNOWN_BOT, COMMANDER_CIRCUIT) or from the final boss (KERNEL_BOSS)
are excluded.
"""
import collections
import pathlib
import re

from gamefiles import MAP_FILES, PLAYABLE_MAPS, load_map, names, read_text

TARGET = pathlib.Path(__file__).resolve().parent.parent / "apworld" / "gravity_circuit" / "data_chips.py"

BOSS_CHIPS = {"RAY_OPTIC_CIRCUIT": "OPTIC", "FIX_PATCH_CIRCUIT": "PATCH", "BLADE_COOLER_CIRCUIT": "COOLER",
              "CABLE_POWER_CIRCUIT": "ELEC", "BIT_SHIFT_CIRCUIT": "SHIFT", "MEDLEY_WAVE_CIRCUIT": "WAVE",
              "CRASH_BREAK_CIRCUIT": "BREAK", "HASH_CIPHER_CIRCUIT": "CIPHER"}

# How each non-enemy chip is obtained, from the NPC and boss scripts.
FIXED_CHIPS = {
    "WRECKER_TANK": ("region", "Opening Stage"),
    "NEGA_UNCAPED": ("region", "Fortress 1"),
    "CRYSTAL_CIRCUIT_BANK": ("region", "Fortress 2"),
    "SCRAP_GOLEM": ("section", "PATCH", 2),
    "VIRUS_HELI": ("section", "SHIFT", 0),
    "NEGA": ("region", "Hub"),
    "GUARD": ("region", "Hub"),
    "SOLDIER_BOT_A": ("region", "Hub"),
    "SOLDIER_BOT_B": ("region", "Hub"),
    "SOLDIER_BOT_C": ("region", "Hub"),
    "MEDIC": ("region", "Hub"),
    "NURSE": ("region", "Hub"),
    "LIBRARIAN": ("region", "Hub"),
    "ELDER_BOT": ("region", "Hub"),
    "GUARDIAN_CORPS": ("region", "Hub"),
    # Prim is always in the hub; the ELEC rescue condition in prim-bot-npc.lua only shows the paint easel.
    "PAINTER_BOT": ("region", "Hub"),
    "DUAL": ("npc", "OPTIC"),
    "SPOOKED_BOT": ("npc", "PATCH"),
    "YUKI": ("npc", "COOLER"),
    "BALL_KID_BOT": ("npc", "SHIFT"),
    "AMADEUS": ("npc", "WAVE"),
    "MINER_BOT": ("npc", "BREAK"),
    "NERD_BOT": ("npc", "CIPHER"),
    "KERNEL": ("region", "Fortress 1"),
    "RESEARCHER_BOT": ("late", "Fortress 3"),
}
EXCLUDED = {"KAI", "UNKNOWN_BOT", "COMMANDER_CIRCUIT", "KERNEL_BOSS"}


def chip_list():
    source = re.sub(r"--\[\[.*?\]\]", "", read_text("content/data/collectibles/datachips.lua"), flags=re.S)
    return re.findall(r'\{\s*class\s*=\s*"([^"]+)",\s*category\s*=\s*classEnums\.(\w+)[^}]*?chance\s*=\s*([\d.]+)',
                       source)


def chip_titles():
    titles = {}
    for line in read_text("content/csv/en/bestiaryData.csv").splitlines():
        parts = line.split(";")
        if len(parts) >= 2 and parts[0].endswith("_title"):
            titles[parts[0][:-len("_title")].upper()] = parts[1]
    return titles


def object_classes():
    classes = {}
    for name in names():
        if name.startswith("lua/gameobjects/editorLoaded/") and name.endswith(".lua"):
            match = re.search(r':subclass\s*\(\s*"([^"]+)"', read_text(name))
            if match:
                classes[pathlib.PurePosixPath(name).stem] = match.group(1)
    return classes


def enemy_locations():
    """Chip id -> stages containing that enemy, resolving variants from map object parameters."""
    classes = object_classes()

    def chip_id(source, params):
        variant = params.get("type") or params.get("variant")
        if source == "virus_soldier" and params.get("isShielded"):
            return "SHIELDED_VIRUS_SOLDIER"
        if source == "surface_sweeper":
            return {3: "FIRE_SWEEPER", 2: "ELEC_SWEEPER"}.get(variant, "SPIKE_SWEEPER")
        if source == "elec_spider" and variant == 2:
            return "JUNK_SPIDER"
        if source == "omnishot_walker" and params.get("type") == 2:
            return "OMNISHOT_WALKER_CYBER"
        return classes.get(source, (source or "").upper())

    where = collections.defaultdict(set)
    for stage in PLAYABLE_MAPS:
        for obj in load_map(MAP_FILES[stage] + ".gcl")["objects"].values():
            where[chip_id(obj.get("source"), obj.get("parameters") or {})].add(stage)
    where["BUG_DISPENSER_FLY"] |= where["BUG_DISPENSER"]
    return where


def collect():
    titles = chip_titles()
    enemies = enemy_locations()
    rows = []
    for chip, category, _ in chip_list():
        if chip in EXCLUDED:
            continue
        name = "Data Chip - " + titles.get(chip, chip.replace("_", " ")).title()
        if chip == "NEGA_UNCAPED":
            name += " (Boss)"
        if chip in BOSS_CHIPS:
            rows.append((chip, name, "reliable", ("boss", BOSS_CHIPS[chip])))
        elif chip in FIXED_CHIPS:
            rows.append((chip, name, "reliable", FIXED_CHIPS[chip]))
        elif category == "ENEMIES":
            stages = sorted(enemies.get(chip, ()))
            if not stages:
                raise SystemExit(f"no stage found for enemy chip {chip}")
            rows.append((chip, name, "random", ("enemy", stages)))
        else:
            raise SystemExit(f"unhandled chip {chip} ({category})")
    location_names = [row[1] for row in rows]
    assert len(set(location_names)) == len(location_names), "duplicate data chip names"
    return rows


def main() -> None:
    rows = collect()
    lines = ['"""Generated by tools/gen_data_chips.py. Do not edit.',
             "",
             "(chip id, location name, group, how it is obtained); see the generator for the meaning.",
             '"""',
             "DATA_CHIPS = ["]
    lines += [f"    ({chip!r}, {name!r}, {group!r}, {spec!r})," for chip, name, group, spec in rows]
    lines += ["]", ""]
    TARGET.write_text("\n".join(lines), encoding="utf-8")
    counts = collections.Counter(row[2] for row in rows)
    print(f"wrote {TARGET.name}: {dict(counts)}")


if __name__ == "__main__":
    main()
