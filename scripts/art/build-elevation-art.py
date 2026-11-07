#!/usr/bin/env python3
"""Builds the cliff art for elevation (docs/godot/ELEVATION.md): seamless walls.

The art is generated with Magnific (GPT 2.5) and turned into runtime textures here; this tool does
not run in the game. Inputs are in asset/Originals/elevation/generated/, outputs (derived; re-run
the tool instead of editing them) in godot/asset/MAPS/elevation/.

Walls (WALLS: style -> source, courses in the source): a full-frame front view of a rock wall whose
courses are separated by dark straight crevices. The two complete courses after the first crevice
are each resampled to exactly 128 px (one level = 64 world units at 2 px per unit), cut through the
middle of their crevices (stacked courses meet in a full crevice; a wall's top and foot show half
of one), and made horizontally periodic with a minimum-error seam (image quilting). A wall texture
is always two courses tall: stacked walls alternate them (elevation.gd, the level of a wall's top
mod 2). The courses in a source may be a fraction (4.4: a course is 1024 / 4.4 px). A seamless
style (0 courses: the earth walls) has no crevices: one course of it, periodic both ways, twice
(SEAMLESS_SCALE).
  -> <style>-wall.png

(The wall ends, lips and feet it once built, `<style>-wall-end-*.png`, `<ground>-lip.png` and
`-foot.png`, belonged to the front-only cliff look and went with it on 2026-10-17; their sources
stay in asset/Originals/elevation/generated/. The walls' sides and corners come from
scripts/art/build-side-wall-art.py.)

(The old stairs kit it once built, `<style>-stairs-tread.png`, `-riser.png` and a railing coping per
wall style, went on 2026-11-07: the flights are painted pieces now, scripts/art/build-stairs-kit.py.)

Usage: python scripts/art/build-elevation-art.py [name ...] [--preview DIR]
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/elevation/generated"
OUT = ROOT / "godot/asset/MAPS/elevation"

## style -> (source file, number of courses in the source, even out its light). A cliff's style is
## painted on the world's `cliffs` layer or picked by the ground on top (its default in
## godot/game/world/elevation/cliffs/ground_wall_styles.tres). The generator paints the light falling off from the upper left over the whole
## frame, which would repeat as a bright patch every period of the wall: evened out for every style
## but meadow-rock (approved as it is on 2026-10-05).
WALLS = {
    "meadow-rock": ("wall-rock-a.png", 4, False),
    "snow-rock": ("snow-rock-wall-a.png", 4, True),
    "sandstone": ("sandstone-wall-a.png", 4, True),
    "cave-rock": ("cave-rock-wall-a.png", 4, True),
    "crystal-rock": ("crystal-rock-wall-b.png", 4, True),
    "mossy-rock": ("mossy-rock-wall-a.png", 4, True),
    "masonry": ("masonry-wall-d.png", 4.4, True),
    "root-rock": ("root-rock-wall-a.png", 4, True),
    "red-rock": ("red-rock-wall-a.png", 4, True),
    # The earth walls (2026-11-05, the owner: "dirt walls ... mountain, desert and ice", "we don't
    # have to stick to the blocks styles", "we dont need to make the between lines so evident"):
    # one continuous face of earth, no courses (0): see SEAMLESS_SCALE.
    "mountain-dirt": ("mountain-dirt-wall-a.png", 0, True),
    "desert-dirt": ("desert-dirt-wall-a.png", 0, True),
    "ice-dirt": ("ice-dirt-wall-a.png", 0, True),
    # The faces of the Phaser-era elevation experiment (asset/Originals/elevation/faces/ and
    # faces-v2/, 2026-10-04), seamless too (the owner, 2026-11-05: "i think that art is cool").
    "autumn-face": ("../faces/autumn-a.png", 0, True),
    "castle-face": ("../faces/castle-a.png", 0, True),
    "cave-face": ("../faces/cave-a.png", 0, True),
    "crystal-face": ("../faces/crystal-a.png", 0, True),
    "desert-face": ("../faces/desert-a.png", 0, True),
    "dungeon-face": ("../faces/dungeon-a.png", 0, True),
    "forest-face": ("../faces/forest-a.png", 0, True),
    "meadow-face": ("../faces/meadow-a.png", 0, True),
    "snow-face": ("../faces/snow-a.png", 0, True),
    "town-face": ("../faces/town-a.png", 0, True),
    "volcanic-face": ("../faces/volcanic-a.png", 0, True),
    "desert-strata": ("../faces-v2/desert-a.png", 0, True),
}
## A seamless style (0 courses in WALLS): an earth face with no courses or crevices, its levels told
## apart by the code (the walls' height, their top edge and foot), not by the look. Its source is
## scaled by SEAMLESS_SCALE (as a four-course source is: a level is 256 source px), one course is cut
## from its middle and made periodic both ways (minimum-error seams, SEAMLESS_OVERLAP source rows
## across the vertical wrap), and the texture holds it twice: every course of its walls is alike and
## stacked levels run on without a line.
SEAMLESS_SCALE = 0.5
SEAMLESS_OVERLAP = 48
## Seamless styles whose source shows rows (of bricks or blocks): style -> rows a level holds. The
## source is scaled so that many rows fill a level exactly (their period measured: `row_period`) and the
## course is cut from a mortar line, so the rows run on across the vertical wrap.
SEAMLESS_ROWS = {"castle-face": 2, "dungeon-face": 2, "town-face": 2}
## Lags (source px) searched for a row period.
ROW_PERIOD_RANGE = (40, 220)
## Evening out the light: the source's brightness averaged over LIGHT_CELLS x LIGHT_CELLS blocks
## (a stone or two each), smoothed, is divided out.
LIGHT_CELLS = 4
## Art px per course (one level = 64 world units at 2 px per unit).
COURSE_PX = 128
## Source columns blended across the horizontal wrap.
OVERLAP = 192
## Rows searched around each expected wall crevice.
JOINT_SEARCH = 48


def periodic(image: np.ndarray, overlap: int) -> np.ndarray:
    """Makes the image horizontally periodic: its right `overlap` columns replace the left ones
    up to a per-row seam of minimum difference (dynamic programming, 8-connected)."""
    height, width = image.shape[:2]
    period = width - overlap
    left = image[:, :overlap]
    right = image[:, period:]
    cost = ((left - right) ** 2).sum(axis=2)
    acc = cost.copy()
    for y in range(1, height):
        prev = acc[y - 1]
        best = np.minimum(prev, np.minimum(np.roll(prev, 1), np.roll(prev, -1)))
        best[0] = min(prev[0], prev[1])
        best[-1] = min(prev[-1], prev[-2])
        acc[y] += best
    seam = np.zeros(height, dtype=int)
    seam[-1] = int(np.argmin(acc[-1]))
    for y in range(height - 2, -1, -1):
        x = seam[y + 1]
        lo, hi = max(0, x - 1), min(overlap, x + 2)
        seam[y] = lo + int(np.argmin(acc[y, lo:hi]))
    out = image[:, :period].copy()
    for y in range(height):
        out[y, : seam[y]] = right[y, : seam[y]]
    return out


def resize(image: np.ndarray, width: int, height: int) -> np.ndarray:
    channels = [np.asarray(Image.fromarray(image[..., c].astype(np.float32), "F").resize((width, height), Image.LANCZOS), dtype=np.float64)
                for c in range(image.shape[2])]
    return np.stack(channels, axis=-1)


def tiled_preview(image: Image.Image, path: Path, tiles_x: int = 3, tiles_y: int = 3) -> None:
    out = Image.new("RGBA", (image.size[0] * tiles_x, image.size[1] * tiles_y), (70, 40, 110, 255))
    for ty in range(tiles_y):
        for tx in range(tiles_x):
            out.alpha_composite(image, (tx * image.size[0], ty * image.size[1]))
    out.save(path)


# --- walls ---------------------------------------------------------------------------------

def find_joints(rgb: np.ndarray, courses: float) -> list[int]:
    """Rows of the dark crevices between courses (the darkest row near each expected one)."""
    lum = rgb.mean(axis=2).mean(axis=1)
    height = rgb.shape[0]
    joints = []
    for k in range(1, math.ceil(courses)):
        expected = round(k * height / courses)
        lo, hi = max(0, expected - JOINT_SEARCH), min(height, expected + JOINT_SEARCH)
        joints.append(lo + int(np.argmin(lum[lo:hi])))
    return joints


def course_spans(joints: list[int]) -> list[tuple[int, int]]:
    """The two complete courses after the first crevice (a wall texture is two courses tall)."""
    spans = list(zip(joints, joints[1:]))[:2]
    assert len(spans) == 2, f"two complete courses needed, crevices at {joints}"
    return spans


def even_light(rgb: np.ndarray) -> np.ndarray:
    """Divides out the source's broad light (its brightness over LIGHT_CELLS² blocks, smoothed back
    to full size), keeping its mean brightness; the shading of each stone stays."""
    height, width = rgb.shape[:2]
    lum = Image.fromarray(rgb.mean(axis=2).astype(np.float32), "F")
    broad = lum.resize((LIGHT_CELLS, LIGHT_CELLS), Image.BOX).resize((width, height), Image.BICUBIC)
    broad = np.maximum(np.asarray(broad, dtype=np.float64), 1.0)
    return rgb * (broad.mean() / broad)[..., None]


def periodic_rows(image: np.ndarray, overlap: int) -> np.ndarray:
    """`periodic` down the image: its bottom `overlap` rows replace the top ones up to a seam."""
    return periodic(image.transpose(1, 0, 2), overlap).transpose(1, 0, 2)


def row_period(rgb: np.ndarray) -> float:
    """The period (source px) of the rows a source shows: the strongest repeat of its rows'
    brightness within ROW_PERIOD_RANGE."""
    rows = rgb.mean(axis=(1, 2))
    rows = rows - rows.mean()
    repeat = np.correlate(rows, rows, "full")[len(rows) - 1:]
    lo, hi = ROW_PERIOD_RANGE
    return float(lo + int(np.argmax(repeat[lo:hi])))


def seamless_layout(style: str, rgb: np.ndarray) -> tuple[np.ndarray, int, int]:
    """A seamless style's source scaled for its walls, the row its course is cut from and the step
    between rows of the same kind (a row style's row period, else 1)."""
    rows = SEAMLESS_ROWS.get(style, 0)
    scale = COURSE_PX / (rows * row_period(rgb)) if rows else SEAMLESS_SCALE
    width, height = round(rgb.shape[1] * scale), round(rgb.shape[0] * scale)
    scaled = resize(rgb, width, height)
    top = (height - COURSE_PX - SEAMLESS_OVERLAP) // 2
    step = 1
    if rows:
        # From the darkest row (a mortar line) within a row period above the middle.
        step = COURSE_PX // rows
        light = scaled.mean(axis=(1, 2))
        top = top - step + int(np.argmin(light[top - step:top]))
    return scaled, top, step


def seamless_course(style: str, rgb: np.ndarray) -> np.ndarray:
    """One course of a seamless style's source (`seamless_layout`), from its middle, periodic both
    ways."""
    scaled, top, _ = seamless_layout(style, rgb)
    course = periodic_rows(scaled[top:top + COURSE_PX + SEAMLESS_OVERLAP], SEAMLESS_OVERLAP)
    return periodic(course, round(OVERLAP * SEAMLESS_SCALE))


def build_wall(style: str, preview: Path | None) -> None:
    source, courses, flatten = WALLS[style]
    rgb = np.asarray(Image.open(SRC / source).convert("RGB")).astype(np.float64)
    if flatten:
        rgb = even_light(rgb)
    if courses == 0:
        course = seamless_course(style, rgb)
        out = Image.fromarray(np.clip(np.concatenate([course, course], axis=0), 0, 255).astype(np.uint8)).convert("RGBA")
        out.save(OUT / f"{style}-wall.png")
        print(f"wall {style}: seamless, {out.size[0]}x{out.size[1]} px")
        if preview is not None:
            tiled_preview(out, preview / f"{style}-wall-tiled.png")
        return
    joints = find_joints(rgb, courses)
    spans = course_spans(joints)
    # One horizontal scale for every course (the mean), so stones keep their proportions.
    scale = float(np.mean([COURSE_PX / (bottom - top) for top, bottom in spans]))
    width = round(rgb.shape[1] * scale)
    rows = [resize(rgb[top:bottom], width, COURSE_PX) for top, bottom in spans]
    wall = periodic(np.concatenate(rows, axis=0), round(OVERLAP * scale))
    out = Image.fromarray(np.clip(wall, 0, 255).astype(np.uint8)).convert("RGBA")
    out.save(OUT / f"{style}-wall.png")
    print(f"wall {style}: crevices at {joints}, {len(rows)} courses, {out.size[0]}x{out.size[1]} px")
    if preview is not None:
        tiled_preview(out, preview / f"{style}-wall-tiled.png")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("names", nargs="*", help="wall styles to build (default: all)")
    parser.add_argument("--preview", type=Path, help="also write tiled previews here")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.preview is not None:
        args.preview.mkdir(parents=True, exist_ok=True)
    for name in args.names or list(WALLS):
        if name in WALLS:
            build_wall(name, args.preview)


if __name__ == "__main__":
    main()
