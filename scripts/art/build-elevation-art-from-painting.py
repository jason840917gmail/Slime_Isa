#!/usr/bin/env python3
"""Cuts elevation cliff art (docs/godot/ELEVATION.md) out of the approved H plateau paintings, so the
elevation system draws cliffs in their look (docs/godot/ELEVATION.md "Storybook art").

The elevation system draws a cliff's walls (sides/elevation_sides.gd) with a wall texture that
repeats sideways and down; its edges and feet are drawn from the grounds' own sheets. This tool cuts
the `storybook-rock` wall from the aligned three-course painting (asset/Originals/elevation/cliff-kit/
kit-h3.png, built by scripts/art/build-cliff-kit.py: one stone course = 128 px):

  wall    the clean middle course of the three-course painting (h3), one row from each leg of the H,
          resampled to 128 px and made horizontally periodic (two rows: stacked courses alternate).

(Its side strip and corner stones come from scripts/art/build-side-wall-art.py. The wall ends, lip
and foot it once cut too belonged to the front-only cliff look, removed on 2026-10-17.)

Outputs (derived; re-run the tool instead of editing them) in godot/asset/MAPS/elevation/:
  storybook-rock-wall.png
A world uses them through its ground layer's metadata (elevation.gd): `cliff_wall_styles`
{"highland": "storybook-rock"}.

Usage: python scripts/art/build-elevation-art-from-painting.py [--preview DIR]   (numpy, Pillow)
"""
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
KITS = ROOT / "asset/Originals/elevation/cliff-kit"
_spec = importlib.util.spec_from_file_location("elevation_art", ROOT / "scripts/art/build-elevation-art.py")
E = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(E)
OUT = E.OUT

STYLE = "storybook-rock"
COURSE = 128
## The wall course the texture comes from: h3's middle course, between the crevices near these rows
## of kit-h3.png (searched within ±CREVICE_SEARCH). Vines hang across it beside each leg's end, so
## the texture is made of the two clean spans, each holding one real joint between two stones
## (columns of kit-h3.png): left leg 731-1020 (joint at 811), right leg 2112-2430 (joint at 2192).
## The spans are joined, and made periodic, through stone faces, so the texture shows two stones.
WALL_COURSE_ROWS = (2568, 2691)
CREVICE_SEARCH = 12
WALL_SPANS = ((731, 1020), (2112, 2430))
SEAM = 48
## The second row of the texture (stacked courses alternate): the first mirrored and shifted by this
## fraction of its width, so the joints of neighbouring courses do not line up.
ROW_B_SHIFT = 0.3


def load(name: str) -> np.ndarray:
    return np.asarray(Image.open(KITS / f"kit-{name}.png").convert("RGBA"), dtype=np.float64) / 255.0


def crevice(a: np.ndarray, x0: int, x1: int, near: int) -> int:
    lum = a[near - CREVICE_SEARCH:near + CREVICE_SEARCH, x0:x1, :3].mean(axis=(1, 2))
    return near - CREVICE_SEARCH + int(np.argmin(lum))


def save(rgba: np.ndarray, name: str, preview: Path | None, tiles: tuple[int, int]) -> None:
    img = Image.fromarray(np.clip(rgba * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")
    img.save(OUT / name, optimize=True)
    print(f"{name}: {img.size[0]}x{img.size[1]}")
    if preview is not None:
        E.tiled_preview(img, preview / name.replace(".png", "-tiled.png"), *tiles)


def join(a: np.ndarray, b: np.ndarray, overlap: int) -> np.ndarray:
    """`a` then `b`, joined along a minimum-error seam over `overlap` columns."""
    both = np.concatenate([a, b[:, overlap:]], axis=1)
    left, right = a[:, -overlap:], b[:, :overlap]
    cost = ((left - right) ** 2).sum(axis=2)
    acc = cost.copy()
    for y in range(1, cost.shape[0]):
        prev = acc[y - 1]
        best = np.minimum(prev, np.minimum(np.roll(prev, 1), np.roll(prev, -1)))
        acc[y] += best
    seam = np.zeros(cost.shape[0], dtype=int)
    seam[-1] = int(np.argmin(acc[-1]))
    for y in range(cost.shape[0] - 2, -1, -1):
        x = seam[y + 1]
        lo, hi = max(0, x - 1), min(overlap, x + 2)
        seam[y] = lo + int(np.argmin(acc[y, lo:hi]))
    start = a.shape[1] - overlap
    for y in range(cost.shape[0]):
        both[y, start + seam[y]:start + overlap] = right[y, seam[y]:]
    return both


# --- wall ------------------------------------------------------------------------------------

def build_wall(preview: Path | None) -> None:
    h3 = load("h3")
    x0, x1 = WALL_SPANS[0][0], WALL_SPANS[1][1]
    top = crevice(h3, x0, x1, WALL_COURSE_ROWS[0])
    bottom = crevice(h3, x0, x1, WALL_COURSE_ROWS[1])
    scale = COURSE / (bottom - top)
    spans = [h3[top:bottom, a:b, :3] for a, b in WALL_SPANS]
    row = E.periodic(join(spans[0], spans[1], SEAM), SEAM)
    row = E.resize(row, round(row.shape[1] * scale), COURSE)
    other = np.roll(row[:, ::-1], round(row.shape[1] * ROW_B_SHIFT), axis=1)
    wall = np.concatenate([row, other], axis=0)
    save(np.concatenate([np.clip(wall, 0, 1), np.ones(wall.shape[:2] + (1,))], axis=-1), f"{STYLE}-wall.png", preview, (3, 3))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
    build_wall(args.preview)


if __name__ == "__main__":
    main()
