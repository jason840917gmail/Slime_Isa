"""Packs the Weaver Hollow's Goo Bomb pieces (docs/design/2026-10-16-dungeon-weaver-hollow.md "What
must be built" -> The Goo Bomb's locks; docs/godot/BODY_SHAPES.md "The Goo Bomb").

Sources (Magnific GPT 2.5, transparent; prompts in asset/Originals/weaver-hollow/bomb-pieces/README.md):
- keg-a.png: a Thorn Guard blast keg lying in an iron cradle bolted to a flagstone block (intact |
  burst), two pieces in a row;
- winch-post-a.png: a stone winch post with an iron chain wound round it and an iron ring (intact |
  broken stump with the snapped chain), two pieces in a row;
- floor-hole-a.png: a hole blown through flagstones into a dark shaft (no ladder).

The bomb's universal mark, the crack decal (godot/asset/abilities/goo-bomb/crack-overlay.webp, the
cracked wall's), is laid onto the intact keg's belly (only over its wood, with a thin pale rim so it
reads on dark oak) and onto the post's lower stone face (only over the stone: the ring and the chain
stay in front of it).

Runtime density: 2 px per game unit (the scenes draw the sheets at 0.5).

    python scripts/art/pack-weaver-bomb-art.py

Writes godot/asset/abilities/goo-bomb/blast-keg-2x1.webp, winch-post-2x1.webp and floor-hole.webp,
and prints each sheet's frame size and the sprite offset (px, at 2 px a unit) that puts the scene
root on the piece's feet.
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/weaver-hollow/bomb-pieces"
OUT = ROOT / "godot/asset/abilities/goo-bomb"
CRACK = OUT / "crack-overlay.webp"
ALPHA_CUT = 40
PX_PER_UNIT = 2.0

# The keg: its flagstone block is KEG_WORLD_W units wide. The crack on its belly (source px of the
# intact piece's sheet): middle, height, turn (degrees). The burst piece's smoke wisp is cut out
# (a kept keg would smoke for good): the light grey pixels in SMOKE_BOX.
KEG_WORLD_W = 72.0
KEG_CRACK_CENTRE = (430.0, 318.0)
KEG_CRACK_HEIGHT = 360.0
KEG_CRACK_TURN = -12.0
KEG_RIM = (246, 226, 178)
SMOKE_BOX = (1080, 0, 1300, 300)
# The feet: this far above the piece's bottom edge (source px), the front of the block.
KEG_FEET_UP = 40.0

# The winch post: POST_WORLD_W units wide (the intact post). The crack on its lower face (source px).
# The broken stump's middle (source x) is lined up with the intact post's middle.
POST_WORLD_W = 70.0
POST_CRACK_CENTRE = (405.0, 622.0)
POST_CRACK_HEIGHT = 330.0
POST_CRACK_TURN = 8.0
STUMP_MIDDLE_X = 1100.0
POST_FEET_UP = 30.0

# The floor hole: HOLE_WORLD_W units wide, squashed to HOLE_SQUASH of its height (it lies flat); the
# root is the opening's middle (source px).
HOLE_WORLD_W = 140.0
HOLE_SQUASH = 0.82
HOLE_OPENING = (510.0, 500.0)


def pieces(image: Image.Image) -> list[tuple[int, int, int, int]]:
	"""The alpha boxes of the pieces, left to right (split at empty columns)."""
	alpha = image.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0)
	width, height = image.size
	columns = [any(alpha.getpixel((x, y)) for y in range(0, height, 2)) for x in range(width)]
	boxes = []
	start = None
	for x, filled in enumerate(columns + [False]):
		if filled and start is None:
			start = x
		elif not filled and start is not None:
			box = alpha.crop((start, 0, x, height)).getbbox()
			boxes.append((start, box[1], x, box[3]))
			start = None
	return boxes


def crack_layer(size: tuple[int, int], centre: tuple[float, float], height: float, turn: float,
		rim: tuple[int, int, int] | None) -> Image.Image:
	"""The crack decal scaled to `height` px, turned, its middle at `centre`, on a clear layer of
	`size`; with `rim`, a soft pale rim under it."""
	crack = Image.open(CRACK).convert("RGBA")
	k = height / crack.height
	crack = crack.resize((round(crack.width * k), round(crack.height * k)), Image.LANCZOS)
	crack = crack.rotate(turn, resample=Image.BICUBIC, expand=True)
	layer = Image.new("RGBA", size)
	at = (round(centre[0] - crack.width / 2), round(centre[1] - crack.height / 2))
	if rim is not None:
		halo_alpha = crack.getchannel("A").filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(1.5))
		halo_alpha = halo_alpha.point(lambda a: int(a * 0.8))
		halo = Image.new("RGBA", crack.size, rim + (0,))
		halo.putalpha(halo_alpha)
		layer.alpha_composite(halo, at)
	layer.alpha_composite(crack, at)
	return layer


def masked(layer: Image.Image, mask: Image.Image) -> Image.Image:
	out = layer.copy()
	out.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
	return out


def wood_mask(image: Image.Image) -> Image.Image:
	"""Opaque warm pixels (the keg's oak, not its grey iron)."""
	r, g, b, a = image.split()
	warm = ImageChops.subtract(r, b).point(lambda v: 255 if v > 22 else 0)
	solid = a.point(lambda v: 255 if v > 200 else 0)
	return ImageChops.multiply(warm, solid).filter(ImageFilter.GaussianBlur(1.0))


def stone_mask(image: Image.Image) -> Image.Image:
	"""Opaque light, not green pixels (the post's stone, not its dark iron or moss)."""
	rgb = image.convert("RGB")
	lum = rgb.convert("L").point(lambda v: 255 if v > 105 else 0)
	r, g, b = rgb.split()
	not_green = ImageChops.subtract(r, g).point(lambda v: 255 if v > 4 else 0)
	solid = image.getchannel("A").point(lambda v: 255 if v > 200 else 0)
	return ImageChops.multiply(ImageChops.multiply(lum, not_green), solid).filter(ImageFilter.GaussianBlur(1.0))


def cut_smoke(image: Image.Image) -> None:
	pixels = image.load()
	x0, y0, x1, y1 = SMOKE_BOX
	for y in range(y0, y1):
		for x in range(x0, x1):
			r, g, b, a = pixels[x, y]
			if a == 0:
				continue
			spread = max(r, g, b) - min(r, g, b)
			if spread < 40 and (r + g + b) / 3 > 95:
				pixels[x, y] = (0, 0, 0, 0)


def two_frames(image: Image.Image, boxes, middles: tuple[float, float], k: float,
		feet_up: float) -> tuple[Image.Image, tuple[int, int], tuple[float, float]]:
	"""Both pieces in cells of one size, each piece's `middle` (source x) on the cell's middle,
	bottoms aligned; returns the sheet, the frame size and the sprite offset of the feet."""
	half = max(max(middles[i] - boxes[i][0], boxes[i][2] - middles[i]) for i in range(2))
	top = min(box[1] for box in boxes)
	bottom = max(box[3] for box in boxes)
	cell_src = (2 * half, bottom - top)
	frame = (round(cell_src[0] * k), round(cell_src[1] * k))
	sheet = Image.new("RGBA", (frame[0] * 2, frame[1]))
	for i, box in enumerate(boxes[:2]):
		piece = image.crop(box)
		size = (round(piece.width * k), round(piece.height * k))
		x = round((half - (middles[i] - box[0])) * k)
		y = round((box[1] - top) * k)
		sheet.alpha_composite(piece.resize(size, Image.LANCZOS), (i * frame[0] + x, y))
	offset = (-frame[0] / 2.0, -(frame[1] - feet_up * k))
	return sheet, frame, offset


def pack_keg() -> None:
	image = Image.open(SRC / "keg-a.png").convert("RGBA")
	crack = crack_layer(image.size, KEG_CRACK_CENTRE, KEG_CRACK_HEIGHT, KEG_CRACK_TURN, KEG_RIM)
	image.alpha_composite(masked(crack, wood_mask(image)))
	cut_smoke(image)
	boxes = pieces(image)[:2]
	k = KEG_WORLD_W * PX_PER_UNIT / (boxes[0][2] - boxes[0][0])
	middles = ((boxes[0][0] + boxes[0][2]) / 2.0, (boxes[1][0] + boxes[1][2]) / 2.0)
	sheet, frame, offset = two_frames(image, boxes, middles, k, KEG_FEET_UP)
	sheet.save(OUT / "blast-keg-2x1.webp", lossless=True)
	print("blast-keg-2x1.webp: frame %s, offset (%.1f, %.1f)" % (frame, offset[0], offset[1]))


def pack_post() -> None:
	image = Image.open(SRC / "winch-post-a.png").convert("RGBA")
	boxes = pieces(image)[:2]
	crack = crack_layer(image.size, POST_CRACK_CENTRE, POST_CRACK_HEIGHT, POST_CRACK_TURN, None)
	only_post = Image.new("L", image.size, 0)
	only_post.paste(255, (0, 0, boxes[0][2] + 1, image.height))
	image.alpha_composite(masked(crack, ImageChops.multiply(stone_mask(image), only_post)))
	k = POST_WORLD_W * PX_PER_UNIT / (boxes[0][2] - boxes[0][0])
	middles = ((boxes[0][0] + boxes[0][2]) / 2.0, STUMP_MIDDLE_X)
	sheet, frame, offset = two_frames(image, boxes, middles, k, POST_FEET_UP)
	sheet.save(OUT / "winch-post-2x1.webp", lossless=True)
	print("winch-post-2x1.webp: frame %s, offset (%.1f, %.1f)" % (frame, offset[0], offset[1]))


def pack_hole() -> None:
	image = Image.open(SRC / "floor-hole-a.png").convert("RGBA")
	box = pieces(image)[0]
	piece = image.crop(box)
	k = HOLE_WORLD_W * PX_PER_UNIT / piece.width
	size = (round(piece.width * k), round(piece.height * k * HOLE_SQUASH))
	piece.resize(size, Image.LANCZOS).save(OUT / "floor-hole.webp", lossless=True)
	offset = (-(HOLE_OPENING[0] - box[0]) * k, -(HOLE_OPENING[1] - box[1]) * k * HOLE_SQUASH)
	print("floor-hole.webp: size %s, offset (%.1f, %.1f)" % (size, offset[0], offset[1]))


def main() -> None:
	OUT.mkdir(parents=True, exist_ok=True)
	pack_keg()
	pack_post()
	pack_hole()


if __name__ == "__main__":
	main()
