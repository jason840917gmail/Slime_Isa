"""Packs the lash bell post (the Stretch Lash switch) from the Magnific source art.

Source: asset/Originals/effects/stretch-lash/bell-post-b.png. Frame 0 is the
post at rest; frames 1 and 2 swing the bell about its chain (the bell is cut out
of the source and rotated), so ringing it plays 1, 2, 1, 0.

Output: asset/MAPS/objects/256x256-tile_3x1-lash-bell-post.webp, three 256x256
frames, the post's foot centred on the bottom edge.

Usage: python scripts/effects/pack-lash-bell.py
"""
from pathlib import Path

from PIL import Image
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from game_webp import save_game_webp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'asset' / 'Originals' / 'effects' / 'stretch-lash' / 'bell-post-b.png'
OUTPUT = ROOT / 'asset' / 'MAPS' / 'objects' / '256x256-tile_3x1-lash-bell-post.webp'

FRAME = 256
# The bell hangs left of the post in the source: its box and its hanging point.
BELL_BOX = (262, 318, 452, 530)
PIVOT = (354, 318)
SWINGS = [0, 16, -12]


def swung(post: Image.Image, degrees: float) -> Image.Image:
    if not degrees:
        return post.copy()
    bell = post.crop(BELL_BOX)
    frame = post.copy()
    frame.paste(Image.new('RGBA', bell.size, (0, 0, 0, 0)), BELL_BOX[:2])
    layer = Image.new('RGBA', post.size, (0, 0, 0, 0))
    layer.paste(bell, BELL_BOX[:2])
    layer = layer.rotate(degrees, resample=Image.BICUBIC, center=PIVOT)
    frame.alpha_composite(layer)
    return frame


def main() -> None:
    post = Image.open(SOURCE).convert('RGBA')
    frames = [swung(post, degrees) for degrees in SWINGS]
    # One crop for every frame (the union of their boxes) keeps the post still.
    boxes = [frame.getbbox() for frame in frames]
    box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    scale = (FRAME - 4) / max(box[2] - box[0], box[3] - box[1])
    sheet = Image.new('RGBA', (FRAME * len(frames), FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        cropped = frame.crop(box)
        size = (round(cropped.width * scale), round(cropped.height * scale))
        cropped = cropped.resize(size, Image.LANCZOS)
        sheet.paste(cropped, (index * FRAME + (FRAME - size[0]) // 2, FRAME - size[1]))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    save_game_webp(sheet, OUTPUT)
    print(f'wrote {OUTPUT.relative_to(ROOT)} ({sheet.width}x{sheet.height})')


if __name__ == '__main__':
    main()
