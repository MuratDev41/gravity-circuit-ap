from typing import Any, Dict, List

from BaseClasses import Item, ItemClassification, Location, Tutorial
from worlds.AutoWorld import WebWorld, World

from .data import (BOSS_HEALTH_RANGES, BOSS_HEALTH_STAGES, FILLER_WEIGHTS, FORTRESS, FORTRESS_ACCESS, GAME_NAME,
                   ITEM_BY_NAME, ITEM_GROUPS, ITEM_NAME_TO_ID, ITEMS, LOCATION_GROUPS, LOCATION_NAME_TO_ID, LOCATIONS,
                   MUSIC_BOSS_THEMES, MUSIC_STAGE_THEMES, SHOP_BURSTS, STAGES, TRAP_WEIGHTS, access_item, boss_region,
                   fortress_access_item)
from .options import GravityCircuitOptions
from .regions import create_regions
from .rules import set_rules

CLIENT_VERSION = "1.1.0"

CLASSIFICATION = {
    "progression": ItemClassification.progression,
    "useful": ItemClassification.useful,
    "filler": ItemClassification.filler,
    "trap": ItemClassification.trap,
}

# location kind -> option that enables it
OPTIONAL_LOCATION_KINDS = {
    "cache": "money_caches",
    "smallcache": "small_money_caches",
    "datachip": "data_chips",
    "datachiprandom": "random_data_chips",
    "shopburst": "shopsanity",
    "shopchip": "shopsanity",
}

SLOT_DATA_OPTIONS = ("bosses_required", "fortress_access", "logic_difficulty", "death_link", "money_caches",
                     "small_money_caches", "data_chips", "random_data_chips", "shopsanity", "burst_link",
                     "knockback_link", "palette_randomizer", "data_chip_markers", "boss_health",
                     "music_shuffle")
BOOL_SLOT_DATA = ("fortress_access", "death_link", "knockback_link", "data_chip_markers", "money_caches",
                  "small_money_caches", "data_chips", "random_data_chips", "shopsanity")


FORTRESS_ITEMS = {fortress_access_item(region) for region, _ in FORTRESS_ACCESS}


class GravityCircuitItem(Item):
    game = GAME_NAME


class GravityCircuitLocation(Location):
    game = GAME_NAME


class GravityCircuitWeb(WebWorld):
    theme = "partyTime"
    tutorials = [Tutorial(
        "Multiworld Setup Guide",
        "How to install the Gravity Circuit Archipelago mod and connect to a multiworld.",
        "English",
        "setup_en.md",
        "setup/en",
        ["Murat Kaan Tekeli"],
    )]


class GravityCircuitWorld(World):
    """Gravity Circuit is a fast 2D action platformer: grapple with your hookshot, punch robots, and
    take back the Guardian Corps HQ from the Virus Army, one Circuit stage at a time."""

    game = GAME_NAME
    web = GravityCircuitWeb()
    options_dataclass = GravityCircuitOptions
    options: GravityCircuitOptions

    item_name_to_id = ITEM_NAME_TO_ID
    location_name_to_id = LOCATION_NAME_TO_ID
    item_name_groups = ITEM_GROUPS
    location_name_groups = LOCATION_GROUPS

    ut_can_gen_without_yaml = True

    starting_stages: List[str]
    boss_hp: Dict[str, int]
    music_map: Dict[str, str]

    @staticmethod
    def interpret_slot_data(slot_data: Dict[str, Any]) -> Dict[str, Any]:
        return slot_data

    def generate_early(self) -> None:
        passthrough = getattr(self.multiworld, "re_gen_passthrough", {})
        if self.game in passthrough:
            # Universal Tracker: options come from slot data, and the starting Access items arrive from the
            # server as received items, so none are rolled here.
            slot_data = passthrough[self.game]
            for key in SLOT_DATA_OPTIONS:
                if key in slot_data:
                    getattr(self.options, key).value = int(slot_data[key])
            self.starting_stages = []
            self.boss_hp = slot_data.get("boss_hp", {})
            self.music_map = slot_data.get("music_map", {})
            return

        stages = [access_item(s) for s in STAGES]
        self.random.shuffle(stages)
        self.starting_stages = stages[:self.options.starting_stages.value]
        for name in self.starting_stages:
            self.multiworld.push_precollected(self.create_item(name))

        self.boss_hp = {}
        hp_range = BOSS_HEALTH_RANGES.get(self.options.boss_health.value)
        if hp_range:
            self.boss_hp = {key: self.random.randint(*hp_range) for key in BOSS_HEALTH_STAGES}

        self.music_map = {}
        if self.options.music_shuffle == self.options.music_shuffle.option_mixed:
            pools = [MUSIC_STAGE_THEMES + MUSIC_BOSS_THEMES]
        elif self.options.music_shuffle == self.options.music_shuffle.option_shuffled:
            pools = [MUSIC_STAGE_THEMES, MUSIC_BOSS_THEMES]
        else:
            pools = []
        for pool in pools:
            shuffled = list(pool)
            self.random.shuffle(shuffled)
            self.music_map.update(zip(pool, shuffled))

    def location_enabled(self, kind: str) -> bool:
        option = OPTIONAL_LOCATION_KINDS.get(kind)
        return option is None or bool(getattr(self.options, option).value)

    def create_regions(self) -> None:
        regions = create_regions(self)

        for loc in LOCATIONS:
            if not self.location_enabled(loc.kind):
                continue
            region = regions[loc.region]
            location = GravityCircuitLocation(self.player, loc.name, loc.code, region)
            location.gc_kind, location.gc_index = loc.kind, loc.index
            region.locations.append(location)

        for stage in STAGES:
            region = regions[boss_region(stage)]
            event = GravityCircuitLocation(self.player, f"{stage.name} - Circuit Cleared", None, region)
            event.place_locked_item(self.create_event("Boss Defeated"))
            region.locations.append(event)

        _, final_region, final_boss, _ = FORTRESS[-1]
        region = regions[final_region]
        goal = GravityCircuitLocation(self.player, f"{final_region} - {final_boss} Defeated", None, region)
        goal.place_locked_item(self.create_event("Victory"))
        region.locations.append(goal)

    def create_item(self, name: str) -> GravityCircuitItem:
        data = ITEM_BY_NAME[name]
        classification = CLASSIFICATION[data.classification]
        if data.kind == "token" and not self.options.shopsanity:
            # Rescue tokens only matter to logic for the Nurse's shop checks.
            classification = ItemClassification.filler
        return GravityCircuitItem(name, classification, data.code, self.player)

    def create_event(self, name: str) -> GravityCircuitItem:
        return GravityCircuitItem(name, ItemClassification.progression, None, self.player)

    def create_items(self) -> None:
        pool: List[Item] = []
        for data in ITEMS:
            if data.name in self.starting_stages:
                continue
            if data.kind == "burst" and data.game_id in SHOP_BURSTS and not self.options.shopsanity:
                continue
            if data.name in FORTRESS_ITEMS and not self.options.fortress_access:
                continue
            pool += [self.create_item(data.name) for _ in range(data.count)]

        unfilled = len(self.multiworld.get_unfilled_locations(self.player))
        pool += [self.create_item(self.get_filler_item_name()) for _ in range(unfilled - len(pool))]
        self.multiworld.itempool += pool

    def set_rules(self) -> None:
        set_rules(self)

    def get_filler_item_name(self) -> str:
        traps = {name: w for name, w in TRAP_WEIGHTS.items() if name in self.options.enabled_traps.value}
        weights = FILLER_WEIGHTS
        if traps and self.random.randint(1, 100) <= self.options.trap_chance.value:
            weights = traps
        return self.random.choices(list(weights), weights=list(weights.values()))[0]

    def fill_slot_data(self) -> Dict[str, Any]:
        slot_data: Dict[str, Any] = {key: getattr(self.options, key).value for key in SLOT_DATA_OPTIONS}
        for key in BOOL_SLOT_DATA:
            slot_data[key] = bool(slot_data[key])
        slot_data["boss_hp"] = self.boss_hp
        slot_data["music_map"] = self.music_map
        slot_data["mod_version"] = CLIENT_VERSION
        return slot_data
