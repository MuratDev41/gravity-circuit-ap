from dataclasses import dataclass

from Options import Choice, DeathLink, DefaultOnToggle, PerGameCommonOptions, Range, StartInventoryPool, Toggle


class BossesRequired(Range):
    """How many of the eight Circuit bosses must be defeated before the Fortress opens on the stage select.
    Only the Circuit stage bosses count; Fortress bosses do not."""
    display_name = "Bosses Required"
    range_start = 1
    range_end = 8
    default = 8


class StartingStages(Range):
    """How many random stage Access items you start with."""
    display_name = "Starting Stages"
    range_start = 1
    range_end = 8
    default = 1


class FortressAccess(Toggle):
    """Fortress 1 and Fortress 2 are opened by their own Access items, found in the multiworld, instead of by
    bosses. Fortress 3 (the final boss) still needs the number of Circuit bosses set by Bosses Required.

    Only the 8 Circuit stage bosses count toward Bosses Required: clearing Fortress 1 or 2, or finding their Access
    items, does not. Fortress 1 and 2 are never needed to reach the goal."""
    display_name = "Fortress Access Items"


class MoneyCaches(DefaultOnToggle):
    """The big money crates (the ones that burst into 100-400 credits) are checks the first time you break each one.
    Adds 52 locations: 36 in the Circuit stages, 3 in the Opening Stage, 13 in the Fortress."""
    display_name = "Money Caches"


class SmallMoneyCaches(DefaultOnToggle):
    """The small pickup boxes are checks the first time you break each one.
    Adds 335 locations: 215 in the Circuit stages, 21 in the Opening Stage, 99 in the Fortress."""
    display_name = "Small Money Caches"


class DataChips(DefaultOnToggle):
    """Data chips you get reliably are checks: the 20 NPC chips in the hub, the 11 boss chips and the
    2 stage miniboss chips. (Kai, Unknown Bot, Kernel's boss form and the Commander are left out: they only
    appear at or after the final boss.)"""
    display_name = "Data Chips"


class RandomDataChips(Toggle):
    """The 43 enemy data chips are checks too. Enemies drop their chip at random (the chance goes up each
    time one fails to drop), so these can take a few repeat kills."""
    display_name = "Random Data Chips"


class Shopsanity(DefaultOnToggle):
    """Every slot in Nega's burst shop (19) and the Nurse's chip shop (19) is a check. Buying a slot sends
    whatever is there; the shop overlay shows what each slot holds and progression items get hinted.
    Rising Upper, Heavenly Piledrive and Catch Interrupt join the item pool."""
    display_name = "Shopsanity"


class TrapChance(Range):
    """Percent chance that each filler item is a trap instead (Damage Trap: lose 8 HP, never lethal;
    Credit Leak Trap: lose 250 credits)."""
    display_name = "Trap Chance"
    range_start = 0
    range_end = 100
    default = 0


class LogicDifficulty(Choice):
    """Normal: a couple of hard-to-reach pickups expect the Air Jumper chip.
    Hard: everything is in logic with the starting kit (hookshot tricks)."""
    display_name = "Logic Difficulty"
    option_normal = 0
    option_hard = 1
    default = 0


@dataclass
class GravityCircuitOptions(PerGameCommonOptions):
    start_inventory_from_pool: StartInventoryPool
    bosses_required: BossesRequired
    starting_stages: StartingStages
    fortress_access: FortressAccess
    money_caches: MoneyCaches
    small_money_caches: SmallMoneyCaches
    data_chips: DataChips
    random_data_chips: RandomDataChips
    shopsanity: Shopsanity
    trap_chance: TrapChance
    logic_difficulty: LogicDifficulty
    death_link: DeathLink
