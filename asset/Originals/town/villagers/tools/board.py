# Pick boards for the West town's villagers and animals (2026-11-01).
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
CUTS, OUT = sys.argv[1], sys.argv[2]
F = "C:/Windows/Fonts/"
def font(name, size): return ImageFont.truetype(F + name, size)
TITLE, HEAD, NAME, BODY, NUM = font("georgiab.ttf", 46), font("georgiab.ttf", 30), font("georgiab.ttf", 23), font("georgia.ttf", 17), font("georgiab.ttf", 20)
ITAL = font("georgiai.ttf", 17)
PAPER, INK, CARD = (241, 228, 195), (42, 26, 14), (250, 242, 222)
KIND = {"indoor": ((62, 100, 168), "INDOOR"), "post": ((61, 120, 40), "AT A POST"), "walker": ((196, 110, 30), "WALKS AROUND"),
        "story": ((140, 60, 120), "STORY NPC"), "ambient": ((61, 120, 40), "AMBIENT"), "pen": ((140, 90, 40), "PEN / YARD"), "pet": ((196, 110, 30), "PET")}


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


def card(fig_paths, code, name, role, where, kind, fig_h, cw=290, ch=410):
    c = Image.new("RGBA", (cw, ch), CARD + (255,))
    d = ImageDraw.Draw(c)
    d.rounded_rectangle((0, 0, cw - 1, ch - 1), 14, outline=(150, 110, 70), width=3)
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
        ImageDraw.Draw(sh).ellipse((x + f.width * 0.15, base - 10, x + f.width * 0.85, base + 8), fill=(60, 40, 20, 90))
        c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(4)))
        c.alpha_composite(f, (x, base - f.height))
        x += f.width + 6
    col, label = KIND[kind]
    bw = max(52, d.textlength(code, font=NUM) + 20)
    d.rounded_rectangle((10, 10, 10 + bw, 46), 18, fill=col)
    d.text((10 + bw / 2, 28), code, font=NUM, fill="white", anchor="mm")
    tw = d.textlength(label, font=BODY) + 16
    d.rounded_rectangle((cw - tw - 10, 52, cw - 10, 78), 8, fill=col)
    d.text((cw - 10 - tw / 2, 65), label, font=BODY, fill="white", anchor="mm")
    y = 278
    d.text((cw / 2, y), name, font=NAME, fill=INK, anchor="ma")
    y += 32
    for ln in wrap(role, BODY, cw - 24, d):
        d.text((cw / 2, y), ln, font=BODY, fill=INK, anchor="ma")
        y += 22
    y += 6
    for ln in wrap(where, ITAL, cw - 24, d):
        d.text((cw / 2, y), ln, font=ITAL, fill=(110, 70, 40), anchor="ma")
        y += 21
    return c


def board(title, subtitle, sections, out, per_row=8, cw=290, ch=410):
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
    d.text((margin, 94), subtitle, font=font("georgiai.ttf", 22), fill=(110, 70, 40))
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
    img.convert("RGB").save(out, quality=90)
    print(out, img.size)


def V(s, n): return f"{CUTS}/villagers-{s}-{n}.png"
def A(s, n): return f"{CUTS}/animals-{s}-{n}.png"


H, K = 230, 165
indoor = [
    card([V(1, 0)], "V1", "Dollop", "Shopkeeper: potions and food ingredients", "General store, behind the counter", "indoor", H),
    card([V(1, 1)], "V2", "Burble", "Innkeeper of the Bubbling Mug", "Inn, behind the bar", "indoor", H),
    card([V(1, 2)], "V3", "Crumb", "Baker: pumpkin pies, mushroom buns", "Twin mushroom house (or a pumpkin house)", "indoor", H),
    card([V(1, 3)], "V4", "Mayor Wobbleton", "The mayor, fussy and proud", "Town hall, at his desk", "indoor", H),
    card([V(1, 4)], "V5", "Bobbin", "Tailor", "Two flats, her shop upstairs", "indoor", H),
    card([V(1, 5)], "V6", "Auntie Suds", "Bathhouse keeper", "Goo bathhouse, by the warm pool", "indoor", H),
    card([V(2, 0)], "V7", "Dune", "A traveller stuck here: the desert road is closed", "Inn, at a table", "indoor", H),
    card([V(2, 1)], "V8", "Granny Thistle", "Herbalist; the town's secret potion", "Jelly dome house (or the snail shell)", "indoor", H),
]
posts = [
    card([V(2, 2)], "V9", "Sprig", "Gardener", "The hedge gardens, by the beds", "post", H),
    card([V(2, 3), V(2, 4)], "V10+11", "Dot & Dab", "The town gossips (two villagers)", "Benches by the goo fountain", "post", [190, 190]),
    card([V(2, 5)], "V12", "Bram", "Apprentice Thorn Guard", "The town gate", "post", H),
    card([V(3, 0)], "V13", "Zing", "Runs the throwing game", "The game booth", "post", H),
    card([V(3, 1)], "V14", "Plum", "Fruit seller", "A market stall on the plaza", "post", H),
    card([V(3, 2)], "V15", "Gramps Reel", "Old fisher, tall tales", "A pond or stream bank (none in the town yet)", "post", H),
]
walkers = [
    card([V(3, 3)], "V16", "Penny", "Mail carrier", "A route from mailbox to mailbox", "walker", H),
    card([V(3, 4), A(1, 1)], "V17", "Old Sedge & Biscuit", "Walks his pup round the town", "A route on the streets", "walker", [H, 110]),
    card([V(3, 5)], "V18", "Wick", "Lamplighter: tops up the goo lamps", "A route from lamp to lamp", "walker", H),
    card([V(4, 0)], "V19", "Tansy", "Shopper with a basket", "Wanders the market and the shops", "walker", H),
    card([V(4, 1), V(4, 2)], "V20+21", "Fizz & Tad", "Two kids playing tag (two villagers)", "A small area by the fountain", "walker", [K, K]),
    card([V(4, 3)], "V22", "Young Burr", "Burr's son; teaches the Roll later", "The gatekeeper's house yard", "story", K),
]
board("West town villagers: pick board",
      "Style roughs (GPT 2.5). Pick by number; looks, names and colours can still change. The final art adds walk cycles and an idle loop.",
      [("Indoors (in their house or shop)", indoor), ("At their posts outside", posts), ("Walking around town", walkers)],
      f"{OUT}/west-town-villagers-board.jpg")

animals = [
    card([A(1, 0)], "A1", "Pigs", "Mother pig and piglets; snuffle and trot about", "A pen with a picket fence", "pen", 200),
    card([A(1, 1)], "A2", "Biscuit the pup", "Trots at Old Sedge's heels; wags; one bark", "With Old Sedge (V17), or a yard", "pet", 170),
    card([A(1, 2)], "A3", "Cat", "Naps, breathes, flicks its tail; strolls off if you get close", "Inn porch, a bench, a doorstep", "pet", 170),
    card([A(1, 3)], "A4", "Hen & chicks", "Peck and wander; scatter if you run through", "A yard or the gardens", "pen", 180),
    card([A(1, 4)], "A5", "Sheep", "Graze and wander; the bell clinks", "A meadow pen", "pen", 190),
    card([A(1, 5)], "A6", "Duck & ducklings", "Paddle a loop, the ducklings in a line", "A pond (none in the town yet)", "ambient", 150),
    card([A(2, 0), A(2, 1), A(2, 2)], "A7", "Butterflies", "Flutter over flowers on looping paths", "Gardens, flower beds", "ambient", [90, 90, 90]),
    card([A(2, 3)], "A8", "Robin", "Hops and pecks; flies off when you come near", "Lawns and paths", "ambient", 120),
    card([A(2, 4)], "A9", "Doves", "A few on the plaza; burst up and fly off near you", "The plaza and fountain", "ambient", 140),
    card([A(2, 5)], "A10", "Snail", "Crawls along slowly; hides in its shell if touched", "Hedges and walls", "ambient", 120),
    card([A(2, 6)], "A11", "Hedgehog", "Snuffles about; curls into a ball near you", "The gardens", "ambient", 130),
    card([A(2, 7)], "A12", "Squirrel", "Sits by a tree, then darts to the next", "Trees at the town's edge", "ambient", 150),
]
board("West town animals: pick board",
      "Style roughs (GPT 2.5). Already in the game: bees on the beehive, frogs on lily pads, fish. No night yet, so fireflies only in shady spots.",
      [("Animals and pets", animals)], f"{OUT}/west-town-animals-board.jpg", per_row=6)
