#!/usr/bin/env python3
"""Makes the crystal-cave interior wall's cracked and blown frames from art the project has (no
generation), for the rebuilt Crystal Mine (M5's cracked wall to the Survey Office, 2026-11-25:
docs/handover/2026-11-23-dungeons-rework.md "Step 4: the Mine"):

  crystal-bevel-cracked-made.png  the plain frame (crystal-bevel-doorways-b.png), its north doorway
                                  box filled with the face's own plain stone (half from each of its
                                  two plain stretches, the joins feathered), the Goo Bomb's crack decal
                                  (godot/asset/abilities/goo-bomb/crack-overlay.webp) laid over it,
                                  over it: as scripts/art/make-root-cracked.py does
  crystal-bevel-blown-made.png    the plain frame with its north doorway as it is (the way through,
                                  its passage left clear), the crack decal laid round its jambs and
                                  lintel: the hole a blast broke through the cracked stretch
The packer cuts only the north piece of an opening and turns it for the other sides, so only the
north face is made.

Both land in asset/Originals/dungeon-kit/interior-walls/; pack-interior-walls.py packs them for
crystal-cave. Then: python scripts/art/strip-credentials.py --check <each new file>,
python scripts/art/pack-interior-walls.py crystal-cave, and
"<Godot console exe>" --headless --path godot -s res://tools/pack_interior_palette.gd.
Usage: python scripts/art/make-crystal-openings.py   (Pillow)
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/dungeon-kit/interior-walls"
FRAME = SRC / "crystal-bevel-doorways-b.png"
CRACKED = SRC / "crystal-bevel-cracked-made.png"
BLOWN = SRC / "crystal-bevel-blown-made.png"
CRACK = ROOT / "godot/asset/abilities/goo-bomb/crack-overlay.webp"

# The packer's numbers for crystal-cave (pack-interior-walls.py STYLES["crystal-cave"]), frame px.
BANDS = {"n": (15, 224), "s": (800, 1006), "w": (19, 220), "e": (803, 1005)}
PLAIN = [(232, 392), (624, 790)]
BOX = (403, 609)
# How much of the face's depth the cracks cover.
CRACK_DEPTH = 0.86
# The blown hole: the crack decal round the opening, this much wider than the box on each end.
BLOWN_SPREAD = 26
# The doorway's passage (the packer's `passages["n"]`): left clear of the blown hole's cracks.
PASSAGE = (450, 77, 563, 186)
# The stone patch's joins fade over this many px (no seam at the box's ends or between its halves).
FEATHER = 14
# The crack toned to the wall (the reviewer, 2026-11-25: the decal's brown read as a black scribble on
# the crystals): its lines thinned, filled with the frame's own dark blue, a pale blue edge below them
# (the light catching the crack's lower lip), laid once and a little see-through.
CRACK_COLOR = (14, 22, 52)
EDGE_COLOR = (150, 196, 240)
CRACK_ALPHA = 0.9
EDGE_ALPHA = 0.55
THIN = 3


def _ramp(width: int, height: int, fade_left: bool, fade_right: bool) -> Image.Image:
	"""An alpha mask, opaque but for FEATHER px fading out at the chosen ends."""
	mask = Image.new("L", (width, height), 255)
	for x in range(FEATHER):
		v = int(255 * (x + 0.5) / FEATHER)
		if fade_left:
			mask.paste(v, (x, 0, x + 1, height))
		if fade_right:
			mask.paste(v, (width - 1 - x, 0, width - x, height))
	return mask


def _fill_north(frame: Image.Image) -> None:
	"""Fills the north doorway box with the face's own plain stone, half from each plain stretch,
	each half reaching FEATHER past its end and fading there, so no seam shows. (The packer cuts only
	the north piece and turns it for the other sides.)"""
	a0, a1 = BANDS["n"]
	height = a1 - a0
	width = BOX[1] - BOX[0]
	half = width // 2
	left, right = PLAIN
	first = frame.crop((left[0], a0, left[0] + half + 2 * FEATHER, a1))
	first.putalpha(_ramp(first.width, height, True, True))
	second = frame.crop((right[1] - (width - half) - 2 * FEATHER, a0, right[1], a1))
	second.putalpha(_ramp(second.width, height, True, True))
	# a solid core first (no see-through where the halves meet), then the feathered halves over it
	core = frame.crop((left[0], a0, left[0] + width, a1))
	frame.paste(core, (BOX[0], a0))
	frame.alpha_composite(second, (BOX[0] + half - 2 * FEATHER + FEATHER, a0))
	frame.alpha_composite(first, (BOX[0] - FEATHER, a0))


def _decal(frame: Image.Image, side: str, crack: Image.Image, lo: int, hi: int, under: Image.Image | None = None) -> None:
	"""Lays the crack decal over `side`'s face between `lo` and `hi` along it, turned to the face.
	With `under`, the decal is kept only where `under` (the frame before) is opaque: off the opening."""
	a0, a1 = BANDS[side]
	depth = int((a1 - a0) * CRACK_DEPTH)
	width = hi - lo
	turned = {"n": crack, "s": crack.rotate(180, expand=True), "w": crack.rotate(90, expand=True),
		"e": crack.rotate(-90, expand=True)}[side]
	if side in ("n", "s"):
		size = (width, depth)
		at = (lo, a0 + ((a1 - a0) - depth) // 2)
	else:
		size = (depth, width)
		at = (a0 + ((a1 - a0) - depth) // 2, lo)
	decal = turned.resize(size, Image.LANCZOS)
	# thinner lines: the decal's alpha eroded
	alpha = decal.split()[3].filter(ImageFilter.MinFilter(THIN))
	if under is not None:
		solid = under.crop((at[0], at[1], at[0] + size[0], at[1] + size[1])).split()[3]
		alpha = Image.composite(alpha, Image.new("L", size, 0), solid.point(lambda v: 255 if v > 200 else 0))
	# the pale edge: the lines' mask a little lower and to the right, under the dark line
	edge = Image.new("RGBA", size, EDGE_COLOR + (0,))
	edge.putalpha(alpha.point(lambda v: int(v * EDGE_ALPHA)))
	frame.alpha_composite(edge, (at[0] + 1, at[1] + 2))
	line = Image.new("RGBA", size, CRACK_COLOR + (0,))
	line.putalpha(alpha.point(lambda v: int(v * CRACK_ALPHA)))
	frame.alpha_composite(line, at)


def main() -> None:
	plain = Image.open(FRAME).convert("RGBA")
	crack = Image.open(CRACK).convert("RGBA")
	cracked = plain.copy()
	_fill_north(cracked)
	_decal(cracked, "n", crack, BOX[0], BOX[1])
	cracked.save(CRACKED)
	blown = plain.copy()
	_decal(blown, "n", crack, BOX[0] - BLOWN_SPREAD, BOX[1] + BLOWN_SPREAD, plain)
	# the way through stays clear: the passage as the plain frame has it
	blown.paste(plain.crop(PASSAGE), PASSAGE[:2])
	blown.save(BLOWN)
	print("wrote", CRACKED, BLOWN)


if __name__ == "__main__":
	main()
