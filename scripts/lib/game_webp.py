"""Saves runtime images as WebP: small, with transparency kept exactly.

Every packed image under asset/ (not asset/Originals) ships as WebP. Colour is
lossy (quality 90) when that keeps the visible pixels at MIN_PSNR_DB or better;
small outlined icon sheets that fall below it (items, weapon icons, arrows) are
saved lossless instead. Transparency is always stored
lossless, and every save is decoded again to check the alpha channel is
identical. Phaser premultiplies alpha on upload, so the colour under fully
transparent pixels never shows and the encoder may drop it.

Use from a tool in scripts/<family>/:

    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
    from game_webp import save_game_webp
    save_game_webp(image, path)  # path ends in .webp
"""
from __future__ import annotations

import io
import math
from pathlib import Path

import numpy as np
from PIL import Image

QUALITY = 90
# Below this the lossy colour shift shows on small outlined icons (gems, keys,
# weapon icons) at close zoom; above it the difference is not visible in play.
MIN_PSNR_DB = 26.0


def _has_alpha(image: Image.Image) -> bool:
    return image.mode in ('RGBA', 'LA') or (image.mode == 'P' and 'transparency' in image.info)


def _visible_psnr(source: np.ndarray, decoded: np.ndarray, alpha: bool) -> float:
    if alpha:
        weight = source[..., 3:4] / 255.0
        error = float((((source[..., :3] - decoded[..., :3]) ** 2) * weight).sum()) / max(float(weight.sum()) * 3, 1.0)
    else:
        error = float(((source - decoded) ** 2).mean())
    return math.inf if error == 0 else 10 * math.log10(255 ** 2 / error)


def encode_game_webp(image: Image.Image) -> tuple[bytes, str, float]:
    """Returns (bytes, 'lossy' | 'lossless', visible PSNR of the lossy trial)."""
    alpha = _has_alpha(image)
    image = image.convert('RGBA' if alpha else 'RGB')
    source = np.asarray(image).astype(np.float64)
    lossy = io.BytesIO()
    image.save(lossy, 'WEBP', quality=QUALITY, alpha_quality=100, method=6)
    decoded = np.asarray(Image.open(io.BytesIO(lossy.getvalue())).convert(image.mode)).astype(np.float64)
    psnr = _visible_psnr(source, decoded, alpha)
    if psnr >= MIN_PSNR_DB and (not alpha or np.array_equal(source[..., 3], decoded[..., 3])):
        return lossy.getvalue(), 'lossy', psnr
    lossless = io.BytesIO()
    image.save(lossless, 'WEBP', lossless=True, quality=100, method=6)
    return lossless.getvalue(), 'lossless', psnr


def save_game_webp(image: Image.Image, path: str | Path) -> str:
    """Writes `image` to `path` (.webp) and returns 'lossy' or 'lossless'."""
    path = Path(path)
    if path.suffix.lower() != '.webp':
        raise ValueError(f'{path} must end in .webp')
    data, kind, _ = encode_game_webp(image)
    if _has_alpha(image):
        written = np.asarray(Image.open(io.BytesIO(data)).convert('RGBA'))[..., 3]
        if not np.array_equal(np.asarray(image.convert('RGBA'))[..., 3], written):
            raise RuntimeError(f'{path}: transparency changed in the WebP encode')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return kind
