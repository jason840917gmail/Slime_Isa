"""Packs the spider web decorations into one sheet (playtest 2026-10-01).

Sources: asset/Originals/props/webs/*.png, generated with Magnific GPT-2 on a
flat #FF00FF background (webs are white, so a white background would not cut).
The magenta is keyed out, the fringe repainted with despill-magenta-fringe,
each piece cropped and fitted into a 256 px cell:

  0 ground-web-a     1 ground-web-b     2 tree-web-a        3 tree-web-b
  4 hanging-cocoon-a 5 hanging-cocoon-b 6 hanging-cocoon-c  7 ground-cocoon-a
  8 ground-cocoon-b  9 egg-sacs-a      10 egg-sacs-b       11 (empty)

Things that hang (tree webs, hanging cocoons) touch the top of their cell, so
an origin of [0.5, 0] hangs them from their thread; the rest sit on the bottom
of their cell (origin [0.5, 1]).

Usage: python scripts/props/pack-web-decor.py
"""
import importlib.util
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

SOURCES = ROOT / "asset" / "Originals" / "props" / "webs"
OUT = ROOT / "asset" / "MAPS" / "props" / "256x256-tile_4x3-web-decor.webp"
CELL = 256
MARGIN = 6
COLS = 4
PIECES = [
    ("ground-web-a", "bottom"), ("ground-web-b", "bottom"), ("tree-web-a", "top"), ("tree-web-b", "top"),
    ("hanging-cocoon-a", "top"), ("hanging-cocoon-b", "top"), ("hanging-cocoon-c", "top"), ("ground-cocoon-a", "bottom"),
    ("ground-cocoon-b", "bottom"), ("egg-sacs-a", "bottom"), ("egg-sacs-b", "bottom"),
]


def load_despill():
    path = ROOT / "scripts" / "art" / "despill-magenta-fringe.py"
    spec = importlib.util.spec_from_file_location("despill_magenta_fringe", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MAGENTA = np.array([255.0, 0.0, 255.0])
# Pure dark outlines key to about 0.88 alpha; this lifts solid paint back to opaque.
ALPHA_GAIN = 1 / 0.85


#: Pixels this close to the flat background are keyed; deeper paint stays opaque.
EDGE_BAND_PX = 6


def near_background(rgb):
    """The flat background, grown by EDGE_BAND_PX (4-neighbour steps)."""
    distance = np.sqrt(((rgb.astype(np.float64) - MAGENTA) ** 2).sum(axis=-1))
    mask = distance < 60
    for _ in range(EDGE_BAND_PX):
        grown = mask.copy()
        grown[1:] |= mask[:-1]
        grown[:-1] |= mask[1:]
        grown[:, 1:] |= mask[:, :-1]
        grown[:, :-1] |= mask[:, 1:]
        mask = grown
    return mask


def key_magenta(rgb):
    """Difference key against #FF00FF near the background: each pixel's least alpha
    that un-blends to a valid colour.

    Thin silk strands are mostly a blend with the background, so their colour is
    un-blended too (observed = a * colour + (1 - a) * magenta); without that the
    webs keep a pink tint. Paint deeper inside a piece stays opaque: its shading
    carries magenta bounce light that a plain key would read as see-through.
    """
    c = rgb.astype(np.float64) / 255.0
    alpha = np.max(np.stack([1.0 - c[..., 0], c[..., 1], 1.0 - c[..., 2]]), axis=0)
    alpha = np.clip(alpha * ALPHA_GAIN, 0.0, 1.0)
    alpha[alpha < 0.04] = 0.0
    alpha[~near_background(rgb)] = 1.0
    safe = np.maximum(alpha, 1e-6)[..., None]
    colour = (rgb.astype(np.float64) - (1.0 - alpha[..., None]) * MAGENTA) / safe
    colour = np.clip(colour, 0, 255)
    colour[alpha == 0] = 0
    return np.dstack([colour, alpha * 255.0]).round().astype(np.uint8)


def cut(name):
    rgba = key_magenta(np.array(Image.open(SOURCES / f"{name}.png").convert("RGB")))
    ys, xs = np.nonzero(rgba[..., 3] > 8)
    return rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def fit(piece, anchor):
    height, width = piece.shape[:2]
    scale = min((CELL - 2 * MARGIN) / width, (CELL - 2 * MARGIN) / height)
    size = (max(1, round(width * scale)), max(1, round(height * scale)))
    image = Image.fromarray(piece, "RGBA").resize(size, Image.LANCZOS)
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    x = (CELL - size[0]) // 2
    y = 0 if anchor == "top" else CELL - size[1] - MARGIN // 2
    cell.alpha_composite(image, (x, y))
    return np.array(cell)


def main():
    rows = (len(PIECES) + COLS - 1) // COLS
    sheet = np.zeros((rows * CELL, COLS * CELL, 4), np.uint8)
    for index, (name, anchor) in enumerate(PIECES):
        row, col = divmod(index, COLS)
        sheet[row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL] = fit(cut(name), anchor)
        print(f"{index:2d} {name}")
    despill = load_despill()
    sheet, repainted = despill.fix(sheet, 6)
    print(f"despilled {repainted} fringe px")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    save_game_webp(Image.fromarray(sheet, "RGBA"), OUT)
    print(OUT)


if __name__ == "__main__":
    main()
