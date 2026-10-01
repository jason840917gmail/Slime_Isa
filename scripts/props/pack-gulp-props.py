"""Pack the Magnific GPT-2 Gulp and secret props into one 256x256 sprite sheet,
and the Gulp form icons into a 128x128 UI sheet.

Sources live in asset/Originals/props/gulp/ (transparent generations). Each
prop is trimmed, scaled to its target width (never upscaled) and bottom-centre
anchored with a small margin, matching the render origin [0.5, 1] used by the
object scenes. The cracked ground and the sinkhole share one crop box and
scale, so breaking the ground swaps frames without the patch jumping.

Frame 0: cracked-ground  (weak ground the Heavy form breaks)
Frame 1: sinkhole        (the broken ground: a hole with a rope ladder down)
Frame 2: cave-ladder     (the way back up, inside a cavern)
Frame 3: silk-cocoon     (the silk Gulp spot: eat it to become Sticky)
Frame 4: spider-web      (a web barrier only the Sticky form crosses)
Frame 5: goo-heart       (collectible: +max HP for the run)
Frame 6: plate-up        (pressure plate, raised)
Frame 7: plate-down      (pressure plate, held down: its rune glows)

Form icons (asset/UI/ui-gulp-form-icons-2x1.webp, sources in asset/Originals/ui/gulp/):
Frame 0: heavy, frame 1: sticky (the Gulp HUD timer and the quick wheel).

Usage: python scripts/props/pack-gulp-props.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from game_webp import save_game_webp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "asset" / "Originals" / "props" / "gulp"
OUTPUT = ROOT / "asset" / "MAPS" / "props" / "256x256-tile_8x1-gulp-props.webp"
ICON_SOURCES = ROOT / "asset" / "Originals" / "ui" / "gulp"
ICON_OUTPUT = ROOT / "asset" / "UI" / "ui-gulp-form-icons-2x1.webp"
ICON_SIZE = 128
ICON_STEMS = ["form-heavy", "form-sticky"]
# Later generations carry faint alpha noise around the art; below this it is cleared.
NOISE_ALPHA = 12

FRAME_W, FRAME_H = 256, 256
MARGIN = 2
# (frame stems sharing one crop box, target art width in px, clear alpha noise)
GROUPS = [
    (["cracked-ground", "sinkhole"], 200, False),
    (["cave-ladder"], 170, False),
    (["silk-cocoon"], 150, False),
    (["spider-web"], 250, False),
    (["goo-heart"], 110, False),
    (["plate-up", "plate-down"], 120, True),
]


def load(path: Path, clean: bool) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    if clean:
        alpha = image.getchannel("A").point(lambda value: 0 if value < NOISE_ALPHA else value)
        image.putalpha(alpha)
    return image


def union_box(images: list[Image.Image]) -> tuple[int, int, int, int]:
    boxes = [image.getbbox() for image in images]
    return (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))


def main() -> None:
    frames: list[Image.Image] = []
    for stems, target, clean in GROUPS:
        sources = [load(SOURCES / f"{stem}-source.png", clean) for stem in stems]
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
    save_game_webp(sheet, OUTPUT)
    print(f"wrote {OUTPUT.relative_to(ROOT)} {sheet.width}x{sheet.height}")
    pack_icons()


def pack_icons() -> None:
    icons = [load(ICON_SOURCES / f"{stem}-source.png", True) for stem in ICON_STEMS]
    box = union_box(icons)
    width, height = box[2] - box[0], box[3] - box[1]
    scale = min((ICON_SIZE - 4) / width, (ICON_SIZE - 4) / height)
    size = (round(width * scale), round(height * scale))
    sheet = Image.new("RGBA", (ICON_SIZE * len(icons), ICON_SIZE), (0, 0, 0, 0))
    for index, icon in enumerate(icons):
        art = icon.crop(box).convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
        sheet.alpha_composite(art, (index * ICON_SIZE + (ICON_SIZE - art.width) // 2, (ICON_SIZE - art.height) // 2))
    save_game_webp(sheet, ICON_OUTPUT)
    print(f"wrote {ICON_OUTPUT.relative_to(ROOT)} {sheet.width}x{sheet.height}")


if __name__ == "__main__":
    main()
