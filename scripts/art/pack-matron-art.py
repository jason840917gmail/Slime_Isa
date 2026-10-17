"""Packs the Orb-Weaver Matron's cocoon fight art (the Weaver Hollow's boss, docs/godot/specs/matron.md
"The cocoon") from its Magnific sheet.

Sources (asset/Originals/enemies/matron/, GPT 2.5 with a transparent background, Lili's sheet as the
style reference, 1024 px sheets with four pictures in a 2 x 2 grid; the prompts are in the README
there):
- `cocoon-sheet-a.png`: the cocoon hanging from its thread (her shape and six red eyes through the
  silk), the same cocoon torn open and empty, Pearl 2 in a cradle of silk, her thread's spool;
- `matron-sheet-a.png` (the cocoon sheet as a second reference, so she is the spider inside it): the
  Matron fallen out of her cocoon, dazed (two poses, legs twitching), recoiling from a hit, and
  climbing her thread seen from behind.

The sheet is cut along its emptiest middle row and columns into its four pictures (reading order),
each trimmed to its opaque pixels.
- The two cocoons share ONE scale (the largest that fits both in COCOON_FIT) and hang from the top
  middle of their cells: the thread's top is (cell / 2, 0) in each, so the game draws the rest of the
  thread up from there.
- The Pearl and the spool are fitted alone in their cells, centred and standing on the bottom; the
  spool is also the thread's bag icon (64 px).
- Her four poses share ONE scale (the largest that fits all in MATRON_FIT; the climbing pose's thread
  above and below her is trimmed first: rows narrower than THREAD_PX), centred and standing on
  MATRON_BOTTOM of their 384 px cells.

Writes godot/asset/MAPS/enemies/256x416-tile_2x1-matron-cocoon.webp,
godot/asset/MAPS/enemies/384x384-tile_4x1-matron.webp,
godot/asset/MAPS/props/256x256-pearl-silk.webp, godot/asset/MAPS/props/128x128-matron-spool.webp and
godot/asset/MAPS/items/64x64-matron-thread.webp, and prints where the cocoon's eyes and bottom land in
its cell (the scene's look exports take them).

usage: python scripts/art/pack-matron-art.py
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

SOURCE = REPO / "asset" / "Originals" / "enemies" / "matron" / "cocoon-sheet-a.png"
POSES = REPO / "asset" / "Originals" / "enemies" / "matron" / "matron-sheet-a.png"
ENEMIES = REPO / "godot" / "asset" / "MAPS" / "enemies"
PROPS = REPO / "godot" / "asset" / "MAPS" / "props"
ITEMS = REPO / "godot" / "asset" / "MAPS" / "items"
ALPHA_CUT = 24
GAP_FROM = 360
GAP_TO = 664

COCOON_CELL = (256, 416)
COCOON_FIT = (248, 412)
MATRON_CELL = 384
MATRON_FIT = 376
MATRON_BOTTOM = 380
# Rows of a pose narrower than this (opaque px) are only the thread.
THREAD_PX = 24
# The red eyes in the intact cocoon's source picture (sheet pixels), to report where they land.
EYES_IN_SHEET = (256, 175)


def gap(mask: np.ndarray, axis: int) -> int:
    counts = mask.sum(axis=axis)
    return GAP_FROM + int(np.argmin(counts[GAP_FROM:GAP_TO]))


def bounds(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = np.asarray(image)[..., 3]
    ys, xs = np.nonzero(alpha > ALPHA_CUT)
    if xs.size == 0:
        raise SystemExit("an empty picture")
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def cut(path: Path) -> list[tuple[Image.Image, tuple[int, int]]]:
    """The four pictures, trimmed, with their top-left corner in the sheet."""
    sheet = Image.open(path).convert("RGBA")
    mask = np.asarray(sheet)[..., 3] > ALPHA_CUT
    split_y = gap(mask, 1)
    boxes = []
    for top, bottom in ((0, split_y), (split_y, sheet.height)):
        split_x = gap(mask[top:bottom], 0)
        boxes += [(0, top, split_x, bottom), (split_x, top, sheet.width, bottom)]
    pictures = []
    for box in boxes:
        part = sheet.crop(box)
        left, top, right, bottom = bounds(part)
        pictures.append((part.crop((left, top, right, bottom)), (box[0] + left, box[1] + top)))
    return pictures


def thread_x(picture: Image.Image) -> float:
    """The thread's middle on the picture's top rows."""
    alpha = np.asarray(picture)[:6, :, 3]
    xs = np.nonzero(alpha.max(axis=0) > ALPHA_CUT)[0]
    return float(xs.mean()) if xs.size else picture.width / 2.0


def hang(pictures: list[Image.Image]) -> tuple[Image.Image, float, list[tuple[float, float]]]:
    """The cocoons side by side at one scale, each thread's top at its cell's top middle. Returns the
    strip, the scale and each picture's placed top-left (cell pixels)."""
    cell_w, cell_h = COCOON_CELL
    scale = min(COCOON_FIT[0] / max(p.width for p in pictures), COCOON_FIT[1] / max(p.height for p in pictures))
    strip = Image.new("RGBA", (cell_w * len(pictures), cell_h), (0, 0, 0, 0))
    placed = []
    for i, picture in enumerate(pictures):
        w, h = max(1, round(picture.width * scale)), max(1, round(picture.height * scale))
        sized = picture.resize((w, h), Image.LANCZOS)
        x = round(cell_w / 2 - thread_x(picture) * scale)
        x = max(0, min(cell_w - w, x))
        strip.alpha_composite(sized, (i * cell_w + x, 0))
        placed.append((float(x), 0.0))
    return strip, scale, placed


def fit(picture: Image.Image, cell: int) -> Image.Image:
    scale = min((cell - 8) / picture.width, (cell - 8) / picture.height)
    w, h = max(1, round(picture.width * scale)), max(1, round(picture.height * scale))
    out = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
    out.alpha_composite(picture.resize((w, h), Image.LANCZOS), ((cell - w) // 2, cell - 4 - h))
    return out


def without_thread(picture: Image.Image) -> Image.Image:
    """The pose alone: the longest run of rows at least THREAD_PX wide (gaps of a few rows allowed),
    so the thread above and below the climbing pose, and a stray bit of it beside another, go."""
    alpha = np.asarray(picture)[..., 3] > ALPHA_CUT
    wide = alpha.sum(axis=1) >= THREAD_PX
    best = (0, 0)
    start = None
    gap = 0
    for y, on in enumerate(list(wide) + [False] * 8):
        if on:
            if start is None:
                start = y
            gap = 0
            end = y + 1
            if end - start > best[1] - best[0]:
                best = (start, end)
        elif start is not None:
            gap += 1
            if gap > 4:
                start = None
    if best[1] <= best[0]:
        return picture
    part = picture.crop((0, best[0], picture.width, best[1]))
    part = largest_piece(part)
    left, top, right, bottom = bounds(part)
    return part.crop((left, top, right, bottom))


def largest_piece(picture: Image.Image) -> Image.Image:
    """The picture with every opaque piece but the largest (4-connected) cleared."""
    pixels = np.asarray(picture).copy()
    mask = pixels[..., 3] > ALPHA_CUT
    labels = np.zeros(mask.shape, dtype=np.int32)
    sizes = [0]
    height, width = mask.shape
    for y0, x0 in zip(*np.nonzero(mask)):
        if labels[y0, x0]:
            continue
        label = len(sizes)
        labels[y0, x0] = label
        stack = [(y0, x0)]
        count = 0
        while stack:
            y, x = stack.pop()
            count += 1
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not labels[ny, nx]:
                    labels[ny, nx] = label
                    stack.append((ny, nx))
        sizes.append(count)
    keep = int(np.argmax(sizes))
    pixels[(labels != keep) & (labels != 0), 3] = 0
    return Image.fromarray(pixels, "RGBA")


def stand(pictures: list[Image.Image]) -> Image.Image:
    scale = min(MATRON_FIT / max(p.width for p in pictures), MATRON_FIT / max(p.height for p in pictures))
    strip = Image.new("RGBA", (MATRON_CELL * len(pictures), MATRON_CELL), (0, 0, 0, 0))
    for i, picture in enumerate(pictures):
        w, h = max(1, round(picture.width * scale)), max(1, round(picture.height * scale))
        sized = picture.resize((w, h), Image.LANCZOS)
        strip.alpha_composite(sized, (i * MATRON_CELL + (MATRON_CELL - w) // 2, MATRON_BOTTOM - h))
    print("matron poses: scale %.3f" % scale)
    return strip


def main() -> None:
    (cocoon, cocoon_at), (torn, _torn_at), (pearl, _), (spool, _) = cut(SOURCE)
    strip, scale, placed = hang([cocoon, torn])
    out = ENEMIES / "256x416-tile_2x1-matron-cocoon.webp"
    print(out.name, save_game_webp(strip, out), strip.size, "scale %.3f" % scale)
    eyes = ((EYES_IN_SHEET[0] - cocoon_at[0]) * scale + placed[0][0], (EYES_IN_SHEET[1] - cocoon_at[1]) * scale)
    print("cocoon in its cell: eyes at (%.0f, %.0f), bottom at %.0f, torn bottom at %.0f" % (
        eyes[0], eyes[1], cocoon.height * scale, torn.height * scale))
    poses = [without_thread(picture) for picture, _ in cut(POSES)]
    matron = stand(poses)
    out = ENEMIES / "384x384-tile_4x1-matron.webp"
    print(out.name, save_game_webp(matron, out), matron.size)
    for picture, path, cell in ((pearl, PROPS / "256x256-pearl-silk.webp", 256),
            (spool, PROPS / "128x128-matron-spool.webp", 128), (spool, ITEMS / "64x64-matron-thread.webp", 64)):
        image = fit(picture, cell)
        print(path.name, save_game_webp(image, path), image.size)


if __name__ == "__main__":
    main()
