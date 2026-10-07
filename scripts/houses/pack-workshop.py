"""Pack the Slimeshire Workshop exterior (frame 0 ruined, frame 1 restored) into one 320x320 two-frame sheet.

Both frames share one crop box so the building does not jump when the ruin is restored. Sources are the
Magnific GPT-2 renders in asset/Originals/houses/generated/.

    python scripts/houses/pack-workshop.py
"""
from pathlib import Path

from PIL import Image
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from game_webp import save_game_webp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / 'asset' / 'Originals' / 'houses' / 'generated'
OUT = ROOT / 'godot' / 'asset' / 'MAPS' / 'Houses' / '320-workshop-2x1.webp'
FRAME = 320
MAX_WIDTH = 300
BOTTOM_MARGIN = 2


def main() -> None:
    sources = [Image.open(SOURCES / f'workshop-{state}-source.png').convert('RGBA') for state in ('ruined', 'restored')]
    boxes = [source.getbbox() for source in sources]
    box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    width, height = box[2] - box[0], box[3] - box[1]
    scale = min(1.0, MAX_WIDTH / width, (FRAME - BOTTOM_MARGIN) / height)
    size = (round(width * scale), round(height * scale))
    sheet = Image.new('RGBA', (FRAME * len(sources), FRAME), (0, 0, 0, 0))
    for index, source in enumerate(sources):
        # Premultiplied resize keeps the transparent edge free of dark fringes.
        art = source.crop(box).convert('RGBa').resize(size, Image.LANCZOS).convert('RGBA')
        sheet.alpha_composite(art, (index * FRAME + (FRAME - art.width) // 2, FRAME - BOTTOM_MARGIN - art.height))
    save_game_webp(sheet, OUT)
    print(f'wrote {OUT.relative_to(ROOT)} ({size[0]}x{size[1]} art per frame)')


if __name__ == '__main__':
    main()
