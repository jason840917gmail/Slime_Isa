"""Packs the Crystal Mine's art (Chapter 3's dungeon; docs/godot/DUNGEONS.md "The Crystal Mine") from
its Magnific sheets.

Sources (asset/Originals/mine/, GPT 2.5 with a transparent background, Lili's sheet as the style
reference, one 1024 px sheet with four pictures in a 2 x 2 grid each; prompts in the README there):
- `colossus-sheet-a.png`: the Crystal Colossus standing, a foot raised (the stomp's tell), the stomp
  landed, his chest armour cracked open (the weak spot);
- `colossus-sheet-b.png`: climbing a wall (from behind), throwing a Crystal Mite down from it, landed
  from a jump, defeated (the heap and the Pearl rising);
- `colossus-sheet-c.png` (2026-10-17, the Pearl mid-dungeon rework): sprawled face down after his claws
  lost their grip on the wall, his back cracked open and glowing (the stun), and the small calm crystal
  golem he shrinks back into once beaten, from the front, walking left and from behind;
- `mine-props-a.png`: the mine cart, the ore lift, the iron-banded ore crate, the rotten timbers (also
  packed with a smashed frame drawn from it: `256x256-tile_2x1-rotten-timbers.webp`);
- `mine-props-b.png`: the crystal lens on its post (plain, struck), the crystal veil (grown,
  shrunk back);
- `mine-props-c.png`: the root wall (the Feral skin's climb), a miner's lantern on a bracket, the
  rails' buffer stop, Pearl 3;
- `mine-props-d.png`: the mine gate (shut, its lamp cups cold; open, the cups burning), a rock stump
  (cover), a heap of ore with a pickaxe;
- `smith-sheet.png`: the smith, Pip's dad (the mine camp, roadmap 12.3): standing with his hammer,
  the hammer raised to strike, holding out the Lantern, pointing.

Each sheet is cut along its emptiest middle row and columns into its four pictures (reading order),
each trimmed to its opaque pixels. The Colossus's first eight poses are drawn at ONE scale (the largest
that fits every pose in FIT_BOSS), centred at x BOSS_CELL / 2 and standing on y BOSS_BOTTOM; his
ninth (the stun, sheet C) at the same scale unless it is wider than FIT_BOSS, then narrowed to fit;
the small golem's three at one scale of their own in SMALL_CELL cells; a
pair (the lens, the veil) shares one scale too; every other prop is fitted alone in its cell, centred
and standing on its bottom.

The smith's four poses share one scale too, each standing on y SMITH_BOTTOM of a SMITH_CELL cell
with its feet centred at x SMITH_CELL.x / 2 (game/crystal_mine/smith_actor.gd's frames).

Writes godot/asset/MAPS/enemies/384x384-tile_9x1-crystal-colossus.webp,
godot/asset/MAPS/enemies/192x192-tile_3x1-small-crystal-golem.webp,
godot/asset/MAPS/props/mine/*.webp and godot/asset/characters/authored/npcs/smith.webp.

usage: python scripts/art/pack-mine-art.py [--only=colossus]
(`--only=colossus` packs the Colossus's strip and the small golem alone.)
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

SOURCES = REPO / "asset" / "Originals" / "mine"
ENEMIES = REPO / "godot" / "asset" / "MAPS" / "enemies"
PROPS = REPO / "godot" / "asset" / "MAPS" / "props" / "mine"
NPCS = REPO / "godot" / "asset" / "characters" / "authored" / "npcs"
ALPHA_CUT = 24
GAP_FROM = 360
GAP_TO = 664

BOSS_CELL = 384
BOSS_BOTTOM = 376
FIT_BOSS = 368

SMALL_CELL = 192
SMALL_BOTTOM = 186
SMALL_FIT = 176

SMITH_CELL = (260, 280)
SMITH_BOTTOM = 276
SMITH_FIT_H = 268

# sheet -> its four pictures' output names (reading order); a name shared by two pictures packs
# them side by side into one 2 x 1 strip at one scale.
PROP_SHEETS = {
    "mine-props-a.png": ["256x256-mine-cart", "256x256-ore-lift", "256x256-ore-crate", "256x256-rotten-timbers"],
    "mine-props-b.png": ["256x256-tile_2x1-crystal-lens", "256x256-tile_2x1-crystal-lens",
        "256x256-tile_2x1-crystal-veil", "256x256-tile_2x1-crystal-veil"],
    "mine-props-c.png": ["256x256-root-wall", "128x128-mine-lantern", "256x256-buffer-stop", "256x256-pearl"],
    "mine-props-d.png": ["256x256-tile_2x1-mine-gate", "256x256-tile_2x1-mine-gate", "256x256-rock-stump",
        "256x256-ore-heap"],
}


def gap(mask: np.ndarray, axis: int) -> int:
    counts = mask.sum(axis=axis)
    return GAP_FROM + int(np.argmin(counts[GAP_FROM:GAP_TO]))


def trimmed(image: Image.Image) -> Image.Image:
    alpha = np.asarray(image)[..., 3]
    ys, xs = np.nonzero(alpha > ALPHA_CUT)
    if xs.size == 0:
        raise SystemExit("an empty picture")
    return image.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def cut(path: Path) -> list[Image.Image]:
    sheet = Image.open(path).convert("RGBA")
    mask = np.asarray(sheet)[..., 3] > ALPHA_CUT
    split_y = gap(mask, 1)
    boxes = []
    for top, bottom in ((0, split_y), (split_y, sheet.height)):
        split_x = gap(mask[top:bottom], 0)
        boxes += [(0, top, split_x, bottom), (split_x, top, sheet.width, bottom)]
    return [trimmed(sheet.crop(box)) for box in boxes]


def cell_of(name: str) -> int:
    return int(name.split("x")[0])


def place(pictures: list[Image.Image], cell: int, fit: int, bottom: int) -> Image.Image:
    scale = min(fit / max(p.width for p in pictures), fit / max(p.height for p in pictures))
    strip = Image.new("RGBA", (cell * len(pictures), cell), (0, 0, 0, 0))
    for i, picture in enumerate(pictures):
        w, h = max(1, round(picture.width * scale)), max(1, round(picture.height * scale))
        sized = picture.resize((w, h), Image.LANCZOS)
        strip.alpha_composite(sized, (i * cell + (cell - w) // 2, bottom - h))
    return strip


def main() -> None:
    poses = cut(SOURCES / "colossus-sheet-a.png") + cut(SOURCES / "colossus-sheet-b.png")
    later = cut(SOURCES / "colossus-sheet-c.png")
    boss = colossus_strip(poses, later[0])
    out = ENEMIES / "384x384-tile_9x1-crystal-colossus.webp"
    print(out.name, save_game_webp(boss, out), boss.size)
    small = place(later[1:4], SMALL_CELL, SMALL_FIT, SMALL_BOTTOM)
    out = ENEMIES / "192x192-tile_3x1-small-crystal-golem.webp"
    print(out.name, save_game_webp(small, out), small.size)
    if "--only=colossus" in sys.argv[1:]:
        return
    for sheet, names in PROP_SHEETS.items():
        pictures = cut(SOURCES / sheet)
        groups: dict[str, list[Image.Image]] = {}
        for name, picture in zip(names, pictures):
            groups.setdefault(name, []).append(picture)
        for name, group in groups.items():
            cell = cell_of(name)
            image = place(group, cell, cell - 8, cell - 4)
            out = PROPS / (name + ".webp")
            print(out.name, save_game_webp(image, out), image.size)
            if name == "256x256-rotten-timbers":
                strip = smashed_strip(image)
                out = PROPS / "256x256-tile_2x1-rotten-timbers.webp"
                print(out.name, save_game_webp(strip, out), strip.size)
    smith = smith_strip()
    out = NPCS / "smith.webp"
    print(out.name, save_game_webp(smith, out), smith.size)


def colossus_strip(poses: list[Image.Image], stunned: Image.Image) -> Image.Image:
    """His eight poses at one scale (`place`), then the stun at the same scale, narrowed to FIT_BOSS
    when wider, centred and standing on BOSS_BOTTOM in a ninth cell."""
    scale = min(FIT_BOSS / max(p.width for p in poses), FIT_BOSS / max(p.height for p in poses))
    eight = place(poses, BOSS_CELL, FIT_BOSS, BOSS_BOTTOM)
    strip = Image.new("RGBA", (BOSS_CELL * (len(poses) + 1), BOSS_CELL), (0, 0, 0, 0))
    strip.alpha_composite(eight, (0, 0))
    own = min(scale, FIT_BOSS / stunned.width, FIT_BOSS / stunned.height)
    w, h = max(1, round(stunned.width * own)), max(1, round(stunned.height * own))
    sized = stunned.resize((w, h), Image.LANCZOS)
    strip.alpha_composite(sized, (len(poses) * BOSS_CELL + (BOSS_CELL - w) // 2, BOSS_BOTTOM - h))
    print("colossus scale %.3f, stun %.3f" % (scale, own))
    return strip


def smith_strip() -> Image.Image:
    """The smith's four poses at one scale, each with its feet (the bottom fifth of the picture)
    centred in its cell and standing on SMITH_BOTTOM."""
    poses = cut(SOURCES / "smith-sheet.png")
    feet_x = []
    for pose in poses:
        alpha = np.asarray(pose)[..., 3] > ALPHA_CUT
        rows = alpha[int(pose.height * 0.8):]
        xs = np.nonzero(rows.any(axis=0))[0]
        feet_x.append((xs.min() + xs.max() + 1) / 2.0)
    half = max(max(fx, pose.width - fx) for fx, pose in zip(feet_x, poses))
    scale = min(SMITH_FIT_H / max(p.height for p in poses), (SMITH_CELL[0] / 2 - 2) / half)
    strip = Image.new("RGBA", (SMITH_CELL[0] * len(poses), SMITH_CELL[1]), (0, 0, 0, 0))
    for i, (pose, fx) in enumerate(zip(poses, feet_x)):
        w, h = max(1, round(pose.width * scale)), max(1, round(pose.height * scale))
        sized = pose.resize((w, h), Image.LANCZOS)
        strip.alpha_composite(sized, (round(i * SMITH_CELL[0] + SMITH_CELL[0] / 2 - fx * scale), SMITH_BOTTOM - h))
    return strip


def smashed_strip(whole: Image.Image) -> Image.Image:
    """The rotten timbers whole (frame 0) and smashed (frame 1): the same planks knocked flat into a
    low, darker heap of splinters lying on the floor (plank_barricade.gd's two frames)."""
    cell = whole.width
    strip = Image.new("RGBA", (cell * 2, cell), (0, 0, 0, 0))
    strip.alpha_composite(whole, (0, 0))
    box = whole.getbbox()
    planks = whole.crop(box)
    flat = planks.resize((int(planks.width * 1.12), max(1, int(planks.height * 0.34))), Image.LANCZOS)
    pixels = np.asarray(flat).astype(np.float32)
    pixels[..., :3] *= 0.72
    flat = Image.fromarray(pixels.clip(0, 255).astype(np.uint8), "RGBA")
    heap = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    heap.alpha_composite(flat, ((cell - flat.width) // 2, cell - 6 - flat.height))
    strip.alpha_composite(heap, (cell, 0))
    return strip


if __name__ == "__main__":
    main()
