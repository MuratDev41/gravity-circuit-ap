from dataclasses import dataclass

from Options import (Choice, DeathLink, DefaultOnToggle, OptionSet, PerGameCommonOptions, Range, StartInventoryPool,
                     Toggle)


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
    """Percent chance that each filler item is a trap instead. Which traps can appear is set by Enabled Traps."""
    display_name = "Trap Chance"
    range_start = 0
    range_end = 100
    default = 0


class EnabledTraps(OptionSet):
    """Traps that can replace filler.
    Damage Trap: lose 8 HP, never lethal. Credit Leak Trap: lose 250 credits.
    Knockback Trap: knocked back like a hit, no damage. Burst Drain Trap: empties your bursts (with Burst Link,
    only your own; the shared ones stay).
    Palette Trap: everything changes colour for 20 seconds. Pixelate Trap: the screen pixelates for 15 seconds.
    Earthquake Trap: the screen shakes for 8 seconds. Flip Trap: the screen turns upside down for 10 seconds."""
    display_name = "Enabled Traps"
    valid_keys = ["Damage Trap", "Credit Leak Trap", "Knockback Trap", "Burst Drain Trap", "Palette Trap",
                  "Pixelate Trap", "Earthquake Trap", "Flip Trap"]
    default = frozenset(valid_keys)


class DataChipMarkers(DefaultOnToggle):
    """With Random Data Chips, enemies whose data chip check is not done yet show an Archipelago icon above them."""
    display_name = "Data Chip Markers"


class BossHealth(Choice):
    """Randomize boss health per stage (vanilla bosses have 32). The final boss keeps its own.
    Weak: 12 to 24. Strong: 36 to 48. Chaotic: 8 to 48."""
    display_name = "Boss Health"
    option_vanilla = 0
    option_weak = 1
    option_strong = 2
    option_chaotic = 3
    default = 0


class MusicShuffle(Choice):
    """Shuffle the music.
    Shuffled: stage themes are shuffled among stage themes, boss themes among boss themes.
    Mixed: stage and boss themes are shuffled together.
    Intros, jingles, the hub and the multi-part final boss themes stay."""
    display_name = "Music Shuffle"
    option_off = 0
    alias_false = 0
    option_shuffled = 1
    option_mixed = 2
    default = 0


class LogicDifficulty(Choice):
    """Normal: a couple of hard-to-reach pickups expect the Air Jumper chip.
    Hard: everything is in logic with the starting kit (hookshot tricks)."""
    display_name = "Logic Difficulty"
    option_normal = 0
    option_hard = 1
    default = 0


class KnockbackLink(Toggle):
    """Getting knocked back by a hit knocks back everyone with Knockback Link, and the other way round. A received
    knockback staggers Kai like a hit without taking health."""
    display_name = "Knockback Link"


class BurstLink(Choice):
    """Share the base burst bar (the first 2 bursts) with other players on your team. Bursts from Burst Boosters
    stay your own.
    Gravity Circuit: shared with other Gravity Circuit players who also chose this.
    Silk Link: shared with Silksong's Silk Link. One burst is 4 Silk of the 9 in the base spool."""
    display_name = "Burst Link"
    option_off = 0
    alias_false = 0
    option_gravity_circuit = 1
    option_silk_link = 2
    default = 0


class PaletteRandomizer(Choice):
    """Recolour sprites with hues picked from the seed, so each seed looks different. Shading stays the same.
    Kai: only Kai.
    Everything: Kai, enemies, bosses and NPCs, each with its own hue. Stages and the HUD keep their colours."""
    display_name = "Palette Randomizer"
    option_off = 0
    alias_false = 0
    option_kai = 1
    option_everything = 2
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
    enabled_traps: EnabledTraps
    logic_difficulty: LogicDifficulty
    death_link: DeathLink
    knockback_link: KnockbackLink
    burst_link: BurstLink
    palette_randomizer: PaletteRandomizer
    data_chip_markers: DataChipMarkers
    boss_health: BossHealth
    music_shuffle: MusicShuffle
