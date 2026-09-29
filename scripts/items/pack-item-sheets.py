"""Pack the generated item icon sheets into clean 64x64 frame atlases.

The Magnific sources in asset/Originals/items/ hold 10 items in a loose 5x2
layout: items drift across cell lines and carry detached sparkles/droplets.
This tool finds every item as a connected alpha component, attaches small
islands (sparkles, drips) to the nearest item, orders items in reading order
(row, then column) and fits each one, centred, inside its own frame with a
transparent safety margin so no pixel reaches a neighbouring frame.

Writes asset/MAPS/items/<sheet>-5x2.png and asset/Originals/items/atlas-index.json
(frame -> item name, so unused frames can be wired up later). Requires Pillow
and numpy.

Usage: python scripts/items/pack-item-sheets.py
"""

from __future__ import annotations

import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ORIGINALS = ROOT / "asset" / "Originals" / "items"
PROMOTED = ROOT / "asset" / "MAPS" / "items"

FRAME = 64
COLUMNS, ROWS = 5, 2
PADDING = 4  # transparent margin kept inside every frame
ALPHA_THRESHOLD = 32  # opaque enough to belong to an item silhouette
HALO_CUTOFF = 16  # fainter glow pixels are cleared so frames stay clean
MIN_ISLAND_AREA = 20  # smaller islands are generation specks
ATTACH_DISTANCE = 80  # source px; farther islands are dropped instead of attached

# Source picked per sheet and the item in each frame, reading order.
SHEETS: dict[str, tuple[str, list[str]]] = {
    "gems": ("gems-a.png", [
        "crystal-shard", "emerald-shard", "ruby-shard", "sapphire-shard", "amber-shard",
        "gold-coin", "silver-coin", "copper-coin", "gold-coin-stack", "diamond",
    ]),
    "materials": ("materials-b.png", [
        "silk-clump", "spider-fang", "slime-gel", "feather", "bone",
        "beetle-carapace", "hide-scrap", "fur-tuft", "honeycomb", "monster-eye",
    ]),
    "forage": ("forage-a.png", [
        "purple-berry", "red-berry", "blueberry", "red-mushroom", "brown-mushroom",
        "apple", "carrot", "wheat-bundle", "healing-herb", "acorn",
    ]),
}


def components(mask: np.ndarray) -> list[np.ndarray]:
    """4-connected components of `mask` as arrays of (y, x) pixels."""
    seen = np.zeros(mask.shape, dtype=bool)
    height, width = mask.shape
    output: list[np.ndarray] = []
    for start_y, start_x in zip(*np.nonzero(mask)):
        if seen[start_y, start_x]:
            continue
        seen[start_y, start_x] = True
        queue = deque([(start_y, start_x)])
        pixels = []
        while queue:
            y, x = queue.popleft()
            pixels.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        output.append(np.array(pixels))
    return output


def bbox(pixels: np.ndarray) -> tuple[int, int, int, int]:
    return int(pixels[:, 1].min()), int(pixels[:, 0].min()), int(pixels[:, 1].max()) + 1, int(pixels[:, 0].max()) + 1


def box_distance(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> float:
    dx = max(a[0] - b[2], b[0] - a[2], 0)
    dy = max(a[1] - b[3], b[1] - a[3], 0)
    return float(np.hypot(dx, dy))


def items_in(source: Image.Image, expected: int) -> list[tuple[int, int, int, int]]:
    alpha = np.array(source)[:, :, 3]
    islands = [pixels for pixels in components(alpha > ALPHA_THRESHOLD) if len(pixels) >= MIN_ISLAND_AREA]
    islands.sort(key=len, reverse=True)
    if len(islands) < expected:
        raise SystemExit(f"found {len(islands)} islands, expected at least {expected}")
    boxes = [list(bbox(pixels)) for pixels in islands[:expected]]
    for pixels in islands[expected:]:
        island = bbox(pixels)
        distances = [box_distance(island, tuple(box)) for box in boxes]
        nearest = int(np.argmin(distances))
        if distances[nearest] > ATTACH_DISTANCE:
            continue
        box = boxes[nearest]
        boxes[nearest] = [min(box[0], island[0]), min(box[1], island[1]), max(box[2], island[2]), max(box[3], island[3])]
    # Reading order: split rows at the middle of the vertical centres, then left to right.
    centres = [(box[1] + box[3]) / 2 for box in boxes]
    split = (min(centres) + max(centres)) / 2
    boxes.sort(key=lambda box: ((box[1] + box[3]) / 2 > split, box[0]))
    return [tuple(box) for box in boxes]


def pack(name: str, source_name: str, labels: list[str]) -> dict[str, int]:
    source = Image.open(ORIGINALS / source_name).convert("RGBA")
    pixels = np.array(source)
    pixels[pixels[:, :, 3] < HALO_CUTOFF] = 0
    source = Image.fromarray(pixels)
    boxes = items_in(source, len(labels))
    atlas = Image.new("RGBA", (FRAME * COLUMNS, FRAME * ROWS), (0, 0, 0, 0))
    inner = FRAME - 2 * PADDING
    for index, box in enumerate(boxes):
        item = source.crop(box)
        scale = inner / max(item.width, item.height)
        item = item.resize((max(1, round(item.width * scale)), max(1, round(item.height * scale))), Image.LANCZOS)
        column, row = index % COLUMNS, index // COLUMNS
        atlas.alpha_composite(item, (column * FRAME + (FRAME - item.width) // 2, row * FRAME + (FRAME - item.height) // 2))
    PROMOTED.mkdir(parents=True, exist_ok=True)
    atlas.save(PROMOTED / f"{name}-{COLUMNS}x{ROWS}.png", optimize=True)
    return {label: frame for frame, label in enumerate(labels)}


def main() -> None:
    index = {name: {"source": source, "frames": pack(name, source, labels)} for name, (source, labels) in SHEETS.items()}
    (ORIGINALS / "atlas-index.json").write_text(json.dumps(index, indent=2) + "\n", encoding="utf8")
    print(f"packed {len(index)} item sheets into {PROMOTED.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
