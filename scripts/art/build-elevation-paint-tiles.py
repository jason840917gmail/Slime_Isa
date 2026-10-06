#!/usr/bin/env python3
"""Draws the editor-only paint tiles of the elevation layer (docs/godot/ELEVATION.md).

64 px tiles in godot/game/world/elevation/elevation_paint_tiles.png (the atlas of
elevation_tileset.tres, same order): row 0, a see-through coloured square per level with the level
written on it (TILES, then the old stairs "S"); row 1, stairs with a railed landing, one arrow per
direction pointing down the stairs (STAIRS order); row 2, the same with an open landing (a dashed
square). The game never draws them (the elevation layer hides itself at run time).

Usage: python scripts/art/build-elevation-paint-tiles.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot/game/world/elevation/elevation_paint_tiles.png"
SIZE = 64
## (label, rgb): holes in blues, raised ground in warm colours, then stairs ("S"); atlas order =
## elevation_tileset.tres.
TILES = [
    ("-3", (40, 60, 160)),
    ("-2", (60, 110, 200)),
    ("-1", (90, 170, 230)),
    ("1", (240, 200, 60)),
    ("2", (240, 140, 40)),
    ("3", (220, 60, 40)),
    ("S", (150, 150, 150)),
]


## Stairs directions in atlas order (row 1 railed, row 2 open landing): the direction down the stairs.
STAIRS = [("s", (0, 1)), ("sw", (-1, 1)), ("w", (-1, 0)), ("nw", (-1, -1)), ("n", (0, -1)), ("ne", (1, -1)),
          ("e", (1, 0)), ("se", (1, 1))]
STAIRS_RGB = (150, 150, 150)
COLUMNS = max(len(TILES), len(STAIRS))


def stairs_tile(draw: ImageDraw.ImageDraw, x0: int, y0: int, direction: tuple[int, int], open_landing: bool) -> None:
    rgb = STAIRS_RGB
    draw.rectangle((x0, y0, x0 + SIZE - 1, y0 + SIZE - 1), fill=rgb + (90,))
    if open_landing:
        for i in range(0, SIZE, 8):
            for a, b in (((x0 + i, y0), (x0 + min(i + 4, SIZE - 1), y0)), ((x0 + i, y0 + SIZE - 2), (x0 + min(i + 4, SIZE - 1), y0 + SIZE - 2)),
                         ((x0, y0 + i), (x0, y0 + min(i + 4, SIZE - 1))), ((x0 + SIZE - 2, y0 + i), (x0 + SIZE - 2, y0 + min(i + 4, SIZE - 1)))):
                draw.line((a, b), fill=rgb + (230,), width=3)
    else:
        draw.rectangle((x0, y0, x0 + SIZE - 1, y0 + SIZE - 1), outline=rgb + (230,), width=3)
    dx, dy = direction
    length = (dx * dx + dy * dy) ** 0.5
    ux, uy = dx / length, dy / length
    cx, cy = x0 + SIZE / 2, y0 + SIZE / 2
    tail = (cx - ux * 20, cy - uy * 20)
    tip = (cx + ux * 20, cy + uy * 20)
    # Steps across the shaft, then the arrow.
    for k in (-10, 0, 10):
        mx, my = cx + ux * k, cy + uy * k
        draw.line(((mx - uy * 9, my + ux * 9), (mx + uy * 9, my - ux * 9)), fill=(20, 20, 30, 200), width=3)
    draw.line((tail, tip), fill=(255, 255, 255, 235), width=4)
    head = [tip, (tip[0] - ux * 11 - uy * 8, tip[1] - uy * 11 + ux * 8), (tip[0] - ux * 11 + uy * 8, tip[1] - uy * 11 - ux * 8)]
    draw.polygon(head, fill=(255, 255, 255, 235), outline=(20, 20, 30, 235))


def main() -> None:
    image = Image.new("RGBA", (SIZE * COLUMNS, SIZE * 3), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype("arialbd.ttf", 30)
    except OSError:
        font = ImageFont.load_default()
    for i, (label, rgb) in enumerate(TILES):
        x0 = i * SIZE
        draw.rectangle((x0, 0, x0 + SIZE - 1, SIZE - 1), fill=rgb + (90,), outline=rgb + (230,), width=3)
        box = draw.textbbox((0, 0), label, font=font)
        tx = x0 + (SIZE - (box[2] - box[0])) / 2 - box[0]
        ty = (SIZE - (box[3] - box[1])) / 2 - box[1]
        draw.text((tx, ty), label, font=font, fill=(255, 255, 255, 235), stroke_width=2, stroke_fill=(20, 20, 30, 235))
    for row, open_landing in ((1, False), (2, True)):
        for i, (_name, direction) in enumerate(STAIRS):
            stairs_tile(draw, i * SIZE, row * SIZE, direction, open_landing)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUT)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(TILES)} level tiles, {2 * len(STAIRS)} stairs tiles)")


if __name__ == "__main__":
    main()
