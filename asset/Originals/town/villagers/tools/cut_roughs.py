# Cut each rough sheet into its figures (grid cells, trimmed to alpha) -> cuts/<sheet>-<n>.png
import sys
from PIL import Image
R = sys.argv[1]; OUT = sys.argv[2]
GRIDS = {"villagers-1": (3, 2), "villagers-2": (3, 2), "villagers-3": (3, 2), "villagers-4": (2, 2),
         "animals-1": (3, 2), "animals-2": (4, 2)}
for name, (cols, rows) in GRIDS.items():
    im = Image.open(f"{R}/{name}.png").convert("RGBA")
    w, h = im.width / cols, im.height / rows
    n = 0
    for r in range(rows):
        for c in range(cols):
            cell = im.crop((int(c * w), int(r * h), int((c + 1) * w), int((r + 1) * h)))
            a = cell.getchannel("A").point(lambda v: 255 if v > 24 else 0)
            box = a.getbbox()
            cell = cell.crop(box)
            cell.save(f"{OUT}/{name}-{n}.png")
            print(name, n, cell.size)
            n += 1
