#!/usr/bin/env python3
"""Builds the hand-made terrain edge tiles: 16 corner tiles per ground (docs/godot/TERRAIN_LAB.md).

The owner chose hand-made transition tiles (Magnific GPT 2.5 art) instead of a code blend,
at 128 px of art per 64-unit cell. For every ground in MATERIALS this tool turns two
generated images into one edge tile sheet; it does not run in the game.

Inputs (asset/Originals/grounds/generated/terrain-edges/):
  <ground>-island.png   a patch of the ground on transparency (straight sides, convex corners)
  <ground>-hole.png     a field of the ground with a round transparent hole (concave corners)
  The ground's own 64 px sheet (godot/asset/MAPS/grounds/) is the colour reference.
  Optional, with --grounds-2x: <ground>-2x-padded-upscale.jpg, a Magnific 2x upscale of the
  ground sheet padded by 152 px of wrapped content (1520 px in, 3040 px out).

Outputs (derived; re-run the tool instead of editing them), in godot/game/world/terrain_edges/art/:
  <ground>-edges.png
      16 corner tiles. alpha = where this ground covers, rgb = its painted rim. Tile index =
      TL + 2*TR + 4*BL + 8*BR (1 = that corner's cell is this ground), at (index % 4,
      index // 4). Index 0 is empty and 15 fully covered. Each tile has a 2 px gutter of its
      own edge pixels (atlas margins 2, separation 4: the sheet is 528 px).
  <ground>-edges-rim.png
      Same layout, greyscale: 1 where the painted rim shows, 0 where the shader
      (terrain_edge.gdshader) draws the ground's own sheet in world space instead, which keeps
      the ground seamless across tiles and with its plain cells.
  With --grounds-2x: <ground>-2x.webp, the seamless 128 px-per-cell ground sheet (2432 px).

Geometry: a border crosses a tile side at its midpoint, so every tile joins its neighbours.
Straight tiles are cut from the island's straight sides where both ends match best, then made
exactly periodic; every other tile's border strips are blended to the straight tiles (rim
crossings), full cover (covered sides) or nothing (uncovered sides), so any two tiles that can
touch share the same border pixels.

Usage: python scripts/art/build-terrain-edge-tiles.py [ground ...] [--preview DIR] [--grounds-2x]
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/grounds/generated/terrain-edges"
GROUND_SHEETS = ROOT / "godot/asset/MAPS/grounds"
OUT = ROOT / "godot/game/world/terrain_edges/art"

## ground (the authored tile set's transition material) -> its 64 px sheet's file stem
MATERIALS = {
    "frozen": "frozen",
    "sanddessert": "sanddessert",
    "highland": "HighlandGreen",
    "forest-floor": "forest-floor",
    "forest-moss": "forest-moss",
    "crystal-floor": "crystal-floor",
    "cavern-floor": "cavern-floor",
    "amberleaf": "amberleaf",
    "town-cobble": "town-cobble",
}

TILE = 128            # art pixels per tile (64 world units at 2 px per unit)
SHEET_TILES = 19      # ground sheets keep the 19x19 sheet-wrap layout
PAD_OUT = 304         # 152 px of padding, doubled by the upscale
SEAM = 48             # blend width for the ground sheet wrap seams
BORDER = 20           # border strip blended to the canonical join
RIM_SIGMA = 7.0       # how far the painted rim reaches into the ground (Gaussian sigma, px)
HAZE_ALPHA = 0.15     # coverage below this is generator haze, not art
GUTTER = 2            # edge-pixel gutter around each tile in the edge sheets
TL, TR, BL, BR = 1, 2, 4, 8
CHANNELS = 5          # premultiplied RGBA + rim weight


# ---------------------------------------------------------------- helpers

def smoothstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def load_premul(path: Path) -> np.ndarray:
    """RGBA file -> float premultiplied array (h, w, 4) in 0..1, generator haze removed."""
    a = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64) / 255.0
    a[a[..., 3] < HAZE_ALPHA] = 0.0
    a[..., :3] *= a[..., 3:4]
    return a


def straight_rgba(premul: np.ndarray) -> np.ndarray:
    a = premul[..., :4].copy()
    alpha = a[..., 3:4]
    a[..., :3] = np.where(alpha > 1e-6, a[..., :3] / np.maximum(alpha, 1e-6), 0.0)
    return a


def save_rgba(premul: np.ndarray, path: Path) -> None:
    Image.fromarray(np.clip(straight_rgba(premul) * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(path, optimize=True)


def resample(premul: np.ndarray, box: tuple[float, float, float, float], size: int) -> np.ndarray:
    """Resamples the premultiplied region `box` (x0, y0, x1, y1, may leave the image) to size^2."""
    h, w = premul.shape[:2]
    margin = int(max(0, -box[0], -box[1], box[2] - w, box[3] - h)) + 2
    padded = np.zeros((h + 2 * margin, w + 2 * margin, premul.shape[2]))
    padded[margin:margin + h, margin:margin + w] = premul
    shifted = (box[0] + margin, box[1] + margin, box[2] + margin, box[3] + margin)
    channels = []
    for c in range(premul.shape[2]):
        im = Image.fromarray(padded[..., c].astype(np.float32), "F")
        channels.append(np.asarray(im.resize((size, size), Image.LANCZOS, box=shifted), dtype=np.float64))
    out = np.stack(channels, axis=-1)
    out[..., 3] = np.clip(out[..., 3], 0.0, 1.0)
    out[..., :3] = np.clip(out[..., :3], 0.0, out[..., 3:4])
    return out


def with_rim(premul: np.ndarray) -> np.ndarray:
    """Adds the rim-weight channel: high near uncovered pixels, fading over ~3 sigma inside."""
    clear = Image.fromarray(((1.0 - premul[..., 3]) * 255.0).astype(np.uint8), "L")
    near = np.asarray(clear.filter(ImageFilter.GaussianBlur(RIM_SIGMA)), dtype=np.float64) / 255.0
    rim = smoothstep(near * 4.0)
    return np.concatenate([premul, rim[..., None]], axis=-1)


def over(top: np.ndarray, bottom: np.ndarray) -> np.ndarray:
    out = top + bottom * (1.0 - top[..., 3:4])
    out[..., 4] = np.maximum(top[..., 4], bottom[..., 4])
    return out


# ---------------------------------------------------------------- ground sheets

def seamless_sheet(padded_upscale: Path) -> np.ndarray:
    """Centre crop of the padded upscale with both wrap seams blended (exactly periodic)."""
    a = np.asarray(Image.open(padded_upscale).convert("RGB"), dtype=np.float64)
    size = TILE * SHEET_TILES
    p = PAD_OUT

    def fix_x(arr: np.ndarray) -> np.ndarray:
        # Past the right crop line the padded upscale shows the same ground as the left
        # edge (and vice versa): blending the two makes column size-1 continue into 0.
        out = arr[:, p:p + size].copy()
        for x in range(SEAM):
            w = 0.5 * float(smoothstep(np.array(1.0 - x / SEAM)))
            out[:, x] = (1 - w) * arr[:, p + x] + w * arr[:, p + size + x]
            out[:, size - 1 - x] = (1 - w) * arr[:, p + size - 1 - x] + w * arr[:, p - 1 - x]
        return out

    fixed = fix_x(a)
    return fix_x(fixed.transpose(1, 0, 2)).transpose(1, 0, 2)


# ---------------------------------------------------------------- edge art

def rim_lines(alpha: np.ndarray) -> tuple[float, float, float, float]:
    """Median alpha-0.5 crossings of the island's four sides (top, bottom, left, right)."""
    mask = alpha > 0.5
    ys, xs = np.nonzero(mask)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    cols = range(int(x0 + 0.3 * (x1 - x0)), int(x0 + 0.7 * (x1 - x0)))
    rows = range(int(y0 + 0.3 * (y1 - y0)), int(y0 + 0.7 * (y1 - y0)))
    top = np.median([np.argmax(mask[:, c]) for c in cols])
    bottom = np.median([len(mask) - 1 - np.argmax(mask[::-1, c]) for c in cols])
    left = np.median([np.argmax(mask[r, :]) for r in rows])
    right = np.median([mask.shape[1] - 1 - np.argmax(mask[r, ::-1]) for r in rows])
    return float(top), float(bottom), float(left), float(right)


def hole_region(alpha: np.ndarray) -> np.ndarray:
    """The uncovered region connected to the image centre (the hole), as a boolean mask."""
    h, w = alpha.shape
    # copy(): an image made from a numpy buffer is read-only and floodfill would not stick
    clear = Image.fromarray(np.where(alpha < 0.5, 255, 0).astype(np.uint8), "L").copy()
    ImageDraw.floodfill(clear, (w // 2, h // 2), 128)
    return np.asarray(clear) == 128


def clear_hole(premul: np.ndarray) -> np.ndarray:
    """Empties the hole: the generator often paints a pale fog into it that fades from opaque at
    the art to clear at the centre. When the hole holds such fog, every fog-coloured pixel
    connected to the centre is cleared (the art around it has other colours); else just the
    uncovered region. Returns the cleared hole mask."""
    alpha = premul[..., 3]
    region = hole_region(alpha)
    faint = region & (alpha > 0.02)
    rgb = straight_rgba(premul)[..., :3]
    fog = np.median(rgb[faint], axis=0) if faint.sum() > 2000 else None
    art = np.median(rgb[alpha > 0.95], axis=0)
    # Fog the colour of the art itself (a pale snow field) cannot be told apart: keep the region.
    if fog is not None and np.linalg.norm(fog - art) > 0.25:
        # A pixel is fog when it is closer to the fog colour than to the art's.
        to_fog = np.linalg.norm(rgb - fog, axis=-1)
        to_art = np.linalg.norm(rgb - art, axis=-1)
        foggy = (to_fog < to_art * 0.8) | (alpha < 0.5)
        h, w = alpha.shape
        mask = Image.fromarray(np.where(foggy, 255, 0).astype(np.uint8), "L").copy()
        ImageDraw.floodfill(mask, (w // 2, h // 2), 128)
        region = np.asarray(mask) == 128
    premul[region] = 0.0
    return region


def hole_circle(hole: np.ndarray) -> tuple[float, float, float]:
    """Centre and radius of the hole region."""
    ys, xs = np.nonzero(hole)
    if len(xs) == 0:
        raise SystemExit("hole image: no transparent hole at the image centre")
    return float(xs.mean()), float(ys.mean()), float(np.sqrt(hole.sum() / np.pi))


def match_colour(premul: np.ndarray, ref_rgb: np.ndarray) -> np.ndarray:
    """Moves the opaque art's colour statistics onto the ground sheet's, so the painted rim
    blends into the ground texture the shader draws behind it."""
    alpha = premul[..., 3]
    solid = alpha > 0.98
    rgb = np.where(alpha[..., None] > 1e-6, premul[..., :3] / np.maximum(alpha[..., None], 1e-6), 0.0)
    src_mu, src_sd = rgb[solid].mean(0), rgb[solid].std(0)
    ref = ref_rgb.reshape(-1, 3)
    dst_mu, dst_sd = ref.mean(0), ref.std(0)
    gain = np.clip(dst_sd / np.maximum(src_sd, 1e-6), 0.7, 1.3)
    rgb = np.clip((rgb - src_mu) * gain + dst_mu, 0.0, 1.0)
    out = premul.copy()
    out[..., :3] = rgb * alpha[..., None]
    return out


def periodic(tile: np.ndarray, axis: int, band: int) -> np.ndarray:
    """Makes the tile wrap along `axis`: within `band` px of both ends it cross-fades to a
    copy rolled by half, whose first and last lines are neighbours in the original."""
    t = np.moveaxis(tile, axis, 0)
    n = t.shape[0]
    rolled = np.roll(t, n // 2, axis=0)
    idx = np.arange(n)
    dist = np.minimum(idx, n - 1 - idx).astype(np.float64)
    keep = smoothstep(dist / band)[:, None, None]
    out = t * keep + rolled * (1.0 - keep)
    return np.moveaxis(out, 0, axis)


def best_window(canvas: np.ndarray, horizontal: bool, start: int, stop: int) -> int:
    """Offset of the TILE-long window along a straight side whose two ends look most alike."""
    alpha = canvas[..., 3]
    best, best_cost = start, float("inf")
    for o in range(start, stop - TILE + 1):
        if horizontal:
            a, b = alpha[:, o], alpha[:, o + TILE - 1]
        else:
            a, b = alpha[o, :], alpha[o + TILE - 1, :]
        cost = float(np.abs(a - b).sum())
        if cost < best_cost:
            best, best_cost = o, cost
    return best


def cut(canvas: np.ndarray, col: int, row: int) -> np.ndarray:
    return canvas[row * TILE:(row + 1) * TILE, col * TILE:(col + 1) * TILE].copy()


def build_edges(island_path: Path, hole_path: Path, ground_rgb: np.ndarray) -> dict[int, np.ndarray]:
    tiles: dict[int, np.ndarray] = {}

    # Island: rims to the middle of the outer ring of a 3x3 tile canvas.
    island = match_colour(load_premul(island_path), ground_rgb)
    top, bottom, left, right = rim_lines(island[..., 3])
    sx, sy = (right - left) / (2 * TILE), (bottom - top) / (2 * TILE)
    box = (left - TILE / 2 * sx, top - TILE / 2 * sy, left + 5 * TILE / 2 * sx, top + 5 * TILE / 2 * sy)
    isl = with_rim(resample(island, box, 3 * TILE))
    for (col, row), index in {(0, 0): BR, (2, 0): BL, (0, 2): TR, (2, 2): TL}.items():
        tiles[index] = cut(isl, col, row)

    # Straight sides: the TILE-long window of the straight part between the rounded corners
    # whose ends match best, then an exact wrap.
    lo, hi = TILE // 2 + 24, 5 * TILE // 2 - 24
    o = best_window(isl[0:TILE], True, lo, hi)
    tiles[BL | BR] = periodic(isl[0:TILE, o:o + TILE], 1, 16)
    o = best_window(isl[2 * TILE:3 * TILE], True, lo, hi)
    tiles[TL | TR] = periodic(isl[2 * TILE:3 * TILE, o:o + TILE], 1, 16)
    o = best_window(isl[:, 0:TILE], False, lo, hi)
    tiles[TR | BR] = periodic(isl[o:o + TILE, 0:TILE], 0, 16)
    o = best_window(isl[:, 2 * TILE:3 * TILE], False, lo, hi)
    tiles[TL | BL] = periodic(isl[o:o + TILE, 2 * TILE:3 * TILE], 0, 16)

    # Hole: circle of radius TILE/2 centred on the middle corner of a 2x2 tile canvas. Haze the
    # generator left inside the hole is cleared first.
    hole = load_premul(hole_path)
    region = clear_hole(hole)
    hole = match_colour(hole, ground_rgb)
    cx, cy, r = hole_circle(region)
    s = r / (TILE / 2)
    hol = with_rim(resample(hole, (cx - TILE * s, cy - TILE * s, cx + TILE * s, cy + TILE * s), 2 * TILE))
    tiles[TL | TR | BL] = cut(hol, 0, 0)
    tiles[TL | TR | BR] = cut(hol, 1, 0)
    tiles[TL | BL | BR] = cut(hol, 0, 1)
    tiles[TR | BL | BR] = cut(hol, 1, 1)

    # Diagonals: two convex corners.
    tiles[TL | BR] = over(tiles[TL], tiles[BR])
    tiles[TR | BL] = over(tiles[TR], tiles[BL])

    tiles[0] = np.zeros((TILE, TILE, CHANNELS))
    full = np.zeros((TILE, TILE, CHANNELS))
    full[..., :3] = ground_rgb.reshape(-1, 3).mean(0)   # never shown (no rim), keeps blends neutral
    full[..., 3] = 1.0   # covered, no rim: the shader shows only the ground texture
    tiles[15] = full
    return normalise_borders(tiles, full)


def normalise_borders(tiles: dict[int, np.ndarray], full: np.ndarray) -> dict[int, np.ndarray]:
    """Blends every tile's border strips to the shared canonical join for that side."""
    ramp = 1.0 - smoothstep(np.arange(TILE, dtype=np.float64) / BORDER)  # 1 at the side
    clear = np.zeros_like(full)
    straight_ids = (BL | BR, TL | TR, TR | BR, TL | BL)
    straight: dict[int, np.ndarray] = {}

    def canon(side: str, a: bool, b: bool) -> np.ndarray | None:
        # a, b: covered at the side's first and second end (top->bottom or left->right).
        # None: a rim crosses this side and the straight tiles are not final yet.
        if a and b:
            return full
        if not a and not b:
            return clear
        if not straight:
            return None
        if side in ("left", "right"):   # the border runs horizontally across this side
            return straight[TL | TR] if a else straight[BL | BR]
        return straight[TL | BL] if a else straight[TR | BR]

    def normalise(index: int, tile: np.ndarray) -> np.ndarray:
        t = tile.copy()
        bits = {c: bool(index & c) for c in (TL, TR, BL, BR)}
        sides = {
            "top": (bits[TL], bits[TR]), "bottom": (bits[BL], bits[BR]),
            "left": (bits[TL], bits[BL]), "right": (bits[TR], bits[BR]),
        }
        for side, (a, b) in sides.items():
            ref = canon(side, a, b)
            if ref is None:
                continue
            if side == "top":
                w = ramp[:, None, None]
            elif side == "bottom":
                w = ramp[::-1][:, None, None]
            elif side == "left":
                w = ramp[None, :, None]
            else:
                w = ramp[::-1][None, :, None]
            t = t * (1.0 - w) + ref * w
        return t

    # Straight tiles first (their covered and uncovered sides only: their rim sides already
    # wrap), then everything else against the finished straights.
    straight.update({index: normalise(index, tiles[index]) for index in straight_ids})
    out: dict[int, np.ndarray] = dict(straight)
    for index, tile in tiles.items():
        if index not in out:
            out[index] = tile if index in (0, 15) else normalise(index, tile)
    return out


def edge_sheet(tiles: dict[int, np.ndarray]) -> np.ndarray:
    """4x4 sheet with a GUTTER-px copy of each tile's edge pixels around it (atlas margins
    GUTTER, separation 2*GUTTER), so linear filtering never reads a neighbouring tile."""
    step = TILE + 2 * GUTTER
    sheet = np.zeros((4 * step, 4 * step, CHANNELS))
    for index, tile in tiles.items():
        c, r = index % 4, index // 4
        padded = np.pad(tile, ((GUTTER, GUTTER), (GUTTER, GUTTER), (0, 0)), mode="edge")
        sheet[r * step:(r + 1) * step, c * step:(c + 1) * step] = padded
    return sheet


def preview(ground: str, tiles: dict[int, np.ndarray], ground_rgb: np.ndarray, path: Path) -> None:
    """The 16 tiles over a neutral backdrop, drawn as the shader draws them."""
    tile_bg = np.full((TILE, TILE, 3), (0.35, 0.33, 0.30))
    out = np.zeros((4 * TILE, 4 * TILE, 3))
    flat = ground_rgb[:TILE, :TILE]
    for index, t in tiles.items():
        alpha, rim = t[..., 3:4], t[..., 4:5]
        colour = flat * (1.0 - rim) + straight_rgba(t)[..., :3] * rim
        c, r = index % 4, index // 4
        out[r * TILE:(r + 1) * TILE, c * TILE:(c + 1) * TILE] = colour * alpha + tile_bg * (1.0 - alpha)
    Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), "RGB").save(path / f"{ground}-preview.png")


# ---------------------------------------------------------------- main

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("grounds", nargs="*", help="grounds to build (default: every ground with art)")
    parser.add_argument("--preview", type=Path, help="write <ground>-preview.png sheets into this folder")
    parser.add_argument("--grounds-2x", action="store_true", help="also write <ground>-2x.webp from padded upscales")
    args = parser.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
    for ground in args.grounds or list(MATERIALS):
        if ground not in MATERIALS:
            raise SystemExit(f"unknown ground '{ground}' (known: {', '.join(MATERIALS)})")
        island, hole = SRC / f"{ground}-island.png", SRC / f"{ground}-hole.png"
        if not island.exists() or not hole.exists():
            print(f"{ground}: no island/hole art, skipped")
            continue
        sheet_path = GROUND_SHEETS / f"64x64-tile_19x19_{MATERIALS[ground]}.webp"
        ground_rgb = np.asarray(Image.open(sheet_path).convert("RGB"), dtype=np.float64) / 255.0
        tiles = build_edges(island, hole, ground_rgb)
        sheet = edge_sheet(tiles)
        save_rgba(sheet[..., :4], OUT / f"{ground}-edges.png")
        Image.fromarray(np.clip(sheet[..., 4] * 255.0 + 0.5, 0, 255).astype(np.uint8), "L").save(
            OUT / f"{ground}-edges-rim.png", optimize=True)
        print(f"{ground}: 16 edge tiles at {TILE} px (+ rim weights)")
        if args.preview:
            preview(ground, tiles, ground_rgb, args.preview)
        upscale = SRC / f"{ground}-2x-padded-upscale.jpg"
        if args.grounds_2x and upscale.exists():
            sheet_2x = seamless_sheet(upscale)
            Image.fromarray(np.clip(sheet_2x + 0.5, 0, 255).astype(np.uint8), "RGB").save(
                OUT / f"{ground}-2x.webp", quality=90, method=6)
            print(f"{ground}: 2x ground sheet")


if __name__ == "__main__":
    main()
