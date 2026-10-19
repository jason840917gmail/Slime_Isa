#!/usr/bin/env python3
"""Build the picture-only palette for the shared connected-fence layer.

Writes fence_paint_tiles.png and the tile set; then run
"<Godot console exe>" --headless --path godot -s res://tools/pack_fence_paint_tiles.gd, which saves
the palette as fence_paint_tiles.res (a native texture the tile set uses: no editor import needed).
The dungeon dividers' gate tiles (docs/godot/FENCES.md "Dungeon dividers") come after the styles,
one tile each (row 0), showing the gate's own picture."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot/asset/MAPS/fences/fence_paint_tiles.png"
TILESET = ROOT / "godot/game/world/fences/fence_tileset.tres"
SIZE = 64
TILE_UID = "uid://b6hbbbrfkchxq"
TEXTURE_UID = "uid://t4lhoo46qy2k"
STYLES = [
    ("wood", (153, 98, 49)),
    ("snow", (207, 227, 247)),
    ("stone", (129, 135, 139)),
    ("sandstone", (206, 146, 82)),
    ("twig", (111, 145, 65)),
    ("picket", (173, 95, 48)),
    ("crystal", (145, 113, 221)),
    ("lair-divider", (226, 202, 152)),
]
## Divider gate tiles: (style, picture) in the columns after STYLES, row 0 only.
GATES = [
    ("lair-divider-eye", ROOT / "godot/asset/MAPS/objects/dungeon/divider-eye-block.png"),
    ("lair-divider-pen", ROOT / "godot/asset/MAPS/objects/dungeon/divider-pen-gate.png"),
]
DIRECTIONS = [
    ("N", 0, (0, -1)), ("NE", 1, (1, -1)), ("E", 2, (1, 0)), ("SE", 3, (1, 1)),
    ("S", 4, (0, 1)), ("SW", 5, (-1, 1)), ("W", 6, (-1, 0)), ("NW", 7, (-1, -1)),
]
# The first row connects to all neighboring fence cells. The next eight rows show one direction.
ROWS = [None] + DIRECTIONS


def _atlas_source() -> str:
    lines = [
        '[gd_resource type="TileSet" format=3 uid="%s"]' % TILE_UID,
        "",
        '[ext_resource type="Texture2D" path="res://asset/MAPS/fences/fence_paint_tiles.res" id="1_tiles"]',
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_fences"]',
        'texture = ExtResource("1_tiles")',
        'texture_region_size = Vector2i(64, 64)',
    ]
    for row, direction in enumerate(ROWS):
        direction_id = -1 if direction is None else direction[1]
        for column, (style, _color) in enumerate(STYLES):
            lines.extend([
                f"{column}:{row}/0 = 0",
                f'{column}:{row}/0/custom_data_0 = "{style}"',
                f"{column}:{row}/0/custom_data_1 = {direction_id}",
            ])
    for index, (style, _picture) in enumerate(GATES):
        column = len(STYLES) + index
        lines.extend([
            f"{column}:0/0 = 0",
            f'{column}:0/0/custom_data_0 = "{style}"',
            f"{column}:0/0/custom_data_1 = -1",
        ])
    lines.extend([
        "",
        "[resource]",
        "tile_size = Vector2i(64, 64)",
        'custom_data_layer_0/name = "fence_style"',
        "custom_data_layer_0/type = 4",
        'custom_data_layer_1/name = "fence_direction"',
        "custom_data_layer_1/type = 2",
        'sources/0 = SubResource("TileSetAtlasSource_fences")',
        "",
    ])
    return "\n".join(lines)


def _line(draw: ImageDraw.ImageDraw, points: tuple[tuple[float, float], ...], color: tuple[int, int, int], width: int) -> None:
    draw.line(points, fill=color + (255,), width=width, joint="curve")


def _post(draw: ImageDraw.ImageDraw, style: str, point: tuple[float, float], color: tuple[int, int, int]) -> None:
    x, y = point
    if style in ("stone", "sandstone", "lair-divider"):
        draw.rounded_rectangle((x - 4, y - 5, x + 4, y + 5), radius=2, fill=color + (255,), outline=(37, 34, 29, 255), width=2)
        if style == "sandstone":
            _line(draw, ((x - 2, y), (x + 2, y)), (112, 72, 39), 1)
    elif style == "crystal":
        draw.polygon(((x, y - 7), (x + 5, y + 1), (x + 2, y + 6), (x - 3, y + 6), (x - 5, y + 1)),
                     fill=color + (255,), outline=(47, 37, 68, 255))
    else:
        draw.ellipse((x - 4, y - 5, x + 4, y + 5), fill=color + (255,), outline=(37, 34, 29, 255), width=2)
        if style == "snow":
            draw.ellipse((x - 4, y - 7, x + 4, y - 2), fill=(249, 251, 255, 255), outline=(71, 93, 112, 255), width=1)
        elif style == "twig":
            draw.ellipse((x + 2, y - 6, x + 7, y - 2), fill=(113, 169, 59, 255), outline=(45, 70, 37, 255), width=1)


def _arrow(draw: ImageDraw.ImageDraw, start: tuple[float, float], end: tuple[float, float], direction: tuple[int, int]) -> None:
    dx, dy = direction
    # Double outline keeps the selected direction readable against every fence material.
    _line(draw, (start, end), (19, 26, 25), 6)
    _line(draw, (start, end), (255, 250, 224), 3)
    ux, uy = float(dx), float(dy)
    length = max(abs(ux), abs(uy), 1.0)
    ux, uy = ux / length, uy / length
    px, py = -uy, ux
    tip = end
    base = (tip[0] - ux * 8, tip[1] - uy * 8)
    triangle = (tip, (base[0] + px * 5, base[1] + py * 5), (base[0] - px * 5, base[1] - py * 5))
    draw.polygon(triangle, fill=(255, 250, 224, 255), outline=(19, 26, 25, 255))


def _draw_material(draw: ImageDraw.ImageDraw, style: str, color: tuple[int, int, int], direction: tuple[int, int] | None) -> None:
    cx, cy = 32.0, 38.0
    dark = (49, 41, 32)
    if direction is None:
        # A small eight-way connection picture: one painted cell joins its neighbors.
        for _name, _index, (dx, dy) in DIRECTIONS:
            edge = (cx + dx * 25.0, cy + dy * 25.0)
            _line(draw, ((cx, cy), edge), color, 3 if style not in ("stone", "sandstone", "lair-divider") else 5)
            draw.ellipse((edge[0] - 2, edge[1] - 2, edge[0] + 2, edge[1] + 2), fill=(255, 246, 207, 255), outline=dark + (255,), width=1)
        _post(draw, style, (cx, cy), color)
        return

    dx, dy = direction
    length = 25.0 / max(abs(dx), abs(dy), 1)
    start = (cx, cy)
    end = (cx + dx * length, cy + dy * length)
    px, py = -dy, dx
    rail_width = 5 if style in ("stone", "sandstone", "lair-divider") else 3
    for offset in (-4, 3):
        a = (start[0] + px * offset, start[1] + py * offset)
        b = (end[0] + px * offset, end[1] + py * offset)
        _line(draw, (a, b), (42, 35, 27), rail_width + 2)
        _line(draw, (a, b), color, rail_width)
    if style == "sandstone":
        mid = ((start[0] + end[0]) * 0.5, (start[1] + end[1]) * 0.5)
        _line(draw, ((mid[0] + px * 3, mid[1] + py * 3), (mid[0] + px * 4, mid[1] + py * 4)), (111, 72, 43), 2)
    if style == "twig":
        leaf = (cx + dx * 8 - dy * 5, cy + dy * 8 + dx * 5)
        draw.ellipse((leaf[0] - 3, leaf[1] - 4, leaf[0] + 3, leaf[1] + 2), fill=(132, 186, 73, 255), outline=(44, 76, 39, 255), width=1)
    if style == "picket":
        for fraction in (0.32, 0.58, 0.82):
            x = cx + dx * length * fraction
            y = cy + dy * length * fraction
            draw.line((x, y + 4, x, y - 8), fill=(43, 35, 27, 255), width=4)
            draw.line((x, y + 3, x, y - 7), fill=color + (255,), width=2)
            draw.polygon(((x, y - 9), (x - 2, y - 5), (x + 2, y - 5)), fill=color + (255,))
    if style == "crystal":
        for fraction, size in ((0.42, 4), (0.67, 3)):
            x = cx + dx * length * fraction + px * 7
            y = cy + dy * length * fraction + py * 7
            draw.polygon(((x, y - size), (x + size, y + size), (x - size, y + size)), fill=(194, 179, 250, 255), outline=(65, 51, 104, 255))
    _post(draw, style, start, color)
    # This marker belongs to the neighboring painted cell and makes the selected link obvious.
    draw.ellipse((end[0] - 3, end[1] - 3, end[0] + 3, end[1] + 3), fill=(255, 239, 179, 255), outline=dark + (255,), width=1)
    arrow_start = (cx + dx * 17.0, cy + dy * 17.0)
    arrow_end = (cx + dx * 23.0, cy + dy * 23.0)
    _arrow(draw, arrow_start, arrow_end, direction)


def _draw_tile(image: Image.Image, column: int, row: int, style: str, color: tuple[int, int, int],
               direction: tuple[int, int] | None) -> None:
    x0, y0 = column * SIZE, row * SIZE
    tile = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)
    background = (18, 26, 20, 24)
    draw.rectangle((0, 0, SIZE - 1, SIZE - 1), fill=background, outline=(223, 229, 211, 205), width=1)
    _draw_material(draw, style, color, direction)
    # A colored foot swatch identifies material without a letter or abbreviation.
    draw.rounded_rectangle((5, 54, 15, 59), radius=2,
                           fill=color + (255,), outline=(31, 31, 28, 235), width=1)
    image.alpha_composite(tile, (x0, y0))


def main() -> None:
    image = Image.new("RGBA", (SIZE * (len(STYLES) + len(GATES)), SIZE * len(ROWS)), (0, 0, 0, 0))
    for row, direction_entry in enumerate(ROWS):
        direction = None if direction_entry is None else direction_entry[2]
        for column, (style, color) in enumerate(STYLES):
            _draw_tile(image, column, row, style, color, direction)
    for index, (_style, picture) in enumerate(GATES):
        tile = Image.new("RGBA", (SIZE, SIZE), (18, 26, 20, 24))
        ImageDraw.Draw(tile).rectangle((0, 0, SIZE - 1, SIZE - 1), outline=(223, 229, 211, 205), width=1)
        art = Image.open(picture).convert("RGBA")
        art.thumbnail((SIZE - 10, SIZE - 10), Image.Resampling.LANCZOS)
        tile.alpha_composite(art, ((SIZE - art.width) // 2, (SIZE - art.height) // 2))
        image.alpha_composite(tile, ((len(STYLES) + index) * SIZE, 0))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUT)
    TILESET.write_text(_atlas_source(), encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)} and {TILESET.relative_to(ROOT)} ({len(STYLES)} picture styles, 8 directions + all-neighbor connector, {len(GATES)} gate tiles)")


if __name__ == "__main__":
    main()
