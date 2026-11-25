"""Packs the dungeon mechanisms' art (docs/godot/DUNGEONS.md "Mechanisms: the knock target, the ram,
the runaway cart"; the rework plan docs/design/2026-11-23-dungeons-2-3-rework.md, step 1).

Sources: asset/Originals/dungeon-kit/mechanisms/ (Magnific GPT 2.5, `gpt-2-mini`, transparent
background, the Lili creation as the style reference; prompts in its README.md), six 1024 px sheets,
each a 2 x 2 grid of pictures:

- `knock-target-a.png`: the whole target (a guide, not packed), the disc face on, its straw back,
  the post with its pivot bracket;
- `ram-a.png`: the iron-capped log, the timber gantry from the front, the ratchet cog, the pawl;
- `bricked-arch-a.png`: the brick panel, the same half knocked down, eight loose bricks, a heap of
  rubble;
- `ram-cart-a.png`: the loaded cart from the side and from the front, one wheel, six loose pieces of
  ore;
- `rail-gate-a.png`: the gate shut, the gate smashed, five broken planks and two chain links, the
  brake lever and its chock (`rail-gate-a-hazy.png` is the generation as it came, with a haze left in
  its background; `rail-gate-a.png` is that picture after Magnific's background removal);
- `rail-buffer-a.png`: the rails' buffer stop from the front and from the side, the pulley post
  that hauls a cart back, its counterweight.

Every picture is cut from its quarter by its alpha, trimmed and scaled to its size in the game at
2 px per game unit (the art density: 128 px per 64-unit cell), then saved in
godot/asset/MAPS/objects/mechanisms/ (drawn at 0.5 by the scenes in
godot/game/scenes/objects/dungeon/ and godot/game/scenes/objects/crystal-mine/). Pieces that turn
or spin are centred in their cell on the point they turn about (the target's disc, the cog, the
wheel, each brick, plank and ore piece). `mechanisms.json` beside the sheets holds what the scripts
need to place them (sizes and anchors in game units).

    python scripts/art/pack-mechanism-art.py [--preview <dir>]

`--preview` also writes each packed sheet on a flat background into <dir>, to look at.
Needs Pillow and numpy.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

SOURCES = REPO / "asset" / "Originals" / "dungeon-kit" / "mechanisms"
OUT = REPO / "godot" / "asset" / "MAPS" / "objects" / "mechanisms"
ALPHA_CUT = 40
## Pixels per game unit.
DENSITY = 2

## The knock target: the disc's iron rim across (game units), the post's height.
DISC_UNITS = 56
DISC_CELL = 160
POST_UNITS_TALL = 46
## The ram: the log's length, the gantry's width from the front, the cog's width.
LOG_UNITS = 160
## The gantry from the front: a post's width with its stone foot, and the gap between the posts
## (the log on end is about 60 wide).
GANTRY_POST_UNITS = 42
GANTRY_GAP_UNITS = 78
COG_UNITS = 40
PAWL_UNITS = 34
## The bricked arch: the panel fills a north doorway's leaf (interior-walls.json `n_shutter`:
## 141 x 132 px); a loose brick's cell; the rubble's width.
PANEL_PX = (141, 132)
BRICK_CELL = 56
BRICK_SCALE = 0.3
RUBBLE_UNITS = 66
## The cart: the side view's width with its wheels, a wheel across, an ore piece's cell.
CART_UNITS = 84
## The side view's two wheels in the source sheet: their middles and their radius (px), measured on
## the picture (the cart's body covers their tops, so the alpha does not give them).
WHEELS_PX = ((208, 483), (412, 483))
WHEEL_RADIUS_PX = 90
WHEEL_CELL = 72
ORE_CELL = 48
ORE_SCALE = 0.26
## The rail gate: its width, a plank's cell, the lever's height, the chock's width.
GATE_UNITS = 116
PLANK_CELL = 112
PLANK_SCALE = 0.34
LEVER_UNITS_TALL = 46
CHOCK_UNITS = 22
## The line's end and its way back: the buffer stop's width from the front, the pulley post's and
## the counterweight's heights.
BUFFER_UNITS = 96
PULLEY_UNITS_TALL = 60
WEIGHT_UNITS_TALL = 46


def quarters(sheet: Image.Image) -> dict[tuple[int, int], Image.Image]:
	"""The sheet's four pictures, by (column, row): every separate piece of the sheet (by its alpha)
	goes to the quarter its middle lies in, so a picture that reaches past the sheet's middle line is
	kept whole and leaves nothing in its neighbour."""
	pixels = np.asarray(sheet)
	labels, boxes = labelled(sheet, 40)
	out = {}
	for column in (0, 1):
		for row in (0, 1):
			keep = np.zeros(labels.shape, dtype=bool)
			for label, left, top, right, bottom in boxes:
				if int((left + right) / 2 >= sheet.width / 2) == column and int((top + bottom) / 2 >= sheet.height / 2) == row:
					keep |= labels == label
			part = pixels.copy()
			part[~keep] = 0
			out[(column, row)] = Image.fromarray(part, "RGBA")
	return out


def mask_of(image: Image.Image) -> np.ndarray:
	return np.asarray(image)[..., 3] > ALPHA_CUT


def trimmed(image: Image.Image) -> Image.Image:
	ys, xs = np.nonzero(mask_of(image))
	if xs.size == 0:
		raise SystemExit("an empty picture")
	return image.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


def labelled(image: Image.Image, min_area: int) -> tuple[np.ndarray, list[tuple[int, int, int, int, int]]]:
	"""The picture's separate pieces (4-connected, by alpha): the label of every pixel and, for each
	piece of `min_area` px or more, (label, left, top, right, bottom)."""
	mask = mask_of(image)
	labels = np.zeros(mask.shape, dtype=np.int32)
	height, width = mask.shape
	boxes = []
	count = 0
	for y0, x0 in zip(*np.nonzero(mask)):
		if labels[y0, x0]:
			continue
		count += 1
		stack = [(int(y0), int(x0))]
		labels[y0, x0] = count
		top = bottom = int(y0)
		left = right = int(x0)
		area = 0
		while stack:
			y, x = stack.pop()
			area += 1
			top, bottom, left, right = min(top, y), max(bottom, y), min(left, x), max(right, x)
			for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
				if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not labels[ny, nx]:
					labels[ny, nx] = count
					stack.append((ny, nx))
		if area >= min_area:
			boxes.append((count, left, top, right + 1, bottom + 1))
	return labels, boxes


def components(image: Image.Image, min_area: int = 400) -> list[Image.Image]:
	"""The picture's separate pieces in reading order, each trimmed, with every other piece's pixels
	cleared from its box."""
	labels, boxes = labelled(image, min_area)
	# reading order: rows of pieces by their middle, then left to right
	boxes.sort(key=lambda b: (round(((b[2] + b[4]) / 2) / 110), b[1]))
	pieces = []
	pixels = np.asarray(image)
	for label, left, top, right, bottom in boxes:
		part = pixels[top:bottom, left:right].copy()
		part[labels[top:bottom, left:right] != label] = 0
		pieces.append(Image.fromarray(part, "RGBA"))
	return pieces


def scaled(image: Image.Image, scale: float) -> Image.Image:
	return image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.LANCZOS)


def to_width(image: Image.Image, units: float) -> Image.Image:
	return scaled(image, units * DENSITY / image.width)


def to_height(image: Image.Image, units: float) -> Image.Image:
	return scaled(image, units * DENSITY / image.height)


def strip(cells: list[Image.Image], cell: tuple[int, int], anchors: list[tuple[float, float]] | None = None) -> Image.Image:
	"""`cells` side by side in cells of `cell` px: each centred, or with its `anchors` point (px in
	the picture) on the cell's middle."""
	sheet = Image.new("RGBA", (cell[0] * len(cells), cell[1]), (0, 0, 0, 0))
	for i, picture in enumerate(cells):
		if anchors is None:
			at = ((cell[0] - picture.width) // 2, (cell[1] - picture.height) // 2)
		else:
			at = (round(cell[0] / 2 - anchors[i][0]), round(cell[1] / 2 - anchors[i][1]))
		sheet.alpha_composite(picture, (i * cell[0] + at[0], at[1]))
	return sheet


def save(image: Image.Image, name: str, preview: Path | None) -> None:
	OUT.mkdir(parents=True, exist_ok=True)
	path = OUT / (name + ".webp")
	print(f"{path.name}: {image.width} x {image.height} px ({image.width / DENSITY:g} x {image.height / DENSITY:g} units)",
		save_game_webp(image, path))
	if preview is not None:
		preview.mkdir(parents=True, exist_ok=True)
		back = Image.new("RGBA", image.size, (70, 90, 120, 255))
		back.alpha_composite(image)
		back.convert("RGB").save(preview / (name + ".png"))


def disc_circle(picture: Image.Image) -> tuple[float, float, float]:
	"""The round disc in a trimmed picture whose only other part is the hook on its top: its centre
	(x, y) and radius, from its widest row (its diameter) and its bottom."""
	mask = mask_of(picture)
	widths = mask.sum(axis=1)
	radius = float(widths.max()) / 2.0
	xs = np.nonzero(mask[int(np.argmax(widths))])[0]
	centre_x = (float(xs.min()) + float(xs.max()) + 1.0) / 2.0
	return centre_x, float(picture.height) - radius, radius


def pack_knock_target(data: dict, preview: Path | None) -> None:
	parts = quarters(Image.open(SOURCES / "knock-target-a.png").convert("RGBA"))
	front = trimmed(parts[(1, 0)])
	back = trimmed(parts[(0, 1)])
	cells = []
	anchors = []
	for picture, across in ((front, DISC_UNITS), (back, DISC_UNITS + 6)):
		centre_x, centre_y, radius = disc_circle(picture)
		scale = across * DENSITY / (radius * 2.0)
		cells.append(scaled(picture, scale))
		anchors.append((centre_x * scale, centre_y * scale))
	save(strip(cells, (DISC_CELL, DISC_CELL), anchors), "knock-target-disc-2x1", preview)
	post = to_height(trimmed(parts[(1, 1)]), POST_UNITS_TALL)
	save(post, "knock-target-post", preview)
	data["knockTarget"] = {"discUnits": DISC_UNITS, "discCellPx": DISC_CELL,
		"postUnits": [post.width / DENSITY, post.height / DENSITY]}


def pack_ram(data: dict, preview: Path | None) -> None:
	parts = quarters(Image.open(SOURCES / "ram-a.png").convert("RGBA"))
	log = to_width(trimmed(parts[(0, 0)]), LOG_UNITS)
	save(log, "ram-log", preview)
	# The log without its rings (the rows over its body), for the lanes that run up and down the
	# screen: turned on end, the rings would stick out of its side.
	mask = mask_of(log)
	widths = mask.sum(axis=1)
	body_top = int(np.argmax(widths > log.width * 0.8))
	plain = log.crop((0, body_top, log.width, log.height))
	north = plain.transpose(Image.ROTATE_90)
	south = plain.transpose(Image.ROTATE_270).transpose(Image.FLIP_LEFT_RIGHT)
	save(north, "ram-log-north", preview)
	save(south, "ram-log-south", preview)
	# The gantry: its posts are too close for the log, so the crossbeam's middle is drawn out until
	# the gap is GANTRY_GAP_UNITS wide.
	raw = trimmed(parts[(1, 0)])
	left, right = gap_columns(raw)
	scale = GANTRY_POST_UNITS * DENSITY / (left + 1)
	west = scaled(raw.crop((0, 0, left + 1, raw.height)), scale)
	east = scaled(raw.crop((right, 0, raw.width, raw.height)), scale)
	slice_from = (left + right) // 2 - 20
	span = raw.crop((slice_from, 0, slice_from + 40, raw.height))
	span = span.resize((GANTRY_GAP_UNITS * DENSITY, west.height), Image.LANCZOS)
	gantry = Image.new("RGBA", (west.width + span.width + east.width, west.height), (0, 0, 0, 0))
	gantry.alpha_composite(span, (west.width, 0))
	gantry.alpha_composite(west, (0, 0))
	gantry.alpha_composite(east, (west.width + span.width, 0))
	save(gantry, "ram-gantry-front", preview)
	cog = to_width(trimmed(parts[(0, 1)]), COG_UNITS)
	size = max(cog.size) + 8
	save(strip([cog], (size, size)), "ram-cog", preview)
	pawl = to_width(trimmed(parts[(1, 1)]), PAWL_UNITS)
	save(pawl, "ram-pawl", preview)
	data["ram"] = {
		"logUnits": [log.width / DENSITY, log.height / DENSITY],
		"logRingsUnits": body_top / DENSITY,
		"logOnEndUnits": [north.width / DENSITY, north.height / DENSITY],
		"gantryUnits": [gantry.width / DENSITY, gantry.height / DENSITY],
		"gantryGapUnits": [west.width / DENSITY, (west.width + span.width) / DENSITY],
		"cogCellPx": size,
	}


def pack_bricked_arch(data: dict, preview: Path | None) -> None:
	parts = quarters(Image.open(SOURCES / "bricked-arch-a.png").convert("RGBA"))
	whole = trimmed(parts[(0, 0)])
	# the half knocked down: its standing wall alone (the biggest piece; its loose bricks fly as
	# pieces of their own in the game)
	half_pieces = components(parts[(1, 0)])
	half = max(half_pieces, key=lambda p: p.width * p.height)
	scale = (PANEL_PX[0] / whole.width, PANEL_PX[1] / whole.height)
	panel = whole.resize(PANEL_PX, Image.LANCZOS)
	fallen = half.resize((max(1, round(half.width * scale[0])), max(1, round(half.height * scale[1]))), Image.LANCZOS)
	frames = Image.new("RGBA", (PANEL_PX[0] * 2, PANEL_PX[1]), (0, 0, 0, 0))
	frames.alpha_composite(panel, (0, 0))
	frames.alpha_composite(fallen, (PANEL_PX[0], PANEL_PX[1] - fallen.height))
	save(frames, "bricked-arch-2x1", preview)
	bricks = [scaled(piece, BRICK_SCALE) for piece in components(parts[(0, 1)])]
	save(strip(bricks, (BRICK_CELL, BRICK_CELL)), "bricked-arch-bricks-%dx1" % len(bricks), preview)
	rubble = to_width(trimmed(parts[(1, 1)]), RUBBLE_UNITS)
	save(rubble, "bricked-arch-rubble", preview)
	data["brickedArch"] = {"panelPx": list(PANEL_PX), "bricks": len(bricks), "brickCellPx": BRICK_CELL,
		"rubbleUnits": [rubble.width / DENSITY, rubble.height / DENSITY]}


def gap_columns(gantry: Image.Image) -> tuple[int, int]:
	"""The gantry's gap: the last column of its left post and the first of its right one (the columns
	between them hold the crossbeam and the braces' ends only)."""
	columns = mask_of(gantry).sum(axis=0)
	thin = columns < columns.max() * 0.45
	middle = gantry.width // 2
	left = middle
	while left > 0 and thin[left]:
		left -= 1
	right = middle
	while right < gantry.width - 1 and thin[right]:
		right += 1
	return left, right


def pack_ram_cart(data: dict, preview: Path | None) -> None:
	parts = quarters(Image.open(SOURCES / "ram-cart-a.png").convert("RGBA"))
	box = Image.fromarray(mask_of(parts[(0, 0)])).getbbox()
	raw_side = parts[(0, 0)].crop(box)
	scale = CART_UNITS * DENSITY / raw_side.width
	side = scaled(raw_side, scale)
	front = scaled(trimmed(parts[(1, 0)]), scale)
	save(side, "ram-cart-side", preview)
	save(front, "ram-cart-front", preview)
	wheels = [((x - box[0]) * scale, (y - box[1]) * scale, WHEEL_RADIUS_PX * scale) for x, y in WHEELS_PX]
	radius = sum(w[2] for w in wheels) / len(wheels)
	wheel = trimmed(parts[(0, 1)])
	wheel = scaled(wheel, radius * 2.0 / wheel.width)
	save(strip([wheel], (WHEEL_CELL, WHEEL_CELL)), "ram-cart-wheel", preview)
	ore = [scaled(piece, ORE_SCALE) for piece in components(parts[(1, 1)])]
	save(strip(ore, (ORE_CELL, ORE_CELL)), "ram-cart-ore-%dx1" % len(ore), preview)
	data["ramCart"] = {
		"sideUnits": [side.width / DENSITY, side.height / DENSITY],
		"frontUnits": [front.width / DENSITY, front.height / DENSITY],
		# each wheel's centre from the side view's bottom middle, and its radius (game units)
		"wheels": [[round((x - side.width / 2.0) / DENSITY, 2), round((y - side.height) / DENSITY, 2)] for x, y, _ in wheels],
		"wheelRadiusUnits": round(radius / DENSITY, 2),
		"wheelCellPx": WHEEL_CELL,
		"ore": len(ore), "oreCellPx": ORE_CELL,
	}


def pack_rail_gate(data: dict, preview: Path | None) -> None:
	parts = quarters(Image.open(SOURCES / "rail-gate-a.png").convert("RGBA"))
	shut = trimmed(parts[(0, 0)])
	smashed = trimmed(parts[(1, 0)])
	scale = GATE_UNITS * DENSITY / shut.width
	shut = scaled(shut, scale)
	smashed = scaled(smashed, GATE_UNITS * DENSITY / smashed.width)
	cell = (GATE_UNITS * DENSITY, max(shut.height, smashed.height))
	frames = Image.new("RGBA", (cell[0] * 2, cell[1]), (0, 0, 0, 0))
	frames.alpha_composite(shut, (0, cell[1] - shut.height))
	frames.alpha_composite(smashed, (cell[0], cell[1] - smashed.height))
	save(frames, "rail-gate-2x1", preview)
	planks = [scaled(piece, PLANK_SCALE) for piece in components(parts[(0, 1)])]
	save(strip(planks, (PLANK_CELL, PLANK_CELL)), "rail-gate-planks-%dx1" % len(planks), preview)
	brake = components(parts[(1, 1)])
	lever = to_height(brake[0], LEVER_UNITS_TALL)
	chock = to_width(brake[1], CHOCK_UNITS)
	save(lever, "ram-cart-brake-lever", preview)
	save(chock, "ram-cart-chock", preview)
	data["railGate"] = {"cellPx": list(cell), "units": [cell[0] / DENSITY, cell[1] / DENSITY],
		"planks": len(planks), "plankCellPx": PLANK_CELL}
	data["ramCart"]["leverUnits"] = [lever.width / DENSITY, lever.height / DENSITY]
	data["ramCart"]["chockUnits"] = [chock.width / DENSITY, chock.height / DENSITY]


def pack_rail_buffer(data: dict, preview: Path | None) -> None:
	parts = quarters(Image.open(SOURCES / "rail-buffer-a.png").convert("RGBA"))
	front = to_width(trimmed(parts[(0, 0)]), BUFFER_UNITS)
	side = scaled(trimmed(parts[(1, 0)]), front.height / trimmed(parts[(1, 0)]).height)
	save(front, "rail-buffer-front", preview)
	save(side, "rail-buffer-side", preview)
	pulley = to_height(max(components(parts[(0, 1)]), key=lambda piece: piece.width * piece.height), PULLEY_UNITS_TALL)
	save(pulley, "ram-cart-pulley", preview)
	weight = to_height(trimmed(parts[(1, 1)]), WEIGHT_UNITS_TALL)
	save(weight, "ram-cart-counterweight", preview)
	data["ramCart"]["bufferFrontUnits"] = [front.width / DENSITY, front.height / DENSITY]
	data["ramCart"]["bufferSideUnits"] = [side.width / DENSITY, side.height / DENSITY]
	data["ramCart"]["pulleyUnits"] = [pulley.width / DENSITY, pulley.height / DENSITY]
	data["ramCart"]["counterweightUnits"] = [weight.width / DENSITY, weight.height / DENSITY]


def main() -> None:
	preview = None
	if "--preview" in sys.argv[1:]:
		preview = Path(sys.argv[sys.argv.index("--preview") + 1])
	data: dict = {}
	pack_knock_target(data, preview)
	pack_ram(data, preview)
	pack_bricked_arch(data, preview)
	pack_ram_cart(data, preview)
	pack_rail_gate(data, preview)
	pack_rail_buffer(data, preview)
	(OUT / "mechanisms.json").write_text(json.dumps(data, indent="\t") + "\n", encoding="utf-8")
	print(json.dumps(data, indent=1))


if __name__ == "__main__":
	main()
