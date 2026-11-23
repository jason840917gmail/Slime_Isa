#!/usr/bin/env python3
"""Packs Gloop Forest's River Roads set pieces (docs/design/2026-11-21-gloop-river-roads.md).

Sources: asset/Originals/props/gloop-river-roads/<name>.png (Magnific GPT 2.5, transparent, the
mushroom furniture sheet as style reference; the north-south footbridge also took the east-west
footbridge as reference). Each is cropped to its painted pixels and sized for 2 px per world unit
(sprites draw at scale 0.5), then written to godot/asset/MAPS/props/gloop-river-roads/<name>.webp.

Usage: python scripts/art/pack-gloop-river-roads.py   (Pillow)
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset/Originals/props/gloop-river-roads"
OUT = ROOT / "godot/asset/MAPS/props/gloop-river-roads"
## Alpha below this counts as empty when cropping (the generator leaves faint haze at the edges).
ALPHA_CUT = 24

## name: (target height in world units, or None) / (target width in world units, or None).
PIECES = {
    "footbridge-north-south": {"height": 300},
    "raft": {"width": 150},
    "hollow-log": {"height": 300},
    "beaver-dam": {"width": 400},
    "lookout-tree": {"height": 480, "islands": True},
}


def drop_islands(image: Image.Image) -> Image.Image:
    """Clears the specks the generator scatters round a piece: every painted blob but the biggest
    (found on a quarter-size mask, then cleared at full size)."""
    small = image.getchannel("A").resize((image.width // 4, image.height // 4), Image.NEAREST)
    w, h = small.size
    solid = [a >= ALPHA_CUT for a in small.getdata()]
    label = [0] * (w * h)
    sizes = {}
    current = 0
    for start in range(w * h):
        if not solid[start] or label[start]:
            continue
        current += 1
        stack = [start]
        label[start] = current
        count = 0
        while stack:
            i = stack.pop()
            count += 1
            x, y = i % w, i // w
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    j = ny * w + nx
                    if solid[j] and not label[j]:
                        label[j] = current
                        stack.append(j)
        sizes[current] = count
    if not sizes:
        return image
    keep = max(sizes, key=sizes.get)
    mask = Image.new("L", (w, h))
    mask.putdata([255 if label[i] == keep else 0 for i in range(w * h)])
    # grown a little so the blob's soft edge survives the quarter-size mask
    from PIL import ImageFilter
    mask = mask.filter(ImageFilter.MaxFilter(5)).resize(image.size, Image.BILINEAR)
    alpha = Image.composite(image.getchannel("A"), Image.new("L", image.size, 0), mask)
    out = image.copy()
    out.putalpha(alpha)
    return out


def crop(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A").point(lambda a: 255 if a >= ALPHA_CUT else 0)
    box = alpha.getbbox()
    return image.crop(box) if box else image


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, size in PIECES.items():
        image = Image.open(SRC / f"{name}.png").convert("RGBA")
        if size.get("islands"):
            image = drop_islands(image)
        image = crop(image)
        if "height" in size:
            h = size["height"] * 2
            w = round(image.width * h / image.height)
        else:
            w = size["width"] * 2
            h = round(image.height * w / image.width)
        image = image.resize((w, h), Image.LANCZOS)
        path = OUT / f"{name}.webp"
        image.save(path, lossless=True, method=6)
        print(f"{path.relative_to(ROOT)}: {w} x {h} px ({w // 2} x {h // 2} units)")


if __name__ == "__main__":
    main()
