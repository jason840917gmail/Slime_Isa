"""Packs the water wake sheet: what anyone walking or swimming in water shows at its feet.

Sources (asset/Originals/water/generated/, Magnific GPT 2.5, transparent, 2 x 2 grids of 512 px):
  wade-splash.png   4 frames: a low oval ring of shallow water with splashes kicked up at its ends
                    (rising, highest, falling, settled)
  swim-ripple.png   4 frames: calm rings around a swimmer that swell and fade (loops)

Each frame is aligned on its ring, not on its grid cell (the generator draws the rings at slightly
different places): the ring is the band of rows where the art is dense, and its centre goes to the
same point of every cell (ANCHOR). One scale per row puts the rings at RING_WIDTH art pixels across
(2 px per world unit: 60 units for the wading ring, 70 for the swimming ring, sized for the player
slime; other bodies scale it by their width).

Writes godot/asset/MAPS/water/<w>x<h>-tile_4x2-water-wake.webp: row 0 the wading splash, row 1 the
swim ripple, and prints the cell size and anchor that game/world/water_wake.gd uses.

  python scripts/art/build-water-wake-sheet.py
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

SOURCES = ROOT / "asset" / "Originals" / "water" / "generated"
OUT = ROOT / "godot" / "asset" / "MAPS" / "water"
GRID_CELL = 512
FRAMES = 4
# Row name -> (source, ring width in art px).
ROWS = {
    "wade": ("wade-splash.png", 120),
    "swim": ("swim-ripple.png", 140),
}
# Cell size and where the ring's centre sits in it (art px); the splashes rise above the ring.
CELL = (224, 128)
ANCHOR = (112, 84)
# Alpha below this is generator haze, cleared.
ALPHA_FLOOR = 30
# Art fades out over this many source pixels at the grid cell's sides.
EDGE_FADE = 24.0
# A row of the ring band has at least this share of the frame's widest row opaque.
DENSE_SHARE = 0.35


def ring_box(alpha: np.ndarray) -> tuple[float, float, float]:
    """Centre x, centre y and width of the ring: the band of dense rows (splash droplets are sparse)."""
    solid = alpha > 40
    rows = solid.sum(axis=1)
    dense = np.nonzero(rows >= rows.max() * DENSE_SHARE)[0]
    band = solid[dense.min():dense.max() + 1]
    xs = np.nonzero(band.any(axis=0))[0]
    return (xs.min() + xs.max()) / 2.0, (dense.min() + dense.max()) / 2.0, float(xs.max() - xs.min())


def main() -> None:
    sheet = Image.new("RGBA", (CELL[0] * FRAMES, CELL[1] * len(ROWS)), (0, 0, 0, 0))
    for row, (name, (source, ring_width)) in enumerate(ROWS.items()):
        grid = Image.open(SOURCES / source).convert("RGBA")
        frames = []
        for i in range(FRAMES):
            box = ((i % 2) * GRID_CELL, (i // 2) * GRID_CELL)
            frame = grid.crop((box[0], box[1], box[0] + GRID_CELL, box[1] + GRID_CELL))
            pixels = np.array(frame)
            pixels[..., 3][pixels[..., 3] < ALPHA_FLOOR] = 0
            # Fade the art out toward the grid cell's sides: a ring the generator drew against its
            # cell border would otherwise end in a straight cut.
            ramp = np.clip(np.minimum(np.arange(GRID_CELL), np.arange(GRID_CELL)[::-1]) / EDGE_FADE, 0.0, 1.0)
            pixels[..., 3] = (pixels[..., 3] * np.minimum.outer(ramp, ramp)).astype(np.uint8)
            frames.append(Image.fromarray(pixels))
        boxes = [ring_box(np.array(f)[..., 3]) for f in frames]
        scale = ring_width / float(np.mean([b[2] for b in boxes]))
        clipped = 0
        for i, (frame, (cx, cy, _w)) in enumerate(zip(frames, boxes)):
            size = (round(GRID_CELL * scale), round(GRID_CELL * scale))
            small = frame.resize(size, Image.LANCZOS)
            at = (round(ANCHOR[0] - cx * scale), round(ANCHOR[1] - cy * scale))
            cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
            cell.alpha_composite(small, dest=(max(at[0], 0), max(at[1], 0)),
                                 source=(max(-at[0], 0), max(-at[1], 0)))
            clipped += int(np.array(small)[..., 3].astype(np.int64).sum() - np.array(cell)[..., 3].astype(np.int64).sum())
            sheet.alpha_composite(cell, dest=(i * CELL[0], row * CELL[1]))
        print(f"{name}: scale {scale:.3f}, ring {ring_width} px, alpha clipped by the cell {clipped / 255:.0f} px")
    path = OUT / f"{CELL[0]}x{CELL[1]}-tile_{FRAMES}x{len(ROWS)}-water-wake.webp"
    save_game_webp(sheet, path)
    print(f"wrote {path.relative_to(ROOT)}: cell {CELL}, ring centre at {ANCHOR}")


if __name__ == "__main__":
    main()
