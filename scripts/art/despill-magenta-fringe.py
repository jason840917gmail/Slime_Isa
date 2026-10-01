"""Remove magenta chroma-key fringe left around sprites after background removal.

Only pixels that are magenta-tinted AND connected to transparency through other
magenta pixels (within --depth px of the silhouette) are touched, so art that is
purple on purpose deeper inside a sprite is kept (--all drops that guard for
sheets with no intended purple). The outermost fringe ring is made transparent;
the rest is inpainted inward from the surrounding clean pixels.

Usage:
  python scripts/art/despill-magenta-fringe.py [--depth 6] [--all] [--min-blue 30] [--write] asset/MAPS/foo.webp ...
Without --write it only reports counts. Needs Pillow + numpy.
"""
import argparse
import numpy as np
from PIL import Image
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from game_webp import save_game_webp  # noqa: E402


MIN_BLUE_OVER_GREEN = 30


def magenta(a):
    r, g, b = (a[..., i].astype(int) for i in range(3))
    return (a[..., 3] > 0) & (r - g > 15) & (b - g > MIN_BLUE_OVER_GREEN) & (b > 50) & (b * 10 >= r * 6)


def neighbours(mask):
    """4-neighbour dilation."""
    out = mask.copy()
    out[1:] |= mask[:-1]
    out[:-1] |= mask[1:]
    out[:, 1:] |= mask[:, :-1]
    out[:, :-1] |= mask[:, 1:]
    return out


def fringe_mask(a, depth):
    mag = magenta(a)
    frontier = ~(a[..., 3] > 0)
    fringe = np.zeros_like(mag)
    rings = []
    for _ in range(depth):
        ring = neighbours(frontier) & mag & ~fringe
        if not ring.any():
            break
        rings.append(ring)
        fringe |= ring
        frontier = frontier | ring
    return fringe, rings


def box_sum(x, r):
    p = np.pad(x, r)
    c = p.cumsum(0).cumsum(1)
    c = np.pad(c, ((1, 0), (1, 0)))
    k = 2 * r + 1
    return c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]


def fix(a, depth, everywhere=False):
    fringe, rings = fringe_mask(a, depth)
    if everywhere:
        fringe = fringe | magenta(a)
    if not fringe.any():
        return a, 0
    out = a.copy()
    rgb = a[..., :3].astype(np.float64)
    known = (a[..., 3] > 0) & ~fringe
    todo = fringe.copy()
    # Inpaint inward: each pass fills fringe pixels touching known pixels with
    # their (slightly darkened) mean, so colours come from the surrounding art.
    for _ in range(64):
        if not todo.any():
            break
        w = known.astype(np.float64)
        n = box_sum(w, 1)
        ready = todo & (n > 0)
        if not ready.any():
            break
        sums = np.stack([box_sum(rgb[..., i] * w, 1) for i in range(3)], -1)
        rgb[ready] = sums[ready] / n[ready][:, None] * 0.97
        known |= ready
        todo &= ~ready
    # Isolated leftovers: warm grey at the same brightness.
    lum = rgb[todo].mean(axis=1, keepdims=True)
    rgb[todo] = lum * np.array([1.0, 0.92, 0.82])
    out[..., :3][fringe] = np.clip(rgb[fringe], 0, 255).astype(np.uint8)
    if rings:
        out[..., 3][rings[0]] = 0
        out[..., :3][rings[0]] = 0
    return out, int(fringe.sum())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--depth", type=int, default=6)
    ap.add_argument("--all", action="store_true",
                    help="also repaint magenta pixels inside the sprite (sheets with no intended purple)")
    ap.add_argument("--min-blue", type=int, default=30,
                    help="blue-over-green margin that counts as magenta (lower catches darker violet)")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("paths", nargs="+")
    args = ap.parse_args()
    global MIN_BLUE_OVER_GREEN
    MIN_BLUE_OVER_GREEN = args.min_blue
    for p in args.paths:
        im = Image.open(p)
        a = np.array(im.convert("RGBA"))
        out, count = fix(a, args.depth, args.all)
        print(f"{count:7d} fringe px  {p}")
        if args.write and count:
            if str(p).lower().endswith(".webp"):
                save_game_webp(Image.fromarray(out, "RGBA"), p)
            else:
                Image.fromarray(out, "RGBA").save(p, optimize=True)


if __name__ == "__main__":
    main()
