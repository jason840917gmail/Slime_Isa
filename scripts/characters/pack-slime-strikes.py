"""Pack the slime's Spear strike frames into the strike sheet, with the jelly neck baked in.

Sources (asset/Originals/characters/slime-v2/shapes/strikes/, GPT 2.5 with transparent
backgrounds, 2026-10-12): spear-<jab|finisher>-<side|down|up>.png, six body-only frames each in a
3 x 2 grid (the figures are not on exact thirds). Jab: 1 rest, 2 lean back, 3 lunge with the bump,
4 full lean, 5 spring back, 6 rest. Finisher: 1 rest, 2 big wind-up squash, 3 launch with the bump,
4 strongest (the cry), 5 bounce back, 6 rest. Side views face right (left is mirrored); in the front
views (down) the bump sits at the bottom of the front below the mouth and the spear goes down the
screen; in the back views (up) the bump rises at the top in front of the sprout and the spear goes up
the screen.

The look is the owner's choice of 2026-10-12 (asset/Originals/characters/slime-v2/shapes/README.md,
"Separate spear synced to body frames"): a separate rigid spear, drawn by code behind the body, its
hidden end inside the jelly, synchronised to these body frames. This script follows that prototype's
compositor:
- every frame of a strip at ONE scale, set by the rest frame (6), whose solid height matches page 1's
  first idle frame of that direction; the back (side: the left-most solid px of the lower body;
  down / up: the lower body's horizontal middle) and the ground on the same pixel in every frame;
- the rest frame stands where page 1's idle frame stands: its ground on the idle frame's, its middle
  on the idle frame's middle (page 1's x 128 is this sheet's x CELL_W / 2);
- frames 3 and 4 hold the spear: the tip of the painted bump is found per frame, and a jelly neck is
  grown from it along the strip's aim (a smooth signed-distance union of the body's painted interior
  and a band tapering to the spear's shaft, in the bump's own colours and grain, no outline at the
  join) and baked into the frame, so the game draws only the rigid spear; the neck's end is the
  socket, where the spear's visible part starts. In the back views the sprout stays in front of the
  neck.

Outputs:
  godot/asset/characters/<CELL_W>x<CELL_H>-tile_8x8-slime-v2-strikes.webp  8 x 8 cells (the other
      pages' grid, so the player's Sprite2D keeps hframes 8 / vframes 8); rows 0-2 spear-jab side /
      down / up, rows 3-5 spear-finisher side / down / up; columns 0-5 = frames 1-6
  godot/game/data/shape-strikes.json  per strike, direction and frame: the socket, the bump, the
      spear's state (hidden / part / full), the aim, and how cell px map to the player's px; MERGED:
      this script's top-level keys and strikes are replaced, the War Axe's and the Hammer's
      (pack-slime-weapon-strikes.py) stay

Usage: python scripts/characters/pack-slime-strikes.py [--preview <dir>]
  --preview writes check images there (the sheet on grass with the sockets, the joins with the spear
  drawn behind the body, the rest frames beside page 1's idle frames). Python 3.12 + Pillow + numpy.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/characters/slime-v2/shapes/strikes"
GODOT = ROOT / "godot"
PAGE_1 = GODOT / "asset/characters/256x256-tile_8x8-slime-v2-page-1.webp"
SPEAR_PATH = GODOT / "asset/characters/shapes/spear.webp"
SHAPES_JSON = GODOT / "asset/characters/shapes/shapes.json"
MANIFEST_OUT = GODOT / "game/data/shape-strikes.json"

GRID = 8
# The cell must hold every frame with its neck while the rest frame stands where page 1's idle frame
# stands, symmetric about its centre (the Visual's origin, so a left strike mirrors about it): the
# 2026-10-12 art needs 498 x 414 (the finisher's side lunge reaches 247 px right of the centre, its
# front-view neck 205 px below it). The run fails if a frame no longer fits and prints the size the
# art needs.
CELL_W = 512
CELL_H = 416
SHEET_NAME = f"{CELL_W}x{CELL_H}-tile_{GRID}x{GRID}-slime-v2-strikes.webp"
SHEET_OUT = GODOT / "asset/characters" / SHEET_NAME
SHEET_RES = "res://asset/characters/" + SHEET_NAME
SPEAR_RES = "res://asset/characters/shapes/spear.webp"
PAGE_CELL = 256
# game px per cell px: the player's Visual sprite scale (game/characters/player_slime.tscn)
CELL_TO_GAME = 0.28125
MARGIN = 2  # cell px a figure keeps from its cell's edges

STRIKES = ("spear-jab", "spear-finisher")
DIRECTIONS = ("side", "down", "up")
AIM = {"side": (1, 0), "down": (0, 1), "up": (0, -1)}
# np.rot90 turns that bring each direction's aim to +x (the side view's), so one bump finder and one
# neck grower serve all three directions
CANON_K = {"side": 0, "down": 1, "up": -1}
# page 1's first idle frame per direction: (column, row)
REFERENCE_CELLS = {"down": (0, 0), "up": (0, 1), "side": (0, 2)}
REST_FRAME = 6
SPEAR_STATES = {3: "part", 4: "full"}  # the other frames: "hidden"
# the spear's shaft in game px, as game/shapes/shape_visuals.gd draws it (SHAFT_PX, SHAFT_BIG_PX):
# the neck's thin end is baked to this width
SHAFT_GAME = {"spear-jab": 5.0, "spear-finisher": 6.0}
# the neck, in shaft widths: its width where it leaves the bump (the bump's chord there, clamped),
# its length (bump tip -> plain shaft: the socket), how far it runs on over the shaft and fades
NECK_W = (1.5, 2.3)
NECK_LEN = 1.5
NECK_OVERLAP = 1.0
SPEAR_TINT = 0.4  # how far the spear's jelly moves toward the body's jelly colour
ALPHA_SOLID = 0.5
PAD = 200  # source px around a figure while its neck is grown

LUMA = np.array([0.299, 0.587, 0.114], np.float32)


# ================================================================== image helpers

def load_rgba(path: Path) -> np.ndarray:
	return np.asarray(Image.open(path).convert("RGBA")).astype(np.float32) / 255.0


def premul(rgba: np.ndarray) -> np.ndarray:
	out = rgba.copy()
	out[..., :3] *= out[..., 3:4]
	return out


def unpremul(p: np.ndarray) -> np.ndarray:
	out = p.copy()
	a = np.maximum(out[..., 3:4], 1e-6)
	out[..., :3] = np.where(out[..., 3:4] > 1e-6, out[..., :3] / a, 0.0)
	return out


def resize_premul(src: np.ndarray, size: tuple[int, int], box: tuple[float, float, float, float] | None = None
		) -> np.ndarray:
	"""LANCZOS resize of a premultiplied float RGBA array to size (w, h), optionally of a float
	source box (x0, y0, x1, y1), pixel edges."""
	chans = [np.asarray(Image.fromarray(np.ascontiguousarray(src[..., c]), "F").resize(size,
		Image.Resampling.LANCZOS, box=box)) for c in range(4)]
	out = np.stack(chans, -1)
	out[..., 3] = np.clip(out[..., 3], 0, 1)
	out[..., :3] = np.clip(out[..., :3], 0, out[..., 3:4])
	return out


def over(dst: np.ndarray, src: np.ndarray, x0: int, y0: int) -> None:
	"""Premultiplied src over dst with src's top-left at (x0, y0), clipped."""
	h, w = src.shape[:2]
	H, W = dst.shape[:2]
	ax0, ay0 = max(x0, 0), max(y0, 0)
	ax1, ay1 = min(x0 + w, W), min(y0 + h, H)
	if ax0 >= ax1 or ay0 >= ay1:
		return
	s = src[ay0 - y0:ay1 - y0, ax0 - x0:ax1 - x0]
	d = dst[ay0:ay1, ax0:ax1]
	d[...] = s + d * (1.0 - s[..., 3:4])


def warp(src: np.ndarray, scale: float, angle_deg: float, pivot_src: tuple[float, float],
		pivot_dst: tuple[float, float], shape: tuple[int, int]) -> tuple[np.ndarray, int, int]:
	"""Premultiplied src scaled and rotated (clockwise on screen for +angle) so pivot_src lands on
	pivot_dst (previews only). Returns (layer, x0, y0) for over()."""
	if scale < 0.9:
		h, w = src.shape[:2]
		nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
		sx, sy = nw / w, nh / h
		src = resize_premul(src, (nw, nh))
		pivot_src = (pivot_src[0] * sx, pivot_src[1] * sy)
		scale = scale / ((sx + sy) / 2)
	h, w = src.shape[:2]
	a = math.radians(angle_deg)
	c, s = math.cos(a), math.sin(a)
	corners = np.array([[0, 0], [w, 0], [0, h], [w, h]], np.float32) - np.array(pivot_src, np.float32)
	xs = (corners[:, 0] * c - corners[:, 1] * s) * scale + pivot_dst[0]
	ys = (corners[:, 0] * s + corners[:, 1] * c) * scale + pivot_dst[1]
	H, W = shape
	x0, x1 = max(int(math.floor(xs.min())) - 1, 0), min(int(math.ceil(xs.max())) + 1, W)
	y0, y1 = max(int(math.floor(ys.min())) - 1, 0), min(int(math.ceil(ys.max())) + 1, H)
	if x0 >= x1 or y0 >= y1:
		return np.zeros((1, 1, 4), np.float32), 0, 0
	gy, gx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
	dx = gx + 0.5 - pivot_dst[0]
	dy = gy + 0.5 - pivot_dst[1]
	u = (c * dx + s * dy) / scale + pivot_src[0] - 0.5
	v = (-s * dx + c * dy) / scale + pivot_src[1] - 0.5
	return bilinear(src, u, v), x0, y0


def bilinear(src: np.ndarray, u: np.ndarray, v: np.ndarray) -> np.ndarray:
	h, w = src.shape[:2]
	pad = np.pad(src, ((1, 1), (1, 1), (0, 0)))
	u = u + 1
	v = v + 1
	inside = (u > 0.0) & (u < w + 1) & (v > 0.0) & (v < h + 1)
	u = np.clip(u, 0, w)
	v = np.clip(v, 0, h)
	iu = np.floor(u).astype(np.int32)
	iv = np.floor(v).astype(np.int32)
	iu1 = np.minimum(iu + 1, w + 1)
	iv1 = np.minimum(iv + 1, h + 1)
	fu = (u - iu)[..., None]
	fv = (v - iv)[..., None]
	out = (pad[iv, iu] * (1 - fu) * (1 - fv) + pad[iv, iu1] * fu * (1 - fv)
		+ pad[iv1, iu] * (1 - fu) * fv + pad[iv1, iu1] * fu * fv)
	out *= inside[..., None]
	return out.astype(np.float32)


def smoothstep(e0: float, e1: float, x):
	t = np.clip((np.asarray(x, np.float32) - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3 - 2 * t)


# ================================================================== masks and components

def label(mask: np.ndarray) -> tuple[np.ndarray, int]:
	"""8-connected component labels of a boolean mask (0 = background), run-length union-find."""
	h, w = mask.shape
	parent: list[int] = [0]

	def find(a: int) -> int:
		while parent[a] != a:
			parent[a] = parent[parent[a]]
			a = parent[a]
		return a

	rows: list[list[tuple[int, int, int]]] = []
	m = mask.astype(np.int8)
	for y in range(h):
		d = np.diff(np.concatenate(([0], m[y], [0])))
		starts, ends = np.where(d == 1)[0].tolist(), np.where(d == -1)[0].tolist()
		prev = rows[-1] if rows else []
		runs: list[tuple[int, int, int]] = []
		j = 0
		for s, e in zip(starts, ends):
			lab = len(parent)
			parent.append(lab)
			while j < len(prev) and prev[j][1] < s:  # ends before s-1: cannot touch, even diagonally
				j += 1
			k = j
			while k < len(prev) and prev[k][0] <= e:  # starts by e: touches (diagonal included)
				ra, rb = find(lab), find(prev[k][2])
				if ra != rb:
					parent[max(ra, rb)] = min(ra, rb)
				k += 1
			runs.append((s, e, lab))
		rows.append(runs)
	labels = np.zeros((h, w), np.int32)
	remap: dict[int, int] = {}
	for y, runs in enumerate(rows):
		for s, e, lab in runs:
			labels[y, s:e] = remap.setdefault(find(lab), len(remap) + 1)
	return labels, len(remap)


def dilate(mask: np.ndarray, r: int) -> np.ndarray:
	"""Octagonal dilation by r px (alternating 8- and 4-neighbourhood steps)."""
	out = mask.copy()
	for i in range(r):
		p = np.pad(out, 1)
		n = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
		if i % 2 == 0:
			n = n | p[:-2, :-2] | p[:-2, 2:] | p[2:, :-2] | p[2:, 2:]
		out = n
	return out


def erode(mask: np.ndarray, r: int) -> np.ndarray:
	return ~dilate(~mask, r)


def depth_map(mask: np.ndarray, maxd: int) -> np.ndarray:
	"""Approximate (octagonal) distance from the outside, inside the mask, capped at maxd."""
	d = np.zeros(mask.shape, np.float32)
	cur = mask.copy()
	for i in range(maxd):
		d += cur
		p = np.pad(cur, 1, constant_values=False)
		n = p[1:-1, 1:-1] & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
		if i % 2 == 1:
			n = n & p[:-2, :-2] & p[:-2, 2:] & p[2:, :-2] & p[2:, 2:]
		cur = n
		if not cur.any():
			break
	return d


def edt(mask: np.ndarray) -> np.ndarray:
	"""Exact Euclidean distance from every True pixel to the nearest False pixel (0 on False)."""
	H, W = mask.shape
	big = float(H + W)
	ys = np.arange(H, dtype=np.float32)[:, None]
	bg = ~mask
	last = np.maximum.accumulate(np.where(bg, ys, -big), axis=0)
	nxt = np.minimum.accumulate(np.where(bg, ys, 2 * big)[::-1], axis=0)[::-1]
	g = np.minimum(ys - last, nxt - ys).astype(np.float32)  # column pass
	xs = np.arange(W, dtype=np.float32)
	dx2 = (xs[:, None] - xs[None, :]) ** 2
	out = np.empty((H, W), np.float32)
	g2 = g * g
	for y0 in range(0, H, 32):  # row pass, brute force, in bands
		band = g2[y0:y0 + 32]
		out[y0:y0 + 32] = (band[:, None, :] + dx2[None, :, :]).min(-1)
	return np.sqrt(out)


def smax(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
	"""Polynomial smooth maximum: the union of two signed-distance shapes with a fillet of ~k."""
	h = np.clip(k - np.abs(a - b), 0, None) / k
	return np.maximum(a, b) + h * h * k * 0.25


def components(mask: np.ndarray, min_size: int) -> list[np.ndarray]:
	"""The 8-connected components of mask with at least min_size px, largest first."""
	lab, n = label(mask)
	if n == 0:
		return []
	sizes = np.bincount(lab.ravel(), minlength=n + 1)
	sizes[0] = 0
	return [lab == k for k in np.argsort(sizes)[::-1] if sizes[k] >= min_size]


def longest_empty_run_mid(counts: np.ndarray, lo: int, hi: int) -> int:
	"""The middle of the longest run of zero entries in counts[lo:hi] (argmin when none is zero)."""
	seg = counts[lo:hi]
	best, best_len, cur = None, 0, None
	for i, e in enumerate(np.concatenate((seg == 0, [False]))):
		if e and cur is None:
			cur = i
		elif not e and cur is not None:
			if i - cur > best_len:
				best_len, best = i - cur, (cur + i) // 2
			cur = None
	return lo + (best if best is not None else int(np.argmin(seg)))


def concave_majorant(y: np.ndarray, x: np.ndarray) -> np.ndarray:
	"""Least concave majorant of x(y) (the front profile's hull) at every y."""
	pts: list[tuple[float, float]] = []
	for yi, xi in zip(y.tolist(), x.tolist()):
		while len(pts) >= 2:
			(y1, x1), (y2, x2) = pts[-2], pts[-1]
			if (x2 - x1) * (yi - y1) <= (xi - x1) * (y2 - y1):
				pts.pop()
			else:
				break
		pts.append((yi, xi))
	return np.interp(y.astype(np.float32), [p[0] for p in pts], [p[1] for p in pts])


# ================================================================== the body frames

def extract_figures(path: Path) -> list[np.ndarray]:
	"""The six figures of a 3 x 2 strip (row 1 = frames 1-3, row 2 = 4-6), cropped, straight RGBA.

	The rows are split at the middle of the longest empty run of rows near the strip's middle, each
	row at the empty columns between its three figures (the widest three column groups, cut in the
	middle of the gaps). Per figure only the largest 8-connected component (alpha > 24/255) and the
	components touching it (within 2 px) are kept, so stray strokes drop out; the kept set is grown
	by 2 px to keep the soft alpha fringe."""
	img = load_rgba(path)
	h, w = img.shape[:2]
	solid_rows = (img[..., 3] > ALPHA_SOLID).sum(1)
	cut_y = longest_empty_run_mid(solid_rows, h // 3, 2 * h // 3)
	figs: list[np.ndarray] = []
	for y0, y1 in ((0, cut_y), (cut_y, h)):
		band = img[y0:y1]
		occ = ((band[..., 3] > ALPHA_SOLID).sum(0) > 0).astype(np.int8)
		d = np.diff(np.concatenate(([0], occ, [0])))
		merged: list[list[int]] = []
		for s, e in zip(np.where(d == 1)[0].tolist(), np.where(d == -1)[0].tolist()):
			if merged and s - merged[-1][1] < 12:
				merged[-1][1] = e
			else:
				merged.append([s, e])
		groups = sorted(sorted(merged, key=lambda r: r[1] - r[0], reverse=True)[:3])
		if len(groups) != 3:
			raise RuntimeError(f"{path.name}: a row does not hold three figures")
		cuts = [0] + [(groups[i][1] + groups[i + 1][0]) // 2 for i in range(2)] + [w]
		for c in range(3):
			cell = band[:, cuts[c]:cuts[c + 1]]
			lab, n = label(cell[..., 3] > 24 / 255)
			sizes = np.bincount(lab.ravel(), minlength=n + 1)
			sizes[0] = 0
			main = lab == int(np.argmax(sizes))
			keep = main.copy()
			for k in np.unique(lab[dilate(main, 2) & (lab > 0)]):
				keep |= lab == k
			fig = cell.copy()
			fig[..., 3] *= dilate(keep, 2)
			ys, xs = np.where(fig[..., 3] > 1 / 255)
			figs.append(np.ascontiguousarray(fig[ys.min():ys.max() + 1, xs.min():xs.max() + 1]))
	return figs


class Figure:
	"""One figure (a strike frame or page 1's idle frame) and its placement measures, in its own
	pixel-edge coordinates: pixel (x, y) covers [x, x + 1] x [y, y + 1]."""

	def __init__(self, rgba: np.ndarray, direction: str):
		self.rgba = rgba
		self.direction = direction
		self.mask = rgba[..., 3] > ALPHA_SOLID
		widths = self.mask.sum(1)
		rows = np.where(widths >= 8)[0]
		self.top = int(rows.min())
		self.baseline = int(rows.max())
		self.height = self.baseline - self.top + 1
		self.area = int(self.mask.sum())
		body_top = int(np.where(widths >= 0.45 * widths.max())[0].min())  # below the sprout
		band = self.mask[self.baseline - int(0.45 * (self.baseline - body_top)):self.baseline + 1]
		cols = np.where(band.any(0))[0]
		# side: the back, the left-most solid px of the lower body; down / up: the lower body's middle
		self.back = float(cols.min())
		self.middle = (cols.min() + cols.max() + 1) / 2.0
		self.anchor_x = self.back if direction == "side" else self.middle
		self.ground = self.baseline + 1.0
		if direction != "side":
			# the front and back views stand on their two feet (the outer fifths of the lower body):
			# the down view's bump hangs below them toward the camera and must not lift the body
			span = cols.max() + 1 - cols.min()
			feet = []
			for lo, hi in ((cols.min(), cols.min() + span // 5), (cols.max() + 1 - span // 5, cols.max() + 1)):
				sub = self.mask[:, lo:hi]
				feet.append(np.where(sub.any(1))[0].max() + 1.0)
			self.ground = float(np.mean(feet))


def outline_thickness(fig: np.ndarray) -> float:
	"""The painted dark outline's width: walk in from both sides of the middle rows while dark."""
	mask = fig[..., 3] > ALPHA_SOLID
	lum = fig[..., :3] @ LUMA
	ys = np.where(mask.any(1))[0]
	runs = []
	for y in range(int(ys.min() + 0.3 * len(ys)), int(ys.min() + 0.85 * len(ys)), 3):
		xs = np.where(mask[y])[0]
		for x, step in ((int(xs.max()), -1), (int(xs.min()), 1)):
			n = 0
			while 0 <= x + n * step < mask.shape[1] and mask[y, x + n * step] and lum[y, x + n * step] < 0.33:
				n += 1
			if 2 <= n <= 30:
				runs.append(n)
	return float(np.median(runs)) if runs else 6.0


def outline_colour(fig: np.ndarray, depth: np.ndarray, ot: float) -> np.ndarray:
	lum = fig[..., :3] @ LUMA
	ring = (fig[..., 3] > ALPHA_SOLID) & (depth >= 2) & (depth <= max(ot - 2, 2)) & (lum < 0.3)
	return np.median(fig[ring][:, :3], 0)


def face_protect(fig: np.ndarray, depth: np.ndarray, ot: float) -> np.ndarray:
	"""Boxes (4 px wide margins) around the eyes (very dark blobs inside the body) and the mouth
	(red blobs): the neck never paints over them."""
	rgb = fig[..., :3]
	lum = rgb @ LUMA
	mask = fig[..., 3] > ALPHA_SOLID
	protect = np.zeros(mask.shape, bool)
	dark = mask & (depth >= ot + 5) & (lum < 0.16)
	red = mask & (rgb[..., 0] > 0.5) & (rgb[..., 0] - rgb[..., 1] > 0.22) & (rgb[..., 0] - rgb[..., 2] > 0.2)
	for comp in components(dark, 30) + components(red, 30):
		yy, xx = np.where(comp)
		protect[max(yy.min() - 4, 0):yy.max() + 5, max(xx.min() - 4, 0):xx.max() + 5] = True
	return protect


def sprout_mask(fig: np.ndarray, ot: float) -> np.ndarray:
	"""The back view's sprout: the leaves' painted interiors (the body's interior is one big
	component; the leaves are cut off from it by their outlines) grown through their outline ring,
	sharing each outline with the body at its middle, plus the soft alpha fringe beyond."""
	mask = fig[..., 3] > ALPHA_SOLID
	lum = fig[..., :3] @ LUMA
	comps = components(mask & (lum > 0.3), 30)
	if len(comps) < 2:
		return np.zeros(mask.shape, bool)
	body = comps[0]
	body_y = np.where(body)[0].mean()
	leaf = np.zeros(mask.shape, bool)
	for comp in comps[1:]:
		if comp.sum() >= 0.02 * body.sum() and np.where(comp)[0].mean() < body_y:
			leaf |= comp
	if not leaf.any():
		return leaf
	grow_body = body.copy()
	for _ in range(int(ot) + 4):  # grow both at once: the shared outline splits at its middle
		leaf = dilate(leaf, 1) & mask & ~grow_body
		grow_body = dilate(grow_body, 1) & mask & ~leaf
	soft = fig[..., 3] > 0
	return leaf | (dilate(leaf, 3) & soft & ~grow_body & ~mask)


# ================================================================== the spear

class Spear:
	"""spear.webp (lying horizontal, root blob left, arrowhead right) and its shaft's cross-section."""

	def __init__(self):
		meta = json.loads(SHAPES_JSON.read_text(encoding="utf-8"))["spear"]
		self.root_end = int(meta["root_end"])
		self.head_start = int(meta["head_start"])
		self.shaft_px = float(meta["shaft_px"])
		self.tex = load_rgba(SPEAR_PATH)
		self.width = self.tex.shape[1]
		a = self.tex[..., 3]
		mid = a[:, self.root_end + 30:self.head_start - 10]
		rows = np.where(np.median(mid, 1) > 0.5)[0]
		self.top, self.bottom = int(rows.min()), int(rows.max())
		self.centre = (self.top + self.bottom + 1) / 2.0
		self.gain = np.ones(3, np.float32)
		self._measure()

	def _measure(self) -> None:
		block = self.tex[self.top:self.bottom + 1, self.root_end + 30:self.head_start - 10, :3]
		prof = np.median(block, 1)  # per-row colour, the speckles median-ed away
		lum = prof @ LUMA
		dark = lum < 0.26
		t = 0
		while t < len(dark) and dark[t]:
			t += 1
		b = len(dark) - 1
		while b >= 0 and dark[b]:
			b -= 1
		self.outline_tx = (t + (len(dark) - 1 - b)) / 2.0
		self.interior = prof[t:b + 1]
		self.interior_tx = float(b - t + 1)
		self.outline_rgb = np.median(np.concatenate([prof[:t], prof[b + 1:]]), 0)

	def tint_toward(self, body_rgb: np.ndarray, share: float) -> None:
		"""Move the spear's jelly toward the body's: a per-channel gain on the light pixels, faded out
		on the dark outline so the line stays warm."""
		block = self.tex[self.top:self.bottom + 1, self.root_end + 30:self.head_start - 10]
		lum = block[..., :3] @ LUMA
		jelly = np.median(block[(block[..., 3] > 0.9) & (lum > 0.35)][:, :3], 0)
		gain = 1.0 + (body_rgb / np.maximum(jelly, 1e-3) - 1.0) * share
		k = smoothstep(0.18, 0.4, self.tex[..., :3] @ LUMA)[..., None]
		self.tex[..., :3] = np.clip(self.tex[..., :3] * (1 + (gain[None, None, :] - 1) * k), 0, 1)
		self.gain = gain.astype(np.float32)
		self._measure()

	def crop_visible(self, visible_tx: float) -> np.ndarray:
		"""The arrowhead and the shaft behind it, visible_tx texture px long in all (anchored to the
		tip: a rigid spear sliding out, never stretched; the root blob is never shown)."""
		x0 = int(round(self.width - visible_tx))
		x0 = min(max(self.root_end + 20, x0), self.head_start - 4)
		return premul(self.tex[:, x0:])

	def profile(self, v: np.ndarray) -> np.ndarray:
		"""The shaft's interior colour at v in [-1, 1] across it (top -> bottom)."""
		n = len(self.interior)
		pos = (np.clip(v, -1, 1) + 1) / 2 * (n - 1)
		return np.stack([np.interp(pos, np.arange(n), self.interior[:, c]) for c in range(3)], -1)


# ================================================================== the neck (grown from the bump)
# Both functions work in the canonical orientation: the aim along +x.

def body_profile(canvas_body: np.ndarray, depth: np.ndarray, S: np.ndarray, half: float, ot: float,
		protect: np.ndarray) -> np.ndarray:
	"""The bump's own jelly colours behind its outline beside the socket, as 9 bins across the neck
	(top -> bottom), smoothed so a painted spot does not stamp. Sampled a little deeper than the
	painter's bright inner rim, so the neck does not glow."""
	H, W = depth.shape
	bins = 9
	out = np.full((bins, 3), np.nan, np.float32)
	ys = np.arange(int(S[1] - half), int(S[1] + half) + 1)
	xs = np.arange(int(S[0] - half - ot - 22), int(S[0]) + 1)
	gy, gx = np.meshgrid(np.clip(ys, 0, H - 1), np.clip(xs, 0, W - 1), indexing="ij")
	d = depth[gy, gx]
	ok = (d >= ot + 7) & (d <= ot + 20) & ~protect[gy, gx]
	a = np.maximum(canvas_body[gy, gx, 3:4], 1e-4)
	rgb = canvas_body[gy, gx, :3] / a
	vb = np.clip(((gy - (S[1] - half)) / (2 * half) * bins).astype(int), 0, bins - 1)
	for b in range(bins):
		sel = ok & (vb == b)
		if sel.sum() > 4:
			out[b] = np.median(rgb[sel], 0)
	good = ~np.isnan(out[:, 0])
	if not good.any():
		return np.tile(np.array([0.6, 0.72, 0.2], np.float32), (bins, 1))
	idx = np.arange(bins)
	for c in range(3):
		out[:, c] = np.interp(idx, idx[good], out[good, c])
	sm = out.copy()
	for _ in range(2):
		sm[1:-1] = (sm[:-2] + 2 * sm[1:-1] + sm[2:]) / 4
	return sm


def neck_layer(body_layer: np.ndarray, depth: np.ndarray, protect: np.ndarray, S: np.ndarray,
		u: np.ndarray, neck: float, length: float, ot_body: float, body_rgb_outline: np.ndarray,
		spear: Spear, k_sp: float, overlap: float) -> tuple[np.ndarray, int, int]:
	"""The goo neck from the bump tip S along the aim u, as a premultiplied patch (layer, x0, y0).

	Signed distances: a straight band (its half-width tapering from the neck's to the shaft's) and
	the body's painted interior (exact EDT of the body minus its dark outline) joined with a smooth
	maximum, so the two corners where it leaves the bump become fillets. Only where that union
	differs from the body alone is anything painted: its interior in the bump's own colours turning
	into the shaft's, a gloss line along the upper side, and its outline band in the body's line
	colour thinning to the shaft's. Inside the body the fill covers the body's outline (no line
	where they join) and fades out within a few px; past the neck's end (the socket) it runs on over
	the shaft and fades into it."""
	side = np.array([-u[1], u[0]])
	h0_full = neck / 2
	d_in = ot_body + 8.0
	Hd, Wd = depth.shape
	for _ in range(int(h0_full / 3) + 1):  # start where the band's whole cross-section is interior
		c = S - u * d_in
		ok = True
		for f in np.linspace(-1, 1, 9):
			q = c + side * f * h0_full
			qx, qy = int(round(q[0])), int(round(q[1]))
			if not (0 <= qx < Wd and 0 <= qy < Hd) or depth[qy, qx] < ot_body + 8:
				ok = False
				break
		if ok:
			break
		d_in += 3.0
	R = S + u * length
	n = 240
	t = np.linspace(0, 1, n)[:, None]
	p0, p3 = S - u * d_in, R + u * overlap
	pts = p0 + (p3 - p0) * t
	tan = np.tile(u[None, :], (n, 1))
	nrm = np.stack([-tan[:, 1], tan[:, 0]], 1)  # +v = the 'down' side, like the texture's rows
	s = (pts - p0) @ u
	s_edge, s_root = d_in, d_in + length
	tau = np.clip((s - s_edge) / max(s_root - s_edge, 1e-3), 0, 1)
	h1 = spear.interior_tx / 2 * k_sp + 0.3
	o1 = spear.outline_tx * k_sp
	h0 = max(neck / 2 - ot_body, h1 + 1)
	half = h1 + (h0 - h1) * (1 - tau) ** 1.25
	cap = np.clip(s / max(s_edge, 1e-3), 0, 1)
	half = np.where(s < s_edge, h0 * np.sqrt(1 - (1 - cap) ** 2), half)
	ot = ot_body + (o1 - ot_body) * smoothstep(0.1, 0.8, tau)
	alpha_s = 1 - smoothstep(s_root + 0.25 * overlap, s_root + overlap, s)
	col_mix = smoothstep(0.05, 0.95, tau)
	vol_k = 1 - smoothstep(0.4, 0.95, tau)
	gloss_k = 0.45 * smoothstep(0.0, 0.35, tau) * (1 - smoothstep(0.75, 1.0, tau))
	gloss_v = -0.45 - 0.3 * tau
	kf = max(0.34 * neck, 4.0)  # fillet size

	bprof = body_profile(body_layer, depth, S, h0 + ot_body, ot_body, protect)
	H, W = depth.shape
	reach = float((half + ot).max()) + kf + 3
	x0 = int(max(min(pts[:, 0].min() - reach, W), 0))
	x1 = int(min(max(pts[:, 0].max() + reach, 0), W))
	y0 = int(max(min(pts[:, 1].min() - reach, H), 0))
	y1 = int(min(max(pts[:, 1].max() + reach, 0), H))
	h, w = y1 - y0, x1 - x0
	gy, gx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
	P = np.stack([gx.ravel() + 0.5, gy.ravel() + 0.5], 1)
	along_all = (P - p0) @ u
	best = np.clip(np.round(along_all / max(s[-1], 1e-3) * (n - 1)).astype(np.int32), 0, n - 1)
	rel = P - pts[best]
	along = (rel * tan[best]).sum(1)
	perp = (rel * nrm[best]).sum(1)
	ends = ((best == 0) & (along < 0)) | ((best == n - 1) & (along > 0))
	hh = half[best]
	sd_t = np.where(ends, -1e3, hh - np.abs(perp)).reshape(h, w)
	win = body_layer[y0:y1, x0:x1]
	m = win[..., 3] > 0.5
	rgb_b = win[..., :3] / np.maximum(win[..., 3:4], 1e-4)
	edge_d = edt(m)
	line = m & (edge_d < 2.2 * ot_body) & (rgb_b @ LUMA < 0.33) & (rgb_b[..., 0] >= 0.9 * rgb_b[..., 1])
	interior = m & ~dilate(line, 1) & (edge_d > 0.6 * ot_body)
	interior = erode(dilate(interior, 2), 2)
	sd_bi = np.where(interior, edt(interior) - 0.5, -(edt(~interior) - 0.5))
	pb = np.pad(sd_bi, 1, mode="edge")
	sd_bi = (pb[:-2, 1:-1] + pb[2:, 1:-1] + pb[1:-1, :-2] + pb[1:-1, 2:] + 4 * sd_bi) / 8
	sd_u = smax(sd_bi, sd_t, kf)
	zone = smoothstep(0.0, 0.8, sd_u - sd_bi)
	wt = smoothstep(-2.0, 2.0, sd_t - sd_bi)
	ot_l = ot_body * (1 - wt) + ot[best].reshape(h, w) * wt
	cov_int = np.clip(sd_u + 0.5, 0, 1)
	cov_sil = np.clip(sd_u + ot_l + 0.5, 0, 1)
	fade_in = 1 - smoothstep(1.0, 7.0, sd_bi)
	v = np.clip(perp / np.maximum(hh, 0.5), -1, 1)
	bpos = (v + 1) / 2 * (len(bprof) - 1)
	bcol = np.stack([np.interp(bpos, np.arange(len(bprof)), bprof[:, c]) for c in range(3)], -1)
	vk = vol_k[best][:, None]
	bcol = bcol * (1 + vk * (0.10 * -v - 0.16 * v * v)[:, None])
	scol = spear.profile(v)
	mix = col_mix[best][:, None]
	icol = bcol * (1 - mix) + scol * mix
	# the bump's paint grain on the neck: soft noise as fine as the body's brushwork, as strong as
	# the bump's own fine luma detail (its high-pass spread, measured deep inside, away from the
	# painter's bright rim and the face), fading as the neck turns into the shaft. Statistics only:
	# nothing is copied, so no painted highlight is duplicated.
	lum_b = rgb_b @ LUMA

	def box(a: np.ndarray, r: int) -> np.ndarray:
		p = np.pad(a, r, mode="edge").cumsum(0).cumsum(1)
		p = np.pad(p, ((1, 0), (1, 0)))
		nb = 2 * r + 1
		return (p[nb:, nb:] - p[:-nb, nb:] - p[nb:, :-nb] + p[:-nb, :-nb]) / (nb * nb)

	deep = interior & (edt(interior) > 6.0) & ~protect[y0:y1, x0:x1]
	hp = lum_b - box(lum_b, 4)
	sel = deep & (np.abs(hp) < 0.15)
	hp_std = float(np.std(hp[sel])) if sel.sum() > 50 else 0.03
	rng = np.random.default_rng(int(S[0] * 7 + S[1] * 13))
	noise = box(box(rng.normal(0.0, 1.0, (h, w)), 1), 1)
	noise /= max(float(noise.std()), 1e-6)
	grain = (noise.ravel() * hp_std)[:, None] * (1 - smoothstep(0.35, 1.0, tau[best]))[:, None]
	icol = icol * (1 + grain / np.maximum(icol @ LUMA, 0.2)[:, None])
	gl = (gloss_k[best] * np.exp(-((v - gloss_v[best]) / 0.16) ** 2))[:, None]
	icol = np.clip(icol * (1 - gl) + np.array([1.0, 1.0, 0.8]) * gl, 0, 1).reshape(h, w, 3)
	ocol = (body_rgb_outline[None, :] * (1 - mix) + spear.outline_rgb[None, :] * mix).reshape(h, w, 3)
	keep = (~protect[y0:y1, x0:x1]).astype(np.float32)
	a_s = alpha_s[best].reshape(h, w)
	w_int = cov_int * fade_in * zone * a_s * keep
	w_out = (cov_sil - cov_int) * zone * a_s * keep
	layer = np.zeros((h, w, 4), np.float32)
	layer[..., :3] = icol * w_int[..., None] + ocol * w_out[..., None]
	layer[..., 3] = np.clip(w_int + w_out, 0, 1)
	return layer, x0, y0


# ================================================================== orientation

def from_canon(p: np.ndarray, k: int, shape: tuple[int, int]) -> np.ndarray:
	"""A canonical point (pixel-edge coordinates of np.rot90(img, k)) back in img's coordinates;
	shape = img's (height, width)."""
	H, W = shape
	if k == 0:
		return np.array(p, np.float64)
	if k == 1:
		return np.array([W - p[1], p[0]], np.float64)
	return np.array([p[1], H - p[0]], np.float64)  # k == -1


# ================================================================== one strip

class Strip:
	def __init__(self, strike: str, direction: str, spear: Spear, reference: Figure):
		self.strike = strike
		self.direction = direction
		self.row = STRIKES.index(strike) * 3 + DIRECTIONS.index(direction)
		self.name = f"{strike}-{direction}"
		self.figs = extract_figures(SRC / f"{self.name}.png")
		if len(self.figs) != 6:
			raise RuntimeError(f"{self.name}: {len(self.figs)} figures, expected 6")
		self.frames = [Figure(f, direction) for f in self.figs]
		self.rest = self.frames[REST_FRAME - 1]
		self.reference = reference
		# ONE scale for the whole strip: the rest frame as tall as page 1's idle frame
		self.scale = reference.height / self.rest.height  # cell px per source px
		self.g = 1.0 / (self.scale * CELL_TO_GAME)  # source px per game px
		self.outline_px = float(np.median([outline_thickness(f) for f in self.figs]))
		self.spear = spear
		self.shaft_game = SHAFT_GAME[strike]
		self.k_sp = self.shaft_game / spear.shaft_px * self.g  # spear texture px -> source px
		# where the rest frame stands: its middle on the idle frame's middle, its ground on the idle
		# frame's ground (page 1's cell centre is this sheet's cell centre)
		dx, dy = (CELL_W - PAGE_CELL) / 2.0, (CELL_H - PAGE_CELL) / 2.0
		self.rest_middle_cell = reference.middle + dx
		self.ground_cell = reference.ground + dy
		self.anchor_cell_x = self.rest_middle_cell + (self.rest.anchor_x - self.rest.middle) * self.scale
		self.aim = np.array(AIM[direction], np.float64)

	def to_cell(self, frame: Figure, p: np.ndarray) -> np.ndarray:
		"""A point in a figure's own coordinates -> cell px."""
		return np.array([self.anchor_cell_x + (p[0] - frame.anchor_x) * self.scale,
			self.ground_cell + (p[1] - frame.ground) * self.scale])

	def grow_neck(self, index: int) -> tuple[np.ndarray, dict]:
		"""Frame index (1-6) with its neck baked in, on a PAD-px padded canvas (premultiplied), and
		its bump tip, socket and fade end in the figure's own coordinates."""
		fig = self.figs[index - 1]
		padded = np.pad(fig, ((PAD, PAD), (PAD, PAD), (0, 0)))
		k = CANON_K[self.direction]
		canon = np.ascontiguousarray(np.rot90(padded, k))
		mask = canon[..., 3] > ALPHA_SOLID
		sprout = np.zeros(mask.shape, bool)
		if self.direction == "up":  # found upright (the leaves above the body), then turned
			sprout = np.ascontiguousarray(np.rot90(sprout_mask(padded, self.outline_px), k))
		body = canon.copy()
		body[..., 3] *= ~sprout
		body_mask = body[..., 3] > ALPHA_SOLID
		depth = depth_map(body_mask, 40)
		protect = face_protect(canon, depth, self.outline_px)
		# the bump's tip: the front-most column of the body (sprout excluded), at the middle of the
		# rows within 2 px of it
		rows = np.where(body_mask.any(1))[0]
		front = np.array([np.where(body_mask[y])[0].max() for y in rows], np.float32)
		tip_x = float(front.max())
		tip_y = float(rows[front >= tip_x - 2].mean())
		hull = concave_majorant(rows, front)
		deficit = float((hull - front)[rows < tip_y].max()) if (rows < tip_y).any() else 0.0
		if deficit < 0.02 * (np.ptp(np.where(body_mask.any(0))[0]) + 1):
			print(f"  warning: {self.name} frame {index}: the front shows no clear bump (deficit {deficit:.1f} px)")
		S = np.array([tip_x + 0.5, tip_y + 0.5])
		chord_x = int(round(tip_x - (self.outline_px + 8)))
		col = body_mask[:, chord_x]
		ty = int(round(tip_y))
		a = b = ty
		if col[ty]:
			while a > 0 and col[a - 1]:
				a -= 1
			while b < len(col) - 1 and col[b + 1]:
				b += 1
		chord = float(b - a + 1) if col[ty] else 0.0
		sw = self.shaft_game * self.g
		neck = float(np.clip(chord, NECK_W[0] * sw, NECK_W[1] * sw))
		length, overlap = NECK_LEN * sw, NECK_OVERLAP * sw
		u = np.array([1.0, 0.0])
		body_p = premul(body)
		layer, nx, ny = neck_layer(body_p, depth, protect, S, u, neck, length, self.outline_px,
			outline_colour(canon, depth, self.outline_px), self.spear, self.k_sp, overlap)
		out = premul(canon)
		over(out, layer, nx, ny)
		if sprout.any():  # the sprout stays in front of the neck
			sp = canon.copy()
			sp[..., 3] *= sprout
			over(out, premul(sp), 0, 0)
		out = np.ascontiguousarray(np.rot90(out, -k))
		shape = padded.shape[:2]
		back = lambda p: from_canon(p, k, shape) - PAD  # noqa: E731 (padded canonical -> figure px)
		info = {"bump": back(S), "socket": back(S + u * length), "fade_end": back(S + u * (length + overlap)),
			"neck_width": neck, "chord": chord, "deficit": deficit}
		return out, info

	def render(self) -> tuple[list[np.ndarray], list[dict]]:
		"""The six cells (premultiplied, CELL_H x CELL_W) and per frame its socket data (cell px)."""
		cells, data = [], []
		bw, bh = CELL_W / self.scale, CELL_H / self.scale  # the cell's box in source px
		for index, (fig, frame) in enumerate(zip(self.figs, self.frames), start=1):
			if index in SPEAR_STATES:
				padded, info = self.grow_neck(index)
				pad = PAD
			else:
				padded, info, pad = premul(fig), {}, 0
			# the source box that becomes the cell: the anchor lands on its cell px exactly
			x0 = frame.anchor_x - self.anchor_cell_x / self.scale
			y0 = frame.ground - self.ground_cell / self.scale
			ox, oy = int(math.floor(-x0)) + 4, int(math.floor(-y0)) + 4  # figure origin in the canvas
			canvas = np.zeros((int(math.ceil(bh)) + 10, int(math.ceil(bw)) + 10, 4), np.float32)
			over(canvas, padded, ox - pad, oy - pad)
			box = (x0 + ox, y0 + oy, x0 + ox + bw, y0 + oy + bh)
			cell = resize_premul(canvas, (CELL_W, CELL_H), box)
			# the art's extent in cell px before the cell clips it (body and neck, alpha > 1/255)
			ys, xs = np.where(padded[..., 3] > 1 / 255)
			lo = self.to_cell(frame, np.array([xs.min() - pad, ys.min() - pad], np.float64))
			hi = self.to_cell(frame, np.array([xs.max() + 1 - pad, ys.max() + 1 - pad], np.float64))
			extent = (float(lo[0]), float(lo[1]), float(hi[0]), float(hi[1]))
			clipped = lo[0] < MARGIN or lo[1] < MARGIN or hi[0] > CELL_W - MARGIN or hi[1] > CELL_H - MARGIN
			entry: dict = {"frame": index, "spear": SPEAR_STATES.get(index, "hidden"), "extent": extent,
				"clipped": bool(clipped), "height_cell": frame.height * self.scale,
				"area_vs_rest": frame.area / self.rest.area}
			if info:
				for key in ("bump", "socket", "fade_end"):
					entry[key] = self.to_cell(frame, info[key])
				entry["neck_width"] = info["neck_width"] * self.scale
				entry["chord"] = info["chord"] * self.scale
			cells.append(cell)
			data.append(entry)
		# hidden frames: where the spear would leave the body, the body's front edge on the line of
		# frame 4's socket (nothing is drawn there; for a glint or a retract)
		line = data[3]["socket"]
		for entry, cell in zip(data, cells):
			if "socket" in entry:
				continue
			entry["socket"] = front_edge(cell[..., 3] > ALPHA_SOLID, self.direction, line)
		return cells, data


def front_edge(mask: np.ndarray, direction: str, line: np.ndarray) -> np.ndarray:
	"""The body's front edge (cell px) on the aim line through line (a cell point): side, the
	right-most solid px of that row; down, the lowest of that column; up, the highest. A line that
	misses the body (a squashed frame) moves to the nearest row or column that holds it."""
	if direction == "side":
		rows = np.where(mask.any(1))[0]
		y = int(rows[np.argmin(np.abs(rows + 0.5 - line[1]))])
		return np.array([np.where(mask[y])[0].max() + 1.0, y + 0.5])
	cols = np.where(mask.any(0))[0]
	x = int(cols[np.argmin(np.abs(cols + 0.5 - line[0]))])
	ys = np.where(mask[:, x])[0]
	return np.array([x + 0.5, ys.max() + 1.0 if direction == "down" else float(ys.min())])


# ================================================================== output

def reference_figures() -> dict[str, Figure]:
	page = load_rgba(PAGE_1)
	out = {}
	for direction, (col, row) in REFERENCE_CELLS.items():
		cell = page[row * PAGE_CELL:(row + 1) * PAGE_CELL, col * PAGE_CELL:(col + 1) * PAGE_CELL]
		out[direction] = Figure(cell, direction)
	return out


def rounded(p, nd: int = 1) -> list[float]:
	return [round(float(v), nd) for v in p]


def main() -> None:
	parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
	parser.add_argument("--preview", type=Path, help="write check images into this folder")
	args = parser.parse_args()

	refs = reference_figures()
	spear = Spear()
	strips = {(s, d): Strip(s, d, spear, refs[d]) for s in STRIKES for d in DIRECTIONS}
	# the spear wears the body's jelly colour (the side jab's rest frame's median jelly), before any
	# neck is grown, as the necks crossfade into its shaft
	jab = strips[("spear-jab", "side")]
	fig = jab.rest.rgba
	depth = depth_map(jab.rest.mask, 40)
	lum = fig[..., :3] @ LUMA
	sel = (depth > jab.outline_px + 12) & (lum > 0.35) & (lum < 0.85)
	jelly = np.median(fig[sel][:, :3], 0)
	spear.tint_toward(jelly, SPEAR_TINT)

	sheet = np.zeros((CELL_H * GRID, CELL_W * GRID, 4), np.float32)
	manifest: dict = {
		"texture": SHEET_RES,
		"cell": [CELL_W, CELL_H],
		"grid": [GRID, GRID],
		"origin": [CELL_W / 2, CELL_H / 2],
		"scale": CELL_TO_GAME,
		"spear": {"texture": SPEAR_RES, "tint_share": SPEAR_TINT, "tint_rgb": rounded(jelly, 4),
			"tint_gain": rounded(spear.gain, 4)},
		"strikes": {},
	}
	results: dict = {}
	for (strike, direction), strip in strips.items():
		cells, data = strip.render()
		results[(strike, direction)] = (strip, cells, data)
		for col, cell in enumerate(cells):
			sheet[strip.row * CELL_H:(strip.row + 1) * CELL_H, col * CELL_W:(col + 1) * CELL_W] = cell
		entry = manifest["strikes"].setdefault(strike, {"shaft_px": SHAFT_GAME[strike], "rest_frame": REST_FRAME})
		origin = np.array(manifest["origin"])
		frames = []
		for d in data:
			f = {"socket": rounded(d["socket"]), "spear": d["spear"]}
			if "bump" in d:
				f["bump"] = rounded(d["bump"])
				f["neck_fade_end"] = rounded(d["fade_end"])
				f["neck_width"] = round(float(d["neck_width"]), 1)
			f["socket_game"] = rounded((np.array(d["socket"]) - origin) * CELL_TO_GAME, 2)
			frames.append(f)
		entry[direction] = {
			"row": strip.row,
			"aim": list(AIM[direction]),
			"source_scale": round(strip.scale, 5),
			"rest_centre": rounded([strip.rest_middle_cell,
				strip.ground_cell - strip.rest.height * strip.scale / 2]),
			"ground": round(strip.ground_cell, 1),
			"anchor": rounded([strip.anchor_cell_x, strip.ground_cell]),
			"frames": frames,
		}
		print(f"{strip.name}: row {strip.row}, scale {strip.scale:.4f} cell px per source px "
			f"({strip.g:.2f} source px per game px), outline {strip.outline_px:.1f} px, "
			f"anchor {strip.anchor_cell_x:.1f}, ground {strip.ground_cell:.1f}")
		for d in data:
			line = (f"  {d['frame']} {d['spear']:<6} extent {rounded(d['extent'])}"
				f"{' CLIPPED' if d['clipped'] else ''} h {d['height_cell']:.1f} area {d['area_vs_rest']:.2f} "
				f"socket {rounded(d['socket'])}")
			if "bump" in d:
				line += (f" bump {rounded(d['bump'])} neck {d['neck_width']:.1f} (chord {d['chord']:.1f}) "
					f"fade end {rounded(d['fade_end'])}")
			print(line)
	# each strike names its sheet and its weapon (the War Axe's and the Hammer's strikes have their own:
	# pack-slime-weapon-strikes.py)
	for entry in manifest["strikes"].values():
		entry["texture"] = SHEET_RES
		entry["weapon"] = "spear"
	# the smallest symmetric cell the art needs, and no clipped frame
	extents = [d["extent"] for _, _, data in results.values() for d in data]
	half_w = max(max(CELL_W / 2 - e[0], e[2] - CELL_W / 2) for e in extents) + MARGIN
	half_h = max(max(CELL_H / 2 - e[1], e[3] - CELL_H / 2) for e in extents) + MARGIN
	print(f"the art needs cells of at least {math.ceil(2 * half_w)} x {math.ceil(2 * half_h)} px "
		f"(these are {CELL_W} x {CELL_H})")
	clipped = [f"{strip.name} {d['frame']}" for strip, _, data in results.values() for d in data if d["clipped"]]
	if clipped:
		raise SystemExit(f"frames do not fit their {CELL_W} x {CELL_H} cells: {', '.join(clipped)}; raise CELL_W / CELL_H")
	manifest["notes"] = (
		"Cell px: pixel (x, y) covers [x, x + 1] x [y, y + 1]. The cell's origin is drawn at the "
		"player Visual's origin (the cell centre: the Visual's offset is -origin), scale game px per "
		"cell px (the Visual's scale); a left strike mirrors the side row about the origin. A frame's "
		"Sprite2D frame is row * 8 + column, its column the frame number - 1. "
		"socket: the neck's end on frames with the spear out (part / full), where the rigid spear's "
		"visible part starts, the spear along aim through it; on hidden frames the body's front edge "
		"on the line of frame 4's socket (nothing is drawn). bump: the painted bump's tip, where the "
		"baked neck leaves the body (the spear's hidden end can start behind it, inside the jelly). "
		"neck_fade_end: where the baked neck has faded into the shaft. socket_game: the socket in game "
		"px from the Visual's origin. shaft_px: the game-px shaft width the neck's end was baked to. "
		"source_scale: cell px per source px of the strip; rest_centre / ground / anchor: where the rest "
		"frame stands (page 1's idle frame's middle and ground: the bottom edge of the solid px on the "
		"side, the feet's in the front and back views), and the strip's fixed back (side) or middle "
		"(down / up) on the ground. rest_frame: the frame (1-6) to hold at rest (frame 1 of the jab "
		"is drawn about 7 percent taller and would pop).")
	out = Image.fromarray((np.clip(unpremul(sheet), 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
	SHEET_OUT.parent.mkdir(parents=True, exist_ok=True)
	out.save(SHEET_OUT, lossless=True, method=6)
	write_manifest(manifest)
	print(f"wrote {SHEET_OUT.relative_to(ROOT)} ({out.width} x {out.height}) and {MANIFEST_OUT.relative_to(ROOT)} (merged)")
	if args.preview:
		write_previews(args.preview, results, refs, spear, out)


def write_manifest(own: dict) -> None:
	"""Merges this script's manifest into shape-strikes.json: its top-level keys and its strikes are
	replaced, every other key (pack-slime-weapon-strikes.py's strikes, `weapons`, `neck`) stays, in
	place; written to a temporary file first, then moved over the old one."""
	manifest = json.loads(MANIFEST_OUT.read_text(encoding="utf-8")) if MANIFEST_OUT.exists() else {}
	strikes = manifest.get("strikes", {})
	for key, value in own.items():
		if key != "strikes":
			manifest[key] = value
	manifest["strikes"] = strikes
	for name, entry in own["strikes"].items():
		strikes[name] = entry
	fd, tmp = tempfile.mkstemp(prefix=MANIFEST_OUT.name + ".", suffix=".tmp", dir=MANIFEST_OUT.parent)
	with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
		f.write(json.dumps(manifest, indent="\t") + "\n")
	os.replace(tmp, MANIFEST_OUT)


# ================================================================== previews

def font(size: int):
	try:
		return ImageFont.truetype("arial.ttf", size)
	except OSError:
		return ImageFont.load_default()


def grass(w: int, h: int) -> np.ndarray:
	"""A plain mottled grass ground (previews only)."""
	rng = np.random.default_rng(7)
	n = rng.normal(0, 1, (h // 8 + 2, w // 8 + 2)).astype(np.float32)
	n = np.asarray(Image.fromarray(n, "F").resize((w, h), Image.Resampling.BICUBIC))
	base = np.array([0.33, 0.52, 0.22], np.float32)
	return np.clip(base[None, None, :] * (1 + 0.06 * n[..., None]), 0, 1)


def on_grass(layer: np.ndarray) -> Image.Image:
	h, w = layer.shape[:2]
	rgb = layer[..., :3] + grass(w, h) * (1 - layer[..., 3:4])
	return Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def draw_spear(canvas: np.ndarray, spear: Spear, strip: Strip, entry: dict, origin: tuple[float, float],
		reach_game: float) -> None:
	"""The rigid spear drawn behind the body as the game would: its hidden end inside the jelly
	behind the bump, its tip reach_game game px out from the socket along the aim."""
	aim = strip.aim
	k_cell = strip.shaft_game / spear.shaft_px / CELL_TO_GAME  # texture px -> cell px
	socket = np.array(entry["socket"]) + origin
	bump = np.array(entry["bump"]) + origin
	tip = socket + aim * reach_game / CELL_TO_GAME
	root = bump - aim * 3.0 / CELL_TO_GAME
	vis_tx = float(np.linalg.norm(tip - root)) / k_cell
	img = spear.crop_visible(vis_tx)
	ang = math.degrees(math.atan2(aim[1], aim[0]))
	layer, lx, ly = warp(img, k_cell, ang, (img.shape[1], spear.centre), tuple(tip), canvas.shape[:2])
	over(canvas, layer, lx, ly)


def write_previews(folder: Path, results: dict, refs: dict[str, Figure], spear: Spear, sheet: Image.Image) -> None:
	folder.mkdir(parents=True, exist_ok=True)
	f_small = font(14)
	# 1. the sheet on grass, the used rows, with the cell grid, anchors and sockets
	used = sheet.crop((0, 0, CELL_W * 6, CELL_H * 6))
	layer = premul(np.asarray(used).astype(np.float32) / 255)
	img = on_grass(layer)
	d = ImageDraw.Draw(img)
	for (strike, direction), (strip, cells, data) in results.items():
		y0 = strip.row * CELL_H
		for col, entry in enumerate(data):
			x0 = col * CELL_W
			d.rectangle([x0, y0, x0 + CELL_W - 1, y0 + CELL_H - 1], outline=(30, 60, 20))
			gy = y0 + strip.ground_cell
			d.line([(x0, gy), (x0 + CELL_W, gy)], fill=(255, 255, 0))
			ax = x0 + strip.anchor_cell_x
			d.line([(ax, y0), (ax, y0 + CELL_H)], fill=(255, 255, 0))
			mx = x0 + strip.rest_middle_cell
			d.line([(mx, gy - 8), (mx, gy + 4)], fill=(0, 255, 255), width=2)
			sx, sy = entry["socket"]
			colour = (255, 40, 40) if entry["spear"] != "hidden" else (255, 160, 255)
			d.ellipse([x0 + sx - 4, y0 + sy - 4, x0 + sx + 4, y0 + sy + 4], outline=colour, width=2)
			if "bump" in entry:
				bx, by = entry["bump"]
				d.ellipse([x0 + bx - 3, y0 + by - 3, x0 + bx + 3, y0 + by + 3], outline=(255, 200, 0), width=2)
			d.text((x0 + 4, y0 + 2), f"{strip.name} {entry['frame']} {entry['spear']}", fill=(255, 255, 255), font=f_small)
	img.save(folder / "strike-sheet.png")
	img.resize((img.width // 2, img.height // 2), Image.Resampling.LANCZOS).save(folder / "strike-sheet-half.png")

	# 2. the joins: frames 3 and 4 with the spear behind the body, at cell scale and at game size x3
	tiles = []
	M = 200
	reach = {"part": 30.0, "full": 45.0}
	for (strike, direction), (strip, cells, data) in results.items():
		for index in (3, 4):
			entry = data[index - 1]
			canvas = np.zeros((CELL_H + 2 * M, CELL_W + 2 * M, 4), np.float32)
			draw_spear(canvas, spear, strip, entry, (M, M), reach[entry["spear"]])
			over(canvas, cells[index - 1], M, M)
			full = on_grass(canvas)
			sx, sy = np.array(entry["socket"]) + M
			zoom = full.crop((int(sx - 110), int(sy - 90), int(sx + 110), int(sy + 90))).resize((440, 360),
				Image.Resampling.LANCZOS)
			gsize = (round(canvas.shape[1] * CELL_TO_GAME), round(canvas.shape[0] * CELL_TO_GAME))
			game = on_grass(resize_premul(canvas, gsize)).resize((gsize[0] * 3, gsize[1] * 3), Image.Resampling.NEAREST)
			gx, gy = (np.array(entry["socket"]) + M) * CELL_TO_GAME * 3
			game = game.crop((int(gx - 220), int(gy - 180), int(gx + 220), int(gy + 180)))
			tile = Image.new("RGB", (890, 386), (24, 24, 26))
			tile.paste(zoom, (0, 26))
			tile.paste(game, (450, 26))
			ImageDraw.Draw(tile).text((6, 4), f"{strip.name} frame {index} ({entry['spear']}): cell px x2 | game px x3",
				fill=(235, 235, 235), font=font(16))
			tiles.append(tile)
	out = Image.new("RGB", (890 * 2, 386 * math.ceil(len(tiles) / 2)), (0, 0, 0))
	for i, t in enumerate(tiles):
		out.paste(t, ((i % 2) * 890, (i // 2) * 386))
	out.save(folder / "strike-joins.png")

	# 3. each direction's rest frames beside page 1's idle frame, same scale, plus an onion skin
	page = load_rgba(PAGE_1)
	rows = []
	for direction in DIRECTIONS:
		col, row = REFERENCE_CELLS[direction]
		idle = np.zeros((CELL_H, CELL_W, 4), np.float32)
		over(idle, premul(page[row * PAGE_CELL:(row + 1) * PAGE_CELL, col * PAGE_CELL:(col + 1) * PAGE_CELL]),
			(CELL_W - PAGE_CELL) // 2, (CELL_H - PAGE_CELL) // 2)
		panels = [("page 1 idle", idle)]
		for strike in STRIKES:
			strip, cells, data = results[(strike, direction)]
			panels.append((f"{strike} rest", cells[REST_FRAME - 1]))
		onion = np.zeros((CELL_H, CELL_W, 4), np.float32)
		ia = idle[..., 3]
		ra = results[("spear-jab", direction)][1][REST_FRAME - 1][..., 3]
		fa = results[("spear-finisher", direction)][1][REST_FRAME - 1][..., 3]
		onion[..., 0] = ia
		onion[..., 1] = ra
		onion[..., 2] = fa
		onion[..., 3] = np.maximum(np.maximum(ia, ra), fa)
		onion[..., :3] *= 0.85
		panels.append(("onion: R idle, G jab, B finisher", onion))
		strip_img = Image.new("RGB", (CELL_W * len(panels), CELL_H + 40), (24, 24, 26))
		dd = ImageDraw.Draw(strip_img)
		for i, (name, layer) in enumerate(panels):
			im = on_grass(layer) if i < len(panels) - 1 else Image.fromarray(
				(np.clip(layer[..., :3] + 0.1 * (1 - layer[..., 3:4]), 0, 1) * 255).astype(np.uint8), "RGB")
			strip_img.paste(im, (i * CELL_W, 40))
			ref = refs[direction]
			gy = 40 + ref.ground + (CELL_H - PAGE_CELL) / 2
			mx = i * CELL_W + ref.middle + (CELL_W - PAGE_CELL) / 2
			dd.line([(i * CELL_W, gy), ((i + 1) * CELL_W, gy)], fill=(255, 255, 0))
			dd.line([(mx, 40), (mx, 40 + CELL_H)], fill=(255, 255, 0))
			m = layer[..., 3] > ALPHA_SOLID
			yy, xx = np.where(m)
			fig = Figure(np.dstack([layer[..., :3], layer[..., 3]]), direction)
			dd.text((i * CELL_W + 4, 2), f"{direction}: {name}", fill=(235, 235, 235), font=f_small)
			dd.text((i * CELL_W + 4, 20), f"h {fig.height} middle {fig.middle:.1f} ground {fig.ground:.1f} "
				f"bbox x {xx.min()}-{xx.max()}", fill=(200, 200, 200), font=f_small)
		rows.append(strip_img)
	check = Image.new("RGB", (rows[0].width, sum(r.height for r in rows)), (0, 0, 0))
	y = 0
	for r in rows:
		check.paste(r, (0, y))
		y += r.height
	check.save(folder / "strike-rest-vs-idle.png")
	print(f"previews in {folder}")


if __name__ == "__main__":
	main()
