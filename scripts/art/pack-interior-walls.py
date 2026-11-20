#!/usr/bin/env python3
"""Packs an interior wall style's bevel kit (docs/godot/INTERIOR_WALLS.md).

The interior walls are Zelda's bevelled frame: every side of a room is a wall FACE seen from above,
sloping up and away from the floor, the same depth on every side (two 64-unit cells: 256 px at the
art density of 128 px a cell), with 45 degree mitres at the corners. North faces are horizontal
courses seen from the front, south faces the same sloping the other way, east and west faces
vertical courses. Doors and openings are cut into the face of their own side, in that side's
perspective; a door's leaf fills its opening exactly.

Every piece is cut from a few Magnific renders of whole frames in one stone and light
(asset/Originals/dungeon-kit/interior-walls/), all made from one reference frame so their layout
matches pixel for pixel:
  lair-bevel-doorways-b    the frame with an open doorway in the middle of each face (runs, outer
                           corners, the doorway frames)
  lair-bevel-leaf-<kind>   the same frame, every doorway shut by one kind (the leaves)
  lair-bevel-<kind>        the same frame with a cracked stretch / blown hole / stairs per face
  lair-floor-cobble        a floor texture, made seamless here

Pieces (sheet px):
  runs      n0.., s0.. (128 x 256: one cell along, two deep), w0.., e0.. (256 x 128): the two plain
            stretches of each face quilted into one loop, cut into whole cells; the loop's length
            in cells is the side's `run_period` in the table (three for every style today)
  corners   nw ne sw se (256 x 256): the mitred squares
  inner     in_se in_sw in_ne in_nw (256 x 256): two faces folding round a corner of the floor,
            split on the diagonal from the floor's corner (named by where the floor is)
  openings  <side>_<kind> (256 x 256, two along by two deep): doorway, cracked, blown, stairs; the
            north piece turned for each side (south 180, west 90 CCW, east 90 CW) and shaded to its
            side's light, the ends feathered over the run drawn under them
  leaves    <side>_<kind> rects inside their side's doorway piece: key1 key2 boss bolt shutter seal
            barricade (the dungeon styles); a style may have fewer openings and other leaves (the
            cottage: no stairs, one `door` leaf, the house door a door node draws), and the palette
            then has no tile for what it lacks

Outputs:
  godot/asset/MAPS/walls/interior/<style>.webp, <style>-floor.webp
  godot/asset/MAPS/walls/interior/interior-walls.json
  godot/asset/MAPS/walls/interior/palette.png, godot/game/world/interior/interior_wall_tileset.tres
  (a column per style, each style's column fixed by its `column` in STYLES, a row per kind; the
  tileset keeps the uid it has, so the room scenes that use it do not change)

Usage: python scripts/art/pack-interior-walls.py [style ...] [--preview]   (Pillow, numpy)
       then "<Godot console exe>" --headless --path godot -s res://tools/pack_interior_palette.gd
       (the palette as palette.res, which the tileset uses: no editor import needed)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

SRC = ROOT / "asset/Originals/dungeon-kit/interior-walls"
OUT = ROOT / "godot/asset/MAPS/walls/interior"
TABLE = OUT / "interior-walls.json"
PALETTE = OUT / "palette.png"
TILESET = ROOT / "godot/game/world/interior/interior_wall_tileset.tres"
CELL = 128
DEPTH = 2 * CELL
FEATHER = 14
SEAM = 16
## The floor texture tile (sheet px): the generated stones scaled to the Lair cobble's size.
FLOOR_PX = 640
SIDES = ["n", "s", "w", "e"]
OPENINGS = ["doorway", "cracked", "blown", "stairs"]
LEAVES = ["key1", "key2", "boss", "bolt", "shutter", "seal", "barricade"]
## The palette's rows (keep the order: painted scenes keep their tiles): the wall, the openings,
## then a closed door per leaf (the layer makes the door object over it).
KINDS = ["wall"] + OPENINGS + LEAVES

## Each style's `column` is its palette column, fixed: painted cells name their tile by column, so a
## repack of one style (or a new style, which takes the next free column) never restyles another's.
STYLES = {
	"lair-stone": {
		"column": 0,
		"frame": "lair-bevel-doorways-b.png",
		"openings": {"cracked": "lair-bevel-cracked.png", "blown": "lair-bevel-blown.png", "stairs": "lair-bevel-stairs.png"},
		"leaves": {k: f"lair-bevel-leaf-{k}.png" for k in LEAVES},
		"floor": "lair-floor-cobble.png",
		# the floor's colours follow the Lair's own cobble ground
		"floor_reference": "godot/asset/MAPS/grounds/64x64-tile_19x19_town-cobble.webp",
		# band edges in the sources (outer edge, floor edge) per side
		"bands": {"n": (16, 222), "s": (797, 1003), "w": (21, 222), "e": (803, 1004)},
		# plain stretches of each face along its length (two per side, between mitre and doorway)
		"plain": {"n": [(228, 418), (606, 799)], "s": [(228, 404), (622, 797)],
			"w": [(228, 402), (616, 795)], "e": [(228, 402), (618, 797)]},
		# the doorway pieces along each face (two cells), and their passages (source px)
		"boxes": {"n": (410, 616), "s": (409, 615), "w": (413, 619), "e": (415, 621)},
		"passages": {"n": (459, 81, 562, 186), "s": (456, 834, 566, 928), "w": (104, 461, 173, 571), "e": (854, 464, 921, 571)},
	},
	"cave-rock": {
		# the Deep: dark slate cave rock (asset/Originals/dungeon-kit/interior-walls/cave-bevel-*)
		"column": 1,
		"frame": "cave-bevel-doorways-b.png",
		"openings": {"cracked": "cave-bevel-cracked.png", "blown": "cave-bevel-blown.png", "stairs": "cave-bevel-stairs.png"},
		"leaves": {k: f"cave-bevel-leaf-{k}.png" for k in LEAVES},
		"floor": "cave-floor.png",

		"bands": {"n": (15, 226), "s": (796, 1007), "w": (17, 219), "e": (804, 1006)},
		"plain": {"n": [(232, 392), (624, 790)], "s": [(232, 392), (624, 790)],
			"w": [(232, 392), (624, 790)], "e": [(232, 392), (624, 790)]},
		"boxes": {"n": (403, 609), "s": (403, 609), "w": (403, 609), "e": (403, 609)},
		"passages": {"n": (450, 77, 563, 186)},
	},
	"root-rock": {
		# Fatty's arena, the Glow-moss Burrow, the bolt-hole: umber root rock (root-bevel-*)
		"column": 2,
		"frame": "root-bevel-doorways-a.png",
		"openings": {"cracked": "root-bevel-cracked.png", "blown": "root-bevel-blown.png", "stairs": "root-bevel-stairs.png"},
		"leaves": {k: f"root-bevel-leaf-{k}.png" for k in LEAVES},
		"floor": "root-floor.png",

		"bands": {"n": (15, 217), "s": (802, 999), "w": (19, 207), "e": (816, 1004)},
		"plain": {"n": [(232, 392), (624, 790)], "s": [(232, 392), (624, 790)],
			"w": [(232, 392), (624, 790)], "e": [(232, 392), (624, 790)]},
		"boxes": {"n": (402, 608), "s": (402, 608), "w": (402, 608), "e": (402, 608)},
		"passages": {"n": (452, 79, 558, 180)},
	},
	"cottage": {
		# the village houses' rooms (2026-11-19): timber-framed plaster, the back wall of the old house
		# rooms (cottage-bevel-*, made from cottage-bevel-square-b); no stairs, and no dungeon doors:
		# its one leaf is the house door, which a door node draws (docs/godot/INTERIOR_WALLS.md)
		"column": 3,
		"frame": "cottage-bevel-doorways-a.png",
		"openings": {"cracked": "cottage-bevel-cracked-a.png", "blown": "cottage-bevel-blown-a.png"},
		"leaves": {"door": "cottage-bevel-leaf-door-a.png"},
		# the faces' posts lean with the render's perspective, so every face is the north face turned
		# (`_turn_runs`), its posts square to the face on every side, each side in its own light
		"turn_runs": True,
		"bands": {"n": (26, 218), "s": (777, 965), "w": (30, 198), "e": (825, 994)},
		# the north loop is one stretch taken as it is (`exact_loop`): the post right of the doorway and
		# the panel after it up to the next post's edge, so the loop's end meets its own post as the
		# panel met the next one; the other sides' stretches only give their light
		"exact_loop": True,
		"plain": {"n": [(607, 763)], "s": [(607, 763)], "w": [(600, 750)], "e": [(600, 750)]},
		"boxes": {"n": (414, 606), "s": (414, 606), "w": (414, 606), "e": (414, 606)},
		"passages": {"n": (448, 86, 574, 200)},
	},
	"mushroom": {
		# the mushroom houses' rooms (2026-11-19, for the round rooms: round_interior_walls.gd): the
		# cottage frame in mushroom stuff, a red spotted cap rim, pale ribs, cream stem flesh, a mossy
		# stone footing (mushroom-bevel-*, made from cottage-bevel-doorways-a and the twin mushroom
		# house); its layout is the cottage's, measured again. `mushroom-bevel-blown-a` came back
		# opaque (a painted checkerboard round the frame), made fully opaque: only its north face is cut.
		"column": 4,
		"frame": "mushroom-bevel-doorways-a.png",
		"openings": {"cracked": "mushroom-bevel-cracked-a.png", "blown": "mushroom-bevel-blown-a.png"},
		"leaves": {"door": "mushroom-bevel-leaf-door-a.png"},
		"turn_runs": True,
		"exact_loop": True,
		"bands": {"n": (24, 207), "s": (780, 968), "w": (30, 197), "e": (829, 995)},
		# the rib right of the doorway and the panel after it, up to the next rib's foot
		"plain": {"n": [(598, 755)], "s": [(598, 755)], "w": [(600, 750)], "e": [(600, 750)]},
		"boxes": {"n": (421, 604), "s": (421, 604), "w": (421, 604), "e": (421, 604)},
		"passages": {"n": (457, 80, 570, 195)},
	},
}


def load(name: str) -> Image.Image:
	return Image.open(SRC / name).convert("RGBA")


def fit(im: Image.Image, w: int, h: int) -> Image.Image:
	return im.resize((int(w), int(h)), Image.Resampling.LANCZOS)


def band_crop(im: Image.Image, spec: dict, side: str, a0: int, a1: int) -> Image.Image:
	"""The face of `side` between a0 and a1 along it (source px)."""
	b0, b1 = spec["bands"][side]
	return im.crop((a0, b0, a1, b1) if side in "ns" else (b0, a0, b1, a1))


def to_piece(im: Image.Image, side: str, cells: int) -> Image.Image:
	return fit(im, cells * CELL, DEPTH) if side in "ns" else fit(im, DEPTH, cells * CELL)


def seam_blend(pieces: list[Image.Image], horizontal: bool) -> list[Image.Image]:
	"""A run of pieces that tiles in order: each piece's far end fades into the next one's start
	(the last into the first)."""
	arrays = [np.asarray(p, dtype=np.float64).copy() for p in pieces]
	if not horizontal:
		arrays = [a.transpose(1, 0, 2) for a in arrays]
	n = len(arrays)
	for i in range(n):
		a, b = arrays[i], arrays[(i + 1) % n]
		for j in range(SEAM):
			t = (j + 1) / (SEAM + 1)
			a[:, -SEAM + j] = a[:, -SEAM + j] * (1 - t) + b[:, j] * t
	if not horizontal:
		arrays = [a.transpose(1, 0, 2) for a in arrays]
	return [Image.fromarray(a.round().clip(0, 255).astype(np.uint8)) for a in arrays]


## Overlap (source px) of two stretches joined along a min-error cut.
QUILT_OVERLAP = 28


def quilt_loop(parts: list[np.ndarray], overlap: int) -> np.ndarray:
	"""Joins stretches (h x w x 4, the wall running left-right) end to start into one loop: each
	join overlaps `overlap` columns and switches from one to the next along the cheapest
	top-to-bottom path through their difference (so it follows a mortar line); the last joins
	the first. Returns the loop's one period."""
	strip = parts[0].copy()
	for nxt in parts[1:]:
		strip = _join(strip, nxt, overlap)
	# the wrap: the strip's end joins its start
	joined = _join(strip, strip[:, :overlap * 2].copy(), overlap)
	period = joined.shape[1] - overlap * 2
	out = joined[:, :period].copy()
	out[:, :overlap] = joined[:, period:period + overlap]
	return out


def _join(a: np.ndarray, b: np.ndarray, overlap: int) -> np.ndarray:
	h = min(a.shape[0], b.shape[0])
	a, b = a[:h], b[:h]
	left, right = a[:, -overlap:], b[:, :overlap]
	path = _min_cut(np.abs(left - right)[..., :3].sum(2))
	seam = left.copy()
	for y in range(h):
		seam[y, path[y]:] = right[y, path[y]:]
	return np.concatenate([a[:, :-overlap], seam, b[:, overlap:]], axis=1)


## How far (sheet px) a corner fades into the runs beside it.
CORNER_FEATHER = 22


def feather_edges(im: Image.Image, edges: tuple[str, ...], width: int) -> Image.Image:
	a = np.asarray(im).copy().astype(np.float64)
	h, w = a.shape[:2]
	ramp = np.array([(j + 1) / (width + 1) for j in range(width)])
	for edge in edges:
		if edge == "right":
			a[:, w - width:, 3] *= ramp[::-1][None, :]
		elif edge == "left":
			a[:, :width, 3] *= ramp[None, :]
		elif edge == "bottom":
			a[h - width:, :, 3] *= ramp[::-1][:, None]
		else:
			a[:width, :, 3] *= ramp[:, None]
	return Image.fromarray(a.round().clip(0, 255).astype(np.uint8))


def feather_ends(im: Image.Image, horizontal: bool) -> Image.Image:
	"""Fades an opening piece's two ends (along the wall) in, so it lies over the run under it
	without a hard edge."""
	a = np.asarray(im).copy().astype(np.float64)
	length = a.shape[1] if horizontal else a.shape[0]
	ramp = np.ones(length)
	for j in range(FEATHER):
		ramp[j] = ramp[length - 1 - j] = (j + 1) / (FEATHER + 1)
	if horizontal:
		a[..., 3] *= ramp[None, :]
	else:
		a[..., 3] *= ramp[:, None]
	return Image.fromarray(a.round().clip(0, 255).astype(np.uint8))


def inner_corner(run_floor_side: Image.Image, run_other: Image.Image, floor_at: str) -> Image.Image:
	"""A 2 x 2 cell inner corner: two faces folding round the floor's corner, split on the diagonal
	from it. `floor_at` names the quadrant the floor is in ("se": floor south and east of the block's
	corner cell ...). The pieces are a two-cell stretch of each face, already turned to fill the
	block: `run_floor_side` the face whose floor edge is the block's top or bottom, `run_other` the
	one whose floor edge is its left or right."""
	size = DEPTH
	mask = Image.new("L", (size, size), 0)
	d = ImageDraw.Draw(mask)
	# the diagonal runs from the floor's corner (the block corner touching the floor quadrant) to
	# the opposite one; the horizontal face keeps the triangle against its floor edge
	corner = {"se": (size, size), "sw": (0, size), "ne": (size, 0), "nw": (0, 0)}[floor_at]
	opposite = (size - corner[0], size - corner[1])
	# triangle against the horizontal floor edge (the edge at y = corner y)
	d.polygon([corner, (opposite[0], corner[1]), opposite], fill=255)
	out = run_other.copy()
	out.paste(run_floor_side, (0, 0), mask)
	line = ImageDraw.Draw(out)
	line.line([corner, opposite], fill=(70, 46, 26, 255), width=3)
	return out


def _min_cut(error: np.ndarray) -> np.ndarray:
	"""For each row of `error` (h x w), the column of the cheapest top-to-bottom path (dynamic
	programming, steps of at most one column)."""
	h, w = error.shape
	cost = error.copy()
	for y in range(1, h):
		left = np.r_[np.inf, cost[y - 1, :-1]]
		right = np.r_[cost[y - 1, 1:], np.inf]
		cost[y] += np.minimum(np.minimum(left, cost[y - 1]), right)
	path = np.zeros(h, dtype=int)
	path[-1] = int(np.argmin(cost[-1]))
	for y in range(h - 2, -1, -1):
		x = path[y + 1]
		lo, hi = max(0, x - 1), min(w, x + 2)
		path[y] = lo + int(np.argmin(cost[y, lo:hi]))
	return path


def _wrap_axis(a: np.ndarray, band: int) -> np.ndarray:
	"""Makes `a` (h x w x c) wrap left-right: rolled by half, its seam (now in the middle) is
	covered by the original's continuous middle (2 x band wide), joined on each side along the
	cheapest path through the difference in its outer half (image quilting), so the joins follow
	the mortar instead of cutting stones."""
	h, w = a.shape[:2]
	rolled = np.roll(a, w // 2, 1)
	x0 = w // 2 - band
	patch = a[:, x0:x0 + 2 * band]
	base = rolled[:, x0:x0 + 2 * band]
	diff = np.abs(patch - base).sum(2)
	# no cut may cross the rolled image's own seam (the middle column)
	left = _min_cut(diff[:, :band - 4])
	right = band + 4 + _min_cut(diff[:, band + 4:])
	out = rolled.copy()
	for y in range(h):
		out[y, x0 + left[y]:x0 + right[y]] = patch[y, left[y]:right[y]]
	return out


def seamless(im: Image.Image, reference: Image.Image | None = None) -> Image.Image:
	"""Makes a ground texture wrap on both axes by quilting, and matches its colours (mean and
	spread per channel) to `reference` when given."""
	a = np.asarray(im.convert("RGB"), dtype=np.float64)
	band = a.shape[1] // 4
	a = _wrap_axis(a, band)
	a = _wrap_axis(a.transpose(1, 0, 2), band).transpose(1, 0, 2)
	if reference is not None:
		r = np.asarray(reference.convert("RGB"), dtype=np.float64).reshape(-1, 3)
		flat = a.reshape(-1, 3)
		flat = (flat - flat.mean(0)) / (flat.std(0) + 1e-6) * r.std(0) + r.mean(0)
		a = flat.reshape(a.shape)
	return Image.fromarray(a.round().clip(0, 255).astype(np.uint8)).convert("RGBA")


def _turn(im: Image.Image, side: str) -> Image.Image:
	"""The north piece turned to face into the room from `side`."""
	if side == "s":
		return im.transpose(Image.Transpose.ROTATE_180)
	if side == "w":
		return im.transpose(Image.Transpose.ROTATE_90)
	if side == "e":
		return im.transpose(Image.Transpose.ROTATE_270)
	return im.copy()


def _turn_rect(rect: list[int], side: str, size: int) -> list[int]:
	"""A rect (x0, y0, x1, y1) of a square north piece, turned as `_turn` turns the piece."""
	x0, y0, x1, y1 = rect
	if side == "s":
		return [size - x1, size - y1, size - x0, size - y0]
	if side == "w":
		return [y0, size - x1, y1, size - x0]
	if side == "e":
		return [size - y1, x0, size - y0, x1]
	return list(rect)


def _mean(pieces: dict[str, Image.Image], side: str) -> np.ndarray:
	values = []
	for name, im in pieces.items():
		if len(name) == 2 and name[0] == side and name[1].isdigit():
			a = np.asarray(im, dtype=np.float64)
			values.append(a[a[..., 3] > 200][:, :3])
	return np.concatenate(values).mean(0)


def _gain(pieces: dict[str, Image.Image], source: str, side: str) -> np.ndarray:
	return _mean(pieces, side) / np.maximum(_mean(pieces, source), 1.0)


def _shade(im: Image.Image, gain: np.ndarray) -> Image.Image:
	a = np.asarray(im, dtype=np.float64).copy()
	a[..., :3] = (a[..., :3] * gain).clip(0, 255)
	return Image.fromarray(a.round().astype(np.uint8))


def _run_square(pieces: dict[str, Image.Image], side: str) -> Image.Image:
	"""The first two cells of `side`'s run as one face square (two cells along, two deep)."""
	out = Image.new("RGBA", (DEPTH, DEPTH))
	out.alpha_composite(pieces[f"{side}0"], (0, 0))
	out.alpha_composite(pieces[f"{side}1"], (CELL, 0) if side in "ns" else (0, CELL))
	return out


## The corner beam laid along a turned style's mitre: its half width and its fade (sheet px).
MITRE_HALF = 15
MITRE_FADE = 6


def _turn_runs(pieces: dict[str, Image.Image], periods: dict[str, int]) -> None:
	"""A style whose faces are the north face turned (as every opening is): the south, west and east
	runs become the north loop turned 180 / 90 CCW / 90 CW, each shaded to its own face's light in
	the render (its run's mean colour over the north run's), and the outer corners become the two
	turned faces split on the mitre, with the render's own corner beam laid along it."""
	gains = {side: _gain(pieces, "n", side) for side in SIDES}
	count = periods["n"]
	loop = Image.new("RGBA", (count * CELL, DEPTH))
	for i in range(count):
		loop.alpha_composite(pieces[f"n{i}"], (i * CELL, 0))
	for side in "swe":
		for i in range(periods[side]):
			del pieces[f"{side}{i}"]
		turned = _shade(_turn(loop, side), gains[side])
		for i in range(count):
			pieces[f"{side}{i}"] = turned.crop((i * CELL, 0, (i + 1) * CELL, DEPTH)) if side == "s" \
				else turned.crop((0, i * CELL, DEPTH, (i + 1) * CELL))
		periods[side] = count
	square = {side: _run_square(pieces, side) for side in SIDES}
	size = DEPTH
	upper_right = [(0, 0), (size, 0), (size, size)]
	upper_left = [(0, 0), (size, 0), (0, size)]
	# corner: (the face in the polygon, the other face, the polygon, the mitre runs along x == y)
	corners = {"nw": ("n", "w", upper_right, True), "ne": ("n", "e", upper_left, False),
		"sw": ("w", "s", upper_left, False), "se": ("e", "s", upper_right, True)}
	ys, xs = np.mgrid[0:size, 0:size]
	for name, (first, other, polygon, falling) in corners.items():
		mask = Image.new("L", (size, size), 0)
		ImageDraw.Draw(mask).polygon(polygon, fill=255)
		out = square[other].copy()
		out.paste(square[first], (0, 0), mask)
		distance = np.abs(xs - ys) if falling else np.abs(xs + ys - (size - 1))
		band = np.clip((MITRE_HALF - distance) / MITRE_FADE + 1.0, 0.0, 1.0)
		beam = np.asarray(pieces[name], dtype=np.float64).copy()
		beam[..., 3] *= band
		out.alpha_composite(Image.fromarray(beam.round().clip(0, 255).astype(np.uint8)))
		pieces[name] = out


def build(style: str) -> dict:
	spec = STYLES[style]
	frame = load(spec["frame"])
	pieces: dict[str, Image.Image] = {}
	# runs: the two plain stretches of each face quilted into one loop (joins cut along the
	# mortar), resampled to a whole number of cells and cut into cells
	periods = {}
	for side in SIDES:
		horizontal = side in "ns"
		parts = [np.asarray(band_crop(frame, spec, side, a0, a1), dtype=np.float64) for a0, a1 in spec["plain"][side]]
		if not horizontal:
			parts = [p.transpose(1, 0, 2) for p in parts]
		loop = np.concatenate(parts, axis=1) if spec.get("exact_loop") else quilt_loop(parts, QUILT_OVERLAP)
		depth_scale = DEPTH / loop.shape[0]
		cells = max(2, round(loop.shape[1] * depth_scale / CELL))
		periods[side] = cells
		img = Image.fromarray(loop.round().clip(0, 255).astype(np.uint8))
		img = fit(img, cells * CELL, DEPTH)
		if not horizontal:
			img = img.transpose(Image.Transpose.TRANSPOSE)
		for i in range(cells):
			pieces[f"{side}{i}"] = img.crop((i * CELL, 0, (i + 1) * CELL, DEPTH)) if horizontal else img.crop((0, i * CELL, DEPTH, (i + 1) * CELL))
	# outer corners: the mitred squares
	b = spec["bands"]
	pieces["nw"] = fit(frame.crop((b["w"][0], b["n"][0], b["w"][1], b["n"][1])), DEPTH, DEPTH)
	pieces["ne"] = fit(frame.crop((b["e"][0], b["n"][0], b["e"][1], b["n"][1])), DEPTH, DEPTH)
	pieces["sw"] = fit(frame.crop((b["w"][0], b["s"][0], b["w"][1], b["s"][1])), DEPTH, DEPTH)
	pieces["se"] = fit(frame.crop((b["e"][0], b["s"][0], b["e"][1], b["s"][1])), DEPTH, DEPTH)
	# a corner's two edges toward its runs fade into the runs drawn under it (rough stone shows a
	# step where a corner cut from one place meets a run cut from another)
	# (no feathering: nothing is drawn under a corner, so a faded edge showed the dark through)
	# inner corners: the wall block diagonal from a floor corner. Floor south and east of it
	# (in_se): its top-left... the faces that meet there are a south face (floor north of it? no:
	# the floor is south and east) -> the north face (floor south) and the west face (floor east).
	if spec.get("turn_runs"):
		_turn_runs(pieces, periods)
	def two(side: str, i: int) -> Image.Image:
		a0, a1 = spec["plain"][side][i]
		return to_piece(band_crop(frame, spec, side, a0, a1), side, 2)
	def square(side: str) -> Image.Image:
		if spec.get("turn_runs"):
			return _run_square(pieces, side)
		p = two(side, 0)
		return fit(p, DEPTH, DEPTH)
	pieces["in_se"] = inner_corner(square("n"), square("w"), "se")
	pieces["in_sw"] = inner_corner(square("n"), square("e"), "sw")
	pieces["in_ne"] = inner_corner(square("s"), square("w"), "ne")
	pieces["in_nw"] = inner_corner(square("s"), square("e"), "nw")
	# openings and leaves: the north piece of each kind, turned for the other sides as Zelda's sheet
	# does (south 180, west 90 counter-clockwise, east 90 clockwise), so every door is the same front
	# doorway facing into the room; a turned piece takes its side's light (a per-channel gain from
	# that side's run over the north run's), its ends fade into the run under it
	gains = {side: _gain(pieces, "n", side) for side in SIDES}
	sources = {"doorway": frame} | {k: load(v) for k, v in spec["openings"].items()}
	a0, a1 = spec["boxes"]["n"]
	for kind, im in sources.items():
		north = to_piece(band_crop(im, spec, "n", a0, a1), "n", 2)
		for side in SIDES:
			turned = _shade(_turn(north, side), gains[side])
			pieces[f"{side}_{kind}"] = feather_ends(turned, side in "ns")
	leaves: dict[str, list[int]] = {}
	leaf_images: dict[str, Image.Image] = {}
	b0, b1 = spec["bands"]["n"]
	box = (a0, b0, a1, b1)
	p = spec["passages"]["n"]
	for kind, name in spec["leaves"].items():
		north = to_piece(band_crop(load(name), spec, "n", a0, a1), "n", 2)
		sx = north.width / (box[2] - box[0])
		sy = north.height / (box[3] - box[1])
		rect_n = [round((p[0] - box[0]) * sx), round((p[1] - box[1]) * sy), round((p[2] - box[0]) * sx), round((p[3] - box[1]) * sy)]
		for side in SIDES:
			turned = _shade(_turn(north, side), gains[side])
			rect = _turn_rect(rect_n, side, north.width)
			leaf_images[f"{side}_{kind}"] = turned.crop(tuple(rect))
			leaves[f"{side}_{kind}"] = rect
	# each opening's front: the frame (jambs, lintel, the face round it) without its passage, drawn
	# over the bodies in the passage, so one walks under the lintel and between the jambs (Zelda's
	# doorway tiles over the sprites); the passage runs from the lintel to the room-side edge
	p = spec["passages"]["n"]
	north_size = DEPTH
	sx = (2 * CELL) / (box[2] - box[0])
	sy = DEPTH / (box[3] - box[1])
	passage_n = [round((p[0] - box[0]) * sx), round((p[1] - box[1]) * sy), round((p[2] - box[0]) * sx), DEPTH]
	for kind in list(sources):
		for side in SIDES:
			front = pieces[f"{side}_{kind}"].copy()
			r = _turn_rect(passage_n, side, north_size)
			a = np.asarray(front).copy()
			a[r[1]:r[3], r[0]:r[2], 3] = 0
			pieces[f"{side}_{kind}_front"] = Image.fromarray(a)
	# pack: a shelf of 256-tall rows
	sheet_w = 2048
	placed: dict[str, list[int]] = {}
	x = y = row_h = 0
	order = list(pieces) + [f"leaf:{k}" for k in leaf_images]
	images = {**pieces, **{f"leaf:{k}": v for k, v in leaf_images.items()}}
	for key in order:
		im = images[key]
		if x + im.width > sheet_w:
			x, y, row_h = 0, y + row_h, 0
		placed[key] = [x, y, im.width, im.height]
		x += im.width
		row_h = max(row_h, im.height)
	sheet = Image.new("RGBA", (sheet_w, y + row_h))
	for key, rect in placed.items():
		sheet.alpha_composite(images[key], (rect[0], rect[1]))
	OUT.mkdir(parents=True, exist_ok=True)
	save_game_webp(sheet, OUT / f"{style}.webp")
	if spec.get("floor"):
		# the Lair cobble follows the Lair's own ground; the others keep their generated colours
		floor_ref = Image.open(ROOT / spec["floor_reference"]).convert("RGBA") if spec.get("floor_reference") else None
		floor = seamless(fit(load(spec["floor"]), FLOOR_PX, FLOOR_PX), floor_ref)
		save_game_webp(floor, OUT / f"{style}-floor.webp")
	if "--preview" in sys.argv:
		sheet.save(SRC.parent / "interior-walls" / f"_{style}-sheet-preview.png")
	table = {
		"model": "bevel",
		"texture": f"res://asset/MAPS/walls/interior/{style}.webp",
		"floor": f"res://asset/MAPS/walls/interior/{style}-floor.webp" if spec.get("floor") else "",
		"floor_px": FLOOR_PX,
		"cell": CELL,
		"depth_cells": DEPTH // CELL,
		"run_period": periods,
		"pieces": {k: v for k, v in placed.items() if not k.startswith("leaf:")},
		"leaves": {k.removeprefix("leaf:"): {"region": v, "in_opening": leaves[k.removeprefix("leaf:")][:2]}
			for k, v in placed.items() if k.startswith("leaf:")},
	}
	return table


def _thumb(sheet: Image.Image, rect: list[int], size: int = 64) -> Image.Image:
	x, y, w, h = rect
	piece = sheet.crop((x, y, x + w, y + h))
	piece.thumbnail((size, size), Image.Resampling.LANCZOS)
	out = Image.new("RGBA", (size, size), (14, 11, 16, 255))
	out.alpha_composite(piece, ((size - piece.width) // 2, (size - piece.height) // 2))
	return out


def palette_columns(styles: list[str]) -> dict[str, int]:
	"""Each style's fixed palette column (its `column` in STYLES)."""
	columns = {}
	for style in styles:
		if "column" not in STYLES.get(style, {}):
			raise SystemExit(f"{style}: no palette column in STYLES")
		columns[style] = STYLES[style]["column"]
	if len(set(columns.values())) != len(columns):
		raise SystemExit(f"two styles share a palette column: {columns}")
	return columns


def tileset_uids() -> tuple[str, str]:
	"""The uids the tileset file has now (its own, and its palette texture's): Godot gave them, the
	room scenes name the tileset by its uid, so a repack keeps them ("" when there is none)."""
	if not TILESET.exists():
		return "", ""
	text = TILESET.read_text(encoding="utf-8")
	own = re.search(r'^\[gd_resource type="TileSet"[^\]]* uid="(uid://[^"]+)"', text, re.M)
	texture = re.search(r'^\[ext_resource type="Texture2D"[^\]]* uid="(uid://[^"]+)"[^\]]*palette\.res"', text, re.M)
	return (own.group(1) if own else ""), (texture.group(1) if texture else "")


def _has_kind(table: dict, kind: str) -> bool:
	"""True when the packed style has a palette tile of `kind` (the wall, an opening, a door's leaf)."""
	if kind == "wall":
		return True
	if kind in OPENINGS:
		return "n_" + kind in table["pieces"]
	return "n_" + kind in table["leaves"]


def palette(tables: dict[str, dict]) -> None:
	"""The paint palette: per style a column of 64 px tiles (the style's fixed `column`), each a small
	picture of its piece cut from the packed sheet (so it always matches the art): the wall (a north
	run with its corner), the openings, then each closed door (the north doorway with its leaf)."""
	columns = palette_columns(list(tables))
	image = Image.new("RGBA", (64 * (max(columns.values()) + 1), 64 * len(KINDS)), (0, 0, 0, 0))
	for style, col in columns.items():
		table = tables[style]
		sheet = Image.open(OUT / f"{style}.webp").convert("RGBA")
		pieces = table["pieces"]
		for row, kind in enumerate(KINDS):
			if not _has_kind(table, kind):
				continue
			if kind == "wall":
				# a corner and a run side by side: reads as "wall"
				a = pieces["nw"]
				b = pieces["n0"]
				pair = Image.new("RGBA", (a[2] + b[2], a[3]))
				pair.alpha_composite(sheet.crop((a[0], a[1], a[0] + a[2], a[1] + a[3])), (0, 0))
				pair.alpha_composite(sheet.crop((b[0], b[1], b[0] + b[2], b[1] + b[3])), (a[2], 0))
				pair.thumbnail((64, 64), Image.Resampling.LANCZOS)
				tile = Image.new("RGBA", (64, 64), (14, 11, 16, 255))
				tile.alpha_composite(pair, (0, (64 - pair.height) // 2))
			elif kind in OPENINGS:
				tile = _thumb(sheet, pieces["n_" + kind])
			else:
				r = pieces["n_doorway"]
				door = sheet.crop((r[0], r[1], r[0] + r[2], r[1] + r[3]))
				leaf = table["leaves"]["n_" + kind]
				lx, ly, lw, lh = leaf["region"]
				door.alpha_composite(sheet.crop((lx, ly, lx + lw, ly + lh)), tuple(leaf["in_opening"]))
				door.thumbnail((64, 64), Image.Resampling.LANCZOS)
				tile = Image.new("RGBA", (64, 64), (14, 11, 16, 255))
				tile.alpha_composite(door, ((64 - door.width) // 2, (64 - door.height) // 2))
			image.alpha_composite(tile, (col * 64, row * 64))
	image.save(PALETTE)
	own_uid, texture_uid = tileset_uids()
	lines = ['[gd_resource type="TileSet" format=3%s]' % (f' uid="{own_uid}"' if own_uid else ""), "",
		'[ext_resource type="Texture2D"%s path="res://asset/MAPS/walls/interior/palette.res" id="1_palette"]'
			% (f' uid="{texture_uid}"' if texture_uid else ""), "",
		'[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_interior"]',
		'texture = ExtResource("1_palette")', "texture_region_size = Vector2i(64, 64)"]
	for style, col in sorted(columns.items(), key=lambda item: item[1]):
		for row, kind in enumerate(KINDS):
			if not _has_kind(tables[style], kind):
				continue
			lines.append(f"{col}:{row}/0 = 0")
			lines.append(f'{col}:{row}/0/custom_data_0 = "{style}"')
			if kind != "wall":
				# (the wall's empty opening is the default, which Godot leaves out)
				lines.append(f'{col}:{row}/0/custom_data_1 = "{kind}"')
	lines += ["", "[resource]", "tile_size = Vector2i(64, 64)",
		'custom_data_layer_0/name = "interior_style"', "custom_data_layer_0/type = 4",
		'custom_data_layer_1/name = "interior_opening"', "custom_data_layer_1/type = 4",
		'sources/0 = SubResource("TileSetAtlasSource_interior")', ""]
	TILESET.parent.mkdir(parents=True, exist_ok=True)
	TILESET.write_text(chr(10).join(lines), encoding="utf-8")


def main() -> None:
	wanted = [a for a in sys.argv[1:] if not a.startswith("--")] or list(STYLES)
	tables = json.loads(TABLE.read_text(encoding="utf-8")) if TABLE.exists() else {}
	tables = {k: v for k, v in tables.items() if v.get("model") == "bevel"}
	for style in wanted:
		tables[style] = build(style)
		print("packed", style)
	TABLE.write_text(json.dumps(tables, indent=1), encoding="utf-8")
	palette(tables)
	print("wrote", TABLE, PALETTE, TILESET)


if __name__ == "__main__":
	main()
