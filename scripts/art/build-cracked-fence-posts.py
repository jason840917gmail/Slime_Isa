#!/usr/bin/env python3
"""Cuts the cracked fence posts (docs/godot/FENCES.md "Cracked fences") out of their Magnific images.

Each style's source is one generated picture of its post split and about to break (GPT 2.5, the
style's front view as reference, 2026-10-19), in `asset/Originals/fences/cracked/<style>-cracked-<n>.png`
(PICKS chooses the take). The tool crops it to its opaque pixels, scales it so the post is as tall as
the style's own posts (its kit's post cell, 2 px per world unit) and writes
`godot/asset/MAPS/fences/<style>-post-cracked.png`, its foot FOOT_PAD px above the picture's bottom
(the chips and moss at its foot hang below). fences.gd draws it in place of the post.

Usage: python scripts/art/build-cracked-fence-posts.py
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "asset/Originals/fences/cracked"
OUT = ROOT / "godot/asset/MAPS/fences"
## The take used per style.
PICKS = {"wood": 1, "snow": 1, "stone": 2, "sandstone": 1, "twig": 1, "picket": 1, "crystal": 1, "lair-divider": 1}
## The cracked post's height over the kit's post cell height (its chips and top shards stand a little
## past a whole post).
HEIGHT_SHARE = 1.08
## px of the picture below the post's foot (keep in step with fences.gd CRACKED_FOOT_PAD).
FOOT_PAD = 6


def main() -> None:
    for style, take in PICKS.items():
        kit = json.loads((OUT / f"{style}.json").read_text(encoding="utf-8"))
        image = Image.open(SOURCES / f"{style}-cracked-{take}.png").convert("RGBA")
        box = image.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
        post = image.crop(box)
        height = round(float(kit["posts"]["cell"][1]) * HEIGHT_SHARE)
        width = max(1, round(post.width * height / post.height))
        post = post.resize((width, height), Image.Resampling.LANCZOS)
        post.save(OUT / f"{style}-post-cracked.png")
        print(f"{style}: {width}x{height}")


if __name__ == "__main__":
    main()
