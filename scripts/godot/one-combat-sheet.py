"""Lays out the one-combat film (godot/tools/film_one_combat.gd): a strip with a row per check (four frames
across its span, its caption and PASS or FAIL), the whole film as a GIF, and the HUD's console cut out larger.

    python scripts/godot/one-combat-sheet.py <film dir> [--gif-width=<px>] [--gif-step=<n>] [--cell=<px>] [--crop=<share>]

`--crop` (0.5) keeps that share of each frame round the window's middle, where the camera holds the slime (the
HUD is pictured on its own in hud-closeup.png); 1 keeps the whole window.

Writes <film dir>/strip.png, <film dir>/one-combat.gif and <film dir>/hud-closeup.png (from hud.png).
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

BG = (24, 26, 30)
TEXT = (235, 235, 235)
DIM = (150, 155, 165)
GOOD = (120, 230, 140)
BAD = (255, 110, 90)
PER_ROW = 4


def font(size):
    for name in ("segoeuib.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def notes_line(check):
    notes = check.get("notes", {})
    parts = []
    for key, value in notes.items():
        parts.append("%s %s" % (key.replace("_", " "), json.dumps(value)))
    return " · ".join(parts)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    folder = Path(args[0])
    film = json.loads((folder / "film.json").read_text(encoding="utf-8"))
    cell = int(opts.get("cell", "420"))
    gif_width = int(opts.get("gif-width", "640"))
    frames = sorted(folder.glob("f*.png"))
    share = float(opts.get("crop", "0.5"))

    def load(path):
        picture = Image.open(path).convert("RGB")
        if share >= 1.0:
            return picture
        w, h = picture.size
        cw, ch = round(w * share), round(h * share)
        left, top = (w - cw) // 2, round(h * 0.46) - ch // 2
        return picture.crop((left, top, left + cw, top + ch))

    big, small = font(24), font(14)
    first = load(frames[0])
    cell_h = round(cell * first.height / first.width)
    head = 44
    note_h = 40
    row_h = head + cell_h + note_h + 16
    width = PER_ROW * cell + (PER_ROW + 1) * 10
    strip = Image.new("RGB", (width, row_h * len(film["checks"]) + 10), BG)
    draw = ImageDraw.Draw(strip)
    for r, check in enumerate(film["checks"]):
        y = r * row_h + 10
        ok = bool(check["pass"])
        draw.text((14, y + 8), check["caption"], fill=TEXT, font=big)
        draw.text((width - 14, y + 8), "PASS" if ok else "FAIL", fill=GOOD if ok else BAD, font=big, anchor="ra")
        start, end = int(check["from_frame"]), int(check.get("to_frame", check["from_frame"]))
        end = max(start, min(end, len(frames) - 1))
        for k in range(PER_ROW):
            index = start + round((end - start) * (k + 0.5) / PER_ROW)
            picture = load(frames[min(index, len(frames) - 1)]).resize((cell, cell_h), Image.LANCZOS)
            strip.paste(picture, (10 + k * (cell + 10), y + head))
        line = notes_line(check)
        draw.text((14, y + head + cell_h + 8), line[:260], fill=DIM, font=small)
    strip.save(folder / "strip.png")

    height = round(gif_width * first.height / first.width)
    step = int(opts.get("gif-step", "2"))
    pictures = [load(path).resize((gif_width, height), Image.LANCZOS) for path in frames[::step]]
    # One palette for the whole film (from a few frames side by side), no dithering: the grass's noise
    # otherwise makes every frame differ and the GIF huge.
    sample = Image.new("RGB", (gif_width * 4, height))
    for k in range(4):
        sample.paste(pictures[len(pictures) * k // 4], (gif_width * k, 0))
    palette = sample.quantize(colors=128, method=Image.Quantize.MEDIANCUT)
    pictures = [p.quantize(palette=palette, dither=Image.Dither.NONE) for p in pictures]
    every = int(film.get("every", 2))
    duration = round(1000 * every * step / 60)
    pictures[0].save(folder / "one-combat.gif", save_all=True, append_images=pictures[1:], duration=duration, loop=0,
        optimize=True)

    hud = folder / "hud.png"
    if hud.exists():
        picture = Image.open(hud).convert("RGB")
        w, h = picture.size
        box = (int(w * 0.25), int(h * 0.855), int(w * 0.75), h)
        crop = picture.crop(box)
        crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS).save(folder / "hud-closeup.png")
    print("one-combat-sheet:", folder / "strip.png", folder / "one-combat.gif")


if __name__ == "__main__":
    main()
