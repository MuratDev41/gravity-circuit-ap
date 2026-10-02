"""Stage maps and pin positions for the PopTracker pack.

Map pictures come from the in-game exporter (client/archipelago/mapexport.lua), which renders every official map
with the game's tile renderer into <save dir>/archipelago/mapexport/<map>/<x>_<y>.png. This module stitches,
crops and scales them, and places every location using the map objects. The images are derived from the user's
own copy of the game and must not be redistributed.
"""
import os
import pathlib

from PIL import Image

from gamefiles import MAP_FILES, load_map

EXPORT_DIR = pathlib.Path(os.environ.get("APPDATA", "")) / "Gravity Circuit" / "archipelago" / "mapexport"
IMG_SCALE = 0.25            # world pixels -> map image pixels
MAP_SCALE = {"HUB": 0.5}
PAD = 24

TAB_NAMES = {
    "HUB": "Hub", "OPENING": "Opening Stage", "OPTIC": "Steelworks", "PATCH": "Junkyard", "COOLER": "Mountains",
    "ELEC": "Power Plant", "SHIFT": "Highway", "WAVE": "City Center", "BREAK": "Ore Mines", "CIPHER": "Warehouse",
    "FINAL_1": "Fortress 1", "FINAL_2": "Fortress 2", "FINAL_3": "Fortress 3",
}
MAPS = {key: (MAP_FILES[key], TAB_NAMES[key]) for key in MAP_FILES}

# data chip id -> hub object that hands it out
NPC_OBJECT = {
    "GUARD": "guard-bot-npc", "MEDIC": "medic-bot-npc", "NURSE": "nurse-bot-npc", "LIBRARIAN": "librarian-bot-npc",
    "ELDER_BOT": "chronos-bot-npc", "SOLDIER_BOT_A": "soldier-bot-a-npc", "SOLDIER_BOT_B": "soldier-bot-b-npc",
    "SOLDIER_BOT_C": "soldier-bot-c-npc", "GUARDIAN_CORPS": "soldier-bot-a-npc", "NEGA": "hub-healing-chamber",
    "KERNEL": "kernel-npc", "RESEARCHER_BOT": "researcher-bot-npc", "AMADEUS": "amadeus-dog-npc",
    "YUKI": "yuki-dog-npc", "DUAL": "sitter-bot-npc", "SPOOKED_BOT": "shocked-bot-npc",
    "PAINTER_BOT": "prim-bot-npc", "BALL_KID_BOT": "ball-kid-bot", "MINER_BOT": "mighty-bot-npc",
    "NERD_BOT": "tech-bot-npc",
}
# Script-spawned bosses and minibosses have no map object; they are pinned at their arena (world x, y).
SCRIPTED = {
    ("OPENING", "boss"): (12976, 1824),
    ("PATCH", "SCRAP_GOLEM"): (12300, 2768),
    ("SHIFT", "VIRUS_HELI"): (20752, 1500),
}


class StageMap:
    def __init__(self, key):
        self.key = key
        self.file, self.name = MAPS[key]
        self.objects = list(load_map(self.file + ".gcl")["objects"].values())
        self.by_id = {o.get("ID"): o for o in self.objects}
        self.crop = (0, 0)
        self.size = (0, 0)
        self.scale = MAP_SCALE.get(key, IMG_SCALE)

    def first(self, source, pred=lambda o: True):
        for o in self.objects:
            if o.get("source") == source and pred(o):
                return o["spawn"]["x"], o["spawn"]["y"]
        return None

    def boss(self):
        for o in self.objects:
            s = o.get("source") or ""
            if s.startswith("boss_") and s not in ("boss_door", "boss_hash_clone_laugher", "boss_rush_spawner"):
                return o["spawn"]["x"], o["spawn"]["y"]
        return None

    def pin(self, world):
        x, y = world
        return int(x * self.scale - self.crop[0]) + 4, int(y * self.scale - self.crop[1]) + 4

    def build_image(self, out_path):
        src = EXPORT_DIR / self.file
        meta = (src / "meta.txt").read_text().split()
        cells_h, cells_v, cw, ch, scale = int(meta[0]), int(meta[1]), int(meta[2]), int(meta[3]), float(meta[4])
        pw, ph = int(cw * scale), int(ch * scale)
        full = Image.new("RGBA", (cells_h * pw, cells_v * ph), (0, 0, 0, 0))
        for f in src.glob("*.png"):
            x, y = map(int, f.stem.split("_"))
            full.alpha_composite(Image.open(f).convert("RGBA"), ((x - 1) * pw, (y - 1) * ph))
        factor = self.scale / scale
        img = full.resize((max(1, int(full.width * factor)), max(1, int(full.height * factor))), Image.NEAREST)
        bbox = img.getbbox() or (0, 0, img.width, img.height)
        left, top = max(bbox[0] - PAD, 0), max(bbox[1] - PAD, 0)
        right, bottom = min(bbox[2] + PAD, img.width), min(bbox[3] + PAD, img.height)
        img = img.crop((left, top, right, bottom))
        bg = Image.new("RGBA", img.size, (16, 19, 27, 255))
        bg.alpha_composite(img)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        bg.convert("RGB").save(out_path, optimize=True)
        self.crop = (left, top)
        self.size = bg.size

    # PopTracker scales pins by the unzoomed fit-to-panel scale only, so they keep a fixed screen size at any zoom.
    # Size them for roughly 16 screen pixels on a typical map panel.
    PANEL = (1100, 900)
    PIN_SCREEN_PX = 16

    def fit_scale(self):
        return max(self.size[0] / self.PANEL[0], self.size[1] / self.PANEL[1], 1.0)

    def location_size(self):
        return max(12, round(self.PIN_SCREEN_PX * self.fit_scale()))

    def border(self):
        return max(2, round(2 * self.fit_scale()))


def location_position(loc, maps, data):
    """(map key, world x, world y) of an AP location, or None if it has no single place (enemy data chips)."""
    k = loc.stage
    if loc.kind == "rescue":
        return k, maps[k].first("rescuable_bot", lambda o: (o.get("parameters") or {}).get("rescueId") == loc.index)
    if loc.kind == "booster":
        return k, maps[k].first("health_booster") or maps[k].first("burst_booster")
    if loc.kind == "palette":
        return k, maps[k].first("palette_chip")
    if loc.kind in ("cache", "smallcache"):
        o = maps[k].by_id.get(loc.obj)
        return k, (o["spawn"]["x"], o["spawn"]["y"]) if o else None
    if loc.kind in ("boss", "fortress"):
        return k, maps[k].boss()
    if loc.kind == "opening":
        return "OPENING", SCRIPTED[("OPENING", "boss")]
    if loc.kind == "shopburst":
        return "HUB", maps["HUB"].first("nega-npc")
    if loc.kind == "shopchip":
        return "HUB", maps["HUB"].first("nurse-bot-npc")
    if loc.kind in ("datachip", "datachiprandom"):
        chip = loc.obj
        spec = data.DATA_CHIP_SPECS[loc.name]
        if spec[0] == "enemy":
            return None
        if spec[0] == "boss":
            return spec[1], maps[spec[1]].boss()
        if spec[0] == "section":
            return spec[1], SCRIPTED[(spec[1], chip)]
        if chip in NPC_OBJECT:
            return "HUB", maps["HUB"].first(NPC_OBJECT[chip])
        if chip == "WRECKER_TANK":
            return "OPENING", SCRIPTED[("OPENING", "boss")]
        if chip == "NEGA_UNCAPED":
            return "FINAL_1", maps["FINAL_1"].boss()
        if chip == "CRYSTAL_CIRCUIT_BANK":
            return "FINAL_2", maps["FINAL_2"].boss()
    return None
