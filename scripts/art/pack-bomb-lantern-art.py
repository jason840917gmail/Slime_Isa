"""Packs the Goo Bomb and Lantern art (docs/design/2026-10-14-bomb-lantern-and-secrets.md).

Sources: asset/Originals/abilities/generated/ (Magnific GPT 2.5, transparent). Each source is cut
into its frames or states (a grid), each piece trimmed to its alpha box, scaled to fit its cell
(2 px per game unit, the art density) and centred in a cell of a fixed size; the cells go in one
row (or the grid) of a runtime sheet in godot/asset/abilities/.

    python scripts/art/pack-bomb-lantern-art.py
"""
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/abilities/generated"
OUT = ROOT / "godot/asset/abilities"
ICONS = ROOT / "godot/asset/UI/hud-console"
ALPHA_CUT = 12

# name: (source, cols, rows, cell w, cell h, out cols, out path)
SHEETS = {
	"bomb": ("bomb-a.png", 1, 1, 96, 112, 1, OUT / "goo-bomb/bomb.webp"),
	"blast": ("blast-a.png", 3, 2, 320, 320, 6, OUT / "goo-bomb/blast-6x1.webp"),
	"cracked-wall": ("wall-a.png", 2, 1, 256, 224, 2, OUT / "goo-bomb/cracked-wall-2x1.webp"),
	"rubble": ("rubble-a.png", 2, 1, 224, 160, 2, OUT / "goo-bomb/rubble-2x1.webp"),
	"flame": ("flame-a.png", 2, 2, 96, 64, 4, OUT / "lantern/flame-4x1.webp"),
	"deadthorn": ("hedge-b.png", 2, 1, 320, 176, 2, OUT / "lantern/deadthorn-2x1.webp"),
}
# Sheets whose pieces stand on the ground: bottom-aligned in their cells (effects are centred).
GROUNDED = {"bomb", "cracked-wall", "rubble", "deadthorn"}
# Animation strips: every frame keeps the same scale (a small flash stays small).
SHARED_SCALE = {"blast", "flame"}
# The icons sheet: left = Goo Bomb, right = Lantern, 96 x 96 each.
ICON_SOURCE = "icons-b.png"
ICON_NAMES = ["ability-goo-bombs.webp", "ability-lantern.webp"]


def trim(piece: Image.Image) -> Image.Image:
	alpha = piece.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0)
	box = alpha.getbbox()
	return piece.crop(box) if box else piece


def fit(piece: Image.Image, w: int, h: int, grounded: bool, scale: float = 0.0) -> Image.Image:
	piece = trim(piece)
	scale = scale if scale > 0.0 else min(w / piece.width, h / piece.height)
	piece = piece.resize((max(1, round(piece.width * scale)), max(1, round(piece.height * scale))), Image.LANCZOS)
	cell = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	cell.alpha_composite(piece, ((w - piece.width) // 2, h - piece.height if grounded else (h - piece.height) // 2))
	return cell


def pieces(image: Image.Image, cols: int, rows: int) -> list[Image.Image]:
	pw, ph = image.width // cols, image.height // rows
	return [image.crop((c * pw, r * ph, (c + 1) * pw, (r + 1) * ph)) for r in range(rows) for c in range(cols)]


def main() -> None:
	for name, (source, cols, rows, w, h, out_cols, out) in SHEETS.items():
		image = Image.open(SRC / source).convert("RGBA")
		parts = pieces(image, cols, rows)
		scale = 0.0
		if name in SHARED_SCALE:
			trimmed = [trim(p) for p in parts]
			scale = min(w / max(t.width for t in trimmed), h / max(t.height for t in trimmed))
		cells = [fit(p, w, h, name in GROUNDED, scale) for p in parts]
		out_rows = (len(cells) + out_cols - 1) // out_cols
		sheet = Image.new("RGBA", (w * out_cols, h * out_rows), (0, 0, 0, 0))
		for i, cell in enumerate(cells):
			sheet.alpha_composite(cell, ((i % out_cols) * w, (i // out_cols) * h))
		out.parent.mkdir(parents=True, exist_ok=True)
		sheet.save(out, "WEBP", lossless=True)
		print(name, sheet.size, out.relative_to(ROOT))
	# Wall overlays laid on any painted wall: the cracks keep their dark browns; the hole is greyed
	# and brightened, so the game tints its rim rocks with the wall's own colour (modulate).
	crack = trim(Image.open(SRC / "crack-b.png").convert("RGBA"))
	crack.thumbnail((256, 256), Image.LANCZOS)
	crack.save(OUT / "goo-bomb/crack-overlay.webp", "WEBP", lossless=True)
	hole = trim(Image.open(SRC / "hole-a.png").convert("RGBA"))
	hole.thumbnail((256, 256), Image.LANCZOS)
	grey = ImageOps.grayscale(hole.convert("RGB")).point(lambda v: min(255, int(v * 1.35)))
	Image.merge("RGBA", (grey, grey, grey, hole.getchannel("A"))).save(OUT / "goo-bomb/hole-overlay.webp", "WEBP", lossless=True)
	print("crack-overlay", crack.size, "hole-overlay", hole.size)
	icons = Image.open(SRC / ICON_SOURCE).convert("RGBA")
	for piece, file_name in zip(pieces(icons, 2, 1), ICON_NAMES):
		cell = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
		art = trim(piece)
		art.thumbnail((92, 92), Image.LANCZOS)
		cell.alpha_composite(art, ((96 - art.width) // 2, (96 - art.height) // 2))
		cell.save(ICONS / file_name, "WEBP", lossless=True)
		print(file_name)


if __name__ == "__main__":
	main()
