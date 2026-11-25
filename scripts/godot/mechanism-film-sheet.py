"""Lays a mechanism film (godot/tools/film_mechanisms.gd) out for judging: a strip of its frames
and GIFs.

    python scripts/godot/mechanism-film-sheet.py <film dir> [--crop=x,y,w,h] [--step=2] [--cols=8]
        [--scale=0.5] [--title=<text>] [--from=<frame>] [--to=<frame>]

Writes into the film dir: strip.png (every `step`-th saved frame, each labelled with its number and
its time on the game's clock, `cols` per row, drawn at `scale` of the cropped picture), film.gif
(game speed: each frame shown for the time to the next saved one, as film.json records it) and
film-slow.gif (a third of that speed). The film saves its frames unevenly (every other step while
things happen, sparsely through a slow winch back), so the times come from film.json, not from
the frame numbers. The crop is in the window's pixels; without one the whole picture is used.
Needs Pillow.
"""
import glob
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    if not args:
        raise SystemExit(__doc__)
    folder = args[0]
    step = int(opts.get("step", 2))
    cols = int(opts.get("cols", 8))
    scale = float(opts.get("scale", 0.5))
    title = opts.get("title", os.path.basename(os.path.normpath(folder)))
    files = sorted(glob.glob(os.path.join(folder, "f[0-9][0-9][0-9].png")))
    with open(os.path.join(folder, "film.json"), encoding="utf-8") as handle:
        film = json.load(handle)
    rows = film.get("rows", [])
    first = int(opts.get("from", 0))
    last = int(opts.get("to", len(files) - 1))
    files = files[first:last + 1]
    if not files:
        raise SystemExit("no frames in " + folder)
    times = [int(rows[first + i]["ms"]) if first + i < len(rows) else 0 for i in range(len(files))]
    frames = [Image.open(f).convert("RGB") for f in files]
    if "crop" in opts:
        x, y, w, h = (int(v) for v in opts["crop"].split(","))
        frames = [f.crop((x, y, x + w, y + h)) for f in frames]

    try:
        font = ImageFont.truetype("arial.ttf", 15)
        big = ImageFont.truetype("arialbd.ttf", 22)
    except OSError:
        font = big = ImageFont.load_default()

    picked = list(range(0, len(frames), step))
    cell = (int(frames[0].width * scale), int(frames[0].height * scale))
    head = 36
    sheet = Image.new("RGB", (cols * cell[0], head + ((len(picked) + cols - 1) // cols) * cell[1]), (24, 24, 28))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 6), "%s   (every %d saved frames)" % (title, step), fill=(255, 255, 255), font=big)
    for n, index in enumerate(picked):
        x = (n % cols) * cell[0]
        y = head + (n // cols) * cell[1]
        sheet.paste(frames[index].resize(cell, Image.LANCZOS), (x, y))
        label = "%d  %d ms" % (first + index, times[index])
        draw.rectangle((x, y + cell[1] - 20, x + 8 * len(label) + 8, y + cell[1]), fill=(0, 0, 0))
        draw.text((x + 4, y + cell[1] - 19), label, fill=(255, 255, 120), font=font)
    sheet.save(os.path.join(folder, "strip.png"))

    # GIFs: each frame lasts until the next saved one (20 ms at least: browsers play nothing faster).
    gif_size = (int(frames[0].width * 0.6), int(frames[0].height * 0.6))
    small = [f.resize(gif_size, Image.LANCZOS).quantize(colors=128, method=Image.MEDIANCUT) for f in frames]
    spans = [max(20, times[i + 1] - times[i]) for i in range(len(times) - 1)] + [600]
    small[0].save(os.path.join(folder, "film.gif"), save_all=True, append_images=small[1:], duration=spans, loop=0)
    small[0].save(os.path.join(folder, "film-slow.gif"), save_all=True, append_images=small[1:],
                  duration=[span * 3 for span in spans], loop=0)
    print("wrote strip.png, film.gif, film-slow.gif in", folder)


if __name__ == "__main__":
    main()
