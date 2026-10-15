#!/usr/bin/env python3
"""Builds a wall style's pieces from its three-part kit (docs/godot/WALLS.md).

A painted wall cell takes one of 16 shapes from its four neighbours (N=1, E=2, S=4, W=8). Every shape
is composed from the style's kit, three Magnific renders in asset/Originals/walls/<style>/kit/:
  run-h   a long straight east-west run (front face under a row of cap stones)
  run-v   a long straight north-south run (the cap stones seen from above)
  pillar  a square pillar a little taller than the wall
The runs are cut gap to gap and wrapped into seamless strips two cells long; each cell draws the
half-arms toward its painted neighbours (the strip at its place along the wall, so runs flow on
without seams) and, unless it is a straight run, the pillar where they meet. Shapes come in four
parities (cell x and y even or odd), as the strips repeat every two cells.

Outputs:
  godot/asset/MAPS/walls/sets/<style>.webp   frame (mask, x parity, y parity) at column mask,
                                             row parity_x + 2 * parity_y
  godot/asset/MAPS/walls/sets/walls.json     per style: the frame size, the foot (cell bottom
                                             middle) inside a frame, and the collision of each shape
  godot/asset/MAPS/walls/sets/palette.png    the WallLayer palette's 64 px tiles
  godot/game/world/walls/wall_tileset.tres   the WallLayer palette: per style an auto tile (row 0),
                                             then every shape, then every exact piece (custom data
                                             `wall_style`, `wall_shape`, `wall_parity`); styles keep
                                             their places, append new ones

Usage: python scripts/art/build-wall-kit.py [style ...]   (numpy, Pillow)
       python scripts/art/build-wall-kit.py --palette     (only the palette, from the built sheets)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

OUT_DIR = ROOT / "godot/asset/MAPS/walls/sets"
TABLE = OUT_DIR / "walls.json"
DENSITY = 2
CELL = 64
## World units (screen, cell local, y down; the cell is 0..64, the wall's foot at y 64).
WALL_HEIGHT = 54          # cap band + front face of an east-west run
RUN_WIDTH = 32            # a north-south run's cap, seen from above
PILLAR_WIDTH = 50
PILLAR_FOOT = 65
JUNCTION = (32, 64 - WALL_HEIGHT + 9)   # where the arms meet: the middle of the cap band
PERIOD = 2 * CELL                       # the strips repeat every two cells
## A frame's box around the cell (world units).
FRAME = (-8, -16, 80, 88)               # left, top, width, height
BLEND = 12                              # wrap cross-fade (world units)
## Cast shadow (light from the upper left): east of north-south runs, south of east-west runs and
## to the lower right of the pillar; soft across a run, constant along it (so runs join without a
## seam). Width (units) and darkest alpha.
SHADOW = 14
SHADOW_ALPHA = 0.55
SHADOW_RGB = (28, 32, 14)
## Collision rectangles (plan, cell local) per arm and for the pillar.
PLAN_JUNCTION_Y = 53
COLLISION = {
    "E": (32, 42, 32, 22), "W": (0, 42, 32, 22),
    "N": (18, PLAN_JUNCTION_Y - 32, 28, 32), "S": (18, PLAN_JUNCTION_Y, 28, 32),
    "pillar": (8, 40, 48, 26),
}
STYLES = {
    "stone": {"run_h": "run-h-b.png", "run_v": "run-v-a.png", "pillar": "pillar-c.png"},
}


def load(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64)


def crop_alpha(rgba: np.ndarray) -> np.ndarray:
    ys, xs = np.nonzero(rgba[..., 3] > 127)
    return rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def resize(rgba: np.ndarray, size: tuple[int, int]) -> np.ndarray:
    """Premultiplied resize to (width, height)."""
    pre = rgba.copy()
    pre[..., :3] *= pre[..., 3:4] / 255
    image = Image.fromarray(np.clip(pre, 0, 255).astype(np.uint8), "RGBa")
    out = np.asarray(image.resize(size, Image.LANCZOS).convert("RGBA"), dtype=np.float64)
    return out


def gaps(profile: np.ndarray, pitch_guess: int) -> list[int]:
    """Local minima of `profile` (dark stone joints), at least half a pitch apart."""
    smooth = np.convolve(profile, np.ones(5) / 5, mode="same")
    found: list[int] = []
    for i in range(2, len(smooth) - 2):
        window = smooth[max(0, i - pitch_guess // 2):i + pitch_guess // 2 + 1]
        if smooth[i] == window.min():
            if not found or i - found[-1] > pitch_guess // 2:
                found.append(i)
    return found


def seamless(strip: np.ndarray, axis: int, period_px: int, band: slice) -> np.ndarray:
    """A piece of `strip` along `axis`, cut at stone joints (found in `band` across the strip),
    stretched to exactly `period_px` and wrapped with a cross-fade, so it tiles."""
    along = strip.shape[1] if axis == 1 else strip.shape[0]
    lum = strip[..., :3].mean(-1) * (strip[..., 3] / 255)
    profile = lum[band, :].mean(0) if axis == 1 else lum[:, band].mean(1)
    joints = gaps(profile, period_px // 5)
    # The run of joints whose span is nearest the period, away from the strip's ends.
    best = None
    for a in range(len(joints)):
        for b in range(a + 1, len(joints)):
            span = joints[b] - joints[a]
            if joints[a] < along * 0.1 or joints[b] > along * 0.9:
                continue
            score = abs(span - period_px)
            if best is None or score < best[0]:
                best = (score, joints[a], joints[b])
    _, start, end = best
    blend_px = BLEND * DENSITY
    extra = int(round(blend_px * (end - start) / period_px))
    piece = strip[:, start:end + extra] if axis == 1 else strip[start:end + extra]
    across = strip.shape[0] if axis == 1 else strip.shape[1]
    size = (period_px + blend_px, across) if axis == 1 else (across, period_px + blend_px)
    piece = resize(piece, size)
    tile = piece[:, :period_px].copy() if axis == 1 else piece[:period_px].copy()
    for i in range(blend_px):
        w = i / blend_px
        if axis == 1:
            tile[:, i] = piece[:, i] * w + piece[:, period_px + i] * (1 - w)
        else:
            tile[i] = piece[i] * w + piece[period_px + i] * (1 - w)
    return tile


def paste(canvas: np.ndarray, image: np.ndarray, x: int, y: int) -> None:
    """Alpha-composites `image` onto `canvas` at (x, y) px (straight alpha)."""
    h, w = image.shape[:2]
    x0, y0 = max(x, 0), max(y, 0)
    x1, y1 = min(x + w, canvas.shape[1]), min(y + h, canvas.shape[0])
    if x0 >= x1 or y0 >= y1:
        return
    src = image[y0 - y:y1 - y, x0 - x:x1 - x]
    dst = canvas[y0:y1, x0:x1]
    a = src[..., 3:4] / 255
    b = dst[..., 3:4] / 255
    out_a = a + b * (1 - a)
    out_rgb = (src[..., :3] * a + dst[..., :3] * b * (1 - a)) / np.maximum(out_a, 1e-6)
    canvas[y0:y1, x0:x1, :3] = out_rgb
    canvas[y0:y1, x0:x1, 3:4] = out_a * 255


def wrap_slice(tile: np.ndarray, axis: int, start_px: int, length_px: int) -> np.ndarray:
    """`length_px` of a seamless `tile` from `start_px` (wrapping)."""
    period = tile.shape[1] if axis == 1 else tile.shape[0]
    idx = (np.arange(length_px) + start_px) % period
    return tile[:, idx] if axis == 1 else tile[idx]


def shadow_band(shape: tuple[int, int], along_axis: int) -> np.ndarray:
    """A shadow band of `shape` (h, w) px, fading across `along_axis`'s perpendicular from the wall
    side (dark) to nothing."""
    h, w = shape
    across = w if along_axis == 0 else h
    fade = np.clip(1 - np.arange(across) / max(1, across - 1), 0, 1) ** 1.5 * SHADOW_ALPHA * 255
    band = np.zeros((h, w, 4))
    band[..., :3] = SHADOW_RGB
    band[..., 3] = fade[None, :] if along_axis == 0 else fade[:, None]
    return band


def px(units: float) -> int:
    return int(round(units * DENSITY))


def build(style: str, kit: dict) -> dict:
    src = ROOT / "asset/Originals/walls" / style / "kit"
    period_px = px(PERIOD)
    # East-west run: the whole wall height at WALL_HEIGHT; joints in its cap band (top third).
    run_h = crop_alpha(load(src / kit["run_h"]))
    scale = px(WALL_HEIGHT) / run_h.shape[0]
    run_h = resize(run_h, (int(round(run_h.shape[1] * scale)), px(WALL_HEIGHT)))
    strip_h = seamless(run_h, 1, period_px, slice(0, run_h.shape[0] // 3))
    # North-south run: RUN_WIDTH across; joints across its middle.
    run_v = crop_alpha(load(src / kit["run_v"]))
    scale = px(RUN_WIDTH) / run_v.shape[1]
    run_v = resize(run_v, (px(RUN_WIDTH), int(round(run_v.shape[0] * scale))))
    strip_v = seamless(run_v, 0, period_px, slice(run_v.shape[1] // 4, 3 * run_v.shape[1] // 4))
    pillar = crop_alpha(load(src / kit["pillar"]))
    scale = px(PILLAR_WIDTH) / pillar.shape[1]
    pillar = resize(pillar, (px(PILLAR_WIDTH), int(round(pillar.shape[0] * scale))))

    # The pillar's shadow: its footprint pushed to the lower right, blurred (it stands away from
    # the frame's edges, so the blur never cuts).
    pad = px(8)
    shadow_w, shadow_h = px(PILLAR_WIDTH) + 2 * pad, px(PILLAR_WIDTH * 0.95) + 2 * pad
    footprint = Image.new("L", (shadow_w, shadow_h), 0)
    footprint.paste(int(SHADOW_ALPHA * 255), (pad, pad, shadow_w - pad, shadow_h - pad))
    footprint = footprint.filter(ImageFilter.GaussianBlur(px(4)))
    pillar_shadow = np.zeros((shadow_h, shadow_w, 4))
    pillar_shadow[..., :3] = SHADOW_RGB
    pillar_shadow[..., 3] = np.asarray(footprint, dtype=np.float64)
    pillar_shadow = pillar_shadow[pad // 2:, pad // 2:]
    fx, fy, fw, fh = FRAME
    frame_w, frame_h = px(fw), px(fh)
    atlas = np.zeros((frame_h * 4, frame_w * 16, 4))
    jx, jy = JUNCTION
    wall_top = 64 - WALL_HEIGHT
    for parity in range(4):
        par_x, par_y = parity % 2, parity // 2
        for mask in range(16):
            canvas = np.zeros((frame_h, frame_w, 4))
            ox, oy = -px(fx), -px(fy)            # the cell's origin inside the frame
            # Cast shadows first, under the stones.
            right = jx + RUN_WIDTH / 2
            for bit, top in ((1, jy - CELL / 2), (4, jy)):
                if mask & bit:
                    paste(canvas, shadow_band((px(CELL / 2), px(SHADOW)), 0), ox + px(right) - 2, oy + px(top + 4))
            for bit, x0 in ((8, 0), (2, CELL / 2)):
                if mask & bit:
                    paste(canvas, shadow_band((px(SHADOW * 0.6), px(CELL / 2)), 1), ox + px(x0), oy + px(64) - 2)
            if mask not in (5, 10):
                paste(canvas, pillar_shadow, ox + px(jx - PILLAR_WIDTH / 2) + px(5), oy + px(PILLAR_FOOT - PILLAR_WIDTH * 0.95) + px(3))
            if mask & 1:   # north half-arm: from the junction up half a cell
                top = jy - CELL / 2
                piece = wrap_slice(strip_v, 0, px(par_y * CELL + top), px(CELL / 2))
                paste(canvas, piece, ox + px(jx - RUN_WIDTH / 2), oy + px(top))
            for bit, x0 in ((8, 0), (2, CELL / 2)):
                if mask & bit:
                    piece = wrap_slice(strip_h, 1, px(par_x * CELL + x0), px(CELL / 2))
                    paste(canvas, piece, ox + px(x0), oy + px(wall_top))
            if mask & 4:   # south half-arm: from the junction down half a cell
                piece = wrap_slice(strip_v, 0, px(par_y * CELL + jy), px(CELL / 2))
                paste(canvas, piece, ox + px(jx - RUN_WIDTH / 2), oy + px(jy))
            if mask not in (5, 10):
                paste(canvas, pillar, ox + px(jx) - pillar.shape[1] // 2, oy + px(PILLAR_FOOT) - pillar.shape[0])
            canvas[canvas[..., 3] < 1, :3] = 0
            atlas[parity * frame_h:(parity + 1) * frame_h, mask * frame_w:(mask + 1) * frame_w] = canvas
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    save_game_webp(Image.fromarray(np.clip(atlas, 0, 255).astype(np.uint8), "RGBA"), OUT_DIR / f"{style}.webp")
    collision = {}
    for mask in range(16):
        rects = [COLLISION[arm] for bit, arm in ((1, "N"), (2, "E"), (4, "S"), (8, "W")) if mask & bit]
        if mask not in (5, 10):
            rects.append(COLLISION["pillar"])
        collision[str(mask)] = [list(r) for r in rects]
    print(f"{style}.webp: 16 shapes x 4 parities, frame {frame_w}x{frame_h} px")
    return {
        "texture": f"res://asset/MAPS/walls/sets/{style}.webp",
        "frame": [frame_w, frame_h],
        "foot": [px(32 - fx), px(64 - fy)],
        "scale": 1.0 / DENSITY,
        "collision": collision,
    }


PALETTE = OUT_DIR / "palette.png"
TILESET = ROOT / "godot/game/world/walls/wall_tileset.tres"
TILE = 64
## The palette's columns: the shapes in a reading order (post; ends N, E, S, W; straights; corners;
## T junctions; cross). A tile's custom data holds the shape's mask, so the order is only looks.
SHAPE_ORDER = [0, 1, 2, 4, 8, 10, 5, 6, 12, 3, 9, 14, 11, 7, 13, 15]
## Rows per style under the auto row: the shapes (their pattern follows the cell), then each of the
## four pattern stretches exactly.
ROWS_PER_STYLE = 5
TILE_BG = (52, 60, 44)
AUTO_FRAME = (240, 230, 200)      # like the forest layer's mixes
FOLLOW_FRAME = (150, 176, 120)
EXACT_FRAME = (20, 20, 24)


def palette_tile(atlas: Image.Image, frame: list[int], shape: int, parity: int, outline: tuple,
                 mark: bool = True) -> Image.Image:
    """A 64 px palette tile: the whole frame of `shape` at `parity`, so the arms keep their sides."""
    fw, fh = frame
    piece = atlas.crop((shape * fw, parity * fh, (shape + 1) * fw, (parity + 1) * fh))
    scale = (TILE - 6) / max(fw, fh)
    piece = piece.resize((round(fw * scale), round(fh * scale)), Image.LANCZOS)
    tile = Image.new("RGBA", (TILE, TILE), TILE_BG + (255,))
    tile.alpha_composite(piece, ((TILE - piece.width) // 2, TILE - piece.height - 3))
    draw = ImageDraw.Draw(tile)
    draw.rectangle((0, 0, TILE - 1, TILE - 1), outline=outline + (255,), width=2)
    if mark:
        # the shape's arms as a small diagram in the corner: the pillar hides them on the piece
        x0, y0, size = 3, 3, 17
        draw.rectangle((x0, y0, x0 + size - 1, y0 + size - 1), fill=(20, 20, 24, 255))
        c = size // 2
        ends = {1: (c, 1), 2: (size - 2, c), 4: (c, size - 2), 8: (1, c)}
        for bit, (ex, ey) in ends.items():
            if shape & bit:
                draw.line((x0 + c, y0 + c, x0 + ex, y0 + ey), fill=(240, 230, 200, 255), width=3)
        draw.rectangle((x0 + c - 2, y0 + c - 2, x0 + c + 2, y0 + c + 2), fill=(240, 230, 200, 255))
    return tile


def write_palette(table: dict) -> None:
    """The WallLayer's palette and tile set. Row 0 holds a tile per style whose shape follows the
    painted neighbours (auto). Under it, five rows per style: the 16 shapes with the pattern
    following the cell (runs stay seamless), then the 16 shapes at each pattern stretch exactly.
    Custom data: `wall_style`, `wall_shape` (-1: from the neighbours), `wall_parity` (-1: from the
    cell). Styles keep their places: append new ones."""
    styles = [s for s in STYLES if s in table]
    rows = 1 + ROWS_PER_STYLE * len(styles)
    sheet = Image.new("RGBA", (TILE * len(SHAPE_ORDER), TILE * rows), (0, 0, 0, 0))
    tiles = []  # (column, row, style, shape, parity)
    for i, style in enumerate(styles):
        frame = table[style]["frame"]
        atlas = Image.open(OUT_DIR / f"{style}.webp").convert("RGBA")
        sheet.alpha_composite(palette_tile(atlas, frame, 15, 0, AUTO_FRAME, False), (i * TILE, 0))
        tiles.append((i, 0, style, -1, -1))
        base = 1 + ROWS_PER_STYLE * i
        for column, shape in enumerate(SHAPE_ORDER):
            sheet.alpha_composite(palette_tile(atlas, frame, shape, 0, FOLLOW_FRAME), (column * TILE, base * TILE))
            tiles.append((column, base, style, shape, -1))
            for parity in range(4):
                row = base + 1 + parity
                sheet.alpha_composite(palette_tile(atlas, frame, shape, parity, EXACT_FRAME), (column * TILE, row * TILE))
                tiles.append((column, row, style, shape, parity))
    sheet.save(PALETTE)
    uid = ""
    if TILESET.exists():
        found = re.search(r'\[gd_resource [^\]]*uid="([^"]+)"', TILESET.read_text(encoding="utf-8"))
        uid = found.group(1) if found else ""
    lines = [
        '[gd_resource type="TileSet" format=3%s]' % (f' uid="{uid}"' if uid else ""),
        "",
        '[ext_resource type="Texture2D" path="res://asset/MAPS/walls/sets/palette.png" id="1_palette"]',
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_walls"]',
        'texture = ExtResource("1_palette")',
        f"texture_region_size = Vector2i({TILE}, {TILE})",
    ]
    for column, row, style, shape, parity in tiles:
        key = f"{column}:{row}/0"
        lines += [f"{key} = 0", f'{key}/custom_data_0 = "{style}"', f"{key}/custom_data_1 = {shape}",
                  f"{key}/custom_data_2 = {parity}"]
    lines += [
        "",
        "[resource]",
        f"tile_size = Vector2i({CELL}, {CELL})",
        'custom_data_layer_0/name = "wall_style"',
        "custom_data_layer_0/type = 4",
        'custom_data_layer_1/name = "wall_shape"',
        "custom_data_layer_1/type = 2",
        'custom_data_layer_2/name = "wall_parity"',
        "custom_data_layer_2/type = 2",
        'sources/0 = SubResource("TileSetAtlasSource_walls")',
        "",
    ]
    TILESET.parent.mkdir(parents=True, exist_ok=True)
    TILESET.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    args = sys.argv[1:]
    table = json.loads(TABLE.read_text(encoding="utf-8")) if TABLE.exists() else {}
    if "--palette" not in args:
        for style in [a for a in args if not a.startswith("--")] or list(STYLES):
            table[style] = build(style, STYLES[style])
        TABLE.write_text(json.dumps(table, indent="\t") + "\n", encoding="utf-8")
    write_palette(table)


if __name__ == "__main__":
    main()
