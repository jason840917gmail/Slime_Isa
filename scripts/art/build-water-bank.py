#!/usr/bin/env python3
"""Builds the deep-water bank: its 16 shore shapes and its earth strip (docs/godot/specs/water.md §11).

The owner, 2026-10-31: an edge on the water where it meets the ground, on the top and the sides,
"at least on deep water", the art belonging to the water. The shoreline water fill
(terrain_edge_water.gdshader, drawn by TerrainEdges under every ground's edge tiles) draws the
bank from these two images; this tool does not run in the game.

Inputs:
  asset/Originals/water/generated/bank-earth-a.png
      Magnific GPT 2.5: three straight horizontal strips of an earthen pond bank seen from the
      front, each running edge to edge, on transparency.
  godot/asset/MAPS/terrain-edges/<ground>-edges.png
      Every ground's edge tiles: the bank's land shape must stay inside each of them, so the
      grass (sand, snow ...) always covers the bank's top.

Outputs (derived; re-run the tool instead of editing them), in godot/asset/MAPS/water/:
  water-bank-shapes.png
      16 dual-grid tiles in the edge sheets' layout (index TL + 2*TR + 4*BL + 8*BR, 1 = that
      corner's cell is land, at (index % 4, index // 4); 128 px tiles, 2 px gutters, 528 px). Per
      pixel: r = rho / 2, how far down the bank face the pixel lies (0 on the land, 1 at the
      waterline, measured with the shape K: HEIGHT units straight down from land, SIDE units
      sideways, nothing up), g = 0.5 + 0.5 * the face's sideness * its way (0 a side wall with the
      land on its left, 0.5 a front wall, 1 a side wall with the land on its right), b = 1 where
      the bank is near (the water surface's own shore foam fades out there), a = 1.
  water-bank-earth.png
      The earth strip, periodic along its width, 2 px a unit: its height is the bank's face
      (HEIGHT units) plus a tenth under the waterline, where the art's damp foot fades out.

Usage: python scripts/art/build-water-bank.py [--height 24] [--side 11] [--preview DIR]
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "asset/Originals/water/generated/bank-earth-a.png"
EDGES = ROOT / "godot/asset/MAPS/terrain-edges"
OUT = ROOT / "godot/asset/MAPS/water"

TILE = 128            # px per dual-grid tile (one 64-unit cell)
GUTTER = 2            # as the edge sheets: atlas margins 2, separation 4
PX = 2.0              # art px per world unit
PAD = 96              # px of the corner's cells carried on around a tile
P = 2.5               # the shape K's superellipse exponent (as the cliffs' side walls)
LAND_BLUR = 18        # px: two box blurs round the land's corners ...
LAND_LEVEL = 0.72     # ... and this level of the blur insets its straight edges by about 4 units
NEAR = 36.0           # units: the reach (down and sideways) where the surface's shore foam fades
FOOT = 0.1            # the strip carries this much of the face again under the waterline
JOIN = 28             # px: crossfade between the strip's three bands


def box_blur(a: np.ndarray, r: int) -> np.ndarray:
    out = a
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r + 1, r)
        p = np.pad(out, pad, mode="edge")
        c = np.cumsum(p, axis=axis)
        n = 2 * r + 1
        out = (c[n:, :] - c[:-n, :]) / n if axis == 0 else (c[:, n:] - c[:, :-n]) / n
    return out


def land_cells(index: int) -> np.ndarray:
    """The four cells around the corner, carried on PAD px past the tile: True = land."""
    size = TILE + 2 * PAD
    half = PAD + TILE // 2
    out = np.zeros((size, size), dtype=bool)
    out[:half, :half] = bool(index & 1)
    out[:half, half:] = bool(index & 2)
    out[half:, :half] = bool(index & 4)
    out[half:, half:] = bool(index & 8)
    return out


def land_shape(index: int) -> np.ndarray:
    """The land as the bank sees it: the cells, corners rounded, straight edges inset."""
    blurred = box_blur(box_blur(land_cells(index).astype(np.float32), LAND_BLUR), LAND_BLUR)
    return blurred >= LAND_LEVEL


def extrude(land: np.ndarray, down: float, side: float) -> tuple[np.ndarray, np.ndarray]:
    """rho (the K-norm to the nearest land up or sideways: K is `down` px straight down, `side`
    px sideways, nothing up) and the signed sideness of that nearest offset, per pixel."""
    h, w = land.shape
    # straight distance up to land per column (0 on land)
    up = np.full((h, w), 1e6, dtype=np.float32)
    run = np.full(w, 1e6, dtype=np.float32)
    for y in range(h):
        run = np.where(land[y], 0.0, run + 1.0)
        up[y] = run
    rho = np.full((h, w), 9.0, dtype=np.float32)
    signed = np.zeros((h, w), dtype=np.float32)
    reach = int(np.ceil(side * 2.0))
    for dx in range(-reach, reach + 1):
        # land at p - (dx, dy): the column dx to the left
        col = np.full((h, w), 1e6, dtype=np.float32)
        if dx >= 0:
            col[:, dx:] = up[:, :w - dx]
        else:
            col[:, :dx] = up[:, -dx:]
        a = abs(dx) / side
        k = (a ** P + (col / down) ** P) ** (1.0 / P)
        better = k < rho
        rho = np.where(better, k, rho)
        b = col / down
        sideness = np.where(a + b > 0, a / np.maximum(a + b, 1e-6), 0.0)
        # dx > 0: the land lies to the left (its east face, in shade)
        signed = np.where(better, sideness * (-1.0 if dx > 0 else 1.0 if dx < 0 else 0.0), signed)
    return rho, signed


def shapes(height: float, side: float) -> dict[int, np.ndarray]:
    tiles = {}
    for index in range(16):
        land = land_shape(index)
        rho, signed = extrude(land, height * PX, side * PX)
        near, _ = extrude(land, NEAR * PX, NEAR * PX)
        crop = (slice(PAD, PAD + TILE), slice(PAD, PAD + TILE))
        tile = np.zeros((TILE, TILE, 4), dtype=np.float32)
        tile[..., 0] = np.clip(rho[crop] / 2.0, 0.0, 1.0)
        tile[..., 1] = 0.5 + 0.5 * signed[crop]
        tile[..., 2] = 1.0 - np.clip((near[crop] - 0.55) / 0.45, 0.0, 1.0)
        tile[..., 3] = 1.0
        tiles[index] = tile
    return tiles


def check_against_edges() -> None:
    """How much of the bank's land shape lies outside each ground's edge art (where water
    would show between the grass and the bank's top)."""
    sheets = sorted(p for p in EDGES.glob("*-edges.png"))
    worst = 0.0
    for index in range(1, 15):
        land = land_shape(index)[PAD:PAD + TILE, PAD:PAD + TILE]
        col, row = index % 4, index // 4
        x0 = GUTTER + col * (TILE + 2 * GUTTER)
        y0 = GUTTER + row * (TILE + 2 * GUTTER)
        for sheet in sheets:
            alpha = np.asarray(Image.open(sheet).convert("RGBA"))[y0:y0 + TILE, x0:x0 + TILE, 3] / 255.0
            outside = (land & (alpha < 0.5)).sum() / max(land.sum(), 1)
            worst = max(worst, outside)
            if outside > 0.01:
                print(f"  index {index:2d} {sheet.name}: {outside * 100:.1f}% of the land shape is outside the art")
    print(f"land shape outside the edge art: worst {worst * 100:.2f}%")


def sheet_of(tiles: dict[int, np.ndarray]) -> np.ndarray:
    step = TILE + 2 * GUTTER
    out = np.zeros((4 * step, 4 * step, 4), dtype=np.float32)
    for index, tile in tiles.items():
        col, row = index % 4, index // 4
        out[row * step:(row + 1) * step, col * step:(col + 1) * step] = np.pad(
            tile, ((GUTTER, GUTTER), (GUTTER, GUTTER), (0, 0)), mode="edge")
    return out


def bands(source: Path) -> list[tuple[int, int, int]]:
    """(top, waterline, bottom) rows of each strip: alpha 0.5 at the top and the waterline."""
    alpha = np.asarray(Image.open(source).convert("RGBA"))[..., 3].mean(axis=1) / 255.0
    rows = np.where(alpha > 0.5)[0]
    runs, start, last = [], rows[0], rows[0]
    for r in rows[1:]:
        if r != last + 1:
            runs.append((start, last))
            start = r
        last = r
    runs.append((start, last))
    return [(int(a), int(b), int(b + (b - a) * FOOT)) for a, b in runs if b - a > 40]


def strip(height: float) -> np.ndarray:
    """The three bands at the face's height, joined end to end and wrapped round (periodic)."""
    image = Image.open(SOURCE).convert("RGBA")
    face = int(round(height * PX))
    rows = int(round(face * (1.0 + FOOT)))
    pieces = []
    for top, line, bottom in bands(SOURCE):
        band = image.crop((0, top, image.width, bottom + 1))
        width = int(round(image.width * face / (line - top)))
        band = np.asarray(band.resize((width, rows), Image.LANCZOS)).astype(np.float32) / 255.0
        # the top lies under the land's edge: opaque
        band[: rows // 3, :, 3] = 1.0
        pieces.append(band)
    # end to end, each join a crossfade of JOIN px; the last band fades into the first
    out = pieces[0]
    for piece in pieces[1:] + [pieces[0][:, :JOIN]]:
        ramp = np.linspace(0.0, 1.0, JOIN)[None, :, None]
        joined = out[:, -JOIN:] * (1.0 - ramp) + piece[:, :JOIN] * ramp
        out = np.concatenate([out[:, :-JOIN], joined, piece[:, JOIN:]], axis=1)
    # the first JOIN px now live at the end (faded into); drop them at the start
    return out[:, JOIN:]


def save(rgba: np.ndarray, path: Path) -> None:
    Image.fromarray(np.clip(rgba * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(path, optimize=True)
    print("wrote", path.relative_to(ROOT))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--height", type=float, default=24.0, help="the front face, units (default 24)")
    parser.add_argument("--side", type=float, default=11.0, help="the side walls' width, units (default 11)")
    parser.add_argument("--preview", type=Path, help="also write the shapes as pictures here")
    args = parser.parse_args()
    check_against_edges()
    tiles = shapes(args.height, args.side)
    save(sheet_of(tiles), OUT / "water-bank-shapes.png")
    save(strip(args.height), OUT / "water-bank-earth.png")
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
        sheet = sheet_of(tiles)
        rho = sheet[..., 0] * 2.0
        view = np.zeros(sheet.shape[:2] + (3,), dtype=np.float32)
        bank = (rho > 0) & (rho < 1)
        view[..., 0] = np.where(bank, 0.45 + 0.4 * (1 - rho), 0.1)
        view[..., 1] = np.where(rho <= 0, 0.5, np.where(bank, 0.3 * sheet[..., 1], 0.1))
        view[..., 2] = np.where(bank | (rho <= 0), 0.1, 0.25 + 0.5 * sheet[..., 2])
        Image.fromarray((view * 255).astype(np.uint8), "RGB").resize((1056, 1056), Image.NEAREST).save(args.preview / "water-bank-shapes.png")
        print("preview in", args.preview)


if __name__ == "__main__":
    main()
