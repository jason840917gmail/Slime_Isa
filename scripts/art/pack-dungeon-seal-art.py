"""Packs the dungeon seal's art (docs/godot/DUNGEONS.md "The seal" and "Art").

Sources: asset/Originals/dungeon-kit/generated/ (Magnific GPT 2.5, transparent background, the Lili
creation as style reference, 2026-10-17): dungeon-seal.png (the dressed-stone block with a dark pearl
set in its face) and seal-ring.png (a ring of white light; the game tints it with the boss's colour
and adds it over the block). Writes into godot/asset/MAPS/objects/dungeon/:

- dungeon-seal.webp: the block, trimmed, SHUTTER_UNITS wide at 2 px a unit (as the kit's shutter);
- seal-ring.webp: the ring, trimmed, RING_PX square.

It prints where the pearl sits on the packed block (from its bottom middle, in game units) and the
ring's scale that rings the pearl's socket: the numbers the scene
godot/game/scenes/objects/dungeon/dungeon-seal.tscn uses for its `Ring` node.

    python scripts/art/pack-dungeon-seal-art.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/dungeon-kit/generated"
OUT = ROOT / "godot/asset/MAPS/objects/dungeon"
ALPHA_CUT = 40
PX = 2
SHUTTER_UNITS = 136
RING_PX = 256
## The light ring's inner edge sits this much outside the socket's groove.
RING_OVER_SOCKET = 1.18


def trimmed(path: Path) -> Image.Image:
	image = Image.open(path).convert("RGBA")
	return image.crop(image.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0).getbbox())


def save(image: Image.Image, name: str) -> None:
	OUT.mkdir(parents=True, exist_ok=True)
	image.save(OUT / name, "WEBP", lossless=True)
	print(f"{(OUT / name).relative_to(ROOT)}  {image.width} x {image.height}")


def pearl(block: Image.Image) -> tuple[float, float, float]:
	"""The dark pearl's centre (x, y px) and radius (px): the dark, opaque pixels in the face's middle."""
	rgba = np.array(block).astype(np.float32)
	h, w = rgba.shape[:2]
	value = rgba[:, :, :3].max(axis=2)
	dark = (rgba[:, :, 3] > 200) & (value < 70)
	dark[:, : int(w * 0.25)] = False
	dark[:, int(w * 0.75):] = False
	ys, xs = np.nonzero(dark)
	cx, cy = float(xs.mean()), float(ys.mean())
	radius = float(np.sqrt(dark.sum() / np.pi))
	return cx, cy, radius


def main() -> None:
	block = trimmed(SRC / "dungeon-seal.png")
	block = block.resize((SHUTTER_UNITS * PX, round(block.height * SHUTTER_UNITS * PX / block.width)), Image.LANCZOS)
	save(block, "dungeon-seal.webp")
	ring = trimmed(SRC / "seal-ring.png")
	side = max(ring.width, ring.height)
	square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
	square.alpha_composite(ring, ((side - ring.width) // 2, (side - ring.height) // 2))
	ring = square.resize((RING_PX, RING_PX), Image.LANCZOS)
	save(ring, "seal-ring.webp")
	# The ring's bright line: the radius of the brightest band from its middle.
	rgba = np.array(ring).astype(np.float32)
	yy, xx = np.mgrid[0:RING_PX, 0:RING_PX]
	distance = np.hypot(xx - RING_PX / 2, yy - RING_PX / 2)
	bright = rgba[:, :, 3] * rgba[:, :, :3].mean(axis=2) / 255.0
	bands = [bright[(distance >= r) & (distance < r + 1)].mean() for r in range(RING_PX // 2)]
	line_px = float(np.argmax(bands))
	cx, cy, radius = pearl(block)
	# The groove ring round the socket is about 1.4 times the pearl's radius.
	socket = radius * 1.4
	scale = socket * RING_OVER_SOCKET / line_px
	print(f"pearl at ({(cx - block.width / 2) / PX:.1f}, {-(block.height - cy) / PX:.1f}) units from the bottom middle; "
		f"pearl radius {radius / PX:.1f} units; ring line {line_px:.0f} px -> Ring scale {scale / PX:.3f}")


if __name__ == "__main__":
	main()
