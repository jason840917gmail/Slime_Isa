"""Pack the Slimeshire Forge, an outdoor smelting furnace in the forge yard (frame 0 ruined, frame 1 restored),
into one 256x256 two-frame sheet.

Sources are Magnific GPT-2 renders on white (`asset/Originals/houses/generated/forge-furnace-source.png` and
`forge-furnace-ruined-source.png`, the ruin made from the restored render), cut out here. The restored render's
chimney smoke is dropped: a still sprite cannot drift. Both frames share one scale and sit on the same base
centre, so the Forge does not jump when it is restored.

    python scripts/houses/pack-forge.py
"""
from pathlib import Path
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from game_webp import save_game_webp  # noqa: E402
from white_cutout import cut_out  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / 'asset' / 'Originals' / 'houses' / 'generated'
OUT = ROOT / 'asset' / 'MAPS' / 'Houses' / '256-forge-2x1.webp'
FRAME = 256
ART_WIDTH = 172   # the restored furnace's width in the frame (under 3 tiles: it stands in the yard beside the home)
BOTTOM_MARGIN = 3


def without_smoke(art: Image.Image) -> Image.Image:
    """Clears the pale smoke plume above the chimney: every row above the first solid (non-smoke) row."""
    pixels = np.array(art)
    rgb = pixels[..., :3].astype(np.int32)
    smoke = (rgb.max(axis=2) - rgb.min(axis=2) < 30) & (rgb.max(axis=2) > 150)
    solid = (pixels[..., 3] > 0) & ~smoke
    top = next(y for y in range(pixels.shape[0]) if solid[y].sum() > 40)
    pixels[: max(0, top - 2), :, 3] = 0
    pixels[smoke & (np.arange(pixels.shape[0])[:, None] < top + 24), 3] = 0
    return Image.fromarray(pixels, 'RGBA')


def main() -> None:
    restored = without_smoke(cut_out(SOURCES / 'forge-furnace-source.png', holes=True))
    ruined = cut_out(SOURCES / 'forge-furnace-ruined-source.png', holes=True)
    restored_box, ruined_box = restored.getbbox(), ruined.getbbox()
    scale = ART_WIDTH / (restored_box[2] - restored_box[0])
    sheet = Image.new('RGBA', (FRAME * 2, FRAME), (0, 0, 0, 0))
    for index, (art, box) in enumerate(((ruined, ruined_box), (restored, restored_box))):
        art = art.crop(box)
        size = (round(art.width * scale), round(art.height * scale))
        # Premultiplied resize keeps the transparent edge free of dark fringes.
        art = art.convert('RGBa').resize(size, Image.LANCZOS).convert('RGBA')
        if art.height > FRAME - BOTTOM_MARGIN:
            raise SystemExit(f'frame {index} is {art.height} px tall; lower ART_WIDTH')
        sheet.alpha_composite(art, (index * FRAME + (FRAME - art.width) // 2, FRAME - BOTTOM_MARGIN - art.height))
    kind = save_game_webp(sheet, OUT)
    print(f'wrote {OUT.relative_to(ROOT)} ({kind})')


if __name__ == '__main__':
    main()
