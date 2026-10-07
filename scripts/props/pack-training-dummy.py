"""Packs the playground's straw training dummy from its Magnific source.

Source: asset/Originals/props/training-dummy/dummy-b.png (Magnific GPT-2 on a
plain background, cut out with Magnific's background removal).
Output: godot/asset/MAPS/objects/256x256-tile_1x1-training-dummy.webp, one 256x256
frame with the base on the bottom edge (the dummy wobbles about its base).

Usage: python scripts/props/pack-training-dummy.py
"""
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from game_webp import save_game_webp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'asset' / 'Originals' / 'props' / 'training-dummy' / 'dummy-b.png'
OUTPUT = ROOT / 'godot' / 'asset' / 'MAPS' / 'objects' / '256x256-tile_1x1-training-dummy.webp'
FRAME = 256


def main() -> None:
    art = Image.open(SOURCE).convert('RGBA')
    art = art.crop(art.getbbox())
    scale = (FRAME - 4) / max(art.size)
    art = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
    sheet = Image.new('RGBA', (FRAME, FRAME), (0, 0, 0, 0))
    sheet.paste(art, ((FRAME - art.width) // 2, FRAME - art.height))
    kind = save_game_webp(sheet, OUTPUT)
    print(f'wrote {OUTPUT.relative_to(ROOT)} ({kind})')


if __name__ == '__main__':
    main()
