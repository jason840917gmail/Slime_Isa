"""Pack the resource piles: the mine heaps and the walk-over pickups.

Sources (Magnific GPT 2.5, transparent, 2026-10-05) in asset/Originals/props/resources/:
- resource-heaps.png: four big heaps in a row (wood, stone, iron ore, charcoal), the art of the
  resource nodes you chop or mine (they never move);
- resource-pickups.png: four small walk-over pickups in a row (a twine-tied log bundle, loose
  cobbles, ore chunks, charcoal lumps), the art of the collectible piles (they bounce in play,
  game/scripts/collectible.gd).

Writes, with the frame layouts the scenes, items.json icons and assets.json already use:
- godot/asset/MAPS/resources/128x128-tile_4x2-resource-piles.webp
    frames 0-3 heaps: wood, stone (the stone node), iron ore, charcoal;
    frames 4-7 pickups: small wood, small stone, iron ore, charcoal;
- godot/asset/MAPS/resources/128x128-tile_2x1-starter-materials.webp
    frame 0 wood pickup, frame 1 stone pickup (the wood and stone world drops, drawn at 0.6).

Each item is split from its row by its columns of art, trimmed, and fitted inside the footprint
the old art had in that frame (FOOTPRINTS: never larger, aspect kept), centred on it and standing on
its bottom, so no scene, collider or icon has to move.

Usage: python scripts/props/pack-resource-piles.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

SOURCES = REPO / "asset" / "Originals" / "props" / "resources"
OUT_4X2 = REPO / "godot" / "asset" / "MAPS" / "resources" / "128x128-tile_4x2-resource-piles.webp"
OUT_2X1 = REPO / "godot" / "asset" / "MAPS" / "resources" / "128x128-tile_2x1-starter-materials.webp"
CELL = 128
ALPHA = 16
# Columns closer than this belong to one item (a pebble, a leaf beside it); the heaps stand only
# 15 px apart.
MERGE_GAP = 8
# The old art's box in each frame, (left, top, right, bottom) inclusive, measured from the sheets
# this replaced: the new art fits inside it, centred, on the same bottom. The small pickups'
# boxes reach 12 px higher than the old flat piles: the new bundles are rounder, and at the old
# height they read too small.
FOOTPRINTS = {
    "4x2": [(1, 19, 127, 112), (9, 23, 120, 104), (3, 23, 121, 109), (4, 21, 122, 110),
            (27, 20, 103, 84), (31, 22, 99, 83), (31, 21, 100, 83), (29, 21, 100, 82)],
    "2x1": [(12, 5, 120, 111), (7, 11, 116, 108)],
}


def split_row(path: Path, count: int = 4) -> list[Image.Image]:
    """The `count` items of a row render, left to right, each trimmed to its art."""
    image = Image.open(path).convert("RGBA")
    alpha = np.asarray(image)[..., 3] > ALPHA
    filled = alpha.any(axis=0)
    runs: list[list[int]] = []
    for x, on in enumerate(filled):
        if not on:
            continue
        if runs and x - runs[-1][1] <= MERGE_GAP:
            runs[-1][1] = x
        else:
            runs.append([x, x])
    runs = sorted(sorted(runs, key=lambda r: r[1] - r[0], reverse=True)[:count])
    if len(runs) != count:
        raise SystemExit(f"{path.name}: found {len(runs)} items, expected {count}")
    items = []
    for x0, x1 in runs:
        rows = np.where(alpha[:, x0:x1 + 1].any(axis=1))[0]
        items.append(image.crop((x0, rows.min(), x1 + 1, rows.max() + 1)))
    return items


def fit(item: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
    """A cell with `item` scaled inside `box` (never larger), centred on it, standing on its bottom."""
    left, top, right, bottom = box
    width, height = right - left + 1, bottom - top + 1
    scale = min(width / item.width, height / item.height)
    size = (max(1, round(item.width * scale)), max(1, round(item.height * scale)))
    scaled = item.resize(size, Image.LANCZOS)
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    x = round(left + (width - size[0]) / 2)
    y = bottom + 1 - size[1]
    cell.alpha_composite(scaled, (x, y))
    return cell


def main() -> None:
    heaps = split_row(SOURCES / "resource-heaps.png")
    pickups = split_row(SOURCES / "resource-pickups.png")

    sheet = Image.new("RGBA", (CELL * 4, CELL * 2), (0, 0, 0, 0))
    for index, item in enumerate(heaps + pickups):
        sheet.alpha_composite(fit(item, FOOTPRINTS["4x2"][index]), ((index % 4) * CELL, (index // 4) * CELL))
    print(f"{OUT_4X2.relative_to(REPO)}: {save_game_webp(sheet, OUT_4X2)}")

    starter = Image.new("RGBA", (CELL * 2, CELL), (0, 0, 0, 0))
    for index, item in enumerate(pickups[:2]):
        starter.alpha_composite(fit(item, FOOTPRINTS["2x1"][index]), (index * CELL, 0))
    print(f"{OUT_2X1.relative_to(REPO)}: {save_game_webp(starter, OUT_2X1)}")


if __name__ == "__main__":
    main()
