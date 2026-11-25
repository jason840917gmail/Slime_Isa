"""Cuts the Matron's web-ball generation (asset/Originals/gulp/generated/web-balls-raw.png, one 2:1
picture holding two takes side by side) into web-ball-a.png and web-ball-b.png, the sources of the
`web-ball` liftable (scripts/props/pack-gulp-art.py FIRST). The generation came with a see-through
haze round the right ball: only what stands well above it is kept (the largest solid island, its cut
closed and softened by a slight blur), as the packer does for grid-4.

Run: python scripts/art/split-web-balls.py
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / "asset" / "Originals" / "gulp" / "generated"
RAW = FOLDER / "web-balls-raw.png"
# Alpha above this is the ball (the haze stays well below it).
SOLID = 200
# Pixels a soft edge may reach past the solid cut.
EDGE_GROW = 3


def largest_island(mask: np.ndarray) -> np.ndarray:
    """The largest 4-connected island of `mask`, with every island at least a fifth its size."""
    from collections import deque
    height, width = mask.shape
    seen = np.zeros_like(mask)
    islands: list[list[tuple[int, int]]] = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        island = []
        queue = deque([(y0, x0)])
        seen[y0, x0] = True
        while queue:
            y, x = queue.popleft()
            island.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        islands.append(island)
    out = np.zeros_like(mask)
    if not islands:
        return out
    biggest = max(len(i) for i in islands)
    for island in islands:
        if len(island) * 5 >= biggest:
            ys, xs = zip(*island)
            out[list(ys), list(xs)] = True
    return out


def clean(half: Image.Image) -> Image.Image:
    pixels = np.asarray(half).copy()
    alpha = pixels[..., 3]
    keep = largest_island(alpha > SOLID)
    mask = Image.fromarray(np.where(keep, 255, 0).astype(np.uint8), "L")
    mask = mask.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    grown = mask.filter(ImageFilter.MaxFilter(EDGE_GROW * 2 + 1))
    # Inside the solid cut the ball keeps its own alpha raised to full; the thin rim just outside it
    # keeps the generation's own soft edge (never the haze further out).
    soft = np.where(np.asarray(grown) > 0, alpha, 0).astype(np.float32)
    solid = np.asarray(mask.filter(ImageFilter.GaussianBlur(0.7)), dtype=np.float32)
    rim = np.where(soft > SOLID * 0.6, soft, 0.0)
    pixels[..., 3] = np.clip(np.maximum(solid, rim), 0, 255).astype(np.uint8)
    image = Image.fromarray(pixels, "RGBA")
    return image.crop(image.getchannel("A").getbbox())


def main() -> None:
    raw = Image.open(RAW).convert("RGBA")
    width = raw.width // 2
    for index, name in enumerate(("web-ball-a", "web-ball-b")):
        half = raw.crop((index * width, 0, (index + 1) * width, raw.height))
        out = clean(half)
        out.save(FOLDER / f"{name}.png")
        print(f"wrote {name}.png {out.size}")


if __name__ == "__main__":
    main()
