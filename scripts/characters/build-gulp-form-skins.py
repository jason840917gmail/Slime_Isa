"""Builds the slime's Gulp form skins from the player sheet (roadmap 7.x).

Each form gets its own full player sheet with the exact frame layout of
`characters/slime_normalized` (8x8 frames of 256 px), so the game swaps the
texture and every animation keeps working (`WorldVisual.setSkin`):

- Heavy: the green goo becomes a mosaic of grey river pebbles.
- Sticky: the green goo becomes wound spider silk.

Only the green body changes. The dark outline, the eyes, the mouth and the
white highlights stay as painted, and the body keeps its original shading
(the texture is multiplied by the goo's brightness). Textures are painted
tiles (Magnific GPT-2) mapped once per frame, so they never seam inside one.

Sources: asset/Originals/characters/slime_normalized.png (the lossless player
sheet) and asset/Originals/characters/gulp-forms/{stone,silk}-texture.png.
Output: godot/asset/characters/slime-form-{heavy,sticky}.webp.

Usage: python scripts/characters/build-gulp-form-skins.py
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from game_webp import save_game_webp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ORIGINALS = ROOT / 'asset' / 'Originals' / 'characters'
FRAME = 256

# (form, texture, texture tile size within a frame, shading floor, shading range, body blend)
FORMS = [
    ('heavy', 'stone-texture.png', 256, 0.42, 0.85, 1.0),
    ('sticky', 'silk-texture.png', 192, 0.62, 0.55, 0.92),
]


def hsv(rgb: np.ndarray):
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    delta = mx - mn + 1e-6
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hue = np.where(mx == r, ((g - b) / delta) % 6, np.where(mx == g, (b - r) / delta + 2, (r - g) / delta + 4)) * 60
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    return hue, sat, mx


def body_weight(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """How much of each pixel is green goo (1) rather than outline, eyes, mouth or highlight (0)."""
    hue, sat, val = hsv(rgb)
    distance = np.abs(((hue - 105) + 180) % 360 - 180)
    by_hue = np.clip(1 - (distance - 45) / 25, 0, 1)
    by_sat = np.clip((sat - 0.12) / 0.15, 0, 1)
    by_val = np.clip((val - 0.18) / 0.12, 0, 1)
    return by_hue * by_sat * by_val * (alpha > 0)


def tiled(texture: Image.Image, tile: int, size: tuple[int, int]) -> np.ndarray:
    """The texture repeated from each frame's own origin, so it never seams inside a frame."""
    tile_rgb = np.asarray(texture.convert('RGB').resize((tile, tile), Image.LANCZOS)).astype(np.float32) / 255
    reps = (FRAME + tile - 1) // tile
    frame = np.tile(tile_rgb, (reps, reps, 1))[:FRAME, :FRAME]
    rows, cols = size[1] // FRAME, size[0] // FRAME
    return np.tile(frame, (rows, cols, 1))


def main() -> None:
    sheet = Image.open(ORIGINALS / 'slime_normalized.png').convert('RGBA')
    pixels = np.asarray(sheet).astype(np.float32) / 255
    rgb, alpha = pixels[..., :3], pixels[..., 3]
    weight = body_weight(rgb, alpha)[..., None]
    shading = rgb.max(-1, keepdims=True)
    for form, texture_name, tile, floor, span, blend in FORMS:
        texture = tiled(Image.open(ORIGINALS / 'gulp-forms' / texture_name), tile, sheet.size)
        material = np.clip(texture * (floor + span * shading), 0, 1)
        out_rgb = rgb * (1 - weight * blend) + material * weight * blend
        out = np.concatenate([out_rgb, alpha[..., None]], axis=-1)
        image = Image.fromarray(np.round(out * 255).astype(np.uint8), 'RGBA')
        target = ROOT / 'godot' / 'asset' / 'characters' / f'slime-form-{form}.webp'
        kind = save_game_webp(image, target)
        print(f'wrote {target.relative_to(ROOT)} ({kind})')


if __name__ == '__main__':
    main()
