"""Build the looping ambient sheets for animated decorations (campfire, cauldron,
lantern post, village banner, stone birdbath) from the static decoration sheet.

Two sources:
- video: frames pulled from a Magnific image-to-video loop rendered on #FF00FF
  (asset/Originals/decorations/ambient/<name>/<i>.jpg, 1440px, the 128px sprite
  was drawn 6x at (128,128) in a 1024 key image). Only the moving fire/bubble
  pixels are taken from the video; everything else stays the original sprite.
- procedural: frames derived from the original sprite itself (flame flicker,
  cloth wave, water shimmer), so no generation noise reaches the game.

Output: godot/asset/MAPS/decorations/128x128-tile_8x5-decorations-ambient.webp, one row
of 8 frames per object in ROWS order. Needs Pillow + numpy.
  python scripts/art/build-ambient-decoration-sheets.py
"""
import math
import os
import numpy as np
from PIL import Image
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from game_webp import save_game_webp  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SHEET = os.path.join(ROOT, "godot", "asset", "MAPS", "decorations", "128x128-tile_8x3.webp")
ORIGINALS = os.path.join(ROOT, "asset", "Originals", "decorations", "ambient")
OUT = os.path.join(ROOT, "godot", "asset", "MAPS", "decorations", "128x128-tile_8x5-decorations-ambient.webp")
CELL, FRAMES = 128, 8

# (name, source frame in the 8x3 decoration sheet, builder)
ROWS = [("campfire", 8, "fire"), ("cooking-cauldron", 7, "bubbles"), ("lantern-post", 6, "lantern"),
        ("village-banner", 13, "banner"), ("stone-birdbath", 15, "water")]


def source_cell(frame):
    sheet = Image.open(SHEET).convert("RGBA")
    x, y = (frame % 8) * CELL, (frame // 8) * CELL
    return np.array(sheet.crop((x, y, x + CELL, y + CELL))).astype(np.float64)


def video_cell(name, index):
    im = Image.open(os.path.join(ORIGINALS, name, f"{index}.jpg")).convert("RGB")
    im = im.resize((1024, 1024), Image.LANCZOS).crop((128, 128, 896, 896)).resize((CELL, CELL), Image.LANCZOS)
    return np.array(im).astype(np.float64)


def fire_mask(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return (r > 170) & (g > 70) & (r - b > 90) & (g - b > 20)


def fire_frames(name, frame, region=None):
    """Original sprite with its flames replaced by the video's flames."""
    orig = source_cell(frame)
    old_fire = fire_mask(orig[..., :3]) & (orig[..., 3] > 0)
    frames = []
    for i in range(FRAMES):
        v = video_cell(name, i)
        new_fire = fire_mask(v)
        if region is not None:
            new_fire &= region
        out = orig.copy()
        # Where the old flame was and the new one is not, show the video's own
        # (keyed) pixels: logs/pot behind the flame or transparency.
        r, g, b = v[..., 0], v[..., 1], v[..., 2]
        video_bg = ((r - g > 45) & (b - g > 45)) | (b - g > 25)
        gone = old_fire & ~new_fire
        out[gone, :3] = v[gone]
        out[gone, 3] = np.where(video_bg[gone], 0, 255)
        out[new_fire, :3] = v[new_fire]
        out[new_fire, 3] = 255
        frames.append(out)
    return frames


def add_bubbles(frames, frame):
    """Small stew bubbles that swell and pop at fixed spots on the pot surface."""
    orig = source_cell(frame)
    rgb = orig[..., :3]
    stew = (orig[..., 3] > 0) & (rgb.mean(axis=2) > 120) & (np.abs(rgb[..., 0] - rgb[..., 2]) < 70) & (rgb[..., 0] > rgb[..., 2])
    ys, xs = np.nonzero(stew)
    cy, cx = ys.mean(), xs.mean()
    spots = [(-1.5, -6, 0), (1.0, 4, 3), (0.0, -1, 5), (-1.0, 7, 6)]  # dy, dx, start frame
    yy, xx = np.mgrid[0:CELL, 0:CELL].astype(np.float64)
    for index, out in enumerate(frames):
        for dy, dx, start in spots:
            age = (index - start) % FRAMES
            if age > 2:
                continue
            radius = [1.0, 1.7, 1.2][age]
            d = np.hypot(yy - (cy + dy), xx - (cx + dx))
            ring = (d <= radius + 0.5) & stew
            shade = 0.82 if age < 2 else 1.1  # dark rim, then a bright pop
            out[ring, :3] = np.clip(out[ring, :3] * shade, 0, 255)
            hi = (np.hypot(yy - (cy + dy - 0.7), xx - (cx + dx - 0.7)) < 0.8) & ring
            out[hi, :3] = np.minimum(255, out[hi, :3] + 60)
    return frames


def lantern_frames(frame):
    """Flicker: brighten/dim the glowing lantern panes."""
    orig = source_cell(frame)
    rgb = orig[..., :3]
    lum = rgb.mean(axis=2)
    glow = (orig[..., 3] > 0) & (rgb[..., 0] > 150) & (rgb[..., 1] > 110) & (rgb[..., 0] - rgb[..., 2] > 50)
    weight = np.clip((lum - 110) / 120, 0, 1) * glow
    levels = [1.0, 0.86, 1.08, 0.94, 0.8, 1.05, 0.9, 1.12]
    frames = []
    for level in levels:
        out = orig.copy()
        factor = 1 + (level - 1) * weight
        out[..., :3] = np.clip(rgb * factor[..., None], 0, 255)
        frames.append(out)
    return frames


def dilate(mask, radius):
    out = mask.copy()
    for _ in range(radius):
        grown = out.copy()
        grown[1:] |= out[:-1]
        grown[:-1] |= out[1:]
        grown[:, 1:] |= out[:, :-1]
        grown[:, :-1] |= out[:, 1:]
        out = grown
    return out


def banner_frames(frame):
    """Cloth wave on a fixed stand: only the cloth and its gold trim move, along
    a travelling sine that grows toward the hanging point; the pole, crossbar and
    base are the original pixels in every frame."""
    orig = source_cell(frame)
    rgb, alpha = orig[..., :3], orig[..., 3] > 0
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    blue = alpha & (b > r + 10) & (b > g)
    gold = alpha & (r > 110) & (g > 80) & (b < 110) & (r > b + 40)
    ys, xs = np.nonzero(blue)
    top, bottom = ys.min(), ys.max()
    cloth = dilate(blue, 3) & (blue | gold)
    cloth[:top] = False  # the crossbar above the cloth never moves

    # Pole revealed behind the cloth: rebuild it from the pole just under the
    # cloth, where it is visible (same columns, repeated upward).
    below = min(CELL - 1, bottom + 4)
    pole_cols = [x for x in range(CELL) if alpha[below, x] and not cloth[below, x]]
    behind = np.zeros_like(orig)
    for y in range(top, bottom + 1):
        for x in pole_cols:
            behind[y, x] = orig[below, x]

    static = orig.copy()
    static[cloth] = behind[cloth]
    layer = np.where(cloth[..., None], orig, 0.0)
    premult = np.concatenate([layer[..., :3] * layer[..., 3:4] / 255, layer[..., 3:4]], axis=-1)
    cols = np.arange(CELL, dtype=np.float64)
    frames = []
    for i in range(FRAMES):
        phase = 2 * math.pi * i / FRAMES
        moved = np.zeros_like(premult)
        for y in range(top, bottom + 1):
            depth = (y - top) / max(1, bottom - top)
            shift = 2.0 * depth * math.sin(phase - depth * 3.0)
            for c in range(4):
                moved[y, :, c] = np.interp(cols - shift, cols, premult[y, :, c], left=0, right=0)
        a = moved[..., 3:4] / 255
        sa = static[..., 3:4] / 255
        out_a = a + sa * (1 - a)
        out = static.copy()
        out[..., :3] = (moved[..., :3] + static[..., :3] * sa * (1 - a)) / np.maximum(out_a, 1e-6)
        out[..., 3] = np.where(out_a[..., 0] > 0.5, 255, 0)
        frames.append(out)
    return frames


def water_frames(frame):
    """Shimmer: a soft highlight band sweeps across the water surface."""
    orig = source_cell(frame)
    rgb = orig[..., :3]
    water = (orig[..., 3] > 0) & (rgb[..., 2] > rgb[..., 0] + 8) & (rgb.mean(axis=2) > 120)
    yy, xx = np.mgrid[0:CELL, 0:CELL].astype(np.float64)
    frames = []
    for i in range(FRAMES):
        phase = 2 * math.pi * i / FRAMES
        wave = 0.5 + 0.5 * np.sin(xx * 0.45 + yy * 0.25 - phase)
        out = orig.copy()
        boost = (wave * 0.16 - 0.05) * water
        out[..., :3] = np.clip(rgb * (1 + boost[..., None]) + 18 * boost[..., None], 0, 255)
        frames.append(out)
    return frames


def _load_despill():
    import importlib.util
    path = os.path.join(os.path.dirname(__file__), "despill-magenta-fringe.py")
    spec = importlib.util.spec_from_file_location("despill_magenta_fringe", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    rows = []
    for name, frame, kind in ROWS:
        if kind == "fire":
            frames = fire_frames(name, frame)
        elif kind == "bubbles":
            # Only the pot mouth and the small fire under it animate.
            region = np.zeros((CELL, CELL), bool)
            region[55:115, 25:105] = True
            frames = add_bubbles(fire_frames(name, frame, region), frame)
        elif kind == "lantern":
            frames = lantern_frames(frame)
        elif kind == "banner":
            frames = banner_frames(frame)
        else:
            frames = water_frames(frame)
        rows.append(np.concatenate(frames, axis=1))
        print(f"{name}: {len(frames)} frames")
    sheet = np.concatenate(rows, axis=0).astype(np.uint8)
    # Smoke and embers that blended with the #FF00FF video background come out
    # pink; repaint them from their neighbours like any chroma-key fringe.
    despill = _load_despill()
    despill.MIN_BLUE_OVER_GREEN = 18
    sheet, _ = despill.fix(sheet, 6, everywhere=True)
    save_game_webp(Image.fromarray(sheet, "RGBA"), OUT)
    print(OUT)


if __name__ == "__main__":
    main()
