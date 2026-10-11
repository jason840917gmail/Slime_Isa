"""Cuts the hand-paintable cliff sheet (docs/godot/CLIFFS.md) out of the approved concept paintings:
an octagonal plateau and an octagonal dip (asset/Originals/elevation/cliff-concepts/, Magnific
GPT 2.5, approved by the owner on 2026-10-09). Every tile is one 64-unit cell at 128 px; both
ground levels (the raised top and the low ground) come from the paintings.

Usage: python scripts/art/build-cliff-tiles.py [--preview DIR]

How the cut works: each side of a concept is laid onto the cell grid as a "run" (a strip of cells
rendered from the painting, scaled so one stone course is one cell), the 45 degree sides by an
oblique mapping that puts the painted line exactly on the cell diagonal (walls by a vertical shear,
so stones stay upright). Cells of a run are tiles; runs from both concepts give variants. Every
tile's sides are blended to the shared joins: the canonical top or low ground on a ground side,
the run's own wrap seam on a side the border or wall crosses, so any variant fits any neighbour.

Outputs (derived; re-run the tool instead of editing them):
  godot/asset/MAPS/cliffs/meadow-rock-highland.png   the sheet (8 columns, blocks below)
  godot/asset/MAPS/cliffs/meadow-rock-highland.json  each tile's cell, label, terrain neighbours
      and weight (godot/tools/build_cliff_lab.gd writes the TileSet from it)
  docs/godot/cliffs-sheet-guide.png                  the sheet with every tile labelled
Needs numpy and Pillow.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
CONCEPTS = ROOT / "asset/Originals/elevation/cliff-concepts"
OUT = ROOT / "godot/asset/MAPS/cliffs"
GUIDE = ROOT / "docs/godot/cliffs-sheet-guide.png"
NAME = "meadow-rock-highland"

_spec = importlib.util.spec_from_file_location("edges", ROOT / "scripts/art/build-terrain-edge-tiles.py")
E = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(E)

TILE = 128
COLUMNS = 8
BLEND = 18                 # px over which a tile's side is blended to its join
INSET = 52                 # px from a border tile's open side to the painted earth line
TOP, WALL, FOOT, CAP, LOW, NONE = 0, 1, 2, 3, 4, -1
SIDES = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


# ---------------------------------------------------------------- the concepts
#
# Measured on the 2048 px paintings. `cs` is the source size of one cell: one stone course.
# A straight run is (x, y) of its first cell and its length in cells; a 45 degree run is the
# painted line's two ends (earth line of a top's border, or a wall's top edge).

PLATEAU = {
    "file": "octagon-plateau-b.png", "cs": 110,
    # North side: T cells (border near the top of the cell), the low ground above, the top below.
    "T": [((650, 180), 6)],
    "L": [((143, 600), 5)],          # west side: L cells (border near the left of the cell)
    "R": [((1797, 600), 5)],         # east side: R cells
    "wall": ((580, 1442), 8),        # row above the wall, then top course, bottom course, foot
    "chamfer_NW": ((190, 600), (560, 230)),    # earth line, lower-left end then upper-right end
    "chamfer_NE": ((1440, 225), (1830, 590)),  # upper-left end then lower-right end
    "wall_SW": ((190, 1210), (570, 1550)),     # wall top edge, upper-left end then lower-right end
    "wall_SE": ((1500, 1460), (1860, 1180)),   # lower-left end then upper-right end
    "top_ground": [(800, 500), (1000, 640), (1200, 800), (700, 900), (1100, 1050), (900, 1200)],
    "low_ground": [(40, 1500), (1900, 1500), (60, 300), (1880, 60), (200, 1900), (1700, 1920)],
}
DIP = {
    "file": "octagon-dip-a.png", "cs": 125,
    "T": [((570, 1738), 6)],         # near (south) rim: the upper ground south of the pit
    "L": [((1789, 760), 4)],         # east rim: upper ground east of the pit, border on its west
    "R": [((155, 760), 4)],          # west rim
    "wall": ((650, 125), 6),         # far (north) wall: row above, top course, bottom, foot
    "chamfer_NW": ((1520, 1720), (1880, 1340)),   # near SE rim: border facing north-west
    "chamfer_NE": ((140, 1340), (520, 1720)),     # near SW rim: border facing north-east
    "wall_SW": ((1420, 250), (1800, 640)),        # far NE inner wall, facing south-west
    "wall_SE": ((260, 640), (640, 250)),          # far NW inner wall, facing south-east
    "top_ground": [(60, 60), (1800, 80), (60, 1900), (1850, 1880), (900, 1900)],
    "low_ground": [(800, 900), (1000, 1100), (700, 1300), (1200, 1250), (950, 800), (600, 1050)],
}


def load(concept: dict) -> np.ndarray:
    """The painting as premultiplied RGBA, made opaque (the generator left alpha near 0.95)."""
    a = np.asarray(Image.open(CONCEPTS / concept["file"]).convert("RGBA"), dtype=np.float64) / 255.0
    a[..., 3] = 1.0
    return a


def sample(src: np.ndarray, xs: np.ndarray, ys: np.ndarray) -> np.ndarray:
    """Bilinear samples of `src` at float pixel coordinates (clamped to the image)."""
    h, w = src.shape[:2]
    xs = np.clip(xs, 0, w - 1.001)
    ys = np.clip(ys, 0, h - 1.001)
    x0, y0 = np.floor(xs).astype(int), np.floor(ys).astype(int)
    fx, fy = (xs - x0)[..., None], (ys - y0)[..., None]
    return (src[y0, x0] * (1 - fx) * (1 - fy) + src[y0, x0 + 1] * fx * (1 - fy)
            + src[y0 + 1, x0] * (1 - fx) * fy + src[y0 + 1, x0 + 1] * fx * fy)


def grid(cols: int, rows: int) -> tuple[np.ndarray, np.ndarray]:
    y, x = np.mgrid[0:rows * TILE, 0:cols * TILE].astype(np.float64)
    return x + 0.5, y + 0.5


def straight_run(src: np.ndarray, cs: float, origin: tuple[float, float], cols: int, rows: int) -> np.ndarray:
    """`cols` x `rows` cells of the painting from `origin`, one cell = `cs` source px."""
    x, y = grid(cols, rows)
    s = cs / TILE
    return sample(src, origin[0] + x * s, origin[1] + y * s)


def cells(run: np.ndarray) -> list[list[np.ndarray]]:
    rows, cols = run.shape[0] // TILE, run.shape[1] // TILE
    return [[run[r * TILE:(r + 1) * TILE, c * TILE:(c + 1) * TILE].copy() for c in range(cols)] for r in range(rows)]


def chamfer_run(src: np.ndarray, cs: float, a: tuple, b: tuple, n: int, covered_below: bool) -> list[np.ndarray]:
    """`n` north-west chamfer cells (border on the line x + y = TILE + INSET in each cell, the top
    below-right of it) and the n-1 notches between them, from the painted line a -> b. The painted
    line runs up-right from a to b; `covered_below` says the top lies below-right of it in the
    painting too (for the north-east chamfer the caller mirrors)."""
    W = (n + 1) * TILE
    x, y = grid(n + 1, n + 1)
    c = n * TILE + INSET                       # the target line x + y = c
    t = (x - y) / np.sqrt(2)                   # along the line (up-right)
    d = (x + y - c) / np.sqrt(2)               # past the line, into the top
    a, b = np.array(a, float), np.array(b, float)
    u = (b - a) / np.linalg.norm(b - a)        # source direction along the line
    nrm = np.array([u[1], -u[0]]) if covered_below else np.array([-u[1], u[0]])
    if nrm[1] < 0:                             # into the top: down-right in the painting
        nrm = -nrm
    s = cs / TILE
    mid = (a + b) / 2
    xs = mid[0] + (t * u[0] + d * nrm[0]) * s
    ys = mid[1] + (t * u[1] + d * nrm[1]) * s
    run = sample(src, xs, ys)
    grid_cells = cells(run)
    chamfers = [grid_cells[n - 1 - k][k] for k in range(n)]
    notches = [grid_cells[n - k][k] for k in range(1, n)]
    return chamfers, notches


def wall_run(src: np.ndarray, cs: float, a: tuple, b: tuple, n: int, face: str) -> dict[str, list[np.ndarray]]:
    """A 45 degree wall `n` cells long, two levels high, from the painted top edge a -> b, by a
    vertical shear (each target column takes a source column; heights below the top edge scale
    by one course per cell). SW face: the top edge goes down to the right (cells on the line
    y = x); SE face: up to the right."""
    rows = n + 3
    x, y = grid(n, rows + 1)
    x = x
    y = y - TILE                               # one row of top ground above the first cell
    if face == "SW":
        edge = x                               # target top edge: y = x
    else:
        edge = n * TILE - x                    # y = n*TILE - x
    a, b = np.array(a, float), np.array(b, float)
    fx = x / (n * TILE)                        # 0..1 along the run, left to right
    xs = a[0] + (b[0] - a[0]) * fx
    ys_edge = a[1] + (b[1] - a[1]) * fx
    ys = ys_edge + (y - edge) * (cs / TILE)
    run = cells(sample(src, xs, ys))
    # The rim above the top edge and the plants below the bottom edge are wider than the line:
    # their tips reach one neighbour of each step (`rim`: the top's cell beside the step, `spill`:
    # the low cell beside the foot), cut from the same run so they join.
    if face == "SW":
        over = [run[c + 1][c] for c in range(n)]          # cell holding the top edge
        middle = [run[c + 2][c] for c in range(n)]
        foot = [run[c + 3][c] for c in range(n)]
        rim = [run[c + 1][c + 1] for c in range(n - 1)]
        spill = [run[c + 3][c - 1] for c in range(1, n)]
    else:
        over = [run[n - c][c] for c in range(n)]
        middle = [run[n - c + 1][c] for c in range(n)]
        foot = [run[n - c + 2][c] for c in range(n)]
        rim = [run[n - c][c - 1] for c in range(1, n)]
        spill = [run[n - c + 2][c + 1] for c in range(n - 1)]
    return {"over": over, "middle": middle, "foot": foot, "rim": rim, "spill": spill}


# ---------------------------------------------------------------- joins

def ramp(side: str) -> np.ndarray:
    r = 1.0 - E.smoothstep(np.arange(TILE, dtype=np.float64) / BLEND)
    return {"top": r[:, None, None], "bottom": r[::-1][:, None, None],
            "left": r[None, :, None], "right": r[None, ::-1, None]}[side]


def blend(tile: np.ndarray, side: str, ref: np.ndarray) -> np.ndarray:
    """`tile`'s `side` blended to what `ref` shows at the same side."""
    w = ramp(side)
    return tile * (1 - w) + ref * w


def wrap_seam(tiles: list[np.ndarray], axis: int) -> list[np.ndarray]:
    """Variants that join in any order along `axis` (1: left-right, 0: top-bottom): every tile's
    two ends are blended to the first tile made periodic (its own ends then match)."""
    base = E.periodic(tiles[0], axis, 24)
    out = []
    for t in tiles:
        a, b = ("left", "right") if axis == 1 else ("top", "bottom")
        out.append(blend(blend(t, a, base), b, base))
    return out


def flatten(tile: np.ndarray, mean: np.ndarray) -> np.ndarray:
    """The tile with its slow light changes removed (the painting's glow and shade): its fine
    texture kept around `mean`, so tiles cut from different places match."""
    out = tile.copy()
    for ch in range(3):
        img = Image.fromarray(np.clip(np.pad(tile[..., ch], 32, mode="reflect") * 255 + 0.5, 0, 255).astype(np.uint8), "L")
        blur = np.asarray(img.filter(ImageFilter.GaussianBlur(18)), dtype=np.float64)[32:-32, 32:-32] / 255.0
        out[..., ch] = np.clip(tile[..., ch] - blur + mean[ch], 0, 1)
    return out


def ground_set(raw: list[np.ndarray], mean: np.ndarray) -> list[np.ndarray]:
    """Ground tiles at one light level that all share the first one's (periodic) borders."""
    flat = [flatten(t, mean) for t in raw]
    canon = E.periodic(E.periodic(flat[0], 0, 24), 1, 24)
    out = [canon]
    for t in flat[1:]:
        for side in ("top", "bottom", "left", "right"):
            t = blend(t, side, canon)
        out.append(t)
    return out


def tone(tiles: list[np.ndarray], target: np.ndarray) -> list[np.ndarray]:
    """Moves tiles' colour statistics onto `target`'s (one concept's ground onto the other's)."""
    tm, ts = target[..., :3].reshape(-1, 3).mean(0), target[..., :3].reshape(-1, 3).std(0)
    out = []
    for t in tiles:
        flat = t[..., :3].reshape(-1, 3)
        m, s = flat.mean(0), np.maximum(flat.std(0), 1e-6)
        u = t.copy()
        u[..., :3] = np.clip((t[..., :3] - m) / s * ts + tm, 0, 1)
        out.append(u)
    return out


# ---------------------------------------------------------------- terrain neighbours
#
# Five terrains: TOP (the raised ground), LOW (the low ground, painted with the sheet's low
# tiles), CAP (a wall's top row), WALL (the rows below it) and FOOT. A side shared by two
# terrains is given by Godot's painting to one of them, depending on the paint order, so tiles
# carry alternatives for both answers; a cell next to ground nobody painted reads NONE, so
# every LOW neighbour also has a NONE alternative.

def variants(p: dict) -> list[dict]:
    """`p` and its copies with each LOW replaced by NONE (unpainted low ground)."""
    out = [p]
    q = {k: (NONE if v == LOW else v) for k, v in p.items()}
    if q != p:
        out.append(q)
    return out


def top_peering(n: int, e: int, s: int, w: int, ne: int = None, se: int = None, sw: int = None, nw: int = None) -> dict:
    side = lambda v: TOP if v == TOP else LOW
    corner = lambda a, b, v: (TOP if a == TOP and b == TOP else LOW) if v is None else v
    return {"N": side(n), "E": side(e), "S": side(s), "W": side(w), "NE": corner(n, e, ne), "SE": corner(s, e, se),
            "SW": corner(s, w, sw), "NW": corner(n, w, nw)}


def row_peering(own: int, n: int, s: int, east: bool, west: bool) -> dict:
    side = lambda present: own if present else LOW
    return {"N": n, "S": s, "E": side(east), "W": side(west),
            "NE": n if east else LOW, "NW": n if west else LOW, "SE": s if east else LOW, "SW": s if west else LOW}


# ---------------------------------------------------------------- main

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preview", type=Path, help="also write the sheet over a backdrop into this folder")
    args = parser.parse_args()

    concepts = [(c, load(c)) for c in (PLATEAU, DIP)]

    # Grounds: plain cells of both paintings, their light flattened to one level per ground (the
    # plateau's top and low ground), all sharing the first cell's borders.
    raw_top = [straight_run(src, c["cs"], xy, 1, 1) for c, src in concepts for xy in c["top_ground"]]
    raw_low = [straight_run(src, c["cs"], xy, 1, 1) for c, src in concepts for xy in c["low_ground"]]
    top_mean = np.mean([t[..., :3].reshape(-1, 3).mean(0) for t in raw_top[:len(PLATEAU["top_ground"])]], axis=0)
    low_mean = np.mean([t[..., :3].reshape(-1, 3).mean(0) for t in raw_low[:len(PLATEAU["low_ground"])]], axis=0)
    top_tiles = ground_set(raw_top, top_mean)
    low_tiles = ground_set(raw_low, low_mean)
    T0, L0 = top_tiles[0], low_tiles[0]
    stats = {"top": (top_mean, np.concatenate([t[..., :3].reshape(-1, 3) for t in top_tiles]).std(0)),
             "low": (low_mean, np.concatenate([t[..., :3].reshape(-1, 3) for t in low_tiles]).std(0))}

    def reground(tile: np.ndarray, high: np.ndarray) -> np.ndarray:
        """The tile's plain grass replaced by the shared top (where `high` is 1) or low ground:
        only the painted details (ferns, earth, stones, flowers, roots) are kept from the painting."""
        rgb = tile[..., :3]
        dev = np.full(rgb.shape[:2], np.inf)
        for mean, std in stats.values():
            dev = np.minimum(dev, (np.abs(rgb - mean) / np.maximum(std, 1e-3)).max(axis=-1))
        detail = E.smoothstep((dev - 2.2) / 1.2)
        m = Image.fromarray((detail * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(2))
        detail = (np.asarray(m, dtype=np.float64) / 255.0)[..., None]
        ground = T0 * high[..., None] + L0 * (1 - high[..., None])
        # Grass pixels the detail mask keeps near details (tuft tips, the shade inside a rim) are
        # brought to the ground's light; stone, earth and flowers keep their own colour.
        green = rgb[..., 1:2] > np.maximum(rgb[..., 0:1], rgb[..., 2:3]) * 1.05
        level = T0[..., :3].reshape(-1, 3).mean(0) * high[..., None] + L0[..., :3].reshape(-1, 3).mean(0) * (1 - high[..., None])
        own = rgb.reshape(-1, 3)[green.reshape(-1)].mean(0) if green.any() else level.mean((0, 1))
        lit = tile.copy()
        lit[..., :3] = np.where(green, np.clip(rgb * (level / np.maximum(own, 1e-3)), 0, 1), rgb)
        return lit * detail + ground * (1 - detail)

    # Straight sides: T (border near the cell's top), L (near its left), R (near its right).
    sides: dict[str, list[np.ndarray]] = {"T": [], "L": [], "R": []}
    for c, src in concepts:
        for side in ("T", "L", "R"):
            for xy, n in c[side]:
                if side == "T":
                    sides[side] += cells(straight_run(src, c["cs"], xy, n, 1))[0]
                else:
                    sides[side] += [row[0] for row in cells(straight_run(src, c["cs"], xy, 1, n))]
    sides["T"] = [blend(blend(t, "top", L0), "bottom", T0) for t in wrap_seam(sides["T"], 1)]
    sides["L"] = [blend(blend(t, "left", L0), "right", T0) for t in wrap_seam(sides["L"], 0)]
    sides["R"] = [blend(blend(t, "right", L0), "left", T0) for t in wrap_seam(sides["R"], 0)]

    # 45 degree tops (chamfers) and the notches between their steps.
    chamfer = {"NW": [], "NE": []}
    notch = {"NW": [], "NE": []}
    for c, src in concepts:
        ch, no = chamfer_run(src, c["cs"], *c["chamfer_NW"], 3, True)
        chamfer["NW"] += ch
        notch["NW"] += no
        # North-east: mirror the painting, map as a north-west, mirror back.
        flipped = src[:, ::-1]
        w = src.shape[1]
        (ax, ay), (bx, by) = c["chamfer_NE"]
        ch, no = chamfer_run(flipped, c["cs"], (w - 1 - bx, by), (w - 1 - ax, ay), 3, True)
        chamfer["NE"] += [np.flip(t, 1) for t in ch]
        notch["NE"] += [np.flip(t, 1) for t in no]
    t_seam, l_seam, r_seam = sides["T"][0], sides["L"][0], sides["R"][0]
    for k, t in enumerate(chamfer["NW"]):
        t = blend(blend(t, "top", L0), "left", L0)
        chamfer["NW"][k] = blend(blend(t, "right", np.flip(t_seam, 1)), "bottom", np.flip(l_seam, 0))
    for k, t in enumerate(chamfer["NE"]):
        t = blend(blend(t, "top", L0), "right", L0)
        chamfer["NE"][k] = blend(blend(t, "left", np.flip(t_seam, 1)), "bottom", np.flip(r_seam, 0))
    for k, t in enumerate(notch["NW"]):
        t = blend(blend(t, "right", T0), "bottom", T0)
        notch["NW"][k] = blend(blend(t, "top", np.flip(l_seam, 0)), "left", np.flip(t_seam, 1))
    for k, t in enumerate(notch["NE"]):
        t = blend(blend(t, "left", T0), "bottom", T0)
        notch["NE"][k] = blend(blend(t, "top", np.flip(r_seam, 0)), "right", np.flip(t_seam, 1))

    # The straight wall: the top's row over it, the top course (lip), the bottom course, the foot.
    wall_rows = {"over": [], "cap": [], "bottom": [], "foot": []}
    for c, src in concepts:
        xy, n = c["wall"]
        rows = cells(straight_run(src, c["cs"], xy, n, 4))
        for key, row in zip(wall_rows, rows):
            wall_rows[key] += row
    for key in wall_rows:
        wall_rows[key] = wrap_seam(wall_rows[key], 1)
    wall_rows["over"] = [blend(t, "top", T0) for t in wall_rows["over"]]
    wall_rows["foot"] = [blend(t, "bottom", L0) for t in wall_rows["foot"]]

    # 45 degree walls.
    diag = {face: {"over": [], "middle": [], "foot": [], "rim": [], "spill": []} for face in ("SW", "SE")}
    for c, src in concepts:
        for face in ("SW", "SE"):
            run = wall_run(src, c["cs"], *c[f"wall_{face}"], 3, face)
            for key in run:
                diag[face][key] += run[key]

    yy, xx = np.mgrid[0:TILE, 0:TILE].astype(np.float64) + 0.5
    soft = lambda v: E.smoothstep(v / 12.0 + 0.5)
    high = {
        "T": soft(yy - INSET), "L": soft(xx - INSET), "R": soft(TILE - INSET - xx),
        "45 NW": soft(xx + yy - TILE - INSET), "45 NE": soft((TILE - xx) + yy - TILE - INSET),
        "notch NW": soft(xx + yy - INSET), "notch NE": soft((TILE - xx) + yy - INSET),
        "top": np.ones((TILE, TILE)), "low": np.zeros((TILE, TILE)),
        "SW over": soft(xx - yy), "SE over": soft((TILE - xx) - yy),
    }
    sides = {k: [reground(t, high[k]) for t in v] for k, v in sides.items()}
    chamfer = {k: [reground(t, high[f"45 {k}"]) for t in v] for k, v in chamfer.items()}
    notch = {k: [reground(t, high[f"notch {k}"]) for t in v] for k, v in notch.items()}
    wall_rows = {k: [reground(t, high["top" if k in ("over", "cap") else "low"]) for t in v] for k, v in wall_rows.items()}
    for face in ("SW", "SE"):
        for key in diag[face]:
            h_mask = high[f"{face} over"] if key == "over" else high["top" if key == "rim" else "low"]
            diag[face][key] = [reground(t, h_mask) for t in diag[face][key]]

    # ---- the sheet
    sheet: dict[tuple[int, int], np.ndarray] = {}
    tiles: list[dict] = []
    labels: dict[tuple[int, int], str] = {}

    def put(col: int, row: int, image: np.ndarray, label: str, kind: str, peers: list[dict], probability: float = 1.0,
            solid: bool = False, shapes: list | None = None) -> None:
        sheet[(col, row)] = image[..., :4]
        labels[(col, row)] = label
        alts = []
        for p in peers:
            for v in variants(p):
                if v not in alts:
                    alts.append(v)
        entry = {"atlas": [col, row], "label": label, "kind": kind, "peering": alts[0], "probability": probability,
                 "solid": solid}
        if len(alts) > 1:
            entry["alternatives"] = alts[1:]
        if shapes is not None:
            entry["shapes"] = shapes
        tiles.append(entry)

    Tn, Lw = TOP, LOW
    full_top = top_peering(TOP, TOP, TOP, TOP)
    full_low = {k: LOW for k in SIDES}
    # Row 0: the three straight sides (first variants), the 45 degree tops and their notches.
    put(0, 0, sides["T"][0], "T", "top", [top_peering(Lw, Tn, Tn, Tn)])
    put(1, 0, sides["L"][0], "L", "top", [top_peering(Tn, Tn, Tn, Lw)])
    put(2, 0, sides["R"][0], "R", "top", [top_peering(Tn, Lw, Tn, Tn)])
    put(4, 0, chamfer["NW"][0], "45 NW", "top", [top_peering(Lw, Tn, Tn, Lw)], probability=0.0,
        shapes=[[[-64, -64], [64, -64], [64, -64 + 24 + INSET - 52], [-64 + INSET, 64], [-64, 64]]])
    put(5, 0, chamfer["NE"][0], "45 NE", "top", [top_peering(Lw, Lw, Tn, Tn)], probability=0.0,
        shapes=[[[64, -64], [-64, -64], [-64, -64 + 24 + INSET - 52], [64 - INSET, 64], [64, 64]]])
    put(6, 0, notch["NW"][0], "notch NW", "top", [top_peering(Tn, Tn, Tn, Tn, nw=Lw)])
    put(7, 0, notch["NE"][0], "notch NE", "top", [top_peering(Tn, Tn, Tn, Tn, ne=Lw)])
    # Rows 1-2: side variants.
    for k, t in enumerate(sides["T"][1:8]):
        put(k, 1, t, f"T var {k + 1}", "top", [top_peering(Lw, Tn, Tn, Tn)], probability=0.6)
    for k, t in enumerate(sides["L"][1:5]):
        put(k, 2, t, f"L var {k + 1}", "top", [top_peering(Tn, Tn, Tn, Lw)], probability=0.6)
    for k, t in enumerate(sides["R"][1:5]):
        put(4 + k, 2, t, f"R var {k + 1}", "top", [top_peering(Tn, Lw, Tn, Tn)], probability=0.6)
    # Row 3: 45 degree variants.
    for k, t in enumerate(chamfer["NW"][1:4]):
        put(k, 3, t, f"45 NW var {k + 1}", "top", [top_peering(Lw, Tn, Tn, Lw)], probability=0.0)
    for k, t in enumerate(chamfer["NE"][1:4]):
        put(3 + k, 3, t, f"45 NE var {k + 1}", "top", [top_peering(Lw, Lw, Tn, Tn)], probability=0.0)
    put(6, 3, notch["NW"][1], "notch NW var", "top", [top_peering(Tn, Tn, Tn, Tn, nw=Lw)], probability=0.5)
    put(7, 3, notch["NE"][1], "notch NE var", "top", [top_peering(Tn, Tn, Tn, Tn, ne=Lw)], probability=0.5)
    # Rows 4-5: top ground and low ground.
    for k, t in enumerate(top_tiles[:8]):
        put(k, 4, t, f"top ground {k + 1}", "top", [full_top], probability=1.0 if k == 0 else 0.5)
    for k, t in enumerate(low_tiles[:8]):
        put(k, 5, t, f"low ground {k + 1}", "low", [full_low], probability=1.0 if k == 0 else 0.5)
    # Rows 6-9: the straight wall, eight variants per row.
    over_peers = [top_peering(Tn, Tn, s, Tn) | {"S": s, "SE": s, "SW": s} for s in (CAP, WALL, TOP)]
    for k in range(8):
        put(k, 6, wall_rows["over"][k], f"top over wall {k + 1}", "top", over_peers, probability=1.0 if k == 0 else 0.5)
        put(k, 7, wall_rows["cap"][k], f"wall top row {k + 1}", "cap",
            [row_peering(CAP, n, s, True, True) for n in (TOP, CAP) for s in (WALL, CAP)],
            probability=1.0 if k == 0 else 0.5, solid=True)
        put(k, 8, wall_rows["bottom"][k], f"wall {k + 1}", "wall",
            [row_peering(WALL, n, s, True, True) for n in (WALL, CAP) for s in (FOOT, WALL)],
            probability=1.0 if k == 0 else 0.5, solid=True)
        put(k, 9, wall_rows["foot"][k], f"foot {k + 1}", "foot",
            [row_peering(FOOT, n, s, True, True) for n in (WALL, FOOT, CAP) for s in (LOW,)],
            probability=1.0 if k == 0 else 0.5)
    # Rows 10-12: 45 degree walls (placed by hand): over, middle stone, foot; SW then SE.
    h = TILE / 2
    shapes = {"SW": {"over": [[-h, -h], [h, h], [-h, h]], "middle": None, "foot": [[-h, -h], [h, -h], [h, h]]},
              "SE": {"over": [[h, -h], [h, h], [-h, h]], "middle": None, "foot": [[-h, -h], [h, -h], [-h, h]]}}
    for r, key in enumerate(("over", "middle", "foot")):
        for k in range(4):
            for face, col0 in (("SW", 0), ("SE", 4)):
                t = diag[face][key][k % len(diag[face][key])]
                shape = shapes[face][key]
                put(col0 + k, 10 + r, t, f"45 wall {face} {key} {k + 1}", "wall" if key != "over" else "top",
                    [row_peering(WALL, WALL, WALL, True, True)], probability=0.0, solid=key == "middle",
                    shapes=[shape] if shape else None)

    for k in range(2):
        for face, col0 in (("SW", 0), ("SE", 4)):
            put(col0 + k, 13, diag[face]["rim"][k], f"45 wall {face} rim {k + 1}", "top", [full_top], probability=0.0)
            put(col0 + 2 + k, 13, diag[face]["spill"][k], f"45 wall {face} spill {k + 1}", "low", [full_low], probability=0.0)

    rows_used = max(r for _, r in sheet) + 1
    atlas = np.zeros((rows_used * TILE, COLUMNS * TILE, 4))
    for (c, r), image in sheet.items():
        atlas[r * TILE:(r + 1) * TILE, c * TILE:(c + 1) * TILE] = image
    OUT.mkdir(parents=True, exist_ok=True)
    save(atlas, OUT / f"{NAME}.png")
    (OUT / f"{NAME}.json").write_text(json.dumps({"tile": TILE, "name": NAME, "tiles": tiles}, indent=1) + "\n",
                                      encoding="utf-8")
    guide(atlas, labels, GUIDE)
    print(f"{NAME}: {len(tiles)} tiles in {COLUMNS} x {rows_used} cells -> {OUT}, guide {GUIDE.relative_to(ROOT)}")


def save(rgba: np.ndarray, path: Path) -> None:
    Image.fromarray(np.clip(rgba * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(path, optimize=True)


def guide(atlas: np.ndarray, labels: dict[tuple[int, int], str], path: Path) -> None:
    sheet = Image.fromarray(np.clip(atlas * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")
    pad, caption = 16, 20
    rows = atlas.shape[0] // TILE
    blocks = {0: "STRAIGHT SIDES (T, L, R) - 45 DEGREE TOPS (place by hand) - NOTCHES between their steps",
              1: "SIDE VARIANTS", 3: "45 DEGREE TOP VARIANTS", 4: "TOP GROUND", 5: "LOW GROUND",
              6: "STRAIGHT WALL: the top's row over it / wall top row (lip) / wall / foot",
              10: "45 DEGREE WALLS (place by hand): over / middle stone / foot  -  facing SW, facing SE",
              13: "45 DEGREE WALL CORNERS: the rim's tip beside each step (rim), the plants' tip beside each foot (spill)"}
    W = COLUMNS * (TILE + pad) + pad
    H = rows * (TILE + caption + pad) + pad + 28 * len(blocks)
    out = Image.new("RGBA", (W, H), (38, 32, 30, 255))
    draw = ImageDraw.Draw(out)
    try:
        font, title = ImageFont.truetype("arial.ttf", 12), ImageFont.truetype("arialbd.ttf", 14)
    except OSError:
        font = title = ImageFont.load_default()
    y = pad
    for r in range(rows):
        if r in blocks:
            draw.text((pad, y), blocks[r], fill=(240, 220, 160, 255), font=title)
            y += 28
        for c in range(COLUMNS):
            x = pad + c * (TILE + pad)
            draw.rectangle((x - 1, y - 1, x + TILE, y + TILE), outline=(90, 80, 75, 255))
            if (c, r) in labels:
                out.alpha_composite(sheet.crop((c * TILE, r * TILE, (c + 1) * TILE, (r + 1) * TILE)), (x, y))
                draw.text((x, y + TILE + 3), labels[(c, r)], fill=(225, 225, 225, 255), font=font)
        y += TILE + caption + pad
    out.crop((0, 0, W, y)).save(path)


if __name__ == "__main__":
    main()
