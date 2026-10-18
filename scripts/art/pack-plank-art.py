"""Packs the plank bridge's art (docs/godot/DUNGEONS.md "Falling planks over water" and "Art").

Source: asset/Originals/dungeon-kit/generated/plank.png (Magnific GPT 2.5, transparent background,
the Lili creation as style reference, 2026-10-17): two square tiles of a rope footbridge's deck seen
from above, side by side: whole honey-wood planks with iron nails (left) and the same planks old,
cracked, split and loose with frayed twine (right). Writes
godot/asset/MAPS/objects/dungeon/plank-2x1.webp: the two tiles, each trimmed to its own painting
and fitted to one 64-unit cell at 2 px a unit (128 x 128 px): frame 0 the landing's whole plank,
frame 1 the falling plank. The boards run across the picture (east-west): the game turns it for a
bridge that runs east-west.

    python scripts/art/pack-plank-art.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/dungeon-kit/generated/plank.png"
OUT = ROOT / "godot/asset/MAPS/objects/dungeon/plank-2x1.webp"
ALPHA_CUT = 40
PX = 2
CELL_UNITS = 64


def main() -> None:
	image = Image.open(SRC).convert("RGBA")
	half = image.width // 2
	side = CELL_UNITS * PX
	sheet = Image.new("RGBA", (side * 2, side), (0, 0, 0, 0))
	for i in range(2):
		panel = image.crop((i * half, 0, (i + 1) * half, image.height))
		box = panel.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0).getbbox()
		tile = panel.crop(box).resize((side, side), Image.LANCZOS)
		sheet.alpha_composite(tile, (i * side, 0))
		print(f"  frame {i}: painting {box[2] - box[0]} x {box[3] - box[1]} px -> {side} x {side}")
	OUT.parent.mkdir(parents=True, exist_ok=True)
	sheet.save(OUT, "WEBP", lossless=True)
	print(f"{OUT.relative_to(ROOT)}  {sheet.width} x {sheet.height}")


if __name__ == "__main__":
	main()
