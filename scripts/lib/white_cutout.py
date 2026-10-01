"""Cuts generated art out of a plain white background.

Magnific's gpt-2 cannot return transparent images (2026-09-30), so sprites are
generated on "a plain flat pure white background" and cut out here: a flood
fill from the border removes the near-white background without touching
white details enclosed by dark outlines, and the anti-aliased rim fades by its
whiteness. Same rule as `cut_out` in scripts/art/build-water-life-sheets.py.
"""
from pathlib import Path

import numpy as np
from PIL import Image


def cut_out(path: str | Path, holes: bool = False) -> Image.Image:
    """RGBA with the border-connected near-white background removed. `holes`
    also clears enclosed near-white pockets (for art with no intended white)."""
    rgb = np.array(Image.open(path).convert('RGB')).astype(np.int32)
    height, width = rgb.shape[:2]
    whiteness = rgb.min(axis=2)
    candidate = whiteness > 228
    background = np.zeros((height, width), bool)
    stack = [(y, x) for x in range(width) for y in (0, height - 1)] + [(y, x) for y in range(height) for x in (0, width - 1)]
    while stack:
        y, x = stack.pop()
        if background[y, x] or not candidate[y, x]:
            continue
        background[y, x] = True
        if y > 0:
            stack.append((y - 1, x))
        if y < height - 1:
            stack.append((y + 1, x))
        if x > 0:
            stack.append((y, x - 1))
        if x < width - 1:
            stack.append((y, x + 1))
    if holes:
        background |= whiteness > 236
    alpha = np.where(background, 0, 255).astype(np.float64)
    near = np.zeros_like(background)
    near[1:] |= background[:-1]
    near[:-1] |= background[1:]
    near[:, 1:] |= background[:, :-1]
    near[:, :-1] |= background[:, 1:]
    rim = near & ~background
    alpha[rim] = np.clip((255 - whiteness[rim]) * 255 / 60, 0, 255)
    return Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), 'RGBA')


def fit(image: Image.Image, frame: int, fill: float = 0.92, anchor: str = 'center') -> Image.Image:
    """`image` trimmed and scaled into a `frame`-sized square (`anchor` 'bottom' sits it on the bottom edge)."""
    art = image.crop(image.getbbox())
    scale = frame * fill / max(art.size)
    art = art.resize((max(1, round(art.width * scale)), max(1, round(art.height * scale))), Image.LANCZOS)
    out = Image.new('RGBA', (frame, frame), (0, 0, 0, 0))
    y = frame - art.height - max(1, round(frame * 0.02)) if anchor == 'bottom' else (frame - art.height) // 2
    out.paste(art, ((frame - art.width) // 2, y))
    return out
