"""Packs the dungeon kit's art (docs/godot/DUNGEONS.md "Art").

Sources: asset/Originals/dungeon-kit/generated/ (Magnific GPT 2.5, transparent background, the Lili
sheet as style reference, 2026-10-17). Each source holds its frames side by side (or in a 2 x 2
grid); every frame is cut along the transparent gaps, trimmed, scaled to the art density of 2 px per
game unit and set into equal cells, standing on the cell's bottom middle (things in a wall or on the
floor) or centred (icons, top-down floor pieces). Writes:

- godot/asset/MAPS/objects/dungeon/door-2x1.webp: the dungeon door, shut and open (the doorway cut
  see-through),
  its doorway DOORWAY_UNITS wide (about the two-tile gap), squashed to DOOR_SQUASH of its height;
- boss-door-2x1.webp: the great door, shut and open, its doorway BOSS_DOORWAY_UNITS wide;
- padlock-2x1.webp (locked, open), bolt-2x1.webp (shut, slid), winch-2x1.webp (crank up, down);
- shutter.webp: the stone block, SHUTTER_UNITS wide;
- drawbridge-down.webp (top-down planks, DRAWBRIDGE_UNITS wide; the script stretches it to its
  length) and drawbridge-up.webp (the raised bridge, as wide);
- slab-2x1.webp: the loose slab, whole and cracked, 64 units a cell;
- spikes.webp: the spike pit tile, two cells square, made seamless (its soft generated border cut
  away, the edges cross-faded);
- glow-moss.webp: the shadow path's moss patch;
- big-chest-2x1.webp: the big chest, shut and open;
- pickups-2x2.webp: the energy flower in bloom and in bud, the goo heart, the coins;
- godot/asset/UI/items/dungeon-items.webp: the small key, the big key, the map, the compass (2 x 2).

    python scripts/art/pack-dungeon-art.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/dungeon-kit/generated"
OUT = ROOT / "godot/asset/MAPS/objects/dungeon"
UI_OUT = ROOT / "godot/asset/UI/items"
ALPHA_CUT = 40
PX = 2  # px per game unit

DOORWAY_UNITS = 120
BOSS_DOORWAY_UNITS = 136
## The doors are squashed to this share of their height.
DOOR_SQUASH = 0.85
SHUTTER_UNITS = 136
DRAWBRIDGE_UNITS = 128
PADLOCK_UNITS = 34
BOLT_UNITS = 64
WINCH_UNITS = 104
SLAB_UNITS = 64
SPIKES_UNITS = 128
MOSS_UNITS = 80
BIG_CHEST_UNITS = 104
PICKUP_CELL = 128
ICON_CELL = 128


def load(name: str) -> Image.Image:
	return Image.open(SRC / name).convert("RGBA")


def save(image: Image.Image, path: Path) -> None:
	path.parent.mkdir(parents=True, exist_ok=True)
	image.save(path, "WEBP", lossless=True)
	print(f"{path.relative_to(ROOT)}  {image.width} x {image.height}")


def solid(image: Image.Image) -> np.ndarray:
	return np.array(image.getchannel("A")) > ALPHA_CUT


def runs(mask: np.ndarray, min_gap: int = 6) -> list[tuple[int, int]]:
	"""Spans of True in a 1-D mask, joining gaps narrower than `min_gap`."""
	out: list[tuple[int, int]] = []
	start = None
	gap = 0
	for i, on in enumerate(mask):
		if on:
			if start is None:
				start = i
			gap = 0
		elif start is not None:
			gap += 1
			if gap >= min_gap:
				out.append((start, i - gap + 1))
				start = None
				gap = 0
	if start is not None:
		out.append((start, len(mask)))
	return out


def panels_in_row(image: Image.Image, count: int) -> list[Image.Image]:
	"""The `count` largest pieces across the image (left to right), each trimmed."""
	cols = solid(image).any(axis=0)
	spans = sorted(runs(cols, 10), key=lambda s: s[1] - s[0], reverse=True)[:count]
	spans.sort()
	out = []
	for x0, x1 in spans:
		piece = image.crop((x0, 0, x1, image.height))
		out.append(piece.crop(piece.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0).getbbox()))
	return out


def split_near(occupied: np.ndarray, middle: int) -> int:
	"""The empty line (no solid pixel) nearest `middle`, so a piece that runs past the middle of the
	grid (the energy flower's stem does) stays whole and out of its neighbour's cell; `middle` when
	no line within a quarter of the image is empty."""
	for d in range(len(occupied) // 4):
		for line in (middle + d, middle - d):
			if not occupied[line]:
				return line
	return middle


def grid_cells(image: Image.Image) -> list[Image.Image]:
	"""A 2 x 2 grid's pieces (row by row), each trimmed, split at the empty lines nearest the middle."""
	mask = solid(image)
	half_w, half_h = image.width // 2, image.height // 2
	split_y = [split_near(mask[:, :half_w].any(axis=1), half_h), split_near(mask[:, half_w:].any(axis=1), half_h)]
	split_x = [split_near(mask[:half_h].any(axis=0), half_w), split_near(mask[half_h:].any(axis=0), half_w)]
	out = []
	for row in range(2):
		for col in range(2):
			x0, x1 = (0, split_x[row]) if col == 0 else (split_x[row], image.width)
			y0, y1 = (0, split_y[col]) if row == 0 else (split_y[col], image.height)
			piece = image.crop((x0, y0, x1, y1))
			out.append(piece.crop(piece.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0).getbbox()))
	return out


def scaled(image: Image.Image, factor: float) -> Image.Image:
	return image.resize((max(1, round(image.width * factor)), max(1, round(image.height * factor))), Image.LANCZOS)


def strip(frames: list[Image.Image], anchor: str = "bottom") -> Image.Image:
	"""Frames in equal cells side by side, standing on the bottom middle or centred."""
	w = max(f.width for f in frames)
	h = max(f.height for f in frames)
	w += w % 2
	h += h % 2
	sheet = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
	for i, f in enumerate(frames):
		x = i * w + (w - f.width) // 2
		y = h - f.height if anchor == "bottom" else (h - f.height) // 2
		sheet.alpha_composite(f, (x, y))
	return sheet


def grid(frames: list[Image.Image], cell: int) -> Image.Image:
	sheet = Image.new("RGBA", (cell * 2, cell * 2), (0, 0, 0, 0))
	for i, f in enumerate(frames):
		fit = min((cell - 8) / f.width, (cell - 8) / f.height)
		f = scaled(f, fit)
		x = (i % 2) * cell + (cell - f.width) // 2
		y = (i // 2) * cell + (cell - f.height) // 2
		sheet.alpha_composite(f, (x, y))
	return sheet


def doorway_span(panel: Image.Image) -> int:
	"""The width (px) of an open door's dark doorway: the median of the longest dark run across rows
	at 60 to 80 % of its height."""
	rows = np.array(panel.convert("RGBA"))
	found = []
	for at in (0.6, 0.65, 0.7, 0.75, 0.8):
		row = rows[int(panel.height * at)]
		dark = (row[:, 3] > ALPHA_CUT) & (row[:, :3].max(axis=1) < 60)
		found.append(max((s[1] - s[0] for s in runs(dark, 4)), default=panel.width // 2))
	return int(np.median(found))


def flood(mask: np.ndarray, seed: tuple[int, int]) -> np.ndarray:
	"""The True region of `mask` connected (4-way) to `seed` (x, y)."""
	region = np.zeros_like(mask)
	x, y = seed
	if not mask[y, x]:
		return region
	region[y, x] = True
	while True:
		grown = region.copy()
		grown[1:, :] |= region[:-1, :]
		grown[:-1, :] |= region[1:, :]
		grown[:, 1:] |= region[:, :-1]
		grown[:, :-1] |= region[:, 1:]
		grown &= mask
		if (grown == region).all():
			return region
		region = grown


def cut_doorway(panel: Image.Image) -> Image.Image:
	"""The open door's dark doorway made see-through (flood-filled from its middle over the dark
	pixels, feathered), so the floor through the wall and the slime walking through show."""
	rgba = np.array(panel)
	dark = (rgba[:, :, 3] > ALPHA_CUT) & (rgba[:, :, :3].max(axis=2) < 48)
	# Only between the posts: the dark run across the middle row, a little inside it.
	row = dark[int(panel.height * 0.55)]
	spans = [s for s in runs(row, 4) if s[0] <= panel.width // 2 < s[1]]
	if spans:
		x0, x1 = spans[0]
		keep = np.zeros_like(dark)
		keep[:, x0 + 4:x1 - 4] = True
		dark &= keep
	hole = flood(dark, (panel.width // 2, int(panel.height * 0.55)))
	if not hole.any():
		return panel
	soft = Image.fromarray((hole * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(1.0))
	alpha = rgba[:, :, 3].astype(np.float32) * (1.0 - np.array(soft).astype(np.float32) / 255.0)
	rgba[:, :, 3] = np.clip(alpha, 0, 255).astype(np.uint8)
	return Image.fromarray(rgba, "RGBA")


def door_sheet(name: str, doorway_units: int, out_name: str) -> None:
	"""A door's shut and open frames, scaled so the doorway is `doorway_units` wide and squashed to
	DOOR_SQUASH of its height (the generated arches are tall for a wall of two or three levels)."""
	shut, open_ = panels_in_row(load(name), 2)
	doorway = doorway_span(open_)
	factor = doorway_units * PX / doorway
	frames = [f.resize((round(f.width * factor), round(f.height * factor * DOOR_SQUASH)), Image.LANCZOS)
		for f in (shut, cut_doorway(open_))]
	sheet = strip(frames, "bottom")
	save(sheet, OUT / out_name)
	print(f"  doorway {doorway} px -> {doorway_units} units; cell {sheet.width // 2} x {sheet.height} px "
		f"({sheet.width // 4} x {sheet.height // 2} units)")


def by_width(name: str, units: int, out_name: str, count: int = 2, anchor: str = "bottom") -> None:
	frames = panels_in_row(load(name), count)
	factor = units * PX / max(f.width for f in frames)
	sheet = strip([scaled(f, factor) for f in frames], anchor)
	save(sheet, OUT / out_name)
	print(f"  cell {sheet.width // count} x {sheet.height} px")


def single(name: str, units: int, out_name: str) -> None:
	image = load(name)
	image = image.crop(image.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0).getbbox())
	image = scaled(image, units * PX / image.width)
	save(image, OUT / out_name)


def square_tiles(name: str, units: int, out_name: str) -> None:
	frames = panels_in_row(load(name), 2)
	side = units * PX
	sheet = Image.new("RGBA", (side * 2, side), (0, 0, 0, 0))
	for i, f in enumerate(frames):
		sheet.alpha_composite(f.resize((side, side), Image.LANCZOS), (i * side, 0))
	save(sheet, OUT / out_name)


def seamless_tile(name: str, units: int, out_name: str) -> None:
	"""The middle of a generated tile (its soft border cut away), alpha forced opaque, made to repeat:
	near each edge it fades into the same tile rolled by half (whose wrap is seamless), first across,
	then down."""
	image = load(name)
	w, h = image.size
	inset = int(min(w, h) * 0.12)
	tile = np.array(image.crop((inset, inset, w - inset, h - inset)).convert("RGB")).astype(np.float32)
	for axis in (1, 0):
		size = tile.shape[axis]
		band = size * 0.16
		edge = np.minimum(np.arange(size), size - 1 - np.arange(size)).astype(np.float32)
		weight = np.clip(edge / band, 0.0, 1.0)
		weight = weight * weight * (3.0 - 2.0 * weight)
		shape = [1, 1, 1]
		shape[axis] = size
		weight = weight.reshape(shape)
		rolled = np.roll(tile, size // 2, axis=axis)
		tile = tile * weight + rolled * (1.0 - weight)
	out = Image.fromarray(np.clip(tile, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
	side = units * PX
	save(out.resize((side, side), Image.LANCZOS), OUT / out_name)


def main() -> None:
	door_sheet("door.png", DOORWAY_UNITS, "door-2x1.webp")
	door_sheet("boss-door.png", BOSS_DOORWAY_UNITS, "boss-door-2x1.webp")
	by_width("padlock.png", PADLOCK_UNITS, "padlock-2x1.webp", anchor="centre")
	by_width("bolt.png", BOLT_UNITS, "bolt-2x1.webp", anchor="centre")
	by_width("winch.png", WINCH_UNITS, "winch-2x1.webp")
	by_width("big-chest-b.png", BIG_CHEST_UNITS, "big-chest-2x1.webp")
	single("shutter.png", SHUTTER_UNITS, "shutter.webp")
	single("drawbridge-down.png", DRAWBRIDGE_UNITS, "drawbridge-down.webp")
	single("drawbridge-up.png", DRAWBRIDGE_UNITS, "drawbridge-up.webp")
	single("glow-moss.png", MOSS_UNITS, "glow-moss.webp")
	square_tiles("slab.png", SLAB_UNITS, "slab-2x1.webp")
	seamless_tile("spikes-b.png", SPIKES_UNITS, "spikes.webp")
	save(grid(grid_cells(load("pickups.png")), PICKUP_CELL), OUT / "pickups-2x2.webp")
	save(grid(grid_cells(load("items.png")), ICON_CELL), UI_OUT / "dungeon-items.webp")


if __name__ == "__main__":
	main()
