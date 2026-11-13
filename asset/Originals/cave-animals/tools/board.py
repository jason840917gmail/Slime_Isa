# The cave animals' pick board (2026-11-12), in the look of the West town's boards
# (asset/Originals/town/villagers/tools/board.py).
#   python asset/Originals/cave-animals/tools/board.py <cuts dir> <out dir>
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

CUTS, OUT = sys.argv[1], sys.argv[2]
F = "C:/Windows/Fonts/"
def font(name, size): return ImageFont.truetype(F + name, size)
TITLE, HEAD, NAME, BODY, NUM = font("georgiab.ttf", 46), font("georgiab.ttf", 30), font("georgiab.ttf", 23), font("georgia.ttf", 17), font("georgiab.ttf", 20)
ITAL = font("georgiai.ttf", 17)
PAPER, INK, CARD = (52, 44, 58), (245, 236, 214), (74, 64, 80)
KIND = {"first": ((61, 130, 60), "FIRST SET"), "extra": ((196, 110, 30), "EXTRA"), "clash": ((176, 52, 52), "LOOKS LIKE AN ENEMY")}


def wrap(text, fnt, width, draw):
    words, lines, line = text.split(), [], ""
    for w in words:
        t = (line + " " + w).strip()
        if draw.textlength(t, font=fnt) <= width:
            line = t
        else:
            lines.append(line)
            line = w
    if line:
        lines.append(line)
    return lines


def card(fig_paths, code, name, role, where, kind, fig_h, cw=300, ch=430):
    c = Image.new("RGBA", (cw, ch), CARD + (255,))
    d = ImageDraw.Draw(c)
    d.rounded_rectangle((0, 0, cw - 1, ch - 1), 14, outline=(150, 130, 160), width=3)
    figs = [Image.open(p).convert("RGBA") for p in fig_paths]
    hs = fig_h if isinstance(fig_h, list) else [fig_h] * len(figs)
    figs = [f.resize((max(1, int(f.width * h / f.height)), h), Image.LANCZOS) for f, h in zip(figs, hs)]
    total = sum(f.width for f in figs) + 6 * (len(figs) - 1)
    scale = min(1.0, (cw - 24) / total)
    if scale < 1.0:
        figs = [f.resize((max(1, int(f.width * scale)), max(1, int(f.height * scale))), Image.LANCZOS) for f in figs]
        total = sum(f.width for f in figs) + 6 * (len(figs) - 1)
    x, base = (cw - total) // 2, 262
    for f in figs:
        sh = Image.new("RGBA", c.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((x + f.width * 0.15, base - 10, x + f.width * 0.85, base + 8), fill=(10, 6, 14, 120))
        c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(4)))
        c.alpha_composite(f, (x, base - f.height))
        x += f.width + 6
    col, label = KIND[kind]
    bw = max(52, d.textlength(code, font=NUM) + 20)
    d.rounded_rectangle((10, 10, 10 + bw, 46), 18, fill=col)
    d.text((10 + bw / 2, 28), code, font=NUM, fill="white", anchor="mm")
    tw = d.textlength(label, font=BODY) + 16
    d.rounded_rectangle((cw - tw - 10, 12, cw - 10, 40), 8, fill=col)
    d.text((cw - 10 - tw / 2, 26), label, font=BODY, fill="white", anchor="mm")
    y = 278
    d.text((cw / 2, y), name, font=NAME, fill=INK, anchor="ma")
    y += 32
    for ln in wrap(role, BODY, cw - 24, d):
        d.text((cw / 2, y), ln, font=BODY, fill=INK, anchor="ma")
        y += 22
    y += 6
    for ln in wrap(where, ITAL, cw - 24, d):
        d.text((cw / 2, y), ln, font=ITAL, fill=(214, 190, 150), anchor="ma")
        y += 21
    return c


def board(title, subtitle, sections, out, per_row=6, cw=300, ch=430):
    gap, margin = 18, 40
    width = margin * 2 + per_row * cw + (per_row - 1) * gap
    rows = []
    for head, cards in sections:
        rows.append(("head", head))
        for i in range(0, len(cards), per_row):
            rows.append(("cards", cards[i:i + per_row]))
    height = 150 + sum(60 if k == "head" else ch + gap for k, _ in rows) + margin
    img = Image.new("RGBA", (width, height), PAPER + (255,))
    d = ImageDraw.Draw(img)
    d.text((margin, 34), title, font=TITLE, fill=INK)
    d.text((margin, 94), subtitle, font=font("georgiai.ttf", 22), fill=(214, 190, 150))
    y = 150
    for kind, item in rows:
        if kind == "head":
            d.text((margin, y + 12), item, font=HEAD, fill=INK)
            y += 60
        else:
            x = margin
            for c in item:
                img.alpha_composite(c, (x, y))
                x += cw + gap
            y += ch + gap
    img.convert("RGB").save(out, quality=92)
    print(out, img.size)


def C(s, n): return f"{CUTS}/cave-animals-{s}-{n}.png"


first = [
    card([C(2, 7)], "C1", "Fireflies", "A swarm that drifts and blinks, a small light in a dark room; scatters when you walk in",
        "Dark rooms: the Mine, the glow-moss burrow, Weaver Hollow", "first", 190),
    card([C(1, 3)], "C2", "Glow-worm", "Inches along slowly, its tail pulsing teal; a faint light in the dark; takes no notice of you",
        "Cave floors by the walls: every cave", "first", 150),
    card([C(1, 4), C(1, 5)], "C3", "Pill bug", "Scuttles about; rolls into a ball when you come near",
        "Cavern floors, the Lair, the desert caves", "first", [130, 120]),
    card([C(1, 6)], "C4", "Cave newt", "Pads about a pool's bank, sits and blinks; darts away when you come close",
        "By the pools of the Crystal Caverns and Gloop", "first", 170),
    card([C(1, 7)], "C5", "Crystal snail", "Crawls very slowly, its crystals glinting; hides in its shell if you come near",
        "Crystal Caverns and the Crystal Mine", "first", 170),
    card([C(2, 0)], "C6", "Lantern moth", "Flutters round and round a light, never lands",
        "Round braziers, lamps and lanterns: the Mine's lamp tunnel, the Lair", "first", 160),
]
extra = [
    card([C(1, 1), C(1, 2)], "C7", "Cave bat", "Hangs asleep; flutters off when you come near, comes back later",
        "The Glint Bat enemy (Mine) is this same brown bat. If you want one: tiny and snow-white?", "clash", [200, 150]),
    card([C(2, 2)], "C8", "Glow beetle", "Scuttles from spot to spot, its spots glowing",
        "Cave floors; keep away from the Dung Roller's rooms (also a beetle)", "extra", 150),
    card([C(2, 3)], "C9", "Cave mouse", "Sits nibbling its glow mushroom; runs off when you come near",
        "Burrows and the single caves", "extra", 180),
    card([C(2, 4)], "C10", "Cave frog", "Sits and blinks, hops now and then",
        "By pools (frogs on lily pads exist already)", "extra", 160),
    card([C(2, 1)], "C11", "Blind cave fish", "Swims a loop in a pool",
        "Crystal Caverns pools (the game's fish are a different, older kind of object)", "extra", 110),
    card([C(2, 6)], "C12", "Cave crab", "Sidesteps along the bank, waves a claw",
        "Pool banks", "extra", 130),
]
board("Cave animals: pick board",
      "Style roughs (GPT 2.5), in the village animals' look. All harmless: they never hurt, never block an attack. The final art adds walks and idle loops.",
      [("First set (what I build unless you say otherwise)", first), ("Extras and one clash: say a number to add or swap", extra)],
      f"{OUT}/cave-animals-board.jpg")
