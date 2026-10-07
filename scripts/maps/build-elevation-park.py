#!/usr/bin/env python3
"""Builds the Elevation Park at the south end of the playground (docs/godot/ELEVATION.md).

The playground (godot/game/scenes/worlds/playground.tscn) keeps its first BASE_ROWS rows; this
tool appends the park's rows of grass below them and paints the park's levels on the world's
`elevation` TileMapLayer (elevation_tileset.tres + elevation_layer.gd), creating that layer the
first time. Re-running it rebuilds the park from scratch, so after hand edits in the editor to the
park area, change the layout here instead (or stop using the tool).

What the park shows, top to bottom: square hills at levels 1, 2 and 3; diamond hills; octagon
hills; a square hole (-1), a diamond hole (-2) and an octagon hole (-3); terraces (an octagon of
levels 1-3 nested), a sand plateau and a snow plateau (their lips are their own ground), and a
ridge of levels 1, 2 and 3 side by side on one south edge. Stairs (flights with a landing and
railings, docs/godot/ELEVATION.md "Stairs") climb every square and octagon hill, the terraces, the
plateaus, the ridge and two of the holes. Water: the diamond hole is flooded, and further down a
two-level cliff stands in a lake with a small island (water at the foot of a wall laps against
it). Then a row of plateaus on forest floor, moss, fallen leaves, cavern, crystal and cobble shows
those grounds' cliff tops and feet. Last, the stairs showcase: a level-2 octagon with a flight on
each of its 8 sides, and a level-1 octagon with flights two cells wide and open landings. A flight
is painted as one stairs cell per cell of width: the first cell past the rim, on the lower ground,
in its direction; it needs a cell of lower ground per level beyond the wall (1.5 to the north).
The water needs no bodies of
its own: shallow water is walkable and deep water collides through its tiles (terrain_tileset.tres);
the tool removes the `park_water_<n>` bodies older runs wrote.

Run it while the Godot editor does not have the playground open (or reload it there afterwards).

Usage: python scripts/maps/build-elevation-park.py
"""
from __future__ import annotations

import base64
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "godot/game/scenes/worlds/playground.tscn"
COLUMNS = 40
## The playground's own rows; the park starts below them.
BASE_ROWS = 28
ROWS = 150
## The lake, the ground row and the showcase sit this many rows lower than they first did (room for
## the ridge's flights).
SHIFT = 3
## Terrain tile set sources (godot/game/world/terrain_tileset.tres).
GRASS = 7
SAND = 10
SNOW = 6
WATER = 11
DEEP_WATER = 3
## The other grounds with cliff art, for the ground row (left to right).
GROUND_ROW = [4, 5, 0, 1, 2, 19]   # forest floor, forest moss, amberleaf, cavern, crystal, cobble
SHEET_CELLS = 19
## Elevation tile set atlas (column, row) of each level (elevation_tileset.tres); stairs: row 1
## with a railed landing, row 2 with an open one, one column per direction (STAIRS_COLUMN).
STAIRS = "stairs"
LEVEL_ATLAS = {-3: (0, 0), -2: (1, 0), -1: (2, 0), 1: (3, 0), 2: (4, 0), 3: (5, 0)}
STAIRS_COLUMN = {"s": 0, "sw": 1, "w": 2, "nw": 3, "n": 4, "ne": 5, "e": 6, "se": 7}
TILESET_ID = "elevation_tiles"
SCRIPT_ID = "elevation_layer"


def rect(x0: int, y0: int, x1: int, y1: int) -> set[tuple[int, int]]:
    return {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}


def octagon(x0: int, y0: int, x1: int, y1: int, cut: int) -> set[tuple[int, int]]:
    """A rectangle with each corner cut by a staircase of `cut` single steps (45° edges)."""
    cells = set()
    for x, y in rect(x0, y0, x1, y1):
        dx = min(x - x0, x1 - x)
        dy = min(y - y0, y1 - y)
        if dx + dy >= cut:
            cells.add((x, y))
    return cells


def diamond(cx: int, cy: int, r: int) -> set[tuple[int, int]]:
    return {(x, y) for x in range(cx - r, cx + r + 1) for y in range(cy - r, cy + r + 1) if abs(x - cx) + abs(y - cy) <= r}


def park() -> tuple[dict[tuple[int, int], int | str], dict[tuple[int, int], int]]:
    """(levels, grounds): painted level (or (STAIRS, direction, open landing)) and terrain source
    per park cell."""
    levels: dict[tuple[int, int], int | tuple] = {}
    grounds: dict[tuple[int, int], int] = {}

    def paint(cells: set[tuple[int, int]], level: int | tuple, ground: int | None = None) -> None:
        for cell in cells:
            levels[cell] = level
            if ground is not None:
                grounds[cell] = ground

    def stairs(x: int, y: int, direction: str = "s", open_landing: bool = False) -> None:
        """A flight one cell wide leaving the rim behind cell (x, y) towards `direction`."""
        levels[(x, y)] = (STAIRS, direction, open_landing)

    def octagon_stairs(x0: int, y0: int, x1: int, y1: int, cut: int, width: dict, open_landing: dict) -> None:
        """A flight on every side of octagon(x0, y0, x1, y1, cut); `width` and `open_landing` per
        direction (default one cell, railed). A 45° side's stairs cells are the lower cells whose
        corner the chamfer fills."""
        xm, ym = (x0 + x1) // 2, (y0 + y1) // 2
        i = (cut - 1) // 2
        starts = {
            "s": ((xm, y1 + 1), (1, 0)), "n": ((xm, y0 - 1), (1, 0)),
            "e": ((x1 + 1, ym), (0, 1)), "w": ((x0 - 1, ym), (0, 1)),
            "se": ((x1 - i, y1 - cut + i + 1), (1, -1)), "sw": ((x0 + i, y1 - cut + i + 1), (1, 1)),
            "ne": ((x1 - i, y0 + cut - i - 1), (1, 1)), "nw": ((x0 + i, y0 + cut - i - 1), (1, -1)),
        }
        for direction, ((x, y), (sx, sy)) in starts.items():
            for k in range(width.get(direction, 1)):
                stairs(x + sx * k, y + sy * k, direction, open_landing.get(direction, False))

    # Square hills (cubes): only the south face shows.
    paint(rect(2, 31, 8, 34), 1)
    paint(rect(14, 31, 22, 35), 2)
    paint(rect(27, 31, 37, 36), 3)
    # Diamond hills: the south-west and south-east faces.
    paint(diamond(6, 45, 3), 1)
    paint(diamond(19, 45, 3), 2)
    paint(diamond(32, 45, 3), 3)
    # Octagon hills: south-west, south and south-east faces.
    paint(octagon(1, 54, 10, 60, 2), 1)
    paint(octagon(14, 54, 24, 60, 3), 2)
    paint(octagon(28, 54, 38, 60, 3), 3)
    # Holes: the wall shows on the far (north) side.
    paint(rect(2, 67, 8, 71), -1)
    paint(diamond(19, 69, 3), -2)
    paint(octagon(28, 66, 38, 75, 3), -3)
    # Terraces: levels 1-3 nested, with walkable ledges.
    paint(octagon(1, 79, 13, 92, 3), 1)
    paint(octagon(3, 80, 11, 88, 2), 2)
    paint(rect(5, 81, 9, 84), 3)
    # A sand plateau and a snow plateau: their lips and the ground on top are their own.
    paint(rect(16, 79, 23, 83), 1, SAND)
    paint(octagon(27, 78, 37, 84, 2), 2, SNOW)
    # A ridge of levels 1, 2 and 3 side by side on one south edge.
    paint(rect(15, 90, 21, 93), 1)
    paint(rect(22, 89, 29, 93), 2)
    paint(rect(30, 88, 37, 93), 3)
    # Stairs: down the south face, onto the ground in front (a cell per level); the level-3 square's
    # keep clear of the diamond below it, the level-3 octagon's and the snow plateau's leave by a
    # side with room.
    stairs(5, 35)
    stairs(18, 36)
    stairs(28, 37)
    stairs(5, 61)
    stairs(19, 61)
    stairs(29, 59, "sw")
    stairs(5, 67)
    stairs(33, 66)
    stairs(7, 93)
    stairs(7, 89)
    stairs(7, 85)
    stairs(19, 84)
    stairs(26, 81, "w")
    stairs(18, 94)
    stairs(25, 94)
    stairs(33, 94)
    # The diamond hole is flooded: water laps at its far walls.
    for x, y in diamond(19, 69, 3):
        grounds[(x, y)] = WATER
    # A two-level cliff standing in a lake, with an island; stairs down to the shore at the west.
    paint(rect(1, 98 + SHIFT, 38, 99 + SHIFT), 2)
    stairs(3, 100 + SHIFT)
    for cell in rect(6, 100 + SHIFT, 38, 110 + SHIFT):
        grounds[cell] = WATER
    for x, y in rect(26, 104 + SHIFT, 37, 110 + SHIFT):
        if ((x - 31.5) / 5.5) ** 2 + ((y - 107.0 - SHIFT) / 3.2) ** 2 <= 1.0:
            grounds[(x, y)] = DEEP_WATER
    paint(rect(17, 104 + SHIFT, 22, 106 + SHIFT), 1, GRASS)
    # A row of two-level plateaus, one per other ground, standing on the same ground (its lip and
    # its foot), with stairs.
    for i, source in enumerate(GROUND_ROW):
        x0 = 1 + i * 6 + i // 3
        for cell in rect(x0, 113 + SHIFT, x0 + 5, 120 + SHIFT):
            grounds[cell] = source
        paint(rect(x0 + 1, 114 + SHIFT, x0 + 4, 116 + SHIFT), 2)
        stairs(x0 + 3, 117 + SHIFT)
    # The stairs showcase: a flight on every side of a level-2 octagon, then of a level-1 one with
    # flights two cells wide (north, south, east, west) and open landings (south and the diagonals).
    paint(octagon(4, 131, 14, 139, 3), 2)
    octagon_stairs(4, 131, 14, 139, 3, {}, {})
    paint(octagon(22, 131, 34, 139, 3), 1)
    octagon_stairs(22, 131, 34, 139, 3, {"s": 2, "n": 2, "e": 2, "w": 2},
                   {"s": True, "se": True, "sw": True, "ne": True, "nw": True})
    return levels, grounds


def decode(data: bytes) -> tuple[bytes, list[tuple[int, int, int, int, int, int]]]:
    header, body = data[:2], data[2:]
    cells = [struct.unpack_from("<hhHHHH", body, i) for i in range(0, len(body), 12)]
    return header, cells


def encode(header: bytes, cells: list[tuple[int, int, int, int, int, int]]) -> bytes:
    return header + b"".join(struct.pack("<hhHHHH", *cell) for cell in cells)


def read_bytes(literal: str) -> tuple[bytes, bool]:
    """A PackedByteArray's contents: base64 (scene format 4, what the editor saves) or a list of
    numbers (format 3). Returns (data, is_base64)."""
    literal = literal.strip()
    if literal.startswith('"'):
        return base64.b64decode(literal.strip('"')), True
    return bytes(int(b) for b in literal.split(",") if b.strip()), False


def write_bytes(data: bytes, as_base64: bool) -> str:
    return '"' + base64.b64encode(data).decode("ascii") + '"' if as_base64 else ", ".join(str(b) for b in data)


def node_header(name: str, node_type: str, parent: str) -> str:
    """Regex of a node's header line, whatever else the editor writes in it (unique_id, ...)."""
    return r'\[node name="' + re.escape(name) + r'" type="' + node_type + r'" parent="' + re.escape(parent) + r'"[^\]\n]*\]\n'


def main() -> None:
    text = SCENE.read_text(encoding="utf-8")
    levels, grounds = park()

    # Ground: the playground's own rows, then the park's grounds. Only the tile data, the cell
    # count and the rows change; every other line of the node (metadata other sessions add) stays.
    ground_match = re.search('(' + node_header("ground", "TileMapLayer", ".") + r'(?:[^\[\n].*\n)*?)tile_map_data = PackedByteArray\(([^)]*)\)', text)
    assert ground_match, "ground layer not found"
    data, as_base64 = read_bytes(ground_match.group(2))
    header, cells = decode(data)
    cells = [c for c in cells if c[1] < BASE_ROWS]
    for y in range(BASE_ROWS, ROWS):
        for x in range(COLUMNS):
            source = grounds.get((x, y), GRASS)
            cells.append((x, y, source, x % SHEET_CELLS, y % SHEET_CELLS, 0))
    text = text[: ground_match.start(2)] + write_bytes(encode(header, cells), as_base64) + text[ground_match.end(2):]
    text = re.sub(r"metadata/source_cell_count = \d+", f"metadata/source_cell_count = {COLUMNS * ROWS}", text, count=1)
    text = re.sub(r"(\[node name=\"ground\"[\s\S]*?)metadata/rows = \d+", rf"\g<1>metadata/rows = {ROWS}", text, count=1)
    text = re.sub(r"(\[node name=\"world-definition\"[\s\S]*?)\nrows = \d+", rf"\g<1>\nrows = {ROWS}", text, count=1)

    # Water bodies older runs wrote (shallow water is walkable now, deep water collides by its tiles).
    text = re.sub(r'\[sub_resource type="RectangleShape2D" id="park_water_shape_\d+"\]\nsize = [^\n]*\n\n', "", text)
    text = re.sub(r'\[node name="park_water_\d+" type="StaticBody2D" parent="ground/TileCollision"[^\]\n]*\]\n(?:[^\[\n].*\n|\n)*'
                  r'\[node name="Shape" type="CollisionShape2D" parent="ground/TileCollision/park_water_\d+"[^\]\n]*\]\n(?:[^\[\n].*\n|\n)*', "", text)

    # Elevation layer.
    def atlas(level: int | tuple) -> tuple[int, int]:
        if isinstance(level, tuple):
            return STAIRS_COLUMN[level[1]], 2 if level[2] else 1
        return LEVEL_ATLAS[level]

    elevation_cells = [(x, y, 0, *atlas(level), 0) for (x, y), level in sorted(levels.items(), key=lambda kv: (kv[0][1], kv[0][0]))]
    elevation_data = encode(b"\x00\x00", elevation_cells)
    if f'id="{TILESET_ID}"' not in text:
        last_ext = list(re.finditer(r"\[ext_resource [^\n]*\]\n", text))[-1]
        text = text[: last_ext.end()] + (
            f'[ext_resource type="TileSet" path="res://game/world/elevation/elevation_tileset.tres" id="{TILESET_ID}"]\n'
            f'[ext_resource type="Script" path="res://game/world/elevation/elevation_layer.gd" id="{SCRIPT_ID}"]\n'
        ) + text[last_ext.end():]
    existing = re.search('(' + node_header("elevation", "TileMapLayer", ".") + r')(?:[^\[\n].*\n|\n)*', text)
    node = (
        (existing.group(1) if existing else '[node name="elevation" type="TileMapLayer" parent="."]\n')
        + "z_index = -1\n"
        f"tile_map_data = PackedByteArray({write_bytes(elevation_data, as_base64)})\n"
        f'tile_set = ExtResource("{TILESET_ID}")\n'
        f'script = ExtResource("{SCRIPT_ID}")\n\n'
    )
    if existing:
        text = text[: existing.start()] + node + text[existing.end():]
    else:
        anchor = text.index('[node name="world-definition"')
        text = text[:anchor] + node + text[anchor:]
    SCENE.write_text(text, encoding="utf-8", newline="\n")
    print(f"playground: {COLUMNS}x{ROWS} cells, {len(levels)} elevation cells")


if __name__ == "__main__":
    main()
