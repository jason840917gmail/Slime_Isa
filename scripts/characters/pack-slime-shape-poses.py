"""Pack the body-shape attack poses and the jelly weapons for the body-shapes prototype.

Sources (asset/Originals/characters/slime-v2/shapes/, GPT 2.5 with transparent backgrounds,
2026-10-12, prompts in that folder's README):
  poses-<shape>-<direction>.png  a 2 x 2 sheet of four key poses of the slime, no weapon
  weapon-<shape>.png             the shape's jelly weapon lying horizontal, root on the left
  vfx-goo-splat.png, vfx-axe-swoosh.png, vfx-spear-glint.png, energy-shard.png  the effects

Outputs:
  godot/asset/characters/256x256-tile_8x8-slime-v2-page-6.webp  the poses, page 1's cells and
      baseline (centred at x 128 on the ground, standing on y 251)
  asset/Originals/characters/slime-v2/page-6.json               where every pose landed
  godot/asset/characters/shapes/<shape>.webp + shapes.json       the weapons, cropped, with their
      root, neck, head and tip positions for the code that draws them
  godot/asset/MAPS/effects/256x256-tile_4x1-goo-splat.webp, shape-axe-swoosh.webp,
      shape-spear-glint.webp, energy-shard.webp                  the effects
  godot/asset/UI/shapes/<shape>-icon.webp                        the shape icons (HUD and bag)

Then `tools/build_player_clips.gd -- --only=shape-` (docs/TOOLING.md) builds the page-6 pose clips the
game shows (the War Axe's Spin; every other strike plays its strike frames).

Scale: jelly keeps its volume, so each sheet is scaled until its four poses cover, on average,
the same area as page 1's first idle frame of that direction (then shrunk if a pose would leave
its cell). Usage: python scripts/characters/pack-slime-shape-poses.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/characters/slime-v2/shapes"
PAGE_OUT = ROOT / "godot/asset/characters/256x256-tile_8x8-slime-v2-page-6.webp"
MANIFEST_OUT = ROOT / "asset/Originals/characters/slime-v2/page-6.json"
WEAPON_DIR = ROOT / "godot/asset/characters/shapes"
PAGE_1 = ROOT / "godot/asset/characters/256x256-tile_8x8-slime-v2-page-1.webp"

CELL = 256
CENTRE_X = 128
BASELINE_Y = 251
MARGIN = 3
ALPHA_SOLID = 40
GROUND_BAND = 0.15
WEAPON_LONG_SIDE = 512

POSES = {
	"spear": ["ready", "jab", "load", "thrust"],
	"axe": ["swing-down", "swing-up", "load", "chop"],
	"hammer": ["lift", "smash", "load", "rebound"],
}
# (shape, direction) -> (row, first column) on page 6.
LAYOUT = {
	("spear", "down"): (0, 0), ("spear", "up"): (0, 4),
	("spear", "side"): (1, 0), ("axe", "down"): (1, 4),
	("axe", "up"): (2, 0), ("axe", "side"): (2, 4),
	("hammer", "down"): (3, 0), ("hammer", "up"): (3, 4),
	("hammer", "side"): (4, 0),
}
# Page 1's first idle frame per direction: (column, row).
REFERENCE_CELLS = {"down": (0, 0), "up": (0, 1), "side": (0, 2)}
# Where the axe's head and the hammer's head leave their haft or stalk: x in the packed 512 px
# weapon, measured on the 2026-10-12 art (the Spear's head_start is measured below). Measure again
# when the weapon art changes; game/shapes/shape_visuals.gd keeps the same numbers as its fallback.
HEAD_STARTS = {"axe": 200, "hammer": 184}


def solid_mask(image: Image.Image) -> Image.Image:
	return image.getchannel("A").point(lambda a: 255 if a > ALPHA_SOLID else 0)


def solid_area(image: Image.Image) -> int:
	return solid_mask(image).histogram()[255]


def reference_areas() -> dict[str, int]:
	page = Image.open(PAGE_1).convert("RGBA")
	areas = {}
	for direction, (col, row) in REFERENCE_CELLS.items():
		cell = page.crop((col * CELL, row * CELL, (col + 1) * CELL, (row + 1) * CELL))
		areas[direction] = solid_area(cell)
	return areas


def quarters(sheet: Image.Image) -> list[Image.Image]:
	"""The four poses in reading order, each cropped to its solid pixels."""
	w, h = sheet.size
	out = []
	for qy in range(2):
		for qx in range(2):
			quarter = sheet.crop((qx * w // 2, qy * h // 2, (qx + 1) * w // 2, (qy + 1) * h // 2))
			box = solid_mask(quarter).getbbox()
			out.append(quarter.crop(box))
	return out


def ground_centre_x(pose: Image.Image) -> float:
	"""Mean x of the solid pixels in the lowest GROUND_BAND of the pose: where it stands."""
	mask = solid_mask(pose)
	w, h = mask.size
	top = int(h * (1.0 - GROUND_BAND))
	total = 0.0
	count = 0
	pixels = mask.load()
	for y in range(top, h):
		for x in range(w):
			if pixels[x, y]:
				total += x
				count += 1
	return total / count if count else w / 2.0


def place(page: Image.Image, pose: Image.Image, col: int, row: int) -> dict:
	gx = ground_centre_x(pose)
	left = round(CENTRE_X - gx)
	top = BASELINE_Y - pose.height
	left = max(MARGIN, min(CELL - MARGIN - pose.width, left))
	top = max(MARGIN, top)
	page.alpha_composite(pose, (col * CELL + left, row * CELL + top))
	return {"frame": row * 8 + col, "width": pose.width, "height": pose.height, "left": left, "top": top}


def pack_poses() -> dict:
	refs = reference_areas()
	page = Image.new("RGBA", (CELL * 8, CELL * 8), (0, 0, 0, 0))
	manifest: dict = {"cell": CELL, "baseline": BASELINE_Y, "centre_x": CENTRE_X, "clips": {}}
	for (shape, direction), (row, first_col) in LAYOUT.items():
		sheet = Image.open(SRC / f"poses-{shape}-{direction}.png").convert("RGBA")
		poses = quarters(sheet)
		mean_area = sum(solid_area(p) for p in poses) / len(poses)
		scale = math.sqrt(refs[direction] / mean_area)
		limit = CELL - 2 * MARGIN
		for pose in poses:
			scale = min(scale, limit / pose.width, (BASELINE_Y - MARGIN) / pose.height)
		entries = {}
		for index, pose in enumerate(poses):
			size = (max(1, round(pose.width * scale)), max(1, round(pose.height * scale)))
			scaled = pose.resize(size, Image.LANCZOS)
			entries[POSES[shape][index]] = place(page, scaled, first_col + index, row)
		manifest["clips"][f"{shape}-{direction}"] = {"row": row, "first_column": first_col,
			"scale": round(scale, 4), "poses": entries}
	PAGE_OUT.parent.mkdir(parents=True, exist_ok=True)
	page.save(PAGE_OUT, lossless=True, method=6)
	MANIFEST_OUT.write_text(json.dumps(manifest, indent="\t") + "\n", encoding="utf-8")
	return manifest


def column_heights(image: Image.Image) -> list[int]:
	mask = solid_mask(image)
	w, h = mask.size
	pixels = mask.load()
	heights = []
	for x in range(w):
		heights.append(sum(1 for y in range(h) if pixels[x, y]))
	return heights


def pack_weapons() -> dict:
	WEAPON_DIR.mkdir(parents=True, exist_ok=True)
	info: dict = {}
	for shape in POSES:
		image = Image.open(SRC / f"weapon-{shape}.png").convert("RGBA")
		image = image.crop(solid_mask(image).getbbox())
		heights = column_heights(image)
		w = len(heights)
		root_peak = max(range(int(w * 0.35)), key=lambda x: heights[x])
		neck = min(range(root_peak, int(w * 0.5)), key=lambda x: heights[x])
		if shape != "spear":
			# The axe's and the hammer's root blobs (with their leaves) would sit inside the body:
			# the weapon starts at its neck.
			image = image.crop((neck, 0, w, image.height))
			image = image.crop(solid_mask(image).getbbox())
			heights = column_heights(image)
			w = len(heights)
			neck = 0
		factor = WEAPON_LONG_SIDE / max(image.size)
		image = image.resize((round(image.width * factor), round(image.height * factor)), Image.LANCZOS)
		heights = column_heights(image)
		w = len(heights)
		h = image.height
		mask = solid_mask(image).load()
		mid = [x for x in range(w) if mask[x, h // 2]]
		entry = {"size": [w, h], "root": [0, h // 2], "tip": [w - 1, h // 2]}
		if shape == "spear":
			middle = sorted(heights[int(w * 0.35):int(w * 0.65)])
			shaft = middle[len(middle) // 2]
			peak = max(range(int(w * 0.25)), key=lambda x: heights[x])
			root_end = next(x for x in range(peak, w) if heights[x] < shaft * 1.6)
			barbs = max(range(int(w * 0.65), w), key=lambda x: heights[x])
			head_start = next(x for x in range(barbs, 0, -1) if heights[x] < shaft * 1.4)
			entry.update({"shaft_px": shaft, "root_end": root_end, "head_start": head_start})
		elif shape in HEAD_STARTS:
			entry["head_start"] = HEAD_STARTS[shape]
		entry["neck"] = round(neck * factor)
		image.save(WEAPON_DIR / f"{shape}.webp", lossless=True, method=6)
		info[shape] = entry
	(WEAPON_DIR / "shapes.json").write_text(json.dumps(info, indent="\t") + "\n", encoding="utf-8")
	return info


EFFECTS_DIR = ROOT / "godot/asset/MAPS/effects"
EFFECT_CELL = 256
# Single sprites: source -> (runtime name, longest side in px).
EFFECT_SPRITES = {
	"vfx-axe-swoosh.png": ("shape-axe-swoosh.webp", 384),
	"vfx-spear-glint.png": ("shape-spear-glint.webp", 256),
	"energy-shard.png": ("energy-shard.webp", 128),
}


def pack_effects() -> dict:
	"""The goo splat's four frames in a 4 x 1 strip of EFFECT_CELL cells (each frame centred,
	one scale for all four, from the biggest), and the single effect sprites cropped and scaled."""
	EFFECTS_DIR.mkdir(parents=True, exist_ok=True)
	frames = quarters(Image.open(SRC / "vfx-goo-splat.png").convert("RGBA"))
	scale = min((EFFECT_CELL - 2 * MARGIN) / max(f.width, f.height) for f in frames)
	strip = Image.new("RGBA", (EFFECT_CELL * len(frames), EFFECT_CELL), (0, 0, 0, 0))
	for index, frame in enumerate(frames):
		scaled = frame.resize((round(frame.width * scale), round(frame.height * scale)), Image.LANCZOS)
		strip.alpha_composite(scaled, (index * EFFECT_CELL + (EFFECT_CELL - scaled.width) // 2,
			(EFFECT_CELL - scaled.height) // 2))
	splat_name = f"{EFFECT_CELL}x{EFFECT_CELL}-tile_{len(frames)}x1-goo-splat.webp"
	strip.save(EFFECTS_DIR / splat_name, lossless=True, method=6)
	info = {"goo-splat": {"file": splat_name, "frames": len(frames), "cell": EFFECT_CELL}}
	for source, (name, long_side) in EFFECT_SPRITES.items():
		image = Image.open(SRC / source).convert("RGBA")
		image = image.crop(solid_mask(image).getbbox())
		factor = long_side / max(image.size)
		image = image.resize((round(image.width * factor), round(image.height * factor)), Image.LANCZOS)
		image.save(EFFECTS_DIR / name, lossless=True, method=6)
		info[name.removesuffix(".webp")] = {"file": name, "size": list(image.size)}
	return info


ICON_DIR = ROOT / "godot/asset/UI/shapes"
ICON_SIZE = 128
ICON_PAD = 8
ICON_ANGLE = 45.0


def pack_icons() -> list[str]:
	"""One icon per shape for the HUD's shape slot and the bag's Shapes row: the packed weapon
	turned to point up and to the right, fitted inside ICON_SIZE with ICON_PAD."""
	ICON_DIR.mkdir(parents=True, exist_ok=True)
	written = []
	for shape in POSES:
		weapon = Image.open(WEAPON_DIR / f"{shape}.webp").convert("RGBA")
		turned = weapon.rotate(ICON_ANGLE, resample=Image.BICUBIC, expand=True)
		turned = turned.crop(solid_mask(turned).getbbox())
		factor = (ICON_SIZE - 2 * ICON_PAD) / max(turned.size)
		turned = turned.resize((round(turned.width * factor), round(turned.height * factor)), Image.LANCZOS)
		icon = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
		icon.alpha_composite(turned, ((ICON_SIZE - turned.width) // 2, (ICON_SIZE - turned.height) // 2))
		path = ICON_DIR / f"{shape}-icon.webp"
		icon.save(path, lossless=True, method=6)
		written.append(str(path.relative_to(ROOT)))
	return written


if __name__ == "__main__":
	poses = pack_poses()
	for clip, data in poses["clips"].items():
		print(clip, "row", data["row"], "col", data["first_column"], "scale", data["scale"])
	print(json.dumps(pack_weapons(), indent=1))
	print(json.dumps(pack_effects(), indent=1))
	print(pack_icons())
