"""Packs the dungeon decor set (docs/godot/PROPS.md "Dungeon decor"; 2026-10-19).

Sources: asset/Originals/dungeon-kit/decor/dungeon-decor-<sheet>-a.png, four Magnific GPT 2.5 sheets
(1:1, 1k, transparent background, the interior mushroom furniture sheet as style reference), each a
2 x 2 grid of props. Each sheet is cut along its emptiest middle column, each half along its emptiest
middle row; each picture is trimmed and scaled to its size in game units at the art density of 2 px
per unit, written to godot/asset/MAPS/objects/dungeon/decor/<name>.webp, and given its scene
godot/game/scenes/objects/dungeon-decor/<name>.tscn (a scenery scene: no gameplay script, so the
prop palette builder lists it under "dungeon decor"). A scene is rewritten only when it is missing,
so hand tuning in the editor stays; --scenes rewrites them all.

- solid: a StaticBody2D whose foot box (COLLIDE_W of the picture's width, its depth from the
  picture) blocks; the root at the bottom middle.
- free: a Node2D, nothing blocks (hung or slim things: chains, shackles, cage, candelabra).
- floor: a Node2D whose root is near the picture's top edge, so whatever stands on it sorts above
  it (grate, bones).

    python scripts/art/pack-dungeon-decor-art.py [--scenes]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/dungeon-kit/decor"
ART = ROOT / "godot/asset/MAPS/objects/dungeon/decor"
SCENES = ROOT / "godot/game/scenes/objects/dungeon-decor"
ART_RES = "res://asset/MAPS/objects/dungeon/decor"
ALPHA_CUT = 40
PX_PER_UNIT = 2
COLLIDE_W = 0.8
# the root of a floor prop: this many units below the picture's top
FLOOR_ROOT = 12

# sheet -> its four props (top left, top right, bottom left, bottom right):
# (name, size in units, "h" for a height or "w" for a width, kind, foot depth in units for solid)
SHEETS = {
	"iron": [
		("hanging-chains", 70, "h", "free", 0),
		("wall-shackles", 60, "h", "free", 0),
		("hanging-cage", 72, "h", "free", 0),
		("weapon-rack", 96, "h", "solid", 18),
	],
	"furniture": [
		("guard-table", 84, "w", "solid", 34),
		("guard-bench", 92, "w", "solid", 22),
		("barrel-stack", 84, "w", "solid", 34),
		("broken-crates", 80, "w", "solid", 26),
	],
	"stone": [
		("sarcophagus", 104, "w", "solid", 40),
		("broken-pillar", 96, "h", "solid", 30),
		("bone-pile", 64, "w", "floor", 0),
		("worm-head-statue", 84, "h", "solid", 30),
	],
	"misc": [
		("candelabra", 96, "h", "free", 0),
		("bookshelf", 112, "h", "solid", 20),
		("floor-grate", 72, "w", "floor", 0),
		("stalagmites", 96, "h", "solid", 26),
	],
}


def emptiest(profile: np.ndarray, lo: float = 0.35, hi: float = 0.65) -> int:
	"""The index with the least alpha in the middle band of a profile."""
	a, b = int(len(profile) * lo), int(len(profile) * hi)
	return a + int(np.argmin(profile[a:b]))


def quarters(image: Image.Image) -> list[Image.Image]:
	alpha = np.asarray(image.getchannel("A"), dtype=np.float64)
	alpha[alpha <= ALPHA_CUT] = 0
	x = emptiest(alpha.sum(axis=0))
	out = []
	for left, right in ((0, x), (x, image.width)):
		y = emptiest(alpha[:, left:right].sum(axis=1))
		out.append((left, right, y))
	tl = image.crop((out[0][0], 0, out[0][1], out[0][2]))
	tr = image.crop((out[1][0], 0, out[1][1], out[1][2]))
	bl = image.crop((out[0][0], out[0][2], out[0][1], image.height))
	br = image.crop((out[1][0], out[1][2], out[1][1], image.height))
	return [tl, tr, bl, br]


def cut(image: Image.Image) -> Image.Image:
	"""Keeps the biggest opaque part's box and clears the faint alpha noise round it."""
	alpha = image.getchannel("A").point(lambda a: a if a > ALPHA_CUT else 0)
	image.putalpha(alpha)
	return image.crop(alpha.getbbox())


def scene_text(name: str, width: int, height: int, kind: str, depth: int) -> str:
	units_w = width / PX_PER_UNIT
	offset_y = -FLOOR_ROOT * PX_PER_UNIT if kind == "floor" else -height
	visual = (
		'[node name="Visual" type="Sprite2D" parent="."]\n'
		"scale = Vector2(0.5, 0.5)\n"
		"centered = false\n"
		f"offset = Vector2({-width / 2:g}, {offset_y:g})\n"
		'script = ExtResource("sheet")\n'
		f'sheet_path = "{ART_RES}/{name}.webp"\n'
	)
	head = '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://game/runtime/sheet_sprite.gd" id="sheet"]\n\n'
	if kind != "solid":
		return head + f'[node name="{name}" type="Node2D"]\ny_sort_enabled = true\n\n' + visual
	box_w = round(units_w * COLLIDE_W)
	return (
		head
		+ f'[sub_resource type="RectangleShape2D" id="foot"]\nsize = Vector2({box_w}, {depth})\n\n'
		+ f'[node name="{name}" type="StaticBody2D"]\ny_sort_enabled = true\ncollision_mask = 0\n\n'
		+ f'[node name="BodyShape" type="CollisionShape2D" parent="."]\nposition = Vector2(0, {-depth / 2:g})\nshape = SubResource("foot")\n\n'
		+ visual
	)


def main() -> None:
	rewrite = "--scenes" in sys.argv
	ART.mkdir(parents=True, exist_ok=True)
	SCENES.mkdir(parents=True, exist_ok=True)
	for sheet, props in SHEETS.items():
		image = Image.open(SRC / f"dungeon-decor-{sheet}-a.png").convert("RGBA")
		for part, (name, units, along, kind, depth) in zip(quarters(image), props):
			picture = cut(part)
			target = units * PX_PER_UNIT
			factor = target / (picture.height if along == "h" else picture.width)
			picture = picture.resize((max(1, round(picture.width * factor)), max(1, round(picture.height * factor))), Image.LANCZOS)
			picture.save(ART / f"{name}.webp", "WEBP", lossless=True)
			scene = SCENES / f"{name}.tscn"
			if rewrite or not scene.exists():
				scene.write_text(scene_text(name, picture.width, picture.height, kind, depth), encoding="utf-8", newline="\n")
			print(f"{name}: {picture.width} x {picture.height} px ({kind})")


if __name__ == "__main__":
	main()
