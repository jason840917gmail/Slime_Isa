"""Pack the Gulp's object art into runtime sheets: the liftables (things the slime sucks in and
throws) and the essences.

Sources live in asset/Originals/gulp/generated/ (Magnific GPT 2.5, transparent generations; the
prompts are in asset/Originals/gulp/README.md).

Liftables (owner, 2026-10-09: "at least 8 by 8 ... stuff for dungeons, different terrains,
interiors like pots"): `grid-1.png` .. `grid-4.png` each hold 16 objects in a 4 x 4 grid of 256 px
cells, and the first liftables are single pictures (rock, puffball, pinecone, two takes each). Each
object is cut out of its grid cell (grid-4 came with a see-through haze over its background, which
is keyed out), cleared of specks, trimmed to its opaque pixels, scaled to fit a 192 px cell (never
upscaled) and stood on the cell's bottom centre with a small margin (the render origin the object
scenes use). The sheet, godot/asset/MAPS/props/192x192-tile_8x9-gulp-liftables.webp, has 8 columns
and 9 rows: rows 0-7 are the grids in reading order (two grid rows per sheet row), row 8 the first
liftables (frames 64-69).

It also writes the catalog godot/game/data/liftables.json that game/scripts/liftable.gd reads: per
kind its name, material (how it breaks and sounds, game/player/gulp/thrown_object.gd), its frames
(two for the first three kinds: a placed one picks by position) and its art size in sheet px (the
liftable's body follows it). Kinds, names and materials are authored in GRIDS and FIRST below.

Essences (godot/asset/MAPS/items/128x128-tile_3x1-gulp-essences.webp): the essence on the ground,
in the mouth and the bag's icon; frame 0 stone, 1 silk, 2 swim (gulp_forms.gd `badge_frame` order).

Usage: python scripts/props/pack-gulp-art.py
Needs Pillow and numpy.
"""
from __future__ import annotations

import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from game_webp import save_game_webp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "asset" / "Originals" / "gulp" / "generated"
LIFTABLES_OUTPUT = ROOT / "godot" / "asset" / "MAPS" / "props" / "192x192-tile_8x9-gulp-liftables.webp"
OLD_LIFTABLES = ROOT / "godot" / "asset" / "MAPS" / "props" / "192x192-tile_6x1-gulp-liftables.webp"
CATALOG_OUTPUT = ROOT / "godot" / "game" / "data" / "liftables.json"
ESSENCES_OUTPUT = ROOT / "godot" / "asset" / "MAPS" / "items" / "128x128-tile_3x1-gulp-essences.webp"

CELL = 192
COLUMNS = 8
MARGIN = 6
GRID_CELL = 256
ALPHA_CUT = 24
SPECK_PX = 40

# The grids in reading order: (kind id, name, material). Materials: clay, glass, wood, metal, stone,
# soft, ice, snow, crystal.
GRIDS = {
    "grid-1": [
        ("clay-pot", "Clay pot", "clay"), ("honey-jar", "Honey jar", "glass"), ("bucket", "Bucket", "wood"),
        ("crate", "Crate", "wood"), ("wicker-basket", "Wicker basket", "wood"), ("flour-sack", "Flour sack", "soft"),
        ("kettle", "Kettle", "metal"), ("keg", "Keg", "wood"), ("rune-urn", "Rune urn", "stone"),
        ("candle-jar", "Candle jar", "glass"), ("lantern", "Lantern", "metal"), ("amphora", "Cracked amphora", "clay"),
        ("mossy-brick", "Mossy brick", "stone"), ("iron-ball", "Iron ball", "metal"),
        ("gargoyle-head", "Gargoyle head", "stone"), ("fancy-pot", "Fancy pot", "clay"),
    ],
    "grid-2": [
        ("log", "Log", "wood"), ("acorn", "Giant acorn", "wood"), ("toadstool", "Toadstool", "soft"),
        ("bird-nest", "Bird nest", "wood"), ("crystal-cluster", "Crystal cluster", "crystal"), ("geode", "Geode", "crystal"),
        ("stalagmite", "Stalagmite", "stone"), ("ore-rock", "Ore rock", "stone"), ("glow-mushrooms", "Glow mushrooms", "soft"),
        ("glowworm-pot", "Glowworm pot", "clay"), ("amethyst", "Amethyst", "crystal"), ("coal", "Coal lump", "stone"),
        ("snowball", "Snowball", "snow"), ("ice-block", "Ice block", "ice"), ("frosted-jar", "Frosted jar", "ice"),
        ("snowy-log", "Snowy log", "wood"),
    ],
    "grid-3": [
        ("icicle", "Icicle", "ice"), ("snowy-rock", "Snowy rock", "stone"), ("frost-crystal", "Frost crystal", "ice"),
        ("snow-brick", "Snow brick", "snow"), ("sandstone", "Sandstone block", "stone"), ("water-jug", "Water jug", "clay"),
        ("dry-gourd", "Dry gourd", "soft"), ("tumbleweed", "Tumbleweed", "soft"), ("potted-cactus", "Potted cactus", "clay"),
        ("desert-urn", "Desert urn", "clay"), ("sandbag", "Sandbag", "soft"), ("fossil-stone", "Fossil stone", "stone"),
        ("coconut", "Coconut", "wood"), ("seashell", "Seashell", "clay"), ("driftwood", "Driftwood", "wood"),
        ("coral", "Coral", "stone"),
    ],
    "grid-4": [
        ("mud-ball", "Mud ball", "soft"), ("swamp-gourd", "Swamp gourd", "soft"), ("glass-float", "Glass float", "glass"),
        ("message-bottle", "Bottle", "glass"), ("pumpkin", "Pumpkin", "soft"), ("cabbage", "Cabbage", "soft"),
        ("watermelon", "Watermelon", "soft"), ("hay-bundle", "Hay bundle", "soft"), ("turnip", "Turnip", "soft"),
        ("flower-pot", "Flower pot", "clay"), ("obsidian", "Obsidian", "crystal"), ("lava-rock", "Lava rock", "stone"),
        ("grain-basket", "Grain basket", "wood"), ("teapot", "Teapot", "clay"), ("stone-lantern", "Stone lantern", "stone"),
        ("piggy-bank", "Piggy bank", "clay"),
    ],
}
# The first liftables (single pictures), row 8: (kind id, name, material, [sources]).
FIRST = [
    ("rock", "Mossy rock", "stone", ["rock-a", "rock-b"]),
    ("puffball", "Puffball", "soft", ["puffball-a", "puffball-b"]),
    ("pinecone", "Pinecone", "wood", ["pinecone-a", "pinecone-b"]),
]
ESSENCES = ["essence-stone-a", "essence-silk-b", "essence-swim-b"]


def drop_specks(alpha: np.ndarray) -> np.ndarray:
    """`alpha` with every opaque island smaller than SPECK_PX cleared (4-connected flood fill)."""
    solid = alpha > ALPHA_CUT
    seen = np.zeros_like(solid)
    out = alpha.copy()
    height, width = solid.shape
    for y0, x0 in zip(*np.nonzero(solid)):
        if seen[y0, x0]:
            continue
        island = []
        queue = deque([(y0, x0)])
        seen[y0, x0] = True
        while queue:
            y, x = queue.popleft()
            island.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < height and 0 <= nx < width and solid[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        if len(island) < SPECK_PX:
            for y, x in island:
                out[y, x] = 0
    out[~solid] = 0
    return out


def grid_cell(grid: Image.Image, index: int) -> Image.Image:
    """The object in cell `index` of a 4 x 4 grid, its background keyed out."""
    row, column = divmod(index, 4)
    cell = np.asarray(grid.crop((column * GRID_CELL, row * GRID_CELL, (column + 1) * GRID_CELL, (row + 1) * GRID_CELL))).copy()
    alpha = cell[..., 3].astype(np.float32)
    ring = np.concatenate([alpha[:6].ravel(), alpha[-6:].ravel(), alpha[:, :6].ravel(), alpha[:, -6:].ravel()])
    haze = float(np.median(ring))
    if haze > 8.0:
        # A see-through background: the object is what stands well above it; its edge is softened
        # by a slight blur of the cut.
        mask = Image.fromarray(np.where(alpha > (haze + 255.0) / 2.0, 255, 0).astype(np.uint8), "L")
        mask = mask.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
        alpha = np.asarray(mask, dtype=np.float32)
    cell[..., 3] = drop_specks(alpha.astype(np.uint8))
    image = Image.fromarray(cell, "RGBA")
    return image.crop(image.getchannel("A").getbbox())


def trimmed(name: str) -> Image.Image:
    image = Image.open(SOURCES / f"{name}.png").convert("RGBA")
    box = image.getchannel("A").point(lambda a: 255 if a > ALPHA_CUT else 0).getbbox()
    return image.crop(box)


def fit_into(sheet: Image.Image, art: Image.Image, frame: int, cell: int) -> tuple[int, int]:
    """Draws `art` into `frame`'s cell (fitted, never upscaled, bottom-centred); its drawn size."""
    fit = min(1.0, (cell - 2 * MARGIN) / art.width, (cell - 2 * MARGIN) / art.height)
    art = art.resize((max(1, round(art.width * fit)), max(1, round(art.height * fit))), Image.LANCZOS)
    columns = sheet.width // cell
    x0, y0 = (frame % columns) * cell, (frame // columns) * cell
    sheet.alpha_composite(art, (x0 + (cell - art.width) // 2, y0 + cell - MARGIN - art.height))
    return art.width, art.height


def pack_liftables() -> None:
    rows = 9
    sheet = Image.new("RGBA", (CELL * COLUMNS, CELL * rows), (0, 0, 0, 0))
    kinds: dict[str, dict] = {}
    frame = 0
    for grid_name, entries in GRIDS.items():
        grid = Image.open(SOURCES / f"{grid_name}.png").convert("RGBA")
        for index, (kind, name, material) in enumerate(entries):
            size = fit_into(sheet, grid_cell(grid, index), frame, CELL)
            kinds[kind] = {"name": name, "material": material, "frames": [frame], "art": list(size)}
            frame += 1
    frame = 8 * COLUMNS
    for kind, name, material, sources in FIRST:
        frames, sizes = [], []
        for source in sources:
            sizes.append(fit_into(sheet, trimmed(source), frame, CELL))
            frames.append(frame)
            frame += 1
        kinds[kind] = {"name": name, "material": material, "frames": frames,
                       "art": [max(s[0] for s in sizes), max(s[1] for s in sizes)]}
    LIFTABLES_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    save_game_webp(sheet, LIFTABLES_OUTPUT)
    catalog = {
        "_comment": "Written by scripts/props/pack-gulp-art.py; edit GRIDS and FIRST there, not here.",
        "sheet": "res://asset/MAPS/props/" + LIFTABLES_OUTPUT.name,
        "cell": CELL, "columns": COLUMNS, "rows": rows,
        "kinds": kinds,
    }
    CATALOG_OUTPUT.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    for old in (OLD_LIFTABLES, OLD_LIFTABLES.with_name(OLD_LIFTABLES.name + ".import")):
        if old.exists():
            old.unlink()
    print(f"wrote {LIFTABLES_OUTPUT.relative_to(ROOT)} ({len(kinds)} kinds) and {CATALOG_OUTPUT.relative_to(ROOT)}")


def pack_essences() -> None:
    sheet = Image.new("RGBA", (128 * len(ESSENCES), 128), (0, 0, 0, 0))
    for index, name in enumerate(ESSENCES):
        fit_into(sheet, trimmed(name), index, 128)
    save_game_webp(sheet, ESSENCES_OUTPUT)
    print(f"wrote {ESSENCES_OUTPUT.relative_to(ROOT)} ({len(ESSENCES)} frames of 128 px)")


def main() -> None:
    pack_liftables()
    pack_essences()


if __name__ == "__main__":
    main()
