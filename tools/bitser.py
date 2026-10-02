"""Decoder for the bitser serialization format used by Gravity Circuit's map and save files."""
import struct
from typing import Any, List

TILE_FIELDS = ("id", "tileset", "autoTile", "frameOffset", "scaleX", "scaleY", "isPrefab",
               "blockX", "blockY", "blockWidth", "blockHeight", "variantOffset")


class _Reader:
    def __init__(self, buffer: bytes):
        self.buffer = buffer
        self.pos = 0

    def byte(self) -> int:
        value = self.buffer[self.pos]
        self.pos += 1
        return value

    def string(self, length: int) -> str:
        value = self.buffer[self.pos:self.pos + length]
        self.pos += length
        return value.decode("latin1")

    def struct(self, fmt: str, size: int) -> Any:
        value = struct.unpack("<" + fmt, self.buffer[self.pos:self.pos + size])[0]
        self.pos += size
        return value


def loads(buffer: bytes) -> Any:
    reader = _Reader(buffer)
    seen: List[Any] = []

    def remember(value: Any) -> Any:
        seen.append(value)
        return value

    def read_table(table: dict) -> dict:
        for i in range(1, value() + 1):
            table[i] = value()
        for _ in range(value()):
            key = value()
            table[key] = value()
        return table

    def value() -> Any:
        tag = reader.byte()
        if tag < 128:
            return tag - 27
        if tag < 192:
            return seen[tag - 128]
        if tag < 224:
            return remember(reader.string(tag - 192))
        if tag < 240:
            return remember(("RESOURCE", reader.string(tag - 224)))
        if tag == 240:
            return read_table(remember({}))
        if tag == 241:
            seen.append(None)
            index = len(seen) - 1
            seen[index] = ("RESOURCE", value())
            return seen[index]
        if tag == 242:
            instance = remember({})
            instance["__class"] = value()
            return read_table(instance)
        if tag == 243:
            return seen[value()]
        if tag == 244:
            return remember(reader.string(value()))
        if tag == 245:
            return reader.struct("i", 4)
        if tag == 246:
            return reader.struct("d", 8)
        if tag == 247:
            return None
        if tag == 248:
            return False
        if tag == 249:
            return True
        if tag == 250:
            return reader.struct("h", 2)
        if tag == 252:
            tile = remember({"__tile": True})
            tile["version"] = value()
            for field in TILE_FIELDS:
                tile[field] = value()
            return tile
        raise ValueError(f"unsupported bitser tag {tag} at offset {reader.pos}")

    return value()
