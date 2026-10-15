"""Builds the cliff kits from the approved H plateau paintings (asset/Originals/elevation/cliff-concepts/):
each painting scaled to 128 px per 64-unit cell, one stone course to a cell, aligned to the cell
lines and colour-matched to h2, the ground outside the cliff made transparent. The elevation's
storybook art is cut from kit-h2 and kit-h3 (scripts/art/build-elevation-art-from-painting.py,
docs/godot/ELEVATION.md "Storybook art").

Usage: python scripts/art/build-cliff-kit.py [--preview DIR]

Outputs (derived; re-run the tool instead of editing them), in godot/asset/MAPS/cliffs/:
  kit-<name>.png    the scaled painting with the outside ground cut away
  kit-<name>.json   {"cells": [cols, rows], "columns": [a, b], "rows": [c, d], "labels": [...]}: the
                    straight middle (columns a..b-1, rows c..d-1) and every cell's label
Needs numpy and Pillow.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
CONCEPTS = ROOT / "asset/Originals/elevation/cliff-concepts"
OUT = ROOT / "godot/asset/MAPS/cliffs"
CELLS = 18                 # the 2048 px paintings become 18 x 18 cells
TILE = 128
SIZE = CELLS * TILE

# Per kit: the painting, its straight middle (in cells of the scaled painting), and a polygon (in
# painting px) a little outside the cliff: whatever lies beyond it is cut away.
def h_labels(wall_rows: int) -> list[str]:
    """Cell labels of the H plateau paintings (18 x 18 cells): T top, W the wall's top course, M a
    middle course, V its bottom course, F the foot, L low ground. Measured on h-plateau-a.png."""
    rows = []
    for y in range(18):
        row = ""
        for x in range(18):
            legs, notch = 2 <= x <= 6 or 11 <= x <= 15, 7 <= x <= 10
            if y < 2 or y > 16 or not (legs or notch):
                row += "L"
            elif notch and y <= 4:
                row += "L"
            elif notch and y <= 10:
                row += "T"
            elif notch:
                course = y - 11
                row += wall_label(course, wall_rows) if course < wall_rows else ("F" if course == wall_rows else "L")
            elif y <= 13:
                row += "T"
            else:
                course = y - 14
                row += wall_label(course, wall_rows) if course < wall_rows else ("F" if course == wall_rows else "L")
        rows.append(row)
    return rows


def h23_labels(leg_walls: int, notch_walls: int) -> list[str]:
    """Labels of the 1- and 3-level H paintings scaled to 23 x 23 cells (one stone course a cell),
    measured on them: legs at columns 3-8 and 14-19, the notches at 9-13; the right leg's wall
    reaches column 20, so the rows above it do too."""
    top = {}
    for y in range(3, 18):
        if y <= 5:
            top[y] = [(3, 8), (14, 19)]
        elif y >= 16:
            top[y] = [(3, 8), (14, 20)]
        elif y >= 14:
            top[y] = [(3, 8), (14, 19)]
        else:
            top[y] = [(3, 19)]
    return labels_from_top(top, leg_walls, 23, {x: notch_walls for x in range(9, 14)})


def labels_from_top(top: dict, wall_rows: int, cells: int = 18, column_walls: dict | None = None) -> list[str]:
    """Cell labels from the rows of a painting's raised top ({row: (first column, last column)}):
    under every column's lowest top cell the wall's courses, then the foot."""
    grid = [["L"] * cells for _ in range(cells)]
    for y, spans in top.items():
        for a, b in (spans if isinstance(spans, list) else [spans]):
            for x in range(a, b + 1):
                grid[y][x] = "T"
    for x in range(cells):
        rows = (column_walls or {}).get(x, wall_rows)
        for y in range(cells - 1, -1, -1):
            if grid[y][x] == "T":
                for k in range(rows + 1):
                    if y + 1 + k < cells and grid[y + 1 + k][x] == "L":
                        grid[y + 1 + k][x] = "F" if k == rows else wall_label(k, rows)
                break
    return ["".join(row) for row in grid]


def wall_label(course: int, count: int) -> str:
    return "W" if course == 0 else ("V" if course == count - 1 else "M")


KITS = {
    "h2": {
        # Stretched, an H is a rectangle: its left leg, the leg's middle repeated, its right leg.
        "file": "h-plateau-a.png", "columns": [6, 8], "rows": [9, 17], "tails": [15, 17], "labels": h_labels(2),
        "align": {"course": 95, "stone_top": 1640, "wall_left": 182},
        "top": [(230, 230), (820, 230), (820, 560), (1220, 560), (1220, 230), (1850, 230), (1850, 1640), (1210, 1640),
                          (1210, 1270), (830, 1270), (830, 1640), (230, 1640)],
        "courses": 2, "notch": [830, 1210, 2],
        "hull": [(120, 120), (1930, 120), (1930, 1960), (120, 1960)],
    },
    "h3": {
        # Its notch's back wall came out two courses high: labelled as painted.
        "file": "h-plateau-level3.png", "cells": 23, "columns": [6, 8], "rows": [9, 17], "tails": [15, 17], "labels": h23_labels(3, 2),
        "align": {"course": 95, "stone_top": 1620, "wall_left": 179},
        "top": [(230, 230), (820, 230), (820, 560), (1220, 560), (1220, 230), (1850, 230), (1850, 1620), (1210, 1620),
                          (1210, 1260), (830, 1260), (830, 1620), (230, 1620)],
        "courses": 3, "notch": [830, 1210, 2],
        "hull": [(120, 120), (1930, 120), (1930, 1960), (120, 1960)],
    },
}


def flat_light(rgb: np.ndarray) -> np.ndarray:
    """The image with its slow light changes removed (fine texture around the image mean)."""
    out = np.empty_like(rgb)
    for ch in range(3):
        img = Image.fromarray(np.clip(rgb[..., ch] * 255 + 0.5, 0, 255).astype(np.uint8), "L")
        slow = np.asarray(img.filter(ImageFilter.GaussianBlur(40)), dtype=np.float64) / 255.0
        out[..., ch] = rgb[..., ch] - slow + rgb[..., ch].mean()
    return out


def cut_outside(rgb: np.ndarray, hull: list[tuple[float, float]], scale: float) -> np.ndarray:
    """Alpha: 0 for the plain ground connected to the picture's border and for everything outside
    the hull, 1 elsewhere (the cliff, its border tufts, the ground inside), softly edged."""
    flat = flat_light(rgb)
    ring = np.zeros(rgb.shape[:2], bool)
    ring[:40], ring[-40:], ring[:, :40], ring[:, -40:] = True, True, True, True
    mean, std = flat[ring].mean(0), flat[ring].std(0)
    dev = (np.abs(flat - mean) / np.maximum(std, 1e-3)).max(axis=-1)
    # Deviation averaged over a few px: single blades and specks are not art, tufts and stones are.
    dev_img = Image.fromarray(np.clip(dev * 40, 0, 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(4))
    dev = np.asarray(dev_img, dtype=np.float64) / 40.0
    grass = Image.fromarray(np.where(dev < 1.9, 255, 0).astype(np.uint8), "L")
    grass = grass.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))   # close gaps between blades
    h, w = rgb.shape[:2]
    for x in range(0, w, 64):
        for y in (0, h - 1):
            if grass.getpixel((x, y)) == 255:
                ImageDraw.floodfill(grass, (x, y), 128)
    for y in range(0, h, 64):
        for x in (0, w - 1):
            if grass.getpixel((x, y)) == 255:
                ImageDraw.floodfill(grass, (x, y), 128)
    outside = np.asarray(grass) == 128
    hull_mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(hull_mask).polygon([(x * scale, y * scale) for x, y in hull], fill=255)
    keep = (~outside) & (np.asarray(hull_mask) > 0)
    alpha = Image.fromarray(np.where(keep, 255, 0).astype(np.uint8), "L")
    # Opening: drops the specks left outside, keeps the border tufts.
    alpha = alpha.filter(ImageFilter.MinFilter(7)).filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(1.5))
    return np.asarray(alpha, dtype=np.float64) / 255.0


def aligned(src: Image.Image, align: dict) -> tuple[np.ndarray, float, float, float, int]:
    """The painting scaled so one stone course (`course` px) is one cell, shifted so the wall's top
    (`stone_top`) and its left end (`wall_left`) fall on cell lines. Returns rgb, the scale and the
    shift (output px = source px * scale + shift) and the size in cells."""
    s = TILE / align["course"]
    def shift(v: float) -> float:
        return (np.ceil(v * s / TILE) + 1) * TILE - v * s
    tx, ty = shift(align["wall_left"]), shift(align["stone_top"])
    cells = int(np.ceil((src.width * s + max(tx, ty)) / TILE))
    size = cells * TILE
    out = src.transform((size, size), Image.AFFINE, (1 / s, 0, -tx / s, 0, 1 / s, -ty / s), resample=Image.BICUBIC,
                        fillcolor=tuple(int(c) for c in np.asarray(src)[5, 5]))
    return np.asarray(out, dtype=np.float64) / 255.0, s, tx, ty, cells


def geo_labels(kit: dict, scale: float, tx: float, ty: float, cells: int) -> list[str]:
    """Labels from the measured outline: a cell is top where the top's polygon covers most of it;
    under the last top cell of every column hang the wall's courses (the notch's columns their own
    number), then the foot: the cliff shape node's own rule, so painting and builder agree."""
    sub = 8
    mask = Image.new("L", (cells * sub, cells * sub), 0)
    to_cells = lambda x, y: ((x * scale + tx) / TILE * sub, (y * scale + ty) / TILE * sub)
    ImageDraw.Draw(mask).polygon([to_cells(x, y) for x, y in kit["top"]], fill=255)
    cover = np.asarray(mask, dtype=np.float64).reshape(cells, sub, cells, sub).mean(axis=(1, 3)) / 255.0
    top = {}
    for y in range(cells):
        spans = []
        for x in range(cells):
            if cover[y, x] > 0.5:
                spans.append((x, x))
        if spans:
            top[y] = spans
    walls = {}
    if "notch" in kit:
        a, b, n = kit["notch"]
        for x in range(cells):
            centre = ((x + 0.5) * TILE - tx) / scale
            if a <= centre <= b:
                walls[x] = n
    return labels_from_top(top, kit["courses"], cells, walls)


def auto_labels(rgb: np.ndarray, alpha: np.ndarray, cells: int) -> list[str]:
    """Labels read from the aligned picture: a cell is wall where most of it is stone (its run of
    wall cells in a column gives W, M..., V), the cell under a wall's last course its foot, a cell
    above a column's first wall (or in a column without one) top where the cut keeps most of it."""
    hsv = np.asarray(Image.fromarray(np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8), "RGB").convert("HSV"),
                     dtype=np.float64) / 255.0
    stone = (hsv[..., 1] < 0.72) & (hsv[..., 2] > 0.33) & ((hsv[..., 0] < 0.17) | (hsv[..., 0] > 0.9))
    frac = stone.reshape(cells, TILE, cells, TILE).mean(axis=(1, 3))
    cover = alpha.reshape(cells, TILE, cells, TILE).mean(axis=(1, 3))
    grid = [["L"] * cells for _ in range(cells)]
    for x in range(cells):
        walls = [y for y in range(cells) if frac[y, x] > 0.42]
        runs = []
        for y in walls:
            if runs and runs[-1][-1] == y - 1:
                runs[-1].append(y)
            else:
                runs.append([y])
        runs = [r for r in runs if cover[r[0], x] > 0.5]
        first = runs[0][0] if runs else cells
        for y in range(first):
            if cover[y, x] > 0.55:
                grid[y][x] = "T"
        for r in runs:
            for i, y in enumerate(r):
                grid[y][x] = "W" if i == 0 else ("V" if i == len(r) - 1 else "M")
            if r[-1] + 1 < cells:
                grid[r[-1] + 1][x] = "F"
    return ["".join(row) for row in grid]


def match_colours(rgb: np.ndarray, labels: list[str], ref: dict | None) -> tuple[np.ndarray, dict]:
    """Moves the picture's top grass and stone colours onto the reference kit's (per channel mean and
    spread), each weighted by how stone-like a pixel is. Returns the picture and its own statistics."""
    cells = len(labels)
    cellmask = lambda keys: np.kron(np.array([[ch in keys for ch in row] for row in labels], float), np.ones((TILE, TILE))) > 0.5
    hsv = np.asarray(Image.fromarray(np.clip(rgb * 255 + 0.5, 0, 255).astype(np.uint8), "RGB").convert("HSV"),
                     dtype=np.float64) / 255.0
    stoneness = np.clip((0.75 - hsv[..., 1]) / 0.25, 0, 1)
    top = cellmask("T") & (stoneness < 0.2)
    wall = cellmask("WMV") & (stoneness > 0.8)
    stats = {"top": (rgb[top].mean(0), rgb[top].std(0)), "stone": (rgb[wall].mean(0), rgb[wall].std(0))}
    if ref is None:
        return rgb, stats
    def moved(key: str) -> np.ndarray:
        (m, sd), (rm, rsd) = stats[key], ref[key]
        return (rgb - m) / np.maximum(sd, 1e-3) * rsd + rm
    w = stoneness[..., None]
    return np.clip(moved("top") * (1 - w) + moved("stone") * w, 0, 1), stats


def drop_busy_interior(rgb: np.ndarray, labels: list[str]) -> list[str]:
    """Interior top cells (top all around) whose picture is not plain grass (a notch's ferns or an
    earth seam the outline missed) become 'X', which no shape matches, so they are never used."""
    cells = len(labels)
    grid = [list(r) for r in labels]
    interior = [(x, y) for y in range(1, cells - 1) for x in range(1, cells - 1)
                if all(labels[y + dy][x + dx] == "T" for dy in (-1, 0, 1) for dx in (-1, 0, 1))]
    if not interior:
        return labels
    tiles = {c: rgb[c[1] * TILE:(c[1] + 1) * TILE, c[0] * TILE:(c[0] + 1) * TILE] for c in interior}
    grass = np.median(np.concatenate([t.reshape(-1, 3) for t in tiles.values()]), axis=0)
    for (x, y), t in tiles.items():
        off = np.abs(t - grass).max(axis=-1) > 0.22
        if off.mean() > 0.06:
            grid[y][x] = "X"
    return ["".join(r) for r in grid]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preview", type=Path, help="also write each kit over a magenta backdrop here")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    ref = None
    for name in sorted(KITS, key=lambda n: n != "h2"):   # h2 first: the colour reference
        kit = KITS[name]
        src = Image.open(CONCEPTS / kit["file"]).convert("RGB")
        rgb, scale, tx, ty, cells = aligned(src, kit["align"])
        size = cells * TILE
        # The cut is made on the painting itself (its border is its own ground) and moved along.
        src_alpha = cut_outside(np.asarray(src, dtype=np.float64) / 255.0, kit["hull"], 1.0)
        moved = Image.fromarray(np.clip(src_alpha * 255 + 0.5, 0, 255).astype(np.uint8), "L").transform(
            (size, size), Image.AFFINE, (1 / scale, 0, -tx / scale, 0, 1 / scale, -ty / scale),
            resample=Image.BILINEAR, fillcolor=0)
        alpha = np.asarray(moved, dtype=np.float64) / 255.0
        kit = dict(kit, labels=geo_labels(kit, scale, tx, ty, cells))
        rgb, stats = match_colours(rgb, kit["labels"], ref)
        kit["labels"] = drop_busy_interior(rgb, kit["labels"])
        if ref is None:
            ref = stats
        rgba = np.concatenate([rgb, alpha[..., None]], axis=-1)
        Image.fromarray(np.clip(rgba * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(OUT / f"kit-{name}.png", optimize=True)
        data = {"cells": [cells, cells], "columns": kit["columns"], "rows": kit["rows"]}
        if "tails" in kit:
            data["tails"] = kit["tails"]
        if "labels" in kit:
            data["labels"] = kit["labels"]
        (OUT / f"kit-{name}.json").write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
        if args.preview:
            args.preview.mkdir(parents=True, exist_ok=True)
            bg = Image.new("RGBA", (size, size), (255, 0, 255, 255))
            bg.alpha_composite(Image.open(OUT / f"kit-{name}.png"))
            bg.resize((size // 3, size // 3)).save(args.preview / f"kit-{name}-preview.png")
        print(f"kit-{name}: {cells} x {cells} cells, middle columns {kit['columns']}, rows {kit['rows']}")


if __name__ == "__main__":
    main()
