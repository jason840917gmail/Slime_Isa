# The roughs at game scale (the render is 1 px per world unit) on the sibling's town render 3.
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
CUTS, RENDER, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
base = Image.open(RENDER).convert("RGBA")
K = base.width / 2000.0  # positions below are in the 2000 px wide preview's coordinates
TAG = ImageFont.truetype("C:/Windows/Fonts/georgiab.ttf", 15)
ADULT, KID = 70, 50


def V(s, n): return f"{CUTS}/villagers-{s}-{n}.png"
def A(s, n): return f"{CUTS}/animals-{s}-{n}.png"


# (picture, feet x, feet y, height in units, tag, flip)
OUTSIDE = [
    (V(2, 2), 112, 205, ADULT, "V9", False),
    (V(2, 3), 893, 690, ADULT, "V10", False),
    (V(2, 4), 1105, 690, ADULT, "V11", True),
    (V(2, 5), 1365, 1092, ADULT, "V12", False),
    (V(3, 0), 1690, 995, ADULT, "V13", False),
    (V(3, 1), 772, 580, ADULT, "V14", False),
    (V(3, 3), 1268, 492, ADULT, "V16", True),
    (V(3, 4), 610, 590, ADULT, "V17", False),
    (A(1, 1), 655, 594, 32, "A2", False),
    (V(3, 5), 1665, 612, ADULT, "V18", True),
    (V(4, 0), 1222, 585, ADULT, "V19", True),
    (V(4, 1), 925, 548, KID, "V20", False),
    (V(4, 2), 1080, 612, KID, "V21", True),
    (V(4, 3), 1055, 965, KID, "V22", True),
    (A(1, 0), 190, 1060, 46, "A1", False),
    (A(1, 2), 600, 440, 30, "A3", False),
    (A(1, 3), 330, 207, 32, "A4", True),
    (A(1, 4), 380, 700, 44, "A5", False),
    (A(2, 0), 1385, 118, 14, "A7", False),
    (A(2, 1), 1835, 128, 14, "", False),
    (A(2, 2), 235, 92, 14, "", False),
    (A(2, 3), 1250, 725, 17, "A8", False),
    (A(2, 3), 560, 770, 17, "", True),
    (A(2, 4), 1040, 470, 20, "A9", False),
    (A(2, 4), 1068, 482, 20, "", True),
    (A(2, 4), 975, 478, 20, "", False),
    (A(2, 5), 1640, 238, 15, "A10", False),
    (A(2, 6), 1700, 205, 19, "A11", False),
    (A(2, 7), 1905, 1082, 26, "A12", True),
]
# Who is inside, a bubble over the door: (pictures, x, y, tag)
INSIDE = [
    ([V(1, 0)], 255, 335, "V1"),
    ([V(1, 1), V(2, 0)], 545, 360, "V2 V7"),
    ([V(1, 3)], 1010, 360, "V4"),
    ([V(1, 5)], 235, 790, "V6"),
    ([V(2, 1)], 580, 800, "V8"),
    ([V(1, 2)], 1130, 800, "V3"),
    ([V(1, 4)], 1500, 800, "V5"),
]


def tag(img, x, y, text, fill=(42, 26, 14, 220)):
    d = ImageDraw.Draw(img)
    w = d.textlength(text, font=TAG) + 10
    d.rounded_rectangle((x - w / 2, y - 10, x + w / 2, y + 10), 7, fill=fill)
    d.text((x, y), text, font=TAG, fill="white", anchor="mm")


figs = []
for path, fx, fy, h, label, flip in OUTSIDE:
    f = Image.open(path).convert("RGBA")
    h = int(h * K * 1.024)
    f = f.resize((max(1, int(f.width * h / f.height)), h), Image.LANCZOS)
    if flip:
        f = f.transpose(Image.FLIP_LEFT_RIGHT)
    figs.append((fy * K, fx * K, f, label))
figs.sort(key=lambda t: t[0])
shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
for fy, fx, f, _ in figs:
    sd.ellipse((fx - f.width * 0.38, fy - f.height * 0.07 - 2, fx + f.width * 0.38, fy + f.height * 0.07 + 2), fill=(20, 30, 10, 110))
base.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(3)))
for fy, fx, f, _ in figs:
    base.alpha_composite(f, (int(fx - f.width / 2), int(fy - f.height)))
for fy, fx, f, label in figs:
    if label:
        tag(base, fx, fy + 12, label)
d = ImageDraw.Draw(base)
for paths, x, y, label in INSIDE:
    x, y = x * K, y * K
    r = 30 if len(paths) == 1 else 40
    d.ellipse((x - r - 3, y - r - 3, x + r + 3, y + r + 3), fill=(42, 26, 14, 255))
    d.ellipse((x - r, y - r, x + r, y + r), fill=(250, 242, 222, 255))
    n = len(paths)
    for i, p in enumerate(paths):
        f = Image.open(p).convert("RGBA")
        fh = int(r * (1.5 if n == 1 else 1.1))
        f = f.resize((max(1, int(f.width * fh / f.height)), fh), Image.LANCZOS)
        cx = x + (0 if n == 1 else (i - 0.5) * r * 0.9)
        base.alpha_composite(f, (int(cx - f.width / 2), int(y + r * 0.75 - f.height)))
    tag(base, x, y + r + 14, label + " inside", fill=(62, 100, 168, 235))
base.convert("RGB").save(f"{OUT}/west-town-life-mockup.jpg", quality=90)
# The plaza at 2x
crop = base.crop((int(560 * K), int(380 * K), int(1400 * K), int(760 * K)))
crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS).convert("RGB").save(f"{OUT}/west-town-life-mockup-plaza-2x.jpg", quality=90)
print("done", base.size)
