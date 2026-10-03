"""Generate the PopTracker pack (build/poptracker and dist/gravity_circuit_poptracker.zip) from the APWorld data.

Ids, location names and logic all come from apworld/gravity_circuit/data.py. Icons and the overview map are drawn
here; the stage maps come from the user's game via pt_maps, so the built pack is for personal use only.
"""
import json
import pathlib
import shutil
import sys
import zipfile

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "apworld" / "gravity_circuit"))
import data  # noqa: E402
import pt_maps  # noqa: E402

VERSION = "0.6.0"
OUT = ROOT / "build" / "poptracker"
shutil.rmtree(OUT, ignore_errors=True)
STAGE_COLORS = {"OPTIC": "#d9534f", "PATCH": "#8a8f98", "COOLER": "#4aa3df", "ELEC": "#5cb85c",
                "SHIFT": "#2bb5a8", "WAVE": "#5b6ee1", "BREAK": "#f0883e", "CIPHER": "#d65db1"}
STAGE_SHORT = {"OPTIC": "SW", "PATCH": "JY", "COOLER": "MT", "ELEC": "PP", "SHIFT": "HW", "WAVE": "CC",
               "BREAK": "OM", "CIPHER": "WH"}


def font(size):
    for name in ("arialbd.ttf", "arial.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def icon(path, label, color, shape="square"):
    s = 48
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if shape == "circle":
        d.ellipse((3, 3, s - 4, s - 4), fill=color, outline="#101010", width=3)
    elif shape == "diamond":
        d.polygon([(s / 2, 2), (s - 3, s / 2), (s / 2, s - 3), (3, s / 2)], fill=color, outline="#101010", width=3)
    else:
        d.rounded_rectangle((3, 3, s - 4, s - 4), radius=9, fill=color, outline="#101010", width=3)
    f = font(17 if len(label) <= 2 else 13 if len(label) <= 3 else 10)
    tw, th = d.textbbox((0, 0), label, font=f)[2:]
    d.text(((s - tw) / 2 + 1, (s - th) / 2 - 1), label, font=f, fill="#000000")
    d.text(((s - tw) / 2, (s - th) / 2 - 2), label, font=f, fill="#ffffff")
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path)


def initials(name):
    words = [w for w in name.replace("-", " ").split() if w[0].isalpha()]
    return "".join(w[0] for w in words[:3]).upper() or name[:2].upper()


items, item_mapping, grids = [], {}, {}


def add_item(code, name, img, kind="toggle", ap_id=None, **extra):
    entry = {"name": name, "type": kind, "img": img, "codes": code}
    entry.update(extra)
    items.append(entry)
    if ap_id is not None:
        item_mapping[ap_id] = (code, kind)


img_dir = OUT / "images" / "items"
grids["stages"], grids["bosses"] = [], []
for i, s in enumerate(data.STAGES):
    key = s.key.lower()
    color = STAGE_COLORS[s.key]
    icon(img_dir / f"access_{key}.png", STAGE_SHORT[s.key], color)
    add_item(f"access_{key}", f"{s.name} Access", f"images/items/access_{key}.png",
             ap_id=data.ITEM_NAME_TO_ID[data.access_item(s)])
    icon(img_dir / f"boss_{key}.png", s.boss[:3].upper(), color, "circle")
    add_item(f"boss_{key}", f"{s.boss} Defeated", f"images/items/boss_{key}.png")
    grids["stages"].append(f"access_{key}")
    grids["bosses"].append(f"boss_{key}")
for number, (region, _) in enumerate(data.FORTRESS_ACCESS, 1):
    code = f"access_final_{number}"
    icon(img_dir / f"{code}.png", f"F{number}", "#8b1e3f")
    add_item(code, data.fortress_access_item(region), f"images/items/{code}.png",
             ap_id=data.ITEM_NAME_TO_ID[data.fortress_access_item(region)])
    grids["stages"].append(code)

grids["chips"], grids["bursts"], grids["paints"] = [], [], []
for it in data.ITEMS:
    if it.kind == "chip":
        code = f"chip_{it.game_id}"
        color = "#f5c518" if it.game_id in data.PROGRESSION_CHIPS else "#c98a2b"
        icon(img_dir / f"{code}.png", initials(it.name[6:]), color)
        add_item(code, it.name, f"images/items/{code}.png", ap_id=it.code)
        grids["chips"].append(code)
    elif it.kind == "burst":
        code = f"burst_{it.game_id}"
        icon(img_dir / f"{code}.png", initials(it.name[7:]), "#7a4fd1", "diamond")
        add_item(code, it.name, f"images/items/{code}.png", ap_id=it.code)
        grids["bursts"].append(code)
    elif it.kind == "paint":
        code = f"paint_{it.game_id}"
        icon(img_dir / f"{code}.png", f"P{it.game_id}", "#9c6644", "circle")
        add_item(code, it.name, f"images/items/{code}.png", ap_id=it.code)
        grids["paints"].append(code)
    elif it.kind == "health":
        icon(img_dir / "health.png", "HP+", "#e05561")
        add_item("health", it.name, "images/items/health.png", "consumable", it.code, max_quantity=4, min_quantity=0)
    elif it.kind == "burstup":
        icon(img_dir / "burstup.png", "BU+", "#e0a030")
        add_item("burstup", it.name, "images/items/burstup.png", "consumable", it.code, max_quantity=4,
                 min_quantity=0)

icon(img_dir / "rescue_token.png", "TOK", "#3fa66b", "circle")
add_item("rescue_token", "Rescue Token", "images/items/rescue_token.png", "consumable",
         data.ITEM_NAME_TO_ID["Rescue Token"], max_quantity=999, min_quantity=0)

# Settings are filled in from slot data by autotracking and can be toggled manually.
SETTINGS = [("opt_money_caches", "Money Caches", "$", True), ("opt_small_money_caches", "Small Caches", "$s", True),
            ("opt_data_chips", "Data Chips", "DC", True), ("opt_random_data_chips", "Enemy Data Chips", "EDC", False),
            ("opt_shopsanity", "Shopsanity", "SHP", True), ("opt_hard_logic", "Hard Logic", "HRD", False),
            ("opt_fortress_access", "Fortress Access Items", "FA", False),
            ("opt_follow_map", "Follow the player's map", "MAP", True),
            ("opt_follow_pos", "Follow Kai: zoom in and keep the map centered on him", "KAI", True)]
for code, name, label, default in SETTINGS:
    icon(img_dir / f"{code}.png", label, "#3d4b5c")
    add_item(code, name, f"images/items/{code}.png", initial_active_state=default)
icon(img_dir / "opt_bosses_required.png", "REQ", "#3d4b5c", "circle")
add_item("opt_bosses_required", "Bosses Required (Fortress)", "images/items/opt_bosses_required.png",
         "consumable", max_quantity=8, min_quantity=1, initial_quantity=8)

BOX_W, BOX_H, LABEL_W, PAD = 150, 56, 170, 14
max_sections = max(s.sections for s in data.STAGES) + 1
W = LABEL_W + max_sections * (BOX_W + PAD) + PAD
TOP_ROWS = 2
H = (len(data.STAGES) + TOP_ROWS) * (BOX_H + PAD) + PAD + 20
im = Image.new("RGB", (W, H), "#151922")
d = ImageDraw.Draw(im)
f_label, f_box = font(18), font(14)
pins = {}


def box(x, y, text, color, name):
    d.rounded_rectangle((x, y, x + BOX_W, y + BOX_H), radius=8, fill="#232a36", outline=color, width=3)
    tw = d.textbbox((0, 0), text, font=f_box)[2]
    d.text((x + (BOX_W - tw) / 2, y + 6), text, font=f_box, fill="#e8e8e8")
    pins[name] = (x + BOX_W // 2, y + BOX_H // 2 + 9)


y = PAD
d.text((PAD, y + 16), "Base / Hub", font=f_label, fill="#ffffff")
for j, (txt, name) in enumerate([("Opening Stage", "Opening Stage"), ("Hub", "Hub"),
                                 ("Hub Data Chips", "Hub - Data Chips"), ("Enemy Data Chips", "Enemy Data Chips"),
                                 ("Nega's Shop", "Nega's Shop"), ("Nurse's Shop", "Nurse's Shop")]):
    box(LABEL_W + j * (BOX_W + PAD), y, txt, "#c8c8c8", name)
y += BOX_H + PAD
d.text((PAD, y + 16), "Fortress", font=f_label, fill="#ffffff")
for j, (_, name, _, _) in enumerate(data.FORTRESS):
    box(LABEL_W + j * (BOX_W + PAD), y, name, "#b23b3b", name)
y += BOX_H + PAD
for s in data.STAGES:
    d.text((PAD, y + 8), s.name, font=f_label, fill=STAGE_COLORS[s.key])
    d.text((PAD, y + 30), s.boss, font=f_box, fill="#9aa4b2")
    names = [data.section_region(s, i) for i in range(s.sections)] + [data.boss_region(s)]
    for j, region in enumerate(names):
        box(LABEL_W + j * (BOX_W + PAD), y, region.split(" - ", 1)[1], STAGE_COLORS[s.key], region)
    y += BOX_H + PAD
(OUT / "images" / "maps").mkdir(parents=True, exist_ok=True)
im.save(OUT / "images" / "maps" / "overview.png")

stage_of_region = {}
for s in data.STAGES:
    for i in range(s.sections):
        stage_of_region[data.section_region(s, i)] = s.key
    stage_of_region[data.boss_region(s)] = s.key
fortress_regions = {name for _, name, _, _ in data.FORTRESS}
fortress_key_region = {key: name for key, name, _, _ in data.FORTRESS}
fortress_number = {name: number for number, (_, name, _, _) in enumerate(data.FORTRESS, 1)}
fortress_number.update({key: number for number, (key, _, _, _) in enumerate(data.FORTRESS, 1)})
VIS = {"cache": "opt_money_caches", "smallcache": "opt_small_money_caches", "datachip": "opt_data_chips",
       "datachiprandom": "opt_random_data_chips", "shopburst": "opt_shopsanity", "shopchip": "opt_shopsanity"}

# Nurse chips enter logic cheapest first, as in rules.py.
_cum, _run = {}, 0
for _cid, _cost in sorted(data.CHIP_TOKENS.items(), key=lambda kv: (kv[1], kv[0])):
    _run += _cost
    _cum[_cid] = _run

pt_locations = {}   # pin name -> location dict
check_rules = {}    # AP id -> (location-level rules, section rules, visibility rules)
location_mapping = {}
boss_locations = {}


def pin_for(loc):
    if loc.kind == "shopburst":
        return "Nega's Shop"
    if loc.kind == "shopchip":
        return "Nurse's Shop"
    if loc.kind in ("datachip", "datachiprandom"):
        spec = data.DATA_CHIP_SPECS[loc.name]
        if spec[0] == "enemy":
            return "Enemy Data Chips"
        if loc.region == "Hub":
            return "Hub - Data Chips"
    return loc.region


def section_name(loc, pin):
    name = loc.name
    for prefix in [pin.split(" - ")[0] + " - ", "Data Chip - ", "Nega's Shop - ", "Nurse's Shop - "]:
        if name.startswith(prefix):
            name = name[len(prefix):]
    return name


for loc in data.LOCATIONS:
    pin = pin_for(loc)
    if pin not in pt_locations:
        entry = {"name": pin, "map_locations": [{"map": "Overview", "x": pins[pin][0], "y": pins[pin][1]}],
                 "sections": []}
        if pin in stage_of_region:
            entry["access_rules"] = [f"$stage|{stage_of_region[pin].lower()}"]
        elif pin in fortress_regions:
            entry["access_rules"] = [f"$fortress|{fortress_number[pin]}"]
        pt_locations[pin] = entry
    sec = {"name": section_name(loc, pin)}
    rules = None
    if loc.name in data.AIR_JUMPER_LOCATIONS:
        rules = ["$airjumper"]
    if loc.kind == "shopburst" and loc.index in data.BURST_BOSS_STAGE:
        rules = [f"$stage|{data.BURST_BOSS_STAGE[loc.index].lower()}"]
    if loc.kind == "shopchip":
        rules = [f"$tokens|{_cum[loc.index]}"]
    spec = data.DATA_CHIP_SPECS.get(loc.name)
    if spec:
        if spec[0] == "npc":
            rules = [f"$npc|{spec[1].lower()}"]
        elif spec[0] == "late":
            rules = ["$fortress|1,$fortress|2,$fortress|3,$bosses|8"]
        elif spec[0] == "enemy" and "OPENING" not in spec[1]:
            rules = []
            for k in spec[1]:
                rules.append(f"$fortress|{fortress_number[k]}" if k in fortress_key_region else f"$stage|{k.lower()}")
            rules = sorted(set(rules))
    if rules:
        sec["access_rules"] = rules
    if loc.kind in VIS:
        sec["visibility_rules"] = [VIS[loc.kind]]
    pt_locations[pin]["sections"].append(sec)
    location_mapping[loc.code] = [f"@{pin}/{sec['name']}"]
    check_rules[loc.code] = (pt_locations[pin].get("access_rules"), sec.get("access_rules"),
                             sec.get("visibility_rules"))
    if loc.kind == "boss":
        boss_locations[loc.code] = f"boss_{loc.stage.lower()}"

stage_maps = {k: pt_maps.StageMap(k) for k in pt_maps.MAPS}
for k, sm in stage_maps.items():
    sm.build_image(OUT / "images" / "maps" / f"{sm.file}.png")

spots = {}   # (map key, x, y) -> list of locations
for loc in data.LOCATIONS:
    pos = pt_maps.location_position(loc, stage_maps, data)
    if not pos or not pos[1]:
        continue
    key, world = pos
    px, py = stage_maps[key].pin(world)
    spots.setdefault((key, px, py), []).append(loc)

detail_locations = []
for (key, px, py), locs in spots.items():
    sm = stage_maps[key]
    first = locs[0]
    if first.kind == "shopburst":
        label = "Nega's Shop"
    elif first.kind == "shopchip":
        label = "Nurse's Shop"
    else:
        label = first.name if len(locs) == 1 else f"{first.name} (+{len(locs) - 1})"
    label = f"{sm.name}: {label}"
    entry = {"name": label, "map_locations": [{"map": sm.name, "x": px, "y": py}], "sections": []}
    region_rules = {tuple(check_rules[l.code][0] or ()) for l in locs}
    shared = next(iter(region_rules)) if len(region_rules) == 1 else None
    if shared:
        entry["access_rules"] = list(shared)
    used = set()
    for l in locs:
        loc_rules, sec_rules, vis = check_rules[l.code]
        name = l.name.split(" - ", 1)[-1] if " - " in l.name else l.name
        if l.kind in ("datachip", "datachiprandom"):
            name = "Data Chip: " + name
        while name in used:
            name += " "
        used.add(name)
        sec = {"name": name}
        rules = sec_rules
        if loc_rules and shared is None:
            # pin shared by checks with different region rules: put the region rule on the section
            rules = [",".join(filter(None, [loc_rules[0], r])) for r in (sec_rules or [""])]
        if rules:
            sec["access_rules"] = rules
        if vis:
            sec["visibility_rules"] = vis
        entry["sections"].append(sec)
        location_mapping[l.code].append(f"@{label}/{name}")
    detail_locations.append(entry)

for entry in list(pt_locations.values()) + detail_locations:
    names = [s["name"] for s in entry["sections"]]
    assert len(names) == len(set(names)), f"duplicate sections in {entry['name']}"

def write_json(rel, obj):
    p = OUT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(obj, indent=2), encoding="utf-8")


write_json("manifest.json", {
    "name": "Gravity Circuit Archipelago", "game_name": "Gravity Circuit (MuratDev's Implementation)", "package_version": VERSION,
    "package_uid": "gravity_circuit_ap", "author": "Murat Kaan Tekeli",
    "min_poptracker_version": "0.25.0",
    "variants": {"standard": {"display_name": "Map Tracker", "flags": ["ap"]}},
})
write_json("items/items.json", items)
write_json("maps/maps.json", [{"name": "Overview", "img": "images/maps/overview.png",
                               "location_size": 30, "location_border_thickness": 2}] +
           [{"name": sm.name, "img": f"images/maps/{sm.file}.png", "location_size": sm.location_size(),
             "location_border_thickness": sm.border()} for sm in stage_maps.values()])
write_json("locations/locations.json", list(pt_locations.values()) + detail_locations)
TAB_ORDER = (["Overview", "Hub", "Opening Stage"] + [s.name for s in data.STAGES]
             + ["Fortress 1", "Fortress 2", "Fortress 3"])


def grid(codes, per_row):
    return [codes[i:i + per_row] for i in range(0, len(codes), per_row)]


def group(header, rows):
    return {"type": "group", "header": header, "dock": "top",
            "content": {"type": "itemgrid", "item_margin": "3,3", "item_size": 36, "rows": rows}}


item_panel = {"type": "array", "orientation": "vertical", "margin": "2,2", "content": [
    group("Stage Access", grid(grids["stages"], 4)),
    group("Circuit Bosses", grid(grids["bosses"], 4)),
    group("Upgrades", [["health", "burstup", "chip_2", "rescue_token"]]),
    group("Booster Chips", grid([c for c in grids["chips"] if c != "chip_2"], 6)),
    group("Burst Techniques", grid(grids["bursts"], 6)),
    group("Armor Paints", grid(grids["paints"], 5)),
]}
settings_panel = {"type": "itemgrid", "item_margin": "3,3", "item_size": 36,
                  "rows": [[c for c, *_ in SETTINGS] + ["opt_bosses_required"]]}
write_json("layouts/tracker.json", {
    "tracker_items": item_panel,
    "settings_popup": {"type": "array", "margin": "5", "content": [
        {"type": "group", "header": "Settings (set automatically when connected)", "content": settings_panel}]},
    "tracker_default": {"type": "container", "background": "#10131a", "content": {
        "type": "dock", "dropshadow": True, "content": [
            {"type": "dock", "dock": "left", "v_alignment": "stretch", "content": [
                {"type": "group", "header": "Items", "dock": "top",
                 "content": {"type": "layout", "key": "tracker_items"},
                 "header_content": {"type": "button_popup", "style": "settings",
                                    "popup_background": "#dd1b2230", "layout": "settings_popup"}}]},
            {"type": "tabbed", "tabs": [{"title": t, "content": {"type": "map", "maps": [t]}}
                                        for t in TAB_ORDER]}]}},
    "tracker_horizontal": {"type": "layout", "key": "tracker_default"},
    "tracker_broadcast": {"type": "container", "background": "#00000000",
                          "content": {"type": "layout", "key": "tracker_items"}},
})

(OUT / "scripts" / "autotracking").mkdir(parents=True, exist_ok=True)
(OUT / "scripts" / "init.lua").write_text("""-- Gravity Circuit Archipelago PopTracker pack
ScriptHost:LoadScript("scripts/logic.lua")
Tracker:AddItems("items/items.json")
Tracker:AddMaps("maps/maps.json")
Tracker:AddLocations("locations/locations.json")
Tracker:AddLayouts("layouts/tracker.json")
ScriptHost:LoadScript("scripts/autotracking/archipelago.lua")
""", encoding="utf-8")

stage_keys = ", ".join(f'"{s.key.lower()}"' for s in data.STAGES)
(OUT / "scripts" / "logic.lua").write_text(f"""-- Logic helpers, mirroring apworld/gravity_circuit/rules.py and regions.py
STAGE_KEYS = {{ {stage_keys} }}

function has(code)
  return Tracker:ProviderCountForCode(code) > 0
end

-- stage select: needs that stage's Access item
function stage(key)
  return has("access_" .. key)
end

-- checks that expect the Air Jumper chip under normal logic
function airjumper()
  return has("opt_hard_logic") or has("chip_2")
end

function bossCount()
  local n = 0
  for _, k in ipairs(STAGE_KEYS) do
    if has("boss_" .. k) then n = n + 1 end
  end
  return n
end

function bosses(n)
  return bossCount() >= tonumber(n)
end

-- Fortress stage n: opens after the required number of Circuit bosses, or with Fortress Access Items,
-- Fortress 1 and 2 open with their own Access item
function fortress(n)
  n = tonumber(n) or 1
  if has("opt_fortress_access") and n < 3 then
    return has("access_final_" .. n)
  end
  return bossCount() >= Tracker:ProviderCountForCode("opt_bosses_required")
end

-- Nurse's shop: every enterable stage gives 8 rescue tokens, plus Rescue Token items
function tokens(n)
  local count = Tracker:ProviderCountForCode("rescue_token")
  for _, k in ipairs(STAGE_KEYS) do
    if stage(k) then count = count + 8 end
  end
  return count >= tonumber(n)
end

-- NPCs that move into the hub after rescues in a stage and one boss clear
function npc(key)
  return stage(key) and bosses(1)
end
""", encoding="utf-8")

with open(OUT / "scripts" / "autotracking" / "item_mapping.lua", "w", encoding="utf-8") as f:
    f.write("-- GENERATED by tools/gen_poptracker.py\nITEM_MAPPING = {\n")
    for ap_id, (code, kind) in sorted(item_mapping.items()):
        f.write(f'  [{ap_id}] = {{ "{code}", "{kind}" }},\n')
    f.write("}\n")
with open(OUT / "scripts" / "autotracking" / "location_mapping.lua", "w", encoding="utf-8") as f:
    f.write("-- GENERATED by tools/gen_poptracker.py\nLOCATION_MAPPING = {\n")
    for ap_id, paths in sorted(location_mapping.items()):
        f.write(f"  [{ap_id}] = {{ " + ", ".join(json.dumps(x) for x in paths) + " },\n")
    f.write("}\nSTAGE_TABS = {\n")
    for k, (_, name) in pt_maps.MAPS.items():
        f.write(f'  ["{k}"] = "{name}",\n')
    f.write("}\n-- map id -> { tab, world->image scale, crop x, crop y }\nMAP_TRANSFORM = {\n")
    for k, sm in stage_maps.items():
        f.write(f'  ["{k}"] = {{ "{sm.name}", {sm.scale}, {sm.crop[0]}, {sm.crop[1]} }},\n')
    f.write("}\nBOSS_LOCATIONS = {\n")
    for ap_id, code in sorted(boss_locations.items()):
        f.write(f'  [{ap_id}] = "{code}",\n')
    f.write("}\n")

(OUT / "scripts" / "autotracking" / "archipelago.lua").write_text("""-- Archipelago autotracking
ScriptHost:LoadScript("scripts/autotracking/item_mapping.lua")
ScriptHost:LoadScript("scripts/autotracking/location_mapping.lua")

CUR_INDEX = -1
SLOT_DATA = {}

local SETTING_KEYS = {
  opt_money_caches = "money_caches",
  opt_small_money_caches = "small_money_caches",
  opt_data_chips = "data_chips",
  opt_random_data_chips = "random_data_chips",
  opt_shopsanity = "shopsanity",
  opt_fortress_access = "fortress_access",
}

local function resetItem(code)
  local obj = Tracker:FindObjectForCode(code)
  if not obj then return end
  if obj.Type == "toggle" then
    obj.Active = false
  elseif obj.Type == "consumable" then
    obj.AcquiredCount = 0
  end
end

local function applySlotData(slot_data)
  for code, key in pairs(SETTING_KEYS) do
    local obj = Tracker:FindObjectForCode(code)
    if obj and slot_data[key] ~= nil then obj.Active = slot_data[key] and true or false end
  end
  local hard = Tracker:FindObjectForCode("opt_hard_logic")
  if hard and slot_data.logic_difficulty ~= nil then hard.Active = slot_data.logic_difficulty == 1 end
  local req = Tracker:FindObjectForCode("opt_bosses_required")
  if req and slot_data.bosses_required then req.AcquiredCount = slot_data.bosses_required end
end

function onClear(slot_data)
  CUR_INDEX = -1
  SLOT_DATA = slot_data or {}
  for _, paths in pairs(LOCATION_MAPPING) do
    for _, path in ipairs(paths) do
      local obj = Tracker:FindObjectForCode(path)
      if obj then
        obj.AvailableChestCount = obj.ChestCount
        if Highlight then obj.Highlight = Highlight.None end
      end
    end
  end
  for _, entry in pairs(ITEM_MAPPING) do resetItem(entry[1]) end
  for _, code in pairs(BOSS_LOCATIONS) do resetItem(code) end
  applySlotData(SLOT_DATA)
  watchDataStorage()
end

function onItem(index, item_id, item_name, player_number)
  if index <= CUR_INDEX then return end
  CUR_INDEX = index
  local entry = ITEM_MAPPING[item_id]
  if not entry then return end
  local obj = Tracker:FindObjectForCode(entry[1])
  if not obj then return end
  if obj.Type == "toggle" then
    obj.Active = true
  elseif obj.Type == "consumable" then
    obj.AcquiredCount = obj.AcquiredCount + obj.Increment
  end
end

function onLocation(location_id, location_name)
  for _, path in ipairs(LOCATION_MAPPING[location_id] or {}) do
    local obj = Tracker:FindObjectForCode(path)
    if obj then
      obj.AvailableChestCount = 0
      if Highlight then obj.Highlight = Highlight.None end
    end
  end
  local boss = BOSS_LOCATIONS[location_id]
  if boss then
    local obj = Tracker:FindObjectForCode(boss)
    if obj then obj.Active = true end
  end
end

-- Map tab follows the player: the game mod stores the current map in data storage.
local function stageKey()
  return string.format("gravity_circuit_stage_%d_%d", Archipelago.TeamNumber or 0, Archipelago.PlayerNumber or 0)
end
local function posKey()
  return string.format("gravity_circuit_pos_%d_%d", Archipelago.TeamNumber or 0, Archipelago.PlayerNumber or 0)
end
local function hintsKey()
  return string.format("_read_hints_%d_%d", Archipelago.TeamNumber or 0, Archipelago.PlayerNumber or 0)
end

local function showStage(value)
  local tab = STAGE_TABS[value or ""]
  local follow = Tracker:FindObjectForCode("opt_follow_map")
  if tab and (not follow or follow.Active) then Tracker:UiHint("ActivateTab", tab) end
end

-- Hinted locations of this slot are highlighted: progression as priority, traps as avoid.
local function showHints(hints)
  if not Highlight or type(hints) ~= "table" then return end
  for _, hint in ipairs(hints) do
    if hint.finding_player == Archipelago.PlayerNumber then
      local flags = hint.item_flags or 0
      local level = Highlight.NoPriority
      if hint.found then
        level = Highlight.None
      elseif flags % 2 == 1 then
        level = Highlight.Priority
      elseif math.floor(flags / 4) % 2 == 1 then
        level = Highlight.Avoid
      end
      for _, path in ipairs(LOCATION_MAPPING[hint.location] or {}) do
        local obj = Tracker:FindObjectForCode(path)
        if obj then obj.Highlight = level end
      end
    end
  end
end

-- "MAPID,x,y" in world pixels: zoom in on the map and keep it centered on Kai.
local FOLLOW_ZOOM = "3"
local zoomedMap = nil
local function showPosition(value)
  if type(value) ~= "string" then return end
  local follow = Tracker:FindObjectForCode("opt_follow_pos")
  if follow and not follow.Active then
    zoomedMap = nil
    return
  end
  local map, x, y = value:match("^([%w_]+),(-?[%d%.]+),(-?[%d%.]+)$")
  local t = map and MAP_TRANSFORM[map]
  if not t then return end
  local ix = math.floor(tonumber(x) * t[2] - t[3])
  local iy = math.floor(tonumber(y) * t[2] - t[4])
  if zoomedMap ~= map then
    Tracker:UiHint("Zoom " .. t[1], FOLLOW_ZOOM)
    zoomedMap = map
  end
  Tracker:UiHint("Pan " .. t[1], ix .. "," .. iy)
end

local function onDataStorage(key, value)
  if key == stageKey() then
    showStage(value)
  elseif key == posKey() then
    showPosition(value)
  elseif key == hintsKey() then
    showHints(value)
  end
end

function watchDataStorage()
  if not Archipelago.PlayerNumber or Archipelago.PlayerNumber < 0 then return end
  local keys = { stageKey(), posKey(), hintsKey() }
  Archipelago:SetNotify(keys)
  Archipelago:Get(keys)
end

Archipelago:AddSetReplyHandler("gc datastorage", function(key, value, old) onDataStorage(key, value) end)
Archipelago:AddRetrievedHandler("gc retrieved", function(key, value) onDataStorage(key, value) end)
Archipelago:AddClearHandler("gc clear", onClear)
Archipelago:AddItemHandler("gc item", onItem)
Archipelago:AddLocationHandler("gc location", onLocation)
""", encoding="utf-8")

dist = ROOT / "dist"
dist.mkdir(exist_ok=True)
zpath = dist / "gravity_circuit_poptracker.zip"
with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
    for p in sorted(OUT.rglob("*")):
        if p.is_file():
            z.write(p, p.relative_to(OUT).as_posix())
print(f"wrote {zpath}: {len(items)} items, {len(pt_locations)} overview pins, "
      f"{len(detail_locations)} stage-map pins, {len(location_mapping)} locations")
