"""Pack the Chapter 2 weapon art into one 128x128 four-frame sheet (`MAPS/weapons/128x128-tile_4x1-iron-tools.webp`).

Frames follow the stone weapons' conventions so the iron weapons can reuse their swing animations:
  0 iron spear, diagonal with the head to the upper right (like `starter-spears` frame 2)
  1 iron spear thrust: the same spear with a pale silver trail (like `starter-spears` frame 3)
  2 iron axe, upright (like `stone-tools` frame 2)
  3 Reinforced Pickaxe, upright (like `stone-tools` frame 3)

Source: one Magnific GPT-2 render of the three upright tools on white
(`asset/Originals/weapon/iron-tools/iron-tools-source.png`), cut out here.

    python scripts/weapons/pack-iron-tools.py
"""
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from game_webp import save_game_webp  # noqa: E402
from white_cutout import cut_out  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'asset' / 'Originals' / 'weapon' / 'iron-tools' / 'iron-tools-source.png'
OUT = ROOT / 'asset' / 'MAPS' / 'weapons' / '128x128-tile_4x1-iron-tools.webp'
FRAME = 128
UPRIGHT_HEIGHT = 126  # the stone tools fill the frame height
DIAGONAL_SPAN = 104   # the starter spears span about 100 px each way


def tools(sheet: Image.Image) -> list[Image.Image]:
    """The three tools, left to right, split at the empty columns between them."""
    alpha = np.array(sheet.getchannel('A')) > 16
    filled = alpha.any(axis=0)
    spans, start = [], None
    for x, on in enumerate(filled):
        if on and start is None:
            start = x
        elif not on and start is not None:
            spans.append((start, x))
            start = None
    if start is not None:
        spans.append((start, len(filled)))
    spans = [span for span in spans if span[1] - span[0] > 20]
    if len(spans) != 3:
        raise SystemExit(f'expected 3 tools in the source, found {len(spans)}')
    parts = [sheet.crop((left, 0, right, sheet.height)) for left, right in spans]
    return [part.crop(part.getbbox()) for part in parts]


def resized(art: Image.Image, scale: float) -> Image.Image:
    # Premultiplied resize keeps the transparent edge free of dark fringes.
    return art.convert('RGBa').resize((max(1, round(art.width * scale)), max(1, round(art.height * scale))), Image.LANCZOS).convert('RGBA')


def upright(art: Image.Image) -> Image.Image:
    art = resized(art, UPRIGHT_HEIGHT / art.height)
    frame = Image.new('RGBA', (FRAME, FRAME), (0, 0, 0, 0))
    frame.alpha_composite(art, ((FRAME - art.width) // 2, FRAME - 1 - art.height))
    return frame


def diagonal(art: Image.Image) -> Image.Image:
    # Rotate clockwise so the head points to the upper right, as the spear swings expect.
    turned = art.convert('RGBa').rotate(-45, resample=Image.BICUBIC, expand=True).convert('RGBA')
    turned = turned.crop(turned.getbbox())
    turned = resized(turned, DIAGONAL_SPAN / max(turned.size))
    frame = Image.new('RGBA', (FRAME, FRAME), (0, 0, 0, 0))
    frame.alpha_composite(turned, ((FRAME - turned.width) // 2, (FRAME - turned.height) // 2))
    return frame


def thrust(spear: Image.Image) -> Image.Image:
    """The spear with a pale silver glow on its head and thin speed streaks behind it, like the stone thrust."""
    alpha = np.array(spear.getchannel('A')).astype(np.float64) / 255
    ys, xs = np.nonzero(alpha > 0.1)
    along = xs - ys  # the spear runs at 45 degrees: larger toward the head (upper right)
    low, high = along.min(), along.max()
    grid_y, grid_x = np.mgrid[0:FRAME, 0:FRAME]
    head = alpha * ((grid_x - grid_y) > high - 0.42 * (high - low))
    glow = Image.new('RGBA', spear.size, (222, 236, 255, 0))
    glow.putalpha(Image.fromarray((head * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5)).point(lambda value: min(255, int(value * 1.6))))
    streaks = Image.new('RGBA', spear.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(streaks)
    tip_x, tip_y = xs[along.argmax()], ys[along.argmax()]
    axis = np.array([1.0, -1.0]) / np.sqrt(2)
    side = np.array([1.0, 1.0]) / np.sqrt(2)
    for offset, start_back, length in ((-11, 14, 54), (-7, 4, 76), (7, 6, 70), (11, 18, 48)):
        origin = np.array([tip_x, tip_y]) - axis * start_back + side * offset
        segments = 12
        for index in range(segments):
            a = origin - axis * (length * index / segments)
            b = origin - axis * (length * (index + 1) / segments)
            fade = int(240 * (1 - index / segments))
            draw.line([tuple(a), tuple(b)], fill=(170, 205, 255, fade), width=3)
    streaks = streaks.filter(ImageFilter.GaussianBlur(0.6))
    frame = Image.new('RGBA', spear.size, (0, 0, 0, 0))
    frame.alpha_composite(glow)
    frame.alpha_composite(streaks)
    frame.alpha_composite(spear)
    return frame


def main() -> None:
    spear, axe, pickaxe = tools(cut_out(SOURCE, holes=True))
    spear_frame = diagonal(spear)
    frames = [spear_frame, thrust(spear_frame), upright(axe), upright(pickaxe)]
    sheet = Image.new('RGBA', (FRAME * len(frames), FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (index * FRAME, 0))
    kind = save_game_webp(sheet, OUT)
    print(f'wrote {OUT.relative_to(ROOT)} ({kind})')


if __name__ == '__main__':
    main()
