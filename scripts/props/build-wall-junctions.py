"""Rebuild the stone wall T-junction sheet from the corner pieces.

Every junction is stitched from halves (or quadrants) of the real corner art,
so outlines, front faces and stone texture match the straight and corner walls
exactly. A short cross-fade hides the seam down the middle of the top surface.

Frames (asset sheet.walls.t-junctions.7x1, scenes wall-stone-solid--junction-0N
use frame N-1):
  0 ┬ (left, right, down)   1 ┴ (left, right, up)
  2 ├ (up, down, right)     3 ┤ (up, down, left)
  4 ┼ (all four)            5 ┬ variant   6 ┴ variant

  python scripts/props/build-wall-junctions.py
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

WALLS = ROOT / "godot" / "asset" / "MAPS" / "walls"
CORNERS = WALLS / "70x70-4x2tiles_corners.webp"
OUT = WALLS / "70x70-7x1tiles_Ts.webp"
CELL = 70
HALF = CELL // 2
FADE = 8  # px cross-fade across each seam

# Corner frames in the 4x2 corner sheet, by the two directions they open to.
# Two art variants of each: (primary, alternate).
DOWN_RIGHT, DOWN_LEFT, UP_RIGHT, UP_LEFT = (0, 1), (2, 3), (4, 5), (6, 7)


def corner(index):
    sheet = Image.open(CORNERS).convert("RGBA")
    x, y = (index % 4) * CELL, (index // 4) * CELL
    return np.array(sheet.crop((x, y, x + CELL, y + CELL))).astype(np.float64)


def ramp(axis_len):
    """Weight of the second image along one axis: 0 before the seam, 1 after."""
    t = np.clip((np.arange(axis_len) - (HALF - FADE / 2)) / FADE, 0, 1)
    return t


def blend(a, b, w):
    """Premultiplied blend of two RGBA cells, w = weight of b per pixel."""
    w = w[..., None]
    alpha = a[..., 3:4] * (1 - w) + b[..., 3:4] * w
    rgb = a[..., :3] * a[..., 3:4] * (1 - w) + b[..., :3] * b[..., 3:4] * w
    rgb = np.where(alpha > 0, rgb / np.maximum(alpha, 1e-6), 0)
    return np.concatenate([rgb, alpha], axis=-1)


def left_right(left, right):
    w = np.tile(ramp(CELL)[None, :], (CELL, 1))
    return blend(left, right, w)


def top_bottom(top, bottom):
    w = np.tile(ramp(CELL)[:, None], (1, CELL))
    return blend(top, bottom, w)


def build():
    v = 0
    frames = [
        left_right(corner(DOWN_LEFT[v]), corner(DOWN_RIGHT[v])),   # ┬
        left_right(corner(UP_LEFT[v]), corner(UP_RIGHT[v])),       # ┴
        top_bottom(corner(UP_RIGHT[v]), corner(DOWN_RIGHT[v])),    # ├
        top_bottom(corner(UP_LEFT[v]), corner(DOWN_LEFT[v])),      # ┤
        top_bottom(left_right(corner(UP_LEFT[v]), corner(UP_RIGHT[v])),
                   left_right(corner(DOWN_LEFT[v]), corner(DOWN_RIGHT[v]))),  # ┼
        left_right(corner(DOWN_LEFT[1]), corner(DOWN_RIGHT[1])),   # ┬ alt
        left_right(corner(UP_LEFT[1]), corner(UP_RIGHT[1])),       # ┴ alt
    ]
    sheet = np.concatenate(frames, axis=1)
    sheet[..., 3] = np.where(sheet[..., 3] > 127, 255, 0)  # walls use hard alpha
    sheet[sheet[..., 3] == 0, :3] = 0
    save_game_webp(Image.fromarray(np.clip(sheet, 0, 255).astype(np.uint8), "RGBA"), OUT)
    print(OUT)


if __name__ == "__main__":
    build()
