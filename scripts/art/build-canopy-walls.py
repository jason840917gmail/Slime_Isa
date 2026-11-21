#!/usr/bin/env python3
"""Packs the canopy walls' crowns and roots (docs/godot/FORESTS.md "Canopy walls").

A canopy wall is the forest layer's second way to paint a wood (owner, 2026-11-20): one solid mass
of big round overlapping crowns with roots only along its foot, so a forest band reads as a wall
nobody can pass. ForestLayer lays a set's crowns over the painted cells and its roots along their
south edge (game/world/forest/canopy_walls.gd).

Sources: asset/Originals/trees/canopy-wall/canopy-<crowns|roots>-<variant>.png, Magnific GPT 2.5
renders on a transparent background, six pieces each on a 3 x 2 grid. Each piece is cut out (the
sheet's opaque blobs, read row by row), optionally colour-graded like the forest set's leaves, sized
to its width in world units at 2 px per unit and packed into its set's atlas.

Outputs:
  godot/asset/MAPS/trees/canopy/<set>.webp   one atlas per set
  godot/asset/MAPS/trees/canopy/canopy.json  {scale, sets: {set: {texture, crowns: [[x, y, w, h]],
      roots: [[x, y, w, h]]}}}: each piece stands on the middle of its rectangle's bottom edge
The atlases import with mipmaps on (drawn at half size, as the big trees).

Usage: python scripts/art/build-canopy-walls.py   (numpy, Pillow)
Then run scripts/art/build-forest-paint-tiles.py (the palette's canopy tiles).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

SOURCES = ROOT / "asset/Originals/trees/canopy-wall"
OUT_DIR = ROOT / "godot/asset/MAPS/trees/canopy"
TABLE = OUT_DIR / "canopy.json"
RES_DIR = "res://asset/MAPS/trees/canopy/"
## Art pixels per world unit (128 px per 64-unit cell); the game draws them at 0.5.
DENSITY = 2
PAD = 2

## Per set: its crown and root sheets (a name, or (name, n) to take only the sheet's first n pieces:
## the wall picks every piece alike, so a set's mix follows its pieces' counts), their widths in world
## units, and the crowns' leaf grade (hue shift in degrees, saturation and value scale, as
## scripts/art/build-tree-sets.py) or None.
SETS = {
	"forest": {
		"crowns": ["canopy-crowns-b.png", "canopy-crowns-a.png"],
		"roots": ["canopy-roots-b.png"],
		"crown_width": 150,
		"root_width": 100,
		# the forest set's oak grade: the renders come out yellow-olive
		"grade": (30, 0.72, 0.95),
	},
	# the village mix's apples and cherries: 12 apple crowns, 6 cherry (about a third in blossom)
	"village": {
		"crowns": ["village-crowns-apple-a.png", "village-crowns-apple-b.png", "village-crowns-cherry-a.png"],
		"roots": ["village-roots-a.png"],
		"crown_width": 150,
		"root_width": 100,
		"grade": None,
	},
	# the caverns' glowing mushrooms first (owner, 2026-11-20: "use the blue mush trees even more than
	# the crystal ones"): 6 mushroom caps to 3 amethyst crowns, 6 mushroom stems to 3 twisted trunks
	# (the -a mushroom sheets came out with a white haze round each piece and are not used)
	"crystal": {
		"crowns": ["crystal-caps-mushroom-b.png", ("crystal-crowns-a.png", 3)],
		"roots": ["crystal-stems-mushroom-b.png", ("crystal-roots-a.png", 3)],
		"crown_width": 150,
		"root_width": 100,
		"grade": None,
	},
}

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{res}"

[params]

compress/mode=1
compress/high_quality=false
compress/lossy_quality=0.9
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def blobs(image: np.ndarray, min_area: int = 4000) -> list[np.ndarray]:
	"""The sheet's pieces, row by row then left to right, each cropped to its pixels: the opaque
	blobs (alpha over 24) bigger than `min_area`, found by flood fill on a quarter-size mask."""
	alpha = image[..., 3] > 24
	small = alpha[::4, ::4]
	labels = np.zeros(small.shape, dtype=np.int32)
	boxes = []
	count = 0
	for sy, sx in zip(*np.nonzero(small)):
		if labels[sy, sx]:
			continue
		count += 1
		stack = [(sy, sx)]
		labels[sy, sx] = count
		ys, xs = [], []
		while stack:
			y, x = stack.pop()
			ys.append(y)
			xs.append(x)
			for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
				if 0 <= ny < small.shape[0] and 0 <= nx < small.shape[1] and small[ny, nx] and not labels[ny, nx]:
					labels[ny, nx] = count
					stack.append((ny, nx))
		if len(ys) * 16 >= min_area:
			boxes.append((min(ys) * 4, min(xs) * 4, max(ys) * 4 + 4, max(xs) * 4 + 4))
	# rows: pieces whose tops lie within half a piece of each other
	boxes.sort(key=lambda b: b[0])
	rows: list[list[tuple]] = []
	for box in boxes:
		if rows and box[0] - rows[-1][0][0] < (rows[-1][0][2] - rows[-1][0][0]) // 2:
			rows[-1].append(box)
		else:
			rows.append([box])
	pieces = []
	for row in rows:
		for y0, x0, y1, x1 in sorted(row, key=lambda b: b[1]):
			part = image[y0:y1, x0:x1].copy()
			ys, xs = np.nonzero(part[..., 3] > 24)
			pieces.append(part[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
	return pieces


def grade(rgba: np.ndarray, measures: tuple) -> np.ndarray:
	dh, ks, kv = measures
	hsv = np.array(Image.fromarray(rgba[..., :3]).convert("HSV")).astype(np.float64)
	h = hsv[..., 0] * 360 / 255
	s = hsv[..., 1]
	v = hsv[..., 2]
	weight = np.clip((s - 60) / 60, 0, 1) * np.clip(1 - np.maximum(0, np.maximum(36 - h, h - 160)) / 12, 0, 1)
	weight *= np.clip((v - 25) / 40, 0, 1)
	shift = dh * (1 - 0.35 * (v / 255) ** 2)
	out = np.stack([
		((h + weight * shift) % 360) * 255 / 360,
		np.clip(s * (1 + weight * (ks - 1)), 0, 255),
		np.clip(v * (1 + weight * (kv - 1)), 0, 255),
	], -1).astype(np.uint8)
	rgb = np.array(Image.fromarray(out, "HSV").convert("RGB"))
	return np.concatenate([rgb, rgba[..., 3:4]], -1)


def resize(rgba: np.ndarray, width_units: float) -> Image.Image:
	image = Image.fromarray(rgba, "RGBA")
	width = round(width_units * DENSITY)
	return image.resize((width, max(1, round(image.height * width / image.width))), Image.LANCZOS)


def pack(pieces: list[Image.Image]) -> tuple[Image.Image, list[list[int]]]:
	"""Shelf-packs the pieces into an atlas at most 2048 px wide."""
	rects = []
	x = y = shelf = 0
	for piece in pieces:
		if x + piece.width + PAD > 2048:
			x = 0
			y += shelf + PAD
			shelf = 0
		rects.append([x, y, piece.width, piece.height])
		x += piece.width + PAD
		shelf = max(shelf, piece.height)
	atlas = Image.new("RGBA", (2048, y + shelf), (0, 0, 0, 0))
	for piece, (px, py, _, _) in zip(pieces, rects):
		atlas.alpha_composite(piece, (px, py))
	return atlas, rects


## As game/world/forest/forest_layer.gd lays them: a root's feet 62 units down its cell, the crown
## over it standing at most 37 down (FOOT_CROWN_Y + CROWN_JITTER.y), at 0.92 of its size at least.
## A root must stay under that crown's lower three quarters (its dome narrows above), or its trunk
## shows over the crowns behind it (the owner's screenshot of 2026-11-20).
ROOT_FOOT_Y = 62
LOWEST_CROWN_FOOT = 37
SMALLEST_CROWN = 0.92
COVERED_SHARE = 0.75


def check_roots(name: str, crowns: list[Image.Image], roots: list[Image.Image]) -> None:
	"""Warns about roots too tall to hide under the set's smallest crown."""
	lowest = min(c.height for c in crowns) / DENSITY * SMALLEST_CROWN
	limit = ROOT_FOOT_Y - LOWEST_CROWN_FOOT + lowest * COVERED_SHARE
	for i, root in enumerate(roots):
		if root.height / DENSITY > limit:
			print(f"WARNING {name}: root {i} is {root.height / DENSITY:.0f} units tall, over the {limit:.0f} its crown hides")


def sheet_pieces(sheets: list) -> list[np.ndarray]:
	"""The pieces of `sheets` (names, or (name, n) for a sheet's first n pieces), in order."""
	pieces = []
	for sheet in sheets:
		name, limit = (sheet, None) if isinstance(sheet, str) else sheet
		found = blobs(np.array(Image.open(SOURCES / name).convert("RGBA")))
		pieces += found[:limit] if limit else found
	return pieces


def main() -> None:
	OUT_DIR.mkdir(parents=True, exist_ok=True)
	table = {"scale": 1.0 / DENSITY, "sets": {}}
	for name, spec in SETS.items():
		crowns: list[Image.Image] = []
		roots: list[Image.Image] = []
		for piece in sheet_pieces(spec["crowns"]):
			if spec["grade"]:
				piece = grade(piece, spec["grade"])
			crowns.append(resize(piece, spec["crown_width"]))
		for piece in sheet_pieces(spec["roots"]):
			roots.append(resize(piece, spec["root_width"]))
		check_roots(name, crowns, roots)
		atlas, rects = pack(crowns + roots)
		path = OUT_DIR / f"{name}.webp"
		save_game_webp(atlas, path)
		import_path = path.with_name(path.name + ".import")
		if not import_path.exists():
			import_path.write_text(IMPORT.format(res=RES_DIR + path.name), encoding="utf-8")
		table["sets"][name] = {
			"texture": RES_DIR + path.name,
			"crowns": rects[:len(crowns)],
			"roots": rects[len(crowns):],
		}
		print(f"{name}: {len(crowns)} crowns, {len(roots)} roots -> {path.relative_to(ROOT)} {atlas.size}")
	text = json.dumps(table, indent="\t")
	# one rectangle per line
	text = re.sub(r"\[\s+(\d+),\s+(\d+),\s+(\d+),\s+(\d+)\s+\]", r"[\1, \2, \3, \4]", text)
	TABLE.write_text(text + "\n", encoding="utf-8")
	print(f"wrote {TABLE.relative_to(ROOT)}")


if __name__ == "__main__":
	main()
