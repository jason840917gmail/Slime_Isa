"""Packs the Stretch Lash effect sheet from the Magnific source art.

Sources (asset/Originals/effects/stretch-lash/): `tendril-a.png`, a horizontal
goo tendril (stump on the left, rope, blob tip on the right), and `splat-a.png`,
a goo splat. The tendril is cut into stump, rope and tip; every frame keeps the
stump and tip proportions and stretches only the rope, so the lash reads the
same at every length.

Output: asset/MAPS/effects/384x96-tile_4x2-stretch-lash.webp, eight 384x96
frames drawn at twice the display size (the game shows them at scale 0.5, so a
full frame is 192 px long). The stump sits at x=0, the tendril's centre line at
y=CENTRE_LINE (52): the game anchors the sprite at (0, 52/96) on the slime and
rotates it (`STRETCH_LASH_SHEET` in LegacyPlayerAbilityPresentation.ts).

Frames: 0-3 reach out, 4-5 hit (splat on the tip), 6-7 pull back.

Usage: python scripts/effects/pack-stretch-lash.py
"""
from pathlib import Path

from PIL import Image
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from game_webp import save_game_webp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'asset' / 'Originals' / 'effects' / 'stretch-lash'
OUTPUT = ROOT / 'asset' / 'MAPS' / 'effects' / '384x96-tile_4x2-stretch-lash.webp'

FRAME_W, FRAME_H = 384, 96
# The tendril's centre line; a little below the middle so the stump's top fits.
CENTRE_LINE = 52
COLS, ROWS = 4, 2
# Source cut points in tendril-a.png (x), and the band that holds the rope (y).
STUMP_END, TIP_START = 236, 1128
CENTRE_Y = 290
# One vertical scale for every part keeps the seams the same thickness.
SCALE = 0.38

# (length as a share of the frame, thickness factor, splat size in px or 0)
FRAMES = [
    (0.0, 0.9, 0),
    (0.35, 1.0, 0),
    (0.7, 1.0, 0),
    (1.0, 1.0, 0),
    (1.0, 1.0, 84),
    (1.0, 0.9, 60),
    (0.55, 0.85, 0),
    (0.0, 0.8, 0),
]


def trimmed(image: Image.Image) -> Image.Image:
    return image.crop(image.getbbox())


def part(tendril: Image.Image, left: int, right: int) -> Image.Image:
    """A vertical slice of the tendril, cropped to rows centred on the rope's centre line."""
    height = tendril.height
    half = max(CENTRE_Y, height - CENTRE_Y)
    return tendril.crop((left, CENTRE_Y - half, right, CENTRE_Y + half))


def scaled(image: Image.Image, sx: float, sy: float) -> Image.Image:
    width = max(1, round(image.width * sx))
    height = max(1, round(image.height * sy))
    return image.resize((width, height), Image.LANCZOS)


def build_frame(stump: Image.Image, rope: Image.Image, tip: Image.Image, splat: Image.Image,
                share: float, thickness: float, splat_size: int) -> Image.Image:
    frame = Image.new('RGBA', (FRAME_W, FRAME_H), (0, 0, 0, 0))
    sy = SCALE * thickness
    stump_part = scaled(stump, SCALE * thickness, sy)
    tip_part = scaled(tip, SCALE * thickness, sy)
    shortest = stump_part.width + tip_part.width - 12
    length = round(shortest + (FRAME_W - shortest) * share)
    rope_width = max(1, length - stump_part.width - tip_part.width + 12)
    rope_part = rope.resize((rope_width, stump_part.height), Image.LANCZOS)

    def paste(image: Image.Image, x: int) -> None:
        layer = Image.new('RGBA', frame.size, (0, 0, 0, 0))
        layer.paste(image, (x, CENTRE_LINE - image.height // 2))
        frame.alpha_composite(layer)

    paste(rope_part, stump_part.width - 6)
    paste(stump_part, 0)
    tip_x = length - tip_part.width
    paste(tip_part, tip_x)
    if splat_size:
        blob = splat.resize((splat_size, splat_size), Image.LANCZOS)
        centre_x = min(tip_x + tip_part.width // 2, FRAME_W - splat_size // 2)
        layer = Image.new('RGBA', frame.size, (0, 0, 0, 0))
        layer.paste(blob, (centre_x - splat_size // 2, CENTRE_LINE - splat_size // 2))
        frame.alpha_composite(layer)
    return frame


def main() -> None:
    tendril = Image.open(SOURCE / 'tendril-a.png').convert('RGBA')
    splat = trimmed(Image.open(SOURCE / 'splat-a.png').convert('RGBA'))
    right = tendril.getbbox()[2]
    stump = part(tendril, tendril.getbbox()[0], STUMP_END)
    rope = part(tendril, STUMP_END, TIP_START)
    tip = part(tendril, TIP_START, right)
    sheet = Image.new('RGBA', (FRAME_W * COLS, FRAME_H * ROWS), (0, 0, 0, 0))
    for index, (share, thickness, splat_size) in enumerate(FRAMES):
        frame = build_frame(stump, rope, tip, splat, share, thickness, splat_size)
        sheet.paste(frame, ((index % COLS) * FRAME_W, (index // COLS) * FRAME_H))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    save_game_webp(sheet, OUTPUT)
    print(f'wrote {OUTPUT.relative_to(ROOT)} ({sheet.width}x{sheet.height})')


if __name__ == '__main__':
    main()
