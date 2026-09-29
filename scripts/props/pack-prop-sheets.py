"""Pack generated terrain prop sources into bottom-anchored frame atlases.

Sources in asset/Originals/props/ hold loose rows of props (2 rows x 4). Each
prop is found as a connected alpha component (small islands such as loose
crystal chips attach to the nearest prop), read in row/column order, and placed
bottom-centred in its own frame. One uniform scale per atlas keeps the props'
relative sizes; a transparent margin keeps every pixel inside its own frame.

Output: asset/MAPS/rocks/<frame>x<frame>-tile_<cols>x<rows>-<name>.png (the rocks
folder naming), used by the wall prop scenes (generate-wall-prop-scenes.py).

Requires Pillow and numpy.

Usage: python scripts/props/pack-prop-sheets.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "items"))
from importlib import import_module  # noqa: E402

items = import_module("pack-item-sheets")  # reuse component detection

ORIGINALS = ROOT / "asset" / "Originals" / "props"
PROMOTED = ROOT / "asset" / "MAPS" / "rocks"

FRAME = 128
PADDING = 4

# atlas name -> (columns, rows, sources; each source holds 8 props in reading order)
ATLASES: dict[str, tuple[int, int, list[str]]] = {
    "crystal-clusters": (8, 2, ["crystal-clusters-a.png", "crystal-clusters-b.png"]),
}


def props_in(path: Path) -> list[Image.Image]:
    source = Image.open(path).convert("RGBA")
    pixels = np.array(source)
    pixels[pixels[:, :, 3] < items.HALO_CUTOFF] = 0
    source = Image.fromarray(pixels)
    return [source.crop(box) for box in items.items_in(source, 8)]


def main() -> None:
    PROMOTED.mkdir(parents=True, exist_ok=True)
    for name, (columns, rows, sources) in ATLASES.items():
        props = [prop for source in sources for prop in props_in(ORIGINALS / source)]
        if len(props) != columns * rows:
            raise SystemExit(f"{name}: found {len(props)} props, expected {columns * rows}")
        inner = FRAME - 2 * PADDING
        scale = inner / max(max(prop.width, prop.height) for prop in props)
        atlas = Image.new("RGBA", (FRAME * columns, FRAME * rows), (0, 0, 0, 0))
        for index, prop in enumerate(props):
            prop = prop.resize((max(1, round(prop.width * scale)), max(1, round(prop.height * scale))), Image.LANCZOS)
            column, row = index % columns, index // columns
            atlas.alpha_composite(prop, (column * FRAME + (FRAME - prop.width) // 2, row * FRAME + FRAME - PADDING - prop.height))
        atlas.save(PROMOTED / f"{FRAME}x{FRAME}-tile_{columns}x{rows}-{name}.png", optimize=True)
    print(f"packed {len(ATLASES)} prop atlases into {PROMOTED.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
