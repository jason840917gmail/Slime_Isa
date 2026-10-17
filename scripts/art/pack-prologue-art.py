"""Packs the prologue's art (docs/design/2026-10-16-prologue.md; docs/godot/PROLOGUE.md).

Sources: asset/Originals/prologue/generated/ (Magnific GPT 2.5, transparent background, the Lili
sheet as style reference, 2026-10-16). Writes, at the art density of 2 px per game unit unless noted:

- godot/asset/MAPS/landmarks/wellspring-pool.webp: the Wellspring's pool of glowing goo (pool-a),
  WELLSPRING_UNITS wide;
- godot/asset/MAPS/objects/barred-gate/frame.webp and grate.webp: the old Thorn Guard gate (gate-a)
  cut in two, the stone posts and the beam (`frame`, the grate's place left empty) and the iron
  grate between them (`grate`), which rises into the beam when the gate opens; its opening is
  GATE_OPENING_UNITS wide;
- godot/asset/MAPS/objects/barred-gate/lever-2x1.webp: the lever behind the bars, up (shut) and
  pulled (open) (lever-a), in cells of LEVER_CELL px;
- godot/asset/characters/authored/npcs/yoi.webp: Old Veteran Yoi's three poses (yoi-a standing,
  thrust-b the thrust with his jelly spear, hurt-a wounded), in a row of YOI_CELL cells at 3 px per
  unit (the NPC sheets' density), every pose at one scale, its feet on the cell's bottom and its body
  centred on YOI_BODY_X;
- godot/asset/UI/items/plops-satchel.webp: Plop's satchel, the bag he gives (128 x 128).

It prints the placement numbers the scenes use (game/scenes/objects/barred-gate.tscn,
game/scenes/characters/yoi.tscn, the Wellspring's water cells in west-village-b4).

    python scripts/art/pack-prologue-art.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/prologue/generated"
ALPHA_CUT = 40

WELLSPRING_UNITS = 360
GATE_OPENING_UNITS = 128
# gate-a: the grate between the posts and under the beam (source px), found from the alpha profile.
GATE_GRATE = (248, 266, 772, 668)
LEVER_CELL = (96, 96)
LEVER_UNITS_WIDE = 40
YOI_CELL = (400, 240)
YOI_BODY_X = 104
YOI_BODY_UNITS_TALL = 76
YOI_PX_PER_UNIT = 3


def load(name: str) -> Image.Image:
	return Image.open(SRC / name).convert("RGBA")


def alpha_box(image: Image.Image) -> tuple[int, int, int, int]:
	return image.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0).getbbox()


def scaled(image: Image.Image, factor: float) -> Image.Image:
	return image.resize((max(1, round(image.width * factor)), max(1, round(image.height * factor))), Image.LANCZOS)


def save(image: Image.Image, path: Path) -> None:
	path.parent.mkdir(parents=True, exist_ok=True)
	image.save(path, "WEBP", lossless=True)
	print(f"{path.relative_to(ROOT)}  {image.width} x {image.height}")


def body_centre_x(image: Image.Image, max_x: int) -> float:
	"""The alpha centroid of the lower half of the picture, left of `max_x` (the body, not a spear)."""
	alpha = image.getchannel("A").load()
	total = 0.0
	weight = 0.0
	for y in range(image.height // 2, image.height, 2):
		for x in range(0, min(max_x, image.width), 2):
			a = alpha[x, y]
			if a > ALPHA_CUT:
				total += x * a
				weight += a
	return total / weight if weight > 0 else image.width / 2


def pack_pool() -> None:
	pool = load("pool-a.png")
	pool = pool.crop(alpha_box(pool))
	factor = WELLSPRING_UNITS * 2 / pool.width
	out = scaled(pool, factor)
	save(out, ROOT / "godot/asset/MAPS/landmarks/wellspring-pool.webp")
	print(f"  pool: {out.width / 2:.0f} x {out.height / 2:.0f} units")


def pack_gate() -> None:
	gate = load("gate-a.png")
	box = alpha_box(gate)
	factor = GATE_OPENING_UNITS * 2 / (GATE_GRATE[2] - GATE_GRATE[0])
	grate = gate.crop(GATE_GRATE)
	frame = gate.copy()
	frame.paste(Image.new("RGBA", grate.size, (0, 0, 0, 0)), GATE_GRATE[:2])
	frame = frame.crop(box)
	grate_out = scaled(grate, factor)
	frame_out = scaled(frame, factor)
	save(frame_out, ROOT / "godot/asset/MAPS/objects/barred-gate/frame.webp")
	save(grate_out, ROOT / "godot/asset/MAPS/objects/barred-gate/grate.webp")
	# Placement in units, from the gate node at the middle of the opening's foot (the grate's bottom).
	units = factor / 2
	foot = (GATE_GRATE[0] + GATE_GRATE[2]) / 2, GATE_GRATE[3]
	print(f"  frame offset (units, scale 0.5): ({(box[0] - foot[0]) * units:.1f}, {(box[1] - foot[1]) * units:.1f})"
		f" size {frame_out.width / 2:.1f} x {frame_out.height / 2:.1f}")
	print(f"  grate offset (units): ({(GATE_GRATE[0] - foot[0]) * units:.1f}, {(GATE_GRATE[1] - foot[1]) * units:.1f})"
		f" size {grate_out.width / 2:.1f} x {grate_out.height / 2:.1f}")
	print(f"  posts: left {(box[0] - foot[0]) * units:.1f}..{(GATE_GRATE[0] - foot[0]) * units:.1f},"
		f" right {(GATE_GRATE[2] - foot[0]) * units:.1f}..{(box[2] - foot[0]) * units:.1f}")


def pack_lever() -> None:
	lever = load("lever-a.png")
	half = lever.width // 2
	cells = []
	pieces = [lever.crop((0, 0, half, lever.height)), lever.crop((half, 0, lever.width, lever.height))]
	trimmed = [piece.crop(alpha_box(piece)) for piece in pieces]
	factor = LEVER_UNITS_WIDE * 2 / max(piece.width for piece in trimmed)
	for piece in trimmed:
		piece = scaled(piece, factor)
		cell = Image.new("RGBA", LEVER_CELL, (0, 0, 0, 0))
		cell.alpha_composite(piece, ((LEVER_CELL[0] - piece.width) // 2, LEVER_CELL[1] - piece.height))
		cells.append(cell)
	sheet = Image.new("RGBA", (LEVER_CELL[0] * 2, LEVER_CELL[1]), (0, 0, 0, 0))
	for i, cell in enumerate(cells):
		sheet.alpha_composite(cell, (i * LEVER_CELL[0], 0))
	save(sheet, ROOT / "godot/asset/MAPS/objects/barred-gate/lever-2x1.webp")


def pack_yoi() -> None:
	# (source, the x right of which a spear, not the body, lies in the source)
	poses = [("yoi-a.png", 10_000), ("thrust-b.png", 720), ("hurt-a.png", 10_000)]
	idle = load(poses[0][0])
	idle_box = alpha_box(idle)
	factor = YOI_BODY_UNITS_TALL * YOI_PX_PER_UNIT / (idle_box[3] - idle_box[1])
	sheet = Image.new("RGBA", (YOI_CELL[0] * len(poses), YOI_CELL[1]), (0, 0, 0, 0))
	for i, (name, spear_x) in enumerate(poses):
		image = load(name)
		box = alpha_box(image)
		centre = body_centre_x(image, spear_x)
		piece = scaled(image.crop(box), factor)
		x = round(YOI_BODY_X - (centre - box[0]) * factor)
		y = YOI_CELL[1] - piece.height
		cell = Image.new("RGBA", YOI_CELL, (0, 0, 0, 0))
		cell.alpha_composite(piece, (max(0, x), max(0, y)), (max(0, -x), max(0, -y)))
		sheet.alpha_composite(cell, (i * YOI_CELL[0], 0))
		print(f"  {name}: {piece.width} x {piece.height} px, body at x {YOI_BODY_X}")
	save(sheet, ROOT / "godot/asset/characters/authored/npcs/yoi.webp")


def pack_satchel() -> None:
	satchel = load("satchel.png")
	satchel = satchel.crop(alpha_box(satchel))
	satchel.thumbnail((120, 120), Image.LANCZOS)
	cell = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
	cell.alpha_composite(satchel, ((128 - satchel.width) // 2, (128 - satchel.height) // 2))
	save(cell, ROOT / "godot/asset/UI/items/plops-satchel.webp")


def main() -> None:
	pack_pool()
	pack_gate()
	pack_lever()
	pack_yoi()
	pack_satchel()


if __name__ == "__main__":
	main()
