#!/usr/bin/env python3
"""Draws the editor-only paint tiles of the fences layer (docs/godot/FENCES.md).

One 64 px tile per entry of TILES, left to right, in
godot/game/world/elevation/fences/fence_paint_tiles.png (the atlas of fence_tileset.tres, in that
order): a see-through coloured square with a fence mark and the style's letter. The game never
draws them (the fences layer hides itself at run time).

Usage: python scripts/art/build-fence-paint-tiles.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot/game/world/elevation/fences/fence_paint_tiles.png"
SIZE = 64
## (label, rgb) per style, atlas order = fence_tileset.tres: "A" = auto (the ground's style).
TILES = [
    ("A", (120, 200, 120)),   # auto
    ("W", (170, 110, 50)),    # wood
    ("S", (200, 225, 245)),   # snow
    ("B", (140, 140, 130)),   # stone blocks
    ("D", (225, 170, 100)),   # sandstone (desert)
    ("T", (90, 130, 60)),     # twig (forest)
    ("P", (190, 90, 50)),     # picket (autumn)
    ("C", (170, 120, 230)),   # crystal
]


def main() -> None:
    image = Image.new("RGBA", (SIZE * len(TILES), SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype("arialbd.ttf", 26)
    except OSError:
        font = ImageFont.load_default()
    for i, (label, rgb) in enumerate(TILES):
        x0 = i * SIZE
        draw.rectangle((x0, 0, x0 + SIZE - 1, SIZE - 1), fill=rgb + (70,), outline=rgb + (230,), width=2)
        # A little fence: three posts and two rails along the bottom.
        for px in (x0 + 10, x0 + 32, x0 + 54):
            draw.rectangle((px - 2, 40, px + 2, 58), fill=rgb + (235,))
        for ry in (45, 52):
            draw.rectangle((x0 + 8, ry, x0 + 56, ry + 2), fill=rgb + (235,))
        box = draw.textbbox((0, 0), label, font=font)
        tx = x0 + (SIZE - (box[2] - box[0])) / 2 - box[0]
        draw.text((tx, 6 - box[1]), label, font=font, fill=(255, 255, 255, 235), stroke_width=2, stroke_fill=(20, 20, 30, 235))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUT)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(TILES)} tiles)")


if __name__ == "__main__":
    main()
