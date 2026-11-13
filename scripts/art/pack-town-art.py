"""Packs the town set: houses, town buildings, garden pieces and street props (docs/godot/PROPS.md
"Town"; 2026-11-01, the West village).

Sources: asset/Originals/town/concepts/<sheet>-a.png, Magnific GPT 2.5 concept sheets (transparent
background, the interior mushroom furniture sheet as style reference) the owner picked, each a grid
of separate pictures, and <sheet>-a-up.jpg, the same sheet through Magnific's Precision upscaler
(2x, no alpha): its colour is used under the original's alpha, scaled 2x. A sheet without an
upscale uses its own colour. Each sheet is cut along its emptiest lines near the grid's lines; each
picture is trimmed and scaled to its size in game units at the art density of 2 px per unit and
written to godot/asset/MAPS/town/<group>/<name>.webp, with its scene
godot/game/scenes/objects/town/<group>/<name>.tscn (a scenery scene: no gameplay script, so the prop
palette builder lists it, the houses under "houses", the rest under "town" and "garden"). A scene
is rewritten only when it is missing, so hand tuning in the editor stays; --scenes rewrites them all.

- solid: a StaticBody2D whose foot box blocks (its width and depth in units, or for a building
  BUILDING_FOOT of its picture); the root at the bottom middle.
- free: a Node2D, nothing blocks.
- floor: a Node2D whose root is FLOOR_ROOT units below the picture's top, so whatever stands on it
  sorts above it (beds, patches, gravel, stepping stones).

Ambient loops (docs/assets/AMBIENT_ANIMATION.md, tier 1, procedural): a picture with an `ambient`
kind is written as 8 frames side by side (KIND_FRAMES: a kind with its own count) and its scene
plays them (AnimationPlayer "idle", random start): `goo` shimmers the lime goo, `glow` also pulses
it, `laundry` sways the cloth under the line, `bees` flies the bees round the hive, `bath` shimmers
the goo and sways the steam over it, `fountain` is the goo fountain (rings over its pool, bobbing
bubbles, the blob on top squashing, streaks down the stem, falling drops), `water` runs light
bands over blue water (the trough, the rain barrel and its stream), `sway` leans the scarecrow from
its pole's foot, `lamp` is the goo lamp (its jar glows and swings from its hook), `still` is a house whose only
motion is its banners and sign: HOUSE_CLOTH waves a house's banners from their top row, HOUSE_SIGNS
swings its hanging sign from its beam (HOUSE_PAD: empty columns on each side for a sign at the
picture's edge; the scene's Visual offset is that much further left). The frames move
only those pixels. The game draws a picture at about half its pixels, so a loop moves at least
4 px or a fifth of the brightness, or it reads as a still picture (owner, 2026-11-12: the first
fountain shimmer looked static).

A building with several homes (the duplex, the triplex row, the two flats, the twin mushroom house,
the town hall, the bathhouse) has a Marker2D `door-1`, `door-2` ... at the foot of each door (an
upper flat's: at the foot of its stair), where a door node (game/scripts/door.gd) goes, one per home.
The owner turned down the apartment house and the manor of the `large` sheet (2026-11-01). The
general store is the `store` sheet's (one picture, with a front door; 2026-11-12): the `civic`
sheet's was an open stall. The painted door of each house is a DoorFrame child of its scene, placed
by hand in the editor (docs/godot/CONVENTIONS.md "Door frames").

    python scripts/art/pack-town-art.py [--scenes] [--only=<sheet>,...]
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from game_webp import save_game_webp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/town/concepts"
ART = ROOT / "godot/asset/MAPS/town"
SCENES = ROOT / "godot/game/scenes/objects/town"
ART_RES = "res://asset/MAPS/town"
ALPHA_CUT = 40
PX_PER_UNIT = 2
FLOOR_ROOT = 12
FRAMES = 8
# an ambient kind with its own number of frames
KIND_FRAMES = {"fountain": 12}
# a building's foot box: this share of its picture's width, and of its height for the depth
BUILDING_FOOT = (0.86, 0.4)

# sheet -> (columns, rows, group, pictures in reading order; None: a picture not used)
# a picture: (name, size in units, "w" or "h" for what the size measures, kind, foot box in units
# (None: a building's), ambient kind, frames per second)
SHEETS = {
	"multi": (2, 2, "houses", [
		("duplex", 300, "w", "solid", None, "", 0),
		("triplex-row", 340, "w", "solid", None, "", 0),
		("two-flats", 230, "w", "solid", None, "", 0),
		("twin-mushroom-house", 300, "w", "solid", None, "", 0),
	]),
	"large": (2, 2, "houses", [
		("town-hall", 480, "w", "solid", None, "goo", 5),
		None,
		None,
		("goo-bathhouse", 420, "w", "solid", None, "bath", 6),
	]),
	"houses": (3, 2, "houses", [
		("jelly-dome-house", 220, "w", "solid", None, "goo", 5),
		("pumpkin-house", 230, "w", "solid", None, "", 0),
		("stump-house", 250, "w", "solid", None, "", 0),
		("snail-shell-house", 240, "w", "solid", None, "", 0),
		("timber-townhouse", 190, "w", "solid", None, "", 0),
		("drop-thatch-cottage", 230, "w", "solid", None, "", 0),
	]),
	"civic": (2, 2, "houses", [
		None,  # the general store of this sheet was an open stall: replaced by the `store` sheet's
		("inn", 360, "w", "solid", None, "still", 6),
		("gatekeeper-house", 300, "w", "solid", None, "still", 6),
		("game-booth", 280, "w", "solid", None, "still", 6),
	]),
	# the general store with a front door (owner, 2026-11-12: a building needs a door to have a room)
	"store": (1, 1, "houses", [
		("general-store", 300, "w", "solid", None, "still", 6),
	]),
	"garden": (4, 3, "garden", [
		("cabbage-bed", 120, "w", "floor", None, "", 0),
		("carrot-bed", 120, "w", "floor", None, "", 0),
		("pumpkin-patch", 120, "w", "floor", None, "", 0),
		("tulip-bed", 100, "w", "floor", None, "", 0),
		("hedge", 128, "w", "solid", (124, 26), "", 0),
		("hedge-corner", 128, "w", "solid", (100, 40), "", 0),
		("picket-fence", 128, "w", "solid", (124, 10), "", 0),
		("gravel-square", 120, "w", "floor", None, "", 0),
		("stepping-stones", 96, "w", "floor", None, "", 0),
		("herb-planter", 84, "w", "solid", (76, 30), "", 0),
		("berry-bush", 72, "w", "solid", (56, 26), "", 0),
		("scarecrow", 88, "h", "solid", (16, 10), "sway", 6),
	]),
	"props": (4, 4, "props", [
		("goo-fountain", 150, "w", "solid", (130, 56), "fountain", 10),
		("market-stall", 120, "w", "solid", (104, 34), "", 0),
		("signpost", 88, "h", "solid", (14, 10), "", 0),
		("notice-board", 100, "w", "solid", (84, 14), "", 0),
		("goo-lamp", 96, "h", "solid", (14, 10), "lamp", 6),
		("barrels", 70, "w", "solid", (62, 30), "", 0),
		("crates", 72, "w", "solid", (62, 30), "", 0),
		("bench", 84, "w", "solid", (72, 18), "", 0),
		("flower-cart", 92, "w", "solid", (70, 24), "", 0),
		("mailbox", 56, "h", "solid", (14, 10), "", 0),
		("slime-statue", 80, "h", "solid", (44, 22), "", 0),
		("clothesline", 128, "w", "free", None, "laundry", 5),
		("wheelbarrow", 80, "w", "solid", (56, 20), "", 0),
		("rain-barrel", 80, "h", "solid", (40, 24), "water", 8),
		("beehive", 64, "h", "solid", (36, 18), "bees", 10),
		("water-trough", 100, "w", "solid", (90, 26), "water", 8),
	]),
}

# building -> the foot of each of its doors, as shares of its picture's width and height (from the
# top-left corner)
DOORS: dict[str, list[tuple[float, float]]] = {
	"duplex": [(0.31, 0.97), (0.73, 0.97)],
	"triplex-row": [(0.25, 0.97), (0.55, 0.97), (0.85, 0.97)],
	# the ground flat's door, then the foot of the upper flat's stair
	"two-flats": [(0.26, 0.97), (0.86, 0.95)],
	"twin-mushroom-house": [(0.25, 0.97), (0.69, 0.97)],
	"town-hall": [(0.52, 0.98)],
	"goo-bathhouse": [(0.45, 0.97)],
}


def splits(profile: np.ndarray, parts: int) -> list[int]:
	"""The cuts between `parts` pictures: the emptiest index near each grid line."""
	n = len(profile)
	cuts = [0]
	for i in range(1, parts):
		centre = n * i // parts
		span = n // (parts * 4)
		cuts.append(centre - span + int(np.argmin(profile[centre - span:centre + span])))
	cuts.append(n)
	return cuts


def load_sheet(stem: str) -> Image.Image:
	"""The sheet at 2x: the upscale's colour under the original's alpha (the original alone when
	there is no upscale)."""
	original = Image.open(SRC / f"{stem}-a.png").convert("RGBA")
	upscale_path = SRC / f"{stem}-a-up.jpg"
	if not upscale_path.exists():
		return original
	colour = Image.open(upscale_path).convert("RGB")
	alpha = original.getchannel("A").resize(colour.size, Image.LANCZOS)
	colour.putalpha(alpha)
	return colour


def pictures(sheet: Image.Image, cols: int, rows: int) -> list[Image.Image]:
	alpha = np.asarray(sheet.getchannel("A"), dtype=np.float64)
	mask = alpha > ALPHA_CUT
	xs = splits(mask.sum(axis=0), cols)
	# each column's own row cuts: a tall picture in the next column must not cut through this one
	ys = [splits(mask[:, xs[c]:xs[c + 1]].sum(axis=1), rows) for c in range(cols)]
	out = []
	for r in range(rows):
		for c in range(cols):
			part = sheet.crop((xs[c], ys[c][r], xs[c + 1], ys[c][r + 1]))
			cut_alpha = part.getchannel("A").point(lambda a: a if a > ALPHA_CUT else 0)
			part.putalpha(cut_alpha)
			out.append(part.crop(cut_alpha.getbbox()))
	return out


# --- ambient frames -------------------------------------------------------------------------------

def hsv(array: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
	rgb = array[..., :3] / 255.0
	mx, mn = rgb.max(axis=2), rgb.min(axis=2)
	v = mx
	s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
	r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
	d = np.maximum(mx - mn, 1e-6)
	h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
	return h, s, v


# How far the loops move (picture pixels; the game draws a picture at about half its pixels, so
# less than 4 px or a fifth of the brightness does not read).
GOO_SHIMMER = 0.2
LAUNDRY_SWING = 6.0
BEE_LOOP = (5.0, 3.5)
STEAM_SWAY = 6.0


def goo_mask(array: np.ndarray) -> np.ndarray:
	"""The bright lime goo (not the darker leaves)."""
	h, s, v = hsv(array)
	return (h > 55) & (h < 100) & (s > 0.45) & (v > 0.55) & (array[..., 3] > 0)


def goo_frames(picture: Image.Image, pulse: float) -> list[Image.Image]:
	base = np.asarray(picture, dtype=np.float64)
	mask = goo_mask(base)
	height, width = mask.shape
	yy, xx = np.mgrid[0:height, 0:width]
	frames = []
	for k in range(FRAMES):
		t = 2 * math.pi * k / FRAMES
		# slow bands drifting across the goo, and the whole goo breathing with `pulse`
		wave = GOO_SHIMMER * np.sin(t + (xx * 0.9 + yy * 0.6) * 2 * math.pi / max(width, 1) * 3)
		gain = 1.0 + wave + pulse * math.sin(t)
		frame = base.copy()
		frame[..., :3] = np.where(mask[..., None], np.clip(base[..., :3] * gain[..., None], 0, 255), base[..., :3])
		frames.append(Image.fromarray(frame.astype(np.uint8), "RGBA"))
	return frames


def laundry_frames(picture: Image.Image) -> list[Image.Image]:
	"""The cloth below the line swings sideways, more the lower it hangs; posts and line stay."""
	base = np.asarray(picture)
	height, width = base.shape[:2]
	line = int(height * 0.22)
	floor = int(height * 0.72)  # the cloth ends above this row; the leaves at the posts' feet are below
	left, right = int(width * 0.205), int(width * 0.825)
	reach = int(math.ceil(LAUNDRY_SWING))
	frames = []
	for k in range(FRAMES):
		t = 2 * math.pi * k / FRAMES
		frame = base.copy()
		band = base[line:floor, left:right].copy()
		frame[line:floor, left:right] = 0
		for y in range(band.shape[0]):
			depth = y / max(band.shape[0] - 1, 1)
			shift = int(round(LAUNDRY_SWING * depth * math.sin(t + depth * 0.8)))
			# the cloth may swing a little past the band's sides, over nothing (it never wraps round)
			row = np.zeros((band.shape[1] + 2 * reach, 4), dtype=band.dtype)
			row[reach + shift:reach + shift + band.shape[1]] = band[y]
			target = frame[line + y, left - reach:right + reach]
			cloth = row[..., 3] > 0
			target[cloth] = row[cloth]
		frames.append(Image.fromarray(frame, "RGBA"))
	return frames


def components(mask: np.ndarray) -> list[np.ndarray]:
	"""The 8-connected parts of a mask, each as an array of (y, x)."""
	seen = np.zeros_like(mask, dtype=bool)
	out = []
	height, width = mask.shape
	for y0, x0 in zip(*np.nonzero(mask)):
		if seen[y0, x0]:
			continue
		stack = [(y0, x0)]
		seen[y0, x0] = True
		part = []
		while stack:
			y, x = stack.pop()
			part.append((y, x))
			for dy in (-1, 0, 1):
				for dx in (-1, 0, 1):
					ny, nx = y + dy, x + dx
					if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
						seen[ny, nx] = True
						stack.append((ny, nx))
		out.append(np.array(part))
	return out


def bee_frames(picture: Image.Image) -> list[Image.Image]:
	"""Each bee (a small part apart from the hive) flies a little loop of its own."""
	base = np.asarray(picture)
	parts = components(base[..., 3] > ALPHA_CUT)
	parts.sort(key=len, reverse=True)
	bees = [p for p in parts[1:] if len(p) < len(parts[0]) * 0.05]
	still = base.copy()
	for bee in bees:
		still[bee[:, 0], bee[:, 1]] = 0
	frames = []
	for k in range(FRAMES):
		frame = still.copy()
		for i, bee in enumerate(bees):
			t = 2 * math.pi * k / FRAMES + i * 2.1
			dx, dy = int(round(BEE_LOOP[0] * math.cos(t))), int(round(BEE_LOOP[1] * math.sin(2 * t)))
			ys = np.clip(bee[:, 0] + dy, 0, base.shape[0] - 1)
			xs = np.clip(bee[:, 1] + dx, 0, base.shape[1] - 1)
			frame[ys, xs] = base[bee[:, 0], bee[:, 1]]
		frames.append(Image.fromarray(frame, "RGBA"))
	return frames


## the steam: the rows above this share of the picture's height (above the chimneys' tops)
STEAM_TOP = 0.2


def steam_frames(frames: list[Image.Image]) -> list[Image.Image]:
	"""The steam over the chimneys sways sideways, more the higher it rises (whole rows, so its
	outline moves with it; nothing at the chimneys' tops moves)."""
	out = []
	for k, picture in enumerate(frames):
		base = np.asarray(picture)
		top = int(base.shape[0] * STEAM_TOP)
		frame = base.copy()
		t = 2 * math.pi * k / FRAMES
		for y in range(top):
			rise = 1 - y / max(top - 1, 1)
			shift = int(round(STEAM_SWAY * rise * math.sin(t + rise * 2.2)))
			if shift:
				frame[y] = np.roll(base[y], shift, axis=0)
		out.append(Image.fromarray(frame, "RGBA"))
	return out


# --- the goo fountain -----------------------------------------------------------------------------

# Where the fountain's parts are, as shares of its picture's width and height.
FOUNTAIN_POOL = (0.507, 0.476, 0.345, 0.185)  # the pool's middle and its half width and half height
FOUNTAIN_BLOB = (0.373, 0.627, 0.27, 0.185)  # the blob's left and right, the row its drips end at, the row it is whole above
FOUNTAIN_STEM = (0.455, 0.545, 0.2, 0.41)  # the stem's left, right, top and bottom
FOUNTAIN_BUBBLES = [(0.337, 0.316, 0.04), (0.65, 0.316, 0.04), (0.273, 0.424, 0.037), (0.71, 0.409, 0.034)]
FOUNTAIN_DROPS = [((0.413, 0.24), (0.413, 0.36)), ((0.573, 0.25), (0.573, 0.365))]  # from a drip's tip to the pool


def sample(image: np.ndarray, xs: np.ndarray, ys: np.ndarray) -> np.ndarray:
	"""`image` (float, premultiplied) read at the points (xs, ys), between pixels by weight."""
	height, width = image.shape[:2]
	xs = np.clip(xs, 0, width - 1.001)
	ys = np.clip(ys, 0, height - 1.001)
	x0, y0 = np.floor(xs).astype(int), np.floor(ys).astype(int)
	fx, fy = (xs - x0)[..., None], (ys - y0)[..., None]
	top = image[y0, x0] * (1 - fx) + image[y0, x0 + 1] * fx
	bottom = image[y0 + 1, x0] * (1 - fx) + image[y0 + 1, x0 + 1] * fx
	return top * (1 - fy) + bottom * fy


def smooth(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
	t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)


def grow(mask: np.ndarray, by: int) -> np.ndarray:
	"""`mask` grown by `by` pixels on every side."""
	out = mask.copy()
	for _ in range(by):
		wide = out.copy()
		wide[1:] |= out[:-1]
		wide[:-1] |= out[1:]
		wide[:, 1:] |= out[:, :-1]
		wide[:, :-1] |= out[:, 1:]
		out = wide
	return out


def row_fill(image: np.ndarray, mask: np.ndarray) -> np.ndarray:
	"""`image` with every `mask` pixel replaced by the nearest pixel of its row outside the mask
	(what shows behind a part that moves away)."""
	out = image.copy()
	height, width = mask.shape
	columns = np.arange(width)
	for y in range(height):
		row = mask[y]
		if not row.any():
			continue
		free = columns[~row]
		if len(free) == 0:
			out[y] = 0
			continue
		place = np.clip(np.searchsorted(free, columns[row]), 1, len(free) - 1)
		left, right = free[place - 1], free[place]
		nearest = np.where(columns[row] - left <= right - columns[row], left, right)
		out[y, row] = image[y, nearest]
	return out


def fountain_goo(array: np.ndarray) -> np.ndarray:
	"""The fountain's lime goo, its darker folds too."""
	h, s, v = hsv(array)
	return (h > 60) & (h < 115) & (s > 0.5) & (v > 0.45) & (array[..., 3] > 0)


def fountain_frames(picture: Image.Image) -> list[Image.Image]:
	"""The goo fountain alive: rings spread over the pool from the stem, the bubbles bob, the blob on
	top squashes and stretches, bright streaks run down the stem and a drop falls from each side
	drip into the pool. Only goo moves; the stone, moss and flowers keep their pixels."""
	count = KIND_FRAMES["fountain"]
	straight = np.asarray(picture, dtype=np.float64)
	height, width = straight.shape[:2]
	base = straight.copy()
	base[..., :3] *= base[..., 3:4] / 255.0  # premultiplied
	goo = fountain_goo(straight)
	yy, xx = np.mgrid[0:height, 0:width].astype(np.float64)

	# the pool: the goo inside the rim
	cx, cy, rx, ry = FOUNTAIN_POOL[0] * width, FOUNTAIN_POOL[1] * height, FOUNTAIN_POOL[2] * width, FOUNTAIN_POOL[3] * height
	ux, uy = (xx - cx) / rx, (yy - cy) / ry
	rho = np.sqrt(ux * ux + uy * uy)
	blob_bottom = FOUNTAIN_BLOB[2] * height
	pool = goo & (rho < 1.12) & (yy > blob_bottom + 4)
	pool_soft = pool.astype(np.float64)
	bubbles = [(bx * width, by * height, r * width) for bx, by, r in FOUNTAIN_BUBBLES]
	calm = np.zeros((height, width))  # 1 on a bubble: the rings do not bend it
	for bx, by, r in bubbles:
		calm = np.maximum(calm, 1 - smooth(r + 1, r + 5, np.hypot(xx - bx, yy - by)))

	# the blob and its drips, with their outline, and what is behind them
	left, right = FOUNTAIN_BLOB[0] * width, FOUNTAIN_BLOB[1] * width
	whole = FOUNTAIN_BLOB[3] * height
	blob = grow(goo & (xx > left) & (xx < right) & (yy < blob_bottom), 2) & (yy < blob_bottom)
	behind = row_fill(base, blob)
	blob_soft = np.zeros((height, width, 1))
	blob_soft[..., 0] = blob
	lift = 1 - smooth(whole, blob_bottom, yy)  # 1 on the blob, 0 where its drips end
	blob_x = (left + right) / 2

	# the stem
	stem = goo & (xx > FOUNTAIN_STEM[0] * width) & (xx < FOUNTAIN_STEM[1] * width) \
		& (yy > FOUNTAIN_STEM[2] * height) & (yy < FOUNTAIN_STEM[3] * height)
	stem_span = (FOUNTAIN_STEM[3] - FOUNTAIN_STEM[2]) * height

	bright = straight[goo & (straight[..., :3].sum(axis=2) > 500)][:, :3]
	light = bright.mean(axis=0) if len(bright) else np.array([190.0, 240.0, 70.0])
	dark = light * 0.42

	frames = []
	for k in range(count):
		t = k / count
		turn = 2 * math.pi * t
		# 1. rings over the pool, and the bubbles bobbing in it
		ring = np.sin(2 * math.pi * (2.1 * rho) - turn) * (1 - calm)
		push = 3.0 * ring * smooth(0.12, 0.3, rho)
		angle = np.arctan2(uy, ux)
		src_x = xx - push * np.cos(angle)
		src_y = yy - push * np.sin(angle) * (ry / rx)
		for i, (bx, by, r) in enumerate(bubbles):
			near = 1 - smooth(r + 1, r + 6, np.hypot(xx - bx, yy - by))
			src_y -= 3.4 * math.sin(turn + i * 1.9) * near
		moved = sample(base, src_x, src_y)
		from_pool = sample(pool_soft[..., None], src_x, src_y)[..., 0] > 0.5
		zone = (pool | (calm > 0)) & (from_pool | (calm > 0.05)) & (yy > blob_bottom + 4)
		frame = np.where(zone[..., None], moved, base)
		gain = 1 + 0.24 * np.sin(2 * math.pi * (2.1 * rho) - turn + 1.1) * (1 - calm)
		frame[..., :3] = np.where((zone & pool)[..., None], frame[..., :3] * gain[..., None], frame[..., :3])

		# 2. streaks running down the stem
		run = ((yy - FOUNTAIN_STEM[2] * height) / stem_span * 2 - t * 2) % 1.0
		streak = 1 + 0.5 * np.exp(-((run - 0.5) / 0.16) ** 2)
		frame[..., :3] = np.where(stem[..., None], frame[..., :3] * streak[..., None], frame[..., :3])

		# 3. the blob squashes and stretches (its drips' ends stay)
		squash = 0.09 * math.sin(turn)
		sx = 1 + squash * lift
		sy = 1 - squash * lift
		from_x = blob_x + (xx - blob_x) / sx
		from_y = blob_bottom + (yy - blob_bottom) / sy
		is_blob = sample(blob_soft, from_x, from_y)[..., 0] > 0.5
		wobbled = sample(frame, from_x, from_y)
		rest = np.where(blob[..., None], behind, frame)
		top = (yy < blob_bottom)
		frame = np.where((is_blob & top)[..., None], wobbled, np.where(top[..., None], rest, frame))

		frame = np.clip(frame, 0, 255)
		alpha = np.maximum(frame[..., 3:4], 1e-6)
		out = frame.copy()
		out[..., :3] = np.clip(frame[..., :3] * 255.0 / alpha, 0, 255)
		image = Image.fromarray(out.astype(np.uint8), "RGBA")

		# 4. a drop falls from each side drip, and a ring opens where it lands
		scale = 4
		layer = Image.new("RGBA", (width * scale, height * scale), (0, 0, 0, 0))
		draw = ImageDraw.Draw(layer)
		for i, ((x0, y0), (x1, y1)) in enumerate(FOUNTAIN_DROPS):
			u = (t + i * 0.5) % 1.0
			x = x0 * width
			if u < 0.55:
				fall = (u / 0.55) ** 2
				y = y0 * height + (y1 - y0) * height * fall
				half_w, half_h = 3.4 * min(1.0, 0.4 + u * 4), 4.4 * min(1.0, 0.4 + u * 4)
				box = [(x - half_w) * scale, (y - half_h) * scale, (x + half_w) * scale, (y + half_h) * scale]
				draw.ellipse(box, fill=tuple(int(c) for c in dark) + (255,))
				inner = [box[0] + 1.0 * scale, box[1] + 1.0 * scale, box[2] - 1.0 * scale, box[3] - 1.0 * scale]
				draw.ellipse(inner, fill=tuple(int(min(255, c * 1.05)) for c in light) + (255,))
			else:
				spread = (u - 0.55) / 0.45
				half_w, half_h = 4.0 + 10.0 * spread, 1.6 + 4.0 * spread
				y = y1 * height
				box = [(x - half_w) * scale, (y - half_h) * scale, (x + half_w) * scale, (y + half_h) * scale]
				shade = int(230 * (1 - spread) ** 1.2)
				draw.ellipse(box, outline=tuple(int(min(255, c * 1.18)) for c in light) + (shade,), width=int(1.8 * scale))
		image.alpha_composite(layer.resize((width, height), Image.LANCZOS))
		frames.append(image)
	return frames


# --- water, sway, the hanging lamp ----------------------------------------------------------------

def premultiplied(picture: Image.Image) -> np.ndarray:
	array = np.asarray(picture, dtype=np.float64).copy()
	array[..., :3] *= array[..., 3:4] / 255.0
	return array


def straight_image(array: np.ndarray) -> Image.Image:
	"""A premultiplied float array back as a picture."""
	array = np.clip(array, 0, 255)
	out = array.copy()
	out[..., :3] = np.clip(array[..., :3] * 255.0 / np.maximum(array[..., 3:4], 1e-6), 0, 255)
	return Image.fromarray(out.astype(np.uint8), "RGBA")


def water_frames(picture: Image.Image) -> list[Image.Image]:
	"""Light bands run down and across the blue water (a trough's surface, a barrel's and the
	stream that falls into it); nothing else changes."""
	base = np.asarray(picture, dtype=np.float64)
	h, s, v = hsv(base)
	water = (h > 170) & (h < 235) & (s > 0.22) & (v > 0.35) & (base[..., 3] > 0)
	height, width = water.shape
	yy, xx = np.mgrid[0:height, 0:width]
	frames = []
	for k in range(FRAMES):
		t = k / FRAMES
		phase = 2 * math.pi * ((yy + xx * 0.35) / 9.0 - t)
		gain = 1.0 + 0.24 * np.sin(phase) + 0.1 * np.sin(2 * phase + 1.3)
		frame = base.copy()
		frame[..., :3] = np.where(water[..., None], np.clip(base[..., :3] * gain[..., None], 0, 255), base[..., :3])
		frames.append(Image.fromarray(frame.astype(np.uint8), "RGBA"))
	return frames


## the scarecrow: the row its pole stands still below (a share of the picture's height), and how far
## its hat's top leans (picture pixels)
SWAY_FOOT = 0.86
SWAY_TOP = 6.0


def sway_frames(picture: Image.Image) -> list[Image.Image]:
	"""The figure leans from its pole's foot in the wind, more the higher up, its top a little
	behind its middle (a bend, not a rocking: the foot's rows keep their pixels)."""
	base = premultiplied(picture)
	height, width = base.shape[:2]
	yy, xx = np.mgrid[0:height, 0:width].astype(np.float64)
	foot = SWAY_FOOT * height
	up = np.clip((foot - yy) / foot, 0, 1)
	frames = []
	for k in range(FRAMES):
		turn = 2 * math.pi * k / FRAMES
		shift = SWAY_TOP * up ** 1.4 * np.sin(turn - up * 0.9)
		frames.append(straight_image(sample(base, xx - shift, yy)))
	return frames


## the goo lamp: where its jar hangs from (shares of the picture's width and height), the part of the
## picture that is the jar and its hanger (right of, below), and how far it swings (degrees)
LAMP_HOOK = (0.853, 0.208)
LAMP_JAR = (0.57, 0.214)
LAMP_SWING = 5.0


def lamp_frames(picture: Image.Image) -> list[Image.Image]:
	"""The jar glows brighter and dimmer and swings from its hook; the post and its arm stay."""
	height, width = picture.height, picture.width
	yy, xx = np.mgrid[0:height, 0:width].astype(np.float64)
	jar = (xx > LAMP_JAR[0] * width) & (yy > LAMP_JAR[1] * height)
	hook_x, hook_y = LAMP_HOOK[0] * width, LAMP_HOOK[1] * height
	frames = []
	for k, glowing in enumerate(goo_frames(picture, 0.26)):
		base = premultiplied(glowing)
		hanging = base * jar[..., None]
		rest = base * (~jar)[..., None]
		angle = math.radians(LAMP_SWING) * math.sin(2 * math.pi * k / FRAMES)
		cos, sin = math.cos(angle), math.sin(angle)
		dx, dy = xx - hook_x, yy - hook_y
		swung = sample(hanging, hook_x + dx * cos + dy * sin, hook_y - dx * sin + dy * cos)
		frames.append(straight_image(swung + rest * (1 - swung[..., 3:4] / 255.0)))
	return frames


# --- banners and hanging signs on the houses ------------------------------------------------------

# A house's cloth that waves: (left, top, right, bottom of the cloth in picture pixels, its colour,
# how far its foot swings in pixels). The cloth hangs from its top row.
HOUSE_CLOTH: dict[str, list[tuple[int, int, int, int, str, float]]] = {
	"gatekeeper-house": [(4, 172, 60, 294, "blue", 6.0), (143, 278, 206, 392, "blue", 5.0)],
	"town-hall": [(338, 501, 391, 598, "green", 5.0), (603, 501, 657, 598, "green", 5.0)],
	"game-booth": [(493, 147, 550, 268, "cream", 6.0)],
}
# A house's sign that swings from its beam: its parts (("circle", x, y, radius) or ("rect", left,
# top, right, bottom), picture pixels; drawn a little wide, the sign is their opaque pixels), the
# point it hangs from, how far it swings (degrees), the box the sign stays inside (left, top) and
# whether leaves in front of it (green pixels) are left out.
HOUSE_SIGNS: dict[str, list[tuple[list[tuple], tuple[float, float], float, tuple[int, int], bool]]] = {
	"inn": [([("circle", 655, 301, 69), ("rect", 623, 217, 648, 246), ("rect", 678, 225, 710, 246)], (665, 214), 4.0, (596, 214), True)],
	"general-store": [([("rect", 489, 224, 595, 332), ("rect", 506, 211, 529, 228), ("rect", 559, 224, 589, 228)], (547, 212), 4.0, (489, 209), False)],
}
# Empty columns added on each side of a house's picture (a sign that swings past its edge).
HOUSE_PAD = {"inn": 10, "general-store": 10}


def cloth_colour(array: np.ndarray, colour: str) -> np.ndarray:
	h, s, v = hsv(array)
	if colour == "blue":
		return (h > 195) & (h < 255) & (s > 0.3)
	if colour == "green":
		return (h > 80) & (h < 175) & (s > 0.2) & (v < 0.75)
	if colour == "leaf":
		return (h > 60) & (h < 150) & (s > 0.3)
	if colour == "cream":
		return ((s < 0.45) & (v > 0.7)) | (((h < 15) | (h > 345)) & (s > 0.5))
	raise ValueError(colour)


def cloth_mask(straight: np.ndarray, box: tuple[int, int, int, int], colour: str, pad: int) -> np.ndarray:
	"""The cloth inside `box`: each row from its first to its last pixel of the cloth's colour (its
	crest and trim are inside), a little wider for its outline."""
	left, top, right, bottom = box[0] + pad, box[1], box[2] + pad, box[3]
	mask = np.zeros(straight.shape[:2], dtype=bool)
	part = cloth_colour(straight[top:bottom, left:right], colour) & (straight[top:bottom, left:right, 3] > 0)
	for y in range(part.shape[0]):
		found = np.nonzero(part[y])[0]
		if len(found) >= 3:
			mask[top + y, left + found[0]:left + found[-1] + 1] = True
	wide = grow(mask, 2)
	wide[:top] = False
	return wide & (straight[..., 3] > 0)


def house_motion(frames: list[Image.Image], name: str) -> list[Image.Image]:
	"""A house's banners wave from their top row and its sign swings from its beam; the rest of the
	picture keeps its pixels."""
	cloths = HOUSE_CLOTH.get(name, [])
	signs = HOUSE_SIGNS.get(name, [])
	if not cloths and not signs:
		return frames
	pad = HOUSE_PAD.get(name, 0)
	first = np.asarray(frames[0], dtype=np.float64)
	height, width = first.shape[:2]
	yy, xx = np.mgrid[0:height, 0:width].astype(np.float64)
	cloth_masks = [cloth_mask(first, box[:4], box[4], pad) for box in cloths]
	sign_masks = []
	leaves = cloth_colour(first, "leaf")
	for parts, _hook, _degrees, corner, skip_leaves in signs:
		mask = np.zeros((height, width), dtype=bool)
		for part in parts:
			if part[0] == "circle":
				mask |= np.hypot(xx - (part[1] + pad), yy - part[2]) <= part[3]
			else:
				mask |= (xx >= part[1] + pad) & (xx <= part[3] + pad) & (yy >= part[2]) & (yy <= part[4])
		mask &= (xx >= corner[0] + pad) & (yy >= corner[1])
		if skip_leaves:
			mask &= ~leaves
		sign_masks.append(mask & (first[..., 3] > 0))
	out = []
	for k, picture in enumerate(frames):
		turn = 2 * math.pi * k / len(frames)
		frame = premultiplied(picture)
		for i, (box, mask) in enumerate(zip(cloths, cloth_masks)):
			top, bottom, reach = box[1], box[3], box[5]
			depth = np.clip((yy - top) / max(bottom - top, 1), 0, 1)
			shift = reach * depth ** 1.1 * np.sin(turn - depth * 2.4 + i * 1.7)
			soft = mask.astype(np.float64)[..., None]
			from_cloth = sample(soft, xx - shift, yy)[..., 0] > 0.5
			moved = sample(frame * soft, xx - shift, yy)
			behind = row_fill(frame, mask)
			rest = np.where(mask[..., None], behind, frame)
			frame = np.where(from_cloth[..., None], moved + rest * (1 - moved[..., 3:4] / 255.0), rest)
		for (parts, hook, degrees, _corner, _skip), mask in zip(signs, sign_masks):
			angle = math.radians(degrees) * math.sin(turn)
			cos, sin = math.cos(angle), math.sin(angle)
			dx, dy = xx - (hook[0] + pad), yy - hook[1]
			hanging = frame * mask[..., None]
			rest = frame * (~mask)[..., None]
			swung = sample(hanging, hook[0] + pad + dx * cos + dy * sin, hook[1] - dx * sin + dy * cos)
			frame = swung + rest * (1 - swung[..., 3:4] / 255.0)
		out.append(straight_image(frame))
	return out


def ambient_strip(picture: Image.Image, ambient: str, name: str = "") -> Image.Image:
	pad = HOUSE_PAD.get(name, 0)
	if pad:
		wider = Image.new("RGBA", (picture.width + 2 * pad, picture.height), (0, 0, 0, 0))
		wider.paste(picture, (pad, 0))
		picture = wider
	if ambient == "goo":
		frames = goo_frames(picture, 0.0)
	elif ambient == "bath":
		frames = steam_frames(goo_frames(picture, 0.0))
	elif ambient == "glow":
		frames = goo_frames(picture, 0.12)
	elif ambient == "laundry":
		frames = laundry_frames(picture)
	elif ambient == "bees":
		frames = bee_frames(picture)
	elif ambient == "fountain":
		frames = fountain_frames(picture)
	elif ambient == "water":
		frames = water_frames(picture)
	elif ambient == "sway":
		frames = sway_frames(picture)
	elif ambient == "lamp":
		frames = lamp_frames(picture)
	elif ambient == "still":
		frames = [picture] * FRAMES
	else:
		raise ValueError(ambient)
	frames = house_motion(frames, name)
	strip = Image.new("RGBA", (picture.width * len(frames), picture.height), (0, 0, 0, 0))
	for k, frame in enumerate(frames):
		strip.alpha_composite(frame, (k * picture.width, 0))
	return strip


# --- scenes ---------------------------------------------------------------------------------------

def door_markers(name: str, width: int, height: int) -> str:
	"""A Marker2D at the foot of each of the building's doors (the root is its bottom middle)."""
	text = ""
	for i, (fx, fy) in enumerate(DOORS.get(name, [])):
		x = (fx - 0.5) * width / PX_PER_UNIT
		y = -(1 - fy) * height / PX_PER_UNIT
		text += f'\n[node name="door-{i + 1}" type="Marker2D" parent="."]\nposition = Vector2({x:.0f}, {y:.0f})\n'
	return text


def scene_text(group: str, name: str, width: int, height: int, kind: str, foot: tuple[int, int] | None,
		ambient: str, fps: int) -> str:
	pad = HOUSE_PAD.get(name, 0) if ambient else 0
	offset_y = -FLOOR_ROOT * PX_PER_UNIT if kind == "floor" else -height
	count = KIND_FRAMES.get(ambient, FRAMES)
	frames = f"hframes = {count}\n" if ambient else ""
	visual = (
		'[node name="Visual" type="Sprite2D" parent="."]\n'
		"scale = Vector2(0.5, 0.5)\n"
		"centered = false\n"
		f"offset = Vector2({-width / 2 - pad:g}, {offset_y:g})\n"
		+ frames
		+ 'script = ExtResource("sheet")\n'
		f'sheet_path = "{ART_RES}/{group}/{name}.webp"\n'
	)
	resources = '[ext_resource type="Script" path="res://game/runtime/sheet_sprite.gd" id="sheet"]\n'
	subs = ""
	player = ""
	if ambient:
		resources += '[ext_resource type="Script" path="res://game/runtime/animation_player.gd" id="player"]\n'
		step = 1.0 / fps
		times = ", ".join(f"{k * step:g}" for k in range(count))
		subs += (
			'[sub_resource type="Animation" id="idle"]\n'
			'resource_name = "object.ambient.idle"\n'
			f"length = {count * step:g}\n"
			"loop_mode = 1\n"
			f"step = {step:g}\n"
			'tracks/0/type = "value"\n'
			"tracks/0/imported = false\n"
			"tracks/0/enabled = true\n"
			'tracks/0/path = NodePath("Visual:frame")\n'
			"tracks/0/interp = 1\n"
			"tracks/0/loop_wrap = false\n"
			"tracks/0/keys = {\n"
			f'"times": PackedFloat32Array({times}),\n'
			f'"transitions": PackedFloat32Array({", ".join(["1"] * count)}),\n'
			'"update": 1,\n'
			f'"values": [{", ".join(str(k) for k in range(count))}]\n'
			"}\n\n"
			'[sub_resource type="AnimationLibrary" id="library"]\n'
			'_data = {\n&"object.ambient.idle": SubResource("idle")\n}\n\n'
		)
		player = (
			'\n[node name="AmbientAnimation" type="AnimationPlayer" parent="."]\n'
			"process_mode = 3\n"
			'libraries/ = SubResource("library")\n'
			'autoplay = &"object.ambient.idle"\n'
			'script = ExtResource("player")\n'
			"randomize_start = true\n"
		)
	head = "[gd_scene format=3]\n\n" + resources + "\n"
	if kind != "solid":
		return head + subs + f'[node name="{name}" type="Node2D"]\ny_sort_enabled = true\n\n' + visual + player
	units_w, units_h = width / PX_PER_UNIT, height / PX_PER_UNIT
	box_w, depth = foot if foot else (round(units_w * BUILDING_FOOT[0]), round(units_h * BUILDING_FOOT[1]))
	return (
		head
		+ subs
		+ f'[sub_resource type="RectangleShape2D" id="foot"]\nsize = Vector2({box_w}, {depth})\n\n'
		+ f'[node name="{name}" type="StaticBody2D"]\ny_sort_enabled = true\ncollision_mask = 0\n\n'
		+ f'[node name="BodyShape" type="CollisionShape2D" parent="."]\nposition = Vector2(0, {-depth / 2:g})\nshape = SubResource("foot")\n\n'
		+ visual
		+ player
		+ door_markers(name, width, height)
	)


def main() -> None:
	rewrite = "--scenes" in sys.argv
	only = [arg.split("=", 1)[1].split(",") for arg in sys.argv if arg.startswith("--only=")]
	for stem, (cols, rows, group, items) in SHEETS.items():
		if only and stem not in only[0]:
			continue
		(ART / group).mkdir(parents=True, exist_ok=True)
		(SCENES / group).mkdir(parents=True, exist_ok=True)
		for picture, item in zip(pictures(load_sheet(stem), cols, rows), items):
			if item is None:
				continue
			name, units, along, kind, foot, ambient, fps = item
			target = units * PX_PER_UNIT
			factor = target / (picture.height if along == "h" else picture.width)
			picture = picture.convert("RGBa").resize(
				(max(1, round(picture.width * factor)), max(1, round(picture.height * factor))), Image.LANCZOS).convert("RGBA")
			out = ambient_strip(picture, ambient, name) if ambient else picture
			save_game_webp(out, ART / group / f"{name}.webp")
			scene = SCENES / group / f"{name}.tscn"
			if rewrite or not scene.exists():
				scene.write_text(scene_text(group, name, picture.width, picture.height, kind, foot, ambient, fps),
					encoding="utf-8", newline="\n")
			print(f"{group}/{name}: {picture.width} x {picture.height} px ({kind}{', ' + ambient if ambient else ''})")


if __name__ == "__main__":
	main()
