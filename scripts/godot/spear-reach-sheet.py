"""Lays out the Spear's reach stills (godot/tools/film_spear_reach.gd) as one sheet: a row per strike (the jab,
the finisher, the Lunge, the jab against a wall), a column per direction (right, left, down, up), each still
captioned with the tip's reach from the slime's feet along the aim. Given two folders (before and after), each
direction shows the two side by side.

    python scripts/godot/spear-reach-sheet.py <stills dir> [<after stills dir>] --out=<sheet.png> [--cell=<px>]
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROWS = [("jab", "Jab"), ("finisher", "Finisher"), ("lunge", "Lunge (charge)"), ("jab-wall", "Jab, a wall ahead")]
DIRECTIONS = ["right", "left", "down", "up"]
ARROWS = {"right": "right", "left": "left", "down": "down", "up": "UP"}
BG = (24, 26, 30)
TEXT = (235, 235, 235)
DIM = (150, 155, 165)
BAD = (255, 110, 90)
GOOD = (120, 230, 140)


def font(size):
    for name in ("segoeuib.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def load(folder):
    data = json.loads((folder / "film.json").read_text(encoding="utf-8"))
    rows = {row["name"]: row for row in data["rows"]}
    return data, rows


def still_name(row_key, direction):
    if row_key == "jab-wall":
        return "jab-%s-wall" % direction
    return "%s-%s" % (row_key, direction)


def side_reach(rows, row_key):
    """The tip's reach from the feet facing right: what every direction should match."""
    row = rows.get(still_name(row_key, "right"))
    return row["tip_from_feet"] if row else None


def caption(row, row_key, rows):
    tip = row["tip_from_feet"]
    if row_key == "jab-wall":
        wall = row["wall_px"]
        diff = tip - wall
        if abs(diff) < 1.0:
            return "tip %d, at the wall" % round(tip), GOOD
        if diff > 0:
            return "tip %d: %d through the wall" % (round(tip), round(diff)), BAD
        full = rows.get(still_name("jab", row["direction"]))
        return "tip %d: %d short of the wall" % (round(tip), round(-diff)), BAD
    side = side_reach(rows, row_key)
    if side is None or abs(tip - side) < 1.5:
        return "tip %d from feet" % round(tip), GOOD
    if tip > side:
        return "tip %d from feet (+%d)" % (round(tip), round(tip - side)), BAD
    return "tip %d from feet (-%d)" % (round(tip), round(side - tip)), BAD


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    folders = [Path(a) for a in args]
    out = Path(opts.get("out", str(folders[0] / "sheet.png")))
    cell = int(opts.get("cell", "300"))
    loaded = [load(f) for f in folders]
    labels = ["before", "after"] if len(folders) == 2 else [""]
    big, mid, small = font(30), font(20), font(16)
    head_w, head_h, cap_h, gap = 190, 70, 56, 10
    group_w = cell * len(folders) + gap * (len(folders) - 1)
    width = head_w + len(DIRECTIONS) * (group_w + gap * 3)
    height = head_h + len(ROWS) * (cell + cap_h + gap * 2) + 40
    sheet = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    for d, direction in enumerate(DIRECTIONS):
        x = head_w + d * (group_w + gap * 3)
        draw.text((x + group_w // 2, 22), "facing %s" % ARROWS[direction], fill=TEXT, font=big, anchor="mm")
        for k, label in enumerate(labels):
            if label:
                draw.text((x + k * (cell + gap) + cell // 2, 54), label, fill=DIM, font=mid, anchor="mm")
    for r, (row_key, title) in enumerate(ROWS):
        y = head_h + r * (cell + cap_h + gap * 2)
        draw.multiline_text((12, y + cell // 2), title.replace(", ", ",\n"), fill=TEXT, font=mid, anchor="lm")
        for d, direction in enumerate(DIRECTIONS):
            x = head_w + d * (group_w + gap * 3)
            for k, (folder, (data, rows)) in enumerate(zip(folders, loaded)):
                name = still_name(row_key, direction)
                path = folder / (name + ".png")
                cx = x + k * (cell + gap)
                if not path.exists() or name not in rows:
                    draw.rectangle((cx, y, cx + cell, y + cell), outline=DIM)
                    continue
                still = Image.open(path).convert("RGB").resize((cell, cell), Image.LANCZOS)
                sheet.paste(still, (cx, y))
                text, colour = caption(rows[name], row_key, rows)
                draw.text((cx + cell // 2, y + cell + 8), text, fill=colour, font=small, anchor="mt")
                draw.text((cx + cell // 2, y + cell + 30), "line %d from the centre" % round(rows[name]["reach_from_centre"]),
                    fill=DIM, font=small, anchor="mt")
    draw.text((12, height - 28), "Yellow: the hit line the game queries. Cyan: the tip's reach from the slime's feet "
        "along the aim (game units). Side reach is the target for every direction.", fill=DIM, font=small)
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print("spear-reach-sheet:", out)


if __name__ == "__main__":
    main()
