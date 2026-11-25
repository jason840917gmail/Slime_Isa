#!/usr/bin/env python3
"""Makes the root-rock interior wall's cracked frame from art the project has (no generation).

The generated `root-bevel-cracked.png` (asset/Originals/dungeon-kit/interior-walls/) came out as a
frame with see-through gaps (the generator's fake checkerboard) where each face's cracked stretch
should be, so every cracked block of a root-rock room showed holes (found 2026-11-25, building the
Weaver Hollow's rooms: docs/handover/2026-11-23-dungeons-rework.md "Step 3"). This builds
`root-bevel-cracked-made.png` instead, which pack-interior-walls.py packs for root-rock:

  the plain frame (root-bevel-doorways-a.png), each face's doorway box (the packer's `boxes`) filled
  with that face's own plain stone (its two plain stretches, the packer's `plain`, a half of each, so
  the stones keep their size and light), then the Goo Bomb's crack decal
  (godot/asset/abilities/goo-bomb/crack-overlay.webp, dark cracks on transparency) laid over the
  middle of the stretch, turned to the face.

Usage: python scripts/art/make-root-cracked.py   (Pillow)
       then python scripts/art/pack-interior-walls.py root-rock
       and  "<Godot console exe>" --headless --path godot -s res://tools/pack_interior_palette.gd
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/dungeon-kit/interior-walls"
FRAME = SRC / "root-bevel-doorways-a.png"
OUT = SRC / "root-bevel-cracked-made.png"
CRACK = ROOT / "godot/asset/abilities/goo-bomb/crack-overlay.webp"

# The packer's numbers for root-rock (pack-interior-walls.py STYLES["root-rock"]), frame px.
BANDS = {"n": (15, 217), "s": (802, 999), "w": (19, 207), "e": (816, 1004)}
PLAIN = [(232, 392), (624, 790)]
BOX = (402, 608)
# How much of the face's depth the cracks cover, and how strong they are.
CRACK_DEPTH = 0.86
CRACK_ALPHA = 1.0


def _fill_box(frame: Image.Image, side: str) -> None:
	"""Fills `side`'s doorway box with the face's own plain stone, half from each plain stretch."""
	a0, a1 = BANDS[side]
	width = BOX[1] - BOX[0]
	half = width // 2
	left = PLAIN[0]
	right = PLAIN[1]
	if side in ("n", "s"):
		first = frame.crop((left[0], a0, left[0] + half, a1))
		second = frame.crop((right[1] - (width - half), a0, right[1], a1))
		patch = Image.new("RGBA", (width, a1 - a0))
		patch.paste(first, (0, 0))
		patch.paste(second, (half, 0))
		frame.paste(patch, (BOX[0], a0))
	else:
		first = frame.crop((a0, left[0], a1, left[0] + half))
		second = frame.crop((a0, right[1] - (width - half), a1, right[1]))
		patch = Image.new("RGBA", (a1 - a0, width))
		patch.paste(first, (0, 0))
		patch.paste(second, (0, half))
		frame.paste(patch, (a0, BOX[0]))


def _crack(frame: Image.Image, side: str, crack: Image.Image) -> None:
	"""Lays the crack decal over the middle of `side`'s box, turned to the face."""
	a0, a1 = BANDS[side]
	depth = int((a1 - a0) * CRACK_DEPTH)
	width = BOX[1] - BOX[0]
	turned = {"n": crack, "s": crack.rotate(180, expand=True), "w": crack.rotate(90, expand=True),
		"e": crack.rotate(-90, expand=True)}[side]
	if side in ("n", "s"):
		size = (width, depth)
		at = (BOX[0], a0 + ((a1 - a0) - depth) // 2)
	else:
		size = (depth, width)
		at = (a0 + ((a1 - a0) - depth) // 2, BOX[0])
	decal = turned.resize(size, Image.LANCZOS)
	alpha = decal.split()[3].point(lambda v: int(v * CRACK_ALPHA))
	decal.putalpha(alpha)
	# a soft dark shadow under the cracks, so they read as sunk into the stone
	shadow = Image.new("RGBA", size, (20, 12, 6, 0))
	shadow.putalpha(alpha.filter(ImageFilter.GaussianBlur(3)).point(lambda v: int(v * 0.55)))
	frame.alpha_composite(shadow, at)
	frame.alpha_composite(decal, at)
	# twice: the decal's thin lines are faint at game size
	frame.alpha_composite(decal, at)


def main() -> None:
	frame = Image.open(FRAME).convert("RGBA")
	crack = Image.open(CRACK).convert("RGBA")
	for side in ("n", "s", "w", "e"):
		_fill_box(frame, side)
		_crack(frame, side, crack)
	frame.save(OUT)
	print("wrote", OUT)


if __name__ == "__main__":
	main()
