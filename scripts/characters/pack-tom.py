"""Packs Tom (roadmap 8.13) and the web he is caught in from their Magnific stills.

Sources (asset/Originals/characters/tom/, GPT 2.5 with a transparent background; prompts in the
README there): `tom-a.png` (Tom, the chosen take; `tom-b-sheet.png` was the other take, an
expression sheet), `cocoon.png` (Tom wrapped in silk between two twigs, made from tom-a) and
`web-torn.png` (the torn, empty web).

Each still is trimmed to its opaque pixels, centred at x 128 and stood on y BOTTOM of a 256 px
cell. Tom is TOM_HEIGHT px tall; the cocoon is COCOON_HEIGHT px tall and the torn web is drawn at
the cocoon's scale, so it sits where the cocoon stood.

Writes godot/asset/characters/authored/npcs/tom.webp (one cell) and
godot/asset/MAPS/props/256x256-tile_2x1-tom-web.webp (cocoon, torn).

usage: python scripts/characters/pack-tom.py
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

SOURCES = REPO / "asset" / "Originals" / "characters" / "tom"
TOM_OUTPUT = REPO / "godot" / "asset" / "characters" / "authored" / "npcs" / "tom.webp"
WEB_OUTPUT = REPO / "godot" / "asset" / "MAPS" / "props" / "256x256-tile_2x1-tom-web.webp"
CELL = 256
BOTTOM = 252
CENTRE_X = 128
TOM_HEIGHT = 210
COCOON_HEIGHT = 228
ALPHA_CUT = 24


def trimmed(name: str) -> Image.Image:
    image = Image.open(SOURCES / name).convert("RGBA")
    alpha = np.asarray(image)[..., 3]
    ys, xs = np.nonzero(alpha > ALPHA_CUT)
    return image.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def draw(sheet: Image.Image, still: Image.Image, scale: float, column: int) -> None:
    size = (round(still.width * scale), round(still.height * scale))
    if size[0] > CELL or size[1] > BOTTOM:
        raise SystemExit(f"{size} does not fit a {CELL} px cell")
    sheet.alpha_composite(still.resize(size, Image.LANCZOS), (column * CELL + CENTRE_X - size[0] // 2, BOTTOM - size[1]))
    print(f"cell {column}: {size[0]} x {size[1]}")


def main() -> None:
    tom = trimmed("tom-a.png")
    sheet = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw(sheet, tom, TOM_HEIGHT / tom.height, 0)
    save_game_webp(sheet, TOM_OUTPUT)
    cocoon = trimmed("cocoon.png")
    torn = trimmed("web-torn.png")
    scale = COCOON_HEIGHT / cocoon.height
    web = Image.new("RGBA", (CELL * 2, CELL), (0, 0, 0, 0))
    draw(web, cocoon, scale, 0)
    draw(web, torn, min(scale, CELL / torn.width, BOTTOM / torn.height), 1)
    save_game_webp(web, WEB_OUTPUT)
    print(f"wrote {TOM_OUTPUT.relative_to(REPO)} and {WEB_OUTPUT.relative_to(REPO)}")


if __name__ == "__main__":
    main()
