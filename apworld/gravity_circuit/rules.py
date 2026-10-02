from typing import TYPE_CHECKING, Dict

from worlds.generic.Rules import add_rule, set_rule

from .data import (AIR_JUMPER_LOCATIONS, BURST_BOSS_STAGE, CHIP_TOKENS, DATA_CHIP_SPECS, FORTRESS, STAGE_BY_KEY,
                   STAGES, access_item)

if TYPE_CHECKING:
    from . import GravityCircuitWorld

FORTRESS_REGION = {key: name for key, name, _, _ in FORTRESS}
RESCUES_PER_STAGE = 8


def _cumulative_chip_costs() -> Dict[int, int]:
    """Token cost of buying each Nurse chip after every cheaper one (chips enter logic cheapest first)."""
    cumulative, running = {}, 0
    for chip, cost in sorted(CHIP_TOKENS.items(), key=lambda kv: (kv[1], kv[0])):
        running += cost
        cumulative[chip] = running
    return cumulative


def set_rules(world: "GravityCircuitWorld") -> None:
    player = world.player
    multiworld = world.multiworld
    access_items = [access_item(stage) for stage in STAGES]
    chip_costs = _cumulative_chip_costs()

    if world.options.logic_difficulty == world.options.logic_difficulty.option_normal:
        for name in AIR_JUMPER_LOCATIONS:
            set_rule(multiworld.get_location(name, player), lambda state: state.has("Chip: Air Jumper", player))

    for location in multiworld.get_locations(player):
        kind = getattr(location, "gc_kind", None)
        if kind == "shopburst" and location.gc_index in BURST_BOSS_STAGE:
            item = access_item(STAGE_BY_KEY[BURST_BOSS_STAGE[location.gc_index]])
            set_rule(location, lambda state, item=item: state.has(item, player))
        elif kind == "shopchip":
            need = chip_costs[location.gc_index]
            set_rule(location, lambda state, need=need:
                     RESCUES_PER_STAGE * state.count_from_list(access_items, player) >= need)

        spec = DATA_CHIP_SPECS.get(location.name)
        if not spec:
            continue
        mode = spec[0]
        if mode == "npc":
            item = access_item(STAGE_BY_KEY[spec[1]])
            set_rule(location, lambda state, item=item:
                     state.has(item, player) and state.has("Boss Defeated", player))
        elif mode == "late":
            add_rule(location, lambda state: state.has("Boss Defeated", player, 8))
        elif mode == "enemy" and "OPENING" not in spec[1]:
            items = [access_item(STAGE_BY_KEY[key]) for key in spec[1] if key in STAGE_BY_KEY]
            regions = [FORTRESS_REGION[key] for key in spec[1] if key in FORTRESS_REGION]
            set_rule(location, lambda state, items=items, regions=regions:
                     state.has_any(items, player) or any(state.can_reach_region(r, player) for r in regions))

    multiworld.completion_condition[player] = lambda state: state.has("Victory", player)
