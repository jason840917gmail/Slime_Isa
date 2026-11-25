# A GIF from frames filmed in the running game (godot/tools/render_door_walk.gd): a crop of every
# frame at the game's own size, one palette for the whole clip.
#   python asset/Originals/cave-animals/tools/game_gif.py <frames dir> <out.gif> <x0,y0,x1,y1> [ms per frame] [colours]
import glob
import sys

from PIL import Image

frames_dir, out = sys.argv[1], sys.argv[2]
box = tuple(int(v) for v in sys.argv[3].split(","))
ms = int(sys.argv[4]) if len(sys.argv) > 4 else 100
colours = int(sys.argv[5]) if len(sys.argv) > 5 else 96
frames = [Image.open(f).convert("RGB").crop(box) for f in sorted(glob.glob(frames_dir + "/frame-*.png"))]
# One palette from a strip of a few frames, so colours do not flicker from frame to frame.
picks = frames[:: max(1, len(frames) // 6)]
strip = Image.new("RGB", (picks[0].width, picks[0].height * len(picks)))
for index, frame in enumerate(picks):
    strip.paste(frame, (0, index * frame.height))
palette = strip.quantize(colors=colours, method=Image.MEDIANCUT, dither=Image.NONE)
mapped = [frame.quantize(palette=palette, dither=Image.NONE) for frame in frames]
mapped[0].save(out, save_all=True, append_images=mapped[1:], duration=ms, loop=0, optimize=True)
print(out, len(frames), frames[0].size)
