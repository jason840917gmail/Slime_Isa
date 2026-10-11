#!/usr/bin/env python3
"""Builds the forest layer's paint tiles and tile set (docs/godot/FORESTS.md).

The trees come from the sway sheet godot/asset/MAPS/trees/128x170-tile_16x22-trees-sway.webp: 44
trees of 8 sway frames each (tree k starts at frame 8k). The palette has one row of mixes (a painted
cell takes a tree of its mix at random, seeded by the cell) and, below, one tile per tree (a
painted cell takes exactly that tree). Each tile stores its trees in the custom data `forest_trees`
(the first frames, comma separated) and a name in `forest_mix`.

Outputs: godot/asset/MAPS/forest/forest_paint_tiles.png (64 px tiles, 16 per row) and
godot/game/world/forest/forest_tileset.tres.

Usage: python scripts/art/build-forest-paint-tiles.py   (numpy, Pillow)
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / "godot/asset/MAPS/trees/128x170-tile_16x22-trees-sway.webp"
PNG = ROOT / "godot/asset/MAPS/forest/forest_paint_tiles.png"
TRES = ROOT / "godot/game/world/forest/forest_tileset.tres"
SHEET_RES = "res://asset/MAPS/forest/forest_paint_tiles.png"
TILE = 64
COLUMNS = 16
FRAME = (128, 170)
SHEET_COLUMNS = 16
SWAY = 8
TREES = 44
## name, background colour, first frames of its trees
MIXES = [
    ("mixed", (52, 86, 60), [144, 152, 160, 176, 184, 232, 240, 248]),
    ("pine", (40, 74, 66), [136, 144, 152, 160, 168, 176, 184]),
    ("green", (46, 90, 46), [216, 232, 240, 248, 336]),
    ("light green", (88, 112, 40), [200, 208, 256, 264, 272, 280, 288, 296, 304, 312, 320, 328]),
    ("autumn", (120, 70, 30), [72, 80, 88, 96, 104, 112, 120, 128]),
    ("dead", (84, 70, 60), [0, 8, 16, 32, 40, 48, 56, 64]),
    ("snow", (110, 124, 140), [24, 192]),
]
SINGLE_BG = (60, 60, 66)


def tree(sheet: Image.Image, first: int) -> Image.Image:
    x = (first % SHEET_COLUMNS) * FRAME[0]
    y = (first // SHEET_COLUMNS) * FRAME[1]
    return sheet.crop((x, y, x + FRAME[0], y + FRAME[1]))


def thumb(sheet: Image.Image, frames: list[int], bg: tuple[int, int, int], mixed: bool) -> Image.Image:
    tile = Image.new("RGBA", (TILE, TILE), bg + (255,))
    draw = ImageDraw.Draw(tile)
    draw.rectangle((0, 0, TILE - 1, TILE - 1), outline=(240, 230, 200, 255) if mixed else (20, 20, 24, 255), width=2)
    picks = frames[:3] if mixed else frames[:1]
    size = (34, 45) if mixed else (44, 58)
    for i, first in enumerate(picks):
        t = tree(sheet, first).resize(size, Image.LANCZOS)
        if mixed:
            pos = [(2, 17), (28, 17), (15, 4)][i]
        else:
            pos = ((TILE - size[0]) // 2, TILE - size[1] - 3)
        tile.alpha_composite(t, pos)
    return tile


def main() -> None:
    sheet = Image.open(SHEET).convert("RGBA")
    tiles: list[tuple[tuple[int, int], Image.Image, str, list[int]]] = []
    for i, (name, bg, frames) in enumerate(MIXES):
        tiles.append(((i, 0), thumb(sheet, frames, bg, True), name, frames))
    for k in range(TREES):
        first = k * SWAY
        if np.asarray(tree(sheet, first))[..., 3].max() == 0:
            continue
        tiles.append(((k % COLUMNS, 1 + k // COLUMNS), thumb(sheet, [first], SINGLE_BG, False), f"tree {first}", [first]))
    rows = 1 + max(c[1] for c, *_ in tiles)
    out = Image.new("RGBA", (COLUMNS * TILE, rows * TILE), (0, 0, 0, 0))
    for (cx, cy), img, *_ in tiles:
        out.alpha_composite(img, (cx * TILE, cy * TILE))
    PNG.parent.mkdir(parents=True, exist_ok=True)
    out.save(PNG, optimize=True)
    lines = [
        '[gd_resource type="TileSet" format=3]',
        "",
        f'[ext_resource type="Texture2D" path="{SHEET_RES}" id="1_tiles"]',
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_forest"]',
        'texture = ExtResource("1_tiles")',
        f"texture_region_size = Vector2i({TILE}, {TILE})",
    ]
    for (cx, cy), _, name, frames in tiles:
        lines += [
            f"{cx}:{cy}/0 = 0",
            f'{cx}:{cy}/0/custom_data_0 = "{name}"',
            f'{cx}:{cy}/0/custom_data_1 = "{",".join(str(f) for f in frames)}"',
        ]
    lines += [
        "",
        "[resource]",
        f"tile_size = Vector2i({TILE}, {TILE})",
        'custom_data_layer_0/name = "forest_mix"',
        "custom_data_layer_0/type = 4",
        'custom_data_layer_1/name = "forest_trees"',
        "custom_data_layer_1/type = 4",
        'sources/0 = SubResource("TileSetAtlasSource_forest")',
        "",
    ]
    TRES.parent.mkdir(parents=True, exist_ok=True)
    TRES.write_text("\n".join(lines), encoding="utf-8")
    print(f"{PNG.name}: {len(tiles)} tiles ({len(MIXES)} mixes); {TRES.name}")


if __name__ == "__main__":
    main()
