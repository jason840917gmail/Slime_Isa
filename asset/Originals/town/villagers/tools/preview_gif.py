# preview_gif.py <manifest> <out dir> [ids...]: an animated GIF per packed character on grass, at
# 2x game size: idle (a blink), talk, then each walk row twice, side walks both ways.
import json
import sys
from pathlib import Path
from PIL import Image

MANIFEST, OUT = Path(sys.argv[1]), Path(sys.argv[2])
GODOT = MANIFEST.parents[4] / "godot"
GRASS = (104, 132, 70, 255)
manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
wanted = sys.argv[3:] or list(manifest)
for cid in wanted:
    info = manifest[cid]
    sheet = Image.open(GODOT / info["sheet"].removeprefix("res://")).convert("RGBA")
    cell = info["cell"]

    def frame(row, col, flip=False):
        f = sheet.crop((col * cell, row * cell, (col + 1) * cell, (row + 1) * cell))
        return f.transpose(Image.FLIP_LEFT_RIGHT) if flip else f

    seq = []  # (image, ms)
    rows = info["rows"]
    poses = rows[list(rows)[0]]["row"]
    if rows[list(rows)[0]]["frames"] >= 4 and "walk-side" in rows or list(rows)[0] == "poses" and rows["poses"]["frames"] == 4:
        seq += [(frame(poses, 0), 900), (frame(poses, 1), 140), (frame(poses, 0), 600), (frame(poses, 2), 220),
                (frame(poses, 0), 200), (frame(poses, 2), 220), (frame(poses, 3), 300), (frame(poses, 0), 400)]
    else:
        seq += [(frame(poses, c), 250) for c in range(rows[list(rows)[0]]["frames"])]
    for name in ("walk-side", "walk-down", "walk-up"):
        if name in rows:
            for flip in ((False, True) if name == "walk-side" else (False,)):
                seq += [(frame(rows[name]["row"], c, flip), 125) for c in range(rows[name]["frames"])] * 3
    size = cell * 2
    images = []
    durations = []
    for img, ms in seq:
        bg = Image.new("RGBA", (cell, cell), GRASS)
        bg.alpha_composite(img)
        images.append(bg.resize((size, size), Image.NEAREST).convert("P", palette=Image.ADAPTIVE))
        durations.append(ms)
    OUT.mkdir(parents=True, exist_ok=True)
    images[0].save(OUT / f"{cid}.gif", save_all=True, append_images=images[1:], duration=durations, loop=0, disposal=2)
    print("wrote", OUT / f"{cid}.gif", len(images), "frames")
