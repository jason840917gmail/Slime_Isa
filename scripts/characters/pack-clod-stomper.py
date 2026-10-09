"""Packs the Clod Stomper's sheet (roadmap 8.12) from its Magnific stills.

Sources (asset/Originals/enemies/clod-stomper/, GPT 2.5 with a transparent background; prompts in
the README there): `idle-a.png` (the chosen look; `idle-b.png` was the other take), then poses made
from it as an image reference: `crouch.png`, `air.png`, `slam.png`, `defeated.png`.

Each still is trimmed to its opaque pixels and drawn at ONE scale (the idle is TARGET_WIDTH px
wide), centred at x 128 and standing on y BOTTOM of a 256 px cell, so the poses keep their sizes
relative to each other. Frames, left to right: idle, crouch, air, slam, defeated.

Writes godot/asset/MAPS/enemies/256x256-tile_5x1-clod-stomper.webp.

usage: python scripts/characters/pack-clod-stomper.py
Needs Pillow and numpy.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

SOURCES = REPO / "asset" / "Originals" / "enemies" / "clod-stomper"
OUTPUT = REPO / "godot" / "asset" / "MAPS" / "enemies" / "256x256-tile_5x1-clod-stomper.webp"
FRAMES = ["idle-a", "crouch", "air", "slam", "defeated"]
CELL = 256
TARGET_WIDTH = 170
BOTTOM = 248
CENTRE_X = 128
ALPHA_CUT = 24


def trimmed(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    alpha = np.asarray(image)[..., 3]
    ys, xs = np.nonzero(alpha > ALPHA_CUT)
    return image.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def main() -> None:
    stills = [trimmed(SOURCES / f"{name}.png") for name in FRAMES]
    scale = TARGET_WIDTH / stills[0].width
    sheet = Image.new("RGBA", (CELL * len(FRAMES), CELL), (0, 0, 0, 0))
    for column, (name, still) in enumerate(zip(FRAMES, stills)):
        size = (round(still.width * scale), round(still.height * scale))
        if size[0] > CELL or size[1] > BOTTOM:
            raise SystemExit(f"{name}: {size} does not fit a {CELL} px cell")
        art = still.resize(size, Image.LANCZOS)
        sheet.alpha_composite(art, (column * CELL + CENTRE_X - size[0] // 2, BOTTOM - size[1]))
        print(f"{name:9s} {size[0]} x {size[1]}")
    save_game_webp(sheet, OUTPUT)
    print(f"wrote {OUTPUT.relative_to(REPO)} (scale {scale:.4f})")


if __name__ == "__main__":
    main()
