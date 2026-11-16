"""Packs the pictures made for a cliff's face in each wall style (docs/godot/SKINS.md "Balconies",
docs/godot/DUNGEONS.md "Holes and hatches"): the balcony, the cave mouth and the wall hole, generated
with Magnific (GPT 2.5, transparent background) and kept in asset/Originals/elevation/balcony/ and
asset/Originals/elevation/wall-doors/ as <kind>-<style>-<take>.png.

    python scripts/art/pack-wall-pictures.py <kind>-<style>-<take>[@<style>] [...] [--preview=<png>]

(`@<style>` names the style of a source whose name does not end in a one-word take: the meadow rock
balcony is `balcony-meadow-rock-open-a@meadow-rock`.)

Each source is cleaned (the faint alpha the transparent generation leaves round it cleared), cropped
to its art and scaled to its kind's width (balcony 512 px, cave mouth 320, wall hole 224), and saved
as lossless webp in godot/asset/MAPS/objects/<kind>-<style>.webp. For a balcony it prints its back
edge's row (the first row where the art is wider than 60% of its width), for
game/world/elevation/wall_pictures.gd BALCONY_BACKS. `--preview` writes the packed pictures side by
side on a plain backdrop.
"""
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = {
    "balcony": ROOT / "asset/Originals/elevation/balcony",
    "cave-mouth": ROOT / "asset/Originals/elevation/wall-doors",
    "wall-hole": ROOT / "asset/Originals/elevation/wall-doors",
}
OUT = ROOT / "godot/asset/MAPS/objects"
WIDTHS = {"balcony": 512, "cave-mouth": 320, "wall-hole": 224}
# alpha under this is the generation's faint fringe, not art
FAINT = 16
BACK_SHARE = 0.6
BACK_ALPHA = 128


def kind_of(name: str) -> str:
    for kind in WIDTHS:
        if name.startswith(kind + "-"):
            return kind
    raise SystemExit(f"{name}: not a balcony-, cave-mouth- or wall-hole- source")


def style_of(name: str, kind: str) -> str:
    # <kind>-<style>-<take>: the take is the last part
    return name[len(kind) + 1:].rsplit("-", 1)[0]


def pack(arg: str) -> tuple[Image.Image, str, str]:
    name, _, style = arg.partition("@")
    kind = kind_of(name)
    style = style or style_of(name, kind)
    source = SOURCES[kind] / f"{name}.png"
    rgba = np.array(Image.open(source).convert("RGBA"))
    rgba[rgba[:, :, 3] < FAINT] = 0
    ys, xs = np.nonzero(rgba[:, :, 3])
    art = Image.fromarray(rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
    width = WIDTHS[kind]
    height = max(1, round(art.height * width / art.width))
    art = art.resize((width, height), Image.LANCZOS)
    out = OUT / f"{kind}-{style}.webp"
    art.save(out, "WEBP", lossless=True, quality=100, method=6)
    line = f"{out.relative_to(ROOT).as_posix()}: {width}x{height}"
    if kind == "balcony":
        alpha = np.array(art)[:, :, 3] >= BACK_ALPHA
        wide = alpha.sum(axis=1) > BACK_SHARE * width
        line += f', back edge row {int(np.argmax(wide))}  ("{style}": {int(np.argmax(wide))},)'
    print(line)
    return art, kind, style


def main() -> None:
    names = [a for a in sys.argv[1:] if not a.startswith("--")]
    preview = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--preview=")), None)
    if not names:
        raise SystemExit(__doc__)
    packed = [pack(name) for name in names]
    if preview:
        pad = 16
        width = sum(p[0].width for p in packed) + pad * (len(packed) + 1)
        height = max(p[0].height for p in packed) + pad * 2
        sheet = Image.new("RGBA", (width, height), (90, 140, 200, 255))
        x = pad
        for art, _, _ in packed:
            sheet.alpha_composite(art, (x, height - pad - art.height))
            x += art.width + pad
        sheet.save(preview)


if __name__ == "__main__":
    main()
