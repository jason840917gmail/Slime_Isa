"""Pack the Bow's body poses into the slime's page 7 (rows 3 and 4).

The Bow is the slime's own body bent into a bow (owner, 2026-11-20: "B, the body bends", turned the
right way: the belly and the face bulge toward the target, the horns sweep back, the goo string sits
behind the body and is pulled back). Sources (asset/Originals/characters/slime-v2/body-bow/, GPT 2.5
with transparent backgrounds, 2026-11-20, prompts in that folder's README): `bow-<side|down|up>.png`,
each a 2 x 2 sheet of four key poses: gather (the body stretches into two horns), drawn (the bow
bent, the string pulled back, the goo arrow's tip out of the front), release (the string snapped
straight, droplets) and recoil (back toward the round blob). Side views face right.

Outputs (page 7 is shared with the Heavy grab: scripts/characters/pack-slime-heavy-grab.py writes
rows 0-2 and keeps these rows and entries):
  godot/asset/characters/256x256-tile_8x8-slime-v2-page-7.webp  rows 3-4 redrawn
  asset/Originals/characters/slime-v2/page-7.json               `bow-<direction>` poses and scales,
      the clips `bow-draw-<direction>` (gather, drawn: held) and `bow-shot-<direction>` (release,
      recoil), each frame's shift

Then `tools/build_player_clips.gd -- --only=bow-` builds the clips into the player scene, and
game/player/abilities/bow_sequence.gd plays them (docs/godot/BODY_SHAPES.md "The Bow").

Placement: every pose keeps the body where page 1's idle of that direction stands. The body is the
pose's mask eroded (the string, the arrow and the thin horn tips drop out); its centre x lands on the
idle's, and its feet (the lowest row at least FEET_WIDTH of its widest row) on the idle's feet, so the
slime neither slides nor hops between the idle and the bow. Scale: jelly keeps its volume, so each
sheet is scaled until its four poses cover, on average, the same area as that idle frame.
Usage: python scripts/characters/pack-slime-bow.py
"""
from __future__ import annotations

import importlib.util
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/characters/slime-v2/body-bow"
_spec = importlib.util.spec_from_file_location("grab", Path(__file__).with_name("pack-slime-heavy-grab.py"))
grab = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(grab)

CELL = grab.CELL
PAGE_OUT = grab.PAGE_OUT
MANIFEST_OUT = grab.MANIFEST_OUT
## The rows this packer owns on page 7.
ROWS = (3, 4)
## direction -> (row, first column); each sheet's four poses in reading order get these names.
LAYOUT = {"side": (3, 0), "down": (3, 4), "up": (4, 0)}
POSE_NAMES = ["gather", "drawn", "release", "recoil"]
## The clips: name -> (pose names, fps, looping). Two frames over `abilities.bow.drawMs` (140): the
## draw ends on the drawn bow, held while the key is; the shot's two frames span `recoverMs` (140).
CLIPS = {
	"bow-draw": (["gather", "drawn"], 14.29, False),
	"bow-shot": (["release", "recoil"], 14.29, False),
}
## The erosion (cell px) that leaves the body without its string and arrow.
ERODE_PX = 5
## The feet: the lowest row of the body at least this share of its widest row.
FEET_WIDTH = 0.35


def body_anchor(image: Image.Image) -> tuple[float, float]:
	"""(centre x, feet y) of the image's body, in its own px."""
	mask = grab.solid_mask(image).filter(ImageFilter.MinFilter(ERODE_PX))
	m = np.array(mask) > 0
	if not m.any():
		m = np.array(grab.solid_mask(image)) > 0
	widths = m.sum(axis=1)
	rows = np.nonzero(widths >= widths.max() * FEET_WIDTH)[0]
	feet = float(rows.max() + 1)
	xs = np.nonzero(m)[1]
	return float(xs.mean()), feet


def main() -> None:
	refs = grab.reference_areas()
	page_1 = Image.open(grab.PAGE_1).convert("RGBA")
	page = Image.open(PAGE_OUT).convert("RGBA") if PAGE_OUT.exists() else Image.new("RGBA", (CELL * 8, CELL * 8))
	blank = Image.new("RGBA", (CELL * 8, CELL), (0, 0, 0, 0))
	for row in ROWS:
		page.paste(blank, (0, row * CELL))
	manifest = json.loads(MANIFEST_OUT.read_text(encoding="utf-8")) if MANIFEST_OUT.exists() else {}
	for key in ("poses", "scales", "clips"):
		manifest[key] = {k: v for k, v in manifest.get(key, {}).items() if not k.startswith("bow-")}
	placed: dict[str, dict[str, dict]] = {}
	for direction, (row, first_col) in LAYOUT.items():
		col_ref, row_ref = grab.REFERENCE_CELLS[direction]
		idle = page_1.crop((col_ref * CELL, row_ref * CELL, (col_ref + 1) * CELL, (row_ref + 1) * CELL))
		ref_x, ref_feet = body_anchor(idle)
		sheet = grab.poses(Image.open(SRC / f"bow-{direction}.png").convert("RGBA"))
		mean = sum(grab.solid_area(p) for p in sheet) / 4.0
		k = math.sqrt(refs[direction] / mean)
		manifest["scales"][f"bow-{direction}"] = round(k, 4)
		entries = {}
		for index, name in enumerate(POSE_NAMES):
			source = sheet[index]
			pose = source.resize((max(1, round(source.width * k)), max(1, round(source.height * k))), Image.LANCZOS)
			if pose.width > CELL - 2 * grab.MARGIN or pose.height > CELL - 2 * grab.MARGIN:
				fit = min((CELL - 2 * grab.MARGIN) / pose.width, (CELL - 2 * grab.MARGIN) / pose.height)
				pose = pose.resize((round(pose.width * fit), round(pose.height * fit)), Image.LANCZOS)
				print(f"note: bow-{direction} {name} shrunk to fit its cell ({fit:.3f})")
			x, feet = body_anchor(pose)
			entry = grab.place(page, pose, first_col + index, row, (ref_x - x, ref_feet - feet))
			entry["source"] = f"bow-{direction}#{index}"
			entries[name] = entry
		placed[direction] = entries
		manifest["poses"][f"bow-{direction}"] = entries
	for prefix, (names, fps, loop) in CLIPS.items():
		for direction in LAYOUT:
			entries = placed[direction]
			manifest["clips"][f"{prefix}-{direction}"] = {
				"fps": fps,
				"loop": loop,
				"frames": [entries[n]["frame"] for n in names],
				"shifts": [entries[n]["shift"] for n in names],
				"poses": names,
			}
	page.save(PAGE_OUT, lossless=True, method=6)
	MANIFEST_OUT.write_text(json.dumps(manifest, indent="\t") + "\n", encoding="utf-8")
	print(f"wrote {PAGE_OUT.relative_to(ROOT)} rows {ROWS} and {MANIFEST_OUT.relative_to(ROOT)}")
	for name, clip in manifest["clips"].items():
		if name.startswith("bow-"):
			print(f"  {name}: frames {clip['frames']} shifts {clip['shifts']}")


if __name__ == "__main__":
	main()
