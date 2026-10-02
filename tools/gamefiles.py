"""Read-only access to the files packed inside the user's GravityCircuit.exe (a fused LÖVE executable)."""
import base64
import functools
import os
import pathlib
import zipfile
from typing import Any

from bitser import loads

DEFAULT_EXE = r"C:\Program Files (x86)\Steam\steamapps\common\Gravity Circuit\win64_steam\GravityCircuit.exe"

# game map id -> map file (content/maps/<file>.gcl)
MAP_FILES = {
    "HUB": "hub-area",
    "OPENING": "opening-level",
    "OPTIC": "optic-area",
    "PATCH": "patch-area",
    "COOLER": "cooler-area",
    "ELEC": "power-area",
    "SHIFT": "shift-area",
    "WAVE": "wave-area",
    "BREAK": "break-area",
    "CIPHER": "cipher-area",
    "FINAL_1": "final-area-1",
    "FINAL_2": "final-area-2",
    "FINAL_3": "final-area-3",
}
PLAYABLE_MAPS = [key for key in MAP_FILES if key != "HUB"]


@functools.lru_cache(maxsize=1)
def archive() -> zipfile.ZipFile:
    exe = pathlib.Path(os.environ.get("GRAVITY_CIRCUIT_EXE", DEFAULT_EXE))
    if not exe.exists():
        raise SystemExit(f"Gravity Circuit not found at {exe}; set GRAVITY_CIRCUIT_EXE to GravityCircuit.exe")
    return zipfile.ZipFile(exe)


def read_text(name: str) -> str:
    return archive().read(name).decode("utf-8", "replace")


def names():
    return archive().namelist()


@functools.lru_cache(maxsize=None)
def load_map(file_name: str) -> Any:
    return loads(base64.b64decode(archive().read("content/maps/" + file_name)))
