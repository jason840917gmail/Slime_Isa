"""Pack the Magnific GPT-2 mushroom house exteriors into a 320 px house sheet.

Sources live in asset/Originals/houses/ (1024x1024 transparent generations). Each
house is trimmed, scaled to fit the same 320 px frame as sheet.houses.3x1 (never
upscaled), and bottom-centre anchored with a 4 px margin, matching the render
origin [0.5, 1] used by the house scenes.

Both are top-down: the spotted cap fills most of the sprite and only a thin strip
of wall with the door shows under its front edge, like the other houses.

Frame 0: mushroom-house-topdown-a (wide cap, chimney and dormer)
Frame 1: mushroom-house-topdown-b (rounder cap, dormer on the right)

Usage: python scripts/houses/normalize-mushroom-houses.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from game_webp import save_game_webp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "asset" / "Originals" / "houses"
OUTPUT = ROOT / "godot" / "asset" / "MAPS" / "Houses" / "320-mushroom-2x1.webp"

FRAME = 320
TARGET = 300  # longest side of the house art inside its frame, like the existing houses
MARGIN = 4
HOUSES = ["mushroom-house-topdown-a", "mushroom-house-topdown-b"]


def main() -> None:
    sheet = Image.new("RGBA", (FRAME * len(HOUSES), FRAME), (0, 0, 0, 0))
    for index, stem in enumerate(HOUSES):
        art = Image.open(SOURCES / f"{stem}-source.png").convert("RGBA")
        art = art.crop(art.getbbox())
        scale = min(1.0, TARGET / max(art.size))
        size = (round(art.width * scale), round(art.height * scale))
        # premultiplied resample avoids dark fringes around transparent edges
        art = art.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
        x = index * FRAME + (FRAME - art.width) // 2
        y = FRAME - MARGIN - art.height
        sheet.alpha_composite(art, (x, y))
        print(f"frame {index}: {stem} {art.width}x{art.height} at ({x - index * FRAME}, {y}) scale {scale:.4f}")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    save_game_webp(sheet, OUTPUT)
    print(f"wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
