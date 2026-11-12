"""Build the 19x19 ground sheets (64x64 tiles) in godot/asset/MAPS/grounds/.

Every ground is one large 1216x1216 image cut row-major into 64x64 frames,
saved as lossless WebP (identical pixels, about 45% smaller than PNG).
Each image is made to wrap seamlessly (its right edge continues into its left,
its bottom into its top), so the runtime repeats the sheet without mirroring
(`selection: "sheet-wrap"` in the terrain tile set) and no symmetry seams
appear every 19 tiles.

Wrap technique: the image is offset by half its size, which moves the
original's hard edges to the centre and makes the new borders continuous, then
the original is blended back over the centre through a soft noisy mask, so the
offset copy only shows near the borders and the two join along irregular,
organic lines instead of a straight cross-fade (no ghosting bands).

Sources:
- asset/Originals/grounds/generated/  Magnific takes (2048px), graded here
- asset/Originals/grounds/legacy-sheets/  snapshot of the original four sheets

Requires Pillow and numpy.

Usage: python scripts/grounds/pack-ground-sheets.py [--only <sheet name>...]
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance

ROOT = Path(__file__).resolve().parents[2]
ORIGINALS = ROOT / "asset" / "Originals" / "grounds"
PROMOTED = ROOT / "godot" / "asset" / "MAPS" / "grounds"

TILE = 64
GRID = 19
SIZE = TILE * GRID  # 1216

# output name -> source path under asset/Originals/grounds/
SHEETS: dict[str, str] = {
    "HighlandGreen": "generated/highland-green-plain-a.png",
    "amberleaf": "legacy-sheets/amberleaf.png",
    "frozen": "legacy-sheets/frozen.png",
    "sanddessert": "legacy-sheets/sanddessert.png",
    "forest-floor": "generated/forest-floor-plain-a.png",
    "forest-moss": "generated/forest-moss-plain-a.png",
    "cavern-floor": "generated/cavern-floor-a.png",
    "crystal-floor": "generated/crystal-floor-a.png",
    "water": "generated/water-a.png",
    "deep-water": "generated/deep-water-a.png",
    "town-cobble": "generated/town-cobble-a.png",
    # the West village's garden grounds (2026-11-01)
    "garden-soil": "generated/garden-soil-a.png",
    "gravel-path": "generated/gravel-path-a.png",
}

# Sheets also written at 128 px per tile (128x128-tile_19x19_<name>.webp, the sharp sheet
# game/world/ground_surface.gd draws): the wrap is made at that size from the 2048 px source and the
# 64 px sheet is its downscale, so the two line up texel for texel. (The older grounds' 128 px sheets
# are Magnific upscales of their 64 px sheets: build-terrain-edge-tiles.py --grounds-2x.)
SHARP: set[str] = {"garden-soil", "gravel-path"}

# (brightness, saturation) grade per ground. Neighbouring materials that meet on
# the same map (cavern/crystal floor) are pulled closer in value so patches read
# as texture, not as a checkerboard; water is calmed from pool-cyan toward the
# world palette. Grounds are generated mostly plain on purpose: leaves, twigs,
# flowers and rocks are placed on top as decoration objects, and walls are
# placed objects, never ground sheets.
GRADES: dict[str, tuple[float, float]] = {
    "cavern-floor": (1.15, 1.0),
    "crystal-floor": (0.82, 0.9),
    "water": (0.8, 0.85),
    "town-cobble": (0.94, 0.95),
}

# Sheets whose source is repeated NxN (after being made seamless) to shrink its
# features, e.g. cobblestones that would otherwise dwarf the props.
REPEATS: dict[str, int] = {
    "town-cobble": 2,
    "gravel-path": 3,
}

WRAP_BAND = 0.34  # fraction of the half-size over which the offset copy fades out
WRAP_NOISE = 0.45  # how far the noisy mask pushes the join line in or out
WRAP_SHARPNESS = 7.0  # higher = crisper join between original and offset copy


def smoothstep(edge0: float, edge1: float, value: np.ndarray) -> np.ndarray:
    t = np.clip((value - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def low_frequency_noise(size: int, cells: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    coarse = Image.fromarray((rng.random((cells, cells)) * 255).astype(np.uint8))
    return np.asarray(coarse.resize((size, size), Image.BICUBIC), dtype=np.float32) / 255.0 * 2.0 - 1.0


def make_wrap_seamless(image: Image.Image, seed: int) -> Image.Image:
    pixels = np.asarray(image, dtype=np.float32)
    height, width = pixels.shape[:2]
    offset = np.roll(pixels, (height // 2, width // 2), axis=(0, 1))
    # Normalised distance to the nearest border: 0 on the edge, 1 at the centre.
    distance_x = np.minimum(np.arange(width), np.arange(width)[::-1]) / (width / 2)
    distance_y = np.minimum(np.arange(height), np.arange(height)[::-1]) / (height / 2)
    distance = np.minimum.outer(distance_y, distance_x)
    base = smoothstep(0.0, WRAP_BAND, distance)
    noise = low_frequency_noise(width, 9, seed) * 0.6 + low_frequency_noise(width, 23, seed + 1) * 0.4
    weight = np.clip((base - 0.5 + noise * WRAP_NOISE * (1.0 - base) * base * 4.0) * WRAP_SHARPNESS + 0.5, 0.0, 1.0)
    # Pin the outermost pixels to the offset copy so the wrap stays exact.
    weight *= smoothstep(0.0, 0.03, distance)
    blended = pixels * weight[..., None] + offset * (1.0 - weight[..., None])
    return Image.fromarray(np.clip(blended, 0, 255).astype(np.uint8), image.mode)


def main() -> None:
    PROMOTED.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[sys.argv.index("--only") + 1:]) if "--only" in sys.argv else None
    packed = 0
    for index, (name, source) in enumerate(SHEETS.items()):
        if only is not None and name not in only:
            continue
        packed += 1
        # opaque: a generator's "transparent" full-frame texture comes slightly see-through
        image = Image.open(ORIGINALS / source).convert("RGB").convert("RGBA")
        size = SIZE * 2 if name in SHARP else SIZE
        if image.size != (size, size):
            image = image.resize((size, size), Image.LANCZOS)
        brightness, saturation = GRADES.get(name, (1.0, 1.0))
        image = ImageEnhance.Color(ImageEnhance.Brightness(image).enhance(brightness)).enhance(saturation)
        image = make_wrap_seamless(image, seed=1000 + index)
        repeat = REPEATS.get(name, 1)
        if repeat > 1:
            tiled = Image.new(image.mode, (size * repeat, size * repeat))
            for row in range(repeat):
                for column in range(repeat):
                    tiled.paste(image, (column * size, row * size))
            image = tiled.resize((size, size), Image.LANCZOS)
        if name in SHARP:
            image.save(PROMOTED / f"{TILE * 2}x{TILE * 2}-tile_{GRID}x{GRID}_{name}.webp", format="WEBP", quality=90, method=6)
            image = image.resize((SIZE, SIZE), Image.LANCZOS)
        # Lossless WebP: the same pixels as a PNG at a little over half the download (roadmap 10.1).
        image.save(PROMOTED / f"{TILE}x{TILE}-tile_{GRID}x{GRID}_{name}.webp", format="WEBP", lossless=True, quality=100, method=6)
    print(f"packed {packed} wrap-seamless ground sheets into {PROMOTED.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
