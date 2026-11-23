#!/usr/bin/env python3
"""Paints the crystal floor trim (docs/godot/INTERIOR_WALLS.md "Floor trim": crystal studs in crystal
blue, palette column 10, row 12) along the walls of a crystal-cave room, as a small text edit of its
scene: it adds a `floor-trim` InteriorTrimLayer after `interior-walls` (and the two resource lines it
needs) and nothing else, so the room's other edits stay as they are. A room that already has a
`floor-trim` layer is left alone.

Which cells: the room's floor (filled from the player spawn through every cell the walls do not
take), those beside a wall (the trim draws only there), but not the cells in front of an opening (a
doorway, cracked, blown or stairs block: an `interior-walls` tile of a row other than 0) nor under a
ladder against a wall (a `cave-ladder` instance): a painted cell draws its band across those.

Usage: python scripts/maps/paint-crystal-trim.py <room.tscn> [...] [--dry]
"""
from __future__ import annotations

import base64
import io
import random
import re
import struct
import sys
from pathlib import Path

TRIM_TILE = (10, 12)   # crystal studs, crystal blue
CELL = 64
LADDER_HALF = 56.0     # a ladder covers the floor cells whose middle lies this close to it (x)
TILESET = '[ext_resource type="TileSet" uid="uid://ebcxu0geywu" path="res://game/world/interior/interior_trim_tileset.tres" id="trim_tiles"]'
SCRIPT = '[ext_resource type="Script" uid="uid://x2vki4u55145" path="res://game/world/interior/interior_trim_layer.gd" id="trim_layer"]'


def cells_of(block: str) -> tuple[bytes, dict]:
	m = re.search(r'tile_map_data = PackedByteArray\("([^"]*)"\)', block)
	raw = base64.b64decode(m.group(1)) if m else b"\x00\x00"
	cells = {}
	for i in range(2, len(raw) - 11, 12):
		x, y, src, ax, ay, alt = struct.unpack("<hhHHHH", raw[i:i + 12])
		if src != 0xFFFF:
			cells[(x, y)] = (ax, ay)
	return raw[:2], cells


def paint(path: Path, dry: bool) -> None:
	text = io.open(path, encoding="utf-8").read()
	if 'interior_trim_layer.gd' in text:
		print(f"{path.name}: has a floor-trim layer already; left alone")
		return
	blocks = re.split(r"\n(?=\[)", text)
	walls_i = next(i for i, b in enumerate(blocks) if b.startswith('[node name="interior-walls"'))
	header, walls = cells_of(blocks[walls_i])
	spawn = re.search(r'\[node name="player-spawn"[^\]]*\]\n(?:[^\[\n][^\n]*\n)*?position = Vector2\(([-\d.]+), ([-\d.]+)\)', text)
	start = (int(float(spawn.group(1)) // CELL), int(float(spawn.group(2)) // CELL))
	xs = [c[0] for c in walls]
	ys = [c[1] for c in walls]
	box = (min(xs), min(ys), max(xs), max(ys))
	floor, stack = set(), [start]
	while stack:
		c = stack.pop()
		if c in floor or c in walls or not (box[0] <= c[0] <= box[2] and box[1] <= c[1] <= box[3]):
			continue
		floor.add(c)
		stack += [(c[0] + 1, c[1]), (c[0] - 1, c[1]), (c[0], c[1] + 1), (c[0], c[1] - 1)]
	openings = {c for c, tile in walls.items() if tile[1] != 0}
	ladders = []
	ladder_ids = re.findall(r'\[ext_resource [^\]]*cave-ladder\.tscn" id="([^"]+)"\]', text)
	for lid in ladder_ids:
		for m in re.finditer(r'instance=ExtResource\("%s"\)\]\nposition = Vector2\(([-\d.]+), ([-\d.]+)\)' % re.escape(lid), text):
			ladders.append((float(m.group(1)), float(m.group(2))))
	trim = []
	for c in sorted(floor, key=lambda c: (c[1], c[0])):
		near = [(c[0] + dx, c[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
		if not any(n in walls for n in near):
			continue
		if any((c[0] + dx, c[1] + dy) in openings for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
			continue
		middle = ((c[0] + 0.5) * CELL, (c[1] + 0.5) * CELL)
		if any(abs(middle[0] - lx) < LADDER_HALF and (c[0], c[1] - 1) in walls and abs(middle[1] - ly) < CELL * 1.5
				for lx, ly in ladders):
			continue
		trim.append(c)
	data = header + b"".join(struct.pack("<hhHHHH", x, y, 0, TRIM_TILE[0], TRIM_TILE[1], 0) for x, y in trim)
	node = ('[node name="floor-trim" type="TileMapLayer" parent="." unique_id=%d]\n'
		'self_modulate = Color(1, 1, 1, 0.2)\n'
		'tile_map_data = PackedByteArray("%s")\n'
		'tile_set = ExtResource("trim_tiles")\n'
		'script = ExtResource("trim_layer")\n') % (random.randint(10 ** 8, 2 ** 31 - 1), base64.b64encode(data).decode())
	blocks.insert(walls_i + 1, node)
	last_ext = max(i for i, b in enumerate(blocks) if b.startswith("[ext_resource"))
	blocks[last_ext] = blocks[last_ext].rstrip("\n") + "\n" + TILESET + "\n" + SCRIPT + "\n"
	out = "\n".join(blocks)
	print(f"{path.name}: {len(floor)} floor cells, {len(trim)} trimmed, openings {len(openings)}, ladders {len(ladders)}")
	if not dry:
		io.open(path, "w", encoding="utf-8", newline="").write(out)


def main() -> None:
	dry = "--dry" in sys.argv
	for arg in sys.argv[1:]:
		if not arg.startswith("--"):
			paint(Path(arg), dry)


if __name__ == "__main__":
	main()
