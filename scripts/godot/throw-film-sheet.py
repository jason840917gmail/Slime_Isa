"""Lays a throw film (godot/tools/film_throw.gd) out for judging: a strip of its frames and GIFs.

    python scripts/godot/throw-film-sheet.py <film dir> [--crop=x,y,w,h] [--step=2] [--cols=8]
        [--zoom=2] [--title=<text>] [--from=<frame>] [--to=<frame>]

Writes into the film dir: strip.png (every `step`-th frame, numbered, `cols` per row), throw.gif
(game speed) and throw-slow.gif (a quarter of it). The crop is in the window's pixels; the default
frames the stage film_throw.gd sets up (the slime throwing right).
"""
import glob
import os
import sys

from PIL import Image, ImageDraw, ImageFont

DEFAULT_CROP = (470, 215, 480, 180)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    if not args:
        raise SystemExit(__doc__)
    folder = args[0]
    crop = tuple(int(v) for v in opts["crop"].split(",")) if "crop" in opts else DEFAULT_CROP
    step = int(opts.get("step", 2))
    cols = int(opts.get("cols", 8))
    zoom = float(opts.get("zoom", 2))
    title = opts.get("title", os.path.basename(os.path.normpath(folder)))
    files = sorted(glob.glob(os.path.join(folder, "f[0-9][0-9][0-9].png")))
    first = int(opts.get("from", 0))
    last = int(opts.get("to", len(files) - 1))
    files = files[first:last + 1]
    if not files:
        raise SystemExit("no frames in " + folder)
    box = (crop[0], crop[1], crop[0] + crop[2], crop[1] + crop[3])
    size = (int(crop[2] * zoom), int(crop[3] * zoom))
    frames = [Image.open(f).convert("RGB").crop(box).resize(size, Image.LANCZOS) for f in files]

    try:
        font = ImageFont.truetype("arial.ttf", 16)
        big = ImageFont.truetype("arialbd.ttf", 22)
    except OSError:
        font = big = ImageFont.load_default()

    picked = list(range(0, len(frames), step))
    rows = (len(picked) + cols - 1) // cols
    cell = (size[0] // 2, size[1] // 2)
    head = 36
    sheet = Image.new("RGB", (cols * cell[0], head + rows * cell[1]), (24, 24, 28))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 6), "%s   (every %d frames, 60 per second)" % (title, step), fill=(255, 255, 255), font=big)
    for n, index in enumerate(picked):
        x = (n % cols) * cell[0]
        y = head + (n // cols) * cell[1]
        sheet.paste(frames[index].resize(cell, Image.LANCZOS), (x, y))
        draw.text((x + 4, y + 2), "%d  %d ms" % (first + index, round((first + index) * 1000 / 60)),
                  fill=(255, 255, 120), font=font)
    sheet.save(os.path.join(folder, "strip.png"))

    # GIFs keep to 50 per second at most (20 ms steps): game speed drops every sixth frame's time.
    palette = [f.quantize(colors=128, method=Image.MEDIANCUT) for f in frames]
    palette[0].save(os.path.join(folder, "throw.gif"), save_all=True, append_images=palette[1:], duration=20, loop=0)
    palette[0].save(os.path.join(folder, "throw-slow.gif"), save_all=True, append_images=palette[1:], duration=70, loop=0)
    print("wrote strip.png, throw.gif, throw-slow.gif in", folder)


if __name__ == "__main__":
    main()
