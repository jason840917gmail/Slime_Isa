"""Packs the heavy plate's art (docs/design/2026-10-14-bomb-lantern-and-secrets.md section 4;
docs/godot/BODY_SHAPES.md "Heavy plates and heavy blocks").

Source: asset/Originals/props/heavy-plate/plate-b.png (Magnific GPT 2.5, transparent): three pieces
in a row, the fixed base (a stone socket ring around a dark pit), the cap released (an oval stone
slab with a carved weight glyph) and the cap pressed (the glyph glowing).

The owner's rule (2026-10-14): the base never moves, only the cap slides down as the plate sinks.
So the base is cut in two: `full` (all of it, drawn under the cap) and `front` (the part of the
ring in front of the opening, drawn over the cap, so the sinking cap goes in behind the front
rim). The cap is scaled to fit the opening (its top face as wide as the opening, a hair less).

Runtime density: 2 px per game unit; the base is BASE_WORLD_W units wide.

    python scripts/art/pack-heavy-plate-art.py

Writes godot/asset/MAPS/props/heavy-plate/base-2x1.webp (full, front) and cap-2x1.webp (released,
pressed), and prints the placement numbers game/scripts/heavy_plate.gd uses (ART_* constants).
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/props/heavy-plate/plate-b.png"
OUT = ROOT / "godot/asset/MAPS/props/heavy-plate"
ALPHA_CUT = 40
PX_PER_UNIT = 2.0
BASE_WORLD_W = 84.0
# Measured on the source (px): the opening's ellipse (the ring's inner top edge) and the cap's top
# face ellipse.
OPENING_CENTRE = (270.0, 490.0)
OPENING_HALF = (155.0, 95.0)
CAP_FACE_CENTRE = (780.0, 525.0)
CAP_FACE_HALF = (198.0, 130.0)
CAP_FIT = 0.97


def pieces(image: Image.Image) -> list[tuple[int, int, int, int]]:
	"""The alpha boxes of the pieces, left to right (split at empty columns)."""
	alpha = image.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0)
	width, height = image.size
	columns = [any(alpha.getpixel((x, y)) for y in range(0, height, 2)) for x in range(width)]
	boxes = []
	start = None
	for x, filled in enumerate(columns + [False]):
		if filled and start is None:
			start = x
		elif not filled and start is not None:
			box = alpha.crop((start, 0, x, height)).getbbox()
			boxes.append((start, box[1], x, box[3]))
			start = None
	return boxes


def main() -> None:
	image = Image.open(SRC).convert("RGBA")
	base_box, cap_box, lit_box = pieces(image)[:3]
	src_to_px = BASE_WORLD_W * PX_PER_UNIT / (base_box[2] - base_box[0])
	base = image.crop(base_box)
	# The front: the ring's pixels in front of the opening (below its centre, outside its ellipse).
	front = base.copy()
	cx = OPENING_CENTRE[0] - base_box[0]
	cy = OPENING_CENTRE[1] - base_box[1]
	pixels = front.load()
	for y in range(front.height):
		for x in range(front.width):
			inside = ((x - cx) / OPENING_HALF[0]) ** 2 + ((y - cy) / OPENING_HALF[1]) ** 2 < 1.0
			if y < cy or inside:
				pixels[x, y] = (0, 0, 0, 0)
	cell = (round(base.width * src_to_px), round(base.height * src_to_px))
	sheet = Image.new("RGBA", (cell[0] * 2, cell[1]))
	sheet.paste(base.resize(cell, Image.LANCZOS), (0, 0))
	sheet.paste(front.resize(cell, Image.LANCZOS), (cell[0], 0))
	OUT.mkdir(parents=True, exist_ok=True)
	sheet.save(OUT / "base-2x1.webp", lossless=True)
	# The caps: one box for both (the union), scaled so the top face fits the opening.
	k = OPENING_HALF[0] / CAP_FACE_HALF[0] * CAP_FIT
	cap_w = max(cap_box[2] - cap_box[0], lit_box[2] - lit_box[0])
	cap_top = min(cap_box[1], lit_box[1])
	cap_bottom = max(cap_box[3], lit_box[3])
	cap_cell = (round(cap_w * k * src_to_px), round((cap_bottom - cap_top) * k * src_to_px))
	caps = Image.new("RGBA", (cap_cell[0] * 2, cap_cell[1]))
	for index, box in enumerate((cap_box, lit_box)):
		piece = image.crop((box[0], cap_top, box[0] + cap_w, cap_bottom))
		caps.paste(piece.resize(cap_cell, Image.LANCZOS), (cap_cell[0] * index, 0))
	caps.save(OUT / "cap-2x1.webp", lossless=True)
	# Placement in world units, from the plate's root (the opening's middle).
	unit = src_to_px / PX_PER_UNIT
	base_offset = ((base_box[0] - OPENING_CENTRE[0]) * unit, (base_box[1] - OPENING_CENTRE[1]) * unit)
	cap_offset = ((cap_box[0] - CAP_FACE_CENTRE[0]) * k * unit, (cap_top - CAP_FACE_CENTRE[1]) * k * unit)
	print("base cell", cell, "cap cell", cap_cell)
	print("ART_BASE_OFFSET = Vector2(%.1f, %.1f)" % base_offset)
	print("ART_CAP_OFFSET = Vector2(%.1f, %.1f)" % cap_offset)


if __name__ == "__main__":
	main()
