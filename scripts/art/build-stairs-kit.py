"""Builds the painted stairs kit (docs/godot/ELEVATION.md "Stairs", owner 2026-11-06: the concepts
Front A and West C in asset/Originals/elevation/stairs-painted/).

Sources (Magnific GPT 2.5 sheets, in asset/Originals/elevation/stairs-painted/):
  tread-a.png          six rows of stair treads seen from above (a slab top, its nosing at the bottom)
  blocks-a.png         a wall of big rounded sandstone blocks
  piece-2x1-b.png, piece-2x2-b.png  a front flight of one and of two levels painted whole: the
                       steps, the notch and the rock framing it (cut-outs, after Front A)
  concept-west-c.png (and the other side concepts)  side flights painted in the game's own camera
  concept-diag-1-b.png, concept-diag-2-a.png  45° front flights painted in the game's own camera
Outputs (godot/asset/MAPS/elevation/):
  stairs-tread.png    one tread row, PX texture px per world unit, horizontally periodic (a side or
                      back flight's treads and its side walls' tops)
  stairs-blocks.png   the blocks, periodic both ways (a side or back flight's side walls)
  stairs-front-<levels>.png  the front flight pieces: frames PIECE_FRAME across, steps PIECE_STEPS,
                      PX per world unit
  stairs-side-<levels>-<cells>.png  the side flight pieces (westward), cut from their concepts
  stairs-diag-<levels>.png  the 45° front flight pieces (south-west), unskewed from their concepts
and prints each output's mean colour (elevation_stairs.gd KIT_MEANS), each piece's aspect and steps
(FRONT_PIECES) and every wall style's mean colour (STONE_COLOURS: a flight takes the colour of the
wall it is cut into). Other sheets there (riser-a, pillars-a/-b, the concepts) are sources of
earlier tries, kept for reference.

    python scripts/art/build-stairs-kit.py [--preview DIR]
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "asset" / "Originals" / "elevation" / "stairs-painted"
OUT = ROOT / "godot" / "asset" / "MAPS" / "elevation"
## Texture px per world unit (elevation_stairs.gd PX).
PX = 3
## One rise of a step (world units): a tread or riser row is this tall.
RISE = 16
ROW_PX = RISE * PX
## Rows in each source sheet, and the rows used (joined side by side for a longer period).
ROWS = 6
PICKS = {"tread": ("tread-a.png", [1, 3])}
## Source px searched around each expected line between rows, and blended across a seam.
LINE_SEARCH = 40
OVERLAP = 64
## The blocks: source px blended across each wrap, and the output's side (world units).
BLOCKS = ("blocks-a.png", 160, 132)
## World units per level; a piece's frames and steps across (a two-cell flight's steps), and how far
## it reaches below the flight's foot.
LEVEL = 64
PIECE_FRAME = 52
PIECE_STEPS = 128
PIECE_SINK = 6
PIECE_ALPHA = 24
## A front piece's steps start at the first row this share of which is opaque (printed: the game
## draws the top's ground down to that row, elevation_stairs.gd FRONT_PIECES "top").
STEPS_FULL = 0.9
## A side flight's run per level, its side walls' thickness and height above the steps (world units,
## elevation_stairs.gd), and its half width per cell.
SIDE_RUN = 64
SIDE_POST = 14
SIDE_POST_UP = 8
HALF_CELL = 32
## A 45° front flight (south-west, south-east) painted whole on its slanted face, as the south-west
## flight it is painted for (a south-east one draws it mirrored), unskewed into a flat piece: across
## it the flight's t (screen-left first) from the outer edge of one frame to the other's, DIAG_FRAME
## screen units each, down it the height from the top edge to PIECE_SINK below the foot; the frames'
## outer DIAG_FADE units and the last PIECE_SINK fade out, and a repainted render's grass is keyed
## out (DIAG_KEY).
DIAG_FRAME = 52
DIAG_FADE = 10
## Green keyed out: a texel is kept as far as its red exceeds its green by more than DIAG_KEY[0],
## fully DIAG_KEY[1] beyond (0 … 255).
DIAG_KEY = (-6, 16)
R45 = 0.7071067811865476


## A 45° concept made by repainting a render: the rim's top in it (px) and its px per world unit.
DIAG_SOURCES = {
    "render-1": ((382.23 * 768 / 763, 407.23 * 1024 / 954), (2 * 768 / 763, 2 * 1024 / 954)),
    "render-2": ((407.22 * 768 / 814, 407.22 * 1024 / 1082), (2 * 768 / 814, 2 * 1024 / 1082)),
}
## The stairs art sets (owner 2026-11-06: "at least 3 or 4 different art stairs to match our other
## grounds"; picks: meadow A, snow A, forest A, town A, caves B): name -> the wall styles that take it,
## the one it is painted for ("home", drawn in its own colour; the others are recoloured to their
## wall), and per part how it is made: ("front", sheet, steps' share across it), ("diag", render
## repainted, DIAG_SOURCES key), ("diag_screen", cut-out repainted from the desert piece on screen),
## ("side", render repainted, box in it) or ("side_piece", cut-out repainted from the desert piece).
## Sheets are in SRC (sets/ for the new sets).
SETS = {
    "desert": {
        "home": "", "styles": ["sandstone", "desert-dirt", "desert-face", "desert-strata", "red-rock",
                               "autumn-face", "mountain-dirt"],
        "parts": {
            "front_1": ("front", "piece-2x1-b.png", (0.31, 0.69)),
            "front_2": ("front", "piece-2x2-b.png", (0.26, 0.73)),
            "diag_1": ("diag", "concept-diag-1-b.png", "render-1"),
            "diag_2": ("diag", "concept-diag-2-a.png", "render-2"),
            "side_1_1": ("side", "concept-side-1-1-b.png", (429.5, 313.0, 584.8, 711.0)),
            "side_1_2": ("side", "concept-side-1-2-a.png", (429.5, 235.4, 584.8, 788.6)),
            "side_2_1": ("side", "concept-west-c.png", (242.7, 326.2, 566.4, 902.6)),
        },
    },
    "meadow": {
        "home": "meadow-rock", "styles": ["meadow-rock", "meadow-face", "storybook-rock"],
        "parts": {
            "front_1": ("front", "sets/meadow-front1.png", (0.31, 0.69)),
            "front_2": ("front", "sets/front2-meadow-a.png", (0.24, 0.77)),
            "diag_1": ("diag", "sets/meadow-diag1.png", "render-1"),
            "diag_2": ("diag", "sets/meadow-diag2.png", "render-2"),
            "side_1_1": ("side", "sets/meadow-side11.png", (429.5, 313.0, 584.8, 711.0)),
            "side_1_2": ("side", "sets/meadow-side12.png", (429.5, 235.4, 584.8, 788.6)),
            "side_2_1": ("side_piece", "sets/meadow-side21p.png"),
        },
    },
}
for _name, _home, _styles, _fractions in [
        ("snow", "snow-rock", ["snow-rock", "snow-face", "ice-dirt"], (0.23, 0.78)),
        ("forest", "root-rock", ["root-rock", "forest-face", "mossy-rock"], (0.25, 0.76)),
        ("town", "masonry", ["masonry", "castle-face", "town-face"], (0.25, 0.75)),
        ("cave", "", ["cave-rock", "cave-face", "crystal-rock", "crystal-face", "dungeon-face", "volcanic-face"], (0.23, 0.76))]:
    _front = {"snow": "front2-snow-a", "forest": "front2-forest-a", "town": "front2-town-a", "cave": "front2-cave-b"}[_name]
    SETS[_name] = {"home": _home, "styles": _styles, "parts": {
        "front_1": ("front", f"sets/{_name}-front1.png", (0.31, 0.69)),
        "front_2": ("front", f"sets/{_front}.png", _fractions),
        "diag_1": ("diag_screen", f"sets/{_name}-diag1s.png"),
        "diag_2": ("diag_screen", f"sets/{_name}-diag2s.png"),
        "side_1_1": ("side_piece", f"sets/{_name}-side11p.png"),
        "side_1_2": ("side_piece", f"sets/{_name}-side12p.png"),
        "side_2_1": ("side_piece", f"sets/{_name}-side21p.png"),
    }}


def load_rgb(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)


def luminance(rgb: np.ndarray) -> np.ndarray:
    return rgb @ np.array([0.299, 0.587, 0.114])


def row_lines(rgb: np.ndarray) -> list[int]:
    """The dark lines between a sheet's ROWS rows (y of each, 0 and the height included)."""
    height = rgb.shape[0]
    profile = luminance(rgb).mean(axis=1)
    lines = [0]
    for k in range(1, ROWS):
        expected = round(k * height / ROWS)
        lo, hi = max(1, expected - LINE_SEARCH), min(height - 1, expected + LINE_SEARCH)
        lines.append(lo + int(np.argmin(profile[lo:hi])))
    lines.append(height)
    return lines


def seam_join(left: np.ndarray, right: np.ndarray, overlap: int) -> np.ndarray:
    """`left` then `right`, their `overlap` columns joined along a seam of least difference."""
    height = left.shape[0]
    a = left[:, -overlap:]
    b = right[:, :overlap]
    cost = ((a - b) ** 2).sum(axis=2)
    acc = cost.copy()
    for y in range(1, height):
        prev = acc[y - 1]
        best = np.minimum(prev, np.minimum(np.roll(prev, 1), np.roll(prev, -1)))
        best[0] = min(prev[0], prev[1])
        best[-1] = min(prev[-1], prev[-2])
        acc[y] += best
    seam = np.zeros(height, dtype=int)
    seam[-1] = int(np.argmin(acc[-1]))
    for y in range(height - 2, -1, -1):
        x = seam[y + 1]
        lo, hi = max(0, x - 1), min(overlap, x + 2)
        seam[y] = lo + int(np.argmin(acc[y, lo:hi]))
    middle = b.copy()
    for y in range(height):
        middle[y, : seam[y]] = a[y, : seam[y]]
    return np.concatenate([left[:, :-overlap], middle, right[:, overlap:]], axis=1)


def periodic_x(image: np.ndarray, overlap: int) -> np.ndarray:
    """Horizontally periodic: the right `overlap` columns are joined onto the left ones."""
    joined = seam_join(image, image, overlap)
    width = image.shape[1]
    # joined = image[:-o] + seam(image[-o:], image[:o]) + image[o:]: one period is width - overlap
    # long, starting at the seam's middle.
    return joined[:, width - overlap: 2 * width - 2 * overlap]


def resize(image: np.ndarray, width: int, height: int) -> np.ndarray:
    out = Image.fromarray(np.clip(image, 0, 255).astype(np.uint8)).resize((width, height), Image.LANCZOS)
    return np.asarray(out, dtype=np.float64)


def build_row(part: str) -> np.ndarray:
    source, picks = PICKS[part]
    rgb = load_rgb(SRC / source)
    lines = row_lines(rgb)
    rows = []
    for index in picks:
        # From just past the line above to just past its own line: the row's dark line at its top.
        top = min(lines[index] + 2, rgb.shape[0] - 1)
        bottom = min(lines[index + 1] + 2, rgb.shape[0])
        row = rgb[top:bottom]
        rows.append(resize(row, round(row.shape[1] * ROW_PX / row.shape[0]), ROW_PX))
    strip = rows[0]
    for row in rows[1:]:
        strip = seam_join(strip, row, OVERLAP * ROW_PX // 166)
    return periodic_x(strip, OVERLAP * ROW_PX // 166)


def build_blocks() -> np.ndarray:
    source, overlap, side_units = BLOCKS
    rgb = load_rgb(SRC / source)
    rgb = periodic_x(rgb, overlap)
    rgb = periodic_x(rgb.transpose(1, 0, 2), overlap).transpose(1, 0, 2)
    side = side_units * PX
    return resize(rgb, side, side)


def build_piece(source: str, fractions: tuple[float, float], levels: int) -> tuple[Image.Image, float, tuple[float, float], float]:
    """A front flight of `levels` levels painted whole (steps, notch and frame), from its sheet:
    cropped to its alpha, cut in three where its steps begin and end (`fractions` of its width), the
    frames scaled to PIECE_FRAME world units across and the steps to PIECE_STEPS (the sheets' steps
    are narrower than a flight), PX per world unit, PIECE_SINK below the flight's foot. Returns it, its
    aspect (width over height), where its steps run across it and where they begin down it."""
    left, right = fractions
    sheet = Image.open(SRC / source).convert("RGBA")
    piece = sheet.crop(sheet.getchannel("A").point(lambda a: 255 if a > PIECE_ALPHA else 0).getbbox())
    width = piece.width
    height = round((levels * LEVEL + PIECE_SINK) * PX)
    parts = [piece.crop((0, 0, round(left * width), piece.height)),
             piece.crop((round(left * width), 0, round(right * width), piece.height)),
             piece.crop((round(right * width), 0, width, piece.height))]
    widths = [round(units * PX) for units in (PIECE_FRAME, PIECE_STEPS, PIECE_FRAME)]
    out = Image.new("RGBA", (sum(widths), height), (0, 0, 0, 0))
    x = 0
    for part, part_width in zip(parts, widths):
        out.alpha_composite(part.resize((part_width, height), Image.LANCZOS), (x, 0))
        x += part_width
    steps = (widths[0] / out.width, (widths[0] + widths[1]) / out.width)
    # Where the steps begin down the piece (the first row they fill across): the game draws the top's
    # own ground down to that row (owner 2026-11-06: no ledge painted over the stairs).
    middle = np.asarray(out)[:, widths[0] + 4: widths[0] + widths[1] - 4, 3] > 200
    first = int(np.argmax(middle.mean(axis=1) > STEPS_FULL))
    return out, out.width / out.height, steps, first / out.height


def side_box(levels: int, cells: int) -> tuple[float, float, float]:
    """A westward side flight's box (world units): its run, its height on screen, and how far down
    its left edge the top of its far side wall's end reaches."""
    run = SIDE_RUN * levels
    outer = HALF_CELL * cells + SIDE_POST
    height = 2 * outer + LEVEL * levels + SIDE_POST_UP
    return run, height, LEVEL * levels


def side_mask(levels: int, cells: int) -> np.ndarray:
    """A westward side flight's outline as alpha (0 … 1, PX per world unit): its box, transparent
    above the top of its far side wall (the line from the box's top right to its left edge, the
    flight's height down it)."""
    run, height, drop = side_box(levels, cells)
    w, h = round(run * PX), round(height * PX)
    ys, xs = np.mgrid[0:h, 0:w]
    line_y = (1.0 - (xs + 0.5) / w) * drop * PX
    return np.clip((ys + 0.5) - line_y + 0.5, 0.0, 1.0)


def build_side_piece(source: str, levels: int, cells: int) -> Image.Image:
    """A side flight repainted as a cut-out from the desert piece of its size: cropped to its alpha,
    fitted to the flight's box, its outline the flight's (`side_mask`)."""
    sheet = Image.open(SRC / source).convert("RGBA")
    piece = sheet.crop(sheet.getchannel("A").point(lambda a: 255 if a > PIECE_ALPHA else 0).getbbox())
    mask = side_mask(levels, cells)
    piece = piece.resize((mask.shape[1], mask.shape[0]), Image.LANCZOS)
    rgba = np.asarray(piece, dtype=np.float64).copy()
    rgba[..., 3] = np.minimum(rgba[..., 3], mask * 255.0)
    return Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")


def build_side(source: str, box: tuple[float, float, float, float], levels: int, cells: int) -> Image.Image:
    """A side flight painted whole: its box cut from its concept (a render repainted), PX per world
    unit, its outline the flight's (`side_mask`)."""
    run, height, drop = side_box(levels, cells)
    sheet = Image.open(SRC / source).convert("RGBA")
    piece = sheet.resize((round(sheet.width * 4), round(sheet.height * 4)), Image.LANCZOS)
    piece = piece.crop(tuple(round(v * 4) for v in box))
    w, h = round(run * PX), round(height * PX)
    piece = piece.resize((w, h), Image.LANCZOS)
    rgba = np.asarray(piece, dtype=np.float64).copy()
    rgba[..., 3] = side_mask(levels, cells) * 255.0
    return Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")


def diag_fade(levels: int) -> np.ndarray:
    """A flat 45° piece's alpha (0 … 1): its frames' outer DIAG_FADE units and the last PIECE_SINK
    fade out."""
    height = LEVEL * levels
    width_units = 2 * HALF_CELL * R45 + 2 * DIAG_FRAME
    w, h = round(width_units * PX), round((height + PIECE_SINK) * PX)
    u, v = np.meshgrid((np.arange(w) + 0.5) / w, (np.arange(h) + 0.5) / h)
    across = u * width_units
    hh = height - v * (height + PIECE_SINK)
    return np.clip(np.minimum(across, width_units - across) / DIAG_FADE, 0, 1) * np.clip(hh / PIECE_SINK + 1.0, 0, 1)


def build_diag_screen(source: str, levels: int) -> Image.Image:
    """A 45° front flight repainted as a cut-out from the desert piece as it shows on screen (a
    south-west flight's slanted face): cropped to its alpha, fitted to the face's box on screen and
    unskewed into a flat piece (as `build_diag`), faded as it is (`diag_fade`)."""
    sheet = Image.open(SRC / source).convert("RGBA")
    shot = sheet.crop(sheet.getchannel("A").point(lambda a: 255 if a > PIECE_ALPHA else 0).getbbox())
    height = LEVEL * levels
    t_out = HALF_CELL + DIAG_FRAME / R45
    screen_w, screen_h = 2 * R45 * t_out, 2 * R45 * t_out + height + PIECE_SINK
    fine = 6
    shot = np.asarray(shot.resize((round(screen_w * fine), round(screen_h * fine)), Image.LANCZOS), dtype=np.float64)
    fade = diag_fade(levels)
    h, w = fade.shape
    u, v = np.meshgrid((np.arange(w) + 0.5) / w, (np.arange(h) + 0.5) / h)
    t = t_out - u * 2 * t_out
    hh = height - v * (height + PIECE_SINK)
    # On screen, from the box's top left: x = −R·t + R·t_out, y = x + height − h.
    x = -R45 * t + R45 * t_out
    y = x + height - hh
    xi = np.clip((x * fine).astype(int), 0, shot.shape[1] - 1)
    yi = np.clip((y * fine).astype(int), 0, shot.shape[0] - 1)
    rgba = shot[yi, xi].copy()
    rgba[..., 3] = rgba[..., 3] * fade
    return Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")


def build_diag(source: str, rim: tuple[float, float], k: tuple[float, float], levels: int) -> Image.Image:
    """A 45° front flight painted whole, unskewed from its concept's slanted face (a render
    repainted: the rim's top in it and its px per world unit)."""
    sheet = np.asarray(Image.open(SRC / source).convert("RGB"), dtype=np.float64)
    height = LEVEL * levels
    steps_w = 2 * HALF_CELL * R45
    width_units = steps_w + 2 * DIAG_FRAME
    w, h = round(width_units * PX), round((height + PIECE_SINK) * PX)
    t_out = HALF_CELL + DIAG_FRAME / R45
    xs = (np.arange(w) + 0.5) / w
    ys = (np.arange(h) + 0.5) / h
    u, v = np.meshgrid(xs, ys)
    t = t_out - u * 2 * t_out
    hh = height - v * (height + PIECE_SINK)
    sx = rim[0] + k[0] * (-R45 * t)
    sy = rim[1] + k[1] * (-R45 * t + (height - hh))
    # Bilinear sample.
    x0 = np.clip(np.floor(sx - 0.5).astype(int), 0, sheet.shape[1] - 2)
    y0 = np.clip(np.floor(sy - 0.5).astype(int), 0, sheet.shape[0] - 2)
    fx = np.clip(sx - 0.5 - x0, 0, 1)[..., None]
    fy = np.clip(sy - 0.5 - y0, 0, 1)[..., None]
    top = sheet[y0, x0] * (1 - fx) + sheet[y0, x0 + 1] * fx
    bottom = sheet[y0 + 1, x0] * (1 - fx) + sheet[y0 + 1, x0 + 1] * fx
    rgb = top * (1 - fy) + bottom * fy
    # The frames' outer edges and the bit below the foot fade out.
    across = u * width_units
    edge = np.minimum(across, width_units - across)
    alpha = np.clip(edge / DIAG_FADE, 0, 1) * np.clip(hh / PIECE_SINK + 1.0, 0, 1)
    # The concept's grass and ferns (green over red) are left out: the game draws its own.
    alpha *= np.clip((rgb[..., 0] - rgb[..., 1] - DIAG_KEY[0]) / DIAG_KEY[1], 0, 1)
    rgba = np.dstack([rgb, alpha * 255.0])
    return Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")


def build_set(name: str, spec: dict) -> dict:
    """One set's pieces into OUT (the desert set's under their old names, the others' as
    stairs-<set>-<part>.png). Returns {part: (res path, mean colour)}, its front pieces' steps' tops
    and its own colour (its two-level front piece's mean)."""
    parts = {}
    tops = {}
    prefix = "stairs-" if name == "desert" else f"stairs-{name}-"
    for part, how in spec["parts"].items():
        method, source = how[0], how[1]
        if method == "front":
            levels = int(part[-1])
            image, _aspect, _steps, top = build_piece(source, how[2], levels)
            tops[levels] = top
        elif method == "diag":
            image = build_diag(source, *DIAG_SOURCES[how[2]], int(part[-1]))
        elif method == "diag_screen":
            image = build_diag_screen(source, int(part[-1]))
        elif method == "side":
            image = build_side(source, how[2], int(part[5]), int(part[7]))
        else:
            image = build_side_piece(source, int(part[5]), int(part[7]))
        file = prefix + part.replace("_", "-") + ".png"
        image.save(OUT / file)
        rgba = np.asarray(image, dtype=np.float64)
        mean = rgba[rgba[..., 3] > 200][:, :3].mean(axis=0) / 255.0
        parts[part] = (f"res://asset/MAPS/elevation/{file}", tuple(round(float(c), 3) for c in mean))
        print(f"{name} {part}: {file} {image.width}x{image.height}")
    return {"parts": parts, "tops": tops, "home": spec["home"], "styles": spec["styles"],
            "tint": parts["front_2"][1]}


def write_sets(sets: dict) -> None:
    """The sets as GDScript constants (godot/game/world/elevation/elevation_stairs_sets.gd)."""
    lines = [
        "@tool",
        "extends RefCounted",
        "## The stairs art sets (docs/godot/ELEVATION.md \"Stairs\"), GENERATED by",
        "## scripts/art/build-stairs-kit.py: do not edit, run it again. A flight takes the set of the wall",
        "## style it is cut into (STYLE_SETS); per set: each part's texture and mean colour, where its front",
        "## pieces' steps begin down them (\"tops\"), its own colour (\"tint\", its two-level front piece's",
        "## mean) and the wall style it is painted for (\"home\": drawn in its own colour there).",
        "##",
        "## Owner: world (elevation).",
        "",
        "const SETS := {",
    ]
    for name, data in sets.items():
        tint = data["tint"]
        lines.append(f'\t"{name}": {{')
        lines.append(f'\t\t"home": "{data["home"]}",')
        lines.append(f'\t\t"tint": Color({tint[0]}, {tint[1]}, {tint[2]}),')
        tops = ", ".join(f"{k}: {v:.4f}" for k, v in sorted(data["tops"].items()))
        lines.append(f'\t\t"tops": {{{tops}}},')
        lines.append('\t\t"parts": {')
        for part, (path, mean) in data["parts"].items():
            lines.append(f'\t\t\t"{part}": ["{path}", Color({mean[0]}, {mean[1]}, {mean[2]})],')
        lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    lines.append("const STYLE_SETS := {")
    for name, data in sets.items():
        for style in data["styles"]:
            lines.append(f'\t"{style}": "{name}",')
    lines.append("}")
    path = ROOT / "godot" / "game" / "world" / "elevation" / "elevation_stairs_sets.gd"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {path}")


def save(image: np.ndarray, name: str, preview: Path | None) -> None:
    out = Image.fromarray(np.clip(image, 0, 255).astype(np.uint8))
    out.save(OUT / name)
    mean = image.reshape(-1, 3).mean(axis=0) / 255.0
    print(f"{name}: {out.size[0]}x{out.size[1]} px, mean colour ({mean[0]:.3f}, {mean[1]:.3f}, {mean[2]:.3f})")
    if preview is not None:
        tiled = Image.new("RGB", (out.width * 3, out.height * 3))
        for x in range(3):
            for y in range(3):
                tiled.paste(out, (x * out.width, y * out.height))
        tiled.save(preview / name.replace(".png", "-tiled.png"))


def wall_colours() -> None:
    """Each wall style's mean colour (opaque pixels of <style>-wall.png), as GDScript."""
    print("const STONE_COLOURS := {")
    for path in sorted(OUT.glob("*-wall.png")):
        rgba = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float64)
        opaque = rgba[rgba[..., 3] > 200][:, :3]
        mean = opaque.mean(axis=0) / 255.0
        print(f'\t"{path.stem.removesuffix("-wall")}": Color({mean[0]:.3f}, {mean[1]:.3f}, {mean[2]:.3f}),')
    print("}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--preview", type=Path, help="also write 3x3 tiled previews here")
    args = parser.parse_args()
    if args.preview is not None:
        args.preview.mkdir(parents=True, exist_ok=True)
    for part in PICKS:
        save(build_row(part), f"stairs-{part}.png", args.preview)
    save(build_blocks(), "stairs-blocks.png", args.preview)
    sets = {}
    for name, spec in SETS.items():
        sets[name] = build_set(name, spec)
    write_sets(sets)
    wall_colours()


if __name__ == "__main__":
    main()
