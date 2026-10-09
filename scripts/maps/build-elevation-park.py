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
each of its 8 sides, and a level-1 octagon with flights two cells wide and open landings.

Wall styles (docs/godot/ELEVATION.md "Wall styles"): the plateaus' walls take their ground's style
(sandstone, snow rock, and the ground row's root rock, mossy rock, red rock, cave rock, crystal rock
and masonry); the tool paints other styles on the `cliffs` layer (cliff_tileset.tres +
cliff_layer.gd) over grass hills: the diamonds, the octagons, the octagon hole's surroundings, the
ridge (three styles meeting on one edge), the east half of the lake cliff and the stairs showcase
(railings in their cliff's rock). The square hills, the terraces and the other holes keep
meadow rock. A flight
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
## Cliffs layer: atlas column of each wall style (cliff_tileset.tres).
CLIFF_ATLAS = {"meadow-rock": 0, "snow-rock": 1, "sandstone": 2, "cave-rock": 3, "crystal-rock": 4,
               "mossy-rock": 5, "masonry": 6, "root-rock": 7, "red-rock": 8}
CLIFF_TILESET_ID = "cliff_tiles"
CLIFF_SCRIPT_ID = "cliff_layer"


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


def cliffs() -> dict[tuple[int, int], str]:
    """Wall styles painted over grass tops (the plateaus keep their ground's style)."""
    styles: dict[tuple[int, int], str] = {}

    def paint(cells: set[tuple[int, int]], style: str) -> None:
        for cell in cells:
            styles[cell] = style

    # Diamond hills: sandstone, mossy rock, crystal rock.
    paint(diamond(6, 45, 3), "sandstone")
    paint(diamond(19, 45, 3), "mossy-rock")
    paint(diamond(32, 45, 3), "crystal-rock")
    # Octagon hills: masonry, red rock, cave rock.
    paint(octagon(1, 54, 10, 60, 2), "masonry")
    paint(octagon(14, 54, 24, 60, 3), "red-rock")
    paint(octagon(28, 54, 38, 60, 3), "cave-rock")
    # The octagon hole's far wall hangs from the ground around it.
    paint(rect(27, 63, 39, 76), "root-rock")
    # The ridge: three styles meeting on one south edge.
    paint(rect(15, 90, 21, 93), "cave-rock")
    paint(rect(22, 89, 29, 93), "masonry")
    paint(rect(30, 88, 37, 93), "sandstone")
    # The lake cliff's east half, the water lapping at another rock.
    paint(rect(20, 98 + SHIFT, 38, 99 + SHIFT), "mossy-rock")
    # The stairs showcase: railings in their cliff's rock.
    paint(octagon(4, 131, 14, 139, 3), "red-rock")
    paint(octagon(22, 131, 34, 139, 3), "masonry")
    return styles


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


def write_layer(text: str, name: str, cells: list[tuple[int, int, int, int, int, int]], as_base64: bool,
                tileset_id: str, script_id: str, before: str) -> str:
    """Writes the TileMapLayer `name` (its tile data, tile set and script), keeping its header line;
    a new one goes before the node header `before`."""
    existing = re.search('(' + node_header(name, "TileMapLayer", ".") + r')(?:[^\[\n].*\n|\n)*', text)
    data = write_bytes(encode(b"\x00\x00", cells), as_base64)
    node = (
        (existing.group(1) if existing else f'[node name="{name}" type="TileMapLayer" parent="."]\n')
        + "z_index = -1\n"
        f"tile_map_data = PackedByteArray({data})\n"
        f'tile_set = ExtResource("{tileset_id}")\n'
        f'script = ExtResource("{script_id}")\n\n'
    )
    if existing:
        return text[: existing.start()] + node + text[existing.end():]
    anchor = text.index(before)
    return text[:anchor] + node + text[anchor:]


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

    def by_row(cells: dict) -> list:
        return sorted(cells.items(), key=lambda kv: (kv[0][1], kv[0][0]))

    elevation_cells = [(x, y, 0, *atlas(level), 0) for (x, y), level in by_row(levels)]
    resources = [
        ("TileSet", "res://game/world/elevation/elevation_tileset.tres", TILESET_ID),
        ("Script", "res://game/world/elevation/elevation_layer.gd", SCRIPT_ID),
        ("TileSet", "res://game/world/elevation/cliffs/cliff_tileset.tres", CLIFF_TILESET_ID),
        ("Script", "res://game/world/elevation/cliffs/cliff_layer.gd", CLIFF_SCRIPT_ID),
    ]
    for kind, path, resource_id in resources:
        if f'id="{resource_id}"' not in text:
            last_ext = list(re.finditer(r"\[ext_resource [^\n]*\]\n", text))[-1]
            text = text[: last_ext.end()] + f'[ext_resource type="{kind}" path="{path}" id="{resource_id}"]\n' + text[last_ext.end():]
    text = write_layer(text, "elevation", elevation_cells, as_base64, TILESET_ID, SCRIPT_ID, '[node name="world-definition"')
    styles = cliffs()
    cliff_cells = [(x, y, 0, CLIFF_ATLAS[style], 0, 0) for (x, y), style in by_row(styles)]
    text = write_layer(text, "cliffs", cliff_cells, as_base64, CLIFF_TILESET_ID, CLIFF_SCRIPT_ID, '[node name="world-definition"')
    SCENE.write_text(text, encoding="utf-8", newline="\n")
    print(f"playground: {COLUMNS}x{ROWS} cells, {len(levels)} elevation cells, {len(styles)} cliffs cells")


if __name__ == "__main__":
    main()
