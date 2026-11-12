import sys, glob, math
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
S = sys.argv[1] + '/'
O = 'asset/Originals/sky/generated/'
sys.path.insert(0, S)
from island_mask import island_mask

def rgb(p): return Image.open(p).convert('RGB')
def copy_rect(im, src, dst_xy):
    im.paste(im.crop(src), dst_xy)

# --- main island: r3 (daylight) ---
r3p = sorted(glob.glob(S + 'r_2300_2500/*.png'))[-1]
r3 = rgb(r3p)
copy_rect(r3, (270, 556, 430, 892), (110, 556))     # stairs -> wall
copy_rect(r3, (1155, 750, 1245, 850), (975, 750))      # ghost slime -> wall
copy_rect(r3, (420, 0, 820, 175), (0, 0))            # quest panel -> grass
r3.save(S + 'r3_patched.png')
m3 = island_mask(S + 'r3_patched.png', [(1000, 1100), (1500, 1000), (400, 1300)], S + 'm3.png', S + 'm3_dbg.png')
m3 = np.asarray(m3).copy(); m3[:, 1400:] = 0; m3[910:, :] = 0
main = r3.crop((0, 0, 1400, 910)); main_a = Image.fromarray(m3[:910, :1400])

# --- second island: r1 left hill, colour-matched to r3 ---
r1 = rgb(S + 'render1/f00000049.png')
copy_rect(r1, (935, 420, 1095, 680), (775, 420))
r1.save(S + 'r1_patched.png')
m1 = island_mask(S + 'r1_patched.png', [(1000, 1000), (1500, 300), (1550, 1100), (100, 300)], S + 'm1.png')
m1 = np.asarray(m1).copy(); m1[:, 1450:] = 0; m1[700:, :] = 0; m1[:, :250] = 0
a1 = np.asarray(r1).astype(np.float32); a3 = np.asarray(r3).astype(np.float32)
sel1 = m1 > 128; sel3 = m3 > 128
out = a1.copy()
for c in range(3):
    src = a1[..., c][sel1]; ref = a3[:910, :1400, c][sel3[:910, :1400]]
    qs = np.linspace(0, 100, 101)
    sp = np.percentile(src, qs); rp = np.percentile(ref, qs)
    out[..., c] = np.interp(a1[..., c], sp, rp)
r1c = Image.fromarray(out.clip(0, 255).astype(np.uint8))
second = r1c.crop((250, 0, 1450, 700)); second_a = Image.fromarray(m1[:700, 250:1450])

# --- art ---
far = Image.open(O + 'far-ground-a-seamless.png').convert('RGB')
far = far.resize((512, 512), Image.LANCZOS)
fa = np.asarray(far).astype(np.float32)
fa = fa * 0.78 + np.array([70, 120, 130]) * 0.22   # height haze
far = Image.fromarray(fa.clip(0, 255).astype(np.uint8))
def cloud(name, scale, tint=0.18):
    im = Image.open(O + name + '.png').convert('RGBA')
    im = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32)
    a[..., :3] = a[..., :3] * (1 - tint) + np.array([236, 236, 248]) * tint
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), 'RGBA')
low = cloud('clouds-big-b', 1.15)
mid = cloud('clouds-big-a', 0.85)
wisp = cloud('clouds-wisps-a', 0.9, 0.1)
wa = np.asarray(wisp).copy(); wa[..., 3] = (wa[..., 3] * 0.75).astype(np.uint8); wisp = Image.fromarray(wa, 'RGBA')

br = Image.open(O + 'rope-bridge-a.png').convert('RGBA')
al = np.asarray(br)[..., 3]; rows = np.where(al.max(1) > 128)[0]; cols = np.where(al.max(0) > 128)[0]
br = br.crop((cols[0], rows[0], cols[-1] + 1, rows[-1] + 1))
bh = 150; br = br.resize((int(br.width * bh / br.height), bh), Image.LANCZOS)
def bridge(length):
    end = 170
    left = br.crop((0, 0, end, bh)); right = br.crop((br.width - end, 0, br.width, bh))
    midseg = br.crop((end, 0, br.width - end, bh))
    out = Image.new('RGBA', (length, bh)); x = end
    while x < length - end:
        out.alpha_composite(midseg.crop((0, 0, min(midseg.width, length - end - x), bh)), (x, 0)); x += midseg.width
    out.alpha_composite(left, (0, 0)); out.alpha_composite(right, (length - end, 0))
    return out

sl = Image.open('godot/asset/characters/256x256-tile_8x8-slime-v2-page-1.webp').convert('RGBA').crop((0, 0, 256, 256))
sl = sl.crop(sl.getchannel('A').getbbox()); sh = 92; sl = sl.resize((int(sl.width * sh / sl.height), sh), Image.LANCZOS)

# --- world canvas (island layer, scroll 1.0) ---
W, H = 3300, 1900
world = Image.new('RGBA', (W, H), (0, 0, 0, 0))
main_rgba = main.convert('RGBA'); main_rgba.putalpha(main_a)
sec_rgba = second.convert('RGBA'); sec_rgba.putalpha(second_a)
SEC_X = 1880
world.alpha_composite(main_rgba, (0, 0))
world.alpha_composite(sec_rgba, (SEC_X, 0))
b = bridge(SEC_X + 150 - 1215)
world.alpha_composite(b, (1215, 250 - bh // 2))
world.alpha_composite(sl, (1120 - sl.width // 2, 265 - sh))

def tiled(layer, ox, oy, w, h):
    out = Image.new(layer.mode, (w, h))
    tw, th = layer.size
    ox %= tw; oy %= th
    for y in range(-int(oy), h, th):
        for x in range(-int(ox), w, tw):
            if layer.mode == 'RGBA': out.alpha_composite(layer, (x, y)) if x >= 0 and y >= 0 else out.paste(layer, (x, y), layer)
            else: out.paste(layer, (x, y))
    return out

VW, VH = 1600, 1000
LAYERS = [  # (image, scroll factor, drift px/s)
    (far, 0.20, (0, 0)),
    (low, 0.45, (10, 2)),
    (mid, 0.62, (18, 3)),
    (wisp, 0.80, (34, 5)),
]
def frame(cx, cy, t):
    img = tiled(LAYERS[0][0], cx * LAYERS[0][1], cy * LAYERS[0][1], VW, VH).convert('RGBA')
    for layer, f, (dx, dy) in LAYERS[1:]:
        img.alpha_composite(tiled(layer, cx * f - dx * t, cy * f - dy * t, VW, VH))
    img.alpha_composite(world.crop((int(cx), int(cy), int(cx) + VW, int(cy) + VH)))
    return img

hero = frame(740, 140, 0.0)
hero.save(S + 'mockup_still.png')
frames = []
N = 72
for i in range(N):
    u = i / N
    e = 0.5 - 0.5 * math.cos(2 * math.pi * u)        # there and back
    cx = 80 + e * 1250; cy = 20 + e * 520 * math.sin(math.pi * e)
    frames.append(frame(cx, cy, i / 15.0).convert('RGB').resize((800, 500), Image.LANCZOS))
frames[0].save(S + 'mockup_parallax.webp', save_all=True, append_images=frames[1:], duration=66, loop=0, quality=85)
pal = [f.quantize(colors=255, method=Image.Quantize.MEDIANCUT) for f in frames]
pal[0].save(S + 'mockup_parallax.gif', save_all=True, append_images=pal[1:], duration=66, loop=0, optimize=False)
print('done')
