"""Pack the pond and deep-water wildlife sheets from the generated sources.

Sources: asset/Originals/water/generated/*.png (Magnific, plain white
background; the white is flood-filled away from the border, so white petals
inside dark outlines survive). Every sheet uses 8-frame loops per row:

  128x64-tile_8x5-water-fish.webp     rows 0-3 koi, carp, minnow, perch (tail
                                      wiggle); row 4 the big dark deep-water
                                      fish shadow
  128x128-tile_8x1-water-frog.webp    frog on a lily pad: idle, blink, croak
                                      (frames 0-2; the clip decides the timing)
  128x128-tile_8x4-water-lilypads.webp  four lily pad clusters, gentle bob
  128x128-tile_8x4-water-reeds.webp     four shore plants, sway from the base
  128x128-tile_8x5-water-plants.webp    rows 0-1 shallow waterweed, rows 2-3
                                      deep kelp (sway from the root), row 4
                                      rising bubbles (procedural)

  python scripts/art/build-water-life-sheets.py
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from game_webp import save_game_webp  # noqa: E402

SOURCES = ROOT / "asset" / "Originals" / "water" / "generated"
OUT = ROOT / "asset" / "MAPS" / "water"
STEPS = 8


def cut_out(path, holes=False):
    """RGBA with the border-connected near-white background removed. `holes`
    also clears enclosed near-white pockets (for art with no intended white)."""
    rgb = np.array(Image.open(path).convert("RGB")).astype(np.int32)
    h, w = rgb.shape[:2]
    whiteness = rgb.min(axis=2)
    candidate = whiteness > 228
    background = np.zeros((h, w), bool)
    stack = [(y, x) for x in range(w) for y in (0, h - 1)] + [(y, x) for y in range(h) for x in (0, w - 1)]
    while stack:
        y, x = stack.pop()
        if background[y, x] or not candidate[y, x]:
            continue
        background[y, x] = True
        if y > 0: stack.append((y - 1, x))
        if y < h - 1: stack.append((y + 1, x))
        if x > 0: stack.append((y, x - 1))
        if x < w - 1: stack.append((y, x + 1))
    if holes:
        background |= whiteness > 236
    alpha = np.where(background, 0, 255).astype(np.float64)
    # Soften the anti-aliased rim: pixels next to the background fade by whiteness.
    near = np.zeros_like(background)
    near[1:] |= background[:-1]; near[:-1] |= background[1:]; near[:, 1:] |= background[:, :-1]; near[:, :-1] |= background[:, 1:]
    rim = near & ~background
    alpha[rim] = np.clip((255 - whiteness[rim]) * 255 / 60, 0, 255)
    out = np.dstack([rgb, alpha]).astype(np.uint8)
    return out


def quadrants(image):
    h, w = image.shape[:2]
    return [image[:h // 2, :w // 2], image[:h // 2, w // 2:], image[h // 2:, :w // 2], image[h // 2:, w // 2:]]


def trim(image):
    ys, xs = np.nonzero(image[..., 3] > 8)
    return image[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def fit(image, width, height, anchor="center", fill=0.92):
    """Scale a trimmed RGBA into a width x height cell (bottom-anchored or centered)."""
    image = trim(image)
    h, w = image.shape[:2]
    scale = min(width * fill / w, height * fill / h)
    size = (max(1, round(w * scale)), max(1, round(h * scale)))
    resized = np.array(Image.fromarray(image, "RGBA").resize(size, Image.LANCZOS))
    cell = np.zeros((height, width, 4), np.uint8)
    x = (width - size[0]) // 2
    y = (height - size[1]) // 2 if anchor == "center" else height - size[1] - 1
    cell[y:y + size[1], x:x + size[0]] = resized
    return cell


def premultiplied(cell):
    rgba = cell.astype(np.float64)
    return np.concatenate([rgba[..., :3] * rgba[..., 3:4] / 255, rgba[..., 3:4]], -1)


def unpremultiplied(p):
    a = p[..., 3:4]
    rgb = np.where(a > 0, p[..., :3] * 255 / np.maximum(a, 1e-6), 0)
    return np.clip(np.concatenate([rgb, a], -1), 0, 255).astype(np.uint8)


def wiggle(cell, amplitude, speed=1.0):
    """Fish tail wiggle: columns shift vertically, growing toward the tail (left)."""
    p = premultiplied(cell)
    h, w = cell.shape[:2]
    xs = np.nonzero((cell[..., 3] > 8).any(axis=0))[0]
    head, tail = xs.max(), xs.min()
    rows = np.arange(h, dtype=np.float64)
    frames = []
    for step in range(STEPS):
        phase = 2 * math.pi * step / STEPS * speed
        out = np.zeros_like(p)
        for x in range(w):
            t = np.clip((head - x) / max(1, head - tail), 0, 1)
            shift = amplitude * t ** 1.8 * math.sin(phase - t * 3.2)
            for c in range(4):
                out[:, x, c] = np.interp(rows - shift, rows, p[:, x, c], left=0, right=0)
        frames.append(unpremultiplied(out))
    return frames


def sway(cell, amplitude, hinge_share=0.1):
    """Plant sway: rows shift sideways, 0 at the root (bottom) growing to the tip."""
    p = premultiplied(cell)
    h, w = cell.shape[:2]
    ys = np.nonzero((cell[..., 3] > 8).any(axis=1))[0]
    top, bottom = ys.min(), ys.max()
    hinge = bottom - int((bottom - top) * hinge_share)
    cols = np.arange(w, dtype=np.float64)
    frames = []
    for step in range(STEPS):
        phase = 2 * math.pi * step / STEPS
        out = p.copy()
        for y in range(top, hinge):
            weight = ((hinge - y) / max(1, hinge - top)) ** 1.5
            shift = amplitude * weight * (math.sin(phase) + 0.3 * math.sin(2 * phase + y * 0.15))
            for c in range(4):
                out[y, :, c] = np.interp(cols - shift, cols, p[y, :, c], left=0, right=0)
        frames.append(unpremultiplied(out))
    return frames


def bob(cell, amplitude=1.2):
    """Floating bob: the whole cell drifts up and down a pixel and breathes slightly."""
    p = premultiplied(cell)
    h, w = cell.shape[:2]
    frames = []
    for step in range(STEPS):
        phase = 2 * math.pi * step / STEPS
        dy = amplitude * math.sin(phase)
        dx = amplitude * 0.6 * math.sin(phase + 1.3)
        img = Image.fromarray(unpremultiplied(p), "RGBA")
        moved = img.transform((w, h), Image.AFFINE, (1, 0, -dx, 0, 1, -dy), resample=Image.BICUBIC)
        frames.append(np.array(moved))
    return frames


def shadow(cell):
    """A big dark silhouette for the deep-water fish, softly blurred."""
    alpha = Image.fromarray(cell[..., 3]).filter(ImageFilter.GaussianBlur(1.6))
    a = np.array(alpha).astype(np.float64) * 0.78
    out = np.zeros_like(cell)
    out[..., 0], out[..., 1], out[..., 2] = 4, 10, 20
    out[..., 3] = np.clip(a, 0, 255).astype(np.uint8)
    return out


def bubbles():
    frames = []
    rng = np.random.default_rng(7)
    columns = [(64 + rng.uniform(-18, 18), rng.uniform(0, 1), rng.uniform(2.2, 4.2)) for _ in range(5)]
    for step in range(STEPS):
        img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        px = img.load()
        for bx, offset, radius in columns:
            t = (step / STEPS + offset) % 1.0
            cy = 118 - t * 100
            cx = bx + 3 * math.sin(t * 9 + offset * 6)
            r = radius * (0.7 + 0.5 * t)
            fade = min(1.0, (1 - t) * 3) * min(1.0, t * 6)
            for y in range(int(cy - r - 1), int(cy + r + 2)):
                for x in range(int(cx - r - 1), int(cx + r + 2)):
                    if not (0 <= x < 128 and 0 <= y < 128):
                        continue
                    d = math.hypot(x - cx, y - cy)
                    if d > r + 0.5:
                        continue
                    edge = max(0.0, min(1.0, r + 0.5 - d))
                    rim = 0.55 if d > r - 1.2 else 0.18
                    highlight = 1.0 if math.hypot(x - (cx - r * 0.35), y - (cy - r * 0.35)) < r * 0.3 else 0.0
                    a = (rim + highlight * 0.6) * edge * fade
                    px[x, y] = (225, 245, 255, int(255 * min(1.0, a)))
        frames.append(np.array(img))
    return frames


def sheet(rows, cell_w, cell_h):
    atlas = np.zeros((len(rows) * cell_h, STEPS * cell_w, 4), np.uint8)
    for r, frames in enumerate(rows):
        for i, frame in enumerate(frames):
            atlas[r * cell_h:(r + 1) * cell_h, i * cell_w:(i + 1) * cell_w] = frame
    return atlas


def save(atlas, name):
    OUT.mkdir(parents=True, exist_ok=True)
    save_game_webp(Image.fromarray(atlas, "RGBA"), OUT / name)
    print(f"{name}: {atlas.shape[1]}x{atlas.shape[0]}")


def main():
    fish = [fit(q, 128, 64, fill=0.86) for q in quadrants(cut_out(SOURCES / "fish.png"))]
    big = fit(quadrants(cut_out(SOURCES / "fish.png"))[1], 128, 64, fill=0.98)
    save(sheet([wiggle(f, 2.6) for f in fish] + [wiggle(shadow(big), 3.2)], 128, 64), "128x64-tile_8x5-water-fish.webp")

    frog = [fit(cut_out(SOURCES / name), 128, 128, anchor="bottom", fill=0.9) for name in ("frog.png", "frog-blink.png", "frog-croak.png")]
    blank = np.zeros_like(frog[0])
    save(sheet([frog + [blank] * (STEPS - 3)], 128, 128), "128x128-tile_8x1-water-frog.webp")

    pads = [fit(q, 128, 128, fill=0.86) for q in quadrants(cut_out(SOURCES / "lilypads.png"))]
    save(sheet([bob(p) for p in pads], 128, 128), "128x128-tile_8x4-water-lilypads.webp")

    reeds = [fit(q, 128, 128, anchor="bottom", fill=0.94) for q in quadrants(cut_out(SOURCES / "reeds.png", holes=True))]
    save(sheet([sway(r, 2.6) for r in reeds], 128, 128), "128x128-tile_8x4-water-reeds.webp")

    plants = [fit(q, 128, 128, anchor="bottom", fill=0.92) for q in quadrants(cut_out(SOURCES / "underwater.png", holes=True))]
    save(sheet([sway(p, 3.4, hinge_share=0.05) for p in plants] + [bubbles()], 128, 128), "128x128-tile_8x5-water-plants.webp")


if __name__ == "__main__":
    main()
