#!/usr/bin/env python3
"""Draws the HUD console mockup (docs/design/2026-10-07-hud-console-mockup.md).

The HUD is one Diablo-style console at the bottom of the screen: the minimap, the life orb, the
weapon in hand and the ability buttons, the energy orb and the menu buttons, 128 units (2 tiles)
tall, with the 16 x 14 tile play area above it. This tool draws it over real game frames rendered
by `godot/tools/render_hud_mockup.gd` (2 px per game unit):

- `after-window.webp`: the console on an 8:7 window (1170 x 1024 units), just after a hit (the
  life orb shows its number and the damage; the energy orb, unchanged, shows none);
- `after-wide.webp`: the same on a 16:9 window (1820 x 1024 units);
- `weapon-scroll.webp`: the console up close while the weapon carousel is open (a scroll);
- `before-after.webp`: today's HUD and the console side by side, on the same 8:7 window;
- `annotated.webp`: the 8:7 frame with the play area and the console's measures marked.

The art is in `asset/Originals/ui/hud-console/` (Magnific GPT 2.5, 2026-10-07: the orb ring, the
console bar, the slot, the ability and menu icons); the goo inside the orbs, the heart pips, the
coin, the carousel and the text are drawn here. Weapon icons and the minimap come from the game.

Usage: python scripts/art/build-hud-console-mockup.py --frames DIR [--out DIR]
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "godot"
ART = ROOT / "asset/Originals/ui/hud-console"
DEFAULT_OUT = ROOT / "docs/design/hud-console"
S = 2  # px per game unit in the frames

FONT = str(GODOT / "game/ui/theme/fonts/source-sans-3/SourceSans3[wght].ttf")
SYMBOLS = str(GODOT / "game/ui/theme/fonts/noto-sans-symbols-2/NotoSansSymbols2-Regular.ttf")
# ui_tokens.gd
TEXT = (245, 247, 255)
ACCENT = (134, 240, 195)
WARNING = (255, 210, 119)
DANGER = (255, 111, 136)
SURFACE = (16, 26, 49)
BORDER = (59, 92, 120)
OUTLINE = (24, 14, 8)

# Layout in game units. The console sits in the bottom 128 units, centred.
PLAY_W, PLAY_H, CONSOLE_H = 1024, 896, 128
ORB_D = 144           # orb ring width
ORB_CY = 952
BAR_CY = 962
PANEL_H = 62          # the bar's dark panel, which holds the slots
WEAPON_SLOT = 54      # the weapon in hand: one slot (owner, 2026-10-08)
ABILITY_SLOT = 46
SLOT_GAP = 4
GROUP_GAP = 18        # between the weapon and the abilities
BAR_MARGIN = 14       # between an orb's ring and the nearest slot
MINIMAP = 128         # never bigger than the orbs (owner, 2026-10-08)
BUTTONS = 108         # the 2 x 2 menu buttons
BUTTON = 52
SIDE_GAP = 8
SLOTS_W = WEAPON_SLOT + GROUP_GAP + 5 * ABILITY_SLOT + 4 * SLOT_GAP
ORB_DX = (SLOTS_W + 2 * BAR_MARGIN + ORB_D) / 2    # orb centres at cx +- ORB_DX
BAR_W = 2 * ORB_DX + 40                            # its ends tuck behind the orbs
CONSOLE_LEFT = ORB_DX + ORB_D / 2 + SIDE_GAP + MINIMAP
CONSOLE_RIGHT = ORB_DX + ORB_D / 2 + SIDE_GAP + BUTTONS


def U(v: float) -> int:
    return int(round(v * S))


def font(units: float, weight: int = 400) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(FONT, U(units))
    try:
        f.set_variation_by_axes([weight])
    except OSError:
        pass
    return f


def crop_alpha(im: Image.Image, threshold: int = 24) -> Image.Image:
    return im.crop(im.getchannel("A").point(lambda a: 255 if a > threshold else 0).getbbox())


def fit(im: Image.Image, w_units: float, h_units: float) -> Image.Image:
    k = min(U(w_units) / im.width, U(h_units) / im.height)
    return im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)


def faded(im: Image.Image, opacity: float) -> Image.Image:
    out = im.copy()
    out.putalpha(im.getchannel("A").point(lambda a: int(a * opacity)))
    return out


def paste_center(canvas: Image.Image, im: Image.Image, cx: float, cy: float) -> None:
    canvas.alpha_composite(im, (U(cx) - im.width // 2, U(cy) - im.height // 2))


def row_of(path: Path, count: int) -> list[Image.Image]:
    sheet = Image.open(path).convert("RGBA")
    cell = sheet.width / count
    return [crop_alpha(sheet.crop((round(i * cell), 0, round((i + 1) * cell), sheet.height))) for i in range(count)]


def frame_of(path: str, frame: int, size: int, columns: int) -> Image.Image:
    sheet = Image.open(GODOT / path).convert("RGBA")
    x, y = (frame % columns) * size, (frame // columns) * size
    return crop_alpha(sheet.crop((x, y, x + size, y + size)))


RING = crop_alpha(Image.open(ART / "orb-ring.png").convert("RGBA"))
BAR = crop_alpha(Image.open(ART / "console-bar.png").convert("RGBA"))
SLOT_ART = crop_alpha(Image.open(ART / "slot.png").convert("RGBA"))
MENU_ICONS = row_of(ART / "menu-icons-1x4.png", 4)
MINIMAP_FRAME = Image.open(GODOT / "asset/UI/ui-organic-minimap-frame.webp").convert("RGBA")
# The belt in the carousel's order; the Stone Spear is in hand.
BELT = [
    ("Basic Sword", frame_of("asset/MAPS/weapons/120x120_9x2_swordTiles.webp", 0, 120, 9)),
    ("Stone Spear", frame_of("asset/MAPS/weapons/128x128-tile_4x1-stone-tools.webp", 1, 128, 4)),
    ("Stone Pickaxe", frame_of("asset/MAPS/weapons/128x128-tile_4x1-stone-tools.webp", 3, 128, 4)),
    ("Wooden Axe", frame_of("asset/MAPS/weapons/128x128-tile_3x1-wooden-axe.webp", 1, 128, 3)),
]
IN_HAND = 1
# Jump, Dodge, Lash, Slam, Teleport: key label and the state the mockup shows.
ABILITIES = list(zip(row_of(ART / "ability-icons-1x5.png", 5), ["Space", "1", "2", "3", "4"],
                     ["ready", "ready", "ready", "cooldown", "locked"]))
# Hearts on the life orb's ring, in quarters: one whole heart and three quarters of the next.
HEARTS = [4, 3]


def ring_hole(ring: Image.Image) -> tuple[float, float, float]:
    """Centre and radius of the ring's transparent hole, in the ring image's px."""
    a = np.asarray(ring.getchannel("A"))
    h, w = a.shape
    cx, cy = w // 2, int(h * 0.53)
    row, col = a[cy], a[:, cx]
    left = cx - next(i for i in range(cx) if row[cx - i] > 128)
    right = cx + next(i for i in range(w - cx) if row[cx + i] > 128)
    top = cy - next(i for i in range(cy) if col[cy - i] > 128)
    bottom = cy + next(i for i in range(h - cy) if col[cy + i] > 128)
    return (left + right) / 2, (top + bottom) / 2, ((right - left) + (bottom - top)) / 4


def bar_panel(bar: Image.Image) -> tuple[float, float]:
    """Top and bottom of the bar's dark panel as fractions of its height (middle column)."""
    col = np.asarray(bar).astype(int)[:, bar.width // 2]
    rows = [i for i, (r, g, b, al) in enumerate(col) if al > 200 and r < 70 and 40 < g < 110 and b > 40]
    return min(rows) / bar.height, max(rows) / bar.height


PANEL_TOP, PANEL_BOTTOM = bar_panel(BAR)
BAR_H = PANEL_H / (PANEL_BOTTOM - PANEL_TOP)
BAR_IMAGE_CY = BAR_CY - ((PANEL_TOP + PANEL_BOTTOM) / 2 - 0.5) * BAR_H


# --- pieces -----------------------------------------------------------------------------------

def three_slice(im: Image.Image, w_units: float, h_units: float, cap: float = 0.2) -> Image.Image:
    """Keeps the ends, stretches the middle."""
    k = U(h_units) / im.height
    cap_px = round(im.width * cap)
    cw = round(cap_px * k)
    out = Image.new("RGBA", (U(w_units), U(h_units)))
    out.alpha_composite(im.crop((0, 0, cap_px, im.height)).resize((cw, out.height), Image.LANCZOS), (0, 0))
    mid = im.crop((cap_px, 0, im.width - cap_px, im.height)).resize((out.width - 2 * cw, out.height), Image.LANCZOS)
    out.alpha_composite(mid, (cw, 0))
    right = im.crop((im.width - cap_px, 0, im.width, im.height)).resize((cw, out.height), Image.LANCZOS)
    out.alpha_composite(right, (out.width - cw, 0))
    return out


def goo(size: int, radius: float, level: float, top, bottom, rim, seed: int) -> Image.Image:
    """A glass globe filled with goo up to `level` (0..1), size x size px."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    c, r = size / 2, radius
    dx, dy = xx - c, yy - c
    d = np.hypot(dx, dy)
    surf = c + r - 2 * r * level + np.sin(xx / r * 5.0 + seed) * 0.025 * r + np.sin(xx / r * 1.7) * 0.02 * r
    liquid = yy >= surf
    t = np.clip((yy - (c - r)) / (2 * r), 0, 1)[..., None]
    rgb = np.array(top) * (1 - t) + np.array(bottom) * t
    rgb *= (1 - 0.5 * np.clip(d / r, 0, 1) ** 3)[..., None]
    rgb *= (1 + 0.22 * np.clip(-(dx + dy) / (r * 1.4), -1, 1))[..., None]
    glass = np.array([20.0, 27.0, 30.0]) * (1 - 0.35 * np.clip(d / r, 0, 1) ** 2)[..., None]
    out = np.where(liquid[..., None], rgb, glass)
    meniscus = np.abs(yy - surf) < r * 0.04
    out[meniscus] = out[meniscus] * 0.35 + np.array(rim) * 0.65
    for _ in range(14):
        bx, by = c + rng.uniform(-0.7, 0.7) * r, c + rng.uniform(-0.2, 0.85) * r
        br = rng.uniform(0.025, 0.07) * r
        bubble = (np.abs(np.hypot(xx - bx, yy - by) - br) < max(1.0, br * 0.25)) & liquid & (d < r * 0.9)
        out[bubble] = out[bubble] * 0.4 + np.array(rim) * 0.6
    hl = np.exp(-(((xx - (c - 0.36 * r)) / (0.30 * r)) ** 2 + ((yy - (c - 0.42 * r)) / (0.17 * r)) ** 2))
    out = out * (1 - 0.55 * hl[..., None]) + 255 * 0.55 * hl[..., None]
    alpha = np.where(liquid, 255.0, 225.0) * np.clip(r - d + 0.5, 0, 1)
    return Image.fromarray(np.dstack([np.clip(out, 0, 255), alpha]).astype(np.uint8), "RGBA")


def heart(size_px: int, quarters: int) -> Image.Image:
    """A heart pip with `quarters` of 4 filled, clockwise from the top left."""
    big = size_px * 4

    def shape(col):
        im = Image.new("RGBA", (big, big))
        d = ImageDraw.Draw(im)
        r = big * 0.27
        d.ellipse((big * 0.04, big * 0.08, big * 0.04 + 2 * r, big * 0.08 + 2 * r), fill=col)
        d.ellipse((big * 0.96 - 2 * r, big * 0.08, big * 0.96, big * 0.08 + 2 * r), fill=col)
        d.polygon([(big * 0.06, big * 0.42), (big * 0.94, big * 0.42), (big * 0.5, big * 0.95)], fill=col)
        return im

    base = shape((255, 236, 220, 255))
    inner_size = (round(big * 0.74), round(big * 0.74))
    at = (round(big * 0.13), round(big * 0.1))
    base.alpha_composite(shape((40, 22, 26, 255)).resize(inner_size, Image.LANCZOS), at)
    full = shape((255, 92, 110, 255)).resize(inner_size, Image.LANCZOS)
    w, h = full.size
    mid_x, mid_y = w // 2, round(h * 0.45)
    boxes = [(0, 0, mid_x, mid_y), (mid_x, 0, w, mid_y), (mid_x, mid_y, w, h), (0, mid_y, mid_x, h)]
    mask = Image.new("L", full.size)
    for box in boxes[:quarters]:
        ImageDraw.Draw(mask).rectangle(box, fill=255)
    full.putalpha(Image.composite(full.getchannel("A"), Image.new("L", full.size), mask))
    base.alpha_composite(full, at)
    if 0 < quarters < 4:
        d = ImageDraw.Draw(base)
        line = (255, 236, 220, 200)
        d.line((at[0] + mid_x, at[1] + big * 0.05, at[0] + mid_x, at[1] + h * 0.92), fill=line, width=max(1, big // 40))
        d.line((at[0] + w * 0.04, at[1] + mid_y, at[0] + w * 0.96, at[1] + mid_y), fill=line, width=max(1, big // 40))
    return base.resize((size_px, size_px), Image.LANCZOS)


def key_badge(d: ImageDraw.ImageDraw, right: int, bottom: int, key: str) -> None:
    f = font(9.5, 700)
    w = max(13.0, d.textlength(key, font=f) / S + 6)
    x0, y0 = right - U(w), bottom - U(12)
    d.rounded_rectangle((x0, y0, right, bottom), radius=U(3), fill=SURFACE + (235,), outline=BORDER + (255,), width=U(1))
    d.text(((x0 + right) // 2, (y0 + bottom) // 2), key, font=f, fill=TEXT, anchor="mm")


def slot(size: float, icon: Image.Image | None, state: str = "ready", key: str = "") -> Image.Image:
    pad = 8
    im = Image.new("RGBA", (U(size + 2 * pad), U(size + 2 * pad)))
    o = U(pad)
    im.alpha_composite(SLOT_ART.resize((U(size), U(size)), Image.LANCZOS), (o, o))
    d = ImageDraw.Draw(im)
    if icon is not None and state != "locked":
        # A soft warm light behind the icon, so dark weapon sprites read on the teal panel.
        glow = Image.new("L", im.size)
        ImageDraw.Draw(glow).ellipse((o + U(7), o + U(7), o + U(size - 7), o + U(size - 7)), fill=110)
        light = Image.new("RGBA", im.size, (255, 236, 196, 0))
        light.putalpha(glow.filter(ImageFilter.GaussianBlur(U(5))))
        im.alpha_composite(light)
    if icon is not None:
        ic = fit(icon, size * 0.8, size * 0.8)
        if state == "locked":
            gray = ic.convert("LA").convert("RGBA")
            ic = Image.blend(Image.new("RGBA", gray.size), gray, 0.45)
            ic.putalpha(gray.getchannel("A").point(lambda a: int(a * 0.7)))
        im.alpha_composite(ic, (im.width // 2 - ic.width // 2, im.height // 2 - ic.height // 2))
    if state == "cooldown":
        sweep = Image.new("RGBA", im.size)
        box = (o + U(4), o + U(4), o + U(size - 4), o + U(size - 4))
        ImageDraw.Draw(sweep).pieslice((box[0] - U(6), box[1] - U(6), box[2] + U(6), box[3] + U(6)), -90, 133,
                                       fill=(8, 12, 20, 150))
        mask = Image.new("L", im.size)
        ImageDraw.Draw(mask).rounded_rectangle(box, radius=U(6), fill=255)
        sweep.putalpha(Image.composite(sweep.getchannel("A"), Image.new("L", im.size), mask))
        im.alpha_composite(sweep)
        d.text((im.width // 2, im.height // 2), "1.3", font=font(15, 700), fill=TEXT, anchor="mm",
               stroke_width=U(1.5), stroke_fill=OUTLINE)
    if key:
        key_badge(d, o + U(size - 2), o + U(size - 2), key)
    return im


def menu_button(icon: Image.Image, key: str) -> Image.Image:
    im = Image.new("RGBA", (U(BUTTON), U(BUTTON)))
    im.alpha_composite(SLOT_ART.resize(im.size, Image.LANCZOS))
    ic = fit(icon, BUTTON * 0.66, BUTTON * 0.66)
    im.alpha_composite(ic, (im.width // 2 - ic.width // 2, im.height // 2 - ic.height // 2 - U(2)))
    if key:
        key_badge(ImageDraw.Draw(im), U(BUTTON - 3), U(BUTTON - 3), key)
    return im


def minimap_art(content: Image.Image) -> Image.Image:
    """Today's minimap content inside the organic minimap frame, MINIMAP units square."""
    out = Image.new("RGBA", (U(MINIMAP), U(MINIMAP)))
    inner = U(MINIMAP * 0.78)
    out.alpha_composite(content.resize((inner, inner), Image.LANCZOS), ((out.width - inner) // 2,) * 2)
    out.alpha_composite(MINIMAP_FRAME.resize(out.size, Image.LANCZOS))
    return out


def pill(d: ImageDraw.ImageDraw, box_units, alpha: int = 200) -> None:
    d.rounded_rectangle(tuple(U(v) for v in box_units), radius=U(9), fill=SURFACE + (alpha,), outline=BORDER + (200,),
                        width=U(1))


def coin(size_units: float) -> Image.Image:
    n = U(size_units) * 4
    im = Image.new("RGBA", (n, n))
    d = ImageDraw.Draw(im)
    d.ellipse((0, 0, n - 1, n - 1), fill=(150, 96, 20, 255))
    d.ellipse((n * 0.08, n * 0.08, n * 0.92, n * 0.92), fill=(250, 196, 70, 255))
    d.ellipse((n * 0.24, n * 0.24, n * 0.76, n * 0.76), outline=(196, 130, 30, 255), width=round(n * 0.07))
    d.ellipse((n * 0.2, n * 0.14, n * 0.42, n * 0.3), fill=(255, 240, 190, 200))
    return im.resize((U(size_units), U(size_units)), Image.LANCZOS)


# --- the screen -------------------------------------------------------------------------------

def weapon_x(cx: float) -> float:
    return cx - SLOTS_W / 2 + WEAPON_SLOT / 2


def draw_carousel(canvas: Image.Image, cx: float) -> None:
    """The weapon carousel a scroll opens over the weapon slot: the belt slides by one weapon per
    scroll, the one now in hand full and the others faded; it fades out a moment after the last
    scroll. Drawn mid-slide, with the Stone Spear arriving from the right."""
    x0, cy, step = weapon_x(cx), 828, 54
    width = step * 4 + 44
    back = Image.new("RGBA", (U(width), U(64)))
    fade = np.clip(1 - np.abs(np.linspace(-1, 1, back.width)) ** 4, 0, 1) * 215
    mask = Image.new("L", back.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, back.width - 1, back.height - 1), radius=U(32), fill=255)
    back.paste(SURFACE + (255,), (0, 0, back.width, back.height))
    back.putalpha(Image.fromarray(((np.asarray(mask) / 255.0) * fade[None, :]).astype(np.uint8), "L"))
    paste_center(canvas, back, x0, cy)
    slide = 8  # units still to travel to the left
    for offset in (-2, 2, -1, 1, 0):
        name, icon = BELT[(IN_HAND + offset) % len(BELT)]
        opacity = {0: 1.0, 1: 0.6, -1: 0.6, 2: 0.25, -2: 0.25}[abs(offset) * (1 if offset >= 0 else -1)]
        cell = slot(48 if offset == 0 else 40, icon)
        x = x0 + offset * step + slide
        if offset != 0:
            paste_center(canvas, faded(cell, opacity * 0.35), x + 5, cy)
        paste_center(canvas, faded(cell, opacity), x, cy)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((U(x0 + slide - 26), U(cy - 26), U(x0 + slide + 26), U(cy + 26)), radius=U(9),
                        outline=WARNING, width=U(2.5))
    d.text((U(x0), U(cy - 42)), BELT[IN_HAND][0], font=font(13, 700), fill=TEXT, anchor="mm",
           stroke_width=U(1.5), stroke_fill=OUTLINE)


def draw_console(canvas: Image.Image, cx: float, minimap: Image.Image, hit: bool) -> None:
    # A soft shade under the console so it reads as one panel over any ground.
    ys = np.arange(canvas.height) / S
    shade = np.clip((ys - 872) / (1024 - 872), 0, 1) ** 1.4 * 150
    tint = Image.new("RGBA", canvas.size, (10, 14, 10, 0))
    tint.putalpha(Image.fromarray(np.repeat(shade[:, None], canvas.width, axis=1).astype(np.uint8), "L"))
    canvas.alpha_composite(tint)

    paste_center(canvas, three_slice(BAR, BAR_W, BAR_H), cx, BAR_IMAGE_CY)
    paste_center(canvas, slot(WEAPON_SLOT, BELT[IN_HAND][1], key="E"), weapon_x(cx), BAR_CY)
    x = weapon_x(cx) + WEAPON_SLOT / 2 + GROUP_GAP + ABILITY_SLOT / 2
    for icon, key, state in ABILITIES:
        paste_center(canvas, slot(ABILITY_SLOT, icon, state, key), x, BAR_CY)
        x += ABILITY_SLOT + SLOT_GAP

    hx, hy, hr = ring_hole(RING)
    k = U(ORB_D) / RING.width
    ring = RING.resize((U(ORB_D), round(RING.height * k)), Image.LANCZOS)
    hole_r = hr * k
    d = ImageDraw.Draw(canvas)
    for side, level, top, bottom, rim, value, seed in (
        (-1, 0.78, (255, 128, 120), (150, 24, 48), (255, 196, 186), "78" if hit else "", 3),   # life
        (1, 0.55, (255, 224, 128), (200, 116, 18), (255, 242, 196), "", 7),                     # energy
    ):
        ocx = cx + side * ORB_DX
        size = round(hole_r * 2 + 8)
        gx = U(ocx) - ring.width // 2 + round(hx * k) - size // 2
        gy = U(ORB_CY) - ring.height // 2 + round(hy * k) - size // 2
        canvas.alpha_composite(goo(size, hole_r + 3, level, top, bottom, rim, seed), (gx, gy))
        canvas.alpha_composite(ring, (U(ocx) - ring.width // 2, U(ORB_CY) - ring.height // 2))
        if value:
            # The number shows only when the value changes (owner, 2026-10-08), with the change.
            d.text((gx + size // 2, gy + size // 2 + U(2)), value, font=font(26, 800), fill=TEXT, anchor="mm",
                   stroke_width=U(2), stroke_fill=OUTLINE)
            d.text((U(ocx + 46), U(ORB_CY - 76)), "−12", font=font(20, 800), fill=DANGER, anchor="mm",
                   stroke_width=U(2), stroke_fill=OUTLINE)
        if side == -1:
            pip_r = hole_r / S + 8
            for i, quarters in enumerate(HEARTS):
                ang = math.radians(142 + i * 27)
                paste_center(canvas, heart(U(18), quarters), ocx + pip_r * math.cos(ang),
                             ORB_CY - pip_r * math.sin(ang) + 2)

    canvas.alpha_composite(minimap_art(minimap), (U(cx - CONSOLE_LEFT), U(BAR_CY - MINIMAP / 2)))
    bx = cx + ORB_DX + ORB_D / 2 + SIDE_GAP
    for i, key in enumerate(("B", "J", "M", "Esc")):    # bag, journal, map, menu
        canvas.alpha_composite(menu_button(MENU_ICONS[i], key),
                               (U(bx + (i % 2) * (BUTTON + 4)), U(BAR_CY - BUTTONS / 2 + (i // 2) * (BUTTON + 4))))


def draw_top_left(canvas: Image.Image) -> None:
    d = ImageDraw.Draw(canvas)
    pill(d, (14, 12, 92, 40))
    canvas.alpha_composite(coin(18), (U(22), U(17)))
    d.text((U(46), U(26)), "50", font=font(17, 700), fill=TEXT, anchor="lm")
    title, goal = "A Place to Work", "Talk to Village Elder Plop"
    w = max(d.textlength(title.upper(), font=font(10.5, 700)), d.textlength(goal, font=font(14, 600))) / S + 13
    pill(d, (14, 46, 14 + w + 22, 92))
    d.text((U(25), U(58)), title.upper(), font=font(10.5, 700), fill=ACCENT, anchor="lm")
    d.text((U(25), U(77)), "▸", font=ImageFont.truetype(SYMBOLS, U(13)), fill=ACCENT, anchor="lm")
    d.text((U(38), U(77)), goal, font=font(14, 600), fill=TEXT, anchor="lm")


def draw_toast(canvas: Image.Image, cx: float) -> None:
    d = ImageDraw.Draw(canvas)
    msg, f = "Press B, then Crafting, to craft", font(15, 700)
    w = d.textlength(msg, font=f) / S + 36
    pill(d, (cx - w / 2, 836, cx + w / 2, 864), alpha=215)
    d.text((U(cx), U(850)), msg, font=f, fill=TEXT, anchor="mm")


def compose(frame: Image.Image, minimap: Image.Image, scroll: bool = False) -> Image.Image:
    canvas = frame.convert("RGBA")
    cx = canvas.width / S / 2
    draw_console(canvas, cx, minimap, hit=not scroll)
    draw_top_left(canvas)
    if scroll:
        draw_carousel(canvas, cx)
    else:
        draw_toast(canvas, cx)
    return canvas.convert("RGB")


def caption(im: Image.Image, text: str) -> Image.Image:
    bar = 56
    out = Image.new("RGB", (im.width, im.height + bar), (11, 16, 32))
    out.paste(im, (0, bar))
    ImageDraw.Draw(out).text((20, bar // 2), text, font=ImageFont.truetype(FONT, 26), fill=TEXT, anchor="lm")
    return out


def before_after(before: Image.Image, after: Image.Image) -> Image.Image:
    """Both on the same 8:7 window, at 1 px per unit of the console's view."""
    size = (after.width // S, after.height // S)
    left = caption(before.convert("RGB").resize(size, Image.LANCZOS), "Today: base 1024 x 896, HUD over the 16 x 14 tiles")
    right = caption(after.resize(size, Image.LANCZOS), "Console: base 1024 x 1024, 16 x 14 tiles clear above it")
    out = Image.new("RGB", (left.width * 2 + 24, left.height), (11, 16, 32))
    out.paste(left, (0, 0))
    out.paste(right, (left.width + 24, 0))
    return out


def dashed_rect(d: ImageDraw.ImageDraw, box, color, width: int, dash: int = 14) -> None:
    x0, y0, x1, y1 = box
    for (ax, ay, bx, by) in ((x0, y0, x1, y0), (x1, y0, x1, y1), (x1, y1, x0, y1), (x0, y1, x0, y0)):
        length = math.hypot(bx - ax, by - ay)
        for s in range(0, int(length), dash * 2):
            e = min(length, s + dash)
            d.line((ax + (bx - ax) * s / length, ay + (by - ay) * s / length,
                    ax + (bx - ax) * e / length, ay + (by - ay) * e / length), fill=color, width=width)


def annotated(after: Image.Image) -> Image.Image:
    im = after.resize((after.width // S, after.height // S), Image.LANCZOS).convert("RGBA")
    over = Image.new("RGBA", im.size)
    d = ImageDraw.Draw(over)
    cx = im.width / 2
    play = (cx - PLAY_W / 2, 0, cx + PLAY_W / 2, PLAY_H)
    for x0, x1 in ((0, play[0]), (play[2], im.width)):
        d.rectangle((x0, 0, x1, PLAY_H), fill=(11, 16, 32, 90))
    dashed_rect(d, play, ACCENT + (255,), 3)
    dashed_rect(d, (cx - CONSOLE_LEFT, PLAY_H, cx + CONSOLE_RIGHT, PLAY_H + CONSOLE_H - 1), WARNING + (255,), 3, 10)
    f = ImageFont.truetype(FONT, 17)
    f.set_variation_by_axes([700])
    width = round(CONSOLE_LEFT + CONSOLE_RIGHT)
    for (x, y, text, col) in (
        (cx, 200, "Play area: 16 x 14 tiles (1024 x 896); the slime stays in its middle", ACCENT),
        (cx, 224, "only the goal line (top left) and short messages sit on it", ACCENT),
        (cx, 248, "shaded sides: extra columns a wider window shows", TEXT),
        (cx, PLAY_H - 110, f"Console: {width} x 128 (2 tiles); the orb tops rise 20 units", WARNING),
    ):
        w = d.textlength(text, font=f)
        d.rounded_rectangle((x - w / 2 - 8, y - 12, x + w / 2 + 8, y + 12), radius=6, fill=(11, 16, 32, 200))
        d.text((x, y), text, font=f, fill=col + (255,), anchor="mm")
    im.alpha_composite(over)
    return im.convert("RGB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--frames", type=Path, required=True, help="render_hud_mockup.gd's --out folder")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    before = Image.open(args.frames / "before.png")
    # Today's minimap box is 180 units at (16, 700) on the 1024 x 896 view (map spec); its own frame
    # covers the box edge, so take the inside.
    minimap = before.convert("RGBA").crop((U(26), U(710), U(186), U(870)))
    frame = Image.open(args.frames / "frame-window.png")
    window = compose(frame, minimap)
    scroll = compose(frame, minimap, scroll=True)
    cx = scroll.width // 2
    outputs = {
        "after-window.webp": window,
        "after-wide.webp": compose(Image.open(args.frames / "frame-wide.png"), minimap),
        "weapon-scroll.webp": scroll.crop((cx - U(CONSOLE_LEFT + 16), U(770), cx + U(CONSOLE_RIGHT + 16), scroll.height)),
        "before-after.webp": before_after(before, window),
        "annotated.webp": annotated(window),
    }
    for name, im in outputs.items():
        im.save(args.out / name, quality=86, method=6)
        print(f"{args.out / name}  {im.width} x {im.height}")


if __name__ == "__main__":
    main()
