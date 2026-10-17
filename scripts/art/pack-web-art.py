"""Packs the Weaver Hollow's web art (docs/godot/WEBS.md; the dungeon design
docs/design/2026-10-16-dungeon-weaver-hollow.md "What must be built" -> Webs).

Sources: asset/Originals/weaver-hollow/webs/ (Magnific GPT 2.5, transparent background, the Lili
creation as the style reference; prompts in its README.md). Every piece is drawn at 2 px per game
unit (the art density: 128 px per 64-unit cell); the runtime sheets go in godot/asset/MAPS/webs/.

- floor-webs-6x1.webp: six flat webs lying on the floor, 192 px frames (96 units: a 64-unit cell
  and 16 units over each side, so painted neighbours overlap into one field). The WebLayer
  (game/world/webs/web_layer.gd) and `object.floor-web` draw them.
- palette.png: the WebLayer's palette (game/world/webs/web_tileset.tres), 64 px tiles: row 0 the
  auto tile (a variant per cell, by the cell), row 1 each variant.
- web-wall-across-2x1.webp: the web wall across a north or south door (`object.web-wall`,
  orientation "across"): intact, cut. Frames 272 px wide (128 units of web and its two silk
  columns, 4 units over each jamb).
- web-wall-side-2x1.webp: the web wall in an east or west door (orientation "side"): a narrow band
  of silk seen from above, intact, cut. Frames 384 px tall (192 units: the 128-unit opening and the
  web's rise above its north end).
- silk-parcel-3x1.webp: the silk parcel (`object.silk-parcel`): closed, torn open, and the glint
  (a painted four-point star where the generated glint frame has its sparkle, drawn over the
  closed parcel now and then).

    python scripts/art/pack-web-art.py
"""
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/weaver-hollow/webs"
OUT = ROOT / "godot/asset/MAPS/webs"
ALPHA_CUT = 12

FLOOR_SOURCE = "floor-webs-a.png"
FLOOR_FRAME = 192
FLOOR_FILL = 186
FLOOR_COUNT = 6
## The floor webs' milky fill between the strands is thinned to this share of its alpha (the
## strands, alpha above STRAND_ALPHA, keep theirs), so the floor shows through.
HAZE_SHARE = 0.72
STRAND_ALPHA = 200

PALETTE_TILE = 64
PALETTE_FILL = (236, 120, 200, 70)
AUTO_FRAME = (255, 214, 240, 255)
FIXED_FRAME = (150, 60, 130, 255)

ACROSS_SOURCE = "web-wall-front-a.png"
ACROSS_FRAME_W = 272
SIDE_SOURCE = "web-wall-side-a.png"
SIDE_FRAME_H = 384
PARCEL_SOURCE = "silk-parcel-a.png"
PARCEL_WIDTH = 136
STAR_RAY = 22
STAR_CORE = 5
STAR_COLOUR = (255, 226, 140)


def alpha_box(image: Image.Image) -> tuple:
	return image.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0).getbbox()


def save(image: Image.Image, name: str) -> None:
	OUT.mkdir(parents=True, exist_ok=True)
	path = OUT / name
	if path.suffix == ".webp":
		image.save(path, "WEBP", lossless=True)
	else:
		image.save(path)
	print(f"{name}: {image.size[0]} x {image.size[1]} px")


def blobs(image: Image.Image, count: int, step: int = 4) -> list:
	"""The `count` largest opaque blobs of `image` (alpha boxes in full pixels, row by row)."""
	small = image.getchannel("A").resize((image.width // step, image.height // step), Image.BOX)
	w, h = small.size
	data = small.load()
	seen = [[False] * w for _ in range(h)]
	found = []
	for y in range(h):
		for x in range(w):
			if seen[y][x] or data[x, y] <= ALPHA_CUT:
				continue
			queue = deque([(x, y)])
			seen[y][x] = True
			x0, y0, x1, y1, size = x, y, x, y, 0
			while queue:
				cx, cy = queue.popleft()
				size += 1
				x0, y0, x1, y1 = min(x0, cx), min(y0, cy), max(x1, cx), max(y1, cy)
				for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
					if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and data[nx, ny] > ALPHA_CUT:
						seen[ny][nx] = True
						queue.append((nx, ny))
			found.append((size, (x0 * step, y0 * step, (x1 + 1) * step, (y1 + 1) * step)))
	found.sort(key=lambda entry: -entry[0])
	boxes = [box for _, box in found[:count]]
	boxes.sort(key=lambda box: (round(box[1] / (image.height / 2)), box[0]))
	return boxes


def thin_haze(image: Image.Image) -> Image.Image:
	r, g, b, a = image.split()
	a = a.point(lambda v: v if v >= STRAND_ALPHA else round(v * HAZE_SHARE))
	return Image.merge("RGBA", (r, g, b, a))


def floor_webs() -> list:
	source = Image.open(SRC / FLOOR_SOURCE).convert("RGBA")
	sheet = Image.new("RGBA", (FLOOR_FRAME * FLOOR_COUNT, FLOOR_FRAME))
	frames = []
	for index, box in enumerate(blobs(source, FLOOR_COUNT)):
		piece = source.crop(box)
		piece = piece.crop(alpha_box(piece))
		scale = FLOOR_FILL / max(piece.size)
		piece = piece.resize((round(piece.width * scale), round(piece.height * scale)), Image.LANCZOS)
		piece = thin_haze(piece)
		frame = Image.new("RGBA", (FLOOR_FRAME, FLOOR_FRAME))
		frame.alpha_composite(piece, ((FLOOR_FRAME - piece.width) // 2, (FLOOR_FRAME - piece.height) // 2))
		sheet.alpha_composite(frame, (index * FLOOR_FRAME, 0))
		frames.append(frame)
	save(sheet, "floor-webs-6x1.webp")
	return frames


def palette(frames: list) -> None:
	tile = PALETTE_TILE
	image = Image.new("RGBA", (tile * len(frames), tile * 2))
	for row in range(2):
		for column, frame in enumerate(frames):
			if row == 0 and column > 0:
				continue
			square = Image.new("RGBA", (tile, tile), PALETTE_FILL)
			web = frame.resize((tile, tile), Image.LANCZOS)
			square.alpha_composite(web)
			draw = ImageDraw.Draw(square)
			colour = AUTO_FRAME if row == 0 else FIXED_FRAME
			draw.rectangle((0, 0, tile - 1, tile - 1), outline=colour, width=3)
			if row == 0:
				# "A" for auto: three dots in the corner.
				for i in range(3):
					draw.ellipse((5 + i * 6, 5, 9 + i * 6, 9), fill=colour)
			else:
				for i in range(column + 1):
					draw.ellipse((5 + i * 6, tile - 10, 9 + i * 6, tile - 6), fill=colour)
			image.alpha_composite(square, (column * tile, row * tile))
	save(image, "palette.png")


def states(source_name: str, halves: int) -> list:
	"""The source cut in `halves` equal columns, each trimmed to its alpha box."""
	source = Image.open(SRC / source_name).convert("RGBA")
	width = source.width // halves
	pieces = []
	for i in range(halves):
		column = source.crop((i * width, 0, (i + 1) * width, source.height))
		box = alpha_box(column)
		pieces.append((column.crop(box), box))
	return pieces


def web_wall_across() -> None:
	pieces = states(ACROSS_SOURCE, 2)
	scale = ACROSS_FRAME_W / pieces[0][0].width
	height = max(round(piece.height * scale) for piece, _ in pieces)
	height += height % 2
	sheet = Image.new("RGBA", (ACROSS_FRAME_W * 2, height))
	for index, (piece, _) in enumerate(pieces):
		resized = piece.resize((round(piece.width * scale), round(piece.height * scale)), Image.LANCZOS)
		x = index * ACROSS_FRAME_W + (ACROSS_FRAME_W - resized.width) // 2
		sheet.alpha_composite(resized, (x, height - resized.height))
	save(sheet, "web-wall-across-2x1.webp")


def web_wall_side() -> None:
	pieces = states(SIDE_SOURCE, 2)
	# One vertical extent for both (the cut keeps its tatters where the band's ends were).
	top = min(box[1] for _, box in pieces)
	bottom = max(box[3] for _, box in pieces)
	scale = SIDE_FRAME_H / (bottom - top)
	width = max(round(piece.width * scale) for piece, _ in pieces)
	width += width % 2
	sheet = Image.new("RGBA", (width * 2, SIDE_FRAME_H))
	for index, (piece, box) in enumerate(pieces):
		resized = piece.resize((round(piece.width * scale), round(piece.height * scale)), Image.LANCZOS)
		x = index * width + (width - resized.width) // 2
		sheet.alpha_composite(resized, (x, round((box[1] - top) * scale)))
	save(sheet, "web-wall-side-2x1.webp")


def star(size: int) -> Image.Image:
	"""A warm four-point glint, its middle at the image's middle."""
	big = size * 4
	glow = Image.new("RGBA", (big, big))
	draw = ImageDraw.Draw(glow)
	c = big / 2
	ray, core = STAR_RAY * 4, STAR_CORE * 4
	for dx, dy in ((1, 0), (0, 1)):
		draw.polygon([(c - dx * ray, c - dy * ray), (c + dy * core * 0.45, c + dx * core * 0.45),
			(c + dx * ray, c + dy * ray), (c - dy * core * 0.45, c - dx * core * 0.45)], fill=STAR_COLOUR + (255,))
	draw.ellipse((c - core, c - core, c + core, c + core), fill=(255, 250, 228, 255))
	halo = glow.filter(ImageFilter.GaussianBlur(big / 14))
	result = Image.alpha_composite(halo, glow)
	return result.resize((size, size), Image.LANCZOS)


def silk_parcel() -> None:
	source = Image.open(SRC / PARCEL_SOURCE).convert("RGBA")
	third = source.width // 3
	columns = [source.crop((i * third, 0, (i + 1) * third, source.height)) for i in range(3)]
	closed, glint, opened = columns[0], columns[1], columns[2]
	closed_box = alpha_box(closed)
	opened_box = alpha_box(opened)
	scale = PARCEL_WIDTH / (closed_box[2] - closed_box[0])
	pieces = [closed.crop(closed_box), opened.crop(opened_box)]
	sized = [p.resize((round(p.width * scale), round(p.height * scale)), Image.LANCZOS) for p in pieces]
	frame_w = max(p.width for p in sized) + 8
	frame_h = max(p.height for p in sized) + 8
	frame_w += frame_w % 2
	frame_h += frame_h % 2
	sheet = Image.new("RGBA", (frame_w * 3, frame_h))
	# Both stand on the frame's bottom, centred.
	for index, piece in enumerate(sized):
		sheet.alpha_composite(piece, (index * frame_w + (frame_w - piece.width) // 2, frame_h - 4 - piece.height))
	# The glint: where the generated glint frame is bright gold and the closed one is not.
	gp, cp = glint.load(), closed.load()
	xs, ys = [], []
	for y in range(0, glint.height, 2):
		for x in range(0, glint.width, 2):
			r, g, b, a = gp[x, y]
			if a > 200 and r > 240 and g > 200 and b < 190 and sum(cp[x, y][:3]) < r + g + b - 90:
				xs.append(x)
				ys.append(y)
	glint_box = alpha_box(glint)
	if xs:
		sx, sy = sum(xs) / len(xs), sum(ys) / len(ys)
	else:
		sx, sy = (glint_box[0] + glint_box[2]) / 2, glint_box[1] + 40
	# Into the closed frame: relative to the glint parcel's own box, the closed piece's frame place.
	closed_piece = sized[0]
	fx = (frame_w - closed_piece.width) // 2 + (sx - glint_box[0]) * scale
	fy = frame_h - 4 - closed_piece.height + (sy - glint_box[1]) * scale
	size = STAR_RAY * 2 + 8
	glint_frame = Image.new("RGBA", (frame_w, frame_h))
	glint_frame.alpha_composite(star(size), (round(fx - size / 2), round(fy - size / 2)))
	sheet.alpha_composite(glint_frame, (frame_w * 2, 0))
	save(sheet, "silk-parcel-3x1.webp")
	print(f"  parcel frame {frame_w} x {frame_h} px, glint at ({fx:.0f}, {fy:.0f}) px in the frame")


def main() -> None:
	frames = floor_webs()
	palette(frames)
	web_wall_across()
	web_wall_side()
	silk_parcel()


if __name__ == "__main__":
	main()
