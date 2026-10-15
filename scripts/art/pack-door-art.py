"""Packs the door art (docs/godot/CONVENTIONS.md "Doors").

Sources: asset/Originals/buildings/doors/ (Magnific GPT 2.5, transparent, style reference: the
mushroom furniture props sheet). Each source is trimmed to its alpha box and scaled to its size in
the game at 2 px per game unit (the art density); the runtime pictures go in
godot/asset/MAPS/Houses/doors/.

- mushroom-door-leaf.png: the leaf drawn over the level-1 mushroom house's painted door
  (`mushroom-home-door`, door.gd `leaf_art_path`; generated 2026-10-14 for the forge, which has no
  door since 2026-10-15).
- interior-timber-door.webp: the way out of the timber rooms (slime-home, gloop-hut): two low
  plank leaves on a sill, between the bottom wall's door posts.
- interior-mushroom-door.webp: the way out of mushroom-home: a root frame with a round-topped door.

The interior pictures are the `house_art` of their `house-door`; door.gd cuts the leaves out of
them (`door_rect`). The script prints each picture's leaf rect in world units, relative to the
picture's bottom centre (the door art node's feet), for the scenes.

    python scripts/art/pack-door-art.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/buildings/doors"
OUT = ROOT / "godot/asset/MAPS/Houses/doors"
ALPHA_CUT = 12
PX_PER_UNIT = 2.0

# name: (source, width in world units, leaf rect in source pixels (x0, y0, x1, y1) or None, arch px,
# tone: the colour factor that matches the painting it lies on)
PIECES = {
	# Darkened to the painted door's browns (its mean colour is 0.78 of the picture's).
	"mushroom-door-leaf.png": ("mushroom-door-leaf-b.png", 37.5, None, 0, 0.78),
	"interior-timber-door.webp": ("interior-timber-door-a.png", 120.0, (302, 290, 1232, 688), 0, 1.0),
	"interior-mushroom-door.webp": ("interior-mushroom-door-a.png", 172.0, (562, 290, 988, 792), 140, 1.0),
}


def main() -> None:
	for out_name, (source, width, leaf, arch, tone) in PIECES.items():
		image = Image.open(SRC / source).convert("RGBA")
		if tone != 1.0:
			r, g, b, a = image.split()
			r, g, b = (c.point(lambda v: min(255, round(v * tone))) for c in (r, g, b))
			image = Image.merge("RGBA", (r, g, b, a))
		alpha = image.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0)
		box = alpha.getbbox()
		piece = image.crop(box)
		scale = width * PX_PER_UNIT / piece.width
		size = (round(piece.width * scale), round(piece.height * scale))
		piece = piece.resize(size, Image.LANCZOS)
		out = OUT / out_name
		out.parent.mkdir(parents=True, exist_ok=True)
		if out.suffix == ".webp":
			piece.save(out, "WEBP", lossless=True)
		else:
			piece.save(out)
		line = f"{out_name} {size} px = {size[0] / PX_PER_UNIT} x {size[1] / PX_PER_UNIT} units"
		if leaf is not None:
			# World units from the picture's bottom centre.
			x0 = ((leaf[0] - box[0]) * scale - size[0] / 2) / PX_PER_UNIT
			y0 = ((leaf[1] - box[1]) * scale - size[1]) / PX_PER_UNIT
			w = (leaf[2] - leaf[0]) * scale / PX_PER_UNIT
			h = (leaf[3] - leaf[1]) * scale / PX_PER_UNIT
			line += f"; leaf Rect2({x0:.1f}, {y0:.1f}, {w:.1f}, {h:.1f}) arch {arch * scale / PX_PER_UNIT:.1f}"
		print(line)


if __name__ == "__main__":
	main()
