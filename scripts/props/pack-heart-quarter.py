"""Packs the heart quarter's four fill levels (owner pick 2026-10-27: the filling glass vessel, 2A)
into one runtime sheet: frame N shows the vessel N+1 quarters full (frame 3 = a whole heart).

Sources: asset/Originals/props/heart-quarter/ (Magnific GPT 2.5 generations; the ideas sheet and
the other candidates are kept beside them). Output: godot/asset/MAPS/props/256x256-tile_4x1-heart-quarter.webp,
each picture fitted into the cell and stood on its bottom edge (game/scripts/goo_heart.gd picks the
frame; goo-heart.tscn draws it).
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset" / "Originals" / "props" / "heart-quarter"
OUT = ROOT / "godot" / "asset" / "MAPS" / "props" / "256x256-tile_4x1-heart-quarter.webp"
# One quarter, half, three quarters, full.
FRAMES = ["2a.png", "half-a.png", "three-a.png", "full-a.png"]
CELL = 256
FIT = 236


def main() -> None:
	sheet = Image.new("RGBA", (CELL * len(FRAMES), CELL), (0, 0, 0, 0))
	for index, name in enumerate(FRAMES):
		picture = Image.open(SRC / name).convert("RGBA")
		picture = picture.crop(picture.getbbox())
		scale = FIT / max(picture.width, picture.height)
		picture = picture.resize((round(picture.width * scale), round(picture.height * scale)), Image.LANCZOS)
		sheet.alpha_composite(picture, (index * CELL + (CELL - picture.width) // 2, CELL - picture.height))
	sheet.save(OUT, lossless=True)
	print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
	main()
