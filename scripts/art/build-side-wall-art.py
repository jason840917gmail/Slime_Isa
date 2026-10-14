#!/usr/bin/env python3
"""Builds a wall style's art for the cliffs' sides look (docs/godot/ELEVATION.md "Side walls"):
its side strip (the single column of short rounded stones a side wall shows) and its corner stones
(one big rounded stone per course over a front wall's outer corner), from a Magnific sheet of four
rounded stones (asset/Originals/elevation/side-walls/corner-stones-a.png, GPT 2.5, transparent;
a 2 x 2 grid), colour-matched to the style's wall art.

  side     STONES stones side by side, each in a CELL of the strip (one course, 128 px, tall), on
           the dark of a joint: <style>-side.png, periodic sideways (each stone sits in its own
           cell). The shader lays it along a side, SIDE_U_RATE times shorter than the wall.
  corners  the same stones, one per CELL, on transparency: <style>-corners.png
           (elevation_sides.gd CORNER_STONES side by side).

Outputs in godot/asset/MAPS/elevation/ (derived; re-run the tool instead of editing them).

Usage: python scripts/art/build-side-wall-art.py [--style storybook-rock] [--source PNG]   (numpy, Pillow)
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "asset/Originals/elevation/side-walls/corner-stones-a.png"
OUT = ROOT / "godot/asset/MAPS/elevation"
STONES = 4
## One stone's cell (px): a course tall, two of them per wall-art width (268 px for 536).
CELL = (268, 128)
## The stone inside its cell, and the cell's ground between stones (a joint's dark brown).
STONE_FILL = (0.97, 0.94)
JOINT = (52, 38, 24)
## The corner sheet's cells (px).
CORNER_CELL = (256, 128)
CORNER_FILL = (0.96, 0.94)


def stones_of(sheet: Image.Image) -> list[Image.Image]:
    """The four stones of a 2 x 2 sheet, each cut to its bounds."""
    out = []
    w, h = sheet.width // 2, sheet.height // 2
    for row in range(2):
        for col in range(2):
            part = sheet.crop((col * w, row * h, (col + 1) * w, (row + 1) * h))
            box = part.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
            if box is None:
                raise SystemExit("an empty quarter in the stone sheet")
            out.append(part.crop(box))
    return out


def match_colours(stone: Image.Image, wall: np.ndarray) -> Image.Image:
    """The stone's colours moved to the wall art's mean and spread, per channel."""
    a = np.asarray(stone).astype(np.float32)
    mask = a[..., 3] > 200
    out = a.copy()
    for c in range(3):
        src = a[..., c][mask]
        out[..., c] = (a[..., c] - src.mean()) / max(src.std(), 1e-3) * wall[:, c].std() + wall[:, c].mean()
    out[..., :3] = np.clip(out[..., :3], 0, 255)
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def fit(stone: Image.Image, cell: tuple[int, int], fill: tuple[float, float]) -> Image.Image:
    size = (round(cell[0] * fill[0]), round(cell[1] * fill[1]))
    return stone.resize(size, Image.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--style", default="storybook-rock")
    parser.add_argument("--source", type=Path, default=SOURCE)
    args = parser.parse_args()
    wall_img = Image.open(OUT / f"{args.style}-wall.png").convert("RGB")
    wall = np.asarray(wall_img).reshape(-1, 3).astype(np.float32)
    stones = [match_colours(s, wall) for s in stones_of(Image.open(args.source).convert("RGBA"))][:STONES]

    side = Image.new("RGBA", (CELL[0] * STONES, CELL[1]), JOINT + (255,))
    for i, stone in enumerate(stones):
        piece = fit(stone, CELL, STONE_FILL)
        side.alpha_composite(piece, (i * CELL[0] + (CELL[0] - piece.width) // 2, (CELL[1] - piece.height) // 2))
    side.convert("RGB").save(OUT / f"{args.style}-side.png")

    corners = Image.new("RGBA", (CORNER_CELL[0] * STONES, CORNER_CELL[1]), (0, 0, 0, 0))
    for i, stone in enumerate(stones):
        piece = fit(stone, CORNER_CELL, CORNER_FILL)
        corners.alpha_composite(piece, (i * CORNER_CELL[0] + (CORNER_CELL[0] - piece.width) // 2,
                                        (CORNER_CELL[1] - piece.height) // 2))
    corners.save(OUT / f"{args.style}-corners.png")
    print(f"wrote {args.style}-side.png ({side.width}x{side.height}), {args.style}-corners.png "
          f"({corners.width}x{corners.height})")


if __name__ == "__main__":
    main()
