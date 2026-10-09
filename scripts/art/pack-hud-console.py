#!/usr/bin/env python3
"""Packs the HUD console art (docs/design/2026-10-07-hud-console-mockup.md) for the game.

Reads the generated art in `asset/Originals/ui/hud-console/` and writes runtime images into
`godot/asset/UI/hud-console/` at 2 px per game unit:

- `orb-ring.webp`: the orb's wooden ring (its hole is transparent), 288 px wide (144 units);
- `console-bar.webp`: the wooden bar under the slots, 256 px tall; its ends are drawn as they are
  and its middle stretches (a NinePatchRect, see `game/ui/console/hud_console.gd`);
- `slot.webp`: the square slot frame, 128 px;
- `ability-<id>.webp`: one icon per ability (96 px), by the ability ids of
  `game/player/abilities/ability_definitions.gd`: the five of `ability-icons-1x5.png`, and one
  file per later ability (`ability-<id>.png`, e.g. swallow, 2026-10-09);
- `menu-<id>.webp`: the bag, journal, map and menu icons (96 px).

It prints the measures the console script keeps as constants (the ring's hole, the bar's panel
and end widths): rerun it and update them when the art changes.

Usage: python scripts/art/pack-hud-console.py
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "asset/Originals/ui/hud-console"
OUT = ROOT / "godot/asset/UI/hud-console"
RING_PX = 288
BAR_HEIGHT_PX = 256
BAR_CAP = 0.2          # the share of the bar's width at each end kept unstretched
SLOT_PX = 128
ICON_PX = 96
ABILITIES = ["jump", "dodge", "stretch-lash", "squash-slam", "teleport"]
## Abilities added after the first row, one source image each.
LATER_ABILITIES = ["swallow"]
MENU = ["bag", "journal", "map", "menu"]


def crop_alpha(im: Image.Image, threshold: int = 24) -> Image.Image:
    return im.crop(im.getchannel("A").point(lambda a: 255 if a > threshold else 0).getbbox())


def row_of(path: Path, count: int) -> list[Image.Image]:
    sheet = Image.open(path).convert("RGBA")
    cell = sheet.width / count
    return [crop_alpha(sheet.crop((round(i * cell), 0, round((i + 1) * cell), sheet.height))) for i in range(count)]


def square(im: Image.Image, size: int) -> Image.Image:
    k = size / max(im.size)
    fitted = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", (size, size))
    out.alpha_composite(fitted, ((size - fitted.width) // 2, (size - fitted.height) // 2))
    return out


def save(im: Image.Image, name: str) -> None:
    im.save(OUT / name, lossless=True, method=6)
    print(f"{name}: {im.width} x {im.height}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    ring = crop_alpha(Image.open(SOURCE / "orb-ring.png").convert("RGBA"))
    ring = ring.resize((RING_PX, round(ring.height * RING_PX / ring.width)), Image.LANCZOS)
    save(ring, "orb-ring.webp")
    a = np.asarray(ring.getchannel("A"))
    cx, cy = ring.width // 2, int(ring.height * 0.53)
    left = cx - next(i for i in range(cx) if a[cy, cx - i] > 128)
    right = cx + next(i for i in range(ring.width - cx) if a[cy, cx + i] > 128)
    top = cy - next(i for i in range(cy) if a[cy - i, cx] > 128)
    bottom = cy + next(i for i in range(ring.height - cy) if a[cy + i, cx] > 128)
    print(f"  ring hole: centre ({(left + right) / 2:.1f}, {(top + bottom) / 2:.1f}) px, "
          f"radius {((right - left) + (bottom - top)) / 4:.1f} px")

    bar = crop_alpha(Image.open(SOURCE / "console-bar.png").convert("RGBA"))
    bar = bar.resize((round(bar.width * BAR_HEIGHT_PX / bar.height), BAR_HEIGHT_PX), Image.LANCZOS)
    save(bar, "console-bar.webp")
    col = np.asarray(bar).astype(int)[:, bar.width // 2]
    rows = [i for i, (r, g, b, al) in enumerate(col) if al > 200 and r < 70 and 40 < g < 110 and b > 40]
    print(f"  bar: panel rows {min(rows)}-{max(rows)} of {bar.height} px, end width {round(bar.width * BAR_CAP)} px")

    save(square(crop_alpha(Image.open(SOURCE / "slot.png").convert("RGBA")), SLOT_PX), "slot.webp")
    for name, icon in zip(ABILITIES, row_of(SOURCE / "ability-icons-1x5.png", 5)):
        save(square(icon, ICON_PX), f"ability-{name}.webp")
    for name in LATER_ABILITIES:
        icon = crop_alpha(Image.open(SOURCE / f"ability-{name}.png").convert("RGBA"))
        save(square(icon, ICON_PX), f"ability-{name}.webp")
    for name, icon in zip(MENU, row_of(SOURCE / "menu-icons-1x4.png", 4)):
        save(square(icon, ICON_PX), f"menu-{name}.webp")


if __name__ == "__main__":
    main()
