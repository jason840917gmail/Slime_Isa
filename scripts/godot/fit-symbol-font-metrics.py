"""Gives the UI's symbol fallback font the line metrics of the UI font.

Godot sizes a Label by the tallest font in its chain (`Font.get_height` takes the largest ascent
plus descent of the font and its fallbacks), so Noto Sans Symbols 2's deep descent made every
single-line label taller (a 22 px label 38 px instead of Source Sans 3's 32). This copies the UI
font's vertical metrics (hhea ascender/descender/lineGap, OS/2 typo and win metrics, scaled to the
symbol font's units per em) into the symbol font, in place, and fixes the checksums. Glyph outlines
do not change. Noto Sans Symbols 2 is SIL OFL with no Reserved Font Name, so a modified copy may
keep its name.

Usage: python scripts/godot/fit-symbol-font-metrics.py [--check]
  --check  exit 1 if the symbol font's metrics differ from the UI font's (no write)

After a write, let the Godot editor reimport the font (or run a headless --import when no editor
has the project open). docs/godot/UI_THEME.md "Symbols".
"""
import struct
import sys
from pathlib import Path

FONTS = Path(__file__).resolve().parents[2] / "godot" / "game" / "ui" / "theme" / "fonts"
UI_FONT = FONTS / "source-sans-3" / "SourceSans3[wght].ttf"
SYMBOL_FONT = FONTS / "noto-sans-symbols-2" / "NotoSansSymbols2-Regular.ttf"

# (table, offset, struct format) of every vertical line metric FreeType and Godot may read.
FIELDS = {
    "hhea_ascender": ("hhea", 4, ">h"),
    "hhea_descender": ("hhea", 6, ">h"),
    "hhea_line_gap": ("hhea", 8, ">h"),
    "typo_ascender": ("OS/2", 68, ">h"),
    "typo_descender": ("OS/2", 70, ">h"),
    "typo_line_gap": ("OS/2", 72, ">h"),
    "win_ascent": ("OS/2", 74, ">H"),
    "win_descent": ("OS/2", 76, ">H"),
}


def tables(data: bytes) -> dict:
    count = struct.unpack_from(">H", data, 4)[0]
    found = {}
    for index in range(count):
        tag, _checksum, offset, length = struct.unpack_from(">4sIII", data, 12 + 16 * index)
        found[tag.decode("latin-1")] = (12 + 16 * index, offset, length)
    return found


def read_metrics(data: bytes) -> dict:
    table = tables(data)
    units = struct.unpack_from(">H", data, table["head"][1] + 18)[0]
    metrics = {name: struct.unpack_from(fmt, data, table[tag][1] + offset)[0] for name, (tag, offset, fmt) in FIELDS.items()}
    return {"units_per_em": units, **metrics}


def checksum(block: bytes) -> int:
    padded = block + b"\0" * (-len(block) % 4)
    return sum(struct.unpack(">%dI" % (len(padded) // 4), padded)) & 0xFFFFFFFF


def write_metrics(data: bytes, metrics: dict) -> bytes:
    out = bytearray(data)
    table = tables(data)
    for name, (tag, offset, fmt) in FIELDS.items():
        struct.pack_into(fmt, out, table[tag][1] + offset, metrics[name])
    head_offset = table["head"][1]
    struct.pack_into(">I", out, head_offset + 8, 0)
    for record, offset, length in table.values():
        struct.pack_into(">I", out, record + 4, checksum(bytes(out[offset:offset + length])))
    struct.pack_into(">I", out, head_offset + 8, (0xB1B0AFBA - checksum(bytes(out))) & 0xFFFFFFFF)
    return bytes(out)


def main() -> int:
    ui = read_metrics(UI_FONT.read_bytes())
    data = SYMBOL_FONT.read_bytes()
    symbols = read_metrics(data)
    scale = symbols["units_per_em"] / ui["units_per_em"]
    wanted = {name: round(ui[name] * scale) for name in FIELDS}
    current = {name: symbols[name] for name in FIELDS}
    if current == wanted:
        print(f"{SYMBOL_FONT.name}: metrics already match {UI_FONT.name}")
        return 0
    if "--check" in sys.argv:
        print(f"{SYMBOL_FONT.name}: metrics differ from {UI_FONT.name}: {current} != {wanted}")
        return 1
    SYMBOL_FONT.write_bytes(write_metrics(data, wanted))
    print(f"{SYMBOL_FONT.name}: {current} -> {wanted}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
