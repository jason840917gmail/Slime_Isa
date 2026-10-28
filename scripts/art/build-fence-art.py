#!/usr/bin/env python3
"""Cuts the painted fences' kits (docs/godot/FENCES.md) out of generated fence art.

Every style's source is one Magnific image of a straight fence seen from the front (posts joined by
rails that run behind them, on a transparent background), in `asset/Originals/fences/`.
The tool finds its posts (tall opaque columns) and its rails (the rows that are opaque between
the posts), scales everything so a post is `post_height` world units tall at 2 px per unit, and
writes the style's kit into `godot/asset/MAPS/fences/`:

- `<style>-posts.png`: every post of the source side by side, one cell each, their feet on one row
  (the rails that ran behind them removed; green moss at their feet kept).
- `<style>-rails.png`: the rails alone, the stretches between the posts joined by cross-fades into
  one strip that repeats seamlessly sideways (drawn along front and diagonal runs, sheared).
- `<style>-rails-side.png`: the upper rail turned a quarter left (its lit top becomes its lit left
  side), repeating seamlessly downwards: a rail seen from above, for east and west runs.
- `<style>.json`: the kit's measures (px of art, world units above a post's foot) that
  `godot/game/world/fences/fences.gd` draws from.

Usage: python scripts/art/build-fence-art.py [style ...] [--preview DIR]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "asset/Originals/fences"
OUT = ROOT / "godot/asset/MAPS/fences"
## Art px per world unit.
PX = 2.0

## Per style: the source image, how tall a post is (world units, its top to its foot), `spacing`
## and `inset` (written to the kit's JSON from the rim fences; the painted fences stand one post per
## cell and read neither) and how far the rail seen from above runs inside the posts' line on east
## and west runs (world units). Optional: `post_share`, a column is a post's when it is at least this
## share as opaque as the most opaque column (lower for posts much wider at their foot, like a
## crystal cluster); `side_band`, the whole rails band seen from above instead of the upper rail (a
## wall's top), or `side_rows`, a part of the band (fractions from its top: a picket fence's tips);
## `side_width`, the width that is squeezed to (world units).
STYLES = {
    "wood": {"source": "wood-front-b.png", "post_height": 40.0, "spacing": 64.0, "inset": 10.0, "side_offset": 5.0},
    "snow": {"source": "snow-front-a.png", "post_height": 40.0, "spacing": 64.0, "inset": 10.0, "side_offset": 5.0},
    "twig": {"source": "twig-front-a.png", "post_height": 40.0, "spacing": 64.0, "inset": 10.0, "side_offset": 5.0},
    "picket": {"source": "picket-front-a.png", "post_height": 42.0, "spacing": 64.0, "inset": 10.0, "side_offset": 3.0,
               "side_rows": (0.0, 0.35), "side_width": 7.0},
    "crystal": {"source": "crystal-front-a.png", "post_height": 44.0, "spacing": 64.0, "inset": 12.0, "side_offset": 0.0,
                "post_share": 0.55},
    "stone": {"source": "stone-front-a.png", "post_height": 34.0, "spacing": 80.0, "inset": 12.0, "side_offset": 0.0,
              "side_band": True, "side_width": 14.0},
    "sandstone": {"source": "sandstone-front-a.png", "post_height": 36.0, "spacing": 80.0, "inset": 12.0, "side_offset": 0.0,
                  "side_band": True, "side_width": 14.0},
    # Dungeon dividers (docs/godot/FENCES.md "Dungeon dividers"): the Lair's fort stone, square posts
    # with capstones and low bars, as ALttP's room dividers (owner, 2026-10-19: posts about 47 high)
    "lair-divider": {"source": "lair-divider-front-a.png", "post_height": 47.0, "spacing": 64.0, "inset": 10.0,
                     "side_offset": 0.0, "side_band": True, "side_width": 14.0},
    # A low ledge of bevelled blocks (owner, 2026-10-27; `build_blocks`): no posts and rails in the
    # source, so its pieces are cut by box: three identical front blocks a cell, the side its own
    # picture (a column of blocks from above, with its end block), and a corner block.
    "lair-ledge": {"kind": "blocks", "source": "lair-ledge-front-c.png", "spacing": 64.0, "inset": 10.0,
                   "side_offset": 0.0, "rail_cols": (264, 870), "rail_blocks": 3,
                   "side_source": "lair-ledge-side-b.png", "side_rows": (364, 932), "side_cols": (249, 501),
                   "side_crop_blocks": 2, "side_blocks": 3, "side_width": 20.0, "side_end_rows": (932, 1275),
                   "corner_source": "lair-ledge-corner-a.png"},
}

ALPHA = 128
## A column is a post's when it is at least this share as opaque as the most opaque column (rails
## alone are much lower); `post_share` overrides it per style.
POST_COLUMN_SHARE = 0.85
## A row is a rail's when this share of the columns between posts is opaque in it.
RAIL_ROW_SHARE = 0.9
## Source px kept beside a post's trunk (moss and roots at its foot) and skipped beside it when
## cutting the rails out (the moss, the post's outline).
POST_PAD = 24
RAIL_SKIP = 30
## Cross-fade between joined rail stretches and across the strip's wrap (source px).
FADE = 24


def runs(mask: np.ndarray) -> list[tuple[int, int]]:
    """Inclusive (start, end) of every run of True in a 1-D mask."""
    out = []
    start = None
    for i, on in enumerate(mask):
        if on and start is None:
            start = i
        elif not on and start is not None:
            out.append((start, i - 1))
            start = None
    if start is not None:
        out.append((start, len(mask) - 1))
    return out


def premultiplied_resize(image: np.ndarray, size: tuple[int, int]) -> np.ndarray:
    """Resizes RGBA (uint8 array) without dark fringes: premultiplied, Lanczos."""
    pil = Image.fromarray(image, "RGBA").convert("RGBa")
    return np.array(pil.resize(size, Image.LANCZOS).convert("RGBA"))


def cross_join(pieces: list[np.ndarray], fade: int) -> np.ndarray:
    """Joins pieces of equal height side by side, each overlapping the last by `fade` px."""
    out = pieces[0].astype(np.float32)
    ramp = np.linspace(0.0, 1.0, fade, dtype=np.float32)[None, :, None]
    for piece in pieces[1:]:
        piece = piece.astype(np.float32)
        blend = out[:, -fade:] * (1.0 - ramp) + piece[:, :fade] * ramp
        out = np.concatenate([out[:, :-fade], blend, piece[:, fade:]], axis=1)
    return out


def periodic(strip: np.ndarray, fade: int) -> np.ndarray:
    """Makes a strip repeat sideways: its last `fade` px fade into its first ones, then are cut."""
    ramp = np.linspace(0.0, 1.0, fade, dtype=np.float32)[None, :, None]
    out = strip[:, :-fade].copy()
    out[:, :fade] = strip[:, -fade:] * (1.0 - ramp) + strip[:, :fade] * ramp
    return out


def to_uint8(array: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(array), 0, 255).astype(np.uint8)


def build_blocks(style: str, spec: dict, preview: Path | None) -> None:
    """A style of blocks (`kind` "blocks"), an edge style (`edge`: fences.gd draws each cell's fence
    along one of its sides, no posts). Its pieces are cut by box, at one scale (`rail_blocks` front
    blocks fill a cell, `spacing`):

    - the front strip: `rail_cols` of `source`, joint middle to joint middle (`rail_blocks` identical
      blocks), so it repeats and a cell's edge falls on a joint;
    - the side: `side_rows` x `side_cols` of `side_source` (`side_crop_blocks` blocks seen from above,
      joint to joint), repeated to `side_blocks` blocks a cell, `side_width` wide;
    - the pieces sheet (`<style>-posts.png`, the kit's post picture: an edge style draws no posts),
      its cells side by side, top-left: the column's end (`side_end_rows`, its front face showing, at
      the side's scale) and the corner block (`corner_source`, as wide as a front block). The JSON's
      `pieces` gives each one's [u, v, width, height] in the sheet."""
    rgba = np.array(Image.open(SOURCES / spec["source"]).convert("RGBA"))
    opaque = rgba[:, :, 3] > ALPHA
    cx0, cx1 = spec["rail_cols"]
    rows = np.where(opaque[:, cx0:cx1].any(axis=1))[0]
    top, foot = int(rows.min()), int(rows.max())
    rails_w = int(round(spec["spacing"] * PX))
    scale = rails_w / (cx1 - cx0)
    rails_h = int(round((foot + 1 - top) * scale))
    rails_out = premultiplied_resize(np.ascontiguousarray(rgba[top:foot + 1, cx0:cx1]), (rails_w, rails_h))
    # The wrap: the two outermost columns (both in a joint) blended into each other.
    edge = (rails_out[:, :1].astype(np.float32) + rails_out[:, -1:].astype(np.float32)) * 0.5
    rails_out[:, :1] = to_uint8(edge)
    rails_out[:, -1:] = to_uint8(edge)

    side_src = np.array(Image.open(SOURCES / spec["side_source"]).convert("RGBA"))
    sy0, sy1 = spec["side_rows"]
    sx0, sx1 = spec["side_cols"]
    crop = side_src[sy0:sy1, sx0:sx1 + 1]
    block_rows = crop.shape[0] / spec["side_crop_blocks"]
    repeats = int(np.ceil(spec["side_blocks"] / spec["side_crop_blocks"]))
    side = np.concatenate([crop] * repeats, axis=0)[:int(round(block_rows * spec["side_blocks"]))]
    side_w = int(round(spec["side_width"] * PX / 2.0)) * 2
    side_h = int(round(spec["spacing"] * PX))
    side_out = premultiplied_resize(np.ascontiguousarray(side), (side_w, side_h))

    ey0, ey1 = spec["side_end_rows"]
    end = side_src[ey0:ey1, sx0:sx1 + 1]
    end_out = premultiplied_resize(np.ascontiguousarray(end), (side_w, int(round(end.shape[0] * side_h / side.shape[0]))))
    corner_src = np.array(Image.open(SOURCES / spec["corner_source"]).convert("RGBA"))
    ys, xs = np.where(corner_src[:, :, 3] > ALPHA)
    corner = corner_src[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    corner_w = int(round(rails_w / spec["rail_blocks"]))
    corner_out = premultiplied_resize(np.ascontiguousarray(corner), (corner_w, int(round(corner.shape[0] * corner_w / corner.shape[1]))))
    pieces = {"end": end_out, "corner": corner_out}
    cell_w = max(p.shape[1] for p in pieces.values())
    cell_h = max(p.shape[0] for p in pieces.values())
    sheet = np.zeros((cell_h, cell_w * len(pieces), 4), dtype=np.uint8)
    places = {}
    for i, (name, piece) in enumerate(pieces.items()):
        sheet[:piece.shape[0], i * cell_w:i * cell_w + piece.shape[1]] = piece
        places[name] = [i * cell_w, 0, piece.shape[1], piece.shape[0]]

    def units_above_foot(row: float) -> float:
        return (foot + 1 - row) * scale / PX

    height = round(units_above_foot(top), 2)
    metrics = {
        "style": style,
        "source": spec["source"],
        "px_per_unit": PX,
        "post_height": height,
        "spacing": spec["spacing"],
        "inset": spec["inset"],
        "posts": {"count": len(pieces), "cell": [cell_w, cell_h], "foot_row": cell_h,
                  "half_width": round(corner_w / PX / 2.0, 2)},
        "rails": {"size": [rails_w, rails_h], "top": height, "bottom": 0.0, "rows": [[height, 0.0]]},
        "side": {"size": [side_w, side_h], "top": height, "bottom": 0.0, "offset": spec["side_offset"],
                 "blocks": spec["side_blocks"]},
        "pieces": places,
        # An edge style: each cell's fence runs along the side of the cell its arrow names (fences.gd
        # `_add_edge_cell`), never linked.
        "edge": True,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(OUT / f"{style}-posts.png")
    Image.fromarray(rails_out, "RGBA").save(OUT / f"{style}-rails.png")
    Image.fromarray(side_out, "RGBA").save(OUT / f"{style}-rails-side.png")
    (OUT / f"{style}.json").write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
    print(f"{style}: rails {rails_w}x{rails_h} px, side {side_w}x{side_h} px, pieces {places}, scale {scale:.3f}")
    if preview is not None:
        preview.mkdir(parents=True, exist_ok=True)
        _preview(style, sheet, rails_out, side_out, metrics, preview)


def build(style: str, preview: Path | None) -> None:
    spec = STYLES[style]
    if spec.get("kind") == "blocks":
        build_blocks(style, spec, preview)
        return
    rgba = np.array(Image.open(SOURCES / spec["source"]).convert("RGBA"))
    opaque = rgba[:, :, 3] > ALPHA
    height, width = opaque.shape

    column_counts = opaque.sum(axis=0)
    posts = runs(column_counts >= spec.get("post_share", POST_COLUMN_SHARE) * column_counts.max())
    posts = [p for p in posts if p[1] - p[0] >= 8]
    if len(posts) < 2:
        raise SystemExit(f"{style}: found {len(posts)} posts, need 2 or more")
    gap_columns = np.concatenate([np.arange(posts[i][1] + RAIL_SKIP, posts[i + 1][0] - RAIL_SKIP) for i in range(len(posts) - 1)])
    rail_rows = runs(opaque[:, gap_columns].mean(axis=1) > RAIL_ROW_SHARE)
    if not rail_rows:
        raise SystemExit(f"{style}: no rails found between the posts")
    band_any = np.where(opaque[:, gap_columns].mean(axis=1) > 0.05)[0]
    band_top, band_bottom = int(band_any.min()) - 2, int(band_any.max()) + 2

    tops, feet = [], []
    for x0, x1 in posts:
        trunk = opaque[:, x0 + 4: x1 - 3]
        tops.append(min(int(np.where(trunk[:, i])[0].min()) for i in range(trunk.shape[1])))
        feet.append(int(np.median([np.where(trunk[:, i])[0].max() for i in range(trunk.shape[1])])))
    post_px = float(np.median(np.array(feet) - np.array(tops)))
    scale = spec["post_height"] * PX / post_px

    # Posts: the trunk's columns whole; beside it only moss (green) and what lies below the rails.
    cells = []
    foot_extra = max(int(np.where(opaque[:, x0:x1 + 1].any(axis=1))[0].max()) - foot for (x0, x1), foot in zip(posts, feet))
    for (x0, x1), top, foot in zip(posts, tops, feet):
        left, right = max(0, x0 - POST_PAD), min(width, x1 + 1 + POST_PAD)
        y0, y1 = max(0, top - 6), min(height, foot + foot_extra + 3)
        cut = rgba[y0:y1, left:right].copy()
        rows = np.arange(y0, y1)[:, None]
        cols = np.arange(left, right)[None, :]
        beside = (cols < x0 - 1) | (cols > x1 + 1)
        in_rails = (rows >= band_top) & (rows <= band_bottom)
        r, g = cut[:, :, 0].astype(int), cut[:, :, 1].astype(int)
        mossy = g > r + 6
        drop = beside & in_rails & ~mossy
        cut[drop, 3] = 0
        # The foot at a common row: pad so that the foot is `foot - y0` px from the cut's top.
        cells.append((cut, foot - y0))
    cell_w = max(c.shape[1] for c, _ in cells)
    foot_row = max(f for _, f in cells)
    below = max(c.shape[0] - f for c, f in cells)
    cell_h = foot_row + below
    sheet = np.zeros((cell_h, cell_w * len(cells), 4), dtype=np.uint8)
    for i, (cut, foot) in enumerate(cells):
        ox = i * cell_w + (cell_w - cut.shape[1]) // 2
        oy = foot_row - foot
        sheet[oy:oy + cut.shape[0], ox:ox + cut.shape[1]] = cut
    out_cell_w = int(round(cell_w * scale / 2.0)) * 2
    out_cell_h = int(round(cell_h * scale))
    posts_out = np.zeros((out_cell_h, out_cell_w * len(cells), 4), dtype=np.uint8)
    for i in range(len(cells)):
        cell = sheet[:, i * cell_w:(i + 1) * cell_w]
        posts_out[:, i * out_cell_w:(i + 1) * out_cell_w] = premultiplied_resize(cell, (out_cell_w, out_cell_h))

    # Rails: the stretches between posts, joined and made periodic.
    pieces = [rgba[band_top:band_bottom + 1, posts[i][1] + RAIL_SKIP:posts[i + 1][0] - RAIL_SKIP] for i in range(len(posts) - 1)]
    strip = periodic(cross_join(pieces, FADE), FADE)
    strip = to_uint8(strip)
    rails_w = int(round(strip.shape[1] * scale))
    rails_h = int(round(strip.shape[0] * scale))
    rails_out = premultiplied_resize(strip, (rails_w, rails_h))
    # Wrap fix after resampling: blend the two outermost columns into each other.
    edge = (rails_out[:, :1].astype(np.float32) + rails_out[:, -1:].astype(np.float32)) * 0.5
    rails_out[:, :1] = to_uint8(edge)
    rails_out[:, -1:] = to_uint8(edge)

    # Side: the upper rail (or a wall's whole band) from above, a quarter turn left, repeating
    # downwards.
    upper = rail_rows[0]
    if spec.get("side_band"):
        upper = (band_top + 2, band_bottom - 2)
    elif spec.get("side_rows"):
        f0, f1 = spec["side_rows"]
        upper = (band_top + 3 + int(f0 * (band_bottom - band_top)), band_top + int(f1 * (band_bottom - band_top)))
    rail_cut = strip[max(0, upper[0] - 3 - band_top):upper[1] + 4 - band_top]
    side = np.rot90(rail_cut, 1)
    side_w = int(round(side.shape[1] * scale / 2.0)) * 2
    if spec.get("side_width"):
        side_w = int(round(spec["side_width"] * PX / 2.0)) * 2
    side_h = rails_w
    side_out = premultiplied_resize(np.ascontiguousarray(side), (side_w, side_h))

    foot_src = float(np.median(feet))
    def units_above_foot(row: float) -> float:
        return (foot_src - row) * scale / PX

    metrics = {
        "style": style,
        "source": spec["source"],
        "px_per_unit": PX,
        "post_height": spec["post_height"],
        "spacing": spec["spacing"],
        "inset": spec["inset"],
        "posts": {"count": len(cells), "cell": [out_cell_w, out_cell_h], "foot_row": round(foot_row * scale, 2),
                   "half_width": round(float(np.median([x1 - x0 for x0, x1 in posts])) * scale / PX / 2.0, 2)},
        "rails": {"size": [rails_w, rails_h], "top": round(units_above_foot(band_top), 2),
                   "bottom": round(units_above_foot(band_bottom + 1), 2),
                   "rows": [[round(units_above_foot(a), 2), round(units_above_foot(b + 1), 2)] for a, b in rail_rows]},
        "side": {"size": [side_w, side_h], "top": round(units_above_foot(upper[0]), 2),
                  "bottom": round(units_above_foot(upper[1] + 1), 2), "offset": spec["side_offset"]},
    }
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(posts_out, "RGBA").save(OUT / f"{style}-posts.png")
    Image.fromarray(rails_out, "RGBA").save(OUT / f"{style}-rails.png")
    Image.fromarray(side_out, "RGBA").save(OUT / f"{style}-rails-side.png")
    (OUT / f"{style}.json").write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
    natural = float(np.median([posts[i + 1][0] - posts[i][0] for i in range(len(posts) - 1)])) * scale / PX
    print(f"{style}: {len(cells)} posts {out_cell_w}x{out_cell_h} px, rails {rails_w}x{rails_h} px, "
          f"side {side_w}x{side_h} px, scale {scale:.3f}, post spacing in the source {natural:.0f} units")
    if preview is not None:
        preview.mkdir(parents=True, exist_ok=True)
        _preview(style, posts_out, rails_out, side_out, metrics, preview)


def _preview(style: str, posts: np.ndarray, rails: np.ndarray, side: np.ndarray, metrics: dict, folder: Path) -> None:
    """A straight run and a side run on grass-green, at 2x, to eyeball the kit."""
    canvas = Image.new("RGBA", (900, 420), (120, 160, 90, 255))
    foot_y = 200
    rails_img = Image.fromarray(rails, "RGBA")
    top_px = foot_y - metrics["rails"]["top"] * PX
    for x in range(0, 900, rails_img.width):
        canvas.alpha_composite(rails_img, (x, int(round(top_px))))
    cell_w, cell_h = metrics["posts"]["cell"]
    spacing = int(metrics["spacing"] * PX)
    for i, x in enumerate(range(40, 900, spacing)):
        k = i % metrics["posts"]["count"]
        post = Image.fromarray(posts[:, k * cell_w:(k + 1) * cell_w], "RGBA")
        canvas.alpha_composite(post, (x - cell_w // 2, int(foot_y - metrics["posts"]["foot_row"])))
    canvas.resize((1800, 840), Image.LANCZOS).save(folder / f"{style}-preview.png")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("styles", nargs="*", help="styles to build (default: all)")
    parser.add_argument("--preview", type=Path, help="write a preview per style into this folder")
    args = parser.parse_args()
    for style in args.styles or list(STYLES):
        if style not in STYLES:
            raise SystemExit(f"unknown style '{style}' (known: {', '.join(STYLES)})")
        build(style, args.preview)


if __name__ == "__main__":
    main()
