#!/usr/bin/env python3
"""Draws the editor-only paint tiles of the cliffs layer (docs/godot/ELEVATION.md "Wall styles").

One 64 px tile per entry of TILES, left to right, in
godot/game/world/elevation/cliffs/cliff_paint_tiles.png (the atlas of cliff_tileset.tres, in that
order): a see-through swatch of the style's wall (godot/asset/MAPS/elevation/<style>-wall.png,
one course scaled to the tile) with the style's letter. The game never draws them (the cliffs layer
hides itself at run time). Run it after scripts/art/build-elevation-art.py.

Usage: python scripts/art/build-cliff-paint-tiles.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "godot/asset/MAPS/elevation"
OUT = ROOT / "godot/game/world/elevation/cliffs/cliff_paint_tiles.png"
SIZE = 64
## (style, letter), atlas order = cliff_tileset.tres.
TILES = [
    ("meadow-rock", "M"),
    ("snow-rock", "S"),
    ("sandstone", "D"),
    ("cave-rock", "C"),
    ("crystal-rock", "K"),
    ("mossy-rock", "G"),
    ("masonry", "B"),
    ("root-rock", "R"),
    ("red-rock", "A"),
]
SWATCH_ALPHA = 170


def main() -> None:
    image = Image.new("RGBA", (SIZE * len(TILES), SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype("arialbd.ttf", 26)
    except OSError:
        font = ImageFont.load_default()
    for i, (style, label) in enumerate(TILES):
        x0 = i * SIZE
        wall = Image.open(ART / f"{style}-wall.png").convert("RGBA")
        # One course (128 px) of the wall, scaled to the tile.
        swatch = wall.crop((0, 0, 128, 128)).resize((SIZE, SIZE), Image.LANCZOS)
        swatch.putalpha(SWATCH_ALPHA)
        image.alpha_composite(swatch, (x0, 0))
        draw.rectangle((x0, 0, x0 + SIZE - 1, SIZE - 1), outline=(255, 255, 255, 230), width=2)
        box = draw.textbbox((0, 0), label, font=font)
        tx = x0 + (SIZE - (box[2] - box[0])) / 2 - box[0]
        ty = (SIZE - (box[3] - box[1])) / 2 - box[1]
        draw.text((tx, ty), label, font=font, fill=(255, 255, 255, 245), stroke_width=2, stroke_fill=(20, 20, 30, 245))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUT)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(TILES)} tiles)")


if __name__ == "__main__":
    main()
