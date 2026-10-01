"""Bake canopy-only sway loops for every tree sprite.

Each tree gets 8 frames. A row of pixels shifts sideways by an amount that is 0
at and below the hinge (where the canopy leaves the trunk) and grows toward the
top, plus a small ripple travelling up through the leaves. The trunk and roots
are the original pixels in every frame, so the tree bends instead of rocking.

Output frame index = source frame * 8 + step:
  asset/MAPS/trees/128x170-tile_16x22-trees-sway.webp  (from 128X170-tiles_8x6)
  asset/MAPS/trees/256x256-tile_8x3-trees-sway.webp     (from 256x256-Tile_3x1)

  python scripts/art/build-tree-sway-sheets.py
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

TREES = ROOT / "asset" / "MAPS" / "trees"
STEPS = 8
# Leafless trees (dead pines, twisted bare trees, the frosted tree) have no
# canopy to sway: their frames are written as still copies. Keep in sync with
# BARE_TREE_FRAMES in scripts/props/wire-ambient-animations.mjs.
BARE = {"128X170-tiles_8x6.webp": set(range(0, 9))}
# source, frame w/h, source cols, source frame count, output, output cols
JOBS = [
    ("128X170-tiles_8x6.webp", 128, 170, 8, 43, "128x170-tile_16x22-trees-sway.webp", 16),
    ("256x256-Tile_3x1.webp", 256, 256, 3, 3, "256x256-tile_8x3-trees-sway.webp", 8),
]


def hinge_row(alpha):
    """Row where the canopy starts: scanning up from the base, the first row
    clearly wider than the trunk."""
    rows = np.nonzero(alpha.any(axis=1))[0]
    top, bottom = rows.min(), rows.max()
    widths = alpha.sum(axis=1)
    widest = widths.max()
    for y in range(bottom, top - 1, -1):
        if widths[y] > 0.45 * widest:
            return top, y
    return top, bottom


def sway(cell, amplitude):
    h, w = cell.shape[:2]
    alpha = cell[..., 3] > 0
    if not alpha.any():
        return [cell] * STEPS
    top, hinge = hinge_row(alpha)
    # Let the lower canopy move a little less than the crown.
    hinge = min(h - 1, hinge + (h - hinge) // 6)
    rgba = cell.astype(np.float64)
    premult = np.concatenate([rgba[..., :3] * rgba[..., 3:4] / 255, rgba[..., 3:4]], -1)
    cols = np.arange(w, dtype=np.float64)
    frames = []
    for step in range(STEPS):
        phase = 2 * math.pi * step / STEPS
        out = premult.copy()
        for y in range(top, hinge):
            weight = ((hinge - y) / max(1, hinge - top)) ** 1.6
            shift = amplitude * weight * (math.sin(phase) + 0.25 * math.sin(2 * phase + y * 0.12))
            for c in range(4):
                out[y, :, c] = np.interp(cols - shift, cols, premult[y, :, c], left=0, right=0)
        a = out[..., 3:4]
        rgb = np.where(a > 0, out[..., :3] * 255 / np.maximum(a, 1e-6), 0)
        result = np.concatenate([rgb, np.where(a > 127, 255, 0)], -1)
        result[result[..., 3] == 0, :3] = 0
        frames.append(np.clip(result, 0, 255).astype(np.uint8))
    return frames


def main():
    for source, fw, fh, src_cols, count, output, out_cols in JOBS:
        sheet = np.array(Image.open(TREES / source).convert("RGBA"))
        total = count * STEPS
        out_rows = math.ceil(total / out_cols)
        atlas = np.zeros((out_rows * fh, out_cols * fw, 4), np.uint8)
        amplitude = 2.4 * fw / 128
        for frame in range(count):
            x, y = (frame % src_cols) * fw, (frame // src_cols) * fh
            cell = sheet[y:y + fh, x:x + fw]
            images = [cell] * STEPS if frame in BARE.get(source, set()) else sway(cell, amplitude)
            for step, image in enumerate(images):
                index = frame * STEPS + step
                ox, oy = (index % out_cols) * fw, (index // out_cols) * fh
                atlas[oy:oy + fh, ox:ox + fw] = image
        save_game_webp(Image.fromarray(atlas, "RGBA"), TREES / output)
        print(f"{output}: {count} trees x {STEPS} frames, {atlas.shape[1]}x{atlas.shape[0]}")


if __name__ == "__main__":
    main()
