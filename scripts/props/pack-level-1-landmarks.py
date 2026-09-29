"""Pack the Magnific GPT-2 level-1 landmark props into one 320x256 sprite sheet.

Sources live in asset/Originals/props/level-1/ (transparent generations). Each
prop is trimmed, scaled to its target width (never upscaled) and bottom-centre
anchored with a small margin, matching the render origin [0.5, 1] used by the
object scenes. The closed and open Verdant Gate share one crop box and scale so
swapping frames at runtime keeps the pillars and lintel in place.

Frame 0: verdant-gate-closed  (east gate, locked until the green key is used)
Frame 1: verdant-gate-open
Frame 2: village-well          (town square centrepiece)
Frame 3: wooden-footbridge     (walk-over bridge across the meadow stream)

Usage: python scripts/props/pack-level-1-landmarks.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "asset" / "Originals" / "props" / "level-1"
OUTPUT = ROOT / "asset" / "MAPS" / "landmarks" / "320x256-tile_4x1-level-1-landmarks.png"

FRAME_W, FRAME_H = 320, 256
MARGIN = 2
# (frame stems sharing one crop box, target art width in px)
GROUPS = [
    (["verdant-gate-closed", "verdant-gate-open"], 316),
    (["village-well"], 150),
    (["wooden-footbridge"], 300),
]


def union_box(images: list[Image.Image]) -> tuple[int, int, int, int]:
    boxes = [image.getbbox() for image in images]
    return (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))


def main() -> None:
    frames: list[Image.Image] = []
    for stems, target in GROUPS:
        sources = [Image.open(SOURCES / f"{stem}-source.png").convert("RGBA") for stem in stems]
        box = union_box(sources)
        width, height = box[2] - box[0], box[3] - box[1]
        scale = min(1.0, target / width, (FRAME_H - MARGIN) / height)
        size = (round(width * scale), round(height * scale))
        for stem, source in zip(stems, sources):
            # premultiplied resample avoids dark fringes around transparent edges
            art = source.crop(box).convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
            frame = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
            frame.alpha_composite(art, ((FRAME_W - art.width) // 2, FRAME_H - MARGIN - art.height))
            frames.append(frame)
            print(f"frame {len(frames) - 1}: {stem} {art.width}x{art.height} scale {scale:.4f}")
    sheet = Image.new("RGBA", (FRAME_W * len(frames), FRAME_H), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (index * FRAME_W, 0))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUTPUT, optimize=True)
    print(f"wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
