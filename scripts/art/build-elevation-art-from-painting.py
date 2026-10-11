#!/usr/bin/env python3
"""Cuts elevation cliff art (docs/godot/ELEVATION.md) out of the approved H plateau paintings, so the
elevation system draws cliffs in their look (docs/godot/CLIFFS.md "Painted elevation").

The elevation system draws a cliff from five pieces laid along the painted outline: a wall texture
that repeats sideways and down, corner stones where a wall ends, a lip along a top's border, a foot
along a wall's base. This tool cuts them from the aligned paintings (godot/asset/MAPS/cliffs/
kit-h2.png and kit-h3.png, built by scripts/art/build-cliff-kit.py: one stone course = 128 px):

  wall    the clean middle course of the three-course painting (h3), one row from each leg of the H,
          resampled to 128 px and made horizontally periodic (two rows: stacked courses alternate);
  ends    the rounded end stones of the same courses, on the left and right of each leg;
  lip     the two-course painting's (h2) fern band along the wall's top, with the hanging ferns and
          vines below it (the stone between them cut away), at LIP_SCALE so the band fits the
          strip the elevation geometry gives a lip (96 px over the top, 64 past the edge);
  foot    the ferns and rubble along the wall's base, the stone above them cut away;
  coping  the railings' coping for stairs leaving these walls (build-elevation-art.py).

Outputs (derived; re-run the tool instead of editing them) in godot/asset/MAPS/elevation/:
  storybook-rock-wall.png, storybook-rock-wall-end-left.png / -right.png,
  storybook-rock-stairs-coping.png, storybook-grass-lip.png, storybook-grass-foot.png
A world uses them through its ground layer's metadata (elevation.gd): `cliff_wall_styles`
{"highland": "storybook-rock"} and `cliff_fringe` {"highland": "storybook-grass"}.

Usage: python scripts/art/build-elevation-art-from-painting.py [--preview DIR]   (numpy, Pillow)
"""
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
KITS = ROOT / "godot/asset/MAPS/cliffs"
_spec = importlib.util.spec_from_file_location("elevation_art", ROOT / "scripts/art/build-elevation-art.py")
E = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(E)
OUT = E.OUT

STYLE = "storybook-rock"
FRINGE = "storybook-grass"
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
## End stones: each leg's ends in the same course, searched outward from these columns (inside the
## end stones); the end line sits END_OUTSIDE px (elevation.gd WALL_END_OUTSIDE) inside the tip.
LEG_ENDS = {"left": (420, 1830), "right": (1200, 2600)}
END_OUTSIDE = 10
END_INSIDE = 64
## Lip and foot: h2's top edge and base (rows of kit-h2.png), along the clean middle of each leg
## (columns), at LIP_SCALE so the fern band fits the strip the elevation gives a lip (96 px over
## the top, 64 past the edge; build-elevation-art.py LAYOUT).
H2_TOP = 2432
H2_BASE = 2690
FRINGE_SPANS = ((480, 1160), (1890, 2590))
LIP_SCALE = 0.75
LAYOUT = {"lip": (96, 64), "foot": (48, 80)}


def load(name: str) -> np.ndarray:
    return np.asarray(Image.open(KITS / f"kit-{name}.png").convert("RGBA"), dtype=np.float64) / 255.0


def hsv(rgb: np.ndarray) -> np.ndarray:
    img = Image.fromarray(np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8), "RGB").convert("HSV")
    return np.asarray(img, dtype=np.float64) / 255.0


def stone_mask(rgb: np.ndarray) -> np.ndarray:
    """Grey-brown stone: unsaturated and not dark (grass, ferns and soil are saturated)."""
    h = hsv(rgb)
    return (h[..., 1] < 0.72) & (h[..., 2] > 0.28)


def plant_mask(rgb: np.ndarray, grow: int = 2) -> np.ndarray:
    """Ferns, vines, moss and soil: saturated and not black, grown a few px into their dark outlines."""
    h = hsv(rgb)
    core = (h[..., 1] > 0.74) & (h[..., 2] > 0.2)
    img = Image.fromarray((core * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(2 * grow + 1))
    dark = h[..., 2] < 0.32
    return core | ((np.asarray(img) > 127) & dark)


def soft(mask: np.ndarray, radius: float = 1.2) -> np.ndarray:
    img = Image.fromarray((mask * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(img, dtype=np.float64) / 255.0


def stone_extent(a: np.ndarray, top: int, bottom: int, x: int, step: int) -> int:
    """From column x, the first column outward (step -1 left, +1 right) with no stone: the stone's tip."""
    frac = stone_mask(a[top + 8:bottom - 8, :, :3]).mean(axis=0)
    while frac[x] > 0.4:
        x += step
    return x - step


def crevice(a: np.ndarray, x0: int, x1: int, near: int) -> int:
    lum = a[near - CREVICE_SEARCH:near + CREVICE_SEARCH, x0:x1, :3].mean(axis=(1, 2))
    return near - CREVICE_SEARCH + int(np.argmin(lum))


def premul(a: np.ndarray) -> np.ndarray:
    out = a.copy()
    out[..., :3] *= out[..., 3:4]
    return out


def straight(p: np.ndarray) -> np.ndarray:
    out = p.copy()
    out[..., :3] = np.where(p[..., 3:4] > 1e-6, p[..., :3] / np.maximum(p[..., 3:4], 1e-6), 0.0)
    return out


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


# --- wall and ends ---------------------------------------------------------------------------

def build_wall_and_ends(preview: Path | None) -> None:
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
    for side, starts in LEG_ENDS.items():
        rows = []
        for x in starts:
            if side == "left":
                tip = stone_extent(h3, top, bottom, x, -1)
                window = h3[top:bottom, tip:tip + END_OUTSIDE + END_INSIDE]
            else:
                tip = stone_extent(h3, top, bottom, x, 1)
                window = h3[top:bottom, tip - END_OUTSIDE - END_INSIDE + 1:tip + 1][:, ::-1]
            print(f"{side} end stone tip at column {tip}")
            rows.append(end_art(E.resize(window, round(window.shape[1] * scale), COURSE)))
        art = np.concatenate(rows, axis=0)
        save(art if side == "left" else art[:, ::-1], f"{STYLE}-wall-end-{side}.png", preview, (1, 3))


def end_art(window: np.ndarray) -> np.ndarray:
    """A left end (outer side on the left): stone kept outside its end line by its own outline,
    everything kept inside it, the inner side faded into the wall texture."""
    rgb = window[..., :3]
    width = window.shape[1]
    outside = round(END_OUTSIDE * window.shape[1] / (END_OUTSIDE + END_INSIDE))
    alpha = soft(stone_mask(window[..., :3]))
    alpha[:, outside:] = 1.0
    alpha *= E.smoothstep((width - 1 - np.arange(width, dtype=np.float64)) / 6.0)[None, :]
    return np.concatenate([np.clip(rgb, 0, 1), alpha[..., None]], axis=-1)


# --- lip and foot ----------------------------------------------------------------------------

def fringe(kind: str, preview: Path | None) -> None:
    h2 = load("h2")
    above, below = LAYOUT[kind]
    edge = H2_TOP if kind == "lip" else H2_BASE
    up, down = round(above / LIP_SCALE), round(below / LIP_SCALE)
    pieces = []
    for a, b in FRINGE_SPANS:
        window = h2[edge - up:edge + down, a:b]
        rgb = window[..., :3]
        rows = np.arange(window.shape[0], dtype=np.float64)[:, None]
        plants = soft(plant_mask(rgb))
        if kind == "lip":
            # Over the top: everything (a soil band right past the edge too), the far side fading
            # into the real ground; past the edge: only the plants hanging over the wall.
            alpha = np.where(rows < up + 8, 1.0, plants) * E.smoothstep(rows / 30.0)
        else:
            # Up the wall: only the plants; below the edge: everything, fading into the ground.
            alpha = np.where(rows < up - 4, plants, 1.0) * E.smoothstep((window.shape[0] - 1 - rows) / 30.0)
        art = premul(np.concatenate([rgb, alpha[..., None]], axis=-1))
        pieces.append(E.resize(art, round(art.shape[1] * LIP_SCALE), above + below))
    strip = E.periodic(join(pieces[0], pieces[1], SEAM), SEAM)
    strip[..., 3] = np.clip(strip[..., 3], 0, 1)
    strip[..., :3] = np.clip(strip[..., :3], 0, strip[..., 3:4])
    save(straight(strip), f"{FRINGE}-{kind}.png", preview, (3, 1))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
    build_wall_and_ends(args.preview)
    fringe("lip", args.preview)
    fringe("foot", args.preview)
    E.build_coping(STYLE, args.preview)


if __name__ == "__main__":
    main()
