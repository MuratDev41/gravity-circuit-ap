"""Consistency checks for the world data. Run with: python -m unittest discover tests"""
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "apworld" / "gravity_circuit"))
sys.path.insert(0, str(ROOT / "tools"))

import data  # noqa: E402
import gen_lua_data  # noqa: E402


class DataTests(unittest.TestCase):
    def test_ids_and_names_are_unique(self):
        for collection in (data.ITEMS, data.LOCATIONS):
            codes = [entry.code for entry in collection]
            names = [entry.name for entry in collection]
            self.assertEqual(len(codes), len(set(codes)))
            self.assertEqual(len(names), len(set(names)))

    def test_totals(self):
        self.assertEqual(len(data.ITEMS), 70)
        self.assertEqual(len(data.LOCATIONS), 593)
        kinds = {}
        for loc in data.LOCATIONS:
            kinds[loc.kind] = kinds.get(loc.kind, 0) + 1
        self.assertEqual(kinds["rescue"], 64)
        self.assertEqual(kinds["cache"], 52)
        self.assertEqual(kinds["smallcache"], 335)
        self.assertEqual(kinds["datachip"] + kinds["datachiprandom"], 76)
        self.assertEqual(kinds["shopburst"] + kinds["shopchip"], 38)

    def test_chip_tokens_match_rescues(self):
        self.assertEqual(sum(data.CHIP_TOKENS.values()), 64)
        self.assertEqual(set(data.CHIP_TOKENS), set(data.CHIPS))

    def test_locations_use_known_regions(self):
        regions = {"Opening Stage", "Hub"} | {name for _, name, _, _ in data.FORTRESS}
        for stage in data.STAGES:
            regions |= {data.section_region(stage, i) for i in range(stage.sections)}
            regions.add(data.boss_region(stage))
        for loc in data.LOCATIONS:
            self.assertIn(loc.region, regions, loc.name)

    def test_filler_weights_reference_items(self):
        for name in list(data.FILLER_WEIGHTS) + list(data.TRAP_WEIGHTS):
            self.assertIn(name, data.ITEM_BY_NAME)

    def test_client_data_is_up_to_date(self):
        current = (ROOT / "client" / "archipelago" / "data.lua").read_text(encoding="utf-8")
        self.assertEqual(current, gen_lua_data.render(), "run python tools/gen_lua_data.py")


if __name__ == "__main__":
    unittest.main()
