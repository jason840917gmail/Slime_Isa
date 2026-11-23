#!/usr/bin/env python3
"""Packs the interior rooms' floor trims (docs/godot/INTERIOR_WALLS.md "Floor trim").

A floor trim is the edging laid on the floor along the foot of a room's walls, as Zelda's dungeons
border their floors: a band of blocks between the wall's face and the floor that softens where they
meet. It is painted cell by cell on a room's `floor-trim` layer (InteriorTrimLayer), a trim per
cell, so each wall and floor gets the edging that suits it. A trim is a SHAPE in a COLOUR.

Each SHAPE is one Magnific render (asset/Originals/dungeon-kit/interior-walls/trims/<shape>-<x>.png,
GPT 2.5, neutral grey stone on a transparent background): a long straight strip of identical blocks
on top, a few loose corner blocks under it (unused). The packer finds the strip, cuts its inner
blocks from joint to joint and lays them again, `blocks` to a cell, at the shape's `depth`, so a cell
starts and ends on a joint and cells join without a seam; `VARIANTS` cells each take other blocks.
The corner block is a block's two ends put together, square. A `loose` shape (rubble) keeps the
gaps round its stones see-through; the others are solid.

The sheet holds each shape once, in grey: its own levels stretched to 0..1 (dark joints 0, the
light 1). Each COLOUR is a gradient map (`stops`: dark joints, the inset, the rim, the light; `solid`
for a shape without an inset, whose stone the inset's colour would speckle), which the game lays over
the grey with a shader (game/world/interior/interior_trim.gdshader), so a colour costs no sheet space.

Pieces (sheet px, 128 a 64-unit cell; the light stays on the upper left on every side):
  h0..   128 x depth   the band along a north or south wall (the floor below or above it)
  v0..   depth x 128   the band along a west or east wall: the h piece transposed
  c      depth x depth the block where two bands meet (a room's corner, outer or inner)

Outputs:
  godot/asset/MAPS/walls/interior/floor-trims.webp (grey, a line per shape), floor-trims.json
  (`shapes`: depth, variants, pieces; `trims`: <shape>-<colour> -> shape, colour, ramp)
  godot/asset/MAPS/walls/interior/trim-palette.png, godot/game/world/interior/interior_trim_tileset.tres
  (a column per shape, a row per colour, each at its fixed `column` / `row`; the tileset keeps the
  uid it has, so the room scenes that use it do not change)

Usage: python scripts/art/pack-floor-trims.py [--preview=<png>]   (Pillow, numpy)
       then "<Godot console exe>" --headless --path godot -s res://tools/pack_interior_palette.gd
       (both palettes as .res textures, which the tilesets use: no editor import needed)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/dungeon-kit/interior-walls/trims"
OUT = ROOT / "godot/asset/MAPS/walls/interior"
SHEET = OUT / "floor-trims.webp"
TABLE = OUT / "floor-trims.json"
PALETTE = OUT / "trim-palette.png"
TILESET = ROOT / "godot/game/world/interior/interior_trim_tileset.tres"
CELL = 128
VARIANTS = 3
# empty px round every piece on the sheet, filled with its edge (no bleeding under mipmaps)
GUTTER = 4
LANCZOS = Image.Resampling.LANCZOS

# shape -> its render, how many blocks of the strip the render has, how many a cell takes, the
# band's depth (sheet px, across the band), whether it has an inset (a second colour), whether its
# gaps are see-through (`loose`) and its palette column (its line on the sheet)
SHAPES = {
	"framed": {"source": "framed-a.png", "count": 8, "blocks": 2, "depth": 56, "inset": True, "column": 0,
		"label": "framed blocks"},
	"bricks": {"source": "bricks-b.png", "count": 6, "blocks": 1, "depth": 52, "inset": False, "column": 1,
		"label": "bricks"},
	"slim": {"source": "bricks-a.png", "count": 8, "blocks": 2, "depth": 30, "inset": False, "column": 2,
		"label": "slim bricks"},
	"studded": {"source": "studded-b.png", "count": 10, "blocks": 2, "depth": 56, "inset": True, "column": 3,
		"label": "studded tiles"},
	"cushion": {"source": "kerb-a.png", "count": 8, "blocks": 2, "depth": 48, "inset": False, "column": 4,
		"label": "cushion stones"},
	"cobble": {"source": "cobble-a.png", "count": 10, "blocks": 2, "depth": 52, "inset": False, "column": 5,
		"label": "cobble setts"},
	"diamond": {"source": "diamond-a.png", "count": 10, "blocks": 2, "depth": 56, "inset": True, "column": 6,
		"label": "diamond tiles"},
	"flags": {"source": "flags-b.png", "count": 6, "blocks": 1, "depth": 50, "inset": False, "column": 7,
		"label": "flagstones"},
	"planks": {"source": "planks-b.png", "count": 12, "blocks": 4, "depth": 52, "inset": False, "column": 8,
		"label": "planks"},
	"rubble": {"source": "rubble-a.png", "count": 8, "blocks": 2, "depth": 50, "inset": False, "loose": True,
		"column": 9, "label": "rubble"},
	# 2026-11-21 (the owner: a trim for the crystal interior walls that matches their art): slate blocks
	# set with a cluster of crystal points, as the crystal-cave style's door frames (crystal-b.png took
	# studded-b.png for its layout and a crop of the crystal-cave frames for its look; -a the other take)
	"crystal": {"source": "crystal-b.png", "count": 8, "blocks": 2, "depth": 56, "inset": True, "column": 10,
		"label": "crystal studs"},
}

# colour -> gradient map stops (grey 0..1 -> RGB) and its palette row: `stops` for a shape with an
# inset (dark joints, the inset's colour, the rim's, its light), `solid` for one without (the rim's
# colour only; the inset's would speckle the stone). One list serves both when the colour has no
# second one. Rows 6.. are taken from the room styles' own walls and floors (lair-stone, cave-rock,
# root-rock and their floors), so they sit on them.
COLOURS = {
	"cream": {"row": 0, "label": "fort cream (lair stone)", "stops": [
		(0.00, "1c120c"), (0.18, "3a2818"), (0.42, "8a7556"), (0.60, "b9a17a"), (0.80, "e2d0a6"), (1.00, "fbf1d4")]},
	"slate": {"row": 1, "label": "slate (cave rock)", "stops": [
		(0.00, "0c0e14"), (0.18, "1e2430"), (0.42, "4a5466"), (0.60, "6d7a8e"), (0.80, "9eabbd"), (1.00, "dbe4ee")]},
	"umber": {"row": 2, "label": "umber (root rock)", "stops": [
		(0.00, "140c08"), (0.18, "2e1c12"), (0.42, "5e3f2a"), (0.60, "86603f"), (0.80, "b08a5e"), (1.00, "e6cc9a")]},
	"moss": {"row": 3, "label": "moss green, blue inset", "stops": [
		(0.00, "0b130e"), (0.18, "17261c"), (0.40, "2f3f78"), (0.52, "4a5ea6"), (0.64, "3d7a40"), (0.82, "79b860"), (1.00, "d4f0a8")],
		"solid": [(0.00, "0b130e"), (0.18, "17261c"), (0.45, "2f5a34"), (0.70, "4f9048"), (0.88, "86c46a"), (1.00, "d4f0a8")]},
	"ember": {"row": 4, "label": "ember orange, plum joints", "stops": [
		(0.00, "120a1a"), (0.18, "2a1838"), (0.40, "5a2a3a"), (0.55, "9a4a24"), (0.75, "d07a2e"), (1.00, "ffd08a")],
		"solid": [(0.00, "120a1a"), (0.18, "2a1838"), (0.42, "7a3622"), (0.66, "c06a28"), (0.86, "e89040"), (1.00, "ffd08a")]},
	"brick": {"row": 5, "label": "brick red, navy inset", "stops": [
		(0.00, "0c0c18"), (0.18, "1a1c34"), (0.40, "2c3256"), (0.52, "47507c"), (0.64, "8a2f2a"), (0.82, "c2554a"), (1.00, "f4b0a0")],
		"solid": [(0.00, "0c0c18"), (0.18, "1a1c34"), (0.44, "5e2224"), (0.68, "9c3a32"), (0.86, "c85e50"), (1.00, "f4b0a0")]},
	"ochre": {"row": 6, "label": "ochre (lair stone's gold)", "stops": [
		(0.00, "1e1006"), (0.18, "4a2e14"), (0.42, "8c653b"), (0.60, "b88c55"), (0.80, "e6bd78"), (1.00, "fdf0b8")]},
	"khaki": {"row": 7, "label": "khaki (lair floor)", "stops": [
		(0.00, "161409"), (0.18, "36321f"), (0.42, "6a6442"), (0.60, "8c8564"), (0.80, "b2a686"), (1.00, "ddd2b0")]},
	"taupe": {"row": 8, "label": "taupe (cave rock's brown)", "stops": [
		(0.00, "100a06"), (0.18, "2c2218"), (0.42, "4e4234"), (0.60, "6a5a48"), (0.80, "948060"), (1.00, "d4bc90")]},
	"charcoal": {"row": 9, "label": "charcoal (cave floor)", "stops": [
		(0.00, "08080a"), (0.18, "18191c"), (0.42, "33353a"), (0.60, "4a4c52"), (0.80, "6c6c70"), (1.00, "a8a6a2")]},
	"clay": {"row": 10, "label": "clay (root floor)", "stops": [
		(0.00, "1a0c04"), (0.18, "3e200c"), (0.42, "6e4220"), (0.60, "8e5a2c"), (0.80, "b8803e"), (1.00, "eebc78")]},
	"lichen": {"row": 11, "label": "lichen grey, moss inset", "stops": [
		(0.00, "0c0e0a"), (0.18, "1c2218"), (0.40, "3c5230"), (0.52, "56703e"), (0.64, "6a6e64"), (0.82, "9a9c90"), (1.00, "d8dacc")],
		"solid": [(0.00, "0c0e0a"), (0.18, "1c2218"), (0.45, "4a5440"), (0.70, "6e7a5e"), (0.88, "98a084"), (1.00, "d0d6bc")]},
	# 2026-11-21, for the crystal-cave rooms: "crystal" is the crystal strip's own colours (its blocks'
	# pixels binned by this sheet's grey, the mean colour of each bin: blue slate up to the glowing
	# crystals), "amethyst" the same light in the crystals' violet.
	"crystal": {"row": 12, "label": "crystal blue (crystal cave)", "stops": [
		(0.00, "07070f"), (0.03, "090918"), (0.13, "0d244d"), (0.23, "183e7f"), (0.35, "2b5ba9"), (0.48, "3c7fcd"),
		(0.60, "48a6df"), (0.72, "69c4e4"), (0.84, "95ddf2"), (0.97, "d4f3f9"), (1.00, "f2fdff")]},
	"amethyst": {"row": 13, "label": "amethyst (crystal cave's violet)", "stops": [
		(0.00, "0a0710"), (0.03, "0e0a1a"), (0.13, "1e1640"), (0.23, "33276c"), (0.35, "4c3a96"), (0.48, "6a4fc0"),
		(0.60, "8c66d8"), (0.72, "ad86e6"), (0.84, "cfaef2"), (0.97, "efe2fc"), (1.00, "fdf8ff")]},
}


def strip_of(im: Image.Image, loose: bool) -> Image.Image:
	"""The long strip of blocks in a render: the longest run of rows in its top half that are mostly
	opaque (a loose shape's grown by the rows its round stones reach into), cut to their opaque
	columns."""
	a = np.asarray(im)[..., 3] > 128
	h = a.shape[0]
	runs: list[list[int]] = []
	for y in range(h // 2):
		if a[y].mean() > 0.6:
			if runs and runs[-1][1] == y:
				runs[-1][1] = y + 1
			else:
				runs.append([y, y + 1])
	if not runs:
		raise SystemExit("no strip in the render")
	y0, y1 = max(runs, key=lambda r: r[1] - r[0])
	if loose:
		cover = a.mean(1)
		while y0 > 0 and cover[y0 - 1] > 0.05:
			y0 -= 1
		while y1 < h and cover[y1] > 0.05:
			y1 += 1
	cols = np.where(a[y0:y1].mean(0) > (0.05 if loose else 0.5))[0]
	return im.crop((int(cols[0]), y0, int(cols[-1]) + 1, y1))


def luminance(a: np.ndarray) -> np.ndarray:
	return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def blocks_of(strip: Image.Image, count: int, loose: bool) -> list[Image.Image]:
	"""The strip's inner blocks (all but the two at its ends, whose outer edge is the strip's own
	border), each cut from the middle of the joint before it to the middle of the joint after it (a
	loose shape's see-through gap reads as a dark joint)."""
	a = np.asarray(strip.convert("RGBA"), dtype=np.float64)
	h, w = a.shape[:2]
	lum = luminance(a) * a[..., 3] / 255.0 if loose else luminance(a)
	profile = lum[h // 5:h - h // 5].mean(0)
	step = w / count
	cuts = [0]
	for k in range(1, count):
		at = int(round(k * step))
		reach = int(step * 0.18)
		window = profile[at - reach:at + reach + 1]
		dark = np.where(window <= window.min() + 6)[0]
		# the middle of the joint: the darkest columns round where it should be
		cuts.append(at - reach + int(round(dark.mean())))
	cuts.append(w)
	return [strip.crop((cuts[k], 0, cuts[k + 1], h)) for k in range(1, count - 1)]


def levels(blocks: list[Image.Image], loose: bool) -> tuple[float, float]:
	"""The shape's grey levels (2nd and 99th percentile, of its stone only when it is loose) that the
	sheet stretches to 0..1."""
	values = []
	for b in blocks:
		a = np.asarray(b.convert("RGBA"), dtype=np.float64)
		values.append(luminance(a)[a[..., 3] > 128] if loose else luminance(a).ravel())
	values = np.concatenate(values)
	return float(np.percentile(values, 2)), float(np.percentile(values, 99))


def resized(im: Image.Image, size: tuple[int, int], loose: bool) -> Image.Image:
	"""`im` at `size`: solid (its colour only), or for a loose shape with its alpha, resized
	premultiplied so its edges take no dark fringe."""
	if loose:
		return im.convert("RGBa").resize(size, LANCZOS).convert("RGBA")
	return im.convert("RGB").resize(size, LANCZOS).convert("RGBA")


def band(blocks: list[Image.Image], variant: int, per_cell: int, depth: int, loose: bool) -> Image.Image:
	"""One cell of the band: `per_cell` blocks side by side, each CELL / per_cell wide, `depth` tall."""
	out = Image.new("RGBA", (CELL, depth), (0, 0, 0, 0))
	width = CELL // per_cell
	for j in range(per_cell):
		block = blocks[(variant * per_cell + j) % len(blocks)]
		out.paste(resized(block, (width, depth), loose), (j * width, 0))
	return out


def corner(block: Image.Image, depth: int, loose: bool) -> Image.Image:
	"""A square block, `depth` a side: the block scaled to the band's depth, its two ends joined (or
	stretched square when it is narrower than it is deep), so its bevels keep their width."""
	scaled = resized(block, (max(1, round(block.width * depth / block.height)), depth), loose)
	if scaled.width <= depth:
		return resized(scaled, (depth, depth), loose)
	half = depth // 2
	out = Image.new("RGBA", (depth, depth), (0, 0, 0, 0))
	out.paste(scaled.crop((0, 0, half, depth)), (0, 0))
	out.paste(scaled.crop((scaled.width - (depth - half), 0, scaled.width, depth)), (half, 0))
	return out


def grey(im: Image.Image, lo: float, hi: float) -> Image.Image:
	"""The piece as the sheet keeps it: its grey stretched from the shape's levels to 0..1 (in R, G
	and B), its alpha kept."""
	a = np.asarray(im.convert("RGBA"), dtype=np.float64)
	g = ((luminance(a) - lo) / max(hi - lo, 1.0)).clip(0.0, 1.0)
	value = (g * 255.0).round().astype(np.uint8)
	return Image.fromarray(np.dstack([value, value, value, a[..., 3].astype(np.uint8)]), "RGBA")


def coloured(piece: Image.Image, stops: list) -> Image.Image:
	"""A grey piece in a colour: its grey through the colour's gradient map (as the game's shader
	does it)."""
	a = np.asarray(piece.convert("RGBA"), dtype=np.float64)
	g = a[..., 0] / 255.0
	xs = [float(s[0]) for s in stops]
	rgb = [[int(str(s[1])[i:i + 2], 16) for i in (0, 2, 4)] for s in stops]
	out = np.stack([np.interp(g, xs, [c[ch] for c in rgb]) for ch in range(3)] + [a[..., 3]], -1)
	return Image.fromarray(out.round().clip(0, 255).astype(np.uint8), "RGBA")


def with_gutter(im: Image.Image) -> Image.Image:
	"""`im` with GUTTER px round it, filled by repeating its edge pixels."""
	a = np.asarray(im.convert("RGBA"))
	return Image.fromarray(np.pad(a, ((GUTTER, GUTTER), (GUTTER, GUTTER), (0, 0)), mode="edge"))


def build() -> tuple[Image.Image, dict]:
	"""The grey sheet (a line per shape: its h pieces, its v pieces, its corner) and the table."""
	deepest = max(s["depth"] for s in SHAPES.values())
	line = VARIANTS * (CELL + 2 * GUTTER) + (VARIANTS + 1) * (deepest + 2 * GUTTER)
	tall = CELL + 2 * GUTTER
	sheet = Image.new("RGBA", (line, tall * (max(s["column"] for s in SHAPES.values()) + 1)), (0, 0, 0, 0))
	shapes = {}
	for shape, spec in SHAPES.items():
		loose = bool(spec.get("loose", False))
		render = Image.open(SRC / spec["source"]).convert("RGBA")
		blocks = blocks_of(strip_of(render, loose), spec["count"], loose)
		lo, hi = levels(blocks, loose)
		cut = {f"h{v}": grey(band(blocks, v, spec["blocks"], spec["depth"], loose), lo, hi) for v in range(VARIANTS)}
		for v in range(VARIANTS):
			cut[f"v{v}"] = cut[f"h{v}"].transpose(Image.Transpose.TRANSPOSE)
		cut["c"] = grey(corner(blocks[len(blocks) // 2], spec["depth"], loose), lo, hi)
		x = 0
		y = spec["column"] * tall
		pieces = {}
		for name, piece in cut.items():
			sheet.paste(with_gutter(piece), (x, y))
			pieces[name] = [x + GUTTER, y + GUTTER, piece.width, piece.height]
			x += piece.width + 2 * GUTTER
		shapes[shape] = {"depth": spec["depth"], "variants": VARIANTS, "pieces": pieces}
	trims = {}
	for shape, spec in SHAPES.items():
		for colour, paint in COLOURS.items():
			stops = paint["stops"] if spec["inset"] else paint.get("solid", paint["stops"])
			trims[f"{shape}-{colour}"] = {"shape": shape, "colour": colour, "ramp": [[s[0], s[1]] for s in stops]}
	table = {"texture": "res://asset/MAPS/walls/interior/floor-trims.webp", "cell": CELL, "shapes": shapes, "trims": trims}
	return sheet, table


def piece_of(sheet: Image.Image, table: dict, trim: dict, name: str) -> Image.Image:
	x, y, w, h = table["shapes"][trim["shape"]]["pieces"][name]
	return coloured(sheet.crop((x, y, x + w, y + h)), trim["ramp"])


def sample(sheet: Image.Image, table: dict, trim: dict, cells: int, floor: tuple[int, int, int]) -> Image.Image:
	"""A corner of a room `cells` x `cells` big, the trim along its top and left (sheet px)."""
	size = cells * CELL
	out = Image.new("RGBA", (size, size), floor + (255,))
	for i in range(cells):
		out.alpha_composite(piece_of(sheet, table, trim, f"h{i % VARIANTS}"), (i * CELL, 0))
		out.alpha_composite(piece_of(sheet, table, trim, f"v{i % VARIANTS}"), (0, i * CELL))
	out.alpha_composite(piece_of(sheet, table, trim, "c"), (0, 0))
	return out


def tileset_uids() -> tuple[str, str]:
	"""The uids the tileset file has now (its own, and its palette texture's), so a repack keeps them
	("" when there is none)."""
	if not TILESET.exists():
		return "", ""
	text = TILESET.read_text(encoding="utf-8")
	own = re.search(r'^\[gd_resource type="TileSet"[^\]]* uid="(uid://[^"]+)"', text, re.M)
	texture = re.search(r'^\[ext_resource type="Texture2D"[^\]]* uid="(uid://[^"]+)"[^\]]*trim-palette\.res"', text, re.M)
	return (own.group(1) if own else ""), (texture.group(1) if texture else "")


def palette(sheet: Image.Image, table: dict) -> None:
	"""The paint palette: a 64 px tile per trim (its shape's column, its colour's row), a picture of a
	room's corner bordered by it."""
	columns = max(s["column"] for s in SHAPES.values()) + 1
	rows = max(c["row"] for c in COLOURS.values()) + 1
	image = Image.new("RGBA", (64 * columns, 64 * rows), (0, 0, 0, 0))
	for name, trim in table["trims"].items():
		tile = sample(sheet, table, trim, 1, (58, 52, 60)).resize((64, 64), LANCZOS)
		image.alpha_composite(tile, (SHAPES[trim["shape"]]["column"] * 64, COLOURS[trim["colour"]]["row"] * 64))
	image.save(PALETTE)
	own_uid, texture_uid = tileset_uids()
	lines = ['[gd_resource type="TileSet" format=3%s]' % (f' uid="{own_uid}"' if own_uid else ""), "",
		'[ext_resource type="Texture2D"%s path="res://asset/MAPS/walls/interior/trim-palette.res" id="1_palette"]'
			% (f' uid="{texture_uid}"' if texture_uid else ""), "",
		'[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_trim"]',
		'texture = ExtResource("1_palette")', "texture_region_size = Vector2i(64, 64)"]
	for name, trim in sorted(table["trims"].items(), key=lambda kv: (SHAPES[kv[1]["shape"]]["column"], COLOURS[kv[1]["colour"]]["row"])):
		col = SHAPES[trim["shape"]]["column"]
		row = COLOURS[trim["colour"]]["row"]
		lines.append(f"{col}:{row}/0 = 0")
		lines.append(f'{col}:{row}/0/custom_data_0 = "{name}"')
	lines += ["", "[resource]", "tile_size = Vector2i(64, 64)",
		'custom_data_layer_0/name = "floor_trim"', "custom_data_layer_0/type = 4",
		'sources/0 = SubResource("TileSetAtlasSource_trim")', ""]
	TILESET.write_text(chr(10).join(lines), encoding="utf-8")


def preview(sheet: Image.Image, table: dict, path: str) -> None:
	"""Every trim as a room corner, a column per shape, a row per colour, over a dark floor."""
	cells = 3
	size = cells * CELL // 3
	pad = 6
	columns = max(s["column"] for s in SHAPES.values()) + 1
	rows = max(c["row"] for c in COLOURS.values()) + 1
	out = Image.new("RGBA", (columns * (size + pad) + pad, rows * (size + pad) + pad), (30, 26, 32, 255))
	for trim in table["trims"].values():
		tile = sample(sheet, table, trim, cells, (96, 90, 84)).resize((size, size), LANCZOS)
		out.alpha_composite(tile, (pad + SHAPES[trim["shape"]]["column"] * (size + pad), pad + COLOURS[trim["colour"]]["row"] * (size + pad)))
	out.save(path)


def main() -> None:
	sheet, table = build()
	SHEET.parent.mkdir(parents=True, exist_ok=True)
	sheet.save(SHEET, "WEBP", lossless=True)
	TABLE.write_text(json.dumps(table, indent=1), encoding="utf-8")
	palette(sheet, table)
	for arg in sys.argv[1:]:
		if arg.startswith("--preview="):
			preview(sheet, table, arg.split("=", 1)[1])
	print("wrote", SHEET, sheet.size, TABLE, PALETTE, TILESET)


if __name__ == "__main__":
	main()
