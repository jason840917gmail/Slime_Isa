# The cave animals' sheet: every frame of each at the game's size (the packed sheet at half its
# pixels, as the scenes draw it at a 1024 px high window) and its first frame three times larger.
#   python asset/Originals/cave-animals/tools/sheet.py <out.png>
import glob
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[4]
PACKED = REPO / "godot" / "asset" / "characters" / "cave-animals"
F = "C:/Windows/Fonts/"
TITLE, NAME, BODY = (ImageFont.truetype(F + "georgiab.ttf", 34), ImageFont.truetype(F + "georgiab.ttf", 22),
    ImageFont.truetype(F + "georgia.ttf", 16))
FLOOR, INK, SOFT = (44, 48, 66), (245, 236, 214), (190, 180, 200)
ANIMALS = [
    ("firefly", "Firefly (and a swarm of five)", "always flying; tail shines, then dims; scatters from the slime",
        ["wings up", "level", "down", "dim", "dim", "dim"]),
    ("glow-worm", "Glow-worm", "inches along; its tail swells bright and fades",
        ["long", "hump", "half", "bright", "dim, blink", "front"]),
    ("pill-bug", "Pill bug", "scuttles; rolls into a ball near the slime",
        ["stand", "step", "step", "ball", "peek", "front"]),
    ("cave-newt", "Cave newt", "pads about, looks up, blinks; runs from the slime",
        ["stand", "step", "step", "look", "blink", "front"]),
    ("crystal-snail", "Crystal snail", "crawls slowly; crystals glint; hides near the slime",
        ["long", "short", "half", "hidden", "glint", "front"]),
    ("lantern-moth", "Lantern moth", "always flying, flutters round a light",
        ["open", "half", "closed", "(spare)", "rest", "(spare)"]),
]
ROW_H, BIG, PAD = 150, 3.0, 30
width = 1500
out = Image.new("RGBA", (width, 110 + ROW_H * len(ANIMALS) + PAD), FLOOR + (255,))
d = ImageDraw.Draw(out)
d.text((PAD, 24), "Cave animals at game size", font=TITLE, fill=INK)
d.text((PAD, 70), "Left: three times larger. Right: every frame as the game draws it (window 1024 px high).", font=BODY, fill=SOFT)
for row, (cid, name, how, labels) in enumerate(ANIMALS):
    path = glob.glob(str(PACKED / f"*-tile_*-{cid}.webp"))[0]
    sheet = Image.open(path).convert("RGBA")
    cell = sheet.height
    frames = [sheet.crop((i * cell, 0, (i + 1) * cell, cell)) for i in range(sheet.width // cell)]
    top = 110 + row * ROW_H
    d.line((PAD, top, width - PAD, top), fill=(70, 74, 96), width=1)
    big = frames[0].crop(frames[0].getbbox())
    big = big.resize((round(big.width * 0.5 * BIG), round(big.height * 0.5 * BIG)), Image.LANCZOS)
    out.alpha_composite(big, (PAD + 80 - big.width // 2, top + ROW_H - 24 - big.height))
    d.text((PAD + 190, top + 22), name, font=NAME, fill=INK)
    d.text((PAD + 190, top + 54), how, font=BODY, fill=SOFT)
    d.text((PAD + 190, top + 80), f"{cell // 2} x {cell // 2} units a frame", font=BODY, fill=(140, 134, 156))
    x = 760
    for frame, label in zip(frames, labels):
        small = frame.resize((cell // 2, cell // 2), Image.LANCZOS)
        out.alpha_composite(small, (x + 55 - small.width // 2, top + ROW_H - 44 - small.height))
        d.text((x + 55, top + ROW_H - 36), label, font=BODY, fill=SOFT, anchor="ma")
        x += 118
out.convert("RGB").save(sys.argv[1])
print(sys.argv[1], out.size)
