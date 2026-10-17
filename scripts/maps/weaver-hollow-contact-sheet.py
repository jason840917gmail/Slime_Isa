"""Lays out the Weaver Hollow's filmed shots (godot/tools/film_weaver_hollow.gd) as a contact sheet.

    python scripts/maps/weaver-hollow-contact-sheet.py <film dir> <out.png> [--columns=5] [--width=480]

Reads <film dir>/shots.json (each shot's file and caption) and writes one picture: the shots in
order, each scaled to --width, with its number and caption under it.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT = "C:/Windows/Fonts/segoeui.ttf"
FONT_BOLD = "C:/Windows/Fonts/segoeuib.ttf"


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    options = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    film = Path(args[0])
    out = Path(args[1])
    columns = int(options.get("columns", 5))
    width = int(options.get("width", 480))
    shots = json.loads((film / "shots.json").read_text(encoding="utf-8"))
    first = Image.open(film / shots[0]["file"])
    height = round(first.height * width / first.width)
    caption_h = 54
    gap = 14
    rows = (len(shots) + columns - 1) // columns
    title_h = 70
    sheet = Image.new("RGB", (columns * (width + gap) + gap, title_h + rows * (height + caption_h + gap) + gap), (30, 27, 24))
    draw = ImageDraw.Draw(sheet)
    title = ImageFont.truetype(FONT_BOLD, 30)
    bold = ImageFont.truetype(FONT_BOLD, 17)
    regular = ImageFont.truetype(FONT, 16)
    draw.text((gap, 16), "The Weaver Hollow: the main path, the forecourt to the Pearl in the Hoard, the Matron's fall and out (filmed in the game)", font=title,
              fill=(240, 228, 205))
    for index, shot in enumerate(shots):
        column, row = index % columns, index // columns
        x = gap + column * (width + gap)
        y = title_h + row * (height + caption_h + gap)
        picture = Image.open(film / shot["file"]).convert("RGB").resize((width, height), Image.LANCZOS)
        sheet.paste(picture, (x, y))
        number = shot["file"].split("-", 1)[0]
        draw.text((x, y + height + 4), number, font=bold, fill=(236, 178, 10))
        words = shot["caption"]
        line, lines = "", []
        for word in words.split():
            trial = (line + " " + word).strip()
            if draw.textlength(trial, font=regular) > width - 34:
                lines.append(line)
                line = word
            else:
                line = trial
        lines.append(line)
        for i, text in enumerate(lines[:2]):
            draw.text((x + 30, y + height + 4 + i * 20), text, font=regular, fill=(232, 222, 204))
    sheet.save(out)
    print("saved", out, sheet.size)


if __name__ == "__main__":
    main()
