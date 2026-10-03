"""Region graph.

Menu -> Opening Stage -> Hub
Hub -> <Stage> - Start -> <Stage> - Checkpoint N ... -> <Stage> - Boss Room   (requires "<Stage> Access")
Hub -> Fortress 1 -> Fortress 2 -> Fortress 3                                  (requires bosses_required defeats)

With fortress_access, Fortress 1 and 2 are entered from the Hub with their own Access items instead, and only
Fortress 3 needs bosses_required defeats.

Stage subregions follow the order of the stage select's checkpoint menu.
"""
from typing import TYPE_CHECKING, Dict

from BaseClasses import Region

from .data import FORTRESS, STAGES, access_item, boss_region, fortress_access_item, section_region

if TYPE_CHECKING:
    from . import GravityCircuitWorld


def create_regions(world: "GravityCircuitWorld") -> Dict[str, Region]:
    player = world.player
    multiworld = world.multiworld
    regions: Dict[str, Region] = {}

    def add(name: str) -> Region:
        region = Region(name, player, multiworld)
        regions[name] = region
        multiworld.regions.append(region)
        return region

    menu = add("Menu")
    opening = add("Opening Stage")
    hub = add("Hub")
    menu.connect(opening)
    opening.connect(hub, "Return to HQ")

    for stage in STAGES:
        names = [section_region(stage, i) for i in range(stage.sections)] + [boss_region(stage)]
        sections = [add(name) for name in names]
        hub.connect(sections[0], f"Stage Select: {stage.name}",
                    lambda state, item=access_item(stage): state.has(item, player))
        for current, following in zip(sections, sections[1:]):
            current.connect(following, f"{current.name} -> {following.name}")

    fortress = [add(name) for _, name, _, _ in FORTRESS]
    required = world.options.bosses_required.value
    if world.options.fortress_access:
        for region in fortress[:-1]:
            hub.connect(region, f"Stage Select: {region.name}",
                        lambda state, item=fortress_access_item(region.name): state.has(item, player))
        hub.connect(fortress[-1], f"Stage Select: {fortress[-1].name}",
                    lambda state: state.has("Boss Defeated", player, required))
    else:
        hub.connect(fortress[0], "Stage Select: Fortress",
                    lambda state: state.has("Boss Defeated", player, required))
        for current, following in zip(fortress, fortress[1:]):
            current.connect(following, f"{current.name} -> {following.name}")

    return regions
