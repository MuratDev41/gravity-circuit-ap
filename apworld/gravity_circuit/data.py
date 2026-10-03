"""Static game data for Gravity Circuit 1.2.2.

Single source of truth for item and location ids; tools/gen_lua_data.py exports it to the client. Pickup positions
inside stages were derived from the game's map files (see docs/DEVELOPMENT.md).
"""
from typing import Dict, List, NamedTuple

try:
    from .data_chips import DATA_CHIPS
    from .money_caches import MONEY_CACHES
except ImportError:  # imported standalone by the tools
    from data_chips import DATA_CHIPS
    from money_caches import MONEY_CACHES

GAME_NAME = "Gravity Circuit (MuratDev's Implementation)"
BASE_ID = 0x4743_0000


class Stage(NamedTuple):
    key: str              # map id used by the game (MapData.OFFICIAL_MAPS)
    name: str
    boss: str
    clear_flag: int       # index into BOSS_CLEAR_FLAGS.kai
    booster: str          # "Health" or "Burst"
    sections: int         # checkpoint sections before the boss room
    booster_section: int
    palette_section: int
    bot_sections: List[int]


# In stage select order (slots 1-8).
STAGES: List[Stage] = [
    Stage("OPTIC",  "Steelworks",  "Ray",    1, "Health", 4, 3, 0, [0, 1, 1, 2, 2, 3, 3, 3]),
    Stage("PATCH",  "Junkyard",    "Trace",  2, "Health", 4, 0, 1, [0, 1, 1, 1, 1, 3, 3, 3]),
    Stage("COOLER", "Mountains",   "Blade",  3, "Health", 4, 1, 0, [0, 0, 1, 2, 2, 3, 3, 3]),
    Stage("ELEC",   "Power Plant", "Cable",  4, "Burst",  5, 4, 1, [0, 2, 2, 2, 3, 4, 4, 4]),
    Stage("SHIFT",  "Highway",     "Bit",    5, "Burst",  4, 1, 3, [0, 0, 0, 1, 1, 2, 3, 3]),
    Stage("WAVE",   "City Center", "Medley", 6, "Health", 4, 2, 3, [0, 1, 1, 2, 2, 3, 3, 3]),
    Stage("BREAK",  "Ore Mines",   "Crash",  7, "Burst",  4, 2, 3, [1, 1, 1, 1, 2, 2, 3, 3]),
    Stage("CIPHER", "Warehouse",   "Hash",   8, "Burst",  3, 1, 0, [0, 0, 0, 1, 1, 1, 1, 2]),
]
STAGE_BY_KEY: Dict[str, Stage] = {s.key: s for s in STAGES}

# (map id, region name, boss, index into BOSS_CLEAR_FLAGS.kai)
FORTRESS = [
    ("FINAL_1", "Fortress 1", "Nega", 9),
    ("FINAL_2", "Fortress 2", "Circuit Crystal", 10),
    ("FINAL_3", "Fortress 3", "Kernel", 11),
]


def section_region(stage: Stage, section: int) -> str:
    if section == 0:
        return f"{stage.name} - Start"
    return f"{stage.name} - Checkpoint {section}"


def boss_region(stage: Stage) -> str:
    return f"{stage.name} - Boss Room"


def access_item(stage: Stage) -> str:
    return f"{stage.name} Access"


def fortress_access_item(region: str) -> str:
    return f"{region} Access"


# Fortress stages that get their own Access item under the fortress_access option: (region, stage select slot)
FORTRESS_ACCESS = [(name, flag) for _, name, _, flag in FORTRESS[:2]]


class LocData(NamedTuple):
    name: str
    code: int
    region: str
    kind: str
    stage: str
    index: int
    obj: str = ""         # map object id (caches) or data chip id


class ItemData(NamedTuple):
    name: str
    code: int
    kind: str
    game_id: int
    classification: str
    count: int = 1        # copies in the pool; filler and traps are added by weight instead


BURSTS = {
    4: "Gravity Freeze", 5: "Surface Render", 7: "Screen Interrupt", 8: "Cycle Kick",
    9: "Clone Array", 10: "Burst Spark", 11: "Hardware Barrier", 12: "Gravity Dash",
    13: "Function Overload", 14: "Piercing Drill", 15: "Support Platform", 16: "Hologram Trap",
    17: "Current Arc", 18: "Emergency Heal", 19: "Distant Detonation", 20: "Erupting Beam",
}

# Bursts Nega sells from the start; only shuffled with shopsanity. Flying Strike is a story gift.
SHOP_BURSTS = {2: "Rising Upper", 3: "Heavenly Piledrive", 6: "Catch Interrupt"}

# Chip 1 (Energy Absorber) is the Nurse's story gift and is not shuffled.
CHIPS = {
    2: "Air Jumper", 3: "Power Extender", 4: "Grip Enhancer", 5: "Surge Protector",
    6: "Catch Block", 7: "Magnet Chassis", 8: "Emergency Accumulator", 9: "Underflow Guard",
    10: "Energy Multiplier", 11: "Light Alloy", 12: "Frame Amplifier", 13: "Dodge Slider",
    14: "Speed Basher", 15: "Chain Booster", 16: "Chain Dasher", 17: "Repair Enhancer",
    18: "Nullifying Layer", 19: "Protection Timer", 20: "Overflow Converter",
}
PROGRESSION_CHIPS = {2}

PAINTS = {
    1: "Hot-Headed Red", 2: "Draining Gray", 3: "Floating Blue", 4: "Electrifying Green",
    5: "Speedy Teal", 6: "Playful Blue", 7: "Heavy Orange", 8: "Scheming Pink", 9: "Fading Onyx",
}

# Stage whose boss puts each burst on sale in Nega's shop (bursts.lua bossUnlock).
BURST_BOSS_STAGE = {
    4: "COOLER", 15: "COOLER", 5: "WAVE", 8: "WAVE", 7: "SHIFT", 12: "SHIFT", 9: "CIPHER", 16: "CIPHER",
    10: "ELEC", 17: "ELEC", 11: "PATCH", 18: "PATCH", 13: "OPTIC", 20: "OPTIC", 14: "BREAK", 19: "BREAK",
}

# Rescue tokens needed to research each chip at the Nurse; they add up to the 64 rescue bots.
CHIP_TOKENS = {2: 8, 3: 4, 4: 2, 5: 2, 6: 4, 7: 1, 8: 3, 9: 3, 10: 3, 11: 3, 12: 5, 13: 3, 14: 3, 15: 5, 16: 3,
               17: 2, 18: 4, 19: 3, 20: 3}

AIR_JUMPER_LOCATIONS = [
    "Junkyard - Health Booster",
    "Highway - Burst Booster",
    "Highway - Money Cache 1",
    "Fortress 2 - Small Cache 11",
    "Fortress 2 - Small Cache 12",
]

# (name, id offset, kind, game value, classification)
FILLER_AND_TRAPS = [
    ("500 Credits", 100, "credits", 500, "filler"),
    ("50 Credits", 101, "credits", 50, "filler"),
    ("100 Credits", 102, "credits", 100, "filler"),
    ("250 Credits", 103, "credits", 250, "filler"),
    ("1000 Credits", 104, "credits", 1000, "filler"),
    ("Health Refill", 110, "heal", 8, "filler"),
    ("Full Health Refill", 111, "heal", 999, "filler"),
    ("Burst Refill", 112, "burstfill", 0, "filler"),
    ("Rescue Token", 113, "token", 1, "progression"),
    ("Damage Trap", 120, "trapdamage", 8, "trap"),
    ("Credit Leak Trap", 121, "trapcredits", 250, "trap"),
]

FILLER_WEIGHTS = {
    "50 Credits": 12, "100 Credits": 18, "250 Credits": 14, "500 Credits": 10, "1000 Credits": 4,
    "Health Refill": 10, "Full Health Refill": 4, "Burst Refill": 10, "Rescue Token": 8,
}
TRAP_WEIGHTS = {"Damage Trap": 1, "Credit Leak Trap": 1}


def _build_items() -> List[ItemData]:
    items: List[ItemData] = []
    for i, stage in enumerate(STAGES):
        items.append(ItemData(access_item(stage), BASE_ID + 1 + i, "access", i + 1, "progression"))
    for region, slot in FORTRESS_ACCESS:
        items.append(ItemData(fortress_access_item(region), BASE_ID + slot, "access", slot, "progression"))
    for bid, name in {**BURSTS, **SHOP_BURSTS}.items():
        items.append(ItemData(f"Burst: {name}", BASE_ID + 20 + bid, "burst", bid, "useful"))
    for cid, name in CHIPS.items():
        classification = "progression" if cid in PROGRESSION_CHIPS else "useful"
        items.append(ItemData(f"Chip: {name}", BASE_ID + 50 + cid, "chip", cid, classification))
    items.append(ItemData("Health Upgrade", BASE_ID + 80, "health", 0, "useful", 4))
    items.append(ItemData("Burst Upgrade", BASE_ID + 81, "burstup", 0, "useful", 4))
    for pid, name in PAINTS.items():
        items.append(ItemData(f"Paint: {name}", BASE_ID + 90 + pid, "paint", pid, "filler"))
    for name, offset, kind, value, classification in FILLER_AND_TRAPS:
        items.append(ItemData(name, BASE_ID + offset, kind, value, classification, 0))
    return items


def _cache_locations() -> List[LocData]:
    locs: List[LocData] = []
    fortress_names = {key: name for key, name, _, _ in FORTRESS}
    counters = {"big": 0, "small": 0}
    for size, key, number, obj, section in MONEY_CACHES:
        if key in STAGE_BY_KEY:
            stage = STAGE_BY_KEY[key]
            prefix, region = stage.name, section_region(stage, section)
        elif key == "OPENING":
            prefix = region = "Opening Stage"
        else:
            prefix = region = fortress_names[key]
        index = counters[size]
        counters[size] += 1
        if size == "big":
            locs.append(LocData(f"{prefix} - Money Cache {number}", BASE_ID + 400 + index, region, "cache",
                                key, number, obj))
        else:
            locs.append(LocData(f"{prefix} - Small Cache {number}", BASE_ID + 1000 + index, region, "smallcache",
                                key, number, obj))
    return locs


def _data_chip_locations() -> List[LocData]:
    locs: List[LocData] = []
    for index, (chip, name, group, spec) in enumerate(DATA_CHIPS):
        mode = spec[0]
        if mode == "boss":
            region = boss_region(STAGE_BY_KEY[spec[1]])
        elif mode == "section":
            region = section_region(STAGE_BY_KEY[spec[1]], spec[2])
        elif mode in ("region", "late"):
            region = spec[1]
        else:
            region = "Hub"
        kind = "datachip" if group == "reliable" else "datachiprandom"
        locs.append(LocData(name, BASE_ID + 2000 + index, region, kind, "CHIP", index, chip))
    return locs


def _build_locations() -> List[LocData]:
    locs: List[LocData] = [
        LocData("Opening Stage - Clear", BASE_ID + 1, "Opening Stage", "opening", "OPENING", 0),
        LocData("Hub - Palette Chip", BASE_ID + 2, "Hub", "palette", "HUB", 9),
    ]
    for i, stage in enumerate(STAGES):
        base = BASE_ID + 100 + i * 20
        locs.append(LocData(f"{stage.name} - {stage.boss} Defeated", base, boss_region(stage), "boss",
                            stage.key, stage.clear_flag))
        locs.append(LocData(f"{stage.name} - {stage.booster} Booster", base + 1,
                            section_region(stage, stage.booster_section), "booster", stage.key, 0))
        locs.append(LocData(f"{stage.name} - Palette Chip", base + 2,
                            section_region(stage, stage.palette_section), "palette", stage.key, i + 1))
        for bot in range(1, 9):
            locs.append(LocData(f"{stage.name} - Rescue Bot {bot}", base + 2 + bot,
                                section_region(stage, stage.bot_sections[bot - 1]), "rescue", stage.key, bot))
    for index, (key, name, boss, flag) in enumerate(FORTRESS[:2]):
        locs.append(LocData(f"{name} - {boss} Defeated", BASE_ID + 300 + index, name, "fortress", key, flag))
    locs += _cache_locations()
    locs += _data_chip_locations()
    for bid, name in sorted({**SHOP_BURSTS, **BURSTS}.items()):
        locs.append(LocData(f"Nega's Shop - {name}", BASE_ID + 3000 + bid, "Hub", "shopburst", "HUB", bid))
    for cid, name in sorted(CHIPS.items()):
        locs.append(LocData(f"Nurse's Shop - {name}", BASE_ID + 3100 + cid, "Hub", "shopchip", "HUB", cid))
    return locs


ITEMS: List[ItemData] = _build_items()
ITEM_BY_NAME: Dict[str, ItemData] = {i.name: i for i in ITEMS}
ITEM_NAME_TO_ID: Dict[str, int] = {i.name: i.code for i in ITEMS}

LOCATIONS: List[LocData] = _build_locations()
LOCATION_NAME_TO_ID: Dict[str, int] = {l.name: l.code for l in LOCATIONS}

DATA_CHIP_SPECS = {name: spec for _, name, _, spec in DATA_CHIPS}

ITEM_GROUPS = {
    "Access": {i.name for i in ITEMS if i.kind == "access"},
    "Bursts": {i.name for i in ITEMS if i.kind == "burst"},
    "Chips": {i.name for i in ITEMS if i.kind == "chip"},
    "Paints": {i.name for i in ITEMS if i.kind == "paint"},
    "Filler": set(FILLER_WEIGHTS),
    "Traps": set(TRAP_WEIGHTS),
}

LOCATION_GROUPS = {s.name: {l.name for l in LOCATIONS if l.stage == s.key} for s in STAGES}
LOCATION_GROUPS.update({
    "Rescues": {l.name for l in LOCATIONS if l.kind == "rescue"},
    "Bosses": {l.name for l in LOCATIONS if l.kind in ("boss", "fortress")},
    "Money Caches": {l.name for l in LOCATIONS if l.kind == "cache"},
    "Small Caches": {l.name for l in LOCATIONS if l.kind == "smallcache"},
    "Data Chips": {l.name for l in LOCATIONS if l.kind in ("datachip", "datachiprandom")},
    "Shops": {l.name for l in LOCATIONS if l.kind in ("shopburst", "shopchip")},
})
