#!/usr/bin/env python3
"""Builds the forest layer's paint tiles and tile set (docs/godot/FORESTS.md).

The trees are the big trees of every region set, godot/asset/MAPS/trees/sets/trees.json (built by
scripts/art/build-tree-sets.py), named <kind>-<variant>-<size>. The palette has one row of mixes (a
painted cell takes a tree of its mix at random, seeded by the cell), then one tile per tree (rows
1 on, 16 a row, set by set: a painted cell takes exactly that tree). Each tile stores its trees in
the custom data `forest_trees` (comma separated) and a name in `forest_mix`. The mixes keep their
columns: worlds are painted with them, and the region world builder paints them by column
(tools/region_worlds/region_canvas.gd); the mixes' row runs past 16 tiles.

Outputs: godot/asset/MAPS/forest/forest_paint_tiles.png (64 px tiles) and
godot/game/world/forest/forest_tileset.tres.

Usage: python scripts/art/build-forest-paint-tiles.py   (Pillow)
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
TABLE = ROOT / "godot/asset/MAPS/trees/sets/trees.json"
GODOT = ROOT / "godot"
PNG = ROOT / "godot/asset/MAPS/forest/forest_paint_tiles.png"
TRES = ROOT / "godot/game/world/forest/forest_tileset.tres"
SHEET_RES = "res://asset/MAPS/forest/forest_paint_tiles.png"
TILE = 64
## Single trees per row.
COLUMNS = 16
## The palette's width in tiles (the mixes' row may run past COLUMNS).
WIDTH = 20
SINGLE_ROW = 1


def big(*kinds: str, sizes: tuple[str, ...] = ("medium", "tall")) -> list[str]:
    return [f"{kind}-{variant}-{size}" for kind in kinds for variant in "ab" for size in sizes]


## name, background colour, trees. Columns are fixed: append new mixes at the end.
MIXES = [
    ("mixed", (52, 86, 60), big("oak", "beech", "birch", "pine")),
    ("pine", (40, 74, 66), big("pine")),
    ("green", (46, 90, 46), big("oak", "beech")),
    ("light green", (88, 112, 40), big("birch", "oak")),
    ("autumn", (120, 70, 30), big("maple", "ginkgo")),
    ("dead", (84, 70, 60), big("gnarled")),
    ("snow", (110, 124, 140), big("fir", "frost")),
    ("oak", (60, 96, 44), big("oak")),
    ("beech", (36, 70, 40), big("beech")),
    ("birch", (110, 130, 50), big("birch")),
    ("dark", (34, 60, 50), big("beech", "pine")),
    ("desert", (176, 140, 80), big("saguaro", "pear", "organ")),
    ("volcano", (70, 40, 34), big("ember", "ash")),
    ("swamp", (66, 74, 44), big("cypress", "mangrove")),
    ("crystal", (70, 56, 100), big("crystal", "mushroom")),
    ("village", (110, 120, 60), big("apple", "cherry")),
    ("ruins", (80, 84, 66), big("gnarled", "ivy")),
    ("forest medium", (52, 86, 60), big("oak", "beech", "birch", "pine", sizes=("medium",))),
]
SINGLE_BG = (44, 62, 48)


class Trees:
    def __init__(self) -> None:
        self.table = json.loads(TABLE.read_text(encoding="utf-8"))["trees"]
        self.atlases: dict[str, Image.Image] = {}

    def image(self, tree: str) -> Image.Image:
        entry = self.table[tree]
        path = entry["texture"]
        if path not in self.atlases:
            self.atlases[path] = Image.open(GODOT / path.removeprefix("res://")).convert("RGBA")
        x, y, w, h = entry["rect"]
        crop = self.atlases[path].crop((x, y, x + w, y + h))
        return crop.crop(crop.getbbox())


def fit(image: Image.Image, box: tuple[int, int]) -> Image.Image:
    scale = min(box[0] / image.width, box[1] / image.height)
    return image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.LANCZOS)


def thumb(trees: Trees, picks: list[str], bg: tuple[int, int, int], mixed: bool) -> Image.Image:
    tile = Image.new("RGBA", (TILE, TILE), bg + (255,))
    draw = ImageDraw.Draw(tile)
    draw.rectangle((0, 0, TILE - 1, TILE - 1), outline=(240, 230, 200, 255) if mixed else (20, 20, 24, 255), width=2)
    if mixed:
        # three trees of the mix, spread over its kinds
        step = max(1, len(picks) // 3)
        chosen = [picks[(i * step + (step // 2)) % len(picks)] for i in range(3)][:len(picks)]
        boxes = [((2, 17), (34, 45)), ((28, 17), (34, 45)), ((15, 4), (34, 45))]
        for tree, (corner, box) in zip(chosen, boxes):
            t = fit(trees.image(tree), box)
            tile.alpha_composite(t, (corner[0] + (box[0] - t.width) // 2, corner[1] + box[1] - t.height))
    else:
        t = fit(trees.image(picks[0]), (56, 58))
        tile.alpha_composite(t, ((TILE - t.width) // 2, TILE - t.height - 3))
    return tile


def keep_uids() -> tuple[str, str]:
    """The tile set's own uid and its texture's, so a rebuild does not churn them."""
    if not TRES.exists():
        return "", ""
    text = TRES.read_text(encoding="utf-8")
    own = re.search(r'\[gd_resource [^\]]*uid="([^"]+)"', text)
    tex = re.search(r'\[ext_resource [^\]]*uid="([^"]+)"', text)
    return (own.group(1) if own else ""), (tex.group(1) if tex else "")


def main() -> None:
    trees = Trees()
    tiles: list[tuple[tuple[int, int], Image.Image, str, list[str]]] = []
    for i, (name, bg, picks) in enumerate(MIXES):
        tiles.append(((i, 0), thumb(trees, picks, bg, True), name, picks))
    for i, name in enumerate(trees.table):
        tiles.append(((i % COLUMNS, SINGLE_ROW + i // COLUMNS), thumb(trees, [name], SINGLE_BG, False), name, [name]))
    rows = 1 + max(c[1] for c, *_ in tiles)
    out = Image.new("RGBA", (WIDTH * TILE, rows * TILE), (0, 0, 0, 0))
    for (cx, cy), img, *_ in tiles:
        out.alpha_composite(img, (cx * TILE, cy * TILE))
    PNG.parent.mkdir(parents=True, exist_ok=True)
    out.save(PNG, optimize=True)
    own_uid, tex_uid = keep_uids()
    lines = [
        '[gd_resource type="TileSet" format=3%s]' % (f' uid="{own_uid}"' if own_uid else ""),
        "",
        '[ext_resource type="Texture2D"%s path="%s" id="1_tiles"]' % (f' uid="{tex_uid}"' if tex_uid else "", SHEET_RES),
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_forest"]',
        'texture = ExtResource("1_tiles")',
        f"texture_region_size = Vector2i({TILE}, {TILE})",
    ]
    for (cx, cy), _, name, picks in tiles:
        lines += [
            f"{cx}:{cy}/0 = 0",
            f'{cx}:{cy}/0/custom_data_0 = "{name}"',
            f'{cx}:{cy}/0/custom_data_1 = "{",".join(picks)}"',
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
    print(f"{PNG.name}: {len(tiles)} tiles ({len(MIXES)} mixes, {len(trees.table)} trees); {TRES.name}")


if __name__ == "__main__":
    main()
