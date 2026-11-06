"""Build the tile compare lab (docs/godot/TILE_COMPARE_LAB.md): Zelda's ground and wall tiles and ours,
in one tile structure, to paint and compare.

Sources, in asset/Originals/concepts/zelda-tile-grid/: native-a..e.png, the game pixels of five Zelda
screenshots (a house cliff, b round plateau, c side wall, d top side, e top corner); native-f.png, the
low ledge's own tiles rebuilt from a sixth (native-ledge.png, in the rain); tile-sources.json, where
each tile of the set is cut from. FIGURES are the owner's figures and the screenshots' arrangements,
painted with the set's codes.

- zelda: the exact 16 px tiles, a dev-only reference.
- stone, dirt: our art in the same tiles, 64 px (32 world units, as a Zelda tile), cut cell by cell from
  Magnific paintings of the guide (painted/grid/), fitted to the guide's walls first.

The guide (the template for Magnific): each tile keeps its Zelda tile's shapes (where the plateau top,
the wall and the low ground are), smoothed four times larger; its wall is drawn as stone blocks or
layered earth laid along the wall's direction, lit from the upper left; along the plateau side Zelda's
rim (light ground, then a darker first grass edge, then the grass); the wall's foot a dark line and a
soft shadow. Written for each set as painted/grid/guide-<name>.png (plain for the stone: the walls'
drawing blurred away), with its numbered copy (guide-<name>-numbered.png: the grid, the same number for
the same tile) and the levels map (guide-levels.png: upper ground, lower ground, walls, arrows downhill).

Every sheet has one layout: the figures compacted (no grass outside the walls, no row or column
twice in a row), every tile where it goes. Writes godot/game/dev/tile_compare/: each sheet and its
TileSet and, unless it exists (it holds what was painted) or --force is given, the lab scene with
the figures in every set; and in the analysis folder tile-layout.json, tile-compare-sheets.png
(every sheet), tile-compare-preview.png (the lab's layers) and tile-compare-single.png (the guide's
figure in every set).

    python scripts/art/build-tile-compare-sheets.py [--force] [--no-carry]
"""
from __future__ import annotations

import argparse
import base64
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ORIG = ROOT / 'asset/Originals/concepts/zelda-tile-grid'
OUT = ROOT / 'godot/game/dev/tile_compare'
RES = 'res://game/dev/tile_compare/'
GRASS = ROOT / 'godot/asset/MAPS/grounds/128x128-tile_19x19_HighlandGreen.webp'
ROCK = ROOT / 'godot/asset/MAPS/elevation/meadow-rock-wall.png'
SHOTS = 'abcdef'  # f: the low ledge's own tiles rebuilt from the rain screenshot (tile-sources.json)

T = 16  # Zelda tile, game pixels
BIG = 64  # our tile: 64 px, 32 world units at our 2 px a unit
ZOOM = BIG // T
# The set. A plain code is the left side (or as in its screenshot), h its mirror. Straight walls
# (S front, N top side) and grass have no mirror.
SIDED = ['D1', 'D2', 'D3', 'D4', 'D5', 'W1', 'W2', 'W3', 'J1', 'J2', 'J3', 'E1', 'E2', 'E3', 'E4', 'E5',
	'Q0', 'Q1', 'Q2', 'Q3', 'Q4', 'K1', 'K2', 'Q5', 'Q6', 'K3']
# N3, Q5, Q6, K3: the low top side (2026-11-05, owner: "add the low ledge's tiles to the Zelda base"),
# a ledge one tile lower than N0-N2: N3 (its shadow and wall top in one tile) over N2, its 45° Q5
# (the shadow's edge) and Q6 (the wall) over Q3 and Q4, K3 its straight wall turning down the 45°.
TILES = ['G1', 'S1', 'S2', 'S3', 'N0', 'N1', 'N2', 'N3'] + SIDED + [c + 'h' for c in SIDED]
# The figures (column, row, tiles; '.' = nothing), as painted in the lab:
# - the owner's two (2026-11-04: "with this 2 figure in the tile sheet we will have enough, we see all
#   wall from different angles and different levels"): a U plateau (side walls with their 45° jogs, a
#   two-level front) and a V plateau (both cliff ends);
# - the top side (owner: "map these tiles that goes on the top, mirror the left side"): screenshot d,
#   a plateau's top edge stepping down a 45°, and its mirror;
# - the top corners (owner: "this is how it joint 90 top with 90 side, there is an small 45"):
#   screenshot e, a plateau's top with both corners and its side walls going down: the small 45° is
#   the top side's own 45° tiles, the side walls start right under them;
# - the single figure (2026-11-04): the owner's whole figure (his top edge with both corners, a 45° step
#   down and the side walls, "i will have to paint a whole figure with the zelda base") extended to
#   hold every tile but the cliff ends ("give magnific a sole figure that hold all the tiles ... make
#   wall at least 2 tile wide even if tiles repeat"): a dip in the top edge (K2, Q4h), a two-step
#   45° at the top-left corner, a jog in each side wall (J3), the U's front; every wall run at least
#   two tiles, every neighbour pair one Zelda's figures have. The cliff ends (E) need a cliff fading
#   into ground of its height, which a closed plateau has not;
# - the low ledge (2026-11-05): the owner's rain screenshot (ledge-tile-map.png), a low top side with a
#   45° going down at each end; the 45° landing on a lower straight ledge is not in it.
# The top side's grid is the one its side walls fit (owner, 2026-11-04: the edge tile must hold the
# whole transition from the wall to the grass, as on every other side).
FIGURES = [
	(0, 0, """
W3 J1 D2 D1 G1 G1 G1 G1 G1 G1 G1 D1h D2h J1h W3h
J2 D5 D3 D2 D1 G1 G1 G1 G1 G1 D1h D2h D3h D5h J2h
D4 D3 D5 J3 W1 G1 G1 G1 G1 G1 W1h J3h D5h D3h D4h
G1 D4 J3 W2 W1 G1 G1 G1 G1 G1 W1h W2h J3h D4h G1
. G1 W3 W2 W1 G1 G1 G1 G1 G1 W1h W2h W3h G1 .
. G1 W3 W2 W1 G1 G1 G1 G1 G1 W1h W2h W3h G1 .
. G1 W3 J1 D2 D1 G1 G1 G1 D1h D2h J1h W3h G1 .
. G1 J2 D5 D3 D2 S1 S1 S1 D2h D3h D5h J2h G1 .
. G1 D4 D3 D3 D3 S2 S2 S2 D3h D3h D3h D4h G1 .
. G1 G1 D4 D3 D3 S2 S2 S2 D3h D3h D4h G1 G1 .
. . G1 G1 D4 D3 S2 S2 S2 D3h D4h G1 G1 . .
. . . G1 G1 D4 S3 S3 S3 D4h G1 G1 . . .
"""),
	(17, 1, """
E1 D1 G1 G1 G1 G1 D1h E1h
E2 E3 D1 G1 G1 D1h E3h E2h
G1 E4 D2 S1 S1 D2h E4h G1
. E5 D3 S2 S2 D3h E5h .
. . D4 S3 S3 D4h . .
"""),
	(0, 14, """
N0 N0 N0 Q0 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 Q0h N0 N0 N0
N1 N1 K1 Q1 Q0 G1 G1 G1 G1 G1 G1 G1 G1 Q0h Q1h K1h N1 N1
N2 N2 Q3 Q2 Q1 Q0 G1 G1 G1 G1 G1 G1 Q0h Q1h Q2h Q3h N2 N2
G1 G1 Q4 Q3 Q2 Q1 N0 N0 N0 N0 N0 N0 Q1h Q2h Q3h Q4h G1 G1
G1 G1 G1 Q4 Q3 K2 N1 N1 N1 N1 N1 N1 K2h Q3h Q4h G1 G1 G1
G1 G1 G1 G1 Q4 N2 N2 N2 N2 N2 N2 N2 N2 Q4h G1 G1 G1 G1
"""),
	(20, 14, """
G1 Q0h N0 N0 N0 N0 Q0 G1
Q0h Q1h K1h N1 N1 K1 Q1 Q0
Q1h Q2h Q3h N2 N2 Q3 Q2 Q1
W3 W2 W1 G1 G1 W1h W2h W3h
W3 W2 W1 G1 G1 W1h W2h W3h
"""),
	(27, 0, """
G1 G1 Q0h N0 N0 N0 N0 Q0 G1 G1 G1 G1 G1 G1 Q0h N0 N0 N0 N0 Q0 G1 G1 G1
G1 Q0h Q1h K1h N1 N1 K1 Q1 Q0 G1 G1 G1 G1 Q0h Q1h K1h N1 N1 K1 Q1 Q0 G1 G1
Q0h Q1h Q2h Q3h N2 N2 Q3 Q2 Q1 Q0 G1 G1 Q0h Q1h Q2h Q3h N2 N2 Q3 Q2 Q1 Q0 G1
Q1h Q2h Q3h Q4h G1 G1 Q4 Q3 Q2 Q1 N0 N0 Q1h Q2h Q3h Q4h G1 G1 Q4 Q3 Q2 Q1 Q0
W3 W2 W1 G1 G1 G1 G1 Q4 Q3 K2 N1 N1 K2h Q3h Q4h G1 G1 G1 G1 Q4 Q3 Q2 Q1
W3 W2 W1 G1 G1 G1 G1 G1 Q4 N2 N2 N2 N2 Q4h G1 G1 G1 G1 G1 G1 W1h W2h W3h
W3 W2 W1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 W1h W2h W3h
W3 J1 D2 D1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 D1h D2h J1h W3h
J2 D5 D3 D2 D1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 D1h D2h D3h D5h J2h
D4 D3 D5 J3 W1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 W1h J3h D5h D3h D4h
G1 D4 J3 W2 W1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 W1h W2h J3h D4h G1
G1 G1 W3 W2 W1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 W1h W2h W3h G1 G1
G1 G1 W3 W2 W1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 W1h W2h W3h G1 G1
G1 G1 W3 J1 D2 D1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 G1 D1h D2h J1h W3h G1 G1
G1 G1 J2 D5 D3 D2 S1 S1 S1 S1 S1 S1 S1 S1 S1 S1 S1 D2h D3h D5h J2h G1 G1
G1 G1 D4 D3 D3 D3 S2 S2 S2 S2 S2 S2 S2 S2 S2 S2 S2 D3h D3h D3h D4h G1 G1
G1 G1 G1 D4 D3 D3 S2 S2 S2 S2 S2 S2 S2 S2 S2 S2 S2 D3h D3h D4h G1 G1 G1
G1 G1 G1 G1 D4 D3 S2 S2 S2 S2 S2 S2 S2 S2 S2 S2 S2 D3h D4h G1 G1 G1 G1
G1 G1 G1 G1 G1 D4 S3 S3 S3 S3 S3 S3 S3 S3 S3 S3 S3 D4h G1 G1 G1 G1 G1
"""),
	(0, 22, """
G1 G1 G1 G1 G1 G1 G1 G1 G1 G1
G1 Q5h K3h N3 N3 N3 N3 K3 Q5 G1
Q5h Q6h Q3h N2 N2 N2 N2 Q3 Q6 Q5
Q6h Q3h Q4h G1 G1 G1 G1 Q4 Q3 Q6
Q3h Q4h G1 G1 G1 G1 G1 G1 Q4 Q3
Q4h G1 G1 G1 G1 G1 G1 G1 G1 Q4
"""),
]
SHEET_WIDTH = 22  # sheet columns before the figures wrap to a new row
SHEET_GAP = 1  # empty cells between the figures on the sheets
LAB_ROW_GAP = 3  # empty cells between the lab's layers
# Zelda's colours, one per class (each screenshot pixel takes the nearest)
CLASSES = [
	('grass', (68, 163, 68)),
	('grass_dark', (38, 115, 38)),
	('outline_green', (16, 34, 16)),
	('tan', (144, 124, 67)),
	('rock_light', (123, 97, 48)),
	('rock_mid', (96, 68, 29)),
	('rock_dark', (66, 47, 29)),
	('rock_outline', (34, 30, 24)),
]
GRASS_CLASSES = (0, 1, 2)
TAN = 3
DARK_ROCK = (6, 7)
# Our art (owner, 2026-11-04): Magnific paints a guide of whole figures on the tile grid, and every
# painted cell is its own tile. A painting is one picture, not tiles made to repeat: a cut reused
# elsewhere breaks at its seams ("tiles don't fit and blur"), so cells are not reused to fill the set.
# Before the cut the painting is fitted to the guide's walls (fit_to_guide); the fitted painting is
# written next to it as <name>-fitted.png.
# (name, title in the lab, painting in painted/grid/, plain): the guide written for Magnific as
# guide-<name>.png is the drawn one, or with plain its walls' drawing blurred away (plain_guide); the
# fit always uses the drawn one. A missing painting leaves its layer out.
PAINTINGS = ORIG / 'painted' / 'grid'
VARIANTS = [
	('stone', 'Our stone walls (Nano Banana 2.1): every painted cell its own tile', 'stone-drystone-nano.png', True),
	('dirt', 'Our dirt cliffs (Nano Banana 2.1): every painted cell its own tile', 'dirt-lumps-nano.png', False),
]
# The guide: (figure in FIGURES, column, row on the guide): the single figure alone (owner: separate
# figures "could be confusing for AI"; a whole plateau shows which side of the top edge is the
# plateau), on GUIDE_TILES tiles of 64 px, asked back at GUIDE_SIZE. With it goes the same picture
# with the tile grid drawn and every cell numbered, the same number for the same tile (owner: "we
# could numerate each tile in the matrix letting know what tiles are the same").
GUIDE = [(4, 1, 1)]
GUIDE_TILES = (25, 21)
GUIDE_SIZE = (1600, 1344)
# light from the upper left: the way it goes (x right, y down)
LIGHT = np.array([1.0, 1.0]) / np.sqrt(2.0)
# the ways a tile's wall may face (0 E, 1 SE, 2 S, 3 SW, 4 W, 5 NW, 6 N, 7 NE), by its code; its mirror
# (h) faces the mirrored ways. A tile with two takes, pixel by pixel, the nearer to the way from the
# plateau top to the low ground there, so straight walls stay straight and a turn splits.
FACINGS = {'S': (2,), 'N': (6,), 'D': (3,), 'Q': (7,), 'W': (4,), 'J': (4, 3), 'E': (4, 3), 'K': (6, 7)}
# the middle tiles that stack for a taller wall (the guide's drawing shades them evenly)
MIDDLE = {'S2', 'D3', 'D5', 'W2'}
# the rim along a wall's plateau side, as Zelda's (owner, 2026-11-04: "wall, then a light ground,
# then a first grass edge, finally a grass that will match your ground")
LIGHT_GROUND = np.array([212, 180, 124], np.float32)
GRASS_EDGE = np.array([0.5, 0.64, 0.46], np.float32)  # the grass darkened along the light ground
FOOT_LINE = np.array([40, 30, 18], np.float32)  # where a wall stands on the low ground


# --- helpers ------------------------------------------------------------------------------------

def blur(a: np.ndarray, sigma: float) -> np.ndarray:
	r = max(1, int(sigma * 3))
	k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
	k /= k.sum()
	pad = np.pad(a, ((r, r), (r, r)) + ((0, 0),) * (a.ndim - 2), mode='edge')
	out = np.zeros_like(pad, dtype=np.float32)
	for i, w in enumerate(k):
		out += w * np.roll(pad, i - r, 0)
	pad = out
	out = np.zeros_like(pad)
	for i, w in enumerate(k):
		out += w * np.roll(pad, i - r, 1)
	return out[r:-r, r:-r]


def dilate(m: np.ndarray, steps: int) -> np.ndarray:
	for _ in range(steps):
		g = m.copy()
		g[1:] |= m[:-1]
		g[:-1] |= m[1:]
		g[:, 1:] |= m[:, :-1]
		g[:, :-1] |= m[:, 1:]
		m = g
	return m


def distance(seed: np.ndarray, limit: int) -> np.ndarray:
	"""Distance to the seed pixels (chamfer: 1 across, 1.41 diagonal), up to limit."""
	d = np.where(seed, 0.0, float(limit)).astype(np.float32)
	big = float(limit)
	for _ in range(limit):
		p = np.pad(d, 1, constant_values=big)
		n = np.minimum.reduce([
			d, p[:-2, 1:-1] + 1, p[2:, 1:-1] + 1, p[1:-1, :-2] + 1, p[1:-1, 2:] + 1,
			p[:-2, :-2] + 1.414, p[:-2, 2:] + 1.414, p[2:, :-2] + 1.414, p[2:, 2:] + 1.414])
		if np.array_equal(n, d):
			break
		d = n
	return d


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
	t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3 - 2 * t)


def split(code: str) -> tuple[str, str]:
	return (code[:-1], 'h') if code.endswith('h') else (code, '')


def flip(a: np.ndarray, how: str) -> np.ndarray:
	return a[:, ::-1] if 'h' in how else a


def periodic(tile: np.ndarray) -> np.ndarray:
	"""A crop made seamless over its own size: blended with itself shifted by half (contrast kept)."""
	n = tile.shape[0]
	shifted = np.roll(np.roll(tile, n // 2, 0), n // 2, 1)
	ramp = np.sin(np.pi * (np.arange(n) + 0.5) / n)
	w = np.outer(ramp, ramp)[..., None] ** 0.7
	mean = tile.mean((0, 1), keepdims=True)
	return mean + (w * (tile - mean) + (1 - w) * (shifted - mean)) / np.sqrt(w ** 2 + (1 - w) ** 2)


def periodic_noise(n: int, scale: float, seed: int) -> np.ndarray:
	"""Smooth noise that repeats every n pixels, values about -1..1."""
	rng = np.random.default_rng(seed)
	f = np.fft.fft2(rng.standard_normal((n, n)))
	fy = np.fft.fftfreq(n)[:, None]
	fx = np.fft.fftfreq(n)[None, :]
	f *= np.exp(-(fx ** 2 + fy ** 2) * (scale ** 2) * 40)
	out = np.real(np.fft.ifft2(f))
	return out / (np.abs(out).max() + 1e-6)


# --- the figures and the layout -----------------------------------------------------------------

def parse(text: str) -> list:
	return [[None if t == '.' else t for t in line.split()] for line in text.strip().splitlines()]


def compact(grid: list) -> list:
	"""A figure without repeats: no grass outside its walls, no row or column twice in a row."""
	grid = [row[:] for row in grid]
	for row in grid:
		walls = [i for i, t in enumerate(row) if t not in (None, 'G1')]
		for i in range(len(row)):
			if walls and (i < walls[0] or i > walls[-1]) and row[i] == 'G1':
				row[i] = None
	rows: list = []
	for row in grid:
		if not rows or rows[-1] != row:
			rows.append(row)
	cols: list = []
	for col in zip(*rows):
		if not cols or cols[-1] != list(col):
			cols.append(list(col))
	return [list(r) for r in zip(*cols)]


def layout() -> list:
	"""(sheet column, sheet row, code) of every tile: the figures compacted, left to right, wrapping."""
	out = []
	x0 = y0 = row_h = 0
	for _, _, text in FIGURES:
		grid = compact(parse(text))
		w, h = len(grid[0]), len(grid)
		if x0 and x0 + w > SHEET_WIDTH:
			x0, y0, row_h = 0, y0 + row_h + SHEET_GAP, 0
		for y, row in enumerate(grid):
			for x, code in enumerate(row):
				if code is not None:
					out.append((x0 + x, y0 + y, code))
		x0 += w + SHEET_GAP
		row_h = max(row_h, h)
	missing = set(TILES) - {code for _, _, code in out}
	assert not missing, f'tiles on no figure: {sorted(missing)}'
	return out


def painted_cells() -> list:
	"""(x, y, code) of every figure as painted in the lab."""
	return [(fx + x, fy + y, code) for fx, fy, text in FIGURES
		for y, row in enumerate(parse(text)) for x, code in enumerate(row) if code is not None]


def zelda_tiles() -> dict:
	"""code -> its 16 px tile, cut from the screenshots."""
	sources = json.load(open(ORIG / 'tile-sources.json'))['tiles']
	native = {s: np.asarray(Image.open(ORIG / f'native-{s}.png').convert('RGB')) for s in SHOTS}
	out = {}
	for code in TILES:
		base, how = split(code)
		s = sources[base]
		out[code] = flip(native[s['shot']][s['y']:s['y'] + T, s['x']:s['x'] + T], how)
	return out


def sheet(cells: list, tiles: dict, size: int) -> Image.Image:
	cols = max(x for x, _, _ in cells) + 1
	rows = max(y for _, y, _ in cells) + 1
	out = np.zeros((rows * size, cols * size, 4), np.uint8)
	for x, y, code in cells:
		out[y * size:(y + 1) * size, x * size:(x + 1) * size, :3] = tiles[code]
		out[y * size:(y + 1) * size, x * size:(x + 1) * size, 3] = 255
	return Image.fromarray(out, 'RGBA')


# --- our art: the textures, each repeating once a tile -----------------------------------------

def grass_texture() -> np.ndarray:
	src = np.asarray(Image.open(GRASS).convert('RGB'), np.float32)
	return np.clip(periodic(src[9 * 128 + 32:9 * 128 + 32 + BIG, 9 * 128 + 32:9 * 128 + 32 + BIG]), 0, 255)


def rock_grain() -> np.ndarray:
	"""Meadow rock's grain over one tile: its light relative to the light around it."""
	rock = np.asarray(Image.open(ROCK).convert('RGB'), np.float32)
	lum = rock @ np.array([0.299, 0.587, 0.114], np.float32)
	detail = lum / np.maximum(blur(lum, 5.0), 1.0) - 1.0
	return periodic(detail[40:40 + BIG, 120:120 + BIG][..., None])[..., 0]


def stone_texture() -> np.ndarray:
	"""Two courses of rounded stone blocks in running bond, 64x64, repeating: drawn 4x larger, then reduced."""
	S = 4
	n = BIG * S
	yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / S
	course = (yy // 32).astype(int)
	ly = yy % 32
	lx = (xx + np.where(course == 1, 32, 0)) % 64
	gap, radius = 2.0, 11.5
	# distance inside each block's rounded rectangle (0 on its edge), its outline a little uneven
	half_w, half_h = 32 - gap, 16 - gap
	cx, cy = np.abs(lx - 32), np.abs(ly - 16)
	qx, qy = cx - (half_w - radius), cy - (half_h - radius)
	outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - radius
	inside = -outside + 1.6 * periodic_noise(n, 2.2 * S, 11)
	height = smoothstep(0.0, 9.0, inside) + 0.25 * periodic_noise(n, 1.4 * S, 5)
	gy, gx = np.gradient(height * 6.0)
	normal = np.stack([-gx, -gy, np.ones_like(gx)], -1)
	normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
	sun = np.array([-0.55, -0.65, 0.52])
	sun /= np.linalg.norm(sun)
	lit = np.clip(normal @ sun, 0, 1)
	grain = np.asarray(Image.fromarray(rock_grain().astype(np.float32), 'F').resize((n, n), Image.BICUBIC))
	tone = np.where((course == 0)[..., None], np.array([1.0, 0.98, 0.95]), np.array([0.94, 0.92, 0.9]))
	stone = np.array([156, 136, 110], np.float32) * tone * (0.58 + 0.66 * lit[..., None]) * (1 + 0.45 * grain[..., None])
	rim = smoothstep(0.0, 1.6, inside)[..., None]
	stone = stone * (0.68 + 0.32 * rim)
	moss = periodic_noise(n, 3.0 * S, 7)[..., None]
	mortar = np.array([54, 42, 28], np.float32) + np.clip(moss, 0, 1) * np.array([44, 62, 6], np.float32)
	a = smoothstep(-0.6, 0.6, inside)[..., None]
	out = stone * a + mortar * (1 - a)
	return np.asarray(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).resize((BIG, BIG), Image.BOX)).astype(np.float32)


def dirt_texture() -> np.ndarray:
	"""Soft layers of packed earth, each bulging like a ledge, 64x64, repeating."""
	S = 4
	n = BIG * S
	yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / S
	layers = 2
	h = BIG / layers
	wave = 3.4 * np.sin(2 * np.pi * (xx / 64 + 0.13)) + 1.6 * np.sin(2 * np.pi * (2 * xx / 64 + 0.57)) 		+ 1.2 * periodic_noise(n, 2.5 * S, 21)
	y = (yy + wave) % 64
	k = (y // h).astype(int)
	f = (y % h) / h  # 0 at a layer's top, 1 at its foot
	colours = np.array([[186, 126, 68], [164, 106, 56]], np.float32)
	base = colours[k]
	bulge = 1.14 - 0.42 * f ** 1.4
	crease = 1 - 0.45 * smoothstep(0.88, 1.0, f)
	noise = periodic_noise(n, 1.2 * S, 3)[..., None]
	streak = periodic_noise(n, 0.6 * S, 9)[..., None]
	out = base * (bulge * crease)[..., None] * (1 + 0.1 * noise + 0.05 * streak)
	for (px, py, r) in ((14, 9, 2.4), (45, 41, 2.0), (30, 26, 1.6)):
		dx = (xx - px + 32) % 64 - 32
		dy = (yy - py + 32) % 64 - 32
		d = np.hypot(dx, dy)
		m = smoothstep(r + 0.6, r - 0.4, d)[..., None]
		shade = (1.15 - 0.35 * np.clip((dx + dy) / (2 * r), -1, 1))[..., None]
		out = out * (1 - m) + np.array([128, 112, 92], np.float32) * shade * m
	return np.asarray(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).resize((BIG, BIG), Image.BOX)).astype(np.float32)


# --- our art: the figures' shapes and drawing ----------------------------------------------------

def regions(img: np.ndarray, empty: np.ndarray) -> np.ndarray:
	"""0 low ground, 1 plateau top, 2 wall, in game pixels. A wall's lip is Zelda's tan rim: grass
	beside it is a top; grass beside its dark rock (and away from any tan) is low ground; each spreads
	over the grass it reaches first."""
	pal = np.array([c for _, c in CLASSES], np.int32)
	cls = np.abs(img[:, :, None, :].astype(np.int32) - pal[None, None]).sum(3).argmin(2)
	grass = np.isin(cls, GRASS_CLASSES) | empty
	near_tan = dilate(cls == TAN, 2)
	top = grass & near_tan
	low = (grass & dilate(np.isin(cls, DARK_ROCK), 1) & ~dilate(cls == TAN, 4)) | empty
	while True:
		free = grass & ~low & ~top
		nl = dilate(low, 1) & free
		nt = dilate(top, 1) & free
		if not nl.any() and not nt.any():
			break
		low |= nl & ~nt
		top |= nt & ~nl
		low |= nl & nt
	return np.where(~grass, 2, np.where(top, 1, 0))


def allowed_facings(code: str) -> tuple:
	base, how = split(code)
	ways = FACINGS.get(base[0], tuple(range(8)))
	if how:  # mirrored: east and west swap
		ways = tuple((4 - w) % 8 for w in ways)
	return ways


def draw(variant: str, img: np.ndarray, empty: np.ndarray, cells: list, with_shapes: bool = False):
	"""The figures drawn in our art, 64 px a tile."""
	region = regions(img, empty)
	h, w = region.shape
	soft = np.zeros((h * ZOOM, w * ZOOM, 3), np.float32)
	for i in range(3):
		m = Image.fromarray((region == i).astype(np.float32), 'F').resize((w * ZOOM, h * ZOOM), Image.BICUBIC)
		soft[..., i] = np.asarray(m)
	big = blur(soft, 2.2).argmax(2)
	top, wall, low = big == 1, big == 2, big == 0
	# distances, in our pixels: from the game-pixel maps, then the near ones exact
	d_top = np.asarray(Image.fromarray(distance(region == 1, 48), 'F').resize((w * ZOOM, h * ZOOM), Image.BILINEAR)) * ZOOM
	d_low = np.asarray(Image.fromarray(distance(region == 0, 48), 'F').resize((w * ZOOM, h * ZOOM), Image.BILINEAR)) * ZOOM
	d_top_near = distance(top, 14)
	d_low_near = distance(low, 20)
	d_wall_near = distance(wall, 20)
	d_top = np.where(d_top_near < 13, d_top_near, d_top)
	d_low = np.where(d_low_near < 19, d_low_near, d_low)
	# which way each wall pixel faces: from the plateau top towards the low ground
	field = blur(distance(region == 1, 128) - distance(region == 0, 128), 1.6)
	gy, gx = np.gradient(field)
	gx = np.asarray(Image.fromarray(gx.astype(np.float32), 'F').resize((w * ZOOM, h * ZOOM), Image.BILINEAR))
	gy = np.asarray(Image.fromarray(gy.astype(np.float32), 'F').resize((w * ZOOM, h * ZOOM), Image.BILINEAR))
	norm = np.hypot(gx, gy) + 1e-6
	nx, ny = gx / norm, gy / norm
	way = (np.arctan2(ny, nx) / (np.pi / 4)) % 8  # 0 E, 1 SE, 2 S, 3 SW, 4 W, 5 NW, 6 N, 7 NE
	first = np.round(way).astype(int) % 8
	second = first.copy()
	for x, y, code in cells:
		ways = allowed_facings(code)
		sl = (slice(y * BIG, (y + 1) * BIG), slice(x * BIG, (x + 1) * BIG))
		first[sl] = ways[0]
		second[sl] = ways[-1]
	gap = lambda a: np.minimum((way - a) % 8, (a - way) % 8)
	sector = np.where(gap(first) <= gap(second), first, second)
	# texture coordinates by facing: courses run along the wall's lip
	Y, X = np.mgrid[0:h * ZOOM, 0:w * ZOOM]
	u = X.copy()
	v = Y.copy()
	side = (sector == 0) | (sector == 4)
	u[side], v[side] = Y[side], X[side]
	falling = (sector == 3) | (sector == 7)  # lip runs down to the right
	v[falling] = Y[falling] - X[falling]
	rising = (sector == 1) | (sector == 5)  # lip runs up to the right
	v[rising] = Y[rising] + X[rising]
	tex = stone_texture() if variant == 'stone' else dirt_texture()
	wall_rgb = tex[v % BIG, u % BIG]
	# light: faces turned to the upper left lit, away darker; a back wall (facing north) in shade
	facing = 1.0 - 0.18 * (nx * LIGHT[0] + ny * LIGHT[1]) - 0.42 * np.clip(-ny, 0, 1)
	depth = d_top / np.maximum(d_top + d_low, 1)
	shade = facing * (1 - 0.2 * depth) * (1 - 0.32 * np.exp(-d_top / 6.0))
	# a wall tile's shading only changes across its wall, so it repeats along the wall without a seam;
	# the middle tiles that stack for a taller wall (the guide's drawing shades them evenly) are evenly shaded
	ly, lx = np.mgrid[0:BIG, 0:BIG]
	for x, y, code in cells:
		base, how = split(code)
		sl = (slice(y * BIG, (y + 1) * BIG), slice(x * BIG, (x + 1) * BIG))
		part = shade[sl]
		if base in MIDDLE:
			shade[sl] = part.mean()
		elif base[0] in 'SN':
			shade[sl] = part.mean(axis=1, keepdims=True)
		elif base[0] == 'W':
			shade[sl] = part.mean(axis=0, keepdims=True)
		elif base[0] in 'DQ':
			bins = (ly + lx) if how else (ly - lx + BIG)  # along the 45° run
			sums = np.bincount(bins.ravel(), part.ravel())
			counts = np.bincount(bins.ravel())
			shade[sl] = (sums / np.maximum(counts, 1))[bins]
	corner = dilate(np.diff(sector, axis=1, prepend=sector[:, :1]) != 0, 1) | dilate(np.diff(sector, axis=0, prepend=sector[:1]) != 0, 1)
	shade = np.where(corner & wall, shade * 0.85, shade)
	rgb = wall_rgb * shade[..., None]
	foot = wall & (d_low < 2.5)
	rgb[foot] = FOOT_LINE
	# the rim, Zelda's shapes: Zelda's tan reached from the plateau's grass (not the tan glints in its
	# rock) is light ground on the wall's plateau side; Zelda's dark grass along it is the first grass
	# edge; then the grass
	pal = np.array([c for _, c in CLASSES], np.int32)
	cls = np.abs(img[:, :, None, :].astype(np.int32) - pal[None, None]).sum(3).argmin(2)

	def grow(seed: np.ndarray, within: np.ndarray) -> np.ndarray:
		while True:
			more = dilate(seed, 1) & within
			if (more == seed).all():
				return seed
			seed = more

	def smooth(m: np.ndarray) -> np.ndarray:
		up = np.asarray(Image.fromarray(m.astype(np.float32), 'F').resize((w * ZOOM, h * ZOOM), Image.BICUBIC))
		return blur(up, 2.2) > 0.5

	tan = (cls == TAN) & ~empty
	rim = grow(tan & dilate(region == 1, 1), tan)
	dark = np.isin(cls, (1, 2)) & (region == 1) & ~empty
	edge = grow(dark & dilate(rim, 1), dark)
	rim_big = smooth(rim) & wall
	edge_big = smooth(edge) & top & ~rim_big
	light = LIGHT_GROUND * (0.94 + 0.12 * (tex[v % BIG, u % BIG].mean(2) / tex.mean() - 1))[..., None]
	rgb = np.where(rim_big[..., None], light, rgb)
	# grass: the plateau's even, its first edge darker along the light ground; the low ground's lies
	# in the wall's shadow
	grass = grass_texture()[Y % BIG, X % BIG]
	g_top = np.where(edge_big[..., None], grass * GRASS_EDGE, grass)
	g_low = grass * (0.62 + 0.38 * smoothstep(0, 18, d_wall_near))[..., None]
	g_low = np.where((d_wall_near < 1.4)[..., None], FOOT_LINE, g_low)
	rgb = np.where(top[..., None], g_top, rgb)
	rgb = np.where(low[..., None], g_low, rgb)
	rgb = np.clip(rgb, 0, 255).astype(np.uint8)
	return (rgb, big) if with_shapes else rgb


def figure_rects() -> list:
	"""(column, row, width, height) of each figure in the lab, in tiles."""
	return [(fx, fy, max(len(r) for r in parse(t)), len(parse(t))) for fx, fy, t in FIGURES]


def guide_cells() -> list:
	"""(x, y, code) of the guide's figures on the guide."""
	out = []
	for index, gx, gy in GUIDE:
		for y, row in enumerate(parse(FIGURES[index][2])):
			for x, code in enumerate(row):
				if code is not None:
					out.append((gx + x, gy + y, code))
	return out


def guide_picture(variant: str, tiles: dict) -> Image.Image:
	"""The guide given to Magnific: the guide's figures drawn by the tool (Zelda's tile shapes, our stone
	or dirt laid along each wall), on the low ground, at the painting's size."""
	cols, rows = GUIDE_TILES
	img = np.zeros((rows * T, cols * T, 3), np.uint8)
	empty = np.ones((rows * T, cols * T), bool)
	cells = guide_cells()
	for x, y, code in cells:
		img[y * T:(y + 1) * T, x * T:(x + 1) * T] = tiles[code]
		empty[y * T:(y + 1) * T, x * T:(x + 1) * T] = False
	pic = draw(variant, img, empty, cells)
	w, h = GUIDE_SIZE
	Y, X = np.mgrid[0:h, 0:w]
	canvas = grass_texture()[Y % BIG, X % BIG].astype(np.uint8)
	canvas[:pic.shape[0], :pic.shape[1]] = pic
	return Image.fromarray(canvas)


def levels_picture(tiles: dict) -> Image.Image:
	"""The guide's levels for Magnific (owner, 2026-11-04: signal "what is the lower ground and the upper
	ground" so the top side is not painted inverted): the upper ground yellow, the lower ground blue, the
	walls grey with arrows downhill, the rim (light ground, first grass edge) on the upper side, labelled."""
	from PIL import ImageDraw, ImageFont
	cols, rows = GUIDE_TILES
	img = np.zeros((rows * T, cols * T, 3), np.uint8)
	empty = np.ones((rows * T, cols * T), bool)
	cells = guide_cells()
	for x, y, code in cells:
		img[y * T:(y + 1) * T, x * T:(x + 1) * T] = tiles[code]
		empty[y * T:(y + 1) * T, x * T:(x + 1) * T] = False
	rgb, shapes = draw('dirt', img, empty, cells, with_shapes=True)
	w, h = GUIDE_SIZE
	level = np.zeros((h, w), np.int8)
	level[:shapes.shape[0], :shapes.shape[1]] = shapes
	out = np.zeros((h, w, 3), np.uint8)
	out[level == 0] = (58, 96, 178)
	out[level == 1] = (238, 200, 92)
	out[level == 2] = (126, 126, 126)
	pic = np.zeros((h, w, 3), np.uint8)
	pic[:rgb.shape[0], :rgb.shape[1]] = rgb
	rim = (level == 2) & (np.abs(pic.astype(int) - LIGHT_GROUND.astype(int)).sum(2) < 60)
	out[rim] = LIGHT_GROUND.astype(np.uint8)
	edge = (level == 1) & (pic[..., 1] < 110) & dilate(level == 2, 26)
	out[edge] = (40, 112, 44)
	img_out = Image.fromarray(out)
	d = ImageDraw.Draw(img_out)
	try:
		big_font, font = ImageFont.truetype('arialbd.ttf', 40), ImageFont.truetype('arialbd.ttf', 24)
	except OSError:
		big_font = font = ImageFont.load_default()
	ways = {0: (1, 0), 1: (1, 1), 2: (0, 1), 3: (-1, 1), 4: (-1, 0), 5: (-1, -1), 6: (0, -1), 7: (1, -1)}
	for x, y, code in cells:
		if code == 'G1' or (x + y) % 2 or level[y * BIG + BIG // 2, x * BIG + BIG // 2] != 2:
			continue  # arrows on the walls only
		dx, dy = ways[allowed_facings(code)[0]]
		n = (dx * dx + dy * dy) ** 0.5
		cx, cy = x * BIG + BIG / 2, y * BIG + BIG / 2
		ex, ey = cx + 22 * dx / n, cy + 22 * dy / n
		d.line([(cx - 18 * dx / n, cy - 18 * dy / n), (ex, ey)], fill=(255, 255, 255), width=5)
		for turn in (2.5, -2.5):
			a = np.arctan2(dy, dx) + turn
			d.line([(ex, ey), (ex + 14 * np.cos(a), ey + 14 * np.sin(a))], fill=(255, 255, 255), width=5)
	_, gx, gy = GUIDE[0]
	fig = parse(FIGURES[GUIDE[0][0]][2])
	fw, fh = max(len(r) for r in fig), len(fig)
	label = dict(fill=(0, 0, 0), stroke_width=3, stroke_fill=(255, 255, 255), anchor='mm')
	d.text(((gx + fw / 2) * BIG, (gy + fh / 2) * BIG), 'UPPER GROUND (high plateau)', font=big_font, **label)
	for px, py in ((gx + 11.5, gy + 1.0), (3.2, 0.5), (cols - 3.2, 0.5), (3.2, rows - 0.5), (cols - 3.2, rows - 0.5)):
		d.text((px * BIG, py * BIG), 'LOWER GROUND (low)', font=font, **label)
	d.text(((gx + fw / 2) * BIG, (gy + fh / 2) * BIG + 52), 'arrows point downhill, from the upper ground to the lower ground',
		font=font, **label)
	d.text(((gx + fw / 2) * BIG, (gy + fh / 2) * BIG + 86), 'the light ground and the first grass edge are always on the upper side',
		font=font, **label)
	return img_out


def numbered_guide(guide: Image.Image) -> Image.Image:
	"""The guide with its tile grid drawn and every cell of the figures numbered: the same number for
	the same tile (grass unnumbered)."""
	from PIL import ImageDraw, ImageFont
	img = guide.convert('RGB').copy()
	d = ImageDraw.Draw(img)
	cols, rows = GUIDE_TILES
	for c in range(cols + 1):
		d.line([(c * BIG, 0), (c * BIG, rows * BIG)], fill=(255, 255, 255), width=1)
	for r in range(rows + 1):
		d.line([(0, r * BIG), (cols * BIG, r * BIG)], fill=(255, 255, 255), width=1)
	try:
		font = ImageFont.truetype('arialbd.ttf', 20)
	except OSError:
		font = ImageFont.load_default()
	numbers: dict = {}
	for x, y, code in guide_cells():
		if code == 'G1':
			continue
		n = numbers.setdefault(code, len(numbers) + 1)
		d.text((x * BIG + BIG / 2, y * BIG + BIG / 2), str(n), fill=(255, 255, 255), font=font, anchor='mm',
			stroke_width=3, stroke_fill=(0, 0, 0))
	return img


def plain_guide(guide: Image.Image) -> Image.Image:
	"""The guide with its walls' drawing (stones, joints) blurred away, the rim, the grass edge and the
	walls' outline kept (2026-11-05): a painting follows the guide's drawn stones, so the round 4
	stones came back on the side and top walls next to big stones from the style picture on the front;
	with plain walls the style picture sets the stones everywhere."""
	g = np.asarray(guide.convert('RGB')).astype(np.float32)
	low, plateau, wall = wall_sides(g.astype(np.uint8))
	rim = wall & (np.abs(g - LIGHT_GROUND).sum(2) < 90) & dilate(plateau, 24)
	outline = wall & (dilate(low, 5) | dilate(plateau, 3)) & (g.mean(2) < 60)
	surface = wall & ~rim & ~outline
	m = surface.astype(np.float32)
	smooth = np.stack([blur(g[..., c] * m, 10.0) for c in range(3)], 2) / np.maximum(blur(m, 10.0), 1e-6)[..., None]
	return Image.fromarray(np.where(surface[..., None], smooth, g).clip(0, 255).astype(np.uint8))


def wall_sides(pic: np.ndarray) -> tuple:
	"""(low ground, plateau, wall) of a guide or painting: the wall is its earth or stone (warm or grey,
	not grass); the low ground is the grass reached from the corner, the plateau the grass reached from
	the figure's middle, and everything else (moss, specks among the stones) is wall."""
	from PIL import ImageDraw
	hsv = np.asarray(Image.fromarray(pic).convert('HSV')).astype(int)
	m = (hsv[..., 0] < 34) | (hsv[..., 1] < 60)
	erode = lambda a, k: ~dilate(~a, k)
	m = erode(dilate(dilate(erode(m, 3), 3), 4), 4)  # specks out, gaps closed
	fill = Image.fromarray((~m * 128).astype(np.uint8)).copy()
	ImageDraw.floodfill(fill, (2, 2), 255)
	_, gx, gy = GUIDE[0]
	fig = parse(FIGURES[GUIDE[0][0]][2])
	mx, my = max(len(r) for r in fig) // 2, len(fig) // 2
	ImageDraw.floodfill(fill, ((gx + mx) * BIG + BIG // 2, (gy + my) * BIG + BIG // 2), 200)
	a = np.asarray(fill)
	if (a == 200).sum() < 100 * BIG * BIG // 4:
		raise SystemExit('the plateau was not found in a painting: is the middle of the figure grass?')
	return a == 255, a == 200, (a != 255) & (a != 200)


def fit_to_guide(pic: np.ndarray, guide: np.ndarray) -> np.ndarray:
	"""The painting warped so its walls' edges lie where the guide's do (owner, 2026-11-04: an edge
	"compose of 2 tiles instead of 1": the painted walls came out up to half a tile thicker, their lip
	in the next cell). Each guide edge pixel takes the shift to the nearest painted edge pixel of the
	same side (low ground, plateau); the shifts spread smoothly (closely near the edges, broadly through
	the middle of wide walls, none far from the walls) and are applied in 64 small steps, so the
	painting bends but never tears or folds over itself (owner, 2026-11-05, on the first fit, which
	left the middle of wide walls unshifted next to shifted edges: "there are artefacts on the
	sides")."""
	h, w = pic.shape[:2]
	go, gi, g = wall_sides(guide)
	po, pi, p = wall_sides(pic)
	num = np.zeros((h, w, 2), np.float32)
	den = np.zeros((h, w), np.float32)
	for gside, pside in ((go, po), (gi, pi)):
		gy, gx = np.nonzero(g & dilate(gside, 1))
		py, px = np.nonzero(p & dilate(pside, 1))
		targets = np.stack([px, py], 1).astype(np.float32)
		for i in range(0, len(gx), 2000):
			q = np.stack([gx[i:i + 2000], gy[i:i + 2000]], 1).astype(np.float32)
			nearest = ((q[:, None, :] - targets[None, :, :]) ** 2).sum(2).argmin(1)
			num[gy[i:i + 2000], gx[i:i + 2000]] += targets[nearest] - q
			den[gy[i:i + 2000], gx[i:i + 2000]] += 1
	den[~dilate(g | p, 96)] += 0.05  # no shift far from the walls

	def spread(sigma: float) -> tuple:
		weight = blur(den, sigma)
		s = np.stack([blur(num[..., 0], sigma), blur(num[..., 1], sigma)], 2)
		return s / np.maximum(weight, 1e-12)[..., None], weight

	close, weight = spread(18.0)
	broad, _ = spread(60.0)
	near = smoothstep(0.0005, 0.004, weight)[..., None]
	shift = (near * close + (1 - near) * broad) / 64.0
	for _ in range(6):  # 64 small steps (scaling and squaring): never a fold
		shift = shift + resample(shift, shift)
	return resample(pic.astype(np.float32), shift).clip(0, 255).astype(np.uint8)


def resample(a: np.ndarray, shift: np.ndarray) -> np.ndarray:
	"""a read at each pixel plus its shift (x, y), bilinear."""
	h, w = a.shape[:2]
	Y, X = np.mgrid[0:h, 0:w].astype(np.float32)
	sx = np.clip(X + shift[..., 0], 0, w - 1.001)
	sy = np.clip(Y + shift[..., 1], 0, h - 1.001)
	x0, y0 = np.floor(sx).astype(int), np.floor(sy).astype(int)
	fx, fy = (sx - x0)[..., None], (sy - y0)[..., None]
	return (a[y0, x0] * (1 - fx) * (1 - fy) + a[y0, x0 + 1] * fx * (1 - fy)
		+ a[y0 + 1, x0] * (1 - fx) * fy + a[y0 + 1, x0 + 1] * fx * fy)


def fitted_painting(path: Path, guide: Image.Image) -> np.ndarray:
	"""The painting at the guide's size, fitted to the guide's walls."""
	img = Image.open(path).convert('RGB')
	if img.size != GUIDE_SIZE:
		img = img.resize(GUIDE_SIZE, Image.LANCZOS)
	g = np.asarray(guide.convert('RGB'))
	return fit_to_guide(np.asarray(img), g)


def painted_sheet(pic: np.ndarray) -> Image.Image:
	"""The painting cut on the guide's grid: every cell of the guide's figures its own tile, the rest empty."""
	cols, rows = GUIDE_TILES
	out = np.zeros((rows * BIG, cols * BIG, 4), np.uint8)
	for x, y, _ in guide_cells():
		out[y * BIG:(y + 1) * BIG, x * BIG:(x + 1) * BIG, :3] = pic[y * BIG:(y + 1) * BIG, x * BIG:(x + 1) * BIG]
		out[y * BIG:(y + 1) * BIG, x * BIG:(x + 1) * BIG, 3] = 255
	return Image.fromarray(out, 'RGBA')


def guide_lab_cells() -> list:
	"""(lab x, lab y, sheet column, sheet row): the guide's figures where the lab paints them, each cell
	from its own place on a painted sheet."""
	out = []
	for index, gx, gy in GUIDE:
		fx, fy, text = FIGURES[index]
		for y, row in enumerate(parse(text)):
			for x, code in enumerate(row):
				if code is not None:
					out.append((fx + x, fy + y, gx + x, gy + y))
	return out


def tileset_text(texture: str, size: int, name: str, cells: list) -> str:
	lines = [
		'[gd_resource type="TileSet" format=3]',
		'',
		f'[ext_resource type="Texture2D" path="{RES}{texture}" id="1_sheet"]',
		'',
		f'[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_{name}"]',
		'texture = ExtResource("1_sheet")',
		f'texture_region_size = Vector2i({size}, {size})',
	]
	for x, y, code in cells:
		lines.append(f'{x}:{y}/0 = 0')
		lines.append(f'{x}:{y}/0/metadata/tile_name = "{code}"')
	lines += ['', '[resource]', f'tile_size = Vector2i({size}, {size})',
		f'sources/0 = SubResource("TileSetAtlasSource_{name}")', '']
	return '\n'.join(lines)


def tile_map_data(cells: list) -> str:
	raw = struct.pack('<H', 0) + b''.join(struct.pack('<hhHHHH', x, y, 0, c, r, 0) for x, y, c, r in cells)
	return base64.b64encode(raw).decode()


def lab_text(layers: list) -> str:
	"""layers: (node name, title, tileset file, tile px, cells (x, y, column, row)), one below the other."""
	out = ['[gd_scene format=4]', '']
	for i, layer in enumerate(layers):
		out.append(f'[ext_resource type="TileSet" path="{RES}{layer[2]}" id="{i + 1}_set"]')
	out += ['', '[node name="TileCompareLab" type="Node2D"]', '']
	cursor = 0
	width = 0
	for i, (node, title, _, size, cells) in enumerate(layers):
		y0 = min(y for _, y, _, _ in cells)
		y1 = max(y for _, y, _, _ in cells)
		top = cursor - y0 * 32
		out += [
			f'[node name="{node}Title" type="Label" parent="."]',
			f'offset_top = {cursor - 56}.0',
			'offset_right = 1400.0',
			f'offset_bottom = {cursor - 16}.0',
			'theme_override_font_sizes/font_size = 28',
			f'text = "{title}"',
			'',
			f'[node name="{node}" type="TileMapLayer" parent="."]',
		]
		if top:
			out.append(f'position = Vector2(0, {top})')
		if size == T:
			out.append('texture_filter = 1')
		out += [
			f'scale = Vector2({32 / size:g}, {32 / size:g})',
			f'tile_map_data = PackedByteArray("{tile_map_data(cells)}")',
			f'tile_set = ExtResource("{i + 1}_set")',
			'',
		]
		cursor = top + (y1 + 1 + LAB_ROW_GAP) * 32
		width = max(width, (max(x for x, _, _, _ in cells) + 1) * 32)
	out += [
		'[node name="Camera2D" type="Camera2D" parent="."]',
		f'position = Vector2({width // 2}, {cursor // 2})',
		'zoom = Vector2(0.4, 0.4)',
		'',
	]
	return '\n'.join(out)


def owner_cells(lab: Path, tileset: Path) -> list:
	"""(x, y, code) of what was painted on the lab's Zelda layer outside the figures, read with the
	tile names of the sheet it was painted with."""
	import re
	if not lab.exists() or not tileset.exists():
		return []
	scene = lab.read_text(encoding='utf-8')
	found = re.search(r'\[node name="Zelda".*?tile_map_data = PackedByteArray\("([^"]*)"\)', scene, re.S)
	if not found:
		return []
	names = {(int(m.group(1)), int(m.group(2))): m.group(3) for m in re.finditer(
		r'(\d+):(\d+)/0/metadata/tile_name = "([^"]+)"', tileset.read_text(encoding='utf-8'))}
	raw = base64.b64decode(found.group(1))
	rects = figure_rects()
	out = []
	for i in range((len(raw) - 2) // 12):
		x, y, _, ax, ay, _ = struct.unpack('<hhHHHH', raw[2 + i * 12:14 + i * 12])
		if any(fx <= x < fx + fw and fy <= y < fy + fh for fx, fy, fw, fh in rects):
			continue
		out.append((x, y, names.get((ax, ay), '?')))
	return out


def preview(layers: list, sheets: list) -> Image.Image:
	"""Every lab layer drawn with its sheet (64 px a tile), one below the other."""
	spans = [(min(y for _, y, _, _ in c), max(y for _, y, _, _ in c)) for *_, c in layers]
	cols = max(max(x for x, _, _, _ in c) for *_, c in layers) + 1
	out = Image.new('RGB', (cols * BIG, sum(y1 - y0 + 2 for y0, y1 in spans) * BIG), (24, 24, 28))
	top = 0
	for (*_, cells), s, (y0, y1) in zip(layers, sheets, spans):
		for x, y, c, r in cells:
			if x >= 0:
				out.paste(s.crop((c * BIG, r * BIG, (c + 1) * BIG, (r + 1) * BIG)), (x * BIG, (top + y - y0) * BIG))
		top += y1 - y0 + 2
	return out


def single_picture(tiles: dict, fitted: list) -> Image.Image:
	"""The guide's figure in every set side by side at 64 px a tile: Zelda's, then each fitted painting."""
	index, gx, gy = GUIDE[0]
	grid = parse(FIGURES[index][2])
	w, h = max(len(r) for r in grid), len(grid)
	zelda = np.zeros((h * T, w * T, 3), np.uint8)
	for y, row in enumerate(grid):
		for x, code in enumerate(row):
			if code is not None:
				zelda[y * T:(y + 1) * T, x * T:(x + 1) * T] = tiles[code]
	panels = [Image.fromarray(zelda).resize((w * BIG, h * BIG), Image.NEAREST)]
	panels += [Image.fromarray(p[gy * BIG:(gy + h) * BIG, gx * BIG:(gx + w) * BIG]) for p in fitted]
	gap = 20
	out = Image.new('RGB', (len(panels) * w * BIG + (len(panels) - 1) * gap, h * BIG), (30, 30, 36))
	for i, p in enumerate(panels):
		out.paste(p, (i * (w * BIG + gap), 0))
	return out


def sheets_picture(sheets: list) -> Image.Image:
	"""Every sheet as the TileMap palette shows it, one below the other at 64 px a tile."""
	gap = BIG // 2
	out = Image.new('RGBA', (max(s.width for s in sheets), sum(s.height for s in sheets) + gap * (len(sheets) - 1)),
		(24, 24, 28, 255))
	y = 0
	for s in sheets:
		out.alpha_composite(s, (0, y))
		y += s.height + gap
	return out.convert('RGB')


def main() -> None:
	ap = argparse.ArgumentParser()
	ap.add_argument('--force', action='store_true', help='rebuild the lab scene (keeps what was painted on its Zelda '
		'layer outside the figures, by tile name)')
	ap.add_argument('--no-carry', action='store_true', help='with --force: drop what was painted outside the figures')
	args = ap.parse_args()
	OUT.mkdir(parents=True, exist_ok=True)
	lab = OUT / 'tile_compare_lab.tscn'
	kept = [] if args.no_carry else owner_cells(lab, OUT / 'zelda_tileset.tres')
	cells = layout()
	zt = zelda_tiles()
	zelda = sheet(cells, zt, T)
	zelda.save(OUT / 'zelda-tiles-16px.png')
	(OUT / 'zelda_tileset.tres').write_text(tileset_text('zelda-tiles-16px.png', T, 'zelda', cells), encoding='utf-8')
	(ORIG / 'tile-layout.json').write_text(json.dumps({
		'note': 'The sheets layout: [column, row, code] of every tile (16 px Zelda, 64 px ours).',
		'columns': max(x for x, _, _ in cells) + 1, 'rows': max(y for _, y, _ in cells) + 1,
		'cells': [[x, y, c] for x, y, c in cells]}), encoding='utf-8')
	places: dict = {}
	for x, y, code in cells:
		places.setdefault(code, (x, y))
	lab_cells = [(x, y, *places[code]) for x, y, code in painted_cells()]
	lost = sorted({code for _, _, code in kept if code not in places})
	if lost:
		print(f'painted tiles no longer in the set, dropped: {lost}')
	owner = [(x, y, *places[code]) for x, y, code in kept if code in places]
	layers = [('Zelda', 'Zelda tiles (dev reference only, never in a world): 16 px, 32 units a tile',
		'zelda_tileset.tres', T, lab_cells + owner)]
	shown = [zelda.resize((zelda.width * ZOOM, zelda.height * ZOOM), Image.NEAREST)]
	levels_picture(zt).save(PAINTINGS / 'guide-levels.png')
	fitted = []
	for name, title, painting, plain in VARIANTS:
		guide = guide_picture(name, zt)
		sent = plain_guide(guide) if plain else guide
		sent.save(PAINTINGS / f'guide-{name}.png')
		numbered_guide(sent).save(PAINTINGS / f'guide-{name}-numbered.png')
		if not (PAINTINGS / painting).exists():
			print(f'no painted/grid/{painting} yet: {name} left out (its guide is painted/grid/guide-{name}.png)')
			continue
		pic = fitted_painting(PAINTINGS / painting, guide)
		Image.fromarray(pic).save(PAINTINGS / f'{name}-fitted.png')
		fitted.append(pic)
		s = painted_sheet(pic)
		s.save(OUT / f'{name}-tiles-64px.png')
		named = guide_cells()
		(OUT / f'{name}_tileset.tres').write_text(tileset_text(f'{name}-tiles-64px.png', BIG, name, named), encoding='utf-8')
		layers.append((name.capitalize(), f'{title}: 64 px, 32 units a tile', f'{name}_tileset.tres', BIG, guide_lab_cells()))
		shown.append(s)
	single_picture(zt, fitted).save(ORIG / 'tile-compare-single.png')
	sheets_picture(shown).save(ORIG / 'tile-compare-sheets.png')
	preview(layers, shown).save(ORIG / 'tile-compare-preview.png')
	if lab.exists() and not args.force:
		print(f'kept {lab.name} (it holds what was painted; --force rebuilds it)')
	else:
		lab.write_text(lab_text(layers), encoding='utf-8')
		print(f'wrote {lab.name} with {len(layers)} layers, {len(owner)} painted cells kept')
	print('sheets, tilesets and pictures written')


if __name__ == '__main__':
	main()
