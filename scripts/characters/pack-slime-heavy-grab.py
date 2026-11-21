"""Pack the Heavy grab's push and pull poses into the slime's page 7.

Sources (asset/Originals/characters/slime-v2/heavy-grab/, GPT 2.5 with transparent backgrounds,
2026-10-19, prompts in that folder's README): `<push|pull>-<side|down|up>-<a|b>.png`, each a 2 x 2
sheet of four key poses of the slime pushing or pulling a heavy block that is not drawn. The owner
approved push A and pull B for the side view; the front and back views were made to match.

Outputs (rows 0-2 of page 7; rows 3-4 and the manifest's `bow-*` entries are the Bow's, written by
scripts/characters/pack-slime-bow.py, and are kept):
  godot/asset/characters/256x256-tile_8x8-slime-v2-page-7.webp  the poses, page 1's cells, scale
      and baseline (the slime's body centre at x 128, its feet on y 251)
  asset/Originals/characters/slime-v2/page-7.json               the clips: frames, fps, looping and
      each frame's shift (where the art must be drawn relative to its cell, in cell px)

Then `tools/build_player_clips.gd -- --only=push-,pull-,grab-` (docs/TOOLING.md) builds the clips
`push-<direction>`, `pull-<direction>` and `grab-<direction>` (and the side's `-left` versions)
into the player scene; game/player/heavy_grab.gd picks them (docs/godot/SKINS.md "Heavy").

Placement: the poses meet the block where the grab stands the slime (heavy_grab.gd `_stand_point`:
the body's 30 x 26 rect 3 px off the block's 58 x 50 footprint; the blocks' art spans about 60 px
across). The side poses put their front (the push) or their snout's tip (the pull, the grip) on the
block's face, FACE_X; the back views' snout tip reaches the block's front at BACK_TIP_Y (the body
leaning back toward the camera at most BACK_LEAN_MAX); the front views' snout tip ends just past
the feet line, behind the block, the body leaning back up the screen. Every pose stands with its
ground contact centred at x 128 otherwise. A pose that would leave its cell is drawn inside it and
the shift records how far the clip's `Visual:offset` moves it back (build_player_clips.gd keys it per
frame; a side clip's mirrored `-left` version mirrors the x shift).

Scale: jelly keeps its volume, so each source sheet is scaled until its four poses cover, on
average, the same area as page 1's first idle frame of that direction.
Usage: python scripts/characters/pack-slime-heavy-grab.py
"""
from __future__ import annotations

import json
import math
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/characters/slime-v2/heavy-grab"
PAGE_OUT = ROOT / "godot/asset/characters/256x256-tile_8x8-slime-v2-page-7.webp"
MANIFEST_OUT = ROOT / "asset/Originals/characters/slime-v2/page-7.json"
PAGE_1 = ROOT / "godot/asset/characters/256x256-tile_8x8-slime-v2-page-1.webp"

CELL = 256
CENTRE_X = 128
BASELINE_Y = 251
MARGIN = 3
ALPHA_SOLID = 40
## Alpha under this is the faint glow GPT leaves around the outline: dropped.
ALPHA_GLOW = 24
GROUND_BAND = 0.15
## Cell px per world unit (the Visual's scale is 0.28125).
PX = 1.0 / 0.28125
## The body centre is 13 world units over the feet.
BODY_CENTRE_Y = BASELINE_Y - 13.0 * PX
## The block's face beside the slime: 15 (half the body) + 3 (the gap) - 1 (the art sits about a
## unit outside the footprint) + 1 (the jelly pressed a unit into it).
FACE_X = round(CENTRE_X + 18.0 * PX)
## The back view's snout tip: on the block's base front, 40 units over the body centre (the block's
## art starts 14 over it; the slime is drawn over the block's foot).
BACK_TIP_Y = round(BODY_CENTRE_Y - 40.0 * PX)
## The back view's body leans toward the camera at most this far below its feet (cell px).
BACK_LEAN_MAX = round(14.0 * PX)
## The front view's snout tip ends this far below the feet line (behind the block).
FRONT_TIP_DROP = round(4.0 * PX)

## Page 1's first idle frame per direction: (column, row).
REFERENCE_CELLS = {"down": (0, 0), "up": (0, 1), "side": (0, 2)}

## The poses on page 7: (action, direction) -> (row, first column, [(sheet, pose index in reading
## order, name)]). Indices count the sheet's 2 x 2 grid left to right, top to bottom.
LAYOUT = {
	("push", "side"): (0, 0, [("push-side-a", 0, "brace"), ("push-side-a", 1, "shove"),
		("push-side-a", 2, "step"), ("push-side-a", 3, "rest")]),
	("pull", "side"): (0, 4, [("pull-side-b", 0, "grip"), ("pull-side-b", 1, "heave"),
		("pull-side-b", 2, "tug"), ("pull-side-b", 3, "rest")]),
	# The front sheets' bottom rows turned to the side: their top rows only, from both takes.
	("push", "down"): (1, 0, [("push-down-a", 0, "brace"), ("push-down-a", 1, "shove"),
		("push-down-b", 0, "brace-b"), ("push-down-b", 1, "shove-b")]),
	("pull", "down"): (1, 4, [("pull-down-a", 0, "grip"), ("pull-down-a", 1, "heave"),
		("pull-down-a", 2, "tug"), ("pull-down-a", 3, "rest")]),
	("push", "up"): (2, 0, [("push-up-a", 0, "brace"), ("push-up-a", 1, "shove"),
		("push-up-b", 1, "shove-b"), ("push-up-a", 3, "rest")]),
	("pull", "up"): (2, 4, [("pull-up-a", 0, "grip"), ("pull-up-a", 1, "heave"),
		("pull-up-a", 2, "tug"), ("pull-up-a", 3, "rest")]),
}
## The clips: name prefix -> (action, the pose names in order, fps, looping). A push or pull loop
## runs once per cell the block moves (`puzzles.heavyBlock.moveMs` 640 = four frames at 6.25 fps);
## the grab holds the pull's grip (the mouth latched on) while the slime only holds the block.
CLIPS = {
	"push": ("push", None, 6.25, True),
	"pull": ("pull", ["heave", "tug", "heave", "tug"], 6.25, True),
	"grab": ("pull", ["grip"], 10.0, False),
}
PUSH_ORDER = {
	"side": ["brace", "shove", "step", "rest"],
	"down": ["brace", "shove", "brace-b", "shove-b"],
	"up": ["brace", "shove", "shove-b", "rest"],
}


def solid_mask(image: Image.Image) -> Image.Image:
	return image.getchannel("A").point(lambda a: 255 if a > ALPHA_SOLID else 0)


def solid_area(image: Image.Image) -> int:
	return solid_mask(image).histogram()[255]


def clean(image: Image.Image) -> Image.Image:
	r, g, b, a = image.split()
	return Image.merge("RGBA", (r, g, b, a.point(lambda v: 0 if v < ALPHA_GLOW else v)))


def components(mask: Image.Image) -> list[tuple[int, tuple[int, int, int, int]]]:
	"""The connected solid regions of `mask`: (pixel count, bbox)."""
	m = np.array(mask) > 0
	h, w = m.shape
	seen = np.zeros_like(m)
	out = []
	for y0, x0 in zip(*np.nonzero(m)):
		if seen[y0, x0]:
			continue
		queue = deque([(y0, x0)])
		seen[y0, x0] = True
		count = 0
		x_min, y_min, x_max, y_max = x0, y0, x0, y0
		while queue:
			y, x = queue.popleft()
			count += 1
			x_min, x_max = min(x_min, x), max(x_max, x)
			y_min, y_max = min(y_min, y), max(y_max, y)
			for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				ny, nx = y + dy, x + dx
				if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not seen[ny, nx]:
					seen[ny, nx] = True
					queue.append((ny, nx))
		out.append((count, (int(x_min), int(y_min), int(x_max) + 1, int(y_max) + 1)))
	return out


def poses(sheet: Image.Image) -> list[Image.Image]:
	"""The sheet's four poses in reading order: the four biggest regions, each with the small bits
	(sweat drops, puffs) nearest it. A pose may reach over the sheet's middle (a long snout)."""
	sheet = clean(sheet)
	half = sheet.resize((sheet.width // 2, sheet.height // 2), Image.BILINEAR)
	regions = sorted(components(solid_mask(half)), key=lambda c: -c[0])
	bodies = regions[:4]
	groups = [[b[1]] for b in bodies]
	for count, box in regions[4:]:
		if count < 6:
			continue
		cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2

		def gap(b: tuple[int, int, int, int]) -> float:
			dx = max(b[0] - cx, 0, cx - b[2])
			dy = max(b[1] - cy, 0, cy - b[3])
			return dx * dx + dy * dy

		groups[min(range(4), key=lambda k: gap(bodies[k][1]))].append(box)
	tops = [min(b[1] for b in g) for g in groups]
	lefts = [min(b[0] for b in g) for g in groups]
	order = sorted(range(4), key=lambda k: (round(tops[k] / (half.height / 2)), lefts[k]))
	out = []
	for k in order:
		keep = Image.new("L", sheet.size, 0)
		draw = ImageDraw.Draw(keep)
		for b in groups[k]:
			draw.rectangle((b[0] * 2 - 2, b[1] * 2 - 2, b[2] * 2 + 2, b[3] * 2 + 2), fill=255)
		piece = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
		piece.paste(sheet, (0, 0), keep)
		out.append(piece.crop(solid_mask(piece).getbbox()))
	return out


def reference_areas() -> dict[str, int]:
	page = Image.open(PAGE_1).convert("RGBA")
	areas = {}
	for direction, (col, row) in REFERENCE_CELLS.items():
		areas[direction] = solid_area(page.crop((col * CELL, row * CELL, (col + 1) * CELL, (row + 1) * CELL)))
	return areas


def band_centre_x(pose: Image.Image, bottom: bool = True) -> float:
	"""Mean x of the solid pixels in the lowest (or highest) GROUND_BAND of the pose."""
	m = np.array(solid_mask(pose)) > 0
	h = m.shape[0]
	band = max(1, int(h * GROUND_BAND))
	rows = m[h - band:] if bottom else m[:band]
	xs = np.nonzero(rows)[1]
	return float(xs.mean()) if xs.size else pose.width / 2.0


def lowest_body_centre_x(pose: Image.Image) -> float:
	"""The front view's pull: where its body stands (the widest low band above the snout tip)."""
	m = np.array(solid_mask(pose)) > 0
	widths = m.sum(axis=1)
	row = int(np.argmax(widths))
	xs = np.nonzero(m[row])[0]
	return float(xs.mean()) if xs.size else pose.width / 2.0


def wanted_top_left(pose: Image.Image, action: str, direction: str) -> tuple[float, float]:
	"""Where the pose belongs in its cell (unclamped), see the module docstring."""
	w, h = pose.size
	if direction == "side":
		return FACE_X - w, BASELINE_Y - h
	if action == "push":
		return CENTRE_X - band_centre_x(pose), BASELINE_Y - h
	if direction == "up":
		top = BACK_TIP_Y
		top = min(top, BASELINE_Y + BACK_LEAN_MAX - h)
		return CENTRE_X - band_centre_x(pose), top
	# The front view's pull: the snout tip just past the feet line, the body over it.
	return CENTRE_X - lowest_body_centre_x(pose), BASELINE_Y + FRONT_TIP_DROP - h


def place(page: Image.Image, pose: Image.Image, col: int, row: int, wanted: tuple[float, float]) -> dict:
	"""Draws the pose in its cell (inside the margins) and returns its frame and shift."""
	w, h = pose.size
	left = max(MARGIN, min(CELL - MARGIN - w, round(wanted[0])))
	top = max(MARGIN, min(CELL - MARGIN - h, round(wanted[1])))
	page.alpha_composite(pose, (col * CELL + left, row * CELL + top))
	return {"frame": row * 8 + col, "width": w, "height": h, "left": left, "top": top,
		"shift": [round(wanted[0]) - left, round(wanted[1]) - top]}


def main() -> None:
	refs = reference_areas()
	# Rows 3 and up belong to other packers (pack-slime-bow.py): kept as they are.
	page = Image.new("RGBA", (CELL * 8, CELL * 8), (0, 0, 0, 0))
	if PAGE_OUT.exists():
		old = Image.open(PAGE_OUT).convert("RGBA")
		page.paste(old.crop((0, 3 * CELL, CELL * 8, CELL * 8)), (0, 3 * CELL))
	kept = json.loads(MANIFEST_OUT.read_text(encoding="utf-8")) if MANIFEST_OUT.exists() else {}
	sheets: dict[str, list[Image.Image]] = {}
	scales: dict[str, float] = {}
	placed: dict[tuple[str, str], dict[str, dict]] = {}
	for (action, direction), (row, first_col, picks) in LAYOUT.items():
		entries = {}
		for index, (sheet_name, pose_index, name) in enumerate(picks):
			if sheet_name not in sheets:
				sheets[sheet_name] = poses(Image.open(SRC / f"{sheet_name}.png").convert("RGBA"))
				mean = sum(solid_area(p) for p in sheets[sheet_name]) / 4.0
				scales[sheet_name] = math.sqrt(refs[direction] / mean)
			k = scales[sheet_name]
			source = sheets[sheet_name][pose_index]
			pose = source.resize((max(1, round(source.width * k)), max(1, round(source.height * k))), Image.LANCZOS)
			if pose.width > CELL - 2 * MARGIN or pose.height > CELL - 2 * MARGIN:
				fit = min((CELL - 2 * MARGIN) / pose.width, (CELL - 2 * MARGIN) / pose.height)
				pose = pose.resize((round(pose.width * fit), round(pose.height * fit)), Image.LANCZOS)
				print(f"note: {sheet_name} pose {pose_index} shrunk to fit its cell ({fit:.3f})")
			entry = place(page, pose, first_col + index, row, wanted_top_left(pose, action, direction))
			entry["source"] = f"{sheet_name}#{pose_index}"
			entries[name] = entry
		placed[(action, direction)] = entries
	clips = {}
	for prefix, (action, names, fps, loop) in CLIPS.items():
		for direction in ("side", "down", "up"):
			entries = placed[(action, direction)]
			order = names if names is not None else PUSH_ORDER[direction]
			clips[f"{prefix}-{direction}"] = {
				"fps": fps,
				"loop": loop,
				"frames": [entries[n]["frame"] for n in order],
				"shifts": [entries[n]["shift"] for n in order],
				"poses": order,
			}
	manifest = {
		"cell": CELL, "baseline": BASELINE_Y, "centre_x": CENTRE_X,
		"anchors": {"face_x": FACE_X, "back_tip_y": BACK_TIP_Y, "back_lean_max": BACK_LEAN_MAX,
			"front_tip_drop": FRONT_TIP_DROP},
		"scales": {k: round(v, 4) for k, v in scales.items()},
		"poses": {f"{a}-{d}": e for (a, d), e in placed.items()},
		"clips": clips,
	}
	# Another packer's entries (the Bow's `bow-*`) stay.
	for key in ("poses", "scales", "clips"):
		for name, value in kept.get(key, {}).items():
			if name.startswith("bow-"):
				manifest[key][name] = value
	PAGE_OUT.parent.mkdir(parents=True, exist_ok=True)
	page.save(PAGE_OUT, lossless=True, method=6)
	MANIFEST_OUT.write_text(json.dumps(manifest, indent="\t") + "\n", encoding="utf-8")
	print(f"wrote {PAGE_OUT.relative_to(ROOT)} and {MANIFEST_OUT.relative_to(ROOT)}")
	for name, clip in clips.items():
		print(f"  {name}: frames {clip['frames']} shifts {clip['shifts']}")


if __name__ == "__main__":
	main()
