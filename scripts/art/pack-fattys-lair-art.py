"""Packs Fatty's Lair's art (docs/design/2026-10-16-dungeon-fattys-lair.md; docs/godot/DUNGEONS.md
"Fatty's Lair (built)").

Sources: asset/Originals/fattys-lair/generated/ (Magnific GPT 2.5, transparent background, the Lili
sheet as style reference, 2026-10-17). Writes godot/asset/MAPS/objects/fattys-lair/ at the art density
of 2 px per game unit (objects) and godot/asset/characters/authored/npcs/burr.webp at 3 px per unit
(the NPC sheets' density):

- drop-gate-frame.webp, drop-gate-leaf.webp: the old Thorn Guard gate in its rock mound (drop-gate-a)
  cut in two: the mound and the arch with a dark doorway where the leaf was, and the oak leaf, which
  rises into the arch when the worm lever lifts it; its doorway is DROP_GATE_OPENING_UNITS wide;
- worm-lever.webp: the worms' lever on its post (worm-lever-a), WORM_LEVER_UNITS tall;
- gate-winch.webp: the gatehouse winch (winch-a), GATE_WINCH_UNITS wide;
- eye-latch-2x1.webp: the stone eye latch, open (the target) and shut (eye-latch-a), in cells of
  EYE_LATCH_CELL px;
- stone-door-frame.webp, stone-door-slab.webp: the stone door (stone-door-a) cut in two, its frame of
  cut blocks with a dark doorway and the slab that slides up; the slab is STONE_DOOR_OPENING_UNITS wide;
- plank-barricade-2x1.webp: the plank barricade, whole and smashed (barricade-a), the wooden door the
  model painted behind the planks cut away so the passage behind shows through the gaps;
- stair-hatch-2x1.webp: the Inner Stair's hatch, shut and open (hatch-a);
- pearl.webp, pearl-altar.webp, pearl-altar-empty.webp: the Pearl alone, the worms' altar with it,
  and the altar with its hollow empty (pearl-altar-a);
- war-banner.webp, worm-bunk.webp: Gorge's army's banner (bright: scenery) and a worm bunk;
- burr.webp (npcs): Burr's three poses (standing, waving, walking right), BURR_CELL cells, feet on the
  cell's bottom, body centred on BURR_BODY_X.

It prints the placement numbers the scenes use.

    python scripts/art/pack-fattys-lair-art.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/fattys-lair/generated"
OUT = ROOT / "godot/asset/MAPS/objects/fattys-lair"
NPCS = ROOT / "godot/asset/characters/authored/npcs"
ALPHA_CUT = 40
DOORWAY = (24, 17, 13, 255)

DROP_GATE_OPENING_UNITS = 128
# drop-gate-a: the leaf (source px): its rectangle and the arch over it.
DROP_LEAF_BOX = (284, 330, 742, 968)
DROP_LEAF_ARCH_Y = 470
WORM_LEVER_UNITS = 120
GATE_WINCH_UNITS = 112
EYE_LATCH_CELL = (128, 128)
EYE_LATCH_UNITS = 60
STONE_DOOR_OPENING_UNITS = 128
# stone-door-a: the slab between the posts (source px).
STONE_SLAB_BOX = (340, 250, 692, 945)
BARRICADE_UNITS = 128
# barricade-a: the doorway inside each frame, where the model painted a wooden door (source px).
BARRICADE_INSIDE = [(282, 118, 546, 692), (1016, 124, 1300, 640)]
HATCH_UNITS = 112
PEARL_CENTRE = (497, 178)
PEARL_RADIUS = 138
PEARL_UNITS = 48
ALTAR_UNITS = 112
BANNER_UNITS = 150
BUNK_UNITS = 150
BURR_CELL = (200, 230)
BURR_BODY_X = 100
BURR_BODY_UNITS_TALL = 70
BURR_PX_PER_UNIT = 3


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


def frames(image: Image.Image, min_gap: int = 20) -> list[tuple[int, int, int, int]]:
	"""The bounding boxes of the pictures standing side by side on a sheet (split on empty columns)."""
	alpha = image.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0)
	px = alpha.load()
	used = [any(px[x, y] for y in range(0, image.height, 3)) for x in range(image.width)]
	runs, start = [], None
	for x, filled in enumerate(used + [False]):
		if filled and start is None:
			start = x
		elif not filled and start is not None:
			if x - start > min_gap:
				runs.append((start, x))
			start = None
	boxes = []
	for x0, x1 in runs:
		b = alpha.crop((x0, 0, x1, image.height)).getbbox()
		boxes.append((x0 + b[0], b[1], x0 + b[2], b[3]))
	return boxes


def row_sheet(pictures: list[Image.Image], cell: tuple[int, int]) -> Image.Image:
	"""Pictures in a row of equal cells, each bottom-centred in its cell."""
	sheet = Image.new("RGBA", (cell[0] * len(pictures), cell[1]), (0, 0, 0, 0))
	for i, picture in enumerate(pictures):
		x = i * cell[0] + (cell[0] - picture.width) // 2
		y = cell[1] - picture.height
		sheet.alpha_composite(picture, (max(i * cell[0], x), max(0, y)))
	return sheet


def leaf_mask(size: tuple[int, int], box: tuple[int, int, int, int], arch_y: int) -> Image.Image:
	"""An arched door shape: the box below `arch_y`, an ellipse over it."""
	mask = Image.new("L", size, 0)
	draw = ImageDraw.Draw(mask)
	x0, y0, x1, y1 = box
	draw.rectangle((x0, arch_y, x1, y1), fill=255)
	draw.ellipse((x0, y0, x1, arch_y + (arch_y - y0)), fill=255)
	return mask


def pack_drop_gate() -> None:
	gate = load("drop-gate-a.png")
	mask = leaf_mask(gate.size, DROP_LEAF_BOX, DROP_LEAF_ARCH_Y)
	leaf = Image.new("RGBA", gate.size, (0, 0, 0, 0))
	leaf.paste(gate, (0, 0), mask)
	frame = gate.copy()
	dark = Image.new("RGBA", gate.size, DOORWAY)
	frame.paste(dark, (0, 0), mask)
	box = alpha_box(gate)
	factor = DROP_GATE_OPENING_UNITS * 2 / (DROP_LEAF_BOX[2] - DROP_LEAF_BOX[0])
	frame = scaled(frame.crop(box), factor)
	leaf_box = DROP_LEAF_BOX
	leaf = scaled(leaf.crop(leaf_box), factor)
	save(frame, OUT / "drop-gate-frame.webp")
	save(leaf, OUT / "drop-gate-leaf.webp")
	# Placement: the node stands at the middle of the doorway's foot (the leaf's bottom centre).
	foot = ((leaf_box[0] + leaf_box[2]) / 2, leaf_box[3])
	frame_offset = ((box[0] - foot[0]) * factor, (box[1] - foot[1]) * factor)
	leaf_offset = ((leaf_box[0] - foot[0]) * factor, (leaf_box[1] - foot[1]) * factor)
	print(f"  drop gate: frame offset {frame_offset[0]:.1f}, {frame_offset[1]:.1f} px; leaf offset "
		f"{leaf_offset[0]:.1f}, {leaf_offset[1]:.1f} px (Sprite2D scale 0.5, centered off); frame "
		f"{frame.width / 2:.0f} x {frame.height / 2:.0f} units")


def pack_single(name: str, out: str, units: float, by_height: bool) -> None:
	picture = load(name)
	picture = picture.crop(alpha_box(picture))
	factor = units * 2 / (picture.height if by_height else picture.width)
	picture = scaled(picture, factor)
	save(picture, OUT / out)
	print(f"  {out}: offset {-picture.width / 2:.1f}, {-picture.height:.1f} px (bottom centre), "
		f"{picture.width / 2:.0f} x {picture.height / 2:.0f} units")


def pack_eye_latch() -> None:
	sheet = load("eye-latch-a.png")
	boxes = frames(sheet)
	pictures = []
	for box in boxes[:2]:
		picture = sheet.crop(box)
		factor = EYE_LATCH_UNITS * 2 / picture.width
		pictures.append(scaled(picture, factor))
	out = Image.new("RGBA", (EYE_LATCH_CELL[0] * 2, EYE_LATCH_CELL[1]), (0, 0, 0, 0))
	for i, picture in enumerate(pictures):
		out.alpha_composite(picture, (i * EYE_LATCH_CELL[0] + (EYE_LATCH_CELL[0] - picture.width) // 2,
			(EYE_LATCH_CELL[1] - picture.height) // 2))
	save(out, OUT / "eye-latch-2x1.webp")


def pack_stone_door() -> None:
	door = load("stone-door-a.png")
	slab = door.crop(STONE_SLAB_BOX)
	frame = door.copy()
	ImageDraw.Draw(frame).rectangle(STONE_SLAB_BOX, fill=DOORWAY)
	box = alpha_box(door)
	factor = STONE_DOOR_OPENING_UNITS * 2 / (STONE_SLAB_BOX[2] - STONE_SLAB_BOX[0])
	frame = scaled(frame.crop(box), factor)
	slab = scaled(slab, factor)
	save(frame, OUT / "stone-door-frame.webp")
	save(slab, OUT / "stone-door-slab.webp")
	foot = ((STONE_SLAB_BOX[0] + STONE_SLAB_BOX[2]) / 2, STONE_SLAB_BOX[3])
	print(f"  stone door: frame offset {(box[0] - foot[0]) * factor:.1f}, {(box[1] - foot[1]) * factor:.1f} px; "
		f"slab offset {(STONE_SLAB_BOX[0] - foot[0]) * factor:.1f}, {(STONE_SLAB_BOX[1] - foot[1]) * factor:.1f} px")


def clear_doorway(image: Image.Image, box: tuple[int, int, int, int]) -> None:
	"""Inside `box`, the dark wood the model painted behind the planks becomes see-through; the pale
	grey planks and the rusty nails stay."""
	px = image.load()
	for y in range(box[1], box[3]):
		for x in range(box[0], box[2]):
			r, g, b, a = px[x, y]
			if a == 0:
				continue
			lum = 0.3 * r + 0.59 * g + 0.11 * b
			grey = max(r, g, b) - min(r, g, b) < 42
			if lum < 118 and not (grey and lum > 70):
				px[x, y] = (r, g, b, 0)


def pack_barricade() -> None:
	sheet = load("barricade-a.png")
	for inside in BARRICADE_INSIDE:
		clear_doorway(sheet, inside)
	boxes = frames(sheet)
	whole = sheet.crop(boxes[0])
	factor = BARRICADE_UNITS * 2 / whole.width
	pictures = [scaled(sheet.crop(box), factor) for box in boxes[:2]]
	cell = (max(p.width for p in pictures) + 4, max(p.height for p in pictures) + 4)
	save(row_sheet(pictures, cell), OUT / "plank-barricade-2x1.webp")
	print(f"  barricade cell {cell[0]} x {cell[1]} px: offset {-cell[0] / 2:.0f}, {-cell[1]:.0f} (bottom centre)")


def pack_hatch() -> None:
	sheet = load("hatch-a.png")
	boxes = frames(sheet)
	shut = sheet.crop(boxes[0])
	factor = HATCH_UNITS * 2 / shut.width
	pictures = [scaled(sheet.crop(box), factor) for box in boxes[:2]]
	cell = (max(p.width for p in pictures) + 4, max(p.height for p in pictures) + 4)
	save(row_sheet(pictures, cell), OUT / "stair-hatch-2x1.webp")
	print(f"  hatch cell {cell[0]} x {cell[1]} px: offset {-cell[0] / 2:.0f}, {-cell[1]:.0f} (bottom centre)")


def pack_pearl() -> None:
	altar = load("pearl-altar-a.png")
	cx, cy = PEARL_CENTRE
	r = PEARL_RADIUS
	orb_mask = Image.new("L", altar.size, 0)
	ImageDraw.Draw(orb_mask).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
	pearl = Image.new("RGBA", altar.size, (0, 0, 0, 0))
	pearl.paste(altar, (0, 0), orb_mask)
	pearl = pearl.crop((cx - r, cy - r, cx + r, cy + r))
	save(scaled(pearl, PEARL_UNITS * 2 / pearl.width), OUT / "pearl.webp")
	empty = altar.copy()
	px = empty.load()
	hollow_top = cy + 50
	for y in range(cy - r, cy + r):
		for x in range(cx - r, cx + r):
			if (x - cx) ** 2 + (y - cy) ** 2 > r * r:
				continue
			if y < hollow_top:
				px[x, y] = (0, 0, 0, 0)
			else:
				px[x, y] = (40, 28, 20, 255) if px[x, y][3] > 0 else px[x, y]
	box = alpha_box(altar)
	factor = ALTAR_UNITS * 2 / (box[3] - box[1])
	full = scaled(altar.crop(box), factor)
	save(full, OUT / "pearl-altar.webp")
	save(scaled(empty.crop(box), factor), OUT / "pearl-altar-empty.webp")
	print(f"  altar: offset {-full.width / 2:.1f}, {-full.height:.1f} px; the pearl's centre "
		f"{(cx - (box[0] + box[2]) / 2) * factor / 2:.1f}, {(cy - box[3]) * factor / 2:.1f} units from the foot")


def pack_burr() -> None:
	sheet = load("burr-a.png")
	boxes = frames(sheet)
	tallest = max(b[3] - b[1] for b in boxes)
	factor = BURR_BODY_UNITS_TALL * BURR_PX_PER_UNIT / tallest
	out = Image.new("RGBA", (BURR_CELL[0] * len(boxes), BURR_CELL[1]), (0, 0, 0, 0))
	for i, box in enumerate(boxes):
		picture = scaled(sheet.crop(box), factor)
		out.alpha_composite(picture, (i * BURR_CELL[0] + BURR_BODY_X - picture.width // 2, BURR_CELL[1] - picture.height))
	save(out, NPCS / "burr.webp")
	print(f"  burr: {len(boxes)} poses, cell {BURR_CELL}, body x {BURR_BODY_X}, scale 1/{BURR_PX_PER_UNIT}")


def main() -> None:
	pack_drop_gate()
	pack_single("worm-lever-a.png", "worm-lever.webp", WORM_LEVER_UNITS, True)
	pack_single("winch-a.png", "gate-winch.webp", GATE_WINCH_UNITS, False)
	pack_eye_latch()
	pack_stone_door()
	pack_barricade()
	pack_hatch()
	pack_pearl()
	pack_single("war-banner-a.png", "war-banner.webp", BANNER_UNITS, True)
	pack_single("worm-bunk-a.png", "worm-bunk.webp", BUNK_UNITS, False)
	pack_burr()


if __name__ == "__main__":
	main()
