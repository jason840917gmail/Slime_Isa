"""Packs the Crystal Colossus's quake art (2026-11-24) into its runtime sheets.

Sources (asset/Originals/dungeon-kit/bosses/colossus/quake/, two Magnific GPT 2.5 stills, 1024 px,
transparent): fissures-raw.png (four long glowing fissures stacked in rows) and craters-raw.png (four
impact craters in a 2 x 2 grid).

Writes (godot/asset/MAPS/effects/, read by godot/game/bosses/colossus_quake.gd):
  colossus-quake-fissures-1x4.webp  four fissures, one a row, each trimmed and fitted to FISSURE_CELL
                                    (2 px a world unit: a fissure is FISSURE_CELL[0] / 2 units long),
                                    standing on its cell's middle line
  colossus-quake-craters-4x1.webp   four craters, one a cell of CRATER_CELL, centred

usage: python scripts/art/pack-quake-art.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "asset" / "Originals" / "dungeon-kit" / "bosses" / "colossus" / "quake"
OUT = ROOT / "godot" / "asset" / "MAPS" / "effects"
FISSURE_CELL = (640, 120)
CRATER_CELL = (256, 256)
CRATER_FIT = 240
SOLID = 12
MIN_ROW_GAP = 12


def bands(alpha: Image.Image, axis: int) -> list[tuple[int, int]]:
	"""Runs of rows (axis 1) or columns (axis 0) holding any pixel above SOLID, gaps under MIN_ROW_GAP joined."""
	width, height = alpha.size
	data = alpha.load()
	count = height if axis == 1 else width
	filled = []
	for i in range(count):
		line = range(width) if axis == 1 else range(height)
		filled.append(any((data[x, i] if axis == 1 else data[i, x]) > SOLID for x in line))
	runs, start, gap = [], None, 0
	for i, on in enumerate(filled + [False] * MIN_ROW_GAP):
		if on:
			if start is None:
				start = i
			gap = 0
		elif start is not None:
			gap += 1
			if gap >= MIN_ROW_GAP:
				runs.append((start, i - gap + 1))
				start, gap = None, 0
	return runs


def trimmed(image: Image.Image) -> Image.Image:
	box = image.getchannel("A").point(lambda a: 255 if a > SOLID else 0).getbbox()
	return image.crop(box) if box else image


def fit(image: Image.Image, width: int, height: int) -> Image.Image:
	scale = min(width / image.width, height / image.height, 1.0)
	return image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.LANCZOS)


def pack_fissures() -> None:
	source = Image.open(SOURCES / "fissures-raw.png").convert("RGBA")
	rows = [run for run in bands(source.getchannel("A"), 1) if run[1] - run[0] > 40]
	assert len(rows) == 4, f"expected four fissure rows, found {rows}"
	sheet = Image.new("RGBA", (FISSURE_CELL[0], FISSURE_CELL[1] * 4), (0, 0, 0, 0))
	for k, (top, bottom) in enumerate(rows):
		piece = fit(trimmed(source.crop((0, top, source.width, bottom))), *FISSURE_CELL)
		sheet.alpha_composite(piece, ((FISSURE_CELL[0] - piece.width) // 2, k * FISSURE_CELL[1] + (FISSURE_CELL[1] - piece.height) // 2))
	OUT.mkdir(parents=True, exist_ok=True)
	sheet.save(OUT / "colossus-quake-fissures-1x4.webp", "WEBP", lossless=True)
	print("fissures", sheet.size, rows)


def pack_craters() -> None:
	source = Image.open(SOURCES / "craters-raw.png").convert("RGBA")
	half_w, half_h = source.width // 2, source.height // 2
	sheet = Image.new("RGBA", (CRATER_CELL[0] * 4, CRATER_CELL[1]), (0, 0, 0, 0))
	for k in range(4):
		x, y = (k % 2) * half_w, (k // 2) * half_h
		piece = fit(trimmed(source.crop((x, y, x + half_w, y + half_h))), CRATER_FIT, CRATER_FIT)
		sheet.alpha_composite(piece, (k * CRATER_CELL[0] + (CRATER_CELL[0] - piece.width) // 2, (CRATER_CELL[1] - piece.height) // 2))
	sheet.save(OUT / "colossus-quake-craters-4x1.webp", "WEBP", lossless=True)
	print("craters", sheet.size)


if __name__ == "__main__":
	pack_fissures()
	pack_craters()
