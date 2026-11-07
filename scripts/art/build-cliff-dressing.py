#!/usr/bin/env python3
"""Builds the cliffs' dressing atlas (docs/godot/ELEVATION.md "Ledge dressing"): the pieces the game
places at the foot of cliff walls.

Input (asset/Originals/elevation/):
  props/cliff-decor-a.png      the Phaser-era cliff decor sheet (2026-10-04): 16 pieces on white,
                               in four rows (DECOR names them in reading order)
Each piece is found as a connected blob of the sheet (the white background cut away first), cropped
and scaled to the game's 2 px a world unit, DECOR_WIDTH px wide. The pieces the game uses are packed
into one atlas with each one's rect and anchor (its point that sits on the ground, near its bottom
middle). The owner, 2026-11-06/07: the golden boulders and sandstone blocks "don't fit well", and
nothing on or hanging from a top edge ("random object on the top ledger like those ices, remove them
all"): those pieces, the icicles and the ivy curtains are left out (DECOR's None).
  -> godot/asset/MAPS/elevation/dressing/cliff-dressing.png, cliff-dressing.json

Usage: python scripts/art/build-cliff-dressing.py [--preview DIR]
"""
from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/elevation"
OUT = ROOT / "godot/asset/MAPS/elevation/dressing"
## The decor sheet's 16 pieces in reading order (the sheet holds them all); None: not in the atlas.
DECOR = [
    None, "mossy-rock", "mushroom-rock", "root-rock",
    "autumn-rocks", "dead-bush", None, "skull",
    "snowy-fir", "ice-crystals", None, "snowy-rock",
    "basalt-rocks", "crystals", "ruins", "lava-rock",
]
DECOR_WIDTH = 120
## A blob smaller than this share of the sheet is a speck, not a piece.
MIN_SHARE = 0.002
## Background: near-white joined to the sheet's border.
WHITE = 246
ALPHA_MIN = 24
## The labelling runs on a sheet scaled down by this much (fast without scipy).
LABEL_STEP = 4
ATLAS_WIDTH = 1024
PAD = 4


def cut_white(rgb: np.ndarray) -> np.ndarray:
    """Alpha with the near-white background joined to the border cut away, its rim softened."""
    h, w = rgb.shape[:2]
    whiteness = rgb.min(axis=2)
    candidate = whiteness > WHITE
    background = np.zeros((h, w), bool)
    queue = deque([(y, x) for x in range(w) for y in (0, h - 1)] + [(y, x) for y in range(h) for x in (0, w - 1)])
    while queue:
        y, x = queue.popleft()
        if background[y, x] or not candidate[y, x]:
            continue
        background[y, x] = True
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not background[ny, nx] and candidate[ny, nx]:
                queue.append((ny, nx))
    alpha = np.where(background, 0.0, 255.0)
    near = np.zeros_like(background)
    near[1:] |= background[:-1]
    near[:-1] |= background[1:]
    near[:, 1:] |= background[:, :-1]
    near[:, :-1] |= background[:, 1:]
    rim = near & ~background
    alpha[rim] = np.clip((255 - whiteness[rim]) * 255 / 40, 0, 255)
    return alpha


def blobs(alpha: np.ndarray) -> list[tuple[np.ndarray, tuple[int, int, int, int]]]:
    """The sheet's pieces: per blob (its full-size mask, its box x0, y0, x1, y1)."""
    h, w = alpha.shape
    small = alpha[::LABEL_STEP, ::LABEL_STEP] > ALPHA_MIN
    sh, sw = small.shape
    labels = np.zeros((sh, sw), np.int32)
    count = 0
    for y in range(sh):
        for x in range(sw):
            if small[y, x] and labels[y, x] == 0:
                count += 1
                labels[y, x] = count
                queue = deque([(y, x)])
                while queue:
                    cy, cx = queue.popleft()
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = cy + dy, cx + dx
                            if 0 <= ny < sh and 0 <= nx < sw and small[ny, nx] and labels[ny, nx] == 0:
                                labels[ny, nx] = count
                                queue.append((ny, nx))
    out = []
    for k in range(1, count + 1):
        mask_small = labels == k
        if mask_small.mean() < MIN_SHARE:
            continue
        # Grown by one small cell so the piece keeps its soft rim, then scaled up.
        grown = mask_small.copy()
        grown[1:] |= mask_small[:-1]
        grown[:-1] |= mask_small[1:]
        grown[:, 1:] |= grown[:, :-1]
        grown[:, :-1] |= grown[:, 1:]
        mask = np.kron(grown, np.ones((LABEL_STEP, LABEL_STEP), bool))[:h, :w] & (alpha > 0)
        ys, xs = np.where(mask)
        out.append((mask, (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)))
    return out


def piece(rgb: np.ndarray, alpha: np.ndarray, mask: np.ndarray, box: tuple[int, int, int, int], scale: float) -> Image.Image:
    x0, y0, x1, y1 = box
    rgba = np.dstack([rgb[y0:y1, x0:x1], np.where(mask[y0:y1, x0:x1], alpha[y0:y1, x0:x1], 0)]).astype(np.uint8)
    image = Image.fromarray(rgba, "RGBA")
    size = (max(1, round((x1 - x0) * scale)), max(1, round((y1 - y0) * scale)))
    return image.resize(size, Image.LANCZOS)


def reading_order(found: list, rows: int) -> list:
    """Blobs sorted into `rows` rows by their middle's height, then left to right."""
    by_y = sorted(found, key=lambda b: (b[1][1] + b[1][3]) / 2)
    per_row = max(1, round(len(by_y) / rows))
    ordered = []
    for r in range(0, len(by_y), per_row):
        ordered += sorted(by_y[r:r + per_row], key=lambda b: b[1][0])
    return ordered


def anchor_of(image: Image.Image) -> list[int]:
    """Where a piece touches the ground: the bottom of its body (the lowest row where it is mostly
    solid), in the middle."""
    a = np.asarray(image)[..., 3] > 128
    h, w = a.shape
    cols = np.where(a.any(axis=0))[0]
    mid = int((cols.min() + cols.max()) / 2) if cols.size else w // 2
    rows = a.sum(axis=1)
    solid = np.where(rows > 0.35 * rows.max())[0]
    return [mid, int(solid.max()) if solid.size else h - 1]


def pack(pieces: list[tuple[str, Image.Image]]) -> tuple[Image.Image, dict[str, list[int]]]:
    """Shelf packing, tallest first, ATLAS_WIDTH wide."""
    order = sorted(pieces, key=lambda p: -p[1].size[1])
    rects: dict[str, list[int]] = {}
    x = y = shelf = PAD
    shelf = 0
    for name, image in order:
        w, h = image.size
        if x + w + PAD > ATLAS_WIDTH:
            x = PAD
            y += shelf + PAD
            shelf = 0
        rects[name] = [x, y, w, h]
        x += w + PAD
        shelf = max(shelf, h)
    height = y + shelf + PAD
    atlas = Image.new("RGBA", (ATLAS_WIDTH, height), (0, 0, 0, 0))
    for name, image in pieces:
        r = rects[name]
        atlas.paste(image, (r[0], r[1]))
    return atlas, rects


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    pieces: list[tuple[str, Image.Image]] = []
    meta: dict[str, dict] = {}

    rgb = np.asarray(Image.open(SRC / "props/cliff-decor-a.png").convert("RGB")).astype(np.float64)
    alpha = cut_white(rgb)
    found = reading_order(blobs(alpha), 4)
    assert len(found) == len(DECOR), f"{len(found)} decor pieces found, {len(DECOR)} named"
    for name, (mask, box) in zip(DECOR, found):
        if name is None:
            continue
        image = piece(rgb, alpha, mask, box, DECOR_WIDTH / (box[2] - box[0]))
        pieces.append((name, image))
        meta[name] = {"places": ["foot"], "anchor": anchor_of(image)}

    atlas, rects = pack(pieces)
    OUT.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT / "cliff-dressing.png")
    for name in meta:
        meta[name]["rect"] = rects[name]
    (OUT / "cliff-dressing.json").write_text(json.dumps(meta, indent="\t") + "\n", encoding="utf-8")
    print(f"dressing: {len(pieces)} pieces, atlas {atlas.size[0]}x{atlas.size[1]}")
    if args.preview is not None:
        args.preview.mkdir(parents=True, exist_ok=True)
        bg = Image.new("RGBA", atlas.size, (70, 95, 50, 255))
        bg.alpha_composite(atlas)
        bg.save(args.preview / "cliff-dressing-preview.png")


if __name__ == "__main__":
    main()
