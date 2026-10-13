#!/usr/bin/env python3
"""Packs the big trees of every region set into atlases (docs/godot/FORESTS.md).

Sources: asset/Originals/trees/<set>/generated/<kind>-<variant>.png, Magnific GPT 2.5 renders on a
transparent background, each holding two trees of one kind: a medium one on the left and a tall one
on the right. Each tree is cut out, optionally colour-graded (GRADE: the forest renders came out
yellow-olive), sized to its width in world units at 2 px per unit, padded so the canopy sway
(game/world/forest/tree_sway.gdshader) never reaches the edge of its rectangle, and packed into its
set's atlas.

Outputs:
  godot/asset/MAPS/trees/sets/<set>.webp   one atlas per set
  godot/asset/MAPS/trees/sets/trees.json   per tree (<kind>-<variant>-<size>): its atlas, its
      rectangle there, its foot (the trunk's base, where it stands) inside the rectangle, and
      whether it sways (cacti, crystals, mushrooms and bare trees stand still)

Usage: python scripts/art/build-tree-sets.py [set ...]   (numpy, Pillow; no set = all)
Then run scripts/art/build-forest-paint-tiles.py.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

SOURCES = ROOT / "asset/Originals/trees"
OUT_DIR = ROOT / "godot/asset/MAPS/trees/sets"
TABLE = OUT_DIR / "trees.json"
RES_DIR = "res://asset/MAPS/trees/sets/"
VARIANTS = ["a", "b"]
SIZES = ["medium", "tall"]
## Art pixels per world unit (docs: 128 px per 64-unit cell).
DENSITY = 2


def kind(width_medium: int, width_tall: int, sway: bool = True, grade: tuple | None = None) -> dict:
    """A kind of tree: its medium and tall width in world units (a cell is 64), whether it sways,
    and its leaf grade (hue shift in degrees, saturation and value scale) if any."""
    return {"widths": (width_medium, width_tall), "sway": sway, "grade": grade}


## set -> kind -> its measures. Kinds are unique across sets (tree names are <kind>-<v>-<size>).
SETS = {
    "forest": {
        "oak": kind(150, 200, grade=(30, 0.72, 0.95)),
        "beech": kind(155, 205, grade=(42, 0.70, 0.78)),
        "birch": kind(125, 150, grade=(20, 0.80, 1.04)),
        "pine": kind(115, 145, grade=(22, 0.95, 0.92)),
    },
    "autumn": {
        "maple": kind(150, 200),
        "ginkgo": kind(130, 165),
    },
    "frost": {
        "fir": kind(120, 150),
        "frost": kind(140, 185),
    },
    "desert": {
        "saguaro": kind(90, 120, sway=False),
        "pear": kind(110, 140, sway=False),
        "organ": kind(100, 125, sway=False),
    },
    "volcano": {
        "ember": kind(145, 190),
        "ash": kind(130, 170, sway=False),
    },
    "swamp": {
        "cypress": kind(160, 210),
        "mangrove": kind(150, 195),
    },
    "crystal": {
        "crystal": kind(130, 170, sway=False),
        "mushroom": kind(120, 160, sway=False),
    },
    "ruins": {
        "gnarled": kind(140, 185, sway=False),
        "ivy": kind(160, 210),
    },
    "village": {
        "apple": kind(140, 180),
        "cherry": kind(150, 200),
    },
}
## Transparent margin around each tree (atlas px): room for the sway and for filtering.
PAD = 14
ATLAS_WIDTH = 2048
## The foot stands this far (fraction of the tree's height) above the lowest root pixel.
FOOT_LIFT = 0.035


def split(image: np.ndarray) -> list[np.ndarray]:
    """The two trees of a render, left then right, each cropped to its pixels: split at the widest
    empty gap in the middle half, else at the emptiest column there."""
    alpha = image[..., 3]
    cols = (alpha > 24).sum(axis=0)
    width = alpha.shape[1]
    lo, hi = width // 4, 3 * width // 4
    best = (0, 0)
    x = lo
    while x < hi:
        if cols[x] == 0:
            start = x
            while x < width and cols[x] == 0:
                x += 1
            if x - start > best[1] - best[0]:
                best = (start, x)
        x += 1
    middle = (best[0] + best[1]) // 2 if best != (0, 0) else lo + int(np.argmin(cols[lo:hi]))
    trees = []
    for part in (image[:, :middle], image[:, middle:]):
        mask = part[..., 3] > 24
        # Drop specks (stray leaves, petals) far from the tree: keep rows/columns with real mass.
        ys, xs = np.nonzero(mask)
        trees.append(part[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
    return trees


def grade(rgba: np.ndarray, measures: tuple) -> np.ndarray:
    dh, ks, kv = measures
    hsv = np.array(Image.fromarray(rgba[..., :3]).convert("HSV")).astype(np.float64)
    h = hsv[..., 0] * 360 / 255
    s = hsv[..., 1]
    v = hsv[..., 2]
    weight = np.clip((s - 60) / 60, 0, 1) * np.clip(1 - np.maximum(0, np.maximum(36 - h, h - 160)) / 12, 0, 1)
    weight *= np.clip((v - 25) / 40, 0, 1)
    shift = dh * (1 - 0.35 * (v / 255) ** 2)  # bright highlights stay a touch warmer
    out = np.stack([
        ((h + weight * shift) % 360) * 255 / 360,
        np.clip(s * (1 + weight * (ks - 1)), 0, 255),
        np.clip(v * (1 + weight * (kv - 1)), 0, 255),
    ], -1).astype(np.uint8)
    rgb = np.array(Image.fromarray(out, "HSV").convert("RGB"))
    return np.concatenate([rgb, rgba[..., 3:4]], -1)


def resize(rgba: np.ndarray, width: int) -> np.ndarray:
    image = Image.fromarray(rgba, "RGBA").convert("RGBa")
    height = round(rgba.shape[0] * width / rgba.shape[1])
    out = np.array(image.resize((width, height), Image.LANCZOS).convert("RGBA"))
    out[out[..., 3] == 0, :3] = 0
    return out


def foot(rgba: np.ndarray) -> tuple[int, int]:
    """The trunk's base: the middle of the lowest pixels, lifted a little above the root tips."""
    alpha = rgba[..., 3] > 127
    ys, xs = np.nonzero(alpha)
    bottom = ys.max()
    low = ys >= bottom - max(4, rgba.shape[0] // 14)
    return int(round(xs[low].mean())), int(round(bottom - FOOT_LIFT * rgba.shape[0]))


def pack(trees: list[tuple[str, np.ndarray]]) -> tuple[np.ndarray, dict[str, tuple[int, int]]]:
    """Shelf packing, tallest first."""
    placed: dict[str, tuple[int, int]] = {}
    x = y = shelf = 0
    for name, tree in sorted(trees, key=lambda t: -t[1].shape[0]):
        h, w = tree.shape[:2]
        if x + w > ATLAS_WIDTH:
            x, y, shelf = 0, y + shelf, 0
        placed[name] = (x, y)
        x += w
        shelf = max(shelf, h)
    atlas = np.zeros((y + shelf, ATLAS_WIDTH, 4), np.uint8)
    for name, tree in trees:
        px, py = placed[name]
        atlas[py:py + tree.shape[0], px:px + tree.shape[1]] = tree
    return atlas, placed


def main() -> None:
    wanted = sys.argv[1:] or list(SETS)
    table = json.loads(TABLE.read_text(encoding="utf-8")) if TABLE.exists() else {"scale": 1.0 / DENSITY, "trees": {}}
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for set_name in wanted:
        trees: list[tuple[str, np.ndarray]] = []
        sways: dict[str, bool] = {}
        for kind_name, measures in SETS[set_name].items():
            for variant in VARIANTS:
                source = SOURCES / set_name / "generated" / f"{kind_name}-{variant}.png"
                image = np.array(Image.open(source).convert("RGBA"))
                for size, width, tree in zip(SIZES, measures["widths"], split(image)):
                    if measures["grade"]:
                        tree = grade(tree, measures["grade"])
                    tree = resize(tree, width * DENSITY)
                    name = f"{kind_name}-{variant}-{size}"
                    trees.append((name, np.pad(tree, ((PAD, PAD), (PAD, PAD), (0, 0)))))
                    sways[name] = measures["sway"]
        atlas, placed = pack(trees)
        texture = RES_DIR + f"{set_name}.webp"
        save_game_webp(Image.fromarray(atlas, "RGBA"), OUT_DIR / f"{set_name}.webp")
        table["trees"] = {k: v for k, v in table["trees"].items() if v.get("texture") != texture}
        for name, tree in trees:
            px, py = placed[name]
            fx, fy = foot(tree)
            table["trees"][name] = {
                "set": set_name, "texture": texture, "rect": [px, py, tree.shape[1], tree.shape[0]],
                "foot": [fx, fy], "sway": sways[name],
            }
        print(f"{set_name}.webp: {len(trees)} trees, {atlas.shape[1]}x{atlas.shape[0]}")
    order = {name: i for i, name in enumerate(SETS)}
    table["trees"] = dict(sorted(table["trees"].items(), key=lambda kv: (order[kv[1]["set"]], kv[0])))
    TABLE.write_text(json.dumps(table, indent="\t") + "\n", encoding="utf-8")
    print(f"{TABLE.name}: {len(table['trees'])} trees")


if __name__ == "__main__":
    main()
