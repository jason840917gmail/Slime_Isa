"""Cuts, cleans and lines up the reworked bosses' animation frames (the Orb-Weaver Matron and the
Crystal Colossus, step 2 of the dungeons 2 and 3 rework) and previews them as GIFs.

Sources: asset/Originals/dungeon-kit/bosses/<boss>/frames/*.png, Magnific GPT 2.5 sheets of four
frames in a 2 x 2 grid (reading order), prompts in the README beside them.

Each sheet is cut along its emptiest middle column, then each half along its emptiest middle row;
each frame is cleared of the model's faint background haze (alpha under ALPHA_CUT, and light
see-through lines) and trimmed. The frames of one animation are then lined up on the part of the body
that does not move (`stable`: the top part of the picture, e.g. the abdomen of the hanging Matron,
the head and shoulders of the walking Colossus): each frame is shifted to match frame 1 there by
cross-correlation, so only the moving parts move.

The Colossus's sheets come twice, with his plates and as a plate-less edit: his frames are a bare
body and a layer per plate ("the Colossus's plates as layers" below), so any plate can be cold, hot
or gone in any frame; the crystal under each plate is cut from the bare body live and dead ("the
Colossus's crystals" below), so any crystal can be live or dark in any frame.

usage:
    python scripts/art/boss_frames.py preview [<animation> ...]
        output/boss-rework/frames/<animation>.gif (at ZOOM times game size, on a dark floor, the
        slime beside it) and <animation>-strip.png; the Colossus's as <animation>-plates.gif (five
        plate states side by side) and <animation>-layers.png. No names: every animation.
    python scripts/art/boss_frames.py contact [matron|colossus]
        <boss>-contact.png: every frame of every animation at game size.
    python scripts/art/boss_frames.py showcase [matron|colossus]
        <boss>-showcase.gif and .webp: every animation playing at once (the Colossus's breastplate
        going cold, hot and bursting), for the owner.
Writes only previews (output/ is git-ignored); packing the frames into the game's sheets comes with
the fights. Needs Pillow and numpy. Sources and prompts: the README in each boss's folder.
"""
from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "asset" / "Originals" / "dungeon-kit" / "bosses"
PREVIEW = REPO / "output" / "boss-rework" / "frames"
SLIME_SHEET = REPO / "godot" / "asset" / "characters" / "256x256-tile_8x8-slime-v2-page-1.webp"
SLIME_GAME_SCALE = 0.28125  # player_slime.tscn, Visual.scale

ALPHA_CUT = 48
HAZE_ALPHA = 150
HAZE_LUMA = 185
HAZE_OPAQUE = 235
ZOOM = 1.5
FLOOR = (55, 55, 63)
GRID = (70, 70, 80)
CELL = 64


# One game scale per boss, so every sheet of his shows him at one size: the first frame of `sheet`
# measures `size` game px along `axis` (his size in the game today: the Matron hanging about 190 wide,
# the Colossus walking about 180 tall). The sheets are drawn at about one size, each a 2 x 2 grid on
# 1024 px; `Animation.rel` corrects one that came out bigger or smaller.
BOSS_SCALE = {
	"matron": ("matron-hang.png", 190.0, "w"),
	"colossus": ("colossus-walk-down.png", 180.0, "h"),
}

# How the frames of an animation are lined up on frame 1: a region (x0, y0, x1, y1, as fractions of
# each frame) of the part that holds still, matched by cross-correlation; "bottom" stands them on
# one line, centred; "centre" centres their boxes.
TOP = (0.0, 0.0, 1.0, 0.42)


@dataclass
class Animation:
	boss: str
	sheet: str
	stable: object
	fps: float
	# Frame order to play (indices into the sheet's four), e.g. holds or a ping-pong.
	order: tuple[int, ...] = (0, 1, 2, 3)
	rel: float = 1.0
	# Frames drawn mirrored (a frame the model turned the wrong way).
	mirror: tuple[int, ...] = ()
	note: str = ""
	# Packing: the sheet's frames that ship (in this order), and the point the game places at the
	# body's origin: "top" (the top middle: a hanging Matron's thread), "centre" or "bottom" (the
	# bottom middle: the feet or the belly on the floor) of frame `anchor_frame`'s picture.
	use: tuple[int, ...] = (0, 1, 2, 3)
	anchor: str = "bottom"
	anchor_frame: int = 0
	# The packed animation's name in the game (the manifest key); the sheet's name without the boss.
	key: str = ""


ANIMATIONS: dict[str, Animation] = {
	"matron-hang": Animation("matron", "matron-hang.png", (0.0, 0.0, 1.0, 0.45), 6, note="hanging idle, a loop",
		anchor="top"),
	"matron-spit": Animation("matron", "matron-spit.png", (0.0, 0.0, 1.0, 0.40), 8, (0, 0, 1, 1, 1, 2, 2, 3, 3),
		note="the spit: wind-up, charge, spit, recover", anchor="top"),
	"matron-dive": Animation("matron", "matron-dive.png", "centre", 8, (0, 1, 2, 2, 3, 3, 3),
		note="the dive: let go, falling, legs flung wide, landed", anchor="centre"),
	"matron-rammed": Animation("matron", "matron-rammed.png", "centre", 8, (0, 0, 1, 2, 3, 3, 3),
		note="caught by the ram from the left: struck, flung, tumbling, on her back", anchor="centre"),
	"matron-on-back": Animation("matron", "matron-on-back.png", (0.3, 0.3, 0.7, 0.7), 7, note="on her back kicking, a loop",
		anchor="centre"),
	"matron-climb": Animation("matron", "matron-climb.png", (0.0, 0.45, 1.0, 1.0), 7, note="climbing her thread from behind, a loop",
		anchor="centre"),
	"matron-spin": Animation("matron", "matron-spin.png", (0.3, 0.0, 0.7, 0.2), 4, (0, 1, 2, 3, 3, 3),
		note="spinning her cocoon round herself", anchor="top"),
	"matron-cocoon": Animation("matron", "matron-cocoon.png", "bottom", 3, (1, 2, 1, 2, 3, 3),
		note="the cocoon knocked down whole, straining, torn (frame 0 unused)", use=(1, 2, 3), anchor="centre", anchor_frame=1,
		# drawn filling its picture: lying, about as long as the hanging cocoon (~210 units) is tall
		rel=0.75),
	"matron-dazed": Animation("matron", "matron-dazed.png", "centre", 6, (0, 1, 2, 1, 2, 3, 3, 1),
		note="dropping out of the torn cocoon, dazed (two), flinching", anchor="centre", anchor_frame=1),
	"colossus-walk-down": Animation("colossus", "colossus-walk-down.png", TOP, 6, note="walking toward the viewer"),
	"colossus-walk-side": Animation("colossus", "colossus-walk-side.png", TOP, 6, note="walking to the right (mirrored for the left)"),
	"colossus-walk-up": Animation("colossus", "colossus-walk-up.png", TOP, 6, note="walking away"),
	"colossus-stomp": Animation("colossus", "colossus-stomp.png", "bottom", 5, (0, 1, 1, 2, 2, 2, 3, 3),
		note="the stomp: raise, reared, slam, staggered"),
	"colossus-leap-cling": Animation("colossus", "colossus-leap-cling.png", "centre", 4, (0, 1, 2, 3, 2, 3),
		note="crouch, leap, clinging (two)"),
	"colossus-fall": Animation("colossus", "colossus-fall.png", "centre", 4, (0, 1, 2, 3, 2, 3), mirror=(3,),
		note="falling off the wall, crashed, on his back (two)", anchor="centre", anchor_frame=2),
}


# --- cutting and cleaning -------------------------------------------------------------------------

def clean(im: Image.Image) -> Image.Image:
	a = np.asarray(im.convert("RGBA")).astype(np.float32)
	alpha = a[..., 3]
	luma = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
	alpha = np.clip((alpha - ALPHA_CUT) * 255.0 / (255.0 - ALPHA_CUT), 0, 255)
	alpha[(a[..., 3] < HAZE_ALPHA) & (luma > HAZE_LUMA)] = 0
	a[..., 3] = alpha
	return Image.fromarray(a.astype(np.uint8), "RGBA")


def trim(im: Image.Image, pad: int = 4) -> Image.Image:
	a = np.asarray(im)[..., 3] > 100
	rows = np.nonzero(a.sum(axis=1) >= 2)[0]
	cols = np.nonzero(a.sum(axis=0) >= 2)[0]
	x0, x1 = max(cols.min() - pad, 0), min(cols.max() + 1 + pad, im.width)
	y0, y1 = max(rows.min() - pad, 0), min(rows.max() + 1 + pad, im.height)
	return im.crop((x0, y0, x1, y1))


def emptiest(profile: np.ndarray, lo: int, hi: int) -> int:
	window = profile[lo:hi]
	candidates = np.nonzero(window <= window.min() + 1e-6)[0] + lo
	return int(candidates[np.argmin(np.abs(candidates - (lo + hi) / 2))])


def flood(mask: np.ndarray, seeds: np.ndarray) -> np.ndarray:
	"""The pixels of `mask` joined to `seeds` (4-connected), grown in numpy steps."""
	reached = seeds & mask
	while True:
		grown = reached.copy()
		for _ in range(16):
			step = grown.copy()
			step[1:, :] |= grown[:-1, :]
			step[:-1, :] |= grown[1:, :]
			step[:, 1:] |= grown[:, :-1]
			step[:, :-1] |= grown[:, 1:]
			grown = step & mask
		if grown.sum() == reached.sum():
			return grown
		reached = grown


def clear_white_ground(im: Image.Image) -> Image.Image:
	"""A plate-less edit: most came back transparent (cleaned as usual), one (walk-down) with a
	see-through light grey haze over the whole background instead. There the figure is the opaque part
	(alpha over HAZE_OPAQUE; the haze stays under it) and the rest is cleared."""
	a = np.asarray(im.convert("RGBA")).astype(np.float32)
	if (a[..., 3] < 10).mean() > 0.05:
		return clean(im)
	rgb = a[..., :3]
	hi, lo = rgb.max(axis=2), rgb.min(axis=2)
	luma = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
	light = (luma > 170) & ((hi - lo) < 0.2 * np.maximum(hi, 1))
	figure = a[..., 3] > HAZE_OPAQUE
	# Whole patches of haze stay opaque in the gaps between arms and legs: a bare golem has no big
	# light grey part, so every light patch bigger than a glint goes.
	for patch in _parts(light & figure, 160, 3, 5, 40):
		figure &= ~_grow(patch, 1)
	# The haze lies light round the outline: peel light pixels off the figure's edge, a pixel at a time.
	for _ in range(4):
		inner = figure.copy()
		inner[1:, :] &= figure[:-1, :]
		inner[:-1, :] &= figure[1:, :]
		inner[:, 1:] &= figure[:, :-1]
		inner[:, :-1] &= figure[:, 1:]
		figure &= ~(figure & ~inner & light)
	out = a.copy()
	out[..., 3] = np.where(figure, 255, 0)
	return Image.fromarray(out.astype(np.uint8), "RGBA")


def cut_grid(path: Path, white_ground: bool = False) -> list[Image.Image]:
	"""The four frames of a 2 x 2 sheet in reading order, cleaned and trimmed."""
	im = clear_white_ground(Image.open(path)) if white_ground else clean(Image.open(path))
	alpha = np.asarray(im)[..., 3].astype(np.float32)
	w, h = im.size
	x = emptiest(alpha.sum(axis=0), int(w * 0.38), int(w * 0.62))
	halves = [(0, x), (x, w)]
	rows = [emptiest(alpha[:, x0:x1].sum(axis=1), int(h * 0.36), int(h * 0.68)) for x0, x1 in halves]
	frames = []
	for top in (True, False):
		for (x0, x1), y in zip(halves, rows):
			frames.append(trim(im.crop((x0, 0, x1, y) if top else (x0, y, x1, h))))
	return frames


def scaled(im: Image.Image, factor: float) -> Image.Image:
	return im.resize((max(1, round(im.width * factor)), max(1, round(im.height * factor))), Image.LANCZOS)


# --- lining up ------------------------------------------------------------------------------------

WHOLE = (0.0, 0.0, 1.0, 1.0)


def _signal(im: Image.Image, size: tuple[int, int], region: tuple[float, float, float, float]) -> np.ndarray:
	"""The frame's alpha-weighted brightness on a canvas of `size`, only inside `region`."""
	a = np.asarray(im).astype(np.float32)
	sig = (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]) * (a[..., 3] / 255.0) + a[..., 3] * 0.5
	keep = np.zeros_like(sig, bool)
	x0, y0, x1, y1 = region
	keep[int(im.height * y0):int(im.height * y1), int(im.width * x0):int(im.width * x1)] = True
	sig[~keep] = 0
	out = np.zeros(size[::-1], np.float32)
	out[: sig.shape[0], : sig.shape[1]] = sig
	return out - out[out > 0].mean() * (out > 0)


def shift_onto(ref: Image.Image, im: Image.Image, region=WHOLE) -> tuple[int, int]:
	"""(dx, dy) to add to `im`'s top-left so its stable part best covers `ref`'s (both trimmed)."""
	size = (max(ref.width, im.width) * 2, max(ref.height, im.height) * 2)
	a = np.fft.rfft2(_signal(ref, size, region))
	b = np.fft.rfft2(_signal(im, size, region))
	corr = np.fft.irfft2(a * np.conj(b), s=size[::-1])
	dy, dx = np.unravel_index(int(np.argmax(corr)), corr.shape)
	if dy > size[1] // 2:
		dy -= size[1]
	if dx > size[0] // 2:
		dx -= size[0]
	return int(dx), int(dy)


def shifts_for(frames: list[Image.Image], stable) -> list[tuple[int, int]]:
	"""Where each frame's top-left goes, relative to frame 1's, for a lining-up mode."""
	if stable == "bottom":
		return [((frames[0].width - f.width) // 2, frames[0].height - f.height) for f in frames]
	if stable == "centre":
		return [((frames[0].width - f.width) // 2, (frames[0].height - f.height) // 2) for f in frames]
	return [(0, 0)] + [shift_onto(frames[0], f, stable) for f in frames[1:]]


def place_all(frames: list[Image.Image], shifts: list[tuple[int, int]]) -> list[Image.Image]:
	x0 = min(dx for dx, _ in shifts)
	y0 = min(dy for _, dy in shifts)
	x1 = max(dx + f.width for (dx, _), f in zip(shifts, frames))
	y1 = max(dy + f.height for (_, dy), f in zip(shifts, frames))
	out = []
	for (dx, dy), f in zip(shifts, frames):
		c = Image.new("RGBA", (x1 - x0, y1 - y0))
		c.alpha_composite(f, (dx - x0, dy - y0))
		out.append(c)
	return out


def boss_scale(boss: str) -> float:
	"""Game px per source px for every sheet of this boss."""
	sheet, size, axis = BOSS_SCALE[boss]
	first = cut_grid(SRC / boss / "frames" / sheet)[0]
	return size / (first.width if axis == "w" else first.height)


def raw_frames(name: str, white_ground: bool = False, sheet: str = "") -> list[Image.Image]:
	anim = ANIMATIONS[name]
	raw = cut_grid(SRC / anim.boss / "frames" / (sheet or anim.sheet), white_ground)
	return [f.transpose(Image.FLIP_LEFT_RIGHT) if i in anim.mirror else f for i, f in enumerate(raw)]


def frames_of(name: str) -> tuple[list[Image.Image], float]:
	"""The lined-up frames of an animation (source px) and the game scale to draw them at."""
	anim = ANIMATIONS[name]
	raw = raw_frames(name)
	return place_all(raw, shifts_for(raw, anim.stable)), boss_scale(anim.boss) * anim.rel


# --- the Colossus's plates as layers --------------------------------------------------------------
#
# Each Colossus sheet comes twice: with his three plates (`plated`) and the same sheet edited with
# them gone, bare rose quartz in their sockets (`bare`). The game draws the bare body and lays each
# plate still on him over it. A plate's layer is the plated frame's pixels inside that plate's mask:
# the plate (pale cyan, low saturation, bright), its holes filled, grown by PLATE_GROW to take its dark
# outline and a ring of the rock around it (which hides the bare socket's edge), feathered by
# PLATE_FEATHER. Plates are named by the screen side they sit on when he faces the viewer: L (his
# right shoulder), C (the breastplate), R (his left shoulder); seen from behind L is on the right.

PLATES = "LCR"
PLATE_GROW = 11  # source px
PLATE_FEATHER = 4
PLATE_MIN_AREA = 0.012  # of the frame's opaque area


@dataclass
class Armour:
	# The plate-less edit of the animation's sheet.
	bare: str
	# Per frame: "front", "back", "right" (profile facing right: the near plate is L, the chest edge C),
	# "lying" (on his back, head to the left: L below his head, R above).
	views: tuple[str, ...]
	# Bare frames the model drew without a socket: frame → (plate, the frame whose bare socket is
	# copied in, inside the plate's region once they are lined up).
	borrow: dict = None


ARMOUR: dict[str, Armour] = {
	"colossus-walk-down": Armour("colossus-walk-down-bare.png", ("front",) * 4, {2: ("C", 3)}),
	"colossus-walk-side": Armour("colossus-walk-side-bare.png", ("right",) * 4),
	"colossus-walk-up": Armour("colossus-walk-up-bare.png", ("back",) * 4),
	"colossus-stomp": Armour("colossus-stomp-bare.png", ("front",) * 4),
	"colossus-leap-cling": Armour("colossus-leap-cling-bare.png", ("front", "back", "back", "back")),
	"colossus-fall": Armour("colossus-fall-bare.png", ("front", "lying", "lying", "lying")),
}


def _components(mask: np.ndarray) -> list[np.ndarray]:
	"""The connected parts of a boolean mask (4-connected), largest first."""
	left = mask.copy()
	parts = []
	while left.any():
		seed = np.zeros_like(left)
		seed[np.unravel_index(int(np.argmax(left)), left.shape)] = True
		part = flood(left, seed)
		parts.append(part)
		left &= ~part
	return sorted(parts, key=lambda p: -int(p.sum()))


def _fill_holes(part: np.ndarray) -> np.ndarray:
	padded = np.pad(~part, 1, constant_values=True)
	seed = np.zeros_like(padded)
	seed[0, 0] = True
	return ~flood(padded, seed)[1:-1, 1:-1]


def _grow(mask: np.ndarray, px: int) -> np.ndarray:
	from PIL import ImageFilter
	im = Image.fromarray(np.where(mask, 255, 0).astype(np.uint8), "L")
	return np.asarray(im.filter(ImageFilter.MaxFilter(px * 2 + 1))) > 0


def _feather(mask: np.ndarray, px: int) -> np.ndarray:
	from PIL import ImageFilter
	im = Image.fromarray(np.where(mask, 255, 0).astype(np.uint8), "L")
	return np.asarray(im.filter(ImageFilter.GaussianBlur(px))).astype(np.float32) / 255.0


def _parts(mask: np.ndarray, floor: float, close: int, open_: int, most: int) -> list[np.ndarray]:
	"""The big parts of a mask: thin lines inside closed, small specks opened away, each part grown
	back over the pixels it came from and its holes filled, largest first."""
	from PIL import ImageFilter
	im = Image.fromarray(np.where(mask, 255, 0).astype(np.uint8), "L")
	closed = im.filter(ImageFilter.MaxFilter(close)).filter(ImageFilter.MinFilter(close))
	opened = np.asarray(closed.filter(ImageFilter.MinFilter(open_))) > 0
	closed_mask = np.asarray(closed) > 0
	parts = []
	for core in _components(opened):
		if core.sum() * 1.6 < floor:
			break
		part = _grow(core, open_ // 2 + 2) & closed_mask
		if part.sum() >= floor:
			parts.append(_fill_holes(part))
		if len(parts) == most:
			break
	return parts


def _side_of(centre: tuple[float, float], figure: tuple[float, float, float, float], view: str, have: set[str]) -> str:
	"""Which plate a socket with no plate drawn over it belongs to, by where it sits on the figure."""
	x, y = centre
	x0, y0, x1, y1 = figure
	u = (x - x0) / max(x1 - x0, 1)
	if view == "front":
		order = ["C"] if 0.35 < u < 0.65 else []
		order += ["L", "R"] if u < 0.5 else ["R", "L"]
	elif view == "back":
		order = ["R", "L"] if u < 0.5 else ["L", "R"]
	elif view == "right":
		order = ["L", "C"]
	else:
		order = ["C", "R", "L"]
	return next((k for k in order if k not in have), "")


def plate_masks(frame: Image.Image, view: str, bare: Image.Image | None = None) -> dict[str, np.ndarray]:
	"""Each plate's region (bool, the frame's size), before growing: the plate seen on the plated
	frame, joined by the bare frame's rose-quartz socket under it. A socket with no plate seen over it
	(a plate hidden behind an arm) is named by where it sits and its region taken alone."""
	a = np.asarray(frame).astype(np.float32)
	rgb = a[..., :3]
	hi, lo = rgb.max(axis=2), rgb.min(axis=2)
	luma = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
	pale = (a[..., 3] > 128) & (luma > 110) & ((hi - lo) < 0.42 * np.maximum(hi, 1)) & (rgb[..., 2] >= rgb[..., 0] - 14)
	floor = PLATE_MIN_AREA * float((a[..., 3] > 128).sum())
	# The plates' facet lines are dark and thin: a closing joins each plate whole; highlights on the
	# blue crystals are pale too, but small: an opening drops them.
	parts = _parts(pale, floor, 7, 9, 3)
	if not parts:
		return {}
	named = _name_plates(parts, frame, view)
	if bare is None:
		return named
	b = np.asarray(bare).astype(np.float32)
	pink = (b[..., 3] > 128) & (b[..., 0] > 150) & (b[..., 0] > b[..., 1] + 55) & (b[..., 2] > b[..., 1] + 10)
	ys, xs = np.nonzero(a[..., 3] > 128)
	figure = (float(xs.min()), float(ys.min()), float(xs.max()), float(ys.max()))
	for socket in _parts(pink, floor * 0.15, 5, 5, 6):
		near = [k for k, m in named.items() if (_grow(m, 12) & socket).any()]
		if near:
			best = max(near, key=lambda k: int((_grow(named[k], 12) & socket).sum()))
			named[best] = named[best] | socket
			continue
		centre = (float(np.nonzero(socket)[1].mean()), float(np.nonzero(socket)[0].mean()))
		key = _side_of(centre, figure, view, set(named))
		if key:
			named[key] = socket
	return named


def _name_plates(parts: list[np.ndarray], frame: Image.Image, view: str) -> dict[str, np.ndarray]:
	centres = [(float(np.nonzero(p)[1].mean()), float(np.nonzero(p)[0].mean()), int(p.sum())) for p in parts]
	named: dict[str, np.ndarray] = {}
	if view in ("front", "back"):
		# In front the breastplate is the lowest plate in the middle third of the figure (an arm may
		# hide a shoulder plate, so it is found by place, not by count); from behind only shoulders.
		ys, xs = np.nonzero(np.asarray(frame)[..., 3] > 128)
		x0, x1 = float(xs.min()), float(xs.max())
		u = [(c[0] - x0) / max(x1 - x0, 1) for c in centres]
		order = list(range(len(parts)))
		if view == "front":
			middle = [i for i in order if 0.3 < u[i] < 0.7]
			if middle:
				chest = max(middle, key=lambda i: centres[i][1])
				if len(parts) == 3 or all(centres[chest][1] >= centres[j][1] for j in order if j != chest):
					named["C"] = parts[chest]
					order.remove(chest)
		for i in order:
			left = u[i] < 0.5
			side = ("L" if left else "R") if view == "front" else ("R" if left else "L")
			if side in named:
				side = "R" if side == "L" else "L"
			named[side] = parts[i]
	elif view == "right":
		# The near shoulder plate is the bigger, the breastplate's edge in front of it on his chest.
		named["L"] = parts[0]
		if len(parts) > 1:
			named["C"] = parts[1]
	elif view == "lying":
		chest = 0  # the breastplate is the biggest
		named["C"] = parts[chest]
		rest = sorted(range(1, len(parts)), key=lambda i: centres[i][1])
		for i, side in zip(rest, ["R", "L"] if len(rest) == 2 else (["L"] if rest and centres[rest[0]][1] > centres[0][1] else ["R"])):
			named[side] = parts[i]
	return named


def _match_colours(src: np.ndarray, ref: np.ndarray, where: np.ndarray) -> np.ndarray:
	out = src.copy()
	for c in range(3):
		s, r = src[..., c][where], ref[..., c][where]
		if s.size < 100:
			return out
		out[..., c] = np.clip((src[..., c] - s.mean()) * (r.std() / max(s.std(), 1e-3)) + r.mean(), 0, 255)
	return out


def armour_frames(name: str) -> tuple[list[Image.Image], list[dict[str, Image.Image]], float]:
	"""The bare body frames and each frame's plate layers (same canvas), lined up, and the game scale."""
	anim, arm = ANIMATIONS[name], ARMOUR[name]
	plated = raw_frames(name)
	bare = raw_frames(name, white_ground=True, sheet=arm.bare)
	scale = boss_scale(anim.boss) * anim.rel
	bodies, layers = [], []
	for p, b, view in zip(plated, bare, arm.views):
		# The bare edit is the same picture redrawn: bring it to the plated frame's height and place.
		b = scaled(b, p.height / b.height)
		dx, dy = shift_onto(p, b)
		canvas = Image.new("RGBA", p.size)
		canvas.alpha_composite(b, (max(dx, 0), max(dy, 0)), (max(-dx, 0), max(-dy, 0)))
		masks = plate_masks(p, view, canvas)
		pa = np.asarray(p).astype(np.float32)
		ba = np.asarray(canvas).astype(np.float32)
		near = np.zeros(p.size[::-1], bool)
		for m in masks.values():
			near |= _grow(m, PLATE_GROW + 6)
		rock = (pa[..., 3] > 200) & (ba[..., 3] > 200) & ~near
		ba[..., :3] = _match_colours(ba[..., :3], pa[..., :3], rock)
		bodies.append(Image.fromarray(ba.astype(np.uint8), "RGBA"))
		frame_layers = {}
		solid = (pa[..., 3] > 200).astype(np.float32)
		for key, m in masks.items():
			# The plate whole (its own soft edge kept); the ring round it only where the rock is solid,
			# so no see-through haze rides along with it.
			grown = _grow(m, PLATE_GROW)
			ring = _feather(grown, PLATE_FEATHER) * solid
			inside = _grow(m, 4) * (pa[..., 3] / 255.0)
			alpha = np.maximum(ring, inside)
			la = pa.copy()
			la[..., 3] = alpha * 255.0
			frame_layers[key] = Image.fromarray(la.astype(np.uint8), "RGBA")
		layers.append(frame_layers)
	# Line the frames up on the plated pictures, then move the bodies and layers the same way.
	shifts = shifts_for(plated, anim.stable)
	placed = place_all(plated + bodies, shifts + shifts)
	bodies = placed[len(plated):]
	keyed = []
	for fl, shift in zip(layers, shifts):
		keys = list(fl)
		moved = place_all(plated + [fl[k] for k in keys], shifts + [shift] * len(keys))[len(plated):]
		keyed.append(dict(zip(keys, moved)))
	for target, (plate, source) in (arm.borrow or {}).items():
		region = keyed[target][plate].getchannel("A")
		patch = bodies[source].copy()
		patch.putalpha(Image.fromarray((np.asarray(region).astype(np.float32) * (np.asarray(patch.getchannel("A")) / 255.0)).astype(np.uint8), "L"))
		bodies[target] = bodies[target].copy()
		bodies[target].alpha_composite(patch)
	return bodies, keyed, scale


EMBER = [(0.0, (60, 14, 8)), (0.35, (170, 48, 18)), (0.6, (240, 120, 30)), (0.8, (255, 190, 70)), (1.0, (255, 245, 200))]


def brittle(layer: Image.Image) -> Image.Image:
	"""A plate glowing hot: its light pixels mapped to an ember ramp, its dark outline kept."""
	a = np.asarray(layer).astype(np.float32)
	luma = (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]) / 255.0
	xs = [p for p, _ in EMBER]
	out = a.copy()
	for c in range(3):
		out[..., c] = np.interp(luma, xs, [col[c] for _, col in EMBER])
	keep = luma < 0.32
	out[..., :3][keep] = a[..., :3][keep]
	return Image.fromarray(out.astype(np.uint8), "RGBA")


def armoured(body: Image.Image, layers: dict[str, Image.Image], state: dict[str, str]) -> Image.Image:
	"""The body with its plates in `state` (plate → "cold", "hot" or "gone"; missing = cold)."""
	from PIL import ImageFilter
	im = body.copy()
	for key in PLATES:
		if key in layers and state.get(key, "cold") != "gone":
			if state.get(key) == "hot":
				hot = brittle(layers[key])
				halo = hot.getchannel("A").filter(ImageFilter.GaussianBlur(10)).point(lambda v: int(v * 0.55))
				glow = Image.new("RGBA", hot.size, (255, 140, 40, 0))
				glow.putalpha(halo)
				im.alpha_composite(glow)
				im.alpha_composite(hot)
			else:
				im.alpha_composite(layers[key])
	return im


ARMOUR_STATES = [
	("three plates", {}),
	("chest hot", {"C": "hot"}),
	("chest gone", {"C": "gone"}),
	("chest and L gone", {"C": "gone", "L": "gone"}),
	("all gone", {"C": "gone", "L": "gone", "R": "gone"}),
]


def preview_armour(name: str) -> None:
	anim = ANIMATIONS[name]
	bodies, layers, scale = armour_frames(name)
	z = scale * ZOOM
	pad = 24
	w, h = scaled(bodies[0], z).size
	cols = len(ARMOUR_STATES)
	size = ((w + pad) * cols + pad, h + pad * 2)
	ground = floor(size, round(CELL * ZOOM))
	images = []
	for i in anim.order:
		im = ground.copy()
		for s, (_, state) in enumerate(ARMOUR_STATES):
			im.alpha_composite(scaled(armoured(bodies[i], layers[i], state), z), (pad + s * (w + pad), pad))
		images.append(im.convert("RGB"))
	PREVIEW.mkdir(parents=True, exist_ok=True)
	gif = PREVIEW / f"{name}-plates.gif"
	images[0].save(gif, save_all=True, append_images=images[1:], duration=round(1000 / anim.fps), loop=0)
	images[0].save(PREVIEW / f"{name}-plates-frame1.png")
	# The layers themselves, frame 1, for checking the masks.
	check = Image.new("RGBA", (bodies[0].width * 4, bodies[0].height), (90, 90, 98, 255))
	check.alpha_composite(bodies[0], (0, 0))
	for k, key in enumerate(PLATES):
		if key in layers[0]:
			check.alpha_composite(layers[0][key], ((k + 1) * bodies[0].width, 0))
	check.save(PREVIEW / f"{name}-layers.png")
	print(f"{gif.relative_to(REPO)}  plates seen in frame 1: {''.join(k for k in PLATES if k in layers[0])}")


# --- previews -------------------------------------------------------------------------------------

def slime() -> Image.Image:
	sheet = Image.open(SLIME_SHEET).convert("RGBA")
	return trim(sheet.crop((0, 0, 256, 256)), pad=0)


def floor(size: tuple[int, int], cell: int) -> Image.Image:
	im = Image.new("RGBA", size, FLOOR + (255,))
	d = ImageDraw.Draw(im)
	for x in range(0, size[0], cell):
		d.line([(x, 0), (x, size[1])], fill=GRID)
	for y in range(0, size[1], cell):
		d.line([(0, y), (size[0], y)], fill=GRID)
	return im


def preview(name: str) -> None:
	anim = ANIMATIONS[name]
	lined, scale = frames_of(name)
	z = scale * ZOOM
	shown = [scaled(f, z) for f in lined]
	pal = scaled(slime(), SLIME_GAME_SCALE * ZOOM)
	w, h = shown[0].size
	pad = 24
	size = (w + pal.width + pad * 3, max(h, pal.height) + pad * 2)
	ground = floor(size, round(CELL * ZOOM))
	images = []
	for i in anim.order:
		im = ground.copy()
		im.alpha_composite(shown[i], (pad, pad))
		im.alpha_composite(pal, (pad * 2 + w, pad + h - pal.height))
		images.append(im.convert("RGB"))
	PREVIEW.mkdir(parents=True, exist_ok=True)
	gif = PREVIEW / f"{name}.gif"
	images[0].save(gif, save_all=True, append_images=images[1:], duration=round(1000 / anim.fps), loop=0)
	strip = Image.new("RGB", (size[0] * len(shown), size[1]))
	for i, f in enumerate(shown):
		im = ground.copy()
		im.alpha_composite(f, (pad, pad))
		strip.paste(im.convert("RGB"), (i * size[0], 0))
	strip.save(PREVIEW / f"{name}-strip.png")
	print(f"{gif.relative_to(REPO)}  {len(images)} frames, game size {lined[0].width * scale:.0f} x {lined[0].height * scale:.0f}")


def contact(boss: str, zoom: float = 1.0) -> None:
	"""Every animation of a boss as a row of its four frames at `zoom` times game size, labelled; the
	Colossus's rows twice: all plates cold, then the chest gone and his L plate hot."""
	from PIL import ImageFont
	f_label = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 22)
	f_note = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 18)
	rows: list[tuple[str, list[Image.Image]]] = []
	for name, anim in ANIMATIONS.items():
		if anim.boss != boss or not (SRC / boss / "frames" / anim.sheet).exists():
			continue
		if name in ARMOUR and (SRC / boss / "frames" / ARMOUR[name].bare).exists():
			bodies, layers, scale = armour_frames(name)
			for label, state in (("three plates", {}), ("chest gone, L hot", {"C": "gone", "L": "hot"})):
				rows.append((f"{name}: {anim.note} ({label})", [scaled(armoured(b, l, state), scale * zoom) for b, l in zip(bodies, layers)]))
		else:
			lined, scale = frames_of(name)
			rows.append((f"{name}: {anim.note}", [scaled(f, scale * zoom) for f in lined]))
	pal = scaled(slime(), SLIME_GAME_SCALE * zoom)
	pad, head = 16, 34
	cell_w = max(f.width for _, fs in rows for f in fs)
	width = pad + (cell_w + pad) * 4 + pal.width + pad
	heights = [head + max(f.height for f in fs) + pad for _, fs in rows]
	sheet = floor((width, sum(heights) + pad), round(CELL * zoom))
	d = ImageDraw.Draw(sheet)
	y = pad
	for (label, fs), h in zip(rows, heights):
		d.text((pad, y), label, fill=(240, 236, 228), font=f_label)
		tallest = max(f.height for f in fs)
		for i, f in enumerate(fs):
			sheet.alpha_composite(f, (pad + i * (cell_w + pad) + (cell_w - f.width) // 2, y + head + tallest - f.height))
		sheet.alpha_composite(pal, (pad + 4 * (cell_w + pad), y + head + tallest - pal.height))
		y += h
	d.text((pad, y - 6), f"{zoom:g} x game size on 64-unit cells; the slime beside each row", fill=(168, 164, 156), font=f_note)
	PREVIEW.mkdir(parents=True, exist_ok=True)
	out = PREVIEW / f"{boss}-contact.png"
	sheet.convert("RGB").save(out)
	print(f"{out.relative_to(REPO)}  {sheet.width} x {sheet.height}")


# --- packing for the game -------------------------------------------------------------------------
#
# `pack <boss>` writes godot/asset/MAPS/enemies/bosses/<boss>/: one strip per animation (its frames
# side by side in equal cells, `<key>.webp`) at PX_PER_UNIT art pixels a game unit (the game draws
# them at 1 / PX_PER_UNIT), and `frames.json`, which the boss's look reads:
#   {"px_per_unit", "animations": {key: {"file", "cell": [w, h], "frames", "anchor": [x, y] (the art
#    point placed at the body's origin, in a cell), "box": [x0, y0, x1, y1] (the anchor frame's
#    picture in its cell), "fps", "order" (frame indices to play)}}}
# The Colossus's strips are his bare body; each animation also has `<key>-plates.webp`, an atlas of
# its plate pieces, and per frame "plates": {plate: {"cold": piece, "hot": piece}} with a piece
# {"rect": [x, y, w, h] in the atlas, "at": [x, y] its top left in the frame's cell}, and "crystals":
# {plate: {"live": piece, "dead": piece}} in the same atlas (the crystal under each plate). His side walk
# faces right ("faces"); the game mirrors it, and its plates, for the left (L and R swap). The burst's
# shards are `shards.webp` with "shards": {"cold": [rect], "hot": [rect], "dust": rect}.

PACK = REPO / "godot" / "asset" / "MAPS" / "enemies" / "bosses"
PX_PER_UNIT = 2.0
PACK_PAD = 2
ATLAS_WIDTH = 1024
HALO_PX = 12
FACES = {"colossus-walk-side": "right"}


def _anchor(im: Image.Image, mode: str) -> tuple[int, int]:
	a = np.asarray(im)[..., 3] > 100
	ys, xs = np.nonzero(a)
	cx = int(round((xs.min() + xs.max()) / 2))
	if mode == "top":
		return cx, int(ys.min())
	if mode == "centre":
		return cx, int(round((ys.min() + ys.max()) / 2))
	return cx, int(ys.max())


def _crop(im: Image.Image, cut: int = 8) -> tuple[Image.Image, tuple[int, int]]:
	box = im.getchannel("A").point(lambda v: 255 if v > cut else 0).getbbox()
	if box is None:
		return Image.new("RGBA", (1, 1)), (0, 0)
	return im.crop(box), (box[0], box[1])


def _atlas(pieces: list[Image.Image]) -> tuple[Image.Image, list[list[int]]]:
	"""The pieces on shelves `ATLAS_WIDTH` wide, tallest first, 2 px apart; each piece's [x, y, w, h]."""
	order = sorted(range(len(pieces)), key=lambda i: -pieces[i].height)
	rects: list[list[int]] = [[0, 0, 0, 0] for _ in pieces]
	x = y = shelf = 0
	for i in order:
		w, h = pieces[i].size
		if x + w > ATLAS_WIDTH and x > 0:
			x, y, shelf = 0, y + shelf + PACK_PAD, 0
		rects[i] = [x, y, w, h]
		x += w + PACK_PAD
		shelf = max(shelf, h)
	atlas = Image.new("RGBA", (ATLAS_WIDTH, max(1, y + shelf)))
	for i, piece in enumerate(pieces):
		atlas.alpha_composite(piece, (rects[i][0], rects[i][1]))
	return atlas, rects


def _hot_piece(layer: Image.Image) -> Image.Image:
	"""A plate hot: the ember-mapped layer over an orange halo (the preview's look, baked)."""
	from PIL import ImageFilter
	hot = brittle(layer)
	padded = Image.new("RGBA", (hot.width + HALO_PX * 4, hot.height + HALO_PX * 4))
	padded.alpha_composite(hot, (HALO_PX * 2, HALO_PX * 2))
	halo_a = padded.getchannel("A").filter(ImageFilter.GaussianBlur(HALO_PX)).point(lambda v: int(v * 0.55))
	glow = Image.new("RGBA", padded.size, (255, 140, 40, 0))
	glow.putalpha(halo_a)
	glow.alpha_composite(padded)
	return glow


# --- the Colossus's crystals: live and dead -------------------------------------------------------
#
# Under each plate a crystal of rose quartz sits in his rock (the bare body's socket): his health, one
# crystal a phase (the three-crystal fight, 2026-11-25). Destroyed, it stays dark and cracked. Per
# frame and plate the pack cuts the socket's crystal out of the bare body, inside that plate's layer:
# the "live" piece is the crystal as drawn (the game pulses it), the "dead" piece the same pixels on a
# cool slate ramp with cracks drawn from its middle. The cracks come from one seed per crystal (its
# plate's letter), so they keep their shape from frame to frame.

CRYSTAL_MIN_PX = 6
CRYSTAL_RIM_PX = 3
# The dead crystal: its brightness (after DEAD_DIM) mapped to slate, the cracks' colours and width.
DEAD_DIM = 0.8
DEAD_RAMP = [(0.0, (14, 13, 20)), (0.35, (38, 37, 48)), (0.7, (78, 77, 92)), (1.0, (150, 148, 166))]
CRACK_DARK = (8, 7, 12, 255)
CRACK_LIGHT = (176, 172, 192, 255)
CRACK_WIDTH = 2
CRACKS = 4


def _pinkish(a: np.ndarray) -> np.ndarray:
	"""Rose quartz: red well over green, blue over green (the rock's browns have blue under green)."""
	r, g, b = a[..., 0], a[..., 1], a[..., 2]
	return (a[..., 3] > 128) & (r > 110) & (r > g + 35) & (b > g + 4)


def crystal_region(body: Image.Image, layer: Image.Image) -> np.ndarray:
	"""The crystal under a plate (bool, the body's size): the bare body's rose quartz inside the plate's
	layer, closed and filled whole, with the socket's darker pink rim round it (never the brown rock)."""
	a = np.asarray(body).astype(np.float32)
	inside = np.asarray(layer.getchannel("A")) > 20
	pink = _pinkish(a) & inside
	if pink.sum() < CRYSTAL_MIN_PX:
		return np.zeros(pink.shape, bool)
	from PIL import ImageFilter
	im = Image.fromarray(np.where(pink, 255, 0).astype(np.uint8), "L")
	closed = np.asarray(im.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))) > 0
	whole = _fill_holes(closed | pink) & inside & (a[..., 3] > 128)
	rim = _grow(whole, CRYSTAL_RIM_PX) & inside & (a[..., 3] > 128) & (a[..., 2] >= a[..., 1] - 4)
	return whole | rim


def _crystal_piece(body: Image.Image, region: np.ndarray) -> Image.Image:
	"""The body's pixels inside `region` (the live crystal), the rest clear."""
	a = np.asarray(body).copy()
	a[..., 3] = np.where(region, a[..., 3], 0)
	return Image.fromarray(a, "RGBA")


def dead_crystal(live: Image.Image, plate: str) -> Image.Image:
	"""A crystal destroyed: its pixels on a cool slate ramp, dimmed, and cracked from its middle (the
	cracks' shape from the plate's seed: the same in every frame)."""
	a = np.asarray(live).astype(np.float32)
	luma = (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]) / 255.0 * DEAD_DIM
	xs = [p for p, _ in DEAD_RAMP]
	out = a.copy()
	for c in range(3):
		out[..., c] = np.interp(luma, xs, [col[c] for _, col in DEAD_RAMP])
	dead = Image.fromarray(out.astype(np.uint8), "RGBA")
	solid = a[..., 3] > 128
	ys, xs_ = np.nonzero(solid)
	if len(xs_) < CRYSTAL_MIN_PX:
		return dead
	cx, cy = float(xs_.mean()), float(ys.mean())
	reach = 0.5 * max(xs_.max() - xs_.min(), ys.max() - ys.min())
	rng = np.random.default_rng(ord(plate) * 7919)
	lines = Image.new("RGBA", dead.size)
	draw = ImageDraw.Draw(lines)
	for k in range(CRACKS):
		angle = (k + rng.uniform(-0.3, 0.3)) * 2.0 * np.pi / CRACKS
		points = [(cx, cy)]
		for step in range(1, 4):
			angle += rng.uniform(-0.55, 0.55)
			length = reach * step / 3.0 * rng.uniform(0.8, 1.05)
			points.append((cx + np.cos(angle) * length, cy + np.sin(angle) * length))
		draw.line([(x + 1, y + 1) for x, y in points], fill=CRACK_DARK, width=CRACK_WIDTH + 1)
		draw.line(points, fill=CRACK_LIGHT, width=CRACK_WIDTH)
	# the cracks only on the crystal
	la = np.asarray(lines).copy()
	la[..., 3] = np.where(solid, la[..., 3], 0)
	dead.alpha_composite(Image.fromarray(la, "RGBA"))
	return dead


def _save(image: Image.Image, path: Path) -> None:
	sys.path.insert(0, str(REPO / "scripts" / "lib"))
	from game_webp import save_game_webp
	path.parent.mkdir(parents=True, exist_ok=True)
	save_game_webp(image, path)


def pack(boss: str) -> None:
	import json
	out = PACK / boss
	manifest: dict = {"px_per_unit": PX_PER_UNIT, "animations": {}}
	for name, anim in ANIMATIONS.items():
		if anim.boss != boss:
			continue
		key = anim.key or name.split("-", 1)[1]
		armour = name in ARMOUR
		if armour:
			bodies, layers, scale = armour_frames(name)
		else:
			bodies, scale = frames_of(name)
			layers = [{} for _ in bodies]
		z = scale * PX_PER_UNIT
		shown = [scaled(bodies[i], z) for i in anim.use]
		cell = (shown[0].width + PACK_PAD * 2, shown[0].height + PACK_PAD * 2)
		strip = Image.new("RGBA", (cell[0] * len(shown), cell[1]))
		for k, frame in enumerate(shown):
			strip.alpha_composite(frame, (k * cell[0] + PACK_PAD, PACK_PAD))
		anchor_picture = scaled(bodies[anim.anchor_frame], z)
		ax, ay = _anchor(anchor_picture, anim.anchor)
		bx0, by0, bx1, by1 = anchor_picture.getchannel("A").point(lambda v: 255 if v > 100 else 0).getbbox()
		entry: dict = {"file": f"{key}.webp", "cell": list(cell), "frames": len(shown),
			"anchor": [ax + PACK_PAD, ay + PACK_PAD],
			"box": [bx0 + PACK_PAD, by0 + PACK_PAD, bx1 + PACK_PAD, by1 + PACK_PAD], "fps": anim.fps,
			"order": [anim.use.index(i) for i in anim.order if i in anim.use], "note": anim.note}
		if name in FACES:
			entry["faces"] = FACES[name]
		_save(strip, out / entry["file"])
		if armour:
			pieces: list[Image.Image] = []
			refs: list[dict] = []
			crystal_refs: list[dict] = []
			for k, i in enumerate(anim.use):
				frame_plates: dict = {}
				frame_crystals: dict = {}
				for plate in PLATES:
					if plate not in layers[i]:
						continue
					layer = scaled(layers[i][plate], z)
					cold, at = _crop(layer)
					hot_full = _hot_piece(cold)
					frame_plates[plate] = {
						"cold": {"piece": len(pieces), "at": [at[0] + PACK_PAD, at[1] + PACK_PAD]},
						"hot": {"piece": len(pieces) + 1, "at": [at[0] + PACK_PAD - HALO_PX * 2, at[1] + PACK_PAD - HALO_PX * 2]},
					}
					pieces += [cold, hot_full]
					# the crystal under it (the bare body's socket), live and dead
					region = crystal_region(shown[k], layer)
					if region.sum() >= CRYSTAL_MIN_PX:
						live, c_at = _crop(_crystal_piece(shown[k], region))
						frame_crystals[plate] = {
							"live": {"piece": len(pieces), "at": [c_at[0] + PACK_PAD, c_at[1] + PACK_PAD]},
							"dead": {"piece": len(pieces) + 1, "at": [c_at[0] + PACK_PAD, c_at[1] + PACK_PAD]},
						}
						pieces += [live, dead_crystal(live, plate)]
				refs.append(frame_plates)
				crystal_refs.append(frame_crystals)
			atlas, rects = _atlas(pieces)
			for frame_plates in refs:
				for plate in frame_plates.values():
					for state in ("cold", "hot"):
						plate[state] = {"rect": rects[plate[state].pop("piece")], "at": plate[state]["at"]}
			for frame_crystals in crystal_refs:
				for crystal in frame_crystals.values():
					for state in ("live", "dead"):
						crystal[state] = {"rect": rects[crystal[state].pop("piece")], "at": crystal[state]["at"]}
			entry["plates_file"] = f"{key}-plates.webp"
			entry["plates"] = refs
			entry["crystals"] = crystal_refs
			_save(atlas, out / entry["plates_file"])
		manifest["animations"][key] = entry
		print(f"  {key}: {len(shown)} frames, cell {cell[0]} x {cell[1]} art px ({cell[0] / PX_PER_UNIT:.0f} x {cell[1] / PX_PER_UNIT:.0f} units)"
			+ (f", {sum(len(f) for f in entry['plates'])} plate pieces, {sum(len(f) for f in entry['crystals'])} crystals" if armour else ""))
	if boss == "colossus":
		z = boss_scale("colossus") * PX_PER_UNIT
		sheet = cut_grid(SRC / "colossus" / "frames" / "colossus-plate-burst.png")
		groups: dict = {}
		pieces = []
		for label, picture in (("cold", sheet[1]), ("hot", sheet[2])):
			groups[label] = []
			for part in _parts(np.asarray(picture)[..., 3] > 100, 300, 3, 3, 10):
				grown = _grow(part, 3)
				ys, xs = np.nonzero(grown)
				box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
				piece = picture.crop(box)
				alpha = np.minimum(np.asarray(piece.getchannel("A")), np.where(grown[box[1]:box[3], box[0]:box[2]], 255, 0))
				piece.putalpha(Image.fromarray(alpha.astype(np.uint8), "L"))
				groups[label].append(len(pieces))
				pieces.append(scaled(piece, z))
		dust, _ = _crop(scaled(sheet[3], z))
		groups["dust"] = len(pieces)
		pieces.append(dust)
		atlas, rects = _atlas(pieces)
		manifest["shards_file"] = "shards.webp"
		manifest["shards"] = {"cold": [rects[i] for i in groups["cold"]], "hot": [rects[i] for i in groups["hot"]],
			"dust": rects[groups["dust"]]}
		_save(atlas, out / "shards.webp")
		print(f"  shards: {len(groups['cold'])} cold, {len(groups['hot'])} hot, a dust burst")
	(out / "frames.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
	print(f"{(out / 'frames.json').relative_to(REPO)}")


# --- the showcase: every animation playing at once, for the owner ---------------------------------

SHOW_TICK = 1 / 12  # s per GIF frame
SHOW_SECONDS = 6.0
SHOW_ZOOM = 1.0


def _burst_shards() -> list[Image.Image]:
	"""The loose cold shards of the plate-burst sheet (its top-right picture), largest first."""
	sheet = cut_grid(SRC / "colossus" / "frames" / "colossus-plate-burst.png")[1]
	a = np.asarray(sheet)
	shards = []
	for part in _parts(a[..., 3] > 100, 300, 3, 3, 10):
		ys, xs = np.nonzero(_grow(part, 3))
		box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
		piece = sheet.crop(box)
		mask = Image.fromarray(np.where(_grow(part, 3)[box[1]:box[3], box[0]:box[2]], 255, 0).astype(np.uint8), "L")
		alpha = np.minimum(np.asarray(piece.getchannel("A")), np.asarray(mask))
		piece.putalpha(Image.fromarray(alpha.astype(np.uint8), "L"))
		shards.append(piece)
	return shards


def _burst_frame(body: Image.Image, layers: dict[str, Image.Image], plate: str, t: float, shards: list[Image.Image], src_scale: float) -> Image.Image:
	"""His frame `t` seconds after `plate` burst: the plate gone, its shards flying out and falling,
	fading, a white flash at the start."""
	im = armoured(body, layers, {plate: "gone"})
	alpha = np.asarray(layers[plate].getchannel("A")) > 200
	ys, xs = np.nonzero(alpha)
	cx, cy = float(xs.mean()), float(ys.mean())
	span = float(xs.max() - xs.min())
	rng = np.random.default_rng(7)
	big = Image.new("RGBA", (im.width * 3, im.height * 3))
	ox, oy = im.width, im.height
	big.alpha_composite(im, (ox, oy))
	fade = max(0.0, 1.0 - t / 0.9)
	for i, shard in enumerate(shards * 2):
		ang = (i / (len(shards) * 2)) * 2 * np.pi + rng.uniform(-0.3, 0.3)
		speed = rng.uniform(0.9, 1.6) * span * 2.2  # source px per second
		x = cx + np.cos(ang) * speed * t
		y = cy + np.sin(ang) * speed * t * 0.6 + 900.0 * t * t
		size = span * rng.uniform(0.16, 0.3) / max(shard.width, shard.height)
		piece = scaled(shard, size).rotate(float(rng.uniform(-200, 200) * t), expand=True, resample=Image.BICUBIC)
		if fade < 1:
			piece.putalpha(piece.getchannel("A").point(lambda v: int(v * fade)))
		big.alpha_composite(piece, (int(ox + x - piece.width / 2), int(oy + y - piece.height / 2)))
	if t < 0.12:
		from PIL import ImageFilter
		flash = Image.new("RGBA", big.size, (255, 255, 255, 0))
		d = ImageDraw.Draw(flash)
		r = span * (0.5 + t * 4)
		d.ellipse((ox + cx - r, oy + cy - r * 0.7, ox + cx + r, oy + cy + r * 0.7), fill=(255, 250, 235, int(200 * (1 - t / 0.12))))
		big.alpha_composite(flash.filter(ImageFilter.GaussianBlur(span * 0.12)))
	return big.crop((ox, oy, ox + im.width, oy + im.height))


def _hot_pulse(body: Image.Image, layers: dict[str, Image.Image], plate: str, t: float) -> Image.Image:
	"""The plate hot, its glow pulsing (the hot layer over the cold one at a breathing strength)."""
	cold = armoured(body, layers, {})
	hot = armoured(body, layers, {plate: "hot"})
	k = 0.9 + 0.1 * np.sin(t * 2 * np.pi * 1.5)
	return Image.blend(cold, hot, float(k))


def showcase(boss: str) -> None:
	from PIL import ImageFont
	f_label = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 17)
	cells: list[tuple[str, callable, tuple[int, int]]] = []  # label, tick → image, size
	zoom = SHOW_ZOOM
	if boss == "matron":
		for name in ["matron-hang", "matron-spit", "matron-dive", "matron-rammed", "matron-on-back", "matron-climb", "matron-spin", "matron-cocoon", "matron-dazed"]:
			anim = ANIMATIONS[name]
			lined, scale = frames_of(name)
			shown = [scaled(f, scale * zoom) for f in lined]
			cells.append((anim.note.split(":")[0].split(",")[0], (lambda shown=shown, anim=anim: lambda t: shown[anim.order[int(t * anim.fps) % len(anim.order)]])(), shown[0].size))
	else:
		shards = _burst_shards()
		walk = {n: armour_frames(n) for n in ["colossus-walk-down", "colossus-walk-side", "colossus-walk-up"]}
		other = {n: armour_frames(n) for n in ["colossus-stomp", "colossus-leap-cling", "colossus-fall"]}

		def walker(name: str, state: dict, frames=None):
			bodies, layers, scale = frames or walk[name]
			anim = ANIMATIONS[name]
			shown = [scaled(armoured(b, l, state), scale * zoom) for b, l in zip(bodies, layers)]
			return (lambda t: shown[anim.order[int(t * anim.fps) % len(anim.order)]]), shown[0].size

		def burst_cell(name: str, plate: str):
			bodies, layers, scale = walk[name]
			anim = ANIMATIONS[name]
			cache: dict = {}

			def at(t: float) -> Image.Image:
				t = t % SHOW_SECONDS
				i = anim.order[int(t * anim.fps) % len(anim.order)]
				if t < 1.5:
					key = ("cold", i)
					im = cache.get(key) or armoured(bodies[i], layers[i], {})
				elif t < 3.0:
					key = None
					im = _hot_pulse(bodies[i], layers[i], plate, t)
				elif t < 4.0:
					key = None
					im = _burst_frame(bodies[i], layers[i], plate, t - 3.0, shards, scale)
				else:
					key = ("gone", i)
					im = cache.get(key) or armoured(bodies[i], layers[i], {plate: "gone"})
				if key:
					cache[key] = im
				return scaled(im, scale * zoom)
			return at, scaled(bodies[0], scale * zoom).size

		for label, (fn, size) in [
			("walking toward you, three plates", walker("colossus-walk-down", {})),
			("to the side, chest hot", walker("colossus-walk-side", {"C": "hot"})),
			("away, one shoulder gone", walker("colossus-walk-up", {"L": "gone"})),
			("the chest plate: cold, hot, burst", burst_cell("colossus-walk-down", "C")),
			("the stomp, three plates", walker("colossus-stomp", {}, other["colossus-stomp"])),
			("leap and cling, two plates gone", walker("colossus-leap-cling", {"C": "gone", "R": "gone"}, other["colossus-leap-cling"])),
			("fall, on his back, L hot", walker("colossus-fall", {"C": "gone", "L": "hot"}, other["colossus-fall"])),
		]:
			cells.append((label, fn, size))
	cols = 3
	pad, head = 14, 26
	pal = scaled(slime(), SLIME_GAME_SCALE * zoom)
	probe = ImageDraw.Draw(Image.new("RGB", (8, 8)))
	cw = max(max(s[0] for _, _, s in cells) + pal.width + pad, max(int(probe.textlength(l, font=f_label)) for l, _, _ in cells)) + pad * 2
	ch = max(s[1] for _, _, s in cells) + head + pad
	rows = (len(cells) + cols - 1) // cols
	size = (pad + cw * cols, pad + ch * rows)
	ground = floor(size, round(CELL * zoom))
	d = ImageDraw.Draw(ground)
	for k, (label, _, _) in enumerate(cells):
		x, y = pad + (k % cols) * cw, pad + (k // cols) * ch
		d.text((x, y), label, fill=(240, 236, 228), font=f_label)
	frames = []
	ticks = int(SHOW_SECONDS / SHOW_TICK)
	for n in range(ticks):
		t = n * SHOW_TICK
		im = ground.copy()
		for k, (_, fn, (w, h)) in enumerate(cells):
			x, y = pad + (k % cols) * cw, pad + (k // cols) * ch + head
			pic = fn(t)
			art_w = cw - pad * 2 - pal.width
			im.alpha_composite(pic, (x + (art_w - pic.width) // 2, y + (ch - head - pad - pic.height)))
			im.alpha_composite(pal, (x + art_w + pad, y + ch - head - pad - pal.height))
		frames.append(im.convert("RGB"))
	ms = round(SHOW_TICK * 1000)
	webp = PREVIEW / f"{boss}-showcase.webp"
	frames[0].save(webp, save_all=True, append_images=frames[1:], duration=ms, loop=0, quality=88, method=4)
	# One palette for every GIF frame (taken from a strip of frames across the clip), so unchanged
	# pixels stay the same index and the GIF keeps small.
	sample = Image.new("RGB", (size[0], size[1] * 4))
	for k in range(4):
		sample.paste(frames[k * len(frames) // 4], (0, k * size[1]))
	palette = sample.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
	gif_frames = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
	gif = PREVIEW / f"{boss}-showcase.gif"
	gif_frames[0].save(gif, save_all=True, append_images=gif_frames[1:], duration=ms, loop=0, optimize=True)
	for k, t in enumerate((0.5, 2.0, 3.08, 3.3, 3.6, 4.5)):
		frames[min(int(t / SHOW_TICK), len(frames) - 1)].save(PREVIEW / f"{boss}-showcase-still-{k}.png")
	print(f"{gif.relative_to(REPO)}  {size[0]} x {size[1]}, {ticks} frames, GIF {gif.stat().st_size // 1024} KB, WebP {webp.stat().st_size // 1024} KB")


def main(argv: list[str]) -> None:
	if argv and argv[0] == "pack":
		for boss in argv[1:] or ["matron", "colossus"]:
			print(boss)
			pack(boss)
		return
	if argv and argv[0] == "showcase":
		for boss in argv[1:] or ["matron", "colossus"]:
			showcase(boss)
		return
	if argv and argv[0] == "contact":
		for boss in argv[1:] or ["matron", "colossus"]:
			contact(boss)
		return
	if not argv or argv[0] != "preview":
		raise SystemExit(__doc__)
	names = argv[1:] or [n for n, a in ANIMATIONS.items() if (SRC / a.boss / "frames" / a.sheet).exists()]
	for name in names:
		if name in ARMOUR and (SRC / ANIMATIONS[name].boss / "frames" / ARMOUR[name].bare).exists():
			preview_armour(name)
		else:
			preview(name)


if __name__ == "__main__":
	main(sys.argv[1:])
