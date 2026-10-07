#!/usr/bin/env python3
"""Builds the Fence Park, a dev world for the fences along hill rims (docs/godot/FENCES.md).

Writes godot/game/scenes/worlds/fence-park.tscn from scratch: a grass field with hills and holes of
every shape, fenced on the `fences` layer (fence_tileset.tres + fence_layer.gd):

- a level-1 square (fenced all round but a gap on its east side, to drop off), where the player
  spawns, with a flight of stairs down its south wall and one down its west side (the fence leaves
  a gap for each);
- a level-2 diamond (four diagonal faces and their tips) fenced all round;
- a level-1 octagon (all 8 faces) with a level-2 octagon on top, both fenced all round;
- a square hole and an octagon hole, fenced all round on the ground around them;
- a level-2 square fenced on its south rim only (a run with open ends);
- a level-1 diamond fenced on its east half only, ending at its tips;
- a level-3 block, fenced all round (the tallest wall under a fence);
- two rows of plots, one per ground, each with its own hill (an octagon, a diamond, a square, a
  terrace, a hole) fenced with "auto", so the fence takes the ground's style: snowy wood on snow,
  sandstone on sand, vine-wrapped branches on forest floor and moss, pickets on fallen leaves, a
  stone wall on cavern rock and on cobble, crystal posts on crystal rock.

Re-running it rebuilds the world from scratch (hand edits are lost). Run it while the Godot editor
does not have the scene open (or reload it there afterwards).

Usage: python scripts/maps/build-fence-park.py
"""
from __future__ import annotations

import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "godot/game/scenes/worlds/fence-park.tscn"
MAP_ID = "fence-park"
COLUMNS = 40
ROWS = 63
TILE = 64
SHEET_CELLS = 19
## Terrain tile set sources (godot/game/world/terrain_tileset.tres).
GRASS = 7
SNOW = 6
SAND = 10
FOREST_FLOOR = 4
FOREST_MOSS = 5
AMBERLEAF = 0
CAVERN = 1
CRYSTAL = 2
COBBLE = 19
## Elevation tile set atlas column per level (elevation_tileset.tres), fence tile set column per
## style (fence_tileset.tres).
LEVEL_ATLAS = {-3: (0, 0), -2: (1, 0), -1: (2, 0), 1: (3, 0), 2: (4, 0), 3: (5, 0),
               "stairs-s": (0, 1), "stairs-w": (2, 1)}
FENCE_ATLAS = {"auto": 0, "wood": 1, "snow": 2, "stone": 3, "sandstone": 4, "twig": 5, "picket": 6, "crystal": 7}
SPAWN_CELL = (6, 5)


def rect(x0: int, y0: int, x1: int, y1: int) -> set[tuple[int, int]]:
    return {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}


def octagon(x0: int, y0: int, x1: int, y1: int, cut: int) -> set[tuple[int, int]]:
    """A rectangle with each corner cut by a staircase of `cut` single steps (45° edges)."""
    return {(x, y) for x, y in rect(x0, y0, x1, y1) if min(x - x0, x1 - x) + min(y - y0, y1 - y) >= cut}


def diamond(cx: int, cy: int, r: int) -> set[tuple[int, int]]:
    return {(x, y) for x in range(cx - r, cx + r + 1) for y in range(cy - r, cy + r + 1) if abs(x - cx) + abs(y - cy) <= r}


def ring(cells: set[tuple[int, int]]) -> set[tuple[int, int]]:
    """The cells touching `cells` (8 ways) outside it."""
    out = set()
    for x, y in cells:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if (x + dx, y + dy) not in cells:
                    out.add((x + dx, y + dy))
    return out


def park() -> tuple[dict[tuple[int, int], int | str], dict[tuple[int, int], str], dict[tuple[int, int], int]]:
    levels: dict[tuple[int, int], int | str] = {}
    fences: dict[tuple[int, int], str] = {}
    grounds: dict[tuple[int, int], int] = {}

    def hill(cells: set[tuple[int, int]], level: int, fenced: set[tuple[int, int]] | None = None, style: str = "wood") -> None:
        for cell in cells:
            levels[cell] = level
        for cell in cells if fenced is None else fenced:
            fences[cell] = style

    square = rect(2, 2, 11, 8)
    hill(square, 1, {c for c in square if not (c[0] == 11 and 4 <= c[1] <= 5)})
    # Stairs on the first cell past the rim, pointing down (docs/godot/ELEVATION.md, Authoring).
    levels[(5, 9)] = "stairs-s"
    levels[(1, 6)] = "stairs-w"
    hill(diamond(20, 6, 4), 2)
    hill(octagon(26, 2, 37, 10, 3), 1)
    hill(octagon(29, 4, 34, 8, 2), 2)
    hole = rect(4, 15, 10, 19)
    hill(hole, -1, set())
    for cell in ring(hole):
        fences[cell] = "wood"
    octagon_hole = octagon(16, 14, 24, 21, 2)
    hill(octagon_hole, -1, set())
    for cell in ring(octagon_hole):
        fences[cell] = "wood"
    south_only = rect(28, 14, 36, 18)
    hill(south_only, 2, {c for c in south_only if c[1] == 18})
    half = diamond(8, 27, 3)
    hill(half, 1, {c for c in half if c[0] >= 8})
    hill(rect(20, 26, 27, 30), 3)

    # Plots, one per ground, fenced "auto": each fence takes its ground's style.
    def plot(x0: int, y0: int, source: int) -> None:
        for cell in rect(x0, y0, x0 + 9, y0 + 12):
            grounds[cell] = source

    plot(0, 35, SNOW)
    hill(octagon(1, 37, 8, 43, 2), 1, style="auto")
    plot(10, 35, SAND)
    hill(diamond(15, 40, 4), 1, style="auto")
    plot(20, 35, FOREST_FLOOR)
    hill(rect(22, 37, 27, 42), 2, style="auto")
    plot(30, 35, FOREST_MOSS)
    hill(octagon(31, 37, 38, 44, 3), 1, style="auto")
    plot(0, 49, AMBERLEAF)
    hill(octagon(1, 51, 8, 58, 2), 1, style="auto")
    hill(rect(3, 53, 6, 55), 2, style="auto")
    plot(10, 49, CAVERN)
    hill(rect(11, 51, 18, 56), 1, style="auto")
    plot(20, 49, CRYSTAL)
    hill(diamond(25, 54, 4), 2, style="auto")
    plot(30, 49, COBBLE)
    cobble_hole = octagon(32, 52, 37, 57, 1)
    hill(cobble_hole, -1, set())
    for cell in ring(cobble_hole):
        fences[cell] = "auto"
    return levels, fences, grounds


def tile_data(cells: list[tuple[int, int, int, int, int, int]]) -> str:
    data = b"\x00\x00" + b"".join(struct.pack("<hhHHHH", *cell) for cell in cells)
    return ", ".join(str(b) for b in data)


def main() -> None:
    levels, fences, grounds = park()
    ground = [(x, y, grounds.get((x, y), GRASS), x % SHEET_CELLS, y % SHEET_CELLS, 0) for y in range(ROWS) for x in range(COLUMNS)]
    elevation = [(x, y, 0, *LEVEL_ATLAS[level], 0) for (x, y), level in sorted(levels.items(), key=lambda kv: (kv[0][1], kv[0][0]))]
    fence = [(x, y, 0, FENCE_ATLAS[style], 0, 0) for (x, y), style in sorted(fences.items(), key=lambda kv: (kv[0][1], kv[0][0]))]
    spawn = ((SPAWN_CELL[0] + 0.5) * TILE, (SPAWN_CELL[1] + 0.5) * TILE)
    text = f"""[gd_scene format=3]

[ext_resource type="TileSet" path="res://game/world/terrain_tileset.tres" id="1"]
[ext_resource type="Script" path="res://game/scripts/world_definition.gd" id="2"]
[ext_resource type="TileSet" path="res://game/world/elevation/elevation_tileset.tres" id="elevation_tiles"]
[ext_resource type="Script" path="res://game/world/elevation/elevation_layer.gd" id="elevation_layer"]
[ext_resource type="TileSet" path="res://game/world/elevation/fences/fence_tileset.tres" id="fence_tiles"]
[ext_resource type="Script" path="res://game/world/elevation/fences/fence_layer.gd" id="fence_layer"]

[node name="{MAP_ID}" type="Node2D"]
y_sort_enabled = true

[node name="ground" type="TileMapLayer" parent="."]
z_index = -2
tile_map_data = PackedByteArray({tile_data(ground)})
tile_set = ExtResource("1")
metadata/source_cell_count = {COLUMNS * ROWS}
metadata/columns = {COLUMNS}
metadata/rows = {ROWS}

[node name="elevation" type="TileMapLayer" parent="."]
z_index = -1
tile_map_data = PackedByteArray({tile_data(elevation)})
tile_set = ExtResource("elevation_tiles")
script = ExtResource("elevation_layer")

[node name="fences" type="TileMapLayer" parent="."]
z_index = -1
tile_map_data = PackedByteArray({tile_data(fence)})
tile_set = ExtResource("fence_tiles")
script = ExtResource("fence_layer")

[node name="world-definition" type="Node" parent="."]
script = ExtResource("2")
map_id = "{MAP_ID}"
tile_size = {TILE}
columns = {COLUMNS}
rows = {ROWS}
metadata = {{
"objects": [],
"player": {{
"spawn": {{
"x": {int(spawn[0])},
"y": {int(spawn[1])}
}},
"entries": {{}}
}}
}}

[node name="player-spawn" type="Node2D" parent="."]
y_sort_enabled = true
position = Vector2({int(spawn[0])}, {int(spawn[1])})
"""
    SCENE.write_text(text, encoding="utf-8", newline="\n")
    print(f"{MAP_ID}: {COLUMNS}x{ROWS} cells, {len(levels)} elevation cells, {len(fences)} fence cells")


if __name__ == "__main__":
    main()
