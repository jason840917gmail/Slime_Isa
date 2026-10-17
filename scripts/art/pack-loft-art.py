"""Packs the Weaver Hollow's Spinning Loft dressing (docs/godot/DUNGEONS.md "The Weaver Hollow";
the rework plan docs/design/2026-10-17-pearl-mid-dungeon.md "C4 the Spinning Loft": "the loft's
dressing (silk rafters)").

Sources: asset/Originals/weaver-hollow/loft/ (Magnific GPT 2.5, transparent background, the Lili
creation as the style reference; prompts in its README.md): loft-dressing-a.png, four props in a
2 x 2 grid, each cut from its quarter by its alpha; brood-altar-a.png, the Hoard's altar for Pearl 2.
Each is trimmed, scaled to its size in the game at 2 px per game unit (the art density: 128 px per
64-unit cell) and saved in godot/asset/MAPS/props/weaver-hollow/ (loft-<name>.webp,
brood-altar.webp), drawn by godot/game/scenes/objects/weaver-hollow/<same name>.tscn at 0.5.

    python scripts/art/pack-loft-art.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "asset/Originals/weaver-hollow/loft/loft-dressing-a.png"
ALTAR_SOURCE = ROOT / "asset/Originals/weaver-hollow/loft/brood-altar-a.png"
## The altar's height in game units (the Lair's worm altar is 112).
ALTAR_UNITS_TALL = 120
OUT = ROOT / "godot/asset/MAPS/props/weaver-hollow"
ALPHA_CUT = 12
## [name, quarter (column, row), width in game units]
PIECES = [
	("rafter", (0, 0), 256),
	("peg-rail", (1, 0), 176),
	("spool", (0, 1), 64),
	("spinning-wheel", (1, 1), 112),
]


def main() -> None:
	sheet = Image.open(SOURCE).convert("RGBA")
	half_w, half_h = sheet.width // 2, sheet.height // 2
	OUT.mkdir(parents=True, exist_ok=True)
	for name, (column, row), units in PIECES:
		quarter = sheet.crop((column * half_w, row * half_h, (column + 1) * half_w, (row + 1) * half_h))
		alpha = quarter.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0)
		piece = quarter.crop(alpha.getbbox())
		width = units * 2
		height = round(piece.height * width / piece.width)
		piece = piece.resize((width, height), Image.LANCZOS)
		path = OUT / f"loft-{name}.webp"
		piece.save(path, "WEBP", lossless=True)
		print(f"{path.name}: {width} x {height} px ({units} x {height / 2:.0f} units)")
	altar = Image.open(ALTAR_SOURCE).convert("RGBA")
	altar = altar.crop(altar.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0).getbbox())
	height = ALTAR_UNITS_TALL * 2
	width = round(altar.width * height / altar.height)
	altar = altar.resize((width, height), Image.LANCZOS)
	altar.save(OUT / "brood-altar.webp", "WEBP", lossless=True)
	print(f"brood-altar.webp: {width} x {height} px")


if __name__ == "__main__":
	main()
