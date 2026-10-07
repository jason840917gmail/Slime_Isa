#!/usr/bin/env python3
"""Builds the cliff art for elevation (docs/godot/ELEVATION.md): seamless walls, lips and feet.

The art is generated with Magnific (GPT 2.5) and turned into runtime textures here; this tool does
not run in the game. Inputs are in asset/Originals/elevation/generated/, outputs (derived; re-run
the tool instead of editing them) in godot/game/world/elevation/art/.

Walls (WALLS: style -> source, courses asked for): a full-frame front view of a rock wall whose
courses are separated by dark straight crevices. The complete courses between the first and last
crevice are each resampled to exactly 128 px (one level = 64 world units at 2 px per unit), cut
through the middle of their crevices (stacked courses meet in a full crevice; a wall's top and foot
show half of one), and made horizontally periodic with a minimum-error seam (image quilting).
  -> <style>-wall.png

Wall ends (WALL_ENDS: style -> right and left end sources): the end of the same wall in a column
of rounded corner stones. The column is cut from the crevice beside it to just past the stones'
bulge, its courses resampled like the wall's and its colours matched to the wall.
  -> <style>-wall-end-right.png, <style>-wall-end-left.png

Strips (STRIPS: ground -> its sheet and a lip and a foot source): one ground's cliff top and foot.
  lip   the ground's straight front edge with a fringe of tufts, soil and roots over the edge,
        transparent below it;
  foot  the ground with a fringe of tufts growing up, transparent above it.
Each source gives its edge line (the source row of the soil band where the cliff edge or the wall
foot runs), how many px of fringe lie on the ground's side of it (kept opaque) and its scale. The
strip keeps LAYOUT px of art on each side of the edge (ground side / fringe side); past the
fringe the solid ground fades out over FADE px into the real ground the layer draws there. The
colours of the solid ground are matched to the ground's sheet and the strip is made horizontally
periodic. In the game a lip's edge row (EDGE_ROWS) lies on the cliff's top edge, a foot's on the
wall's foot (elevation_fringe.gdshader).
  -> <ground>-lip.png, <ground>-foot.png

Stairs (STAIRS: style -> its kit): the stone of the flights of stairs (docs/godot/ELEVATION.md
"Stairs", approved mockups in asset/Originals/elevation/stairs-mockups/). Each source holds rows of
cut stone; one row, crevice to crevice, is one step: a tread seen from above, or a riser (and a
railing's coping) seen from the front. The row is resampled to STEP_PX (one rise of 64 / 3 world
units at 2 px per unit), made opaque and horizontally periodic. Risers are baked RISER_TONE darker;
the coping is the riser row tinted halfway to the style's wall rock, COPING_LIGHT lighter. A
flight's railings and posts use the wall itself.
  -> <style>-stairs-tread.png, <style>-stairs-riser.png, <style>-stairs-coping.png

Usage: python scripts/art/build-elevation-art.py [name ...] [--preview DIR]
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/elevation/generated"
GROUND_SHEETS = ROOT / "godot/asset/MAPS/grounds"
OUT = ROOT / "godot/game/world/elevation/art"

## style -> (source file, number of courses the source was asked for)
WALLS = {
    "meadow-rock": ("wall-rock-a.png", 4),
}
## style -> per end ("right", "left"): (source file, courses asked for, source column of the crevice
## between the wall and its corner stones)
WALL_ENDS = {
    "meadow-rock": {
        "right": ("wall-corner-b.png", 4, 555),
        "left": ("wall-corner-left-a.png", 4, 320),
    },
}
## Wall end strip: px of art kept outside the wall's end line (the stones' rounded bulge).
WALL_END_OUTSIDE = 10
## style -> stairs kit: per part, (source file, first row, last row) of one step, crevice to crevice
STAIRS = {
    "meadow-rock": {
        "tread": ("stairs-tread-a.png", 394, 530),
        "riser": ("stairs-riser-b.png", 322, 471),
    },
}
## One step's row at game size: a rise of 64 / 3 world units at 2 px per unit.
STEP_PX = 43
RISER_TONE = 0.80
COPING_LIGHT = 1.10
## Source px cross-faded into the horizontal seam of a stairs row.
STAIRS_OVERLAP = 64
## ground -> its 64 px sheet stem, and per strip (source, edge row, fringe px on the ground side, scale)
STRIPS = {
    "highland": {
        "sheet": "HighlandGreen",
        "lip": ("highland-lip-b.png", 420, 95, 0.42),
        "foot": ("highland-foot-b.png", 418, 0, 0.34),
    },
    "frozen": {
        "sheet": "frozen",
        "lip": ("frozen-lip-b.png", 440, 70, 0.42),
        "foot": ("frozen-foot-a.png", 445, 0, 0.34),
    },
    "sanddessert": {
        "sheet": "sanddessert",
        "lip": ("sanddessert-lip-a.png", 418, 30, 0.42),
        "foot": ("sanddessert-foot-b.png", 330, 0, 0.45),
    },
    "forest-floor": {
        "sheet": "forest-floor",
        "lip": ("forest-floor-lip-b.png", 409, 80, 0.42),
        "foot": ("forest-floor-foot-b.png", 433, 0, 0.34),
    },
    "forest-moss": {
        "sheet": "forest-moss",
        "lip": ("forest-moss-lip-b.png", 445, 60, 0.42),
        "foot": ("forest-moss-foot-b.png", 415, 0, 0.34),
    },
    "amberleaf": {
        "sheet": "amberleaf",
        "lip": ("amberleaf-lip-a.png", 409, 60, 0.42),
        "foot": ("amberleaf-foot-a.png", 369, 0, 0.34),
    },
    "cavern-floor": {
        "sheet": "cavern-floor",
        "lip": ("cavern-floor-lip-b.png", 493, 50, 0.42),
        "foot": ("cavern-floor-foot-b.png", 431, 0, 0.34),
    },
    "crystal-floor": {
        "sheet": "crystal-floor",
        "lip": ("crystal-floor-lip-a.png", 429, 50, 0.42),
        "foot": ("crystal-floor-foot-b.png", 435, 0, 0.34),
    },
    "town-cobble": {
        "sheet": "town-cobble",
        "lip": ("town-cobble-lip-b.png", 473, 70, 0.42),
        "foot": ("town-cobble-foot-a.png", 441, 0, 0.34),
    },
}
## Art px per course (one level = 64 world units at 2 px per unit).
COURSE_PX = 128
## Strip px kept on the ground side and on the fringe side of the edge (a lip: above / below; a
## foot: below / above). The game reads the edge row from EDGE_ROWS (elevation.gd FRINGE_EDGE_ROW).
LAYOUT = {"lip": (96, 64), "foot": (48, 80)}
EDGE_ROWS = {"lip": 96, "foot": 80}
## Px over which the solid ground fades out on the strip's ground side.
FADE = 32
## Source columns blended across the horizontal wrap.
OVERLAP = 192
## Rows searched around each expected wall crevice.
JOINT_SEARCH = 48
## Generated "transparent" art keeps faint haze; below this alpha it is cleared.
HAZE_ALPHA = 0.06


def smoothstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


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

def find_joints(rgb: np.ndarray, courses: int) -> list[int]:
    """Rows of the dark crevices between courses (the darkest row near each expected one)."""
    lum = rgb.mean(axis=2).mean(axis=1)
    height = rgb.shape[0]
    joints = []
    for k in range(1, courses):
        expected = round(k * height / courses)
        lo, hi = max(0, expected - JOINT_SEARCH), min(height, expected + JOINT_SEARCH)
        joints.append(lo + int(np.argmin(lum[lo:hi])))
    return joints


def build_wall(style: str, preview: Path | None) -> None:
    source, courses = WALLS[style]
    rgb = np.asarray(Image.open(SRC / source).convert("RGB")).astype(np.float64)
    joints = find_joints(rgb, courses)
    spans = list(zip(joints, joints[1:]))
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


# --- strips --------------------------------------------------------------------------------

def load_rgba(path: Path) -> np.ndarray:
    """Straight RGBA in 0..1; generator haze cleared, the near-opaque ground made opaque."""
    a = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64) / 255.0
    alpha = a[..., 3]
    solid = np.percentile(alpha[alpha > 0.5], 90) if (alpha > 0.5).any() else 1.0
    alpha = np.clip(alpha / max(solid, 1e-6), 0.0, 1.0)
    alpha[alpha < HAZE_ALPHA] = 0.0
    a[..., 3] = alpha
    return a


def match_colour(rgba: np.ndarray, solid: np.ndarray, ref_rgb: np.ndarray) -> np.ndarray:
    """Moves the art's colour statistics (measured on its solid ground) onto the ground sheet's."""
    rgb = rgba[..., :3]
    src_mu, src_sd = rgb[solid].mean(0), rgb[solid].std(0)
    ref = ref_rgb.reshape(-1, 3)
    dst_mu, dst_sd = ref.mean(0), ref.std(0)
    gain = np.clip(dst_sd / np.maximum(src_sd, 1e-6), 0.7, 1.3)
    out = rgba.copy()
    out[..., :3] = np.clip((rgb - src_mu) * gain + dst_mu, 0.0, 1.0)
    return out


def build_strip(ground: str, kind: str, preview: Path | None) -> None:
    source, edge, inner, scale = STRIPS[ground][kind]
    rgba = load_rgba(SRC / source)
    if kind == "foot":
        # Work on it as a lip (ground above, fringe below), flip back at the end.
        rgba = rgba[::-1]
        edge = rgba.shape[0] - 1 - edge
    sheet = STRIPS[ground]["sheet"]
    ref = np.asarray(Image.open(GROUND_SHEETS / f"64x64-tile_19x19_{sheet}.webp").convert("RGB"), dtype=np.float64) / 255.0
    solid_mask = np.zeros(rgba.shape[:2], dtype=bool)
    solid_mask[: max(1, edge - inner - 8)] = True
    rgba = match_colour(rgba, solid_mask & (rgba[..., 3] > 0.99), ref)
    above, below = LAYOUT[kind]
    top = edge - round(above / scale)
    bottom = edge + round(below / scale)
    pad_top = max(0, -top)
    pad_bottom = max(0, bottom - rgba.shape[0])
    premul = rgba.copy()
    premul[..., :3] *= premul[..., 3:4]
    premul = np.pad(premul, ((pad_top, pad_bottom), (0, 0), (0, 0)), mode="edge")
    width = round(rgba.shape[1] * scale)
    strip = resize(premul[top + pad_top: bottom + pad_top], width, above + below)
    strip[..., 3] = np.clip(strip[..., 3], 0.0, 1.0)
    strip = periodic(strip, round(OVERLAP * scale))
    # The solid ground fades out beyond the fringe's ground side (the real ground shows there).
    rows = np.arange(above + below, dtype=np.float64)
    keep_from = above - round(inner * scale) - 4
    fade = smoothstep((rows - (keep_from - FADE)) / FADE)[:, None]
    strip *= fade[..., None]
    straight = strip.copy()
    straight[..., :3] = np.where(strip[..., 3:4] > 1e-6, strip[..., :3] / np.maximum(strip[..., 3:4], 1e-6), 0.0)
    if kind == "foot":
        straight = straight[::-1]
    out = Image.fromarray(np.clip(straight * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA")
    out.save(OUT / f"{ground}-{kind}.png", optimize=True)
    print(f"{kind} {ground}: {out.size[0]}x{out.size[1]} px, edge row {EDGE_ROWS[kind]}")
    if preview is not None:
        tiled_preview(out, preview / f"{ground}-{kind}-tiled.png", 3, 1)


def build_wall_ends(style: str, preview: Path | None) -> None:
    for side in ("right", "left"):
        build_wall_end(style, side, preview)


def build_wall_end(style: str, side: str, preview: Path | None) -> None:
    """The column of rounded corner stones where a wall ends on `side`: cut from the crevice beside
    the stones to just past their rounded bulge, its courses resampled to the wall's 128 px, its
    colours matched to the wall's, the end line (the mean edge of the stones) WALL_END_OUTSIDE px
    inside the art's outer side (its right for a right end, its left for a left end). Inside the
    end line the gaps between the rounded stones are filled with the corner's shadow, so no plain
    wall shows through. A left end is worked on mirrored, as a right end, and mirrored back."""
    source, courses, crevice = WALL_ENDS[style][side]
    rgba = np.asarray(Image.open(SRC / source).convert("RGBA")).astype(np.float64) / 255.0
    if side == "left":
        rgba = rgba[:, ::-1]
        crevice = rgba.shape[1] - 1 - crevice
    joints = find_joints(rgba[..., :3] * 255.0, courses)
    spans = list(zip(joints, joints[1:]))
    scale = float(np.mean([COURSE_PX / (bottom - top) for top, bottom in spans]))
    opaque = rgba[..., 3] > 0.5
    edges = [int(np.nonzero(row)[0].max()) for row in opaque if row.any()]
    edge = int(round(np.mean(edges)))
    right = edge + round(WALL_END_OUTSIDE / scale)
    width = round((right - crevice) * scale)
    wall = np.asarray(Image.open(OUT / f"{style}-wall.png").convert("RGB"), dtype=np.float64) / 255.0
    rgba = match_colour(rgba, rgba[..., 3] > 0.99, wall)
    premul = rgba.copy()
    premul[..., :3] *= premul[..., 3:4]
    rows = [resize(premul[top:bottom, crevice:right], width, COURSE_PX) for top, bottom in spans]
    strip = np.concatenate(rows, axis=0)
    strip[..., 3] = np.clip(strip[..., 3], 0.0, 1.0)
    end_line = width - WALL_END_OUTSIDE
    # Inside the end line: the corner's own shadow behind the gaps between stones.
    shadow = np.array([0.16, 0.12, 0.09])
    inside = np.zeros(strip.shape[:2], dtype=bool)
    inside[:, :end_line] = True
    gap = (1.0 - strip[..., 3])[..., None] * inside[..., None]
    strip[..., :3] += shadow * gap
    strip[..., 3:4] += gap
    # A short fade on the crevice side, where the wall's own texture takes over.
    fade = smoothstep(np.arange(width, dtype=np.float64) / 6.0)[None, :, None]
    strip *= fade
    straight = strip.copy()
    straight[..., :3] = np.where(strip[..., 3:4] > 1e-6, strip[..., :3] / np.maximum(strip[..., 3:4], 1e-6), 0.0)
    if side == "left":
        straight = straight[:, ::-1]
    out = Image.fromarray(np.clip(straight * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGBA")
    out.save(OUT / f"{style}-wall-end-{side}.png", optimize=True)
    print(f"wall end {style} {side}: crevices at {joints}, {out.size[0]}x{out.size[1]} px, end line {WALL_END_OUTSIDE} px from its outer side")
    if preview is not None:
        tiled_preview(out, preview / f"{style}-wall-end-{side}-tiled.png", 1, 3)


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


def build_stairs(style: str, preview: Path | None) -> None:
    kit = STAIRS[style]
    tread = stairs_row(*kit["tread"])
    riser = stairs_row(*kit["riser"])
    wall = np.asarray(Image.open(OUT / f"{style}-wall.png").convert("RGB")).astype(np.float64)
    tint = wall.reshape(-1, 3).mean(0) / riser.reshape(-1, 3).mean(0)
    coping = riser * (0.5 + 0.5 * tint)[None, None, :] * COPING_LIGHT
    for part, image in (("tread", tread), ("riser", riser * RISER_TONE), ("coping", coping)):
        out = save_rgb(image, OUT / f"{style}-stairs-{part}.png")
        print(f"stairs {style} {part}: {out.size[0]}x{out.size[1]} px")
        if preview is not None:
            tiled_preview(out, preview / f"{style}-stairs-{part}-tiled.png", 3, 3)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("names", nargs="*", help="wall styles and grounds to build (default: all)")
    parser.add_argument("--preview", type=Path, help="also write tiled previews here")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.preview is not None:
        args.preview.mkdir(parents=True, exist_ok=True)
    names = args.names or list(dict.fromkeys(list(WALLS) + list(STAIRS) + list(STRIPS)))
    for name in names:
        if name in WALLS:
            build_wall(name, args.preview)
        if name in WALL_ENDS:
            build_wall_ends(name, args.preview)
        if name in STAIRS:
            build_stairs(name, args.preview)
        if name in STRIPS:
            build_strip(name, "lip", args.preview)
            build_strip(name, "foot", args.preview)


if __name__ == "__main__":
    main()
