"""Packs the town set: houses, town buildings, garden pieces and street props (docs/godot/PROPS.md
"Town"; 2026-11-01, the West village).

Sources: asset/Originals/town/concepts/<sheet>-a.png, Magnific GPT 2.5 concept sheets (transparent
background, the interior mushroom furniture sheet as style reference) the owner picked, each a grid
of separate pictures, and <sheet>-a-up.jpg, the same sheet through Magnific's Precision upscaler
(2x, no alpha): its colour is used under the original's alpha, scaled 2x. A sheet without an
upscale uses its own colour. Each sheet is cut along its emptiest lines near the grid's lines; each
picture is trimmed and scaled to its size in game units at the art density of 2 px per unit and
written to godot/asset/MAPS/town/<group>/<name>.webp, with its scene
godot/game/scenes/objects/town/<group>/<name>.tscn (a scenery scene: no gameplay script, so the prop
palette builder lists it, the houses under "houses", the rest under "town" and "garden"). A scene
is rewritten only when it is missing, so hand tuning in the editor stays; --scenes rewrites them all.

- solid: a StaticBody2D whose foot box blocks (its width and depth in units, or for a building
  BUILDING_FOOT of its picture); the root at the bottom middle.
- free: a Node2D, nothing blocks.
- floor: a Node2D whose root is FLOOR_ROOT units below the picture's top, so whatever stands on it
  sorts above it (beds, patches, gravel, stepping stones).

Ambient loops (docs/assets/AMBIENT_ANIMATION.md, tier 1, procedural): a picture with an `ambient`
kind is written as 8 frames side by side and its scene plays them (AnimationPlayer "idle", random
start): `goo` shimmers the lime goo, `glow` also pulses it, `laundry` sways the cloth under the
line, `bees` flies the bees round the hive, `bath` shimmers the goo and sways the steam over it. The
frames move only those pixels.

A building with several homes (the duplex, the triplex row, the two flats, the twin mushroom house,
the town hall, the bathhouse) has a Marker2D `door-1`, `door-2` ... at the foot of each door (an
upper flat's: at the foot of its stair), where a door node (game/scripts/door.gd) goes, one per home.
The owner turned down the apartment house and the manor of the `large` sheet (2026-11-01).

    python scripts/art/pack-town-art.py [--scenes] [--only=<sheet>,...]
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from game_webp import save_game_webp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/town/concepts"
ART = ROOT / "godot/asset/MAPS/town"
SCENES = ROOT / "godot/game/scenes/objects/town"
ART_RES = "res://asset/MAPS/town"
ALPHA_CUT = 40
PX_PER_UNIT = 2
FLOOR_ROOT = 12
FRAMES = 8
# a building's foot box: this share of its picture's width, and of its height for the depth
BUILDING_FOOT = (0.86, 0.4)

# sheet -> (columns, rows, group, pictures in reading order; None: a picture not used)
# a picture: (name, size in units, "w" or "h" for what the size measures, kind, foot box in units
# (None: a building's), ambient kind, frames per second)
SHEETS = {
	"multi": (2, 2, "houses", [
		("duplex", 300, "w", "solid", None, "", 0),
		("triplex-row", 340, "w", "solid", None, "", 0),
		("two-flats", 230, "w", "solid", None, "", 0),
		("twin-mushroom-house", 300, "w", "solid", None, "", 0),
	]),
	"large": (2, 2, "houses", [
		("town-hall", 480, "w", "solid", None, "goo", 5),
		None,
		None,
		("goo-bathhouse", 420, "w", "solid", None, "bath", 6),
	]),
	"houses": (3, 2, "houses", [
		("jelly-dome-house", 220, "w", "solid", None, "goo", 5),
		("pumpkin-house", 230, "w", "solid", None, "", 0),
		("stump-house", 250, "w", "solid", None, "", 0),
		("snail-shell-house", 240, "w", "solid", None, "", 0),
		("timber-townhouse", 190, "w", "solid", None, "", 0),
		("drop-thatch-cottage", 230, "w", "solid", None, "", 0),
	]),
	"civic": (2, 2, "houses", [
		("general-store", 300, "w", "solid", None, "", 0),
		("inn", 360, "w", "solid", None, "", 0),
		("gatekeeper-house", 300, "w", "solid", None, "", 0),
		("game-booth", 280, "w", "solid", None, "", 0),
	]),
	"garden": (4, 3, "garden", [
		("cabbage-bed", 120, "w", "floor", None, "", 0),
		("carrot-bed", 120, "w", "floor", None, "", 0),
		("pumpkin-patch", 120, "w", "floor", None, "", 0),
		("tulip-bed", 100, "w", "floor", None, "", 0),
		("hedge", 128, "w", "solid", (124, 26), "", 0),
		("hedge-corner", 128, "w", "solid", (100, 40), "", 0),
		("picket-fence", 128, "w", "solid", (124, 10), "", 0),
		("gravel-square", 120, "w", "floor", None, "", 0),
		("stepping-stones", 96, "w", "floor", None, "", 0),
		("herb-planter", 84, "w", "solid", (76, 30), "", 0),
		("berry-bush", 72, "w", "solid", (56, 26), "", 0),
		("scarecrow", 88, "h", "solid", (16, 10), "", 0),
	]),
	"props": (4, 4, "props", [
		("goo-fountain", 150, "w", "solid", (130, 56), "goo", 8),
		("market-stall", 120, "w", "solid", (104, 34), "", 0),
		("signpost", 88, "h", "solid", (14, 10), "", 0),
		("notice-board", 100, "w", "solid", (84, 14), "", 0),
		("goo-lamp", 96, "h", "solid", (14, 10), "glow", 6),
		("barrels", 70, "w", "solid", (62, 30), "", 0),
		("crates", 72, "w", "solid", (62, 30), "", 0),
		("bench", 84, "w", "solid", (72, 18), "", 0),
		("flower-cart", 92, "w", "solid", (70, 24), "", 0),
		("mailbox", 56, "h", "solid", (14, 10), "", 0),
		("slime-statue", 80, "h", "solid", (44, 22), "", 0),
		("clothesline", 128, "w", "free", None, "laundry", 5),
		("wheelbarrow", 80, "w", "solid", (56, 20), "", 0),
		("rain-barrel", 80, "h", "solid", (40, 24), "", 0),
		("beehive", 64, "h", "solid", (36, 18), "bees", 10),
		("water-trough", 100, "w", "solid", (90, 26), "", 0),
	]),
}

# building -> the foot of each of its doors, as shares of its picture's width and height (from the
# top-left corner)
DOORS: dict[str, list[tuple[float, float]]] = {
	"duplex": [(0.31, 0.97), (0.73, 0.97)],
	"triplex-row": [(0.25, 0.97), (0.55, 0.97), (0.85, 0.97)],
	# the ground flat's door, then the foot of the upper flat's stair
	"two-flats": [(0.26, 0.97), (0.86, 0.95)],
	"twin-mushroom-house": [(0.25, 0.97), (0.69, 0.97)],
	"town-hall": [(0.52, 0.98)],
	"goo-bathhouse": [(0.45, 0.97)],
}


def splits(profile: np.ndarray, parts: int) -> list[int]:
	"""The cuts between `parts` pictures: the emptiest index near each grid line."""
	n = len(profile)
	cuts = [0]
	for i in range(1, parts):
		centre = n * i // parts
		span = n // (parts * 4)
		cuts.append(centre - span + int(np.argmin(profile[centre - span:centre + span])))
	cuts.append(n)
	return cuts


def load_sheet(stem: str) -> Image.Image:
	"""The sheet at 2x: the upscale's colour under the original's alpha (the original alone when
	there is no upscale)."""
	original = Image.open(SRC / f"{stem}-a.png").convert("RGBA")
	upscale_path = SRC / f"{stem}-a-up.jpg"
	if not upscale_path.exists():
		return original
	colour = Image.open(upscale_path).convert("RGB")
	alpha = original.getchannel("A").resize(colour.size, Image.LANCZOS)
	colour.putalpha(alpha)
	return colour


def pictures(sheet: Image.Image, cols: int, rows: int) -> list[Image.Image]:
	alpha = np.asarray(sheet.getchannel("A"), dtype=np.float64)
	mask = alpha > ALPHA_CUT
	xs = splits(mask.sum(axis=0), cols)
	# each column's own row cuts: a tall picture in the next column must not cut through this one
	ys = [splits(mask[:, xs[c]:xs[c + 1]].sum(axis=1), rows) for c in range(cols)]
	out = []
	for r in range(rows):
		for c in range(cols):
			part = sheet.crop((xs[c], ys[c][r], xs[c + 1], ys[c][r + 1]))
			cut_alpha = part.getchannel("A").point(lambda a: a if a > ALPHA_CUT else 0)
			part.putalpha(cut_alpha)
			out.append(part.crop(cut_alpha.getbbox()))
	return out


# --- ambient frames -------------------------------------------------------------------------------

def hsv(array: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
	rgb = array[..., :3] / 255.0
	mx, mn = rgb.max(axis=2), rgb.min(axis=2)
	v = mx
	s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
	r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
	d = np.maximum(mx - mn, 1e-6)
	h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
	return h, s, v


def goo_mask(array: np.ndarray) -> np.ndarray:
	"""The bright lime goo (not the darker leaves)."""
	h, s, v = hsv(array)
	return (h > 55) & (h < 100) & (s > 0.45) & (v > 0.55) & (array[..., 3] > 0)


def goo_frames(picture: Image.Image, pulse: float) -> list[Image.Image]:
	base = np.asarray(picture, dtype=np.float64)
	mask = goo_mask(base)
	height, width = mask.shape
	yy, xx = np.mgrid[0:height, 0:width]
	frames = []
	for k in range(FRAMES):
		t = 2 * math.pi * k / FRAMES
		# slow bands drifting across the goo, and the whole goo breathing with `pulse`
		wave = 0.10 * np.sin(t + (xx * 0.9 + yy * 0.6) * 2 * math.pi / max(width, 1) * 3)
		gain = 1.0 + wave + pulse * math.sin(t)
		frame = base.copy()
		frame[..., :3] = np.where(mask[..., None], np.clip(base[..., :3] * gain[..., None], 0, 255), base[..., :3])
		frames.append(Image.fromarray(frame.astype(np.uint8), "RGBA"))
	return frames


def laundry_frames(picture: Image.Image) -> list[Image.Image]:
	"""The cloth below the line swings sideways, more the lower it hangs; posts and line stay."""
	base = np.asarray(picture)
	height, width = base.shape[:2]
	line = int(height * 0.22)
	left, right = int(width * 0.17), int(width * 0.83)
	frames = []
	for k in range(FRAMES):
		t = 2 * math.pi * k / FRAMES
		frame = base.copy()
		band = base[line:, left:right].copy()
		out = np.zeros_like(band)
		for y in range(band.shape[0]):
			depth = y / max(band.shape[0] - 1, 1)
			shift = int(round(3.0 * depth * math.sin(t + depth * 0.8)))
			out[y] = np.roll(band[y], shift, axis=0)
		frame[line:, left:right] = out
		frames.append(Image.fromarray(frame, "RGBA"))
	return frames


def components(mask: np.ndarray) -> list[np.ndarray]:
	"""The 8-connected parts of a mask, each as an array of (y, x)."""
	seen = np.zeros_like(mask, dtype=bool)
	out = []
	height, width = mask.shape
	for y0, x0 in zip(*np.nonzero(mask)):
		if seen[y0, x0]:
			continue
		stack = [(y0, x0)]
		seen[y0, x0] = True
		part = []
		while stack:
			y, x = stack.pop()
			part.append((y, x))
			for dy in (-1, 0, 1):
				for dx in (-1, 0, 1):
					ny, nx = y + dy, x + dx
					if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
						seen[ny, nx] = True
						stack.append((ny, nx))
		out.append(np.array(part))
	return out


def bee_frames(picture: Image.Image) -> list[Image.Image]:
	"""Each bee (a small part apart from the hive) flies a little loop of its own."""
	base = np.asarray(picture)
	parts = components(base[..., 3] > ALPHA_CUT)
	parts.sort(key=len, reverse=True)
	bees = [p for p in parts[1:] if len(p) < len(parts[0]) * 0.05]
	still = base.copy()
	for bee in bees:
		still[bee[:, 0], bee[:, 1]] = 0
	frames = []
	for k in range(FRAMES):
		frame = still.copy()
		for i, bee in enumerate(bees):
			t = 2 * math.pi * k / FRAMES + i * 2.1
			dx, dy = int(round(2.5 * math.cos(t))), int(round(1.8 * math.sin(2 * t)))
			ys = np.clip(bee[:, 0] + dy, 0, base.shape[0] - 1)
			xs = np.clip(bee[:, 1] + dx, 0, base.shape[1] - 1)
			frame[ys, xs] = base[bee[:, 0], bee[:, 1]]
		frames.append(Image.fromarray(frame, "RGBA"))
	return frames


## the steam: the rows above this share of the picture's height (above the chimneys' tops)
STEAM_TOP = 0.2


def steam_frames(frames: list[Image.Image]) -> list[Image.Image]:
	"""The steam over the chimneys sways sideways, more the higher it rises (whole rows, so its
	outline moves with it; nothing at the chimneys' tops moves)."""
	out = []
	for k, picture in enumerate(frames):
		base = np.asarray(picture)
		top = int(base.shape[0] * STEAM_TOP)
		frame = base.copy()
		t = 2 * math.pi * k / FRAMES
		for y in range(top):
			rise = 1 - y / max(top - 1, 1)
			shift = int(round(3.0 * rise * math.sin(t + rise * 2.2)))
			if shift:
				frame[y] = np.roll(base[y], shift, axis=0)
		out.append(Image.fromarray(frame, "RGBA"))
	return out


def ambient_strip(picture: Image.Image, ambient: str) -> Image.Image:
	if ambient == "goo":
		frames = goo_frames(picture, 0.0)
	elif ambient == "bath":
		frames = steam_frames(goo_frames(picture, 0.0))
	elif ambient == "glow":
		frames = goo_frames(picture, 0.12)
	elif ambient == "laundry":
		frames = laundry_frames(picture)
	elif ambient == "bees":
		frames = bee_frames(picture)
	else:
		raise ValueError(ambient)
	strip = Image.new("RGBA", (picture.width * FRAMES, picture.height), (0, 0, 0, 0))
	for k, frame in enumerate(frames):
		strip.alpha_composite(frame, (k * picture.width, 0))
	return strip


# --- scenes ---------------------------------------------------------------------------------------

def door_markers(name: str, width: int, height: int) -> str:
	"""A Marker2D at the foot of each of the building's doors (the root is its bottom middle)."""
	text = ""
	for i, (fx, fy) in enumerate(DOORS.get(name, [])):
		x = (fx - 0.5) * width / PX_PER_UNIT
		y = -(1 - fy) * height / PX_PER_UNIT
		text += f'\n[node name="door-{i + 1}" type="Marker2D" parent="."]\nposition = Vector2({x:.0f}, {y:.0f})\n'
	return text


def scene_text(group: str, name: str, width: int, height: int, kind: str, foot: tuple[int, int] | None,
		ambient: str, fps: int) -> str:
	offset_y = -FLOOR_ROOT * PX_PER_UNIT if kind == "floor" else -height
	frames = f"hframes = {FRAMES}\n" if ambient else ""
	visual = (
		'[node name="Visual" type="Sprite2D" parent="."]\n'
		"scale = Vector2(0.5, 0.5)\n"
		"centered = false\n"
		f"offset = Vector2({-width / 2:g}, {offset_y:g})\n"
		+ frames
		+ 'script = ExtResource("sheet")\n'
		f'sheet_path = "{ART_RES}/{group}/{name}.webp"\n'
	)
	resources = '[ext_resource type="Script" path="res://game/runtime/sheet_sprite.gd" id="sheet"]\n'
	subs = ""
	player = ""
	if ambient:
		resources += '[ext_resource type="Script" path="res://game/runtime/animation_player.gd" id="player"]\n'
		step = 1.0 / fps
		times = ", ".join(f"{k * step:g}" for k in range(FRAMES))
		subs += (
			'[sub_resource type="Animation" id="idle"]\n'
			'resource_name = "object.ambient.idle"\n'
			f"length = {FRAMES * step:g}\n"
			"loop_mode = 1\n"
			f"step = {step:g}\n"
			'tracks/0/type = "value"\n'
			"tracks/0/imported = false\n"
			"tracks/0/enabled = true\n"
			'tracks/0/path = NodePath("Visual:frame")\n'
			"tracks/0/interp = 1\n"
			"tracks/0/loop_wrap = false\n"
			"tracks/0/keys = {\n"
			f'"times": PackedFloat32Array({times}),\n'
			f'"transitions": PackedFloat32Array({", ".join(["1"] * FRAMES)}),\n'
			'"update": 1,\n'
			f'"values": [{", ".join(str(k) for k in range(FRAMES))}]\n'
			"}\n\n"
			'[sub_resource type="AnimationLibrary" id="library"]\n'
			'_data = {\n&"object.ambient.idle": SubResource("idle")\n}\n\n'
		)
		player = (
			'\n[node name="AmbientAnimation" type="AnimationPlayer" parent="."]\n'
			"process_mode = 3\n"
			'libraries/ = SubResource("library")\n'
			'autoplay = &"object.ambient.idle"\n'
			'script = ExtResource("player")\n'
			"randomize_start = true\n"
		)
	head = "[gd_scene format=3]\n\n" + resources + "\n"
	if kind != "solid":
		return head + subs + f'[node name="{name}" type="Node2D"]\ny_sort_enabled = true\n\n' + visual + player
	units_w, units_h = width / PX_PER_UNIT, height / PX_PER_UNIT
	box_w, depth = foot if foot else (round(units_w * BUILDING_FOOT[0]), round(units_h * BUILDING_FOOT[1]))
	return (
		head
		+ subs
		+ f'[sub_resource type="RectangleShape2D" id="foot"]\nsize = Vector2({box_w}, {depth})\n\n'
		+ f'[node name="{name}" type="StaticBody2D"]\ny_sort_enabled = true\ncollision_mask = 0\n\n'
		+ f'[node name="BodyShape" type="CollisionShape2D" parent="."]\nposition = Vector2(0, {-depth / 2:g})\nshape = SubResource("foot")\n\n'
		+ visual
		+ player
		+ door_markers(name, width, height)
	)


def main() -> None:
	rewrite = "--scenes" in sys.argv
	only = [arg.split("=", 1)[1].split(",") for arg in sys.argv if arg.startswith("--only=")]
	for stem, (cols, rows, group, items) in SHEETS.items():
		if only and stem not in only[0]:
			continue
		(ART / group).mkdir(parents=True, exist_ok=True)
		(SCENES / group).mkdir(parents=True, exist_ok=True)
		for picture, item in zip(pictures(load_sheet(stem), cols, rows), items):
			if item is None:
				continue
			name, units, along, kind, foot, ambient, fps = item
			target = units * PX_PER_UNIT
			factor = target / (picture.height if along == "h" else picture.width)
			picture = picture.convert("RGBa").resize(
				(max(1, round(picture.width * factor)), max(1, round(picture.height * factor))), Image.LANCZOS).convert("RGBA")
			out = ambient_strip(picture, ambient) if ambient else picture
			save_game_webp(out, ART / group / f"{name}.webp")
			scene = SCENES / group / f"{name}.tscn"
			if rewrite or not scene.exists():
				scene.write_text(scene_text(group, name, picture.width, picture.height, kind, foot, ambient, fps),
					encoding="utf-8", newline="\n")
			print(f"{group}/{name}: {picture.width} x {picture.height} px ({kind}{', ' + ambient if ambient else ''})")


if __name__ == "__main__":
	main()
