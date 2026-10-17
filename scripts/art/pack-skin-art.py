"""Packs the skins' art (docs/godot/SKINS.md; roadmap 7.8).

Sources: asset/Originals/skins/generated/ (Magnific GPT 2.5, transparent background, the Lili creation
as style reference, 2026-10-17). Writes:

- godot/asset/MAPS/props/heavy-skin/ at 2 px per game unit, each a 2x1 sheet (whole | broken) whose
  cells share one size, the thing's foot on the cell's bottom edge, centred across:
  - loose-rock-2x1.webp: a big old loose boulder | its rubble (LOOSE_ROCK_UNITS wide);
  - old-trunk-2x1.webp: a hollow, mossy old trunk lying across a path | its splinters (OLD_TRUNK_UNITS);
  - old-fence-2x1.webp: a grey, broken-backed old fence | its planks (OLD_FENCE_UNITS);
  - loose-prize.webp: a coin pouch snagged on a twig, its pouch's bottom on the bottom edge
    (LOOSE_PRIZE_UNITS wide).
- godot/asset/UI/skins/<skin>-icon.webp: the bag's Skins row icons, 128 x 128 (heavy, silk, feral:
  the three badges of icons.png, left to right).
- godot/asset/player/skins/<skin>-look.webp: the looks' painted textures, 256 x 256, opaque: the
  slime's shader paints them over its body, mirrored when tiled (form_skin.gdshader).

It prints each sheet's cell size and the offsets the scenes use.

    python scripts/art/pack-skin-art.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/skins/generated"
PROPS = ROOT / "godot/asset/MAPS/props/heavy-skin"
ICONS = ROOT / "godot/asset/UI/skins"
LOOKS = ROOT / "godot/asset/player/skins"
ALPHA_CUT = 40
PX_PER_UNIT = 2
LOOSE_ROCK_UNITS = 104
OLD_TRUNK_UNITS = 150
OLD_FENCE_UNITS = 132
LOOSE_PRIZE_UNITS = 46
ICON_PX = 128
LOOK_PX = 256
SKINS = ["heavy", "silk", "feral"]


def load(name: str) -> Image.Image:
	return Image.open(SRC / name).convert("RGBA")


def alpha_box(image: Image.Image) -> tuple[int, int, int, int]:
	return image.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0).getbbox()


def scaled(image: Image.Image, factor: float) -> Image.Image:
	return image.resize((max(1, round(image.width * factor)), max(1, round(image.height * factor))), Image.LANCZOS)


def halves(image: Image.Image) -> list[Image.Image]:
	"""The two sprites of a 2x1 sheet, each cropped to what it shows."""
	w = image.width // 2
	out = []
	for x in (0, w):
		half = image.crop((x, 0, x + w, image.height))
		out.append(half.crop(alpha_box(half)))
	return out


def sheet(name: str, out_name: str, units: int) -> None:
	whole, broken = halves(load(name))
	factor = units * PX_PER_UNIT / whole.width
	whole = scaled(whole, factor)
	broken = scaled(broken, factor)
	cell_w = max(whole.width, broken.width) + 8
	cell_h = max(whole.height, broken.height) + 4
	out = Image.new("RGBA", (cell_w * 2, cell_h), (0, 0, 0, 0))
	for index, part in enumerate([whole, broken]):
		out.alpha_composite(part, (index * cell_w + (cell_w - part.width) // 2, cell_h - part.height))
	PROPS.mkdir(parents=True, exist_ok=True)
	out.save(PROPS / out_name, "WEBP", lossless=True)
	print(f"{out_name}: cell {cell_w} x {cell_h} px; Visual offset (-{cell_w // 2}, -{cell_h}) at scale 0.5")


def prize() -> None:
	image = load("loose-prize.png")
	image = image.crop(alpha_box(image))
	image = scaled(image, LOOSE_PRIZE_UNITS * PX_PER_UNIT / image.width)
	PROPS.mkdir(parents=True, exist_ok=True)
	image.save(PROPS / "loose-prize.webp", "WEBP", lossless=True)
	print(f"loose-prize.webp: {image.width} x {image.height} px; Visual offset (-{image.width // 2}, -{image.height}) at scale 0.5")


def icons() -> None:
	image = load("icons.png")
	third = image.width // 3
	ICONS.mkdir(parents=True, exist_ok=True)
	for index, skin in enumerate(SKINS):
		part = image.crop((index * third, 0, (index + 1) * third, image.height))
		part = part.crop(alpha_box(part))
		side = max(part.width, part.height)
		square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
		square.alpha_composite(part, ((side - part.width) // 2, (side - part.height) // 2))
		square.resize((ICON_PX, ICON_PX), Image.LANCZOS).save(ICONS / f"{skin}-icon.webp", "WEBP", lossless=True)
		print(f"{skin}-icon.webp: {ICON_PX} x {ICON_PX}")


def looks() -> None:
	LOOKS.mkdir(parents=True, exist_ok=True)
	for skin in SKINS:
		image = load(f"tex-{skin}.png")
		# The model leaves the full frame a little see-through: the texture is opaque.
		image.putalpha(255)
		image = image.convert("RGB").resize((LOOK_PX, LOOK_PX), Image.LANCZOS)
		image.save(LOOKS / f"{skin}-look.webp", "WEBP", quality=92)
		print(f"{skin}-look.webp: {LOOK_PX} x {LOOK_PX}")


if __name__ == "__main__":
	sheet("loose-rock.png", "loose-rock-2x1.webp", LOOSE_ROCK_UNITS)
	sheet("old-trunk.png", "old-trunk-2x1.webp", OLD_TRUNK_UNITS)
	sheet("old-fence.png", "old-fence-2x1.webp", OLD_FENCE_UNITS)
	prize()
	icons()
	looks()
