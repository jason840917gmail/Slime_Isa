#!/usr/bin/env python3
"""Builds the cliff art for elevation (docs/godot/ELEVATION.md): seamless walls and the stairs' stone.

The art is generated with Magnific (GPT 2.5) and turned into runtime textures here; this tool does
not run in the game. Inputs are in asset/Originals/elevation/generated/, outputs (derived; re-run
the tool instead of editing them) in godot/asset/MAPS/elevation/.

Walls (WALLS: style -> source, courses in the source): a full-frame front view of a rock wall whose
courses are separated by dark straight crevices. The two complete courses after the first crevice
are each resampled to exactly 128 px (one level = 64 world units at 2 px per unit), cut through the
middle of their crevices (stacked courses meet in a full crevice; a wall's top and foot show half
of one), and made horizontally periodic with a minimum-error seam (image quilting). A wall texture
is always two courses tall: stacked walls alternate them (elevation.gd, the level of a wall's top
mod 2). The courses in a source may be a fraction (4.4: a course is 1024 / 4.4 px).
  -> <style>-wall.png

(The wall ends, lips and feet it once built, `<style>-wall-end-*.png`, `<ground>-lip.png` and
`-foot.png`, belonged to the front-only cliff look and went with it on 2026-10-17; their sources
stay in asset/Originals/elevation/generated/. The walls' sides and corners come from
scripts/art/build-side-wall-art.py.)

Stairs (STAIRS: style -> its kit): the stone of the flights of stairs (docs/godot/ELEVATION.md
"Stairs", approved mockups in asset/Originals/elevation/stairs-mockups/). Each source holds rows of
cut stone; one row, crevice to crevice, is one step: a tread seen from above, or a riser (and a
railing's coping) seen from the front. The row is resampled to STEP_PX (one rise of 64 / 3 world
units at 2 px per unit), made opaque and horizontally periodic. Risers are baked RISER_TONE darker;
the coping is the riser row tinted halfway to the style's wall rock, COPING_LIGHT lighter. A
flight's railings and posts use the wall itself.
  -> <style>-stairs-tread.png, <style>-stairs-riser.png, <style>-stairs-coping.png
Every other wall style gets its own coping from the kit's riser row (STAIRS_KIT), tinted the same
way towards its own wall, so a flight's railings are of the rock of the cliff it leaves.
  -> <style>-stairs-coping.png

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
## painted on the world's `cliffs` layer or picked by the ground on top (elevation.gd
## GROUND_WALL_STYLES). The generator paints the light falling off from the upper left over the whole
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
}
## Evening out the light: the source's brightness averaged over LIGHT_CELLS x LIGHT_CELLS blocks
## (a stone or two each), smoothed, is divided out.
LIGHT_CELLS = 4
## style -> stairs kit: per part, (source file, first row, last row) of one step, crevice to crevice
STAIRS = {
    "meadow-rock": {
        "tread": ("stairs-tread-a.png", 394, 530),
        "riser": ("stairs-riser-b.png", 322, 471),
    },
}
## The kit every flight's treads and risers come from (elevation.gd STAIRS_STYLE).
STAIRS_KIT = "meadow-rock"
## One step's row at game size: a rise of 64 / 3 world units at 2 px per unit.
STEP_PX = 43
RISER_TONE = 0.80
COPING_LIGHT = 1.10
## Source px cross-faded into the horizontal seam of a stairs row.
STAIRS_OVERLAP = 64
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


def build_wall(style: str, preview: Path | None) -> None:
    source, courses, flatten = WALLS[style]
    rgb = np.asarray(Image.open(SRC / source).convert("RGB")).astype(np.float64)
    if flatten:
        rgb = even_light(rgb)
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


def stairs_row(source: str, first: int, last: int) -> np.ndarray:
    """One step's row of a stairs source at game size (STEP_PX tall), opaque and periodic."""
    rgb = np.asarray(Image.open(SRC / source).convert("RGB")).astype(np.float64)[first:last]
    scale = STEP_PX / rgb.shape[0]
    row = resize(rgb, round(rgb.shape[1] * scale), STEP_PX)
    return periodic(row, round(STAIRS_OVERLAP * scale))


def save_rgb(image: np.ndarray, path: Path) -> Image.Image:
    out = Image.fromarray(np.clip(image, 0, 255).astype(np.uint8)).convert("RGBA")
    out.save(path)
    return out


def coping_for(riser: np.ndarray, style: str) -> np.ndarray:
    """The riser row tinted halfway to the mean colour of `style`'s wall, COPING_LIGHT lighter."""
    wall = np.asarray(Image.open(OUT / f"{style}-wall.png").convert("RGB")).astype(np.float64)
    tint = wall.reshape(-1, 3).mean(0) / riser.reshape(-1, 3).mean(0)
    return riser * (0.5 + 0.5 * tint)[None, None, :] * COPING_LIGHT


def build_stairs(style: str, preview: Path | None) -> None:
    kit = STAIRS[style]
    tread = stairs_row(*kit["tread"])
    riser = stairs_row(*kit["riser"])
    coping = coping_for(riser, style)
    for part, image in (("tread", tread), ("riser", riser * RISER_TONE), ("coping", coping)):
        out = save_rgb(image, OUT / f"{style}-stairs-{part}.png")
        print(f"stairs {style} {part}: {out.size[0]}x{out.size[1]} px")
        if preview is not None:
            tiled_preview(out, preview / f"{style}-stairs-{part}-tiled.png", 3, 3)


def build_coping(style: str, preview: Path | None) -> None:
    """The railings' coping of a wall style without a stairs kit: STAIRS_KIT's riser row, tinted
    towards this style's wall."""
    coping = coping_for(stairs_row(*STAIRS[STAIRS_KIT]["riser"]), style)
    out = save_rgb(coping, OUT / f"{style}-stairs-coping.png")
    print(f"stairs {style} coping: {out.size[0]}x{out.size[1]} px")
    if preview is not None:
        tiled_preview(out, preview / f"{style}-stairs-coping-tiled.png", 3, 3)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("names", nargs="*", help="wall styles to build (default: all)")
    parser.add_argument("--preview", type=Path, help="also write tiled previews here")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.preview is not None:
        args.preview.mkdir(parents=True, exist_ok=True)
    names = args.names or list(dict.fromkeys(list(WALLS) + list(STAIRS)))
    for name in names:
        if name in WALLS:
            build_wall(name, args.preview)
        if name in STAIRS:
            build_stairs(name, args.preview)
        elif name in WALLS:
            build_coping(name, args.preview)


if __name__ == "__main__":
    main()
