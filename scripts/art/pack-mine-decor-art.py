"""Packs the Mine's dressing props into the dungeon decor set (docs/godot/PROPS.md "Dungeon decor";
2026-11-25, the rebuilt Crystal Mine's missing art).

Source: asset/Originals/mine/mine-props-e.png, one Magnific GPT 2.5 still (2:1, 1536 x 768,
transparent), eight props on an uneven 4 x 2 grid. Each prop is cut at its box (asset/Originals/mine/
README.md: the rows split at y 399, a gap in each column), its faint glow pixels cleared (alpha 16 and
below), trimmed, and scaled by 0.61 (the game mine cart's packing scale, so every prop fits a 256 cell
and the tipped cart matches the standing one), then written as the dungeon decor set's pictures are
(scripts/art/pack-dungeon-decor-art.py): godot/asset/MAPS/objects/dungeon/decor/<name>.webp at 2 px a
unit, and its scene godot/game/scenes/objects/dungeon-decor/<name>.tscn (a scenery scene, no gameplay
script, so the prop palette builder lists it under "dungeon decor"). A scene is written only when it
is missing, so hand tuning in the editor stays; --scenes rewrites them all.

Kinds (the root at the picture's bottom middle, y-sorted by it):
- solid: a StaticBody2D whose foot box (FOOT_W of the picture's width, `depth` units deep) blocks.
- frame: a StaticBody2D with a small box at each leg (`depth` deep, LEG_W wide, LEG_IN in from each
  side): the slime walks between the legs and, north of the root, behind it (the pit-prop set, the
  lift gantry).
- free: a Node2D, nothing blocks (the ladder's foot against a wall).

    python scripts/art/pack-mine-decor-art.py [--scenes]
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/mine/mine-props-e.png"
ART = ROOT / "godot/asset/MAPS/objects/dungeon/decor"
SCENES = ROOT / "godot/game/scenes/objects/dungeon-decor"
ART_RES = "res://asset/MAPS/objects/dungeon/decor"
ALPHA_CUT = 16
SCALE = 0.61
PX_PER_UNIT = 2
FOOT_W = 0.8
LEG_W = 16
LEG_IN = 14

# name, box (x0, y0, x1, y1 in the source), kind, foot or leg depth (units)
PROPS = [
	("mine-pit-props", (42, 59, 373, 381), "frame", 12),
	("mine-ladder-foot", (461, 53, 677, 391), "free", 0),
	("mine-lift-gantry", (787, 25, 1111, 393), "frame", 12),
	("mine-spare-props", (1167, 127, 1502, 389), "solid", 30),
	("mine-slate-heap", (42, 456, 381, 736), "solid", 34),
	("mine-lantern-post", (499, 405, 672, 730), "solid", 14),
	("mine-tipped-cart", (761, 464, 1103, 733), "solid", 36),
	("mine-tools-crate", (1236, 436, 1468, 734), "solid", 26),
]


def cut(image: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
	part = image.crop(box)
	alpha = part.getchannel("A").point(lambda a: a if a > ALPHA_CUT else 0)
	part.putalpha(alpha)
	return part.crop(alpha.getbbox())


def scene_text(name: str, width: int, height: int, kind: str, depth: int) -> str:
	units_w = width / PX_PER_UNIT
	visual = (
		'[node name="Visual" type="Sprite2D" parent="."]\n'
		"scale = Vector2(0.5, 0.5)\n"
		"centered = false\n"
		f"offset = Vector2({-width / 2:g}, {-height:g})\n"
		'script = ExtResource("sheet")\n'
		f'sheet_path = "{ART_RES}/{name}.webp"\n'
	)
	head = '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://game/runtime/sheet_sprite.gd" id="sheet"]\n\n'
	if kind == "free":
		return head + f'[node name="{name}" type="Node2D"]\ny_sort_enabled = true\n\n' + visual
	body = f'[node name="{name}" type="StaticBody2D"]\ny_sort_enabled = true\ncollision_mask = 0\n\n'
	if kind == "solid":
		box_w = round(units_w * FOOT_W)
		return (
			head
			+ f'[sub_resource type="RectangleShape2D" id="foot"]\nsize = Vector2({box_w}, {depth})\n\n'
			+ body
			+ f'[node name="BodyShape" type="CollisionShape2D" parent="."]\nposition = Vector2(0, {-depth / 2:g})\nshape = SubResource("foot")\n\n'
			+ visual
		)
	leg_x = units_w / 2 - LEG_IN
	return (
		head
		+ f'[sub_resource type="RectangleShape2D" id="leg"]\nsize = Vector2({LEG_W}, {depth})\n\n'
		+ body
		+ f'[node name="LegWest" type="CollisionShape2D" parent="."]\nposition = Vector2({-leg_x:g}, {-depth / 2:g})\nshape = SubResource("leg")\n\n'
		+ f'[node name="LegEast" type="CollisionShape2D" parent="."]\nposition = Vector2({leg_x:g}, {-depth / 2:g})\nshape = SubResource("leg")\n\n'
		+ visual
	)


def main() -> None:
	rewrite = "--scenes" in sys.argv
	ART.mkdir(parents=True, exist_ok=True)
	SCENES.mkdir(parents=True, exist_ok=True)
	sheet = Image.open(SRC).convert("RGBA")
	for name, box, kind, depth in PROPS:
		picture = cut(sheet, box)
		picture = picture.resize((max(1, round(picture.width * SCALE)), max(1, round(picture.height * SCALE))), Image.LANCZOS)
		picture.save(ART / f"{name}.webp", "WEBP", lossless=True)
		scene = SCENES / f"{name}.tscn"
		if rewrite or not scene.exists():
			scene.write_text(scene_text(name, picture.width, picture.height, kind, depth), encoding="utf-8", newline="\n")
		print(f"{name}: {picture.width} x {picture.height} px ({kind})")


if __name__ == "__main__":
	main()
