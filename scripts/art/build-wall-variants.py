#!/usr/bin/env python3
"""Builds the cliff walls' variants (docs/godot/ELEVATION.md "Wall variation"): stretches of a wall
style's stone course that all start and end like its wall art, so the cliff shader can pick one per
period of the wall and per course and the stones no longer repeat every period.

A style's wall art (`<style>-wall.png`, scripts/art/build-elevation-art.py) is periodic: every
period (416 px for the generated styles, 536 for storybook-rock) the same stones come back, a
course of each level the same as the course two levels below. Here each variant is one course
(128 px tall, a period wide) quilted from the style's stone courses (image quilting, Efros and
Freeman 2001): patches of whole course height, laid left to right, each joined to what is already
laid along a minimum-error seam, so the joins follow the gaps between stones. The material is the
wall art's own two courses and the two complete courses of each extra source (`EXTRA`: the other
Magnific candidate of the style, colour matched to the wall art; storybook-rock, cut from a
painting, has only its own two courses, laid in wider patches: `SIZES`). Every variant keeps the wall
art's first course's columns at its two ends (`EDGE` px each side of the period's wrap, the seams
never reaching the outer `KEEP` columns), so any variant follows any other, or the plain art,
without a seam. The wrap is moved first to a dark gap between stones (`_edge_column`): the
variants' sheet starts there.
  -> <style>-wall-variants.png (a period wide, VARIANTS courses stacked; RGBA like the wall art)

Usage: python scripts/art/build-wall-variants.py [style ...] [--preview DIR] [--seed N]
"""
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("elevation_art", ROOT / "scripts/art/build-elevation-art.py")
art = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(art)

SRC = art.SRC
OUT = art.OUT
COURSE_PX = art.COURSE_PX
## style -> extra Magnific sources of the same style (the other candidate), for more stones.
EXTRA = {
    "meadow-rock": ["wall-rock-b.png"],
    "snow-rock": ["snow-rock-wall-b.png"],
    "sandstone": ["sandstone-wall-b.png"],
    "cave-rock": ["cave-rock-wall-b.png"],
    "crystal-rock": ["crystal-rock-wall-a.png"],
    "mossy-rock": ["mossy-rock-wall-b.png"],
    "masonry": ["masonry-wall-c.png"],
    "root-rock": ["root-rock-wall-b.png"],
    "red-rock": ["red-rock-wall-b.png"],
    "mountain-dirt": ["mountain-dirt-wall-b.png"],
    "desert-dirt": ["desert-dirt-wall-b.png"],
    "ice-dirt": ["ice-dirt-wall-b.png"],
}
## Courses in the variants' sheet.
VARIANTS = 6
## Columns of the wall art each side of the wrap a variant may keep (its seams run inside them), and
## the outer ones it always keeps, so it joins any other variant there.
EDGE = 40
KEEP = 3
## A patch's width (px) and how far it overlaps what is laid before it (where its seam runs).
PATCH_MIN = 120
PATCH_MAX = 220
OVERLAP = 40
## Per style, other sizes (`_sizes`): storybook-rock's blocks are wider than a default patch, so its
## patches take a block or more and their seams can find the joints between blocks.
SIZES = {
    "storybook-rock": {"edge": 64, "overlap": 64, "min": 230, "max": 330},
}
## A seamless style (an earth wall: 0 courses in build-elevation-art.py WALLS) has no crevices to hide
## a course's joins: its variants also keep the wall art's rows at their top and bottom (BAND rows
## each, the seams inside them, never the outer KEEP), so a course of any variant sits on any other
## without a line; the shader does not shift its courses (they would no longer meet). Its material is
## cut from the scaled sources every STRIP_STEP rows.
BAND = 24
STRIP_STEP = 32
## A patch closer than this (mean squared difference per channel) to the base where it goes copies it.
COPY_MIN = 400.0
## Candidate patches are tried every STRIDE px of the material; one of the BEST cheapest is taken.
STRIDE = 3
BEST = 4
## A patch's light is matched to the overlap it joins, within these bounds.
GAIN = (0.88, 1.12)
## Px across a seam blended, so it leaves no hard step.
FEATHER = 2
## How much a seam prefers the dark gaps between stones to running through a stone: added to its cost
## per unit of brightness (the squared difference of the two sides, summed over RGB, is the rest).
DARK_WEIGHT = 12.0


def lum(image: np.ndarray) -> np.ndarray:
    return image @ np.array([0.299, 0.587, 0.114])


def course_strips(source: str, courses: float, flatten: bool) -> list[np.ndarray]:
    """The source's complete courses (crevice to crevice), each resampled to COURSE_PX tall at one
    width scale, as build-elevation-art.py cuts a wall's two."""
    rgb = np.asarray(Image.open(SRC / source).convert("RGB")).astype(np.float64)
    if flatten:
        rgb = art.even_light(rgb)
    joints = art.find_joints(rgb, courses)
    spans = list(zip(joints, joints[1:]))
    scale = float(np.mean([COURSE_PX / (bottom - top) for top, bottom in spans]))
    width = round(rgb.shape[1] * scale)
    return [art.resize(rgb[top:bottom], width, COURSE_PX) for top, bottom in spans]


def seamless(style: str) -> bool:
    return style in art.WALLS and art.WALLS[style][1] == 0


def seamless_strips(style: str, source: str, own: bool) -> list[np.ndarray]:
    """Courses of a seamless style's source, scaled as build-elevation-art.py scales it
    (`seamless_layout`), cut every STRIP_STEP rows (a row style's: every row period, from a mortar
    line, so the rows meet the base's). `own`: the source the wall art was cut from, whose rows that
    went into it are left out (a strip a few rows off them is the wall art again, and every variant
    came out alike)."""
    rgb = art.even_light(np.asarray(Image.open(SRC / source).convert("RGB")).astype(np.float64))
    scaled, cut, step = art.seamless_layout(style, rgb)
    height = scaled.shape[0]
    taken = range(cut - COURSE_PX + 1, cut + COURSE_PX + art.SEAMLESS_OVERLAP) if own else range(0)
    starts = range(cut % step, height - COURSE_PX + 1, step) if step > 1 else range(0, height - COURSE_PX + 1, STRIP_STEP)
    return [scaled[y:y + COURSE_PX] for y in starts if y not in taken]


def match_colour(strip: np.ndarray, reference: np.ndarray) -> np.ndarray:
    """Each channel moved to the reference's mean and spread."""
    out = strip.copy()
    for c in range(3):
        s_mean, s_std = strip[..., c].mean(), strip[..., c].std() + 1e-6
        r_mean, r_std = reference[..., c].mean(), reference[..., c].std()
        out[..., c] = (strip[..., c] - s_mean) * (r_std / s_std) + r_mean
    return out


def _edge_column(row: np.ndarray, quiet: bool = False) -> int:
    """The column of the course's darkest band EDGE px wide: the gap between two stones where the
    variants all start and end. `quiet` (a seamless style, whose kept columns show on every course
    of a wall, one above the other): its plainest band instead (least spread of brightness), so no
    stone or frost stands in it."""
    width = row.shape[1]
    if quiet:
        light = lum(row)
        return int(np.argmin([np.take(light, range(x - EDGE // 2, x + EDGE // 2), axis=1, mode="wrap").std() for x in range(width)]))
    dark = light = lum(row).mean(axis=0)
    window = np.array([np.take(dark, range(x - EDGE // 2, x + EDGE // 2), mode="wrap").mean() for x in range(width)])
    return int(np.argmin(window))


def seam(cost: np.ndarray, lo: int, hi: int) -> np.ndarray:
    """Per row, the column (lo … hi - 1) of a top-to-bottom path of least cost (8-connected)."""
    height, width = cost.shape
    big = cost.max() * height + 1.0
    acc = np.full_like(cost, big)
    acc[0, lo:hi] = cost[0, lo:hi]
    for y in range(1, height):
        prev = acc[y - 1]
        best = np.minimum(prev, np.minimum(np.concatenate([[big], prev[:-1]]), np.concatenate([prev[1:], [big]])))
        acc[y, lo:hi] = cost[y, lo:hi] + best[lo:hi]
    path = np.zeros(height, dtype=int)
    path[-1] = lo + int(np.argmin(acc[-1, lo:hi]))
    for y in range(height - 2, -1, -1):
        x = path[y + 1]
        a, b = max(lo, x - 1), min(hi, x + 2)
        path[y] = a + int(np.argmin(acc[y, a:b]))
    return path


def join(left: np.ndarray, right: np.ndarray, lo: int, hi: int) -> np.ndarray:
    """Two images of the overlap's size joined along their seam of least difference: `left` left of
    it, `right` right of it, FEATHER px blended across."""
    cost = ((left - right) ** 2).sum(axis=2) + DARK_WEIGHT * (lum(left) + lum(right)) * 0.5
    path = seam(cost, lo, hi)
    x = np.arange(left.shape[1])[None, :]
    weight = np.clip((x - path[:, None] + FEATHER * 0.5) / max(FEATHER, 1), 0.0, 1.0)[..., None]
    return left * (1.0 - weight) + right * weight


def seam_weight(a: np.ndarray, b: np.ndarray, lo: int, hi: int) -> np.ndarray:
    """How much of `b` (0 … 1) each pixel of the overlap takes: `a` left of their seam of least
    difference (`join`'s), `b` right of it."""
    cost = ((a - b) ** 2).sum(axis=2) + DARK_WEIGHT * (lum(a) + lum(b)) * 0.5
    path = seam(cost, lo, hi)
    x = np.arange(a.shape[1])[None, :]
    return np.clip((x - path[:, None] + FEATHER * 0.5) / max(FEATHER, 1), 0.0, 1.0)


def seam_weight_rows(a: np.ndarray, b: np.ndarray, lo: int, hi: int) -> np.ndarray:
    """`seam_weight` across rows: `a` above the seam, `b` below it."""
    return seam_weight(a.transpose(1, 0, 2), b.transpose(1, 0, 2), lo, hi).T


def candidates(material: list[np.ndarray], width: int) -> list[tuple[int, int]]:
    out = []
    for index, strip in enumerate(material):
        out += [(index, x) for x in range(0, strip.shape[1] - width + 1, STRIDE)]
    return out


def quilt(base: np.ndarray, material: list[np.ndarray], forbidden: tuple[int, int], rng: np.random.Generator,
          used: list[tuple[int, int]], sizes: dict[str, int], band: int = 0) -> np.ndarray:
    """One variant: the base course's EDGE columns each side of the wrap, the rest laid from the
    material's patches. `forbidden` (material index, offset): the base itself in the material, whose
    patch at the same place would only copy it. `sizes`: the style's edge, overlap and patch widths
    (`_sizes`). `band`: rows at the top and the bottom kept from the base too (a seamless style)."""
    EDGE, OVERLAP, PATCH_MIN, PATCH_MAX = sizes["edge"], sizes["overlap"], sizes["min"], sizes["max"]
    period = base.shape[1]
    canvas = base.copy()
    x = EDGE
    while x < period - EDGE:
        remaining = period - EDGE - x
        last = remaining + 2 * OVERLAP <= PATCH_MAX
        if last:
            width = remaining + 2 * OVERLAP
        else:
            width = int(rng.integers(PATCH_MIN, PATCH_MAX + 1))
            if remaining - (width - OVERLAP) + 2 * OVERLAP < PATCH_MIN:
                width = remaining // 2 + OVERLAP
        start = x - OVERLAP
        options = candidates(material, width)
        left = canvas[:, start:start + OVERLAP]
        right = canvas[:, period - EDGE:period - EDGE + OVERLAP] if last else None
        costs = []
        for index, offset in options:
            patch = material[index][:, offset:offset + width]
            gain = np.clip(lum(left).mean() / max(lum(patch[:, :OVERLAP]).mean(), 1.0), *GAIN)
            cost = ((left - patch[:, :OVERLAP] * gain) ** 2).mean()
            if last:
                cost += ((right - patch[:, width - OVERLAP:] * gain) ** 2).mean()
            if band:
                cost += ((canvas[:band, start:start + width] - patch[:band] * gain) ** 2).mean()
                cost += ((canvas[-band:, start:start + width] - patch[-band:] * gain) ** 2).mean()
            # The base continued at its own place, or a patch near one already laid: far less wanted.
            base_offset = (forbidden[1] + start) % period
            if index == forbidden[0] and min(abs(offset - base_offset), abs(offset - base_offset - period)) < PATCH_MAX:
                cost *= 4.0
            if any(index == i and abs(offset - o) < width for i, o in used):
                cost *= 2.0
            # A patch that only copies the base where it goes (the base's own source cut at the same
            # place: a seamless style's material holds it) brings nothing new.
            if ((patch[:, OVERLAP:width - OVERLAP] - base[:, start + OVERLAP:start + width - OVERLAP]) ** 2).mean() < COPY_MIN:
                cost *= 20.0
            costs.append(cost)
        order = np.argsort(costs)[:BEST]
        index, offset = options[int(rng.choice(order))]
        used.append((index, offset))
        patch = material[index][:, offset:offset + width]
        patch = patch * np.clip(lum(left).mean() / max(lum(patch[:, :OVERLAP]).mean(), 1.0), *GAIN)
        if band:
            # Seams on all sides: the left one (inside the base's first EDGE columns for the first
            # patch), the right one into the base's kept end for the last, and along the top and
            # bottom bands the base keeps.
            region = canvas[:, start:start + width].copy()
            weight = np.ones(region.shape[:2])
            weight[:, :OVERLAP] *= seam_weight(region[:, :OVERLAP], patch[:, :OVERLAP], KEEP if start < KEEP else 0, OVERLAP)
            if last:
                end = period - EDGE
                weight[:, width - OVERLAP:] *= 1.0 - seam_weight(patch[:, width - OVERLAP:], base[:, end:end + OVERLAP], 0, OVERLAP - KEEP)
            weight[:band] *= seam_weight_rows(region[:band], patch[:band], KEEP, band)
            weight[-band:] *= 1.0 - seam_weight_rows(patch[-band:], region[-band:], 0, band - KEEP)
            canvas[:, start:start + width] = region * (1.0 - weight[..., None]) + patch * weight[..., None]
            x = start + width - (OVERLAP if last else 0)
            if last:
                break
            continue
        # The first patch's seam runs inside the base's first EDGE columns, never the outer KEEP.
        joined = join(left, patch[:, :OVERLAP], KEEP if start < KEEP else 0, OVERLAP)
        canvas[:, start:start + OVERLAP] = joined
        canvas[:, start + OVERLAP:start + width] = patch[:, OVERLAP:]
        if last:
            # The patch's last OVERLAP columns meet the base's kept end: seams inside it, never the outer KEEP columns.
            end = period - EDGE
            joined = join(patch[:, width - OVERLAP:], base[:, end:end + OVERLAP], 0, OVERLAP - KEEP)
            canvas[:, end:end + OVERLAP] = joined
        x = start + width - (OVERLAP if last else 0)
        if last:
            break
    # The first patch's seam ran inside the base's first EDGE columns: the outer KEEP stay the base's.
    canvas[:, :KEEP] = base[:, :KEEP]
    canvas[:, period - KEEP:] = base[:, period - KEEP:]
    if band:
        canvas[:KEEP] = base[:KEEP]
        canvas[-KEEP:] = base[-KEEP:]
    return canvas


def _sizes(style: str) -> dict[str, int]:
    sizes = {"edge": EDGE, "overlap": OVERLAP, "min": PATCH_MIN, "max": PATCH_MAX}
    sizes.update(SIZES.get(style, {}))
    return sizes


def styles() -> list[str]:
    """Every generated style (build-elevation-art.py WALLS), and storybook-rock (cut from the
    painting: its own two courses only) when its wall art exists."""
    names = list(art.WALLS)
    if (OUT / "storybook-rock-wall.png").exists():
        names.append("storybook-rock")
    return names


def build(style: str, preview: Path | None, seed: int) -> None:
    sizes = _sizes(style)
    wall = np.asarray(Image.open(OUT / f"{style}-wall.png").convert("RGB")).astype(np.float64)
    period = wall.shape[1]
    rows = [wall[:COURSE_PX], wall[COURSE_PX:2 * COURSE_PX]]
    # The wrap moved to a gap between stones: the variants' sheet starts there.
    edge = _edge_column(rows[0], seamless(style))
    base = np.roll(rows[0], -edge + sizes["edge"], axis=1)
    # The wall art's two courses, twice round (patches may run over their wrap), then the extra courses.
    # A seamless style's two courses are the base itself (the same course twice): its material is only
    # its sources' other rows, or every variant would be the base moved along.
    band = BAND if seamless(style) else 0
    material = [] if band else [np.concatenate([row, row], axis=1) for row in rows]
    reference = np.concatenate(rows, axis=1)
    sources = ([art.WALLS[style][0]] if band else []) + [e for e in EXTRA.get(style, []) if (SRC / e).exists()]
    for extra in sources:
        strips = seamless_strips(style, extra, extra == art.WALLS[style][0]) if band else course_strips(extra, art.WALLS[style][1], True)
        material += [match_colour(strip, reference) for strip in strips]
    if band and not material:
        # A short source (faces-v2's desert strata) has no rows left beside the wall art's: take them
        # all; the patches that would copy the base where they go are held back (COPY_MIN).
        material = [match_colour(strip, reference) for strip in seamless_strips(style, art.WALLS[style][0], False)]
    rng = np.random.default_rng(seed)
    used: list[tuple[int, int]] = []
    forbidden =(-1 if band else 0, (edge - sizes["edge"]) % period)
    variants = [quilt(base, material, forbidden, rng, used, sizes, band) for _ in range(VARIANTS)]
    sheet = np.clip(np.concatenate(variants, axis=0), 0, 255).astype(np.uint8)
    out = Image.fromarray(sheet).convert("RGBA")
    out.save(OUT / f"{style}-wall-variants.png")
    print(f"variants {style}: {VARIANTS} courses of {period} px from {len(material)} strips, wrap moved {edge - sizes['edge']} px")
    if preview is not None:
        _preview(wall, base, variants, preview / f"{style}-variants-preview.png", rng, not band)


def _preview(wall: np.ndarray, base: np.ndarray, variants: list[np.ndarray], path: Path, rng: np.random.Generator,
             shifted: bool = True, periods: int = 6) -> None:
    """Three courses of a wall six periods long: the art as it repeats today (its two courses
    alternating), then picked variants, each course shifted as the shader shifts it."""
    tiled = np.concatenate([wall] * periods, axis=1)
    plain = np.concatenate([tiled, tiled[:COURSE_PX]], axis=0)
    rows = []
    for course in range(3):
        row = np.concatenate([variants[int(rng.integers(len(variants)))] for _ in range(periods + 1)], axis=1)
        shift = int(rng.integers(base.shape[1])) if shifted else 0
        rows.append(row[:, shift:shift + base.shape[1] * periods])
    varied = np.concatenate(rows, axis=0)
    gap = np.full((16, plain.shape[1], 3), 30.0)
    picture = np.concatenate([plain, gap, varied], axis=0)
    Image.fromarray(np.clip(picture, 0, 255).astype(np.uint8)).save(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("styles", nargs="*", help="wall styles (default: every style of build-elevation-art.py WALLS, and storybook-rock)")
    parser.add_argument("--preview", type=Path, help="write <style>-variants-preview.png here")
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()
    if args.preview is not None:
        args.preview.mkdir(parents=True, exist_ok=True)
    for style in args.styles or styles():
        build(style, args.preview, args.seed)


if __name__ == "__main__":
    main()
