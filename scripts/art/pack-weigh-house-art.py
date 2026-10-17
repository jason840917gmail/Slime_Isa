"""Packs the Weigh House's props (Fatty's Lair's C2, docs/godot/DUNGEONS.md "Fatty's Lair (built)";
docs/design/2026-10-17-pearl-mid-dungeon.md "Fatty's Lair").

Sources: asset/Originals/fattys-lair/generated/weigh-*-a.png (Magnific GPT 2.5, transparent
background, the Lili creation as style reference, 2026-10-17). Writes godot/asset/MAPS/objects/
fattys-lair/ at the art density of 2 px per game unit:

- weigh-beam-scale.webp: the Thorn Guard's beam scale (an oak post, an iron beam, two pans on
  chains, a grain sack in one), BEAM_SCALE_UNITS tall;
- weigh-weights.webp: a heap of cast-iron counterweights on a pallet, WEIGHTS_UNITS wide;
- weigh-scale-pan.webp: an iron scale pan on a wall hook with a coin pouch in it (the Weigh House's
  loose prize), SCALE_PAN_UNITS tall.

It prints each picture's size and the Visual offset its scene uses (the root at the bottom middle).

    python scripts/art/pack-weigh-house-art.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/fattys-lair/generated"
OUT = ROOT / "godot/asset/MAPS/objects/fattys-lair"
ALPHA_CUT = 40
PX_PER_UNIT = 2

BEAM_SCALE_UNITS = 140
WEIGHTS_UNITS = 84
SCALE_PAN_UNITS = 70

# (source, output, size in units, "h" for a height or "w" for a width)
PROPS = [
	("weigh-beam-scale-a.png", "weigh-beam-scale.webp", BEAM_SCALE_UNITS, "h"),
	("weigh-weights-a.png", "weigh-weights.webp", WEIGHTS_UNITS, "w"),
	("weigh-scale-pan-a.png", "weigh-scale-pan.webp", SCALE_PAN_UNITS, "h"),
]


def cut(image: Image.Image) -> Image.Image:
	"""Crops to the opaque part and clears the faint alpha noise round it."""
	alpha = image.getchannel("A").point(lambda a: a if a > ALPHA_CUT else 0)
	image.putalpha(alpha)
	return image.crop(alpha.getbbox())


def main() -> None:
	OUT.mkdir(parents=True, exist_ok=True)
	for source, output, units, along in PROPS:
		image = cut(Image.open(SRC / source).convert("RGBA"))
		target = units * PX_PER_UNIT
		factor = target / (image.height if along == "h" else image.width)
		image = image.resize((max(1, round(image.width * factor)), max(1, round(image.height * factor))), Image.LANCZOS)
		image.save(OUT / output, "WEBP", lossless=True)
		print(f"{output}: {image.width} x {image.height} px; Visual offset ({-image.width / 2:.1f}, {-image.height:.1f}) at scale 0.5")


if __name__ == "__main__":
	main()
