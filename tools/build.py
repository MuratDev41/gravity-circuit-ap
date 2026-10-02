"""Build the release artifacts into dist/.

    python tools/build.py               client data table, gravity_circuit.apworld and the release zip
    python tools/build.py --poptracker  also the PopTracker pack (needs the game and an in-game map export)
"""
import argparse
import json
import pathlib
import runpy
import zipfile

import gen_lua_data

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORLD = ROOT / "apworld" / "gravity_circuit"
CLIENT = ROOT / "client"
PACKAGING = ROOT / "packaging"
DIST = ROOT / "dist"

RELEASE_FILES = ["README.md", "Gravity Circuit.yaml", "Install Mod.bat", "Uninstall Mod.bat", "install.ps1"]


def version() -> str:
    return json.loads((WORLD / "archipelago.json").read_text(encoding="utf-8"))["world_version"]


def source_files(folder: pathlib.Path):
    return sorted(p for p in folder.rglob("*") if p.is_file() and "__pycache__" not in p.parts)


def build_apworld() -> pathlib.Path:
    target = DIST / "gravity_circuit.apworld"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in source_files(WORLD):
            archive.write(path, "gravity_circuit/" + path.relative_to(WORLD).as_posix())
    return target


def build_release(apworld: pathlib.Path) -> pathlib.Path:
    top = f"GravityCircuit-Archipelago-{version()}/"
    target = DIST / f"GravityCircuit-Archipelago-{version()}.zip"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in RELEASE_FILES:
            archive.write(PACKAGING / name, top + name)
        archive.write(apworld, top + apworld.name)
        for path in source_files(CLIENT):
            archive.write(path, top + "mod/" + path.relative_to(CLIENT).as_posix())
    return target


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--poptracker", action="store_true", help="also build the PopTracker pack")
    args = parser.parse_args()

    DIST.mkdir(exist_ok=True)
    gen_lua_data.main()
    apworld = build_apworld()
    print(f"wrote {apworld.relative_to(ROOT)}")
    release = build_release(apworld)
    print(f"wrote {release.relative_to(ROOT)}")
    if args.poptracker:
        runpy.run_path(str(ROOT / "tools" / "gen_poptracker.py"), run_name="__main__")


if __name__ == "__main__":
    main()
