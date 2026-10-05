#!/usr/bin/env python3
"""Builds the terrain-lab art: 2x ground sheets and the snow edge tile set.

The owner chose 128 px of art per 64-unit tile (2 px per world unit) and hand-made
transition tiles painted with Godot's terrain brush instead of the code blend
(docs/godot/TERRAIN_LAB.md). This tool turns Magnific output into those tiles; it does
not run in the game.

Inputs (asset/Originals/grounds/generated/terrain-edges/):
  frozen-2x-padded-upscale.jpg, sanddessert-2x-padded-upscale.jpg
      Magnific 2x upscales of the 64 px ground sheets after padding them with 152 px of
      wrapped content on every side (1520 px in, 3040 px out). The centre 2432 px is the
      new sheet; the padding lets the seams be blended so the sheet still wraps.
  snow-island.png   GPT 2.5 snow patch on transparency (straight sides, convex corners).
  snow-hole.png     GPT 2.5 snow field with a round transparent hole (concave corners).

Outputs (all derived; re-run the tool instead of editing them):
  godot/game/dev/terrain_lab/art/128x128-tile_19x19_{frozen,sanddessert}.webp
  godot/game/dev/terrain_lab/art/128x128-tile_4x4_snow-edges.png
      16 corner tiles: alpha = snow coverage, rgb = the painted rim. Tile index =
      TL + 2*TR + 4*BL + 8*BR (1 = that corner is snow), at (index % 4, index // 4).
      Index 0 is empty and 15 is fully covered. Each tile has a 2 px gutter of its own
      edge pixels (atlas margins 2, separation 4: the sheet is 528 px).
  godot/game/dev/terrain_lab/art/128x128-tile_4x4_snow-edges-rim.png
      Same layout, greyscale: 1 where the painted rim shows, 0 where the overlay shader
      (snow_edges.gdshader) draws the ice ground texture in world space instead. That is
      what keeps the snow seamless across tiles and with the ice ground beside it.

Geometry: a snow/clear border crosses a tile side at its midpoint, so every tile joins
its neighbours. Straight tiles are cut from the island's straight sides where both ends
match best, then made exactly periodic; every other tile's border strips are blended to
the straight tiles (rim crossings), full cover (all-snow sides) or nothing (all-clear
sides), so any two tiles that can touch share the same border pixels.

Usage: python scripts/art/build-terrain-edge-tiles.py [--preview out.png]
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/grounds/generated/terrain-edges"
LAB_ART = ROOT / "godot/game/dev/terrain_lab/art"

TILE = 128            # art pixels per tile (64 world units at 2 px per unit)
SHEET_TILES = 19      # ground sheets keep the 19x19 sheet-wrap layout
PAD_OUT = 304         # 152 px of padding, doubled by the upscale
SEAM = 48             # blend width for the ground sheet wrap seams
BORDER = 20           # border strip blended to the canonical join
RIM_SIGMA = 7.0       # how far the painted rim reaches into the snow (Gaussian sigma, px)
GUTTER = 2            # edge-pixel gutter around each tile in the edge sheets
TL, TR, BL, BR = 1, 2, 4, 8
CHANNELS = 5          # premultiplied RGBA + rim weight


# ---------------------------------------------------------------- helpers

def smoothstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def load_premul(path: Path) -> np.ndarray:
    """RGBA file -> float premultiplied array (h, w, 4) in 0..1."""
    a = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64) / 255.0
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


def hole_circle(alpha: np.ndarray) -> tuple[float, float, float]:
    """Centre and radius of the transparent hole around the image centre."""
    h, w = alpha.shape
    # copy(): an image made from a numpy buffer is read-only and floodfill would not stick
    clear = Image.fromarray(np.where(alpha < 0.5, 255, 0).astype(np.uint8), "L").copy()
    ImageDraw.floodfill(clear, (w // 2, h // 2), 128)
    hole = np.asarray(clear) == 128
    ys, xs = np.nonzero(hole)
    return float(xs.mean()), float(ys.mean()), float(np.sqrt(hole.sum() / np.pi))


def match_colour(premul: np.ndarray, ref_rgb: np.ndarray) -> np.ndarray:
    """Moves the opaque snow's colour statistics onto the ice ground's, so the painted rim
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


def build_edges(island_path: Path, hole_path: Path, ice_rgb: np.ndarray) -> dict[int, np.ndarray]:
    tiles: dict[int, np.ndarray] = {}

    # Island: rims to the middle of the outer ring of a 3x3 tile canvas.
    island = match_colour(load_premul(island_path), ice_rgb)
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

    # Hole: circle of radius TILE/2 centred on the middle corner of a 2x2 tile canvas.
    hole = match_colour(load_premul(hole_path), ice_rgb)
    cx, cy, r = hole_circle(hole[..., 3])
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
    full[..., :3] = ice_rgb.reshape(-1, 3).mean(0)   # never shown (no rim), keeps blends neutral
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
        # a, b: snow at the side's first and second end (top->bottom or left->right).
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

    # Straight tiles first (their all-snow and all-clear sides only: their rim sides already
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


# ---------------------------------------------------------------- preview

PREVIEW_MAP = [
    "................",
    "..####..........",
    "..#####.....##..",
    "..######...###..",
    "...#####...###..",
    "....###.........",
    "..........#.....",
    "...####....#....",
    "...#..#.........",
    "...####.........",
    "................",
]


def preview(frozen: np.ndarray, sand: np.ndarray, tiles: dict[int, np.ndarray], path: Path) -> None:
    """Top: today's hard cell edges. Bottom: sand ground + the snow edge layer, drawn the way
    snow_edges.gdshader draws it (ground texture in world space, painted rim on top)."""
    rows, cols = len(PREVIEW_MAP), len(PREVIEW_MAP[0])
    ice = {(x, y) for y, line in enumerate(PREVIEW_MAP) for x, ch in enumerate(line) if ch == "#"}

    def frame(sheet: np.ndarray, x: int, y: int) -> np.ndarray:
        fx, fy = x % SHEET_TILES, y % SHEET_TILES
        return sheet[fy * TILE:(fy + 1) * TILE, fx * TILE:(fx + 1) * TILE] / 255.0

    hard = np.zeros((rows * TILE, cols * TILE, 3))
    soft = np.zeros_like(hard)
    for y in range(rows):
        for x in range(cols):
            cell = np.s_[y * TILE:(y + 1) * TILE, x * TILE:(x + 1) * TILE]
            hard[cell] = frame(frozen if (x, y) in ice else sand, x, y)
            soft[cell] = frame(sand, x, y)

    def corner(cx: int, cy: int) -> bool:   # a grid corner is snow if a painted cell touches it
        return any((cx - dx, cy - dy) in ice for dx in (0, 1) for dy in (0, 1))

    for y in range(rows):
        for x in range(cols):
            index = (TL * corner(x, y) + TR * corner(x + 1, y)
                     + BL * corner(x, y + 1) + BR * corner(x + 1, y + 1))
            t = tiles[index]
            alpha, rim = t[..., 3:4], t[..., 4:5]
            painted = straight_rgba(t)[..., :3]
            colour = frame(frozen, x, y) * (1.0 - rim) + painted * rim
            cell = np.s_[y * TILE:(y + 1) * TILE, x * TILE:(x + 1) * TILE]
            soft[cell] = colour * alpha + soft[cell] * (1.0 - alpha)
    both = np.concatenate([hard, soft], axis=0)
    Image.fromarray(np.clip(both * 255 + 0.5, 0, 255).astype(np.uint8), "RGB").save(path)


# ---------------------------------------------------------------- main

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preview", type=Path, help="write a hard-edge vs edge-tile comparison PNG")
    args = parser.parse_args()

    LAB_ART.mkdir(parents=True, exist_ok=True)
    sheets = {}
    for name in ("frozen", "sanddessert"):
        sheet = seamless_sheet(SRC / f"{name}-2x-padded-upscale.jpg")
        sheets[name] = sheet
        im = Image.fromarray(np.clip(sheet + 0.5, 0, 255).astype(np.uint8), "RGB")
        im.save(LAB_ART / f"128x128-tile_19x19_{name}.webp", quality=90, method=6)
        print(f"ground {name}: {im.size[0]} px")

    tiles = build_edges(SRC / "snow-island.png", SRC / "snow-hole.png", sheets["frozen"] / 255.0)
    sheet = edge_sheet(tiles)
    save_rgba(sheet[..., :4], LAB_ART / "128x128-tile_4x4_snow-edges.png")
    Image.fromarray(np.clip(sheet[..., 4] * 255.0 + 0.5, 0, 255).astype(np.uint8), "L").save(
        LAB_ART / "128x128-tile_4x4_snow-edges-rim.png", optimize=True)
    print(f"snow edges: 16 tiles at {TILE} px (+ rim weights)")
    if args.preview:
        preview(sheets["frozen"], sheets["sanddessert"], tiles, args.preview)
        print(f"preview: {args.preview}")


if __name__ == "__main__":
    main()
