"""Builds the front layer of the bath tub (docs/godot/specs/interaction.md "Baths"; owner, 2026-11-12).

The bath (godot/game/scenes/objects/bath-tub.tscn) is the wooden water tub of the kitchen sheet. The
slime soaks behind the tub's near wall and waist-deep in its water: the scene draws this picture over
the slime's art during a bath. It is cut from the tub's own tile, so it lines up exactly:

- the near wall: the tub's pixels below the water's middle that are not water, opaque;
- the water in front of the bather: the water's pixels below WATERLINE, at WATER_ALPHA.

    python scripts/art/build-bath-tub.py [--preview=<png>]
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from game_webp import save_game_webp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / "godot/asset/MAPS/interiors/128x128-tile_8x8-interior-kitchen-hearth.webp"
TILE, COLUMNS, FRAME = 128, 8, 41
OUT = ROOT / "godot/asset/MAPS/interiors/bath/bath-tub-front.webp"
## the water covers the bather from this share of its height down (0 its top, 1 its near edge)
WATERLINE = 0.6
WATER_ALPHA = 0.55
WATERLINE_ROWS = 3.0


def water_mask(array: np.ndarray) -> np.ndarray:
	rgb = array[..., :3] / 255.0
	mx, mn = rgb.max(axis=2), rgb.min(axis=2)
	s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
	r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
	d = np.maximum(mx - mn, 1e-6)
	h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
	return (array[..., 3] > 0) & (h > 170) & (h < 250) & (s > 0.15) & (mx > 0.4)


def main() -> None:
	sheet = Image.open(SHEET).convert("RGBA")
	tile = sheet.crop(((FRAME % COLUMNS) * TILE, (FRAME // COLUMNS) * TILE, (FRAME % COLUMNS + 1) * TILE, (FRAME // COLUMNS + 1) * TILE))
	array = np.asarray(tile).copy()
	water = water_mask(array.astype(np.float64))
	ys, xs = np.nonzero(water)
	top, bottom = int(ys.min()), int(ys.max())
	middle = (top + bottom) / 2.0
	line = top + (bottom - top) * WATERLINE
	yy = np.mgrid[0:TILE, 0:TILE][0]
	front = np.zeros_like(array)
	wall = (array[..., 3] > 0) & ~water & (yy > middle)
	# the rim's pixels beside the water, above its near edge, are the tub's far half: only what is
	# below the water's own outline at that column is the near wall
	lowest = np.full(TILE, -1)
	for x in range(TILE):
		column = np.nonzero(water[:, x])[0]
		if len(column):
			lowest[x] = column.max()
	inside = (lowest[None, :] >= 0) & (yy <= lowest[None, :])
	left, right = int(xs.min()), int(xs.max())
	xx = np.mgrid[0:TILE, 0:TILE][1]
	wall &= ~(inside & (xx >= left) & (xx <= right))
	front[wall] = array[wall]
	deep = water & (yy >= line)
	front[deep] = array[deep]
	# the waterline is soft: the water thickens over its first rows
	depth = np.clip((yy - line + 1) / WATERLINE_ROWS, 0, 1)
	front[deep, 3] = (array[deep, 3] * WATER_ALPHA * depth[deep]).astype(np.uint8)
	picture = Image.fromarray(front, "RGBA")
	preview = [arg.split("=", 1)[1] for arg in sys.argv[1:] if arg.startswith("--preview=")]
	if preview:
		shot = Image.new("RGBA", (TILE * 2, TILE), (92, 62, 40, 255))
		shot.alpha_composite(tile, (0, 0))
		shot.alpha_composite(picture, (TILE, 0))
		shot.resize((TILE * 8, TILE * 4), Image.NEAREST).convert("RGB").save(preview[0])
		print("water rows %d..%d, columns %d..%d, waterline %.1f" % (top, bottom, left, right, line))
		return
	OUT.parent.mkdir(parents=True, exist_ok=True)
	save_game_webp(picture, OUT)
	print("written", OUT.relative_to(ROOT), "water rows %d..%d, columns %d..%d, waterline %.1f" % (top, bottom, left, right, line))


if __name__ == "__main__":
	main()
