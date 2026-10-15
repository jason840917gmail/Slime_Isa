"""Pack the War Axe's and the Hammer's strike frames into their strike sheets, with their timelines.

The build contract: docs/design/2026-10-12-weapon-strike-frames.md. Sources
(asset/Originals/characters/slime-v2/shapes/strikes/, GPT 2.5, 3 x 2 six-frame body-only strips,
transparent; side views face right): axe-sweep-<side|down|up>, axe-backswing-side, axe-chop-<side|down|up>,
hammer-thud-<side|down|up>, hammer-boom-<side|down|up>. Frames: 1 rest (never shown), 2 wind-up / lift,
3 swing / spring up / pitch, 4 follow-through / chop / smash, 5 spring back, 6 rest. Each frame paints a
round jelly knob where the weapon's handle leaves the body. The backswing's front and back strips are
the sweep's, mirrored (no rows of their own: `flip: true`).

The method is the Spear's (pack-slime-strikes.py, reused here): every frame of a strip at ONE scale,
set by its rest frame (6) against page 1's first idle frame of that direction; the back (side) or the
middle (down / up) and the ground on the same pixel in every frame; the rest frame where the idle frame
stands. No neck is baked in: the Axe and the Hammer turn while one body frame shows, so the game draws
a jelly neck sprite (neck.webp, made here) over the body at the frame's socket.

The knob (prototypes/synced/compose_axe.py's detection, at WS work px per game px): the silhouette
with the sprout's leaves masked out (painted interiors cut off from the body's by their outlines,
elongated, above the middle) and thin strands opened away; its outer radius round the body's core
centre (the body opened with radius OPEN_R_GAME) at 1 degree steps minus that radius's 1-D opening
over +-KNOB_WIN_DEG (the polar form of 'silhouette minus its opening'): the highest bump within
KNOB_CONE_DEG of the frame's expected direction (KNOBS) standing at least KNOB_MIN_GAME off. The
socket is the knob's tip (its point farthest from the centre), or where a line at a given angle from
the knob's middle leaves the body (`exit`), or the knob's middle (`middle`: a handle leaving toward the
camera); frames without a knob take the silhouette's farthest point along a direction (`fallback`).
knob_w: the knob's chord across its outward direction KNOB_W_DEPTH_GAME inside the tip.

Outputs:
  godot/asset/characters/512x416-tile_8x8-slime-v2-strikes-axe.webp     rows 0-2 axe-sweep side / down /
      up, 3 axe-backswing side, 4-6 axe-chop side / down / up; columns 0-5 = frames 1-6
  godot/asset/characters/512x416-tile_8x8-slime-v2-strikes-hammer.webp  rows 0-2 hammer-thud, 3-5
      hammer-boom side / down / up
  godot/asset/characters/shapes/neck.webp   the code neck: a horizontal jelly cone, root left
  godot/asset/characters/shapes/<axe|hammer>-views.webp   the weapon views of Round 2 (weapon-<shape>-
      <toward|away>.png cut, their end balls off, matched to the side weapon's jelly): row 0 toward, row 1
      away, columns = views 1-4; the manifest's `weapons.<shape>.views`
  godot/game/data/shape-strikes.json        MERGED: the Spear's strikes and top-level keys stay; this
      script writes its five strikes (texture, weapon, rows, each strip's jelly arm `arm_px` solved to the
      game's hit numbers in REACH_TARGETS, frames with sockets, timeline keys, contact reach), the
      `weapons` block and the `neck` block

Usage: python scripts/characters/pack-slime-weapon-strikes.py [--preview [<dir>]] [--knobs-only]
        [--only=<names>] [--no-write]
  --preview simulates what the game draws from the manifest alone (shape_visuals.gd's weapon and neck
  drawing, ported: GIFs per strike and direction, the chains, contact sheets, knob and neck sheets);
  default folder asset/Originals/characters/slime-v2/shapes/prototypes/strikes-preview/. --knobs-only
  writes only the knob sheets; --only limits the previews to the variants whose names hold one of the
  comma-separated words; --no-write leaves the sheets, the neck and the manifest untouched (previews of
  the current state). Python 3.12 + Pillow + numpy.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import os
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
_SPEC = importlib.util.spec_from_file_location("pack_slime_strikes", HERE / "pack-slime-strikes.py")
P = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(P)

ROOT, SRC, GODOT = P.ROOT, P.SRC, P.GODOT
CONSTANTS_PATH = GODOT / "game/data/game-constants.json"
MANIFEST_PATH = P.MANIFEST_OUT
SHAPES_DIR = GODOT / "asset/characters/shapes"
NECK_PATH = SHAPES_DIR / "neck.webp"
NECK_RES = "res://asset/characters/shapes/neck.webp"
PREVIEW_DEFAULT = ROOT / "asset/Originals/characters/slime-v2/shapes/prototypes/strikes-preview"
DUMMY_PATH = GODOT / "asset/MAPS/objects/256x256-tile_1x1-training-dummy.webp"
DUMMY_SCALE = 0.42  # training-dummy.tscn Visual scale (offset -128, -256: its base at its position)
GRID, CELL_W, CELL_H = P.GRID, P.CELL_W, P.CELL_H
CELL_TO_GAME = P.CELL_TO_GAME
ORIGIN = np.array([CELL_W / 2.0, CELL_H / 2.0])
MARGIN = P.MARGIN
REST_FRAME = 6
DIRECTIONS = ("side", "down", "up")
AIM = {"side": (1, 0), "down": (0, 1), "up": (0, -1)}
AIM_DEG = {"side": 0.0, "down": 90.0, "up": -90.0}

# ------------------------------------------------------------------ the strikes and their strips
SHEETS = {shape: f"{CELL_W}x{CELL_H}-tile_{GRID}x{GRID}-slime-v2-strikes-{shape}.webp" for shape in ("axe", "hammer")}
STRIKES = {
	"axe-sweep": {"weapon": "axe", "step": "sweep", "rows": {"side": 0, "down": 1, "up": 2}},
	"axe-backswing": {"weapon": "axe", "step": "backswing", "rows": {"side": 3},
		"flip": {"down": "axe-sweep", "up": "axe-sweep"}},
	"axe-chop": {"weapon": "axe", "step": "chop", "rows": {"side": 4, "down": 5, "up": 6}},
	"hammer-thud": {"weapon": "hammer", "step": "thud", "rows": {"side": 0, "down": 1, "up": 2}},
	"hammer-boom": {"weapon": "hammer", "step": "boom", "rows": {"side": 3, "down": 4, "up": 5}},
}

# Per strip: the knob's expected direction per frame (screen degrees round the body's core centre: 0
# right, +90 down; None: no knob is looked for), how the socket is taken where it is not the knob's tip
# (`exit`: where a line at that angle from the knob's middle leaves the body; `middle`: the knob's middle;
# `bottom`: the body's lowest middle point, with that knob_w: the front views' chop and smash come down in
# front of the body, so the weapon is handed out below it, the face kept clear), a lower stand-off bar for
# flat knobs (`knob_min`, game px), and
# for frames without a knob the direction of the silhouette point that stands in (`fallback`). `manual`:
# knob tips read off the knob sheet (game px from the cell origin, the outward direction, knob_w) where
# the search cannot tell the knob from a leaf.
KNOBS: dict[tuple[str, str], dict] = {
	("axe-sweep", "side"): {"hint": {2: -50, 3: 5, 4: 30}, "fallback": {1: 25, 5: 25, 6: 25}},
	("axe-sweep", "down"): {"hint": {2: -5, 3: 90, 4: -175}, "knob_min": {3: 0.5}, "fallback": {1: 170, 5: 170, 6: 170}},
	("axe-sweep", "up"): {"hint": {2: -160, 3: -90, 4: -25}, "fallback": {1: -20, 5: -20, 6: -20},
		"manual": {3: {"tip": (0.5, -5.5), "out": -90, "w": 8.5}}},
	("axe-backswing", "side"): {"hint": {2: 35, 3: 5, 4: -60}, "fallback": {1: -60, 5: -60, 6: -60}},
	("axe-chop", "side"): {"hint": {2: -70, 3: -85, 4: -40}, "socket": {4: ("exit", 40.0)},
		"fallback": {1: 15, 5: 15, 6: 15}},
	("axe-chop", "down"): {"hint": {2: -90, 3: -90, 4: -90}, "socket": {4: ("bottom", 8.5)}, "no_sprout": (4,),
		"fallback": {1: -90, 5: -90, 6: -90}, "manual": {3: {"tip": (-1.0, -32.5), "out": -90, "w": 9.5}}},
	("axe-chop", "up"): {"hint": {2: -90, 3: -90, 4: -90, 5: -90}, "fallback": {1: -90, 6: -90}},
	("hammer-thud", "side"): {"hint": {2: -90, 3: -55, 4: -35}, "fallback": {1: -88, 5: -88, 6: -88},
		"manual": {4: {"tip": (28.5, 18.5), "out": 35, "w": 8.5}}},
	("hammer-thud", "down"): {"hint": {2: -90, 3: -90, 4: -90, 5: -90}, "socket": {4: ("bottom", 9.5)},
		"fallback": {1: -90, 6: -90}},
	("hammer-thud", "up"): {"hint": {}, "fallback": {f: -90 for f in range(1, 7)}},
	("hammer-boom", "side"): {"hint": {2: -100, 3: -90, 4: -30}, "fallback": {1: -92, 5: -92, 6: -92},
		"manual": {2: {"tip": (7.5, -6.3), "out": -90, "w": 10.0}, 4: {"tip": (26.5, 13.5), "out": 35, "w": 10.0}}},
	("hammer-boom", "down"): {"hint": {2: -90, 3: -90, 4: -90, 5: -90}, "socket": {4: ("bottom", 9.5)},
		"fallback": {1: -90, 6: -90}, "manual": {2: {"tip": (-0.5, -3.5), "out": -90, "w": 10.0}}},
	("hammer-boom", "up"): {"hint": {2: -90, 3: -90}, "fallback": {1: -90, 4: -90, 5: -90, 6: -90}},
}

# ------------------------------------------------------------------ knob detection (compose_axe.py's)
WS = 4.5  # work px per game px: each figure is resampled to it for the knob search
OPEN_R_GAME = 10.0  # the body's core (its centre for the polar search): the body opened this much
STEM_R_GAME = 2.0  # strands thinner than 2 x this (the sprout's stem) are opened away first
KNOB_WIN_DEG = 14  # the polar opening's half window: bumps narrower than ~28 degrees stand out
KNOB_CONE_DEG = 35  # how far from the expected direction a knob may sit
KNOB_MIN_GAME = 1.0  # how far a knob must stand off the body's flattened outline (game px)
KNOB_W_DEPTH_GAME = 2.5  # knob_w is the knob's chord this far inside its tip
KNOB_W_RANGE = (6.5, 12.0)  # knob_w is clamped to this (game px): the neck's root width


def load_constants() -> dict:
	return json.loads(CONSTANTS_PATH.read_text(encoding="utf-8"))


def chain_step(constants: dict, weapon: str, step: str) -> dict:
	for entry in constants["shapes"][weapon]["chain"]:
		if entry["id"] == step:
			return entry
	raise KeyError(f"{weapon} chain has no step {step}")


def unit(deg: float) -> np.ndarray:
	a = math.radians(deg)
	return np.array([math.cos(a), math.sin(a)])


def angle_of(v) -> float:
	return math.degrees(math.atan2(v[1], v[0]))


def opening(mask: np.ndarray, r: int) -> np.ndarray:
	"""Morphological opening (octagonal, radius r) on a padded copy: the crop's edge is background."""
	p = np.pad(mask, r + 2)
	out = P.dilate(P.erode(p, r), r)
	return out[r + 2:-(r + 2), r + 2:-(r + 2)] & mask


STEM_CUT_GAME = 1.6  # the painted interiors are opened this much first, so a leaf hung on its stem parts
ROUND_ASPECT = 1.15  # an outlined interior rounder than this (axis ratio) is a knob, not a leaf ...
CENTRED_ASPECT = 1.35  # ... and in the front and back views one this round within CENTRED_GAME of the
CENTRED_GAME = 5.0  # body's middle line (the leaves spread to the sides)


def sprout_mask(fig: np.ndarray, ot: float, centred_knob: bool = False) -> np.ndarray:
	"""The sprout's leaves: painted interiors (opened by STEM_CUT_GAME, so the stem's own interior no
	longer joins a leaf to the body) apart from the body's own, above the body's middle and elongated
	(a round knob outlined on its own stays in the body), grown back with the body at once through the
	interiors and their outline rings, plus the soft fringe beyond (after compose_axe.py)."""
	mask = fig[..., 3] > 0.5
	lum = fig[..., :3] @ P.LUMA
	interior = mask & (lum > 0.3)
	comps = P.components(opening(interior, int(round(STEM_CUT_GAME * WS))), 30)
	if len(comps) < 2:
		return np.zeros(mask.shape, bool)
	body = comps[0]
	body_y = np.where(body)[0].mean()
	cols = np.where(body.any(0))[0]
	mid_x = (cols.min() + cols.max() + 1) / 2.0
	leaf = np.zeros(mask.shape, bool)
	for comp in comps[1:]:
		if comp.sum() < 0.02 * body.sum():
			continue
		ys, xs = np.where(comp)
		if ys.mean() >= body_y:
			continue
		ev = np.linalg.eigvalsh(np.cov(np.stack([xs, ys]).astype(np.float64)))
		aspect = math.sqrt(ev[1] / ev[0]) if ev[0] > 0 else 99.0
		if aspect < ROUND_ASPECT:  # round: a knob, not a leaf
			continue
		# a front or back view's knob sits on the middle line (the leaves spread to the sides)
		if centred_knob and aspect < CENTRED_ASPECT and abs(xs.mean() + 0.5 - mid_x) < CENTRED_GAME * WS:
			continue
		leaf |= comp
	if not leaf.any():
		return leaf
	grow_body = body.copy()
	for _ in range(int(ot) + 4 + 2 * int(round(STEM_CUT_GAME * WS))):
		leaf = P.dilate(leaf, 1) & mask & ~grow_body
		grow_body = P.dilate(grow_body, 1) & mask & ~leaf
	soft = fig[..., 3] > 0
	return leaf | (P.dilate(leaf, 3) & soft & ~grow_body & ~mask)


class Knobs:
	"""One figure resampled to WS work px per game px, its sprout and its knob search."""

	def __init__(self, fig: np.ndarray, g_src: float, sprout: bool = True, centred_knob: bool = False):
		f = WS / g_src
		h, w = fig.shape[:2]
		nw, nh = max(1, round(w * f)), max(1, round(h * f))
		self.fig = np.ascontiguousarray(P.unpremul(P.resize_premul(P.premul(fig), (nw, nh))))
		self.to_src = np.array([w / nw, h / nh])  # source px per work px, per axis
		self.mask = self.fig[..., 3] > 0.5
		self.ot = P.outline_thickness(self.fig)
		self.sprout = sprout_mask(self.fig, self.ot, centred_knob) if sprout else np.zeros(self.mask.shape, bool)
		body = self.mask & ~P.dilate(self.sprout, 2)
		body = opening(body, int(round(STEM_R_GAME * WS)))
		comps = P.components(body, 50)
		self.body = comps[0] if comps else body
		core = opening(self.body, int(round(OPEN_R_GAME * WS)))
		ys, xs = np.where(core if core.any() else self.body)
		self.centre = np.array([xs.mean() + 0.5, ys.mean() + 0.5])
		self._polar()

	def _polar(self) -> None:
		c = self.centre
		th = np.radians(np.arange(360.0) - 180.0)
		rad = np.arange(0.0, 600.0, 0.5)
		px = c[0] + np.cos(th)[:, None] * rad[None, :]
		py = c[1] + np.sin(th)[:, None] * rad[None, :]
		h, w = self.body.shape
		ok = (px >= 0) & (px < w) & (py >= 0) & (py < h)
		hit = np.zeros(px.shape, bool)
		hit[ok] = self.body[py[ok].astype(int), px[ok].astype(int)]
		last = np.where(hit.any(1), hit.shape[1] - 1 - np.argmax(hit[:, ::-1], 1), 0)
		r = rad[last] / WS  # game px, per degree from -180
		n = KNOB_WIN_DEG
		ext = np.concatenate([r[-n:], r, r[:n]])
		mn = np.array([ext[j:j + 2 * n + 1].min() for j in range(360)])
		ext = np.concatenate([mn[-n:], mn, mn[:n]])
		self.env = np.array([ext[j:j + 2 * n + 1].max() for j in range(360)])
		self.r = r
		self.bump = r - self.env

	def find(self, hint: float, knob_min: float = KNOB_MIN_GAME) -> dict:
		degs = np.arange(360.0) - 180.0
		cone = np.abs((degs - hint + 180) % 360 - 180) <= KNOB_CONE_DEG
		score = np.where(cone, self.bump, -1.0)
		j = int(np.argmax(score))
		out: dict = {"found": False, "peak": float(self.bump[j]), "peak_deg": float(degs[j])}
		if self.bump[j] < knob_min:
			return out
		bump = self.bump
		lo = hi = j
		while bump[(lo - 1) % 360] > bump[j] / 3 and (j - lo) < 60:
			lo -= 1
		while bump[(hi + 1) % 360] > bump[j] / 3 and (hi - j) < 60:
			hi += 1
		span = [(k % 360) for k in range(lo, hi + 1)]
		h, w = self.body.shape
		gy, gx = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
		c = self.centre
		ang = (np.degrees(np.arctan2(gy - c[1], gx - c[0])) + 180.0).astype(int) % 360
		dist = np.hypot(gx - c[0], gy - c[1]) / WS
		knob = self.body & np.isin(ang, span) & (dist > self.env[ang] - 1.0)
		yy, xx = np.where(knob)
		d = np.hypot(xx + 0.5 - c[0], yy + 0.5 - c[1])
		far = d >= d.max() - 1.5
		tip = np.array([xx[far].mean() + 0.5, yy[far].mean() + 0.5])
		out.update({"found": True, "mask": knob, "tip": tip, "middle": np.array([xx.mean() + 0.5, yy.mean() + 0.5]),
			"outward": angle_of(tip - c), "stand_game": float(bump[j]), "area_game2": float(knob.sum()) / WS ** 2})
		return out

	def along(self, start: np.ndarray, deg: float, inside_only: bool) -> np.ndarray:
		"""The last body px along deg from start: the first exit (inside_only) or the farthest."""
		u = unit(deg)
		last = start.copy()
		h, w = self.body.shape
		for s in np.arange(0, 800, 0.5):
			q = start + u * s
			x, y = int(q[0]), int(q[1])
			if not (0 <= x < w and 0 <= y < h):
				break
			if self.body[y, x]:
				last = q
			elif inside_only and s > 0:
				break
		return last

	def chord(self, tip: np.ndarray, deg: float) -> float:
		"""The body's run across deg through a point KNOB_W_DEPTH_GAME inside the tip (game px)."""
		u = unit(deg)
		n = np.array([-u[1], u[0]])
		p = tip - u * KNOB_W_DEPTH_GAME * WS
		run = 0.0
		h, w = self.body.shape
		for sgn in (1, -1):
			for s in np.arange(0.5 if sgn > 0 else 0.0, 300, 0.5):
				q = p + n * s * sgn
				x, y = int(q[0]), int(q[1])
				if not (0 <= x < w and 0 <= y < h) or not self.body[y, x]:
					break
				run += 0.5
		return run / WS


# ------------------------------------------------------------------ one strip

class Strip:
	"""A source strip: its six figures at one scale in the strike cell, and per frame its socket."""

	def __init__(self, strike: str, direction: str, reference: P.Figure):
		self.strike = strike
		self.direction = direction
		self.name = f"{strike}-{direction}"
		self.row = STRIKES[strike]["rows"][direction]
		self.figs = P.extract_figures(SRC / f"{self.name}.png")
		if len(self.figs) != 6:
			raise RuntimeError(f"{self.name}: {len(self.figs)} figures, expected 6")
		self.frames = [P.Figure(f, direction) for f in self.figs]
		self.rest = self.frames[REST_FRAME - 1]
		self.reference = reference
		self.scale = reference.height / self.rest.height  # cell px per source px
		self.g = 1.0 / (self.scale * CELL_TO_GAME)  # source px per game px
		dx, dy = (CELL_W - P.PAGE_CELL) / 2.0, (CELL_H - P.PAGE_CELL) / 2.0
		self.rest_middle_cell = reference.middle + dx
		self.ground_cell = reference.ground + dy
		self.anchor_cell_x = self.rest_middle_cell + (self.rest.anchor_x - self.rest.middle) * self.scale
		self.spec = KNOBS[(strike, direction)]
		no_sprout = self.spec.get("no_sprout", ())
		centred = direction != "side" and not self.spec.get("no_centred_knob", False)
		self.knobs = [Knobs(f, self.g, i not in no_sprout, centred) for i, f in enumerate(self.figs, start=1)]
		self.found: dict[int, dict] = {}
		self.sockets: list[dict] = [self._socket(i) for i in range(1, 7)]

	def to_cell(self, index: int, p_src: np.ndarray) -> np.ndarray:
		frame = self.frames[index - 1]
		return np.array([self.anchor_cell_x + (p_src[0] - frame.anchor_x) * self.scale,
			self.ground_cell + (p_src[1] - frame.ground) * self.scale])

	def work_to_cell(self, index: int, p_work: np.ndarray) -> np.ndarray:
		return self.to_cell(index, np.asarray(p_work) * self.knobs[index - 1].to_src)

	def cell_to_work(self, index: int, p_cell: np.ndarray) -> np.ndarray:
		frame = self.frames[index - 1]
		src = np.array([frame.anchor_x + (p_cell[0] - self.anchor_cell_x) / self.scale,
			frame.ground + (p_cell[1] - self.ground_cell) / self.scale])
		return src / self.knobs[index - 1].to_src

	def _socket(self, index: int) -> dict:
		kn = self.knobs[index - 1]
		manual = self.spec.get("manual", {}).get(index)
		if manual is not None:  # read off the knob sheet where the search cannot tell knob from leaf
			cell = ORIGIN + np.array(manual["tip"], np.float64) / CELL_TO_GAME
			return {"frame": index, "knob": True, "how": "manual", "tip_work": self.cell_to_work(index, cell),
				"socket": cell, "socket_game": (cell - ORIGIN) * CELL_TO_GAME, "knob_out": float(manual["out"]),
				"chord_game": float(manual["w"]), "knob_w": float(manual["w"]),
				"centre_cell": self.work_to_cell(index, kn.centre)}
		hint = self.spec.get("hint", {}).get(index)
		mode = self.spec.get("socket", {}).get(index, ("tip",))
		if mode[0] == "bottom":  # the weapon leaves the body's lowest middle (no knob is painted there)
			tip = kn.along(kn.centre, 90.0, inside_only=False)
			cell = self.work_to_cell(index, tip)
			return {"frame": index, "knob": False, "how": "bottom (the weapon below the body)", "tip_work": tip,
				"socket": cell, "socket_game": (cell - ORIGIN) * CELL_TO_GAME, "knob_out": 90.0,
				"chord_game": float(mode[1]), "knob_w": float(mode[1]), "centre_cell": self.work_to_cell(index, kn.centre)}
		found: dict = {"found": False}
		if hint is not None:
			found = kn.find(float(hint), float(self.spec.get("knob_min", {}).get(index, KNOB_MIN_GAME)))
			self.found[index] = found
		if found["found"]:
			out_deg = found["outward"]
			if mode[0] == "exit":
				tip = kn.along(found["middle"], float(mode[1]), inside_only=True)
				how = f"knob exit at {mode[1]:+.0f}"
			elif mode[0] == "middle":
				tip = found["middle"]
				how = "knob middle"
			else:
				tip = found["tip"]
				how = "knob tip"
			chord = kn.chord(found["tip"], out_deg)
		else:
			deg = float(self.spec["fallback"].get(index, hint if hint is not None else AIM_DEG[self.direction]))
			tip = kn.along(kn.centre, deg, inside_only=False)
			out_deg = deg
			how = "no knob: silhouette along " + f"{deg:+.0f}"
			if hint is not None:
				how = f"NOT FOUND (peak {found['peak']:.1f} at {found['peak_deg']:+.0f}); along {deg:+.0f}"
			chord = kn.chord(tip, deg)
		cell = self.work_to_cell(index, tip)
		return {"frame": index, "knob": bool(found["found"]), "how": how, "tip_work": tip, "socket": cell,
			"socket_game": (cell - ORIGIN) * CELL_TO_GAME, "knob_out": float(out_deg), "chord_game": chord,
			"knob_w": float(np.clip(chord, *KNOB_W_RANGE)),
			"centre_cell": self.work_to_cell(index, kn.centre)}

	def render(self) -> tuple[list[np.ndarray], list[tuple[float, float, float, float]]]:
		"""The six cells (premultiplied, CELL_H x CELL_W) and each figure's extent in cell px."""
		cells, extents = [], []
		bw, bh = CELL_W / self.scale, CELL_H / self.scale
		for index, (fig, frame) in enumerate(zip(self.figs, self.frames), start=1):
			x0 = frame.anchor_x - self.anchor_cell_x / self.scale
			y0 = frame.ground - self.ground_cell / self.scale
			ox, oy = int(math.floor(-x0)) + 4, int(math.floor(-y0)) + 4
			canvas = np.zeros((int(math.ceil(bh)) + 10, int(math.ceil(bw)) + 10, 4), np.float32)
			P.over(canvas, P.premul(fig), ox, oy)
			box = (x0 + ox, y0 + oy, x0 + ox + bw, y0 + oy + bh)
			cells.append(P.resize_premul(canvas, (CELL_W, CELL_H), box))
			ys, xs = np.where(fig[..., 3] > 1 / 255)
			lo = self.to_cell(index, np.array([xs.min(), ys.min()], np.float64))
			hi = self.to_cell(index, np.array([xs.max() + 1, ys.max() + 1], np.float64))
			extents.append((float(lo[0]), float(lo[1]), float(hi[0]), float(hi[1])))
		return cells, extents


def rounded(p, nd: int = 1) -> list[float]:
	return [round(float(v), nd) for v in p]


def font(size: int, bold: bool = False):
	for name in (("arialbd.ttf", "segoeuib.ttf") if bold else ("arial.ttf", "segoeui.ttf")):
		try:
			return ImageFont.truetype(name, size)
		except OSError:
			continue
	return ImageFont.load_default()


def knobs_sheet(strips: list[Strip], path: Path) -> None:
	"""Every frame of the shape's strips at work scale: the sprout (magenta), the flattened outline the
	knob stands off (blue), the knob (orange), the core centre (yellow dot), the socket (red ring), the
	knob's outward direction (yellow line), knob_w as a cyan bar; a fallback socket in grey."""
	rows = []
	for strip in strips:
		tiles = []
		for i, kn in enumerate(strip.knobs, start=1):
			pad = 40
			h, w = kn.mask.shape
			base = np.full((h + 2 * pad, w + 2 * pad, 3), 0.42, np.float32)
			a = kn.fig[..., 3:4]
			view = base[pad:pad + h, pad:pad + w]
			view[...] = kn.fig[..., :3] * a + view * (1 - a)
			view[kn.sprout] = view[kn.sprout] * 0.5 + np.array([0.9, 0.2, 0.9]) * 0.5
			found = strip.found.get(i)
			if found is not None and found["found"]:
				m = found["mask"]
				view[m] = view[m] * 0.4 + np.array([1.0, 0.55, 0.0]) * 0.6
			im = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8), "RGB")
			d = ImageDraw.Draw(im)
			cc = kn.centre + pad
			pts = [tuple(cc + unit(dg - 180.0) * kn.env[dg] * WS) for dg in range(360)]
			d.line(pts + [pts[0]], fill=(60, 120, 255), width=1)
			d.ellipse([cc[0] - 4, cc[1] - 4, cc[0] + 4, cc[1] + 4], fill=(255, 230, 0))
			s = strip.sockets[i - 1]
			S = s["tip_work"] + pad
			col = (255, 30, 30) if s["knob"] else (200, 200, 200)
			d.ellipse([S[0] - 6, S[1] - 6, S[0] + 6, S[1] + 6], outline=col, width=3)
			o = unit(s["knob_out"])
			d.line([tuple(S), tuple(S + o * 45)], fill=(255, 230, 0), width=2)
			nrm = np.array([-o[1], o[0]]) * s["knob_w"] * WS / 2
			q = S - o * KNOB_W_DEPTH_GAME * WS
			d.line([tuple(q - nrm), tuple(q + nrm)], fill=(0, 230, 255), width=2)
			lines = [f"{strip.name} f{i}", s["how"], f"knob_w {s['knob_w']:.1f} (chord {s['chord_game']:.1f})",
				f"out {s['knob_out']:+.0f}  socket {rounded(s['socket_game'])}"]
			for j, t in enumerate(lines):
				d.text((4, 3 + j * 14), t, fill=(255, 255, 255), font=font(12))
			tiles.append(im)
		H = max(t.height for t in tiles)
		row = Image.new("RGB", (sum(t.width for t in tiles), H), (30, 30, 30))
		x = 0
		for t in tiles:
			row.paste(t, (x, H - t.height))
			x += t.width
		rows.append(row)
	out = Image.new("RGB", (max(r.width for r in rows), sum(r.height for r in rows)), (30, 30, 30))
	y = 0
	for r in rows:
		out.paste(r, (0, y))
		y += r.height
	out.save(path)




# ================================================================== the weapons (the approved look)
# The side prototypes (prototypes/synced/compose_axe.py, compose_hammer.py) drew the rest frame 72 px
# tall and sized the weapons in those px; in the game page 1's idle frame is ~48.7 game px tall (the
# Visual's 0.28125), so every prototype size is taken x PROTO (the side idle height / 72): the weapons
# keep the proportions to the body the owner approved.
PROTO_SLIME_H = 72.0
WEAPON_TINT = 0.4  # how far the weapon's jelly moves toward the body's (the Spear's 0.4)


def proto_factor(refs: dict) -> float:
	return refs["side"].height * CELL_TO_GAME / PROTO_SLIME_H


class Weapon:
	"""A weapon texture (handle along +x from x 0, head at the right) and its manifest block. The game
	draws it (shape_visuals.gd _strike_weapon_at): the handle (texture x 0 to head_start) stretched from
	hidden_px behind the socket to handle_px past the neck's tip, the head from there at `scale`, the
	whole slid back along its axis by (1 - length) of its run and cut at the hidden end."""

	def __init__(self, name: str, proto: float, body_rgb: np.ndarray, neck_len_ref: float):
		self.name = name
		self.res = f"res://asset/characters/shapes/{name}.webp"
		self.tex = P.load_rgba(SHAPES_DIR / f"{name}.webp")
		self.h, self.w = self.tex.shape[:2]
		if name == "axe":
			# compose_axe.py: 1.2 x shape_visuals.gd's radius-60 axe (its head's middle-to-tip span is 0.24
			# x the radius), its handle (x 0 to 200) stretched 1.45x, 26 px of it from the socket to the head
			self.scale = 1.2 * 60.0 * (1.0 - 0.76) / ((512 - 200) * 0.5) * proto
			self.head_start = 200.0
			self.axis_row = 212.0  # rows 174-250 at x 5-20
			socket_to_head = 26.0 * proto
			self.hidden_px = 200.0 * 1.45 * self.scale - socket_to_head
			self.head_centre = (356.0, 206.5)  # the head's middle (x 200-512, rows 0-413)
			self.across = 1.0
			measure = (110, 185)
		else:
			# compose_hammer.py: the head 54 px face to face (rows 2-418), a 38 px stalk from the socket,
			# 6 px of it hidden; the head's sprite from x 168 (the collar over the stalk's end)
			self.scale = 54.0 / (418.0 - 2.0) * proto
			self.head_start = 168.0
			self.axis_row = 232.5  # rows 182-283 at x 0-20
			socket_to_head = 38.0 * proto
			self.hidden_px = 6.0 * proto
			self.head_centre = (341.0, 210.0)  # the head's middle (x 175-507, rows 2-418)
			self.face_row = 418.0  # its lower face
			self.across = 0.8  # the stalk 0.8x the texture handle's thickness (compose_hammer.py STALK_THICK)
			measure = (20, 130)
		self.socket_to_head_ref = socket_to_head
		self.handle_px = socket_to_head - neck_len_ref  # the game measures it from the neck's tip
		a = self.tex[:, measure[0]:measure[1], 3]
		rows = np.where(np.median(a, 1) > 0.5)[0]
		block = self.tex[rows.min():rows.max() + 1, measure[0]:measure[1]]
		self.handle_w_game = (rows.max() + 1 - rows.min()) * self.scale * self.across
		lum = block[..., :3] @ P.LUMA
		jelly = np.median(block[(block[..., 3] > 0.9) & (lum > 0.35)][:, :3], 0)
		self.gain = (1.0 + (body_rgb / np.maximum(jelly, 1e-3) - 1.0) * WEAPON_TINT).astype(np.float32)
		self.head_depth = (self.w - self.head_start) * self.scale
		ys, xs = np.where(self.tex[..., 3] > 0.5)
		keep = xs >= self.head_start
		self.head_pts = np.stack([xs[keep] + 0.5, ys[keep] + 0.5], 1).astype(np.float64)  # for the reach
		self.mips = mip_chain(P.premul(self.tex))
		self.views = None  # WeaponViews, set once made

	def block(self) -> dict:
		out = {"texture": self.res, "scale": round(self.scale, 6), "head_start": self.head_start,
			"axis_row": self.axis_row, "handle_px": round(self.handle_px, 2), "hidden_px": round(self.hidden_px, 2),
			"handle_across": self.across,
			"tint_gain": rounded(self.gain, 4), "head_centre": list(self.head_centre),
			"socket_to_head_px": round(self.socket_to_head_ref, 2), "handle_width_game": round(float(self.handle_w_game), 2),
			"head_depth_game": round(self.head_depth, 2), "head_height_game": round(self.h * self.scale, 2)}
		if self.name == "hammer":
			out["face_row"] = self.face_row
		return out


def mip_chain(premul: np.ndarray) -> list[np.ndarray]:
	"""Halvings of a premultiplied texture (box-filtered, as the GPU's mipmaps), level 0 the texture."""
	levels = [premul]
	cur = premul
	while min(cur.shape[:2]) > 8:
		h, w = cur.shape[:2]
		cur = P.resize_premul(cur, (max(1, w // 2), max(1, h // 2)))
		levels.append(cur)
	return levels


# ================================================================== the code neck
NECK_TX = 8.0  # texture px per game px at the reference root width
NECK = {"root_w": 10.0, "cap": 4.5, "len": 6.0, "run": 3.5, "tip_w": 5.6, "outline": 0.8, "margin": 1.0,
	"fillet": 1.4, "arm": 1.6, "arm_w": (9.6, 8.2)}
NECK_LIT = 0.55  # the neck's jelly: this share of the body's lit rim colour, the rest its deep jelly


def body_colours(strip: Strip) -> dict:
	"""The side rest frame's jelly (deep interior median), its outline colour and its fine grain."""
	fig = strip.rest.rgba
	mask = fig[..., 3] > 0.5
	depth = P.depth_map(mask, 60)
	ot = P.outline_thickness(fig)
	lum = fig[..., :3] @ P.LUMA
	deep = (depth > ot + 14) & (lum > 0.35) & (lum < 0.85)
	jelly = np.median(fig[deep][:, :3], 0)
	rim = (depth > ot + 2) & (depth < ot + 10) & (lum > 0.4) & (lum < 0.92)
	lit = np.median(fig[rim][:, :3], 0)
	ring = mask & (depth >= 2) & (depth <= max(ot - 2, 2)) & (lum < 0.3)
	line = np.median(fig[ring][:, :3], 0)
	k = 4
	pad = np.pad(lum, k, mode="edge").cumsum(0).cumsum(1)
	pad = np.pad(pad, ((1, 0), (1, 0)))
	nb = 2 * k + 1
	box = (pad[nb:, nb:] - pad[:-nb, nb:] - pad[nb:, :-nb] + pad[:-nb, :-nb]) / (nb * nb)
	hp = lum - box
	sel = deep & (np.abs(hp) < 0.15)
	return {"jelly": jelly.astype(np.float32), "lit": lit.astype(np.float32), "line": line.astype(np.float32),
		"grain": float(np.std(hp[sel]))}


def make_neck(colours: dict) -> tuple[np.ndarray, dict]:
	"""neck.webp: a horizontal jelly cone, root left (compose.py's neck_layer look: the body's jelly and
	grain, a soft gloss, the body's line along the flanks, none on the root, which fades into the knob it
	lies on; the thin end fades into the handle). Along it (game px at the reference root width, from the
	socket): the root's cap inside the knob (-cap..0), a fillet from the knob's width down to the arm's
	(0..fillet), the ARM span (a straight jelly tube, slightly tapering: the part the game stretches by a
	strip's arm_px, so a long arm stays a smooth tube), the taper into the handle (to `len`, tip_x) and the
	run that fades over the handle. Straight RGBA and its manifest block."""
	n = NECK
	T = NECK_TX
	x_lo = -(n["cap"] + n["margin"])
	x_hi = n["len"] + n["run"] + n["margin"]
	half_h = n["root_w"] / 2 + n["margin"]
	W, H = int(round((x_hi - x_lo) * T)), int(round(2 * half_h * T))
	gy, gx = np.mgrid[0:H, 0:W].astype(np.float32) + 0.5
	x = gx / T + x_lo  # game px from the socket along the neck (at the reference root width)
	y = gy / T - half_h  # game px across
	r0, r1 = n["root_w"] / 2, n["tip_w"] / 2
	ra0, ra1 = n["arm_w"][0] / 2, n["arm_w"][1] / 2
	f_end, a_end = n["fillet"], n["fillet"] + n["arm"]
	tf = np.clip(x / f_end, 0, 1)
	fillet = ra0 + (r0 - ra0) * (1 - tf) ** 2  # concave: it leaves the knob wide
	ta = np.clip((x - f_end) / n["arm"], 0, 1)
	arm = ra0 + (ra1 - ra0) * ta  # linear: it stays the same shape however far it is stretched
	tt = np.clip((x - a_end) / (n["len"] - a_end), 0, 1)
	taper = ra1 + (r1 - ra1) * tt * tt * (3 - 2 * tt)
	half = np.where(x < f_end, fillet, np.where(x < a_end, arm, taper))
	cap = r0 * np.sqrt(np.clip(1 - (np.minimum(x, 0) / n["cap"]) ** 2, 0, 1))
	half = np.where(x < 0, cap, half)
	d = half - np.abs(y)  # game px inside the edge
	cov = np.clip(d * T + 0.5, 0, 1)
	fade = P.smoothstep(-n["cap"], -0.3 * n["cap"], x) * (1 - P.smoothstep(n["len"] + 0.3, n["len"] + n["run"], x))
	line_k = P.smoothstep(-0.6, 1.0, x)  # no line where it lies on the knob
	band = (1 - np.clip((d - n["outline"]) * T + 0.5, 0, 1)) * line_k
	v = np.clip(y / np.maximum(half, 0.3), -1, 1)
	jelly = NECK_LIT * colours["lit"] + (1 - NECK_LIT) * colours["jelly"]
	shade = 1.0 + 0.07 * (1 - v * v) - 0.08 * v * v
	icol = jelly[None, None, :] * shade[..., None]
	gloss = 0.24 * np.exp(-((v + 0.38) / 0.16) ** 2) + 0.12 * np.exp(-((v - 0.5) / 0.14) ** 2)
	gloss = gloss * P.smoothstep(-0.5, 1.5, x)
	icol = icol * (1 - gloss[..., None]) + np.array([1.0, 1.0, 0.82]) * gloss[..., None]
	rng = np.random.default_rng(11)
	noise = rng.normal(0.0, 1.0, (H, W)).astype(np.float32)
	for _ in range(2):
		p = np.pad(noise, 1, mode="edge")
		noise = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:] + 2 * noise) / 6
	noise /= max(float(noise.std()), 1e-6)
	# no grain on the arm span: stretched, it would streak
	grain = colours["grain"] * (1 - 0.85 * ((x >= f_end) & (x < a_end)))
	icol = icol * (1 + (noise * grain)[..., None] / max(float(jelly @ P.LUMA), 0.2))
	rgb = icol * (1 - band[..., None]) + colours["line"][None, None, :] * band[..., None]
	alpha = cov * fade
	out = np.dstack([np.clip(rgb, 0, 1), alpha]).astype(np.float32)
	block = {"texture": NECK_RES, "root_x": round(-x_lo * T, 2), "tip_x": round((n["len"] - x_lo) * T, 2),
		"arm_from_x": round((f_end - x_lo) * T, 2), "arm_to_x": round((a_end - x_lo) * T, 2),
		"axis_row": H / 2.0, "width_px": n["root_w"] * T, "size": [W, H]}
	return out, block


def neck_len_at(neck: dict, knob_w: float) -> float:
	"""The neck's tip from the socket (game px) on a frame: shape_visuals.gd's neck_len."""
	return max(0.0, neck["tip_x"] - neck["root_x"]) * knob_w / neck["width_px"]


# ================================================================== the weapon views (Round 2)
# asset/Originals/characters/slime-v2/shapes/weapon-<axe|hammer>-<toward|away>.png (GPT 2.5, 2 x 2): one
# vertical swing as the game's camera sees it: 1 raised (handle up from its free end), 2 tipping toward /
# away, 3 pointing at / away from the viewer, 4 planted in front / beyond. Per view: where the handle's
# free end is (`top` / `bottom` of the figure); the round end ball is cut off at its neck, and the cut's
# middle is the pivot (set on the code neck's tip, whose fading tail covers the cut).
VIEW_SRC = ROOT / "asset/Originals/characters/slime-v2/shapes"
VIEWS = ("toward", "away")
# the screen direction of the handle's free end in each view (0 right, +90 down)
VIEW_END = {"axe": {"toward": (90, -90, -90, -90), "away": (90, 90, 90, 90)},
	"hammer": {"toward": (90, 127, -90, -90), "away": (90, 90, 90, 90)}}
VIEW_PAD = 6  # texture px round each view in the packed texture
NECK_OF_BALL = 0.62  # the end ball is cut where the handle has narrowed to this share of its width
# the pointing-at views show only the handle's end above the head (no ball to cut): their pivot is set by
# hand this many source px in from the end
VIEW_PIVOT_IN = {("axe", "toward", 3): 14.0, ("hammer", "toward", 3): 14.0}


def extract_2x2(path: Path) -> list[np.ndarray]:
	"""The four figures of a 2 x 2 sheet (reading order), cropped, straight RGBA: the rows split at the
	longest empty run of rows near the middle, each row at its empty columns (the two widest column
	groups); per figure the largest component (alpha > 24/255) and the ones touching it, grown 2 px."""
	img = P.load_rgba(path)
	h, w = img.shape[:2]
	cut_y = P.longest_empty_run_mid((img[..., 3] > P.ALPHA_SOLID).sum(1), h // 3, 2 * h // 3)
	figs = []
	for y0, y1 in ((0, cut_y), (cut_y, h)):
		band = img[y0:y1]
		occ = ((band[..., 3] > P.ALPHA_SOLID).sum(0) > 0).astype(np.int8)
		cut_x = P.longest_empty_run_mid(occ, w // 3, 2 * w // 3)
		for x0, x1 in ((0, cut_x), (cut_x, w)):
			cell = band[:, x0:x1]
			lab, n = P.label(cell[..., 3] > 24 / 255)
			sizes = np.bincount(lab.ravel(), minlength=n + 1)
			sizes[0] = 0
			main = lab == int(np.argmax(sizes))
			keep = main.copy()
			for k in np.unique(lab[P.dilate(main, 2) & (lab > 0)]):
				keep |= lab == k
			fig = cell.copy()
			fig[..., 3] *= P.dilate(keep, 2)
			ys, xs = np.where(fig[..., 3] > 1 / 255)
			figs.append(np.ascontiguousarray(fig[ys.min():ys.max() + 1, xs.min():xs.max() + 1]))
	return figs


def width_along(mask: np.ndarray, E: np.ndarray, u: np.ndarray, length: float) -> np.ndarray:
	"""The silhouette's run across u through E + u s, for s = 0, 1, ... length (px): the run containing
	the axis point (0 where the axis point is outside)."""
	n = np.array([-u[1], u[0]])
	h, w = mask.shape
	out = np.zeros(int(length) + 1, np.float32)
	for s in range(len(out)):
		c = E + u * s
		run = 0.0
		for sgn in (1, -1):
			for t in np.arange(0.0 if sgn > 0 else 0.5, 400, 0.5):
				q = c + n * t * sgn
				x, y = int(q[0]), int(q[1])
				if not (0 <= x < w and 0 <= y < h) or not mask[y, x]:
					break
				run += 0.5
		out[s] = run
	return out


class View:
	"""One weapon view: the figure (its end ball cut off), its pivot, head, dir and extent (figure px)."""

	def __init__(self, fig: np.ndarray, end: float, pivot_in: float | None = None):
		self.src = fig
		mask = fig[..., 3] > 0.5
		h, w = mask.shape
		ys, xs = np.where(mask)
		# the free end: the figure's extreme px toward `end` (degrees), the middle of those within 3 px of it
		e = unit(end)
		proj = (xs + 0.5) * e[0] + (ys + 0.5) * e[1]
		sel = proj >= proj.max() - 3
		E = np.array([xs[sel].mean() + 0.5, ys[sel].mean() + 0.5]) + e * 0.5
		# the head: the far 40 % of the figure from the end
		d = np.hypot(xs + 0.5 - E[0], ys + 0.5 - E[1])
		far = d >= np.quantile(d, 0.6)
		H0 = np.array([xs[far].mean() + 0.5, ys[far].mean() + 0.5])
		u = (H0 - E) / max(np.linalg.norm(H0 - E), 1e-6)
		L = float(np.max((np.stack([xs + 0.5, ys + 0.5], 1) - E) @ u))
		wid = width_along(mask, E, u, L)
		# the end ball: the first peak of the run (smoothed) from the end, then its neck (the narrowest run
		# within 0.8 of the ball's width after it)
		sm = np.convolve(np.pad(wid, 3, mode="edge"), np.ones(7) / 7, mode="valid")
		first = max(4, int(0.35 * len(wid)))
		s_ball = int(np.argmax(wid[:first]))
		for i in range(3, first):
			lo, hi = max(0, i - 8), min(len(sm), i + 9)
			if sm[i] > 3 and sm[i] >= sm[lo:hi].max() - 1e-6:
				s_ball = i
				break
		ball_w = float(wid[s_ball])
		win = wid[s_ball:min(len(wid), s_ball + int(0.8 * ball_w) + 2)]
		s_cut = s_ball + int(np.argmin(win))
		thin = np.where(win <= NECK_OF_BALL * ball_w)[0]  # a teardrop end tapers: cut where it is thin enough
		if len(thin):
			s_cut = min(s_cut, s_ball + int(thin[0]))
		self.cut = bool(wid[s_cut] < 0.85 * ball_w and s_cut > s_ball) and pivot_in is None
		if not self.cut:
			s_cut = int(round(s_ball if pivot_in is None else pivot_in))
		gy, gx = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
		along = (gx - E[0]) * u[0] + (gy - E[1]) * u[1]
		perp = (gx - E[0]) * -u[1] + (gy - E[1]) * u[0]
		rgba = fig.copy()
		if self.cut:  # the ball off, a soft 1.5 px edge at its neck
			near = np.abs(perp) < 0.65 * ball_w
			k = np.where(near, P.smoothstep(s_cut - 0.5, s_cut + 1.0, along), 1.0)
			rgba[..., 3] *= k
		self.rgba = rgba
		self.pivot = E + u * s_cut
		mask2 = rgba[..., 3] > 0.5
		ys2, xs2 = np.where(mask2)
		pts = np.stack([xs2 + 0.5, ys2 + 0.5], 1)
		# the head: the px beyond where the run first grows past twice the handle's (else the far 40 %)
		shaft = float(np.median(wid[s_cut + 2:s_cut + 2 + max(3, int(0.15 * len(wid)))])) if s_cut + 5 < len(wid) else ball_w
		grow = np.where(wid[s_cut + 1:] > 2.0 * max(shaft, 1.0))[0]
		s_head = s_cut + 1 + int(grow[0]) if len(grow) else int(0.6 * L)
		a2 = (pts - E) @ u
		head = pts[a2 >= s_head] if (a2 >= s_head).sum() > 50 else pts[a2 >= 0.6 * L]
		self.head = head.mean(0)
		self.head_mask_pts = head
		self.dir = angle_of(self.head - self.pivot)
		self.extent = float(np.max(np.hypot(pts[:, 0] - self.pivot[0], pts[:, 1] - self.pivot[1])))
		self.E, self.u, self.L, self.wid, self.s_ball, self.s_cut, self.s_head = E, u, L, wid, s_ball, s_cut, s_head
		self.end = end
		self.shaft_w = shaft

	def head_span(self) -> float:
		"""The head's extent across the handle (figure px): the blade span, the hammer's face to face."""
		n = np.array([-self.u[1], self.u[0]])
		p = (self.head_mask_pts - self.E) @ n
		return float(p.max() - p.min())


def light_median(rgba: np.ndarray) -> np.ndarray:
	lum = rgba[..., :3] @ P.LUMA
	sel = (rgba[..., 3] > 0.9) & (lum > 0.35) & (lum < 0.85)
	return np.median(rgba[sel][:, :3], 0)


def match_jelly(rgba: np.ndarray, target: np.ndarray) -> np.ndarray:
	"""rgba's light jelly moved onto `target` (a per-channel gain faded out on the dark outline, as
	Spear.tint_toward), so the game's tint_gain modulate gives the views the side weapon's colour."""
	gain = target / np.maximum(light_median(rgba), 1e-3)
	k = P.smoothstep(0.18, 0.4, rgba[..., :3] @ P.LUMA)[..., None]
	out = rgba.copy()
	out[..., :3] = np.clip(rgba[..., :3] * (1 + (gain[None, None, :] - 1) * k), 0, 1)
	return out


class WeaponViews:
	"""Both views' four frames of a weapon, packed into one texture, and their manifest blocks."""

	def __init__(self, weapon: Weapon):
		self.weapon = weapon
		side_jelly = light_median(weapon.tex)
		side_span = (weapon.h if weapon.name == "axe" else (418.0 - 2.0)) * weapon.scale  # game px
		self.views: dict[str, list[View]] = {}
		self.scale: dict[str, float] = {}
		for view in VIEWS:
			figs = extract_2x2(VIEW_SRC / f"weapon-{weapon.name}-{view}.png")
			if len(figs) != 4:
				raise RuntimeError(f"weapon-{weapon.name}-{view}.png: {len(figs)} figures")
			vs = [View(match_jelly(f, side_jelly), e, VIEW_PIVOT_IN.get((weapon.name, view, i)))
				for i, (f, e) in enumerate(zip(figs, VIEW_END[weapon.name][view]), start=1)]
			self.views[view] = vs
			self.scale[view] = side_span / vs[0].head_span()  # view 1 (raised) is not foreshortened
		# pack: a row per view, the frames side by side
		cw = max(v.rgba.shape[1] for vs in self.views.values() for v in vs) + 2 * VIEW_PAD
		ch = max(v.rgba.shape[0] for vs in self.views.values() for v in vs) + 2 * VIEW_PAD
		tex = np.zeros((ch * len(VIEWS), cw * 4, 4), np.float32)
		self.rects: dict[str, list[tuple[int, int, int, int]]] = {}
		for r, view in enumerate(VIEWS):
			self.rects[view] = []
			for c, v in enumerate(self.views[view]):
				h, w = v.rgba.shape[:2]
				x0, y0 = c * cw + VIEW_PAD, r * ch + VIEW_PAD
				P.over(tex, P.premul(v.rgba), x0, y0)
				self.rects[view].append((x0, y0, w, h))
		self.premul = tex
		self.mips = mip_chain(tex)
		self.path = SHAPES_DIR / f"{weapon.name}-views.webp"
		self._points: dict = {}
		self.res = f"res://asset/characters/shapes/{weapon.name}-views.webp"

	def frame(self, view: str, number: int) -> dict:
		v = self.views[view][number - 1]
		x0, y0, w, h = self.rects[view][number - 1]
		o = np.array([x0, y0], np.float64)
		return {"rect": [x0, y0, w, h], "pivot": rounded(v.pivot + o, 1), "dir": round(v.dir, 1),
			"head": rounded(v.head + o, 1), "extent": round(v.extent, 1)}

	def block(self) -> dict:
		return {view: {"texture": self.res, "scale": round(self.scale[view], 6),
			"frames": [self.frame(view, i) for i in range(1, 5)]} for view in VIEWS}

	def points(self, view: str, number: int) -> np.ndarray:
		"""A view frame's opaque px (every second one), texture px."""
		key = (view, number)
		if key not in self._points:
			x0, y0, w, h = self.rects[view][number - 1]
			ys, xs = np.where(self.premul[y0:y0 + h, x0:x0 + w, 3] > 0.5)
			self._points[key] = np.stack([xs[::2] + x0 + 0.5, ys[::2] + y0 + 0.5], 1).astype(np.float64)
		return self._points[key]

	def save(self) -> None:
		out = Image.fromarray((np.clip(P.unpremul(self.premul), 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
		out.save(self.path, lossless=True, method=6)
		print(f"wrote {self.path.relative_to(ROOT)} ({out.width} x {out.height})")

	def debug_sheet(self, path: Path) -> None:
		"""Each view on grey: the source with the cut ball (red tint), the pivot (red ring), the head
		(yellow dot), dir (yellow line), the width profile's ball / cut / head marks along the axis."""
		tiles = []
		for view in VIEWS:
			for i, v in enumerate(self.views[view], start=1):
				h, w = v.src.shape[:2]
				pad = 20
				base = np.full((h + 2 * pad, w + 2 * pad, 3), 0.42, np.float32)
				cut = np.clip(v.src[..., 3] - v.rgba[..., 3], 0, 1)[..., None]
				a = v.rgba[..., 3:4]
				vw = base[pad:pad + h, pad:pad + w]
				vw[...] = v.rgba[..., :3] * a + vw * (1 - a)
				vw[...] = vw * (1 - cut) + np.array([1.0, 0.2, 0.2]) * cut
				im = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8), "RGB")
				d = ImageDraw.Draw(im)
				pv, hd = v.pivot + pad, v.head + pad
				d.line([tuple(pv), tuple(hd)], fill=(255, 230, 0), width=2)
				d.ellipse([pv[0] - 6, pv[1] - 6, pv[0] + 6, pv[1] + 6], outline=(255, 0, 0), width=3)
				d.ellipse([hd[0] - 4, hd[1] - 4, hd[0] + 4, hd[1] + 4], fill=(255, 230, 0))
				for s, col in ((v.s_ball, (0, 200, 255)), (v.s_head, (0, 255, 0))):
					q = v.E + v.u * s + pad
					n = np.array([-v.u[1], v.u[0]]) * 30
					d.line([tuple(q - n), tuple(q + n)], fill=col, width=1)
				d.text((4, 3), f"{self.weapon.name} {view} {i}: dir {v.dir:+.0f} cut {v.cut} ext {v.extent:.0f}",
					fill=(255, 255, 255), font=font(12))
				tiles.append(im)
		W = sum(t.width for t in tiles[:4])
		H = max(t.height for t in tiles[:4]) + max(t.height for t in tiles[4:])
		out = Image.new("RGB", (max(W, sum(t.width for t in tiles[4:])), H), (20, 20, 20))
		x = 0
		for t in tiles[:4]:
			out.paste(t, (x, 0))
			x += t.width
		x, y = 0, max(t.height for t in tiles[:4])
		for t in tiles[4:]:
			out.paste(t, (x, y))
			x += t.width
		out.save(path)

# ================================================================== the timelines
# Per strike and direction the keys (contract syntax: `at` w|a|r<share>; frame; angle; length;
# head_angle; layer). "arc" as an angle: on the sweep's hit line at that point (the aim -/+ half arcDeg in
# the turning sense, linear over the active window); "smash": the stalk angle that stands the hammer's
# head (head_angle 0) on its lower face on the strip's ground. Two keys a hair apart make a jump. A flip
# strip's keys are its source row's, unmirrored (the game mirrors them). The game slides the weapon out
# (length) without scaling it, its head straddling the socket below about 0.6: the visible lengths stay
# at OUT_MIN or more and jump to 0.
OUT_MIN = 0.65


def K(at: str, **values) -> dict:
	return {"at": at, **values}


def sweep_down_keys() -> list[dict]:
	return [K("w0", frame=2, angle=-40, length=OUT_MIN, layer="behind"), K("w0.4", angle=-50, length=1.0),
		K("w0.8", angle=-55), K("w1", angle="arc", layer="front"), K("a0.25", frame=3, angle="arc"),
		K("a0.75", frame=4, angle="arc"), K("a1", angle="arc"), K("r0.15", angle=175, layer="behind"),
		K("r0.25", angle=180), K("r0.3", frame=5, angle=190, length=0.85), K("r0.45", angle=200, length=OUT_MIN),
		K("r0.46", length=0.0), K("r0.55", frame=6)]


def sweep_up_keys() -> list[dict]:
	return [K("w0", frame=2, angle=-185, length=OUT_MIN, layer="behind"), K("w0.4", angle=-195, length=1.0),
		K("w0.8", angle=-200), K("w1", angle="arc"), K("a0.25", frame=3, angle="arc"),
		K("a0.75", frame=4, angle="arc"), K("a1", angle="arc"), K("r0.25", angle=-5),
		K("r0.3", frame=5, angle=10, length=0.85), K("r0.45", angle=20, length=OUT_MIN), K("r0.46", length=0.0),
		K("r0.55", frame=6)]


KEYS: dict[tuple[str, str], list[dict]] = {
	("axe-sweep", "side"): [
		K("w0", frame=2, angle=-82, length=OUT_MIN, layer="behind"), K("w0.4", angle=-95, length=1.0),
		K("w0.8", angle=-100), K("w1", frame=3, angle="arc"), K("a0.5", angle="arc", layer="front"),
		K("a0.55", frame=4, angle="arc"), K("a1", angle="arc"), K("r0.25", angle=70),
		K("r0.3", frame=5, angle=45, length=0.85), K("r0.45", angle=30, length=OUT_MIN), K("r0.46", length=0.0),
		K("r0.55", frame=6)],
	("axe-sweep", "down"): sweep_down_keys(),
	("axe-sweep", "up"): sweep_up_keys(),
	("axe-backswing", "side"): [
		K("w0", frame=2, angle=88, length=OUT_MIN, layer="front"), K("w0.5", angle=85, length=1.0),
		K("w1", angle="arc"), K("a0.25", frame=3, angle="arc"), K("a0.5", angle="arc", layer="behind"),
		K("a0.6", frame=4, angle="arc"), K("a1", angle="arc"), K("r0.2", angle=-78),
		K("r0.3", frame=5, angle=-70, length=0.85), K("r0.45", angle=-65, length=OUT_MIN), K("r0.46", length=0.0),
		K("r0.55", frame=6)],
	("axe-backswing", "down"): sweep_down_keys(),
	("axe-backswing", "up"): sweep_up_keys(),
	("axe-chop", "side"): [
		K("w0", frame=2, angle=-95, length=OUT_MIN, layer="behind"), K("w0.08", angle=-108, length=0.85),
		K("w0.23", angle=-118, length=1.0), K("w0.35", frame=3, angle=-125), K("w0.62", angle=-105),
		K("w0.96", angle=-4), K("w1", frame=4, angle="bite", layer="front"), K("r0.2", angle="bite"),
		K("r0.27", frame=5, angle=30, length=0.85), K("r0.4", angle=15, length=OUT_MIN), K("r0.41", length=0.0),
		K("r0.75", frame=6)],
	("axe-chop", "down"): [
		K("w0", frame=2, view="toward", view_frame=1, angle="dir", length=OUT_MIN, layer="behind"),
		K("w0.08", length=0.85), K("w0.23", length=1.0), K("w0.35", frame=3, angle=-94), K("w0.62", angle="dir"),
		K("w0.74", angle="dir"), K("w0.74", view_frame=3, angle="dir", layer="front"), K("w0.87", angle="dir"),
		K("w0.87", view_frame=2, angle="dir"), K("w1", frame=4, view_frame=4, angle="dir"), K("r0.2"),
		K("r0.32", length=0.85), K("r0.42", length=OUT_MIN), K("r0.43", length=0.0), K("r0.5", frame=5),
		K("r0.75", frame=6)],
	("axe-chop", "up"): [
		K("w0", frame=2, view="away", view_frame=1, angle="dir", length=OUT_MIN, layer="behind"),
		K("w0.08", length=0.85), K("w0.23", length=1.0), K("w0.35", frame=3, angle=-93), K("w0.62", angle="dir"),
		K("w0.72", view_frame=2, angle="dir"), K("w0.86", view_frame=3, angle="dir"),
		K("w1", frame=4, view_frame=4, angle="dir"), K("r0.2"), K("r0.27", frame=5, length=0.85),
		K("r0.4", length=OUT_MIN), K("r0.41", length=0.0), K("r0.75", frame=6)],
	("hammer-thud", "side"): [
		K("w0", frame=2, angle=-80, length=OUT_MIN, layer="behind"), K("w0.08", angle=-88, length=0.85),
		K("w0.19", angle=-95, length=1.0), K("w0.42", angle=-101), K("w0.58", frame=3, angle=-86),
		K("w0.88", angle=-57), K("w0.97", angle=-52), K("w1", frame=4, angle="smash", head_angle=0, layer="front"),
		K("r0.33", angle="smash", head_angle=0), K("r0.34", frame=5, angle=-70, length=0.85, layer="behind"),
		K("r0.47", angle=-88, length=OUT_MIN), K("r0.48", length=0.0), K("r0.6", frame=6)],
	("hammer-thud", "down"): [
		K("w0", frame=2, view="toward", view_frame=1, angle="dir", length=OUT_MIN, layer="behind"),
		K("w0.08", length=0.85), K("w0.19", length=1.0), K("w0.42", angle=-93), K("w0.58", frame=3, angle="dir"),
		K("w0.7", angle="dir"), K("w0.7", view_frame=2, angle="dir", layer="front"), K("w0.84", angle="dir"),
		K("w0.84", view_frame=3, angle="dir"), K("w1", frame=4, view_frame=4, angle="dir"), K("r0.34"),
		K("r0.34", frame=5, view_frame=1, angle="dir", length=0.85, layer="behind"), K("r0.47", length=OUT_MIN),
		K("r0.48", length=0.0), K("r0.6", frame=6)],
	("hammer-thud", "up"): [
		K("w0", frame=2, view="away", view_frame=1, angle="dir", length=OUT_MIN, layer="behind"),
		K("w0.08", length=0.85), K("w0.19", length=1.0), K("w0.42", angle=-93), K("w0.58", frame=3, angle="dir"),
		K("w0.7", view_frame=2, angle="dir"), K("w0.85", view_frame=3, angle="dir"),
		K("w1", frame=4, view_frame=4, angle="dir"), K("r0.33"), K("r0.34", frame=5, length=0.85),
		K("r0.47", length=OUT_MIN), K("r0.48", length=0.0), K("r0.6", frame=6)],
	("hammer-boom", "side"): [
		K("w0", frame=2, angle=-100, length=OUT_MIN, layer="behind"), K("w0.07", angle=-110, length=0.85),
		K("w0.18", angle=-117, length=1.0), K("w0.61", angle=-124), K("w0.64", frame=3, angle=-112),
		K("w0.96", angle=-8), K("w1", frame=4, angle="smash", head_angle=0, layer="front"),
		K("r0.35", angle="smash", head_angle=0), K("r0.36", frame=5, angle=-75, length=0.85, layer="behind"), K("r0.46", angle=-92, length=OUT_MIN), K("r0.47", length=0.0),
		K("r0.6", frame=6)],
	("hammer-boom", "down"): [
		K("w0", frame=2, view="toward", view_frame=1, angle="dir", length=OUT_MIN, layer="behind"),
		K("w0.07", length=0.85), K("w0.18", length=1.0), K("w0.61", angle=-94), K("w0.64", frame=3, angle="dir"),
		K("w0.76", angle="dir"), K("w0.76", view_frame=2, angle="dir", layer="front"), K("w0.88", angle="dir"),
		K("w0.88", view_frame=3, angle="dir"), K("w1", frame=4, view_frame=4, angle="dir"), K("r0.36"),
		K("r0.36", frame=5, view_frame=1, angle="dir", length=0.85, layer="behind"), K("r0.46", length=OUT_MIN),
		K("r0.47", length=0.0), K("r0.6", frame=6)],
	("hammer-boom", "up"): [
		K("w0", frame=2, view="away", view_frame=1, angle="dir", length=OUT_MIN, layer="behind"),
		K("w0.07", length=0.85), K("w0.18", length=1.0), K("w0.61", angle=-94), K("w0.64", frame=3, angle="dir"),
		K("w0.76", view_frame=2, angle="dir"), K("w0.88", view_frame=3, angle="dir"),
		K("w1", frame=4, view_frame=4, angle="dir"), K("r0.35"), K("r0.36", frame=5, length=0.85),
		K("r0.46", length=OUT_MIN), K("r0.47", length=0.0), K("r0.6", frame=6)],
}


# The front and back chop and smashes swing through the weapon views (Round 2: toward the viewer on the
# down strips, away on the up strips): every key of those strips names its view (a key without one draws
# the side weapon).
VIEW_STRIPS = {(strike, direction): ("toward" if direction == "down" else "away")
	for strike in ("axe-chop", "hammer-thud", "hammer-boom") for direction in ("down", "up")}
for _strip, _view in VIEW_STRIPS.items():
	for _key in KEYS[_strip]:
		_key.setdefault("view", _view)

def at_ms(at: str, step: dict) -> float:
	phase, share = at[0], float(at[1:])
	w, a, r = float(step["windupMs"]), float(step["activeMs"]), float(step["recoveryMs"])
	return {"w": w * share, "a": w + a * share, "r": w + a + r * share}[phase]


def arc_angle(at: str, aim_deg: float, step: dict, cw: bool, flip: bool) -> float:
	"""The hit line's angle at `at` (in the active window): aim -/+ half arcDeg in the turning sense, in
	the game's frame, mirrored back into the source frame for a flip strip."""
	share = float(at[1:]) if at[0] == "a" else (0.0 if at[0] == "w" else 1.0)
	half = float(step["arcDeg"]) / 2.0
	sgn = 1.0 if cw else -1.0
	game = aim_deg - sgn * half + sgn * 2 * half * share
	return 180.0 - game if flip else game


def smash_angle(socket: np.ndarray, joint: float, weapon: Weapon, ground_y: float, bite: float) -> float:
	"""The stalk angle (degrees, forward: +x) that puts the joint where the head, at head_angle 0, stands
	on its lower face `bite` px into the ground line ground_y."""
	joint_y = ground_y + bite - (weapon.face_row - weapon.axis_row) * weapon.scale
	s = np.clip((joint_y - socket[1]) / max(joint, 1e-3), -0.95, 0.95)
	return math.degrees(math.asin(float(s)))


SMASH_BITE = 1.0  # game px the hammer's face sits into the ground line on the smash
CHOP_BITE = 4.0  # game px the axe's lowest blade point bites below the ground line on the side chop


def head_points(w: dict, weapon: Weapon) -> np.ndarray:
	"""Every opaque px of the head where the game draws it (game px from the slime's centre)."""
	n = np.array([-w["head_axis"][1], w["head_axis"][0]])
	sy = -1.0 if w["flipped"] else 1.0
	return (w["socket"] + w["axis"] * w["joint"] + np.outer((weapon.head_pts[:, 0] - weapon.head_start) * weapon.scale,
		w["head_axis"]) + np.outer(sy * (weapon.head_pts[:, 1] - weapon.axis_row) * weapon.scale, n))


def bite_angle(frame: dict, weapon: Weapon, neck: dict, ground_y: float, bite: float, arm_px: float = 0.0) -> float:
	"""The smallest forward angle (degrees) at which the head's lowest px reaches `bite` below the
	ground line: the side chop lands its blade on the ground in front."""
	for a in np.arange(0.0, 90.0, 0.5):
		pose = {"angle": float(a), "head_angle": float(a), "length": 1.0, "layer": "behind", "frame": 0}
		w = weapon_at(pose, frame, weapon, neck, False, 0.0, arm_px)
		if head_points(w, weapon)[:, 1].max() >= ground_y + bite:
			return float(a)
	return 60.0


def resolve_keys(raw: list[dict], frames: list[dict], aim_deg: float, step: dict, cw: bool, flip: bool,
		weapon: Weapon, neck: dict, ground_y: float, arm_px: float = 0.0, contact_length: float = 1.0) -> list[dict]:
	"""The manifest's keys: "arc" and "smash" made numbers, each arc angle unwrapped next to the key before
	it (the game eases the raw numbers); with contact_length < 1 every key from w1 on shows the weapon at
	most that far out (the strip's drawn reach matched to the side view's)."""
	out = _resolve_keys(raw, frames, aim_deg, step, cw, flip, weapon, neck, ground_y, arm_px)
	if contact_length < 1.0:
		length = FIRST_LENGTH
		w1 = at_ms("w1", step)
		for k in out:
			length = float(k.get("length", length))
			if at_ms(k["at"], step) >= w1 - 1e-6:
				k["length"] = round(min(length, contact_length), 3)
	return out


def _resolve_keys(raw: list[dict], frames: list[dict], aim_deg: float, step: dict, cw: bool, flip: bool,
		weapon: Weapon, neck: dict, ground_y: float, arm_px: float = 0.0) -> list[dict]:
	out, prev, frame, view, vf = [], None, 2, "", 1
	for key in raw:
		k = dict(key)
		frame = int(k.get("frame", frame))
		kv = k.get("view", "")
		if kv != view:
			vf = 1
		view = kv
		vf = int(k.get("view_frame", vf))
		for name in ("angle", "head_angle"):
			v = k.get(name)
			if v == "dir":
				v = weapon.views.frame(view, vf)["dir"]
			elif v == "arc":
				v = arc_angle(k["at"], aim_deg, step, cw, flip)
				if prev is not None:
					v = prev + (v - prev + 180.0) % 360.0 - 180.0
			elif v == "smash":
				f = frames[frame - 1]
				v = smash_angle(np.array(f["socket_game"]), neck_len_at(neck, f["knob_w"]) + arm_px + weapon.handle_px,
					weapon, ground_y, SMASH_BITE)
			elif v == "bite":
				v = bite_angle(frames[frame - 1], weapon, neck, ground_y, CHOP_BITE, arm_px)
			if v is not None:
				k[name] = round(float(v), 2)
		if "angle" in k:
			prev = float(k["angle"])
		out.append(k)
	return out


# ================================================================== the game's drawing, ported
# shape_strikes.gd (keys, key_ms, key_pose, view_angle, aim_turn) and shape_visuals.gd
# (_strike_weapon_at, _draw_strike_parts, _draw_strike_neck, _slice_on_axis), so the previews show what
# the game draws from the manifest alone.
HEAD_COLLAR_TX = 16.0
HEAD_CLIP_DOT = 0.15
NECK_GROW_SHARE = 0.25
NECK_MIN_ACROSS = 0.6
FIRST_LENGTH = 1.0


def game_keys(keys: list[dict]) -> list[dict]:
	out, number, angle, length, layer, view, vf = [], 2, 0.0, FIRST_LENGTH, "behind", "", 1
	for key in keys:
		number = int(key.get("frame", number))
		angle = float(key.get("angle", angle))
		length = min(max(float(key.get("length", length)), 0.0), 1.0)
		if "layer" in key:
			layer = "front" if key["layer"] == "front" else "behind"
		kv = key.get("view", "") if key.get("view") in VIEWS else ""
		if kv != view:
			vf = 1
		view = kv
		vf = min(max(int(key.get("view_frame", vf)), 1), 4)
		out.append({"at": key["at"], "frame": number, "angle": angle, "length": length,
			"head_angle": float(key.get("head_angle", angle)), "layer": layer, "view": view,
			"view_frame": vf if view else 0})
	return out


def key_pose(keys: list[dict], step: dict, t: float) -> dict:
	before = keys[0]
	if t < at_ms(before["at"], step):
		return dict(before)
	for after in keys[1:]:
		to = at_ms(after["at"], step)
		if t < to:
			fr = at_ms(before["at"], step)
			k = min(max((t - fr) / (to - fr), 0.0), 1.0) if to > fr else 1.0
			return {"frame": before["frame"], "layer": before["layer"], "view": before["view"],
				"view_frame": before["view_frame"],
				**{n: before[n] + (after[n] - before[n]) * k for n in ("angle", "length", "head_angle")}}
		before = after
	return dict(before)


DOWN_FRONT_Y = 0.5  # shape_visuals.gd: a `behind` weapon whose axis points down more than this, on a
# downward aim (snapped y > 0.5), draws its part past the neck's tip over the world


def weapon_at(pose: dict, frame: dict, weapon: Weapon, neck: dict, flipped: bool, turn: float,
		arm_px: float = 0.0, aim_y: float = 0.0) -> dict:
	"""_strike_weapon_at: game px from the slime's centre (the Visual's origin). The strip's jelly arm
	(arm = `arm_px` x length) stretches the neck's tube (arm_from_x to arm_to_x), so the handle starts that
	much further out; the slide leaves the arm out (it pulls in by itself). A weapon view: its pivot on the
	neck's tip, slid back by (1 - length) x (hidden_px + the neck's own length + the view rect's reach
	along its dir), turned by angle - dir (_strike_view)."""
	view = lambda a: (180.0 - a if flipped else a) + turn  # noqa: E731
	angle, head_angle = view(pose["angle"]), view(pose["head_angle"])
	length = min(max(pose["length"], 0.0), 1.0)
	socket = np.array(frame["socket_game"], np.float64)
	if flipped:
		socket[0] = -socket[0]
	neck_scale = frame["knob_w"] / neck["width_px"]
	neck_own = max(0.0, neck["tip_x"] - neck["root_x"]) * neck_scale
	arm = max(0.0, arm_px) * length
	neck_len = neck_own + arm
	joint = neck_len + weapon.handle_px
	slide = (1.0 - length) * (weapon.hidden_px + neck_own + weapon.handle_px + weapon.head_depth)
	axis = unit(angle)
	layer = pose["layer"]
	if layer == "behind" and axis[1] > DOWN_FRONT_Y and aim_y > 0.5:
		layer = "front"
	out = {"socket": socket, "axis": axis, "head_axis": unit(head_angle), "angle": angle,
		"head_angle": head_angle, "layer": layer, "flipped": flipped, "length": length,
		"handle_from": -weapon.hidden_px - slide, "joint": joint - slide, "neck_scale": neck_scale,
		"neck_len": neck_len, "neck_tip": neck_len, "neck_own": neck_own, "arm": arm,
		"neck_grow": min(max(length / NECK_GROW_SHARE, 0.0), 1.0), "view": ""}
	if pose.get("view") and weapon.views is not None:
		vw = weapon.views
		f = vw.frame(pose["view"], pose["view_frame"])
		k = vw.scale[pose["view"]]
		x0, y0, ww, hh = f["rect"]
		d = unit(f["dir"])
		corners = np.array([[x0, y0], [x0 + ww, y0], [x0 + ww, y0 + hh], [x0, y0 + hh]], np.float64)
		reach_px = float(np.max((corners - np.array(f["pivot"])) @ d)) * k
		vslide = (1.0 - length) * (weapon.hidden_px + neck_own + reach_px)
		out.update({"view": pose["view"], "view_frame": pose["view_frame"], "view_scale": k,
			"pivot_pos": socket + axis * (neck_own + arm - vslide), "rot": angle - f["dir"],
			"view_entry": f})
	return out


def head_point(w: dict, weapon: Weapon, tex_pt) -> np.ndarray:
	"""A head texture point (x >= head_start) where the game draws it."""
	n = np.array([-w["head_axis"][1], w["head_axis"][0]])
	sy = -1.0 if w["flipped"] else 1.0
	return (w["socket"] + w["axis"] * w["joint"] + w["head_axis"] * (tex_pt[0] - weapon.head_start) * weapon.scale
		+ n * sy * (tex_pt[1] - weapon.axis_row) * weapon.scale)


class Canvas:
	"""A premultiplied float canvas in preview px: ppg px per game px, game point `centre` at `origin_px`."""

	def __init__(self, w: int, h: int, ppg: float, origin_px: np.ndarray):
		self.a = np.zeros((h, w, 4), np.float32)
		self.ppg = ppg
		self.o = np.asarray(origin_px, np.float64)

	def px(self, p_game) -> np.ndarray:
		return self.o + np.asarray(p_game, np.float64) * self.ppg


def slice_on_axis(cv: Canvas, mips: list[np.ndarray], src: tuple[float, float, float, float], origin: np.ndarray,
		axis: np.ndarray, along_from: float, along_len: float, across: float, flip: bool, axis_row: float,
		gain=None, clip_from: float = -math.inf, clip_to: float = math.inf) -> None:
	"""_slice_on_axis: src (x0, y0, w, h, texture px) drawn from `origin` (game px) along `axis`, from
	`along_from` for `along_len` game px, the part inside [clip_from, clip_to], `across` game px per
	texture px across with row `axis_row` on the axis, mirrored across it when `flip`; sampled from the
	mip level the scale needs (the textures import with mipmaps)."""
	if along_len <= 0.01 or across <= 0.0:
		return
	start, end = max(along_from, clip_from), min(along_from + along_len, clip_to)
	if end - start <= 0.01:
		return
	x0, y0, sw, sh = src
	nrm = np.array([-axis[1], axis[0]])
	sy = -1.0 if flip else 1.0
	top, bottom = (y0 - axis_row) * across, (y0 + sh - axis_row) * across
	corners = [origin + axis * a + nrm * sy * b for a in (start, end) for b in (top, bottom)]
	pts = np.array([cv.px(c) for c in corners])
	H, W = cv.a.shape[:2]
	bx0, by0 = max(int(math.floor(pts[:, 0].min())) - 1, 0), max(int(math.floor(pts[:, 1].min())) - 1, 0)
	bx1, by1 = min(int(math.ceil(pts[:, 0].max())) + 1, W), min(int(math.ceil(pts[:, 1].max())) + 1, H)
	if bx0 >= bx1 or by0 >= by1:
		return
	gy, gx = np.mgrid[by0:by1, bx0:bx1].astype(np.float64) + 0.5
	rel_x = (gx - cv.o[0]) / cv.ppg - origin[0]
	rel_y = (gy - cv.o[1]) / cv.ppg - origin[1]
	along = rel_x * axis[0] + rel_y * axis[1]
	perp = (rel_x * nrm[0] + rel_y * nrm[1]) * sy
	tx = x0 + (along - along_from) / along_len * sw
	ty = axis_row + perp / across
	# the mip level: texture px per preview px across
	level = int(max(0, min(len(mips) - 1, math.floor(math.log2(max(1.0, 1.0 / (across * cv.ppg)))))))
	tex = mips[level]
	f = 2 ** level
	inside_t = (tx >= x0) & (tx <= x0 + sw) & (ty >= y0) & (ty <= y0 + sh)
	col = P.bilinear(tex, (tx / f - 0.5).astype(np.float32), (ty / f - 0.5).astype(np.float32))
	# anti-aliased ends along the axis (the cut and the clip)
	px_game = 1.0 / cv.ppg
	cov = np.clip((along - start) / px_game + 0.5, 0, 1) * np.clip((end - along) / px_game + 0.5, 0, 1)
	cov *= inside_t
	col *= cov[..., None]
	if gain is not None:
		col[..., :3] *= np.asarray(gain, np.float32)
	P.over(cv.a, col.astype(np.float32), bx0, by0)


def draw_parts(cv: Canvas, w: dict, weapon: Weapon, centre: np.ndarray, clip_from: float, clip_to: float) -> None:
	"""_draw_strike_parts."""
	if w["length"] <= 0.0:
		return
	low = max(clip_from, -weapon.hidden_px)
	if clip_to <= low:
		return
	origin = centre + w["socket"]
	axis, head_axis = w["axis"], w["head_axis"]
	if w["joint"] > w["handle_from"]:
		slice_on_axis(cv, weapon.mips, (0.0, 0.0, weapon.head_start, weapon.h), origin, axis, w["handle_from"],
			w["joint"] - w["handle_from"], weapon.scale * weapon.across, w["flipped"], weapon.axis_row, weapon.gain,
			low, clip_to)
	along = float(head_axis @ axis)
	head_low, head_high = -math.inf, math.inf
	if along > HEAD_CLIP_DOT:
		head_low = (low - w["joint"]) / along
		head_high = (clip_to - w["joint"]) / along
	elif w["joint"] < low or w["joint"] >= clip_to:
		return
	collar = HEAD_COLLAR_TX if along < 0.9998 else 0.0
	from_tx = max(0.0, weapon.head_start - collar)
	slice_on_axis(cv, weapon.mips, (from_tx, 0.0, weapon.w - from_tx, weapon.h), origin + axis * w["joint"], head_axis,
		(from_tx - weapon.head_start) * weapon.scale, (weapon.w - from_tx) * weapon.scale, weapon.scale, w["flipped"],
		weapon.axis_row, weapon.gain, head_low, head_high)


def draw_view(cv: Canvas, w: dict, weapon: Weapon, centre: np.ndarray, clip_from: float = -math.inf,
		clip_to: float = math.inf) -> None:
	"""_draw_strike_view: the view's frame (rect) placed by weapon_at, in the weapon's tint (the block's
	tint_gain), the part between clip_from and clip_to along the axis from the socket (never behind the
	hidden end)."""
	if w["length"] <= 0.0:
		return
	clip_from = max(clip_from, -weapon.hidden_px)
	if clip_to <= clip_from:
		return
	vw = weapon.views
	x0, y0, ww, hh = w["view_entry"]["rect"]
	img = vw.premul[y0:y0 + hh, x0:x0 + ww].copy()
	img[..., :3] *= weapon.gain
	px, py = w["view_entry"]["pivot"]
	layer, lx, ly = P.warp(np.ascontiguousarray(img), w["view_scale"] * cv.ppg, w["rot"], (px - x0, py - y0),
		tuple(cv.px(centre + w["pivot_pos"])), cv.a.shape[:2])
	h, ww2 = layer.shape[:2]
	gy, gx = np.mgrid[ly:ly + h, lx:lx + ww2].astype(np.float64) + 0.5
	o = cv.px(centre + w["socket"])
	along = ((gx - o[0]) * w["axis"][0] + (gy - o[1]) * w["axis"][1]) / cv.ppg
	k = np.clip((along - clip_from) * cv.ppg + 0.5, 0, 1) * np.clip((clip_to - along) * cv.ppg + 0.5, 0, 1)
	P.over(cv.a, (layer * k[..., None]).astype(np.float32), lx, ly)


def draw_neck(cv: Canvas, w: dict, neck: dict, neck_mips: list[np.ndarray], centre: np.ndarray) -> None:
	"""_draw_strike_neck (the weapon's colour without its tint: the body's jelly)."""
	if w["neck_scale"] <= 0.0 or w["neck_grow"] <= 0.0 or w["length"] <= 0.0:
		return
	width, height = float(neck["size"][0]), float(neck["size"][1])
	grow = w["neck_grow"]
	along = w["neck_scale"] * grow
	across = w["neck_scale"] * (NECK_MIN_ACROSS + (1 - NECK_MIN_ACROSS) * grow)
	root = neck["root_x"]
	cuts = [0.0, root, neck.get("arm_from_x", root), neck.get("arm_to_x", root), width]
	at = -root * along
	origin = centre + w["socket"]
	for i in range(len(cuts) - 1):
		a, b = cuts[i], cuts[i + 1]
		span = (b - a) * along + (w["arm"] * grow if i == 2 else 0.0)
		slice_on_axis(cv, neck_mips, (a, 0.0, b - a, height), origin, w["axis"], at, span, across, w["flipped"],
			neck["axis_row"])
		at += span


def view_points(w: dict, weapon: Weapon, pts_tex: np.ndarray) -> np.ndarray:
	"""Texture points of a view frame where the game draws them (game px from the slime's centre)."""
	f = w["view_entry"]
	r = math.radians(w["rot"])
	c, s_ = math.cos(r), math.sin(r)
	d = (pts_tex - np.array(f["pivot"])) * w["view_scale"]
	rot = np.stack([d[:, 0] * c - d[:, 1] * s_, d[:, 0] * s_ + d[:, 1] * c], 1)
	return w["pivot_pos"] + rot


def reach(w: dict, weapon: Weapon) -> dict:
	"""The head's centre and its farthest point (the blade's edge, the hammer's far corner) from the
	slime's centre, game px."""
	if w.get("view"):
		f = w["view_entry"]
		hc = view_points(w, weapon, np.array([f["head"]], np.float64))[0]
		pts = view_points(w, weapon, weapon.views.points(w["view"], w["view_frame"]))
		d = np.hypot(pts[:, 0], pts[:, 1])
		return {"head_centre": hc, "head_centre_dist": float(np.hypot(*hc)), "far_dist": float(d.max()),
			"far_point": pts[int(np.argmax(d))]}
	hc = head_point(w, weapon, weapon.head_centre)
	pts = head_points(w, weapon)
	d = np.hypot(pts[:, 0], pts[:, 1])
	return {"head_centre": hc, "head_centre_dist": float(np.hypot(*hc)), "far_dist": float(d.max()),
		"far_point": pts[int(np.argmax(d))]}


# ================================================================== the manifest

WEAPON_NOTES = (
	"The War Axe's and the Hammer's strike frames (scripts/characters/pack-slime-weapon-strikes.py; "
	"docs/design/2026-10-12-weapon-strike-frames.md). Per strike: its sheet (`texture`), its weapon "
	"block (`weapon`), per direction the sheet row (a `flip` strip shows its `source` strike's row "
	"mirrored; its frames and keys are the source row's, unmirrored), per frame the socket (the knob's "
	"tip, cell px; `socket_game`: game px from the Visual's origin, the slime's centre) and `knob_w` "
	"(the knob's chord, game px: the code neck's root width), and the timeline `keys`: `at` "
	"w|a|r<share> of the step's windupMs / activeMs / recoveryMs; each key's frame shows from its `at`, "
	"its angle / length / head_angle are eased linearly (as numbers) to the next key's; a value a key "
	"leaves out is the previous key's, head_angle the key's own angle; layer steps. Angles: screen "
	"degrees in the strip's own frame (0 right, +90 down), from the socket along the handle. The game "
	"(shape_visuals.gd _strike_weapon_at) draws the weapon rigid at `scale`: the neck (neck.webp, root_x "
	"on the socket, uniformly scaled by knob_w / width_px) ends neck_len = (tip_x - root_x) x that scale "
	"from the socket; the strip's jelly arm (`arm_px`, per direction) stretches the neck's cone (root_x to "
	"tip_x) by arm_px, so the neck's tip is neck_len + arm_px out; the handle "
	"(texture x 0 to head_start, row axis_row on the axis, handle_across x scale thick) stretched from "
	"hidden_px behind the socket to handle_px past the neck's tip (the joint), the head from the joint at "
	"head_angle; the whole slid back along the axis by (1 - length) x (hidden_px + joint + the head's depth) "
	"and cut at the hidden end; `front` draws the part past the neck's tip over the world, as does a "
	"`behind` weapon pointing down (axis y > 0.5) on a downward aim. Mirrored: "
	"x negated, a -> 180 - a, the textures reflected across the axis. head_centre, face_row, "
	"socket_to_head_px, handle_width_game, head_depth_game, head_height_game: for reference. `contact` "
	"(per strike): the art's reach at the hit (the sweeps' a0.5, the chop's and smashes' w1): the head's "
	"centre and its farthest point (the Axe's blade edge, the Hammer's head corner) from the slime's "
	"centre, game px, and the Hammer's head centre along the aim (where it lands in front), each strip's "
	"arm_px set so the reach meets the game's numbers (`target`) where the art falls short, else its "
	"contact_length (every key from w1 holds length at most that) where it reaches past; every direction "
	"within 2 px of the side view's; far_edge_along_aim_game: the head's farthest px along the aim.")


def frames_entry(strip: Strip) -> list[dict]:
	out = []
	for s in strip.sockets:
		out.append({"socket": rounded(s["socket"]), "socket_game": rounded(s["socket_game"], 2),
			"knob_w": round(s["knob_w"], 2), "knob": s["knob"], "knob_out": round(s["knob_out"], 1)})
	return out


def strip_entry(strip: Strip) -> dict:
	return {"row": strip.row, "flip": False, "aim": list(AIM[strip.direction]), "source_scale": round(strip.scale, 5),
		"rest_centre": rounded([strip.rest_middle_cell, strip.ground_cell - strip.rest.height * strip.scale / 2]),
		"ground": round(strip.ground_cell, 1), "anchor": rounded([strip.anchor_cell_x, strip.ground_cell]),
		"arm_px": 0.0, "frames": frames_entry(strip)}


def write_json_atomic(path: Path, data: dict) -> None:
	text = json.dumps(data, indent="\t") + "\n"
	fd, tmp = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
	with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
		f.write(text)
	os.replace(tmp, path)


def merge_manifest(strikes: dict, weapons: dict, neck: dict) -> dict:
	"""shape-strikes.json with this script's strikes, `weapons` and `neck` merged in: every other key (the
	Spear's top level and strikes) stays; the Spear's strikes gain `texture` and `weapon` if missing."""
	manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8")) if MANIFEST_PATH.exists() else {}
	manifest.setdefault("strikes", {})
	for name, entry in manifest["strikes"].items():
		if name.startswith("spear-"):
			entry.setdefault("texture", manifest.get("texture", ""))
			entry.setdefault("weapon", "spear")
	for name, entry in strikes.items():
		manifest["strikes"][name] = entry
	manifest["weapons"] = weapons
	manifest["neck"] = neck
	return manifest


# ================================================================== the previews (the game, simulated)
PPG = 3.0  # preview px per game px
FEET_BELOW_CENTRE = 27.56  # the player's feet below its centre (the Visual's origin)
TICK_MS = 20.0
PRE_MS, POST_MS = 300.0, 340.0


def grass(w: int, h: int) -> np.ndarray:
	rng = np.random.default_rng(7)
	n = rng.normal(0, 1, (h // 10 + 2, w // 10 + 2)).astype(np.float32)
	n = np.asarray(Image.fromarray(n, "F").resize((w, h), Image.Resampling.BICUBIC))
	n2 = rng.normal(0, 1, (h // 3 + 2, w // 3 + 2)).astype(np.float32)
	n2 = np.asarray(Image.fromarray(n2, "F").resize((w, h), Image.Resampling.BICUBIC))
	base = np.array([0.36, 0.55, 0.22], np.float32)
	return np.clip(base[None, None, :] * (1 + 0.07 * n[..., None] + 0.04 * n2[..., None]), 0, 1)


def ellipse(cv: Canvas, c_game, rx: float, ry: float, alpha: float) -> None:
	c = cv.px(c_game)
	H, W = cv.a.shape[:2]
	rx, ry = rx * cv.ppg, ry * cv.ppg
	x0, x1 = int(max(c[0] - rx - 2, 0)), int(min(c[0] + rx + 2, W))
	y0, y1 = int(max(c[1] - ry - 2, 0)), int(min(c[1] + ry + 2, H))
	if x0 >= x1 or y0 >= y1:
		return
	gy, gx = np.mgrid[y0:y1, x0:x1].astype(np.float32) + 0.5
	r = np.hypot((gx - c[0]) / rx, (gy - c[1]) / ry)
	a = alpha * (1 - P.smoothstep(0.55, 1.0, r))
	layer = np.zeros((y1 - y0, x1 - x0, 4), np.float32)
	layer[..., 3] = a
	layer[..., :3] = np.array([0.08, 0.1, 0.02]) * a[..., None]
	P.over(cv.a, layer, x0, y0)


class Art:
	"""The packed sheets, weapons and neck as the previews read them (the manifest's own files)."""

	def __init__(self, manifest: dict, weapons: dict[str, Weapon], neck_rgba: np.ndarray):
		self.manifest = manifest
		self.weapons = weapons
		self.neck = manifest["neck"]
		self.neck_mips = mip_chain(P.premul(neck_rgba))
		self.sheets = {}
		self.cells: dict = {}
		s = CELL_TO_GAME * PPG
		self.cell_size = (int(round(CELL_W * s)), int(round(CELL_H * s)))
		self.cell_origin = ORIGIN * np.array([self.cell_size[0] / CELL_W, self.cell_size[1] / CELL_H])
		dummy = P.load_rgba(DUMMY_PATH)
		self.dummy = P.premul(dummy)
		self.dummy_mask = dummy[..., 3] > 0.5

	def cell(self, texture: str, row: int, frame: int, flipped: bool) -> np.ndarray:
		key = (texture, row, frame, flipped)
		if key not in self.cells:
			if texture not in self.sheets:
				path = GODOT / texture.replace("res://", "")
				self.sheets[texture] = P.premul(P.load_rgba(path))
			sheet = self.sheets[texture]
			c = sheet[row * CELL_H:(row + 1) * CELL_H, (frame - 1) * CELL_W:frame * CELL_W]
			c = P.resize_premul(np.ascontiguousarray(c), self.cell_size)
			self.cells[key] = np.ascontiguousarray(c[:, ::-1]) if flipped else c
		return self.cells[key]


def anticipation_offset(step: dict, t: float, aim: np.ndarray) -> np.ndarray:
	"""ShapeVisuals.art_pose's offset (the squash does not play on strike frames)."""
	plan = step.get("anticipation")
	if not plan or t < 0:
		return np.zeros(2)
	w, a = float(step["windupMs"]), float(step["activeMs"])
	pull_ms = min(max(float(plan.get("pullMs", 0)), 0.0), w)
	pull, push, jump = float(plan.get("pullPx", 0)), float(plan.get("pushPx", 0)), float(plan.get("jumpPx", 0))
	shift = lift = 0.0
	if t < pull_ms:
		k = t / max(1.0, pull_ms)
		shift = -pull * (1 - (1 - k) * (1 - k))
	elif t < w:
		k = min(max((t - pull_ms) / max(1.0, w - pull_ms), 0.0), 1.0)
		shift = -pull + (push + pull) * k * k
		lift = jump * 4 * k * (1 - k)
	elif t < w + a:
		k = min(max((t - w) / max(1.0, a), 0.0), 1.0)
		shift = push * (1 - (1 - (1 - k) * (1 - k)))
	return aim * shift + np.array([0.0, -lift])


def step_offset(step: dict, t: float, aim: np.ndarray) -> np.ndarray:
	"""How far the slime has stepped along the aim (stepPx over stepFromMs..stepToMs)."""
	px = float(step.get("stepPx", 0))
	fr = float(step.get("stepFromMs", 0))
	to = float(step.get("stepToMs", float(step["windupMs"]) + float(step["activeMs"])))
	if px <= 0 or to <= fr:
		return np.zeros(2)
	return aim * px * min(max((t - fr) / (to - fr), 0.0), 1.0)


class Variant:
	"""One preview: a strike in one view (its strip, mirrored for a left strike, turned on a diagonal)."""

	def __init__(self, art: Art, constants: dict, strike: str, direction: str, mirrored: bool = False,
			turn: float = 0.0, label: str = "", close: bool = False):
		self.art = art
		self.close = close
		self.strike = strike
		self.direction = direction
		self.entry = art.manifest["strikes"][strike]
		self.strip = self.entry[direction]
		self.weapon = art.weapons[self.entry["weapon"]]
		self.step = chain_step(constants, self.entry["weapon"], STRIKES[strike]["step"])
		self.flipped = mirrored != bool(self.strip.get("flip", False))
		own = np.array(self.strip["aim"], np.float64)
		if mirrored:
			own[0] = -own[0]
		self.aim = unit(angle_of(own) + turn)
		self.turn = turn
		self.keys = game_keys(self.strip["keys"])
		self.label = label or f"{strike} {direction}"
		self.texture = self.entry["texture"]
		self.row = int(self.strip["row"])
		w, a = float(self.step["windupMs"]), float(self.step["activeMs"])
		self.hit_ms = w + 0.5 * a if "arcDeg" in self.step and not self.step.get("chop") else w
		self.hit_stop = float(self.step.get("hitStopMs", 0))
		self.total = w + a + float(self.step["recoveryMs"])
		self.base = np.zeros(2)  # where the slime starts (a chain's later steps start where it stepped to)

	def step_time(self, wall: float) -> float:
		if wall < self.hit_ms:
			return wall
		if wall < self.hit_ms + self.hit_stop:
			return self.hit_ms
		return wall - self.hit_stop

	def state(self, t: float) -> dict:
		"""The slime's centre (world game px; feet at the origin at t 0), the shown frame and the weapon."""
		centre = self.base + np.array([0.0, -FEET_BELOW_CENTRE]) + step_offset(self.step, t, self.aim)
		feet_y = centre[1] + FEET_BELOW_CENTRE
		centre = centre + anticipation_offset(self.step, t, self.aim)
		if t < 0 or t > self.total:
			return {"centre": centre, "feet_y": feet_y, "frame": REST_FRAME, "weapon": None}
		pose = key_pose(self.keys, self.step, t)
		frame = pose["frame"]
		w = None
		if pose["length"] > 0.0:
			aim_y = unit(round(angle_of(self.aim) / 45.0) * 45.0)[1]  # ShapeDefs.snap8
			w = weapon_at(pose, self.strip["frames"][frame - 1], self.weapon, self.art.neck, self.flipped, self.turn,
				float(self.strip.get("arm_px", 0.0)), aim_y)
		return {"centre": centre, "feet_y": feet_y, "frame": frame, "weapon": w, "pose": pose}

	def contact(self) -> dict:
		st = self.state(self.hit_ms)
		w = st["weapon"]
		r = reach(w, self.weapon)
		r["along_aim"] = float(r["head_centre"] @ self.aim)
		pts = view_points(w, self.weapon, self.weapon.views.points(w["view"], w["view_frame"])) if w.get("view") \
			else head_points(w, self.weapon)
		r["far_along_aim"] = float(np.max(pts @ self.aim))
		return {**r, "centre": st["centre"]}


def place_dummy(v: Variant) -> dict:
	"""The training dummy where the weapon lands at the contact: its base (world game px; the texture's
	bottom-centre) so the weapon's farthest point sits DUMMY_BITE px inside its silhouette."""
	c = v.contact()
	far = c["centre"] + c["far_point"]
	aim = v.aim
	if v.close:  # a target inside the hit: its base under the head, its feet CLOSE_DROP lower than the slime's
		hc = c["centre"] + c["head_centre"]
		feet_y = v.base[1] + step_offset(v.step, v.hit_ms, aim)[1]
		base = np.array([hc[0], feet_y + CLOSE_DROP])
		return {"base": base, "sort_y": base[1]}
	s = DUMMY_SCALE
	mask = v.art.dummy_mask
	smash = v.entry["weapon"] == "hammer"

	def covers(base: np.ndarray, q: np.ndarray) -> bool:
		tx = 128.0 + (q[0] - base[0]) / s
		ty = 256.0 + (q[1] - base[1]) / s
		return 0 <= tx < 256 and 0 <= ty < 256 and bool(mask[int(ty), int(tx)])

	target = far - aim * DUMMY_BITE
	if abs(aim[0]) < 0.3:  # front and back views: below the head's centre by the swing's height
		hc = c["centre"] + c["head_centre"]
		rise = 4.0 if smash else FEET_BELOW_CENTRE
		base = np.array([hc[0], hc[1] + rise])
		return {"base": base, "sort_y": base[1] + 10.0}
	if abs(aim[0]) > 0.9:  # side: the dummy stands on the slime's ground line in front
		base_y = v.base[1] + step_offset(v.step, v.hit_ms, aim)[1]
		lift = 0.0
	else:
		lift = 6.0 if smash else 30.0
		base_y = None
	best = None
	for d in np.arange(80.0, -40.0, -0.5):
		base = far + aim * d
		base = np.array([base[0], base_y if base_y is not None else far[1] + lift + aim[1] * d])
		if covers(base, target):
			best = base
			break
	if best is None:
		best = np.array([far[0] + aim[0] * 20, (base_y if base_y is not None else far[1] + lift)])
	return {"base": best, "sort_y": best[1] + 10.0}


DUMMY_BITE = 2.5
CLOSE_DROP = 4.0  # the close dummy's feet below the slime's: y-sorted in front of it
DUMMY_SEE_THROUGH = 0.38  # a dummy below the slime is drawn over it (y-sorted): faint, so the hit shows


def wobble(t_ms: float) -> float:
	t = t_ms / 1000.0
	return math.degrees(0.22 * math.exp(-4.5 * t) * math.cos(6.0 * math.pi * t))


def render(v: Variant, wall: float, dummy: dict, cv_shape: tuple[int, int], origin_px: np.ndarray,
		bg: np.ndarray, see_through: bool) -> Image.Image:
	t = v.step_time(wall)
	st = v.state(t)
	cv = Canvas(cv_shape[1], cv_shape[0], PPG, origin_px)
	centre = st["centre"]
	ellipse(cv, (centre[0], st["feet_y"] - 1.0), 17.0, 4.0, 0.3)
	ellipse(cv, (dummy["base"][0], dummy["base"][1] - 1.0), 18.0, 4.0, 0.26)
	# the dummy: white during the hit-stop, pink after, rocking
	dt = v.art.dummy.copy()
	since = wall - v.hit_ms
	lean = 0.0
	if 0 <= since < v.hit_stop:
		amt, col = 0.9, np.array([1.0, 1.0, 1.0])
	elif v.hit_stop <= since < v.hit_stop + 80:
		amt, col = 0.55 * (1 - (since - v.hit_stop) / 80) + 0.15, np.array([1.0, 0.56, 0.66])
	else:
		amt, col = 0.0, None
	if col is not None:
		dt[..., :3] = dt[..., :3] * (1 - amt) + col[None, None, :] * dt[..., 3:4] * amt
	if since >= v.hit_stop:
		lean = wobble(since - v.hit_stop) * (1 if v.aim[0] >= -0.1 else -1)
	if see_through:
		dt = dt * DUMMY_SEE_THROUGH
	dl, dx, dy = P.warp(dt, DUMMY_SCALE * PPG, lean, (128.0, 256.0), tuple(cv.px(dummy["base"])), cv.a.shape[:2])
	dummy_first = dummy["sort_y"] < st["feet_y"]
	if dummy_first:
		P.over(cv.a, dl, dx, dy)
	w = st["weapon"]
	front = w is not None and w["layer"] == "front"
	on_view = w is not None and bool(w.get("view"))
	if w is not None and on_view:
		draw_view(cv, w, v.weapon, centre, -math.inf, w["neck_tip"] if front else math.inf)
	elif w is not None:
		draw_parts(cv, w, v.weapon, centre, -math.inf, w["neck_tip"] if front else math.inf)
	cell = v.art.cell(v.texture, v.row, st["frame"], v.flipped)
	o = cv.px(centre) - v.art.cell_origin
	P.over(cv.a, cell, int(round(o[0])), int(round(o[1])))
	if w is not None:
		draw_neck(cv, w, v.art.neck, v.art.neck_mips, centre)
	if not dummy_first:
		P.over(cv.a, dl, dx, dy)
	if front and on_view:
		draw_view(cv, w, v.weapon, centre, w["neck_tip"], math.inf)
	elif front:
		draw_parts(cv, w, v.weapon, centre, w["neck_tip"], math.inf)
	rgb = cv.a[..., :3] + bg * (1 - cv.a[..., 3:4])
	return Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def bounds(v: Variant, dummy: dict, walls: list[float]) -> tuple[float, float, float, float]:
	xs, ys = [], []
	b = dummy["base"]
	xs += [b[0] - 34, b[0] + 34]
	ys += [b[1] - 110, b[1] + 6]
	for wall in walls:
		st = v.state(v.step_time(wall))
		c = st["centre"]
		xs += [c[0] - 42, c[0] + 42]
		ys += [c[1] - 42, st["feet_y"] + 8]
		w = st["weapon"]
		if w is not None:
			r = reach(w, v.weapon)
			for p in (w["socket"], r["far_point"], r["head_centre"]):
				xs.append(c[0] + p[0])
				ys.append(c[1] + p[1])
			hr = 0.5 * math.hypot(v.weapon.w - v.weapon.head_start, v.weapon.h) * v.weapon.scale
			if w.get("view"):
				hr = w["view_entry"]["extent"] * w["view_scale"]
			xs += [c[0] + r["head_centre"][0] - hr, c[0] + r["head_centre"][0] + hr]
			ys += [c[1] + r["head_centre"][1] - hr, c[1] + r["head_centre"][1] + hr]
	return min(xs) - 6, min(ys) - 6, max(xs) + 6, max(ys) + 6


def preview_variant(v: Variant, folder: Path, name: str) -> tuple[list[Image.Image], list[float], int]:
	dummy = place_dummy(v)
	end = v.total + v.hit_stop
	walls = [-PRE_MS] + list(np.arange(0.0, end + TICK_MS / 2, TICK_MS)) + [end + POST_MS]
	x0, y0, x1, y1 = bounds(v, dummy, walls)
	W, H = int(math.ceil((x1 - x0) * PPG)), int(math.ceil((y1 - y0) * PPG + 18))
	origin = np.array([-x0 * PPG, -y0 * PPG + 18])
	bg = grass(W, H)
	see = v.aim[1] > 0.5  # a dummy below the slime is drawn over it: see-through so the hit shows
	ims, durs = [], []
	f = font(13)
	hit_index = 0
	for j, wall in enumerate(walls):
		im = render(v, wall, dummy, (H, W), origin, bg, see)
		d = ImageDraw.Draw(im)
		t = v.step_time(wall)
		st = v.state(t)
		tag = "rest" if wall < 0 or t > v.total else phase_tag(v, t)
		if v.hit_ms <= wall < v.hit_ms + v.hit_stop:
			tag += " HIT-STOP"
			hit_index = hit_index or j
		d.rectangle([0, 0, W, 17], fill=(20, 22, 24))
		d.text((4, 2), f"{v.label}  {tag}  f{st['frame']}", fill=(235, 235, 235), font=f)
		ims.append(im)
		durs.append(int(PRE_MS) if j == 0 else (int(POST_MS) if j == len(walls) - 1 else int(TICK_MS)))
	save_gif(ims, durs, folder / f"{name}.gif")
	return ims, walls, hit_index


def phase_tag(v: Variant, t: float) -> str:
	w, a, r = float(v.step["windupMs"]), float(v.step["activeMs"]), float(v.step["recoveryMs"])
	if t < w:
		return f"w{t / w:.2f}"
	if t < w + a:
		return f"a{(t - w) / a:.2f}"
	return f"r{(t - w - a) / r:.2f}"


def save_gif(ims: list[Image.Image], durs: list[int], path: Path) -> None:
	w, h = ims[0].size
	pick = ims[::max(1, len(ims) // 12)]
	m = Image.new("RGB", (w, h * len(pick)))
	for i, im in enumerate(pick):
		m.paste(im, (0, i * h))
	pal = m.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
	q = [im.quantize(palette=pal, dither=Image.Dither.NONE) for im in ims]
	q[0].save(path, save_all=True, append_images=q[1:], duration=durs, loop=0, optimize=False, disposal=1)


def contact_sheet(rows: list[tuple[str, list[Image.Image], list[float]]], path: Path, every: int = 2) -> None:
	"""Each variant a row: its ticks (every `every`-th, half size), the rest frame first."""
	tiles_rows = []
	for label, ims, walls in rows:
		pick = [ims[0]] + ims[1:-1:every] + [ims[-1]]
		half = [im.resize((im.width // 2, im.height // 2), Image.Resampling.LANCZOS) for im in pick]
		tiles_rows.append(half)
	W = max(sum(t.width + 2 for t in r) for r in tiles_rows)
	H = sum(max(t.height for t in r) + 2 for r in tiles_rows)
	out = Image.new("RGB", (W, H), (16, 16, 18))
	y = 0
	for r in tiles_rows:
		x = 0
		for t in r:
			out.paste(t, (x, y))
			x += t.width + 2
		y += max(t.height for t in r) + 2
	out.save(path)


def neck_test(art: Art, path: Path) -> None:
	"""The neck and the weapon on every knob frame at the knob's outward angle and 40 degrees either
	side (length 1, behind), 8 px per game px, cropped round the socket: the join must read as grown."""
	k = 8.0
	tiles = []
	f = font(13)
	for strike, entry in art.manifest["strikes"].items():
		if strike.startswith("spear-"):
			continue
		weapon = art.weapons[entry["weapon"]]
		for direction in DIRECTIONS:
			strip = entry.get(direction)
			if strip is None or strip.get("flip"):
				continue
			for number in (2, 3, 4, 5):
				fr = strip["frames"][number - 1]
				if not fr["knob"]:
					continue
				for da in (-40.0, 0.0, 40.0):
					a = fr["knob_out"] + da
					pose = {"frame": number, "angle": a, "length": 1.0, "head_angle": a, "layer": "behind"}
					w = weapon_at(pose, fr, weapon, art.neck, False, 0.0, float(strip.get("arm_px", 0.0)))
					size = 28.0 + float(strip.get("arm_px", 0.0))
					cv = Canvas(int(2 * size * k), int(2 * size * k), k, np.array([size * k, size * k]) - w["socket"] * k)
					draw_parts(cv, w, weapon, np.zeros(2), -math.inf, math.inf)
					sheet = art.sheets.get(entry["texture"])
					if sheet is None:
						art.cell(entry["texture"], strip["row"], number, False)
						sheet = art.sheets[entry["texture"]]
					c = sheet[strip["row"] * CELL_H:(strip["row"] + 1) * CELL_H, (number - 1) * CELL_W:number * CELL_W]
					sc = CELL_TO_GAME * k
					big = P.resize_premul(np.ascontiguousarray(c), (int(round(CELL_W * sc)), int(round(CELL_H * sc))))
					o = cv.px(np.zeros(2)) - ORIGIN * sc
					P.over(cv.a, big, int(round(o[0])), int(round(o[1])))
					draw_neck(cv, w, art.neck, art.neck_mips, np.zeros(2))
					bg = np.full(cv.a.shape[:2] + (3,), 0.42, np.float32)
					rgb = cv.a[..., :3] + bg * (1 - cv.a[..., 3:4])
					im = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB")
					ImageDraw.Draw(im).text((4, 3), f"{strike} {direction} f{number} {a:+.0f}", fill=(255, 255, 255), font=f)
					tiles.append(im)
	cols = 9
	tw, th = tiles[0].size
	out = Image.new("RGB", (cols * (tw + 2), math.ceil(len(tiles) / cols) * (th + 2)), (10, 10, 10))
	for i, t in enumerate(tiles):
		out.paste(t, ((i % cols) * (tw + 2), (i // cols) * (th + 2)))
	out = out.resize((out.width // 2, out.height // 2), Image.Resampling.LANCZOS)
	out.save(path)


VARIANTS = [
	# (strike, direction, mirrored, turn, label)
	("axe-sweep", "side", False, 0.0, "sweep right"), ("axe-sweep", "side", True, 0.0, "sweep left"),
	("axe-sweep", "side", False, 45.0, "sweep down-right (side +45)"),
	("axe-sweep", "down", False, 0.0, "sweep down"), ("axe-sweep", "up", False, 0.0, "sweep up"),
	("axe-backswing", "side", False, 0.0, "backswing right"), ("axe-backswing", "side", True, 0.0, "backswing left"),
	("axe-backswing", "down", False, 0.0, "backswing down (flip)"), ("axe-backswing", "up", False, 0.0, "backswing up (flip)"),
	("axe-chop", "side", False, 0.0, "chop right"), ("axe-chop", "side", True, 0.0, "chop left"),
	("axe-chop", "side", False, 45.0, "chop down-right (side +45)"),
	("axe-chop", "down", False, 0.0, "chop down"), ("axe-chop", "up", False, 0.0, "chop up"),
	("hammer-thud", "side", False, 0.0, "thud right"), ("hammer-thud", "side", True, 0.0, "thud left"),
	("hammer-thud", "side", False, 45.0, "thud down-right (side +45)"),
	("hammer-thud", "down", False, 0.0, "thud down"), ("hammer-thud", "up", False, 0.0, "thud up"),
	("hammer-boom", "side", False, 0.0, "boom right"), ("hammer-boom", "side", True, 0.0, "boom left"),
	("hammer-boom", "down", False, 0.0, "boom down"), ("hammer-boom", "up", False, 0.0, "boom up"),
	# a target inside the hit, its feet a few px lower (y-sorted in front of the slime)
	("axe-chop", "side", False, 0.0, "chop right, close target"),
	("hammer-thud", "side", False, 0.0, "thud right, close target"),
	("hammer-boom", "side", False, 0.0, "boom right, close target"),
]


CHAINS = {"axe": ("axe-sweep", "axe-backswing", "axe-chop"), "hammer": ("hammer-thud", "hammer-boom")}


def preview_chain(art: Art, constants: dict, weapon: str, folder: Path) -> None:
	"""The shape's chain, side view facing right, at real speed: each step cut at its cancelAtMs (the
	next tap), the last played out; the dummy where the first step lands; 3 px and 1 px (x 2) per game px."""
	parts = []
	base = np.zeros(2)
	for j, strike in enumerate(CHAINS[weapon]):
		v = Variant(art, constants, strike, "side", False, 0.0, strike)
		v.base = base.copy()
		last = j == len(CHAINS[weapon]) - 1
		cut = v.total + v.hit_stop + TICK_MS if last else float(v.step.get("cancelAtMs", v.total)) + v.hit_stop
		parts.append((v, cut))
		base = base + step_offset(v.step, 1e9, v.aim)
	dummy = place_dummy(parts[0][0])
	walls = []
	for v, cut in parts:
		walls += [(v, t) for t in np.arange(0.0, cut, TICK_MS)]
	walls = [(parts[0][0], -PRE_MS)] + walls
	xs = []
	for v, cut in parts:
		xs.append(bounds(v, dummy, [t for vv, t in walls if vv is v]))
	x0, y0 = min(b[0] for b in xs), min(b[1] for b in xs)
	x1, y1 = max(b[2] for b in xs), max(b[3] for b in xs)
	W, H = int(math.ceil((x1 - x0) * PPG)), int(math.ceil((y1 - y0) * PPG + 18))
	origin = np.array([-x0 * PPG, -y0 * PPG + 18])
	bg = grass(W, H)
	ims, durs = [], []
	f = font(13)
	for k, (v, wall) in enumerate(walls):
		im = render(v, wall, dummy, (H, W), origin, bg, False)
		d = ImageDraw.Draw(im)
		t = v.step_time(wall)
		tag = "rest" if wall < 0 or t > v.total else phase_tag(v, t)
		d.rectangle([0, 0, W, 17], fill=(20, 22, 24))
		d.text((4, 2), f"{weapon} chain  {v.strike} {tag}", fill=(235, 235, 235), font=f)
		ims.append(im)
		durs.append(int(PRE_MS) if k == 0 else int(TICK_MS))
	durs[-1] = int(POST_MS)
	save_gif(ims, durs, folder / f"{weapon}-chain.gif")
	game = [im.resize((max(1, round(im.width / PPG)) * 2, max(1, round(im.height / PPG)) * 2), Image.Resampling.LANCZOS)
		for im in ims]
	save_gif(game, durs, folder / f"{weapon}-chain-game.gif")
	print(f"  preview {weapon}-chain.gif, {weapon}-chain-game.gif ({len(ims)} frames)")


def variant_name(strike: str, direction: str, mirrored: bool, turn: float, label: str = "") -> str:
	tail = direction if direction != "side" else ("left" if mirrored else ("down-right" if turn else "right"))
	return f"{strike}-{tail}" + ("-close" if "close" in label else "")


def write_previews(folder: Path, art: Art, constants: dict, only: list[str] | None = None) -> None:
	folder.mkdir(parents=True, exist_ok=True)
	sheets: dict[str, list] = {}
	for strike, direction, mirrored, turn, label in VARIANTS:
		name = variant_name(strike, direction, mirrored, turn, label)
		if only and not any(o in name for o in only):
			continue
		v = Variant(art, constants, strike, direction, mirrored, turn, label, close="close" in label)
		ims, walls, _ = preview_variant(v, folder, name)
		sheets.setdefault(strike, []).append((label, ims, walls))
		print(f"  preview {name}.gif ({len(ims)} frames)")
	for strike, rows in sheets.items():
		if not only:
			contact_sheet(rows, folder / f"{strike}-sheet.png")
	if not only:
		neck_test(art, folder / "neck-joins.png")
		for weapon in CHAINS:
			preview_chain(art, constants, weapon, folder)


# ================================================================== the jelly arms
# The hit numbers the game sets (the lead, 2026-10-12): the sweeps' radius 76 (blade tip), the chop's 70,
# the smashes' impact offset 68 (head centre along the aim; the Quake shares the BOOM's art). A strip whose
# art falls short of its target gets a jelly arm (`arm_px`) that reaches the weapon out to it; one that
# already reaches past keeps 0.
REACH_TARGETS = {"axe-sweep": ("blade", 76.0), "axe-backswing": ("blade", 76.0), "axe-chop": ("blade", 70.0),
	"hammer-thud": ("along", 68.0), "hammer-boom": ("along", 68.0)}


REACH_TOLERANCE = 2.0  # game px: every direction's contact reach within this of the side view's
FAR_TOLERANCE = 3.0  # game px: the head's far edge along the aim within this of the side view's


def solve_reach(art: Art, constants: dict, strike: str, direction: str, context: tuple, kind: str,
		target: float) -> tuple[float, float]:
	"""The strip's arm_px when its art falls short of `target` (the arm reaches it out), else the contact
	length (< 1: the weapon slid into the jelly from w1 on) when it reaches past; (arm_px, contact_length).
	Leaves the strip's arm_px and keys set."""
	entry = art.manifest["strikes"][strike][direction]

	def measure_length(cl: float) -> float:
		entry["arm_px"] = 0.0
		entry["keys"] = resolve_keys(*context, arm_px=0.0, contact_length=round(float(cl), 3))
		c = Variant(art, constants, strike, direction).contact()
		return c["far_dist"] if kind == "blade" else c["along_aim"]

	r1 = measure_length(1.0)
	if r1 > target + 0.05:  # too far: slide it in (bisection on the length)
		lo, hi = 0.4, 1.0
		for _ in range(24):
			mid = (lo + hi) / 2
			if measure_length(mid) > target:
				hi = mid
			else:
				lo = mid
		cl = round((lo + hi) / 2, 3)
		measure_length(cl)
		return 0.0, cl
	return solve_arm(art, constants, strike, direction, context, kind, target), 1.0


def solve_arm(art: Art, constants: dict, strike: str, direction: str, context: tuple, kind: str,
		target: float) -> float:
	"""The strip's arm_px (game px, 2 decimals) that brings its contact reach to `target` (secant steps; the
	keys are resolved again for each arm: the chop's bite and the smash angles move with it); 0 when the
	art already reaches it. Leaves the strip's arm_px and keys set."""
	entry = art.manifest["strikes"][strike][direction]

	def measure(arm: float) -> float:
		entry["arm_px"] = round(float(arm), 2)
		entry["keys"] = resolve_keys(*context, arm_px=entry["arm_px"])
		c = Variant(art, constants, strike, direction).contact()
		return c["far_dist"] if kind == "blade" else c["along_aim"]

	r0 = measure(0.0)
	if r0 >= target - 0.05:
		return 0.0
	a_prev, r_prev = 0.0, r0
	a = target - r0
	for _ in range(12):
		r = measure(a)
		if abs(target - r) < 0.05:
			break
		slope = (r - r_prev) / (a - a_prev) if abs(a - a_prev) > 1e-6 else 1.0
		a_prev, r_prev = a, r
		a = max(0.0, a + (target - r) / max(slope, 0.2))
	measure(a)
	return entry["arm_px"]


# ================================================================== main

def main() -> None:
	parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
	parser.add_argument("--preview", nargs="?", const=PREVIEW_DEFAULT, type=Path,
		help="write the previews (default folder: prototypes/strikes-preview)")
	parser.add_argument("--knobs-only", action="store_true", help="only the knob sheets (into --preview's folder)")
	parser.add_argument("--only", default="", help="previews: only the variants whose name holds one of these (comma list)")
	parser.add_argument("--no-write", action="store_true", help="do not write the sheets, the neck or the manifest")
	args = parser.parse_args()
	constants = load_constants()
	refs = P.reference_figures()
	strips: dict[tuple[str, str], Strip] = {}
	for strike, spec in STRIKES.items():
		for direction in spec["rows"]:
			st = Strip(strike, direction, refs[direction])
			strips[(strike, direction)] = st
			print(f"{st.name}: row {st.row}, scale {st.scale:.4f} cell px per source px")
			for s in st.sockets:
				print(f"  f{s['frame']} {s['how']:<34} socket {rounded(s['socket_game'])} knob_w {s['knob_w']:.1f}"
					f" out {s['knob_out']:+.0f}")
	folder = args.preview or PREVIEW_DEFAULT
	if args.preview or args.knobs_only:
		folder.mkdir(parents=True, exist_ok=True)
		for weapon in ("axe", "hammer"):
			knobs_sheet([s for (k, _), s in strips.items() if STRIKES[k]["weapon"] == weapon], folder / f"knobs-{weapon}.png")
	if args.knobs_only:
		return
	proto = proto_factor(refs)
	colours = body_colours(strips[("axe-sweep", "side")])
	neck_rgba, neck_block = make_neck(colours)
	neck_ref = neck_len_at(neck_block, NECK["root_w"])
	weapons = {}
	for name, first in (("axe", "axe-sweep"), ("hammer", "hammer-thud")):
		body = body_colours(strips[(first, "side")])["jelly"]
		weapons[name] = Weapon(name, proto, body, neck_ref)
		weapons[name].views = WeaponViews(weapons[name])
	print(f"the in-game slime is {refs['side'].height * CELL_TO_GAME:.1f} game px tall: the prototypes' sizes x {proto:.4f}")
	# the strikes' manifest entries
	entries: dict = {}
	contexts: dict = {}  # what each strip's keys are resolved from (again for each arm tried)
	for strike, spec in STRIKES.items():
		weapon = weapons[spec["weapon"]]
		step = chain_step(constants, spec["weapon"], spec["step"])
		cw = step.get("sweep", "cw") == "cw"
		entry: dict = {"texture": "res://asset/characters/" + SHEETS[spec["weapon"]], "weapon": spec["weapon"],
			"step": spec["step"], "rest_frame": REST_FRAME}
		for direction in DIRECTIONS:
			if direction in spec["rows"]:
				strip = strips[(strike, direction)]
				e = strip_entry(strip)
				ground_y = (strip.ground_cell - ORIGIN[1]) * CELL_TO_GAME
				flip = False
			else:
				source = spec["flip"][direction]
				strip = strips[(source, direction)]
				e = strip_entry(strip)
				e["flip"] = True
				e["source"] = source
				ground_y = (strip.ground_cell - ORIGIN[1]) * CELL_TO_GAME
				flip = True
			contexts[(strike, direction)] = (KEYS[(strike, direction)], e["frames"], AIM_DEG[direction], step, cw,
				flip, weapon, neck_block, ground_y)
			e["keys"] = resolve_keys(*contexts[(strike, direction)])
			entry[direction] = e
		entries[strike] = entry
	weapons_block = {name: {**w.block(), "views": w.views.block()} for name, w in weapons.items()}
	weapons_block["notes"] = WEAPON_NOTES
	neck_out = dict(neck_block)
	neck_out["notes"] = ("The code neck (made by the packer): a horizontal jelly cone, root left; root_x is put on "
		"the frame's socket, the texture scaled uniformly so width_px is the frame's knob_w; its cone (root_x "
		"to tip_x) stretched along by the strip's arm_px (arm_from_x to arm_to_x: the straight tube in it); "
		"tip_x: where the handle starts showing (and a `front` weapon goes over the world). Drawn over the "
		"body in the weapon's colour without its tint (it is the body's jelly).")
	manifest = merge_manifest(entries, weapons_block, neck_out)
	# the contact reach, from the drawing itself
	sheets_px: dict[str, np.ndarray] = {}
	for weapon in ("axe", "hammer"):
		sheet = np.zeros((CELL_H * GRID, CELL_W * GRID, 4), np.float32)
		extents = []
		for (strike, direction), strip in strips.items():
			if STRIKES[strike]["weapon"] != weapon:
				continue
			cells, ext = strip.render()
			extents += [(strip.name, i + 1, e) for i, e in enumerate(ext)]
			for col, cell in enumerate(cells):
				sheet[strip.row * CELL_H:(strip.row + 1) * CELL_H, col * CELL_W:(col + 1) * CELL_W] = cell
		clipped = [f"{n} {i}" for n, i, e in extents if e[0] < MARGIN or e[1] < MARGIN or e[2] > CELL_W - MARGIN
			or e[3] > CELL_H - MARGIN]
		if clipped:
			raise SystemExit(f"frames do not fit their {CELL_W} x {CELL_H} cells: {', '.join(clipped)}")
		sheets_px[weapon] = sheet
	if not args.no_write:
		for weapon, sheet in sheets_px.items():
			out = Image.fromarray((np.clip(P.unpremul(sheet), 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
			path = GODOT / "asset/characters" / SHEETS[weapon]
			out.save(path, lossless=True, method=6)
			print(f"wrote {path.relative_to(ROOT)} ({out.width} x {out.height})")
		Image.fromarray((np.clip(neck_rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(NECK_PATH, lossless=True,
			method=6)
		for w in weapons.values():
			w.views.save()
		print(f"wrote {NECK_PATH.relative_to(ROOT)} {neck_block['size']}")
	art = Art(manifest, weapons, neck_rgba)
	if args.no_write:  # the sheets as packed now, without writing them
		for weapon, sheet in sheets_px.items():
			art.sheets["res://asset/characters/" + SHEETS[weapon]] = sheet
	drift: list[str] = []
	for strike in STRIKES:
		contact: dict = {}
		kind, target = REACH_TARGETS[strike]
		for direction in DIRECTIONS:
			arm, cl = solve_reach(art, constants, strike, direction, contexts[(strike, direction)], kind, target)
			v = Variant(art, constants, strike, direction)
			c = v.contact()
			at = "a0.5" if v.hit_ms > float(v.step["windupMs"]) else "w1"
			d = {"at": at, "arm_px": arm, "contact_length": cl, "head_centre": rounded(c["head_centre"], 1),
				"head_centre_game": round(c["head_centre_dist"], 1)}
			if STRIKES[strike]["weapon"] == "axe":
				d["blade_tip_game"] = round(c["far_dist"], 1)
			else:
				d["head_centre_along_aim_game"] = round(c["along_aim"], 1)
				d["head_far_game"] = round(c["far_dist"], 1)
			d["far_edge_along_aim_game"] = round(c["far_along_aim"], 1)
			d["target"] = target
			contact[direction] = d
		# every direction reaches as far as the side view (the hit areas are the same in all of them)
		side = contact["side"]
		key = "blade_tip_game" if kind == "blade" else "head_centre_along_aim_game"
		for direction in ("down", "up"):
			d = contact[direction]
			if abs(d[key] - side[key]) > REACH_TOLERANCE:
				drift.append(f"{strike} {direction}: {key} {d[key]} vs side {side[key]}")
			if abs(d["far_edge_along_aim_game"] - side["far_edge_along_aim_game"]) > FAR_TOLERANCE:
				print(f"  note: {strike} {direction}: far edge along the aim {d['far_edge_along_aim_game']} vs "
					f"side {side['far_edge_along_aim_game']} (more than {FAR_TOLERANCE} px apart)")
		side = contact["side"]
		top = {k: side[k] for k in side if k not in ("head_centre",)}
		manifest["strikes"][strike]["contact"] = {**top, "by_direction": contact}
		print(f"{strike} contact: " + "; ".join(f"{d} {c}" for d, c in contact.items()))
	if drift:
		raise SystemExit("the drawn reach at contact differs from the side view's by more than "
			f"{REACH_TOLERANCE} px (nothing written): " + "; ".join(drift))
	if not args.no_write:
		write_json_atomic(MANIFEST_PATH, manifest)
		print(f"wrote {MANIFEST_PATH.relative_to(ROOT)} (merged)")
	if args.preview:
		only = [o for o in args.only.split(",") if o]
		for w in weapons.values():
			w.views.debug_sheet(folder / f"views-{w.name}.png")
		write_previews(folder, art, constants, only or None)
		print(f"previews in {folder}")


if __name__ == "__main__":
	main()
