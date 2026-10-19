extends RefCounted
## Level faces inside dungeon rooms (docs/godot/ELEVATION.md "Faces in rooms"; INTERIOR_WALLS.md
## "Pits and holes"): in a world whose rooms are drawn by an InteriorWallLayer, a level change (a
## pit, a raised floor) is drawn with the room's own bevel pieces instead of the outdoor cliffs, and
## collides exactly where it is drawn.
##
## From the `elevation` paint, per 64-unit cell of a lower level next to a higher one (a stair cell
## is neither: its flight draws itself):
##   front  the higher cell is north: the north-wall run (`n0..n2`) squashed to one cell, its cap on
##          the upper floor's edge, darker toward its foot (one cell per level);
##   sides  the higher cell is west or east: the west/east-wall run squashed to SIDE units, mitred
##          into a front in the same cell, and carried down beside a front that turns a corner
##          (a convex corner of the upper floor);
##   back   the higher cell is south: only the cap of the south-wall run, LIP units, along the edge.
## The faces are Polygon2Ds textured from the style's sheet (game/world/interior/interior-walls.json).
##
## The collision stays the outdoor one (Elevation's level outlines, its ledge drops and deck
## passages): the faces are drawn on its footprint (a front one cell a level, a side SIDE units).
## `cells` gives the same footprint as level-collision cells (16 units, level_collision_layer.gd):
## a **base** of the lower level at each face's foot, a **rim** of the higher level on the upper
## floor's edge; "Fill from the automatic collision" copies them in a room.
##
## Owner: world (elevation).

const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")

const CELL := 64.0
## A side face's width (units): the outdoor side wall's strip (the collision's, Elevation `_with_sides`).
const SIDE := 24.0
## A back edge's cap (units).
const LIP := 7.0
## The face's foot is this much darker than its cap.
const FOOT_SHADE := 0.78
const SIDE_SHADE := 0.88
## Collision tiles a cell (16-unit tiles).
const PER := 4
const KINDS: PackedStringArray = ["rim", "base"]


## Builds the faces of the levels painted on `painted` (the `elevation` layer) inside the rooms of
## `walls` (an InteriorWallLayer): {"faces": Node2D in the painted layer's space (its children the
## face polygons), "cells": Vector2i 16-unit cell -> [kind, level]}. Empty when no room has a style.
static func build(painted: TileMapLayer, walls: Node, bounds: Rect2i) -> Dictionary:
	var levels := {}
	var stairs := {}
	for cell: Vector2i in painted.get_used_cells():
		var data := painted.get_cell_tile_data(cell)
		if data == null:
			continue
		if painted.get_cell_atlas_coords(cell).y > 0:
			stairs[cell] = true
		else:
			levels[cell] = int(data.get_custom_data(&"elevation_level"))
	var level_of := func(c: Vector2i) -> int:
		return int(levels.get(c, 0))
	var holder := Node2D.new()
	holder.name = "RoomFaces"
	var cells := {}
	var table := InteriorWalls.table()
	var textures := {}
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var c := Vector2i(x, y)
			if stairs.has(c):
				continue
			var own := int(level_of.call(c))
			var higher := func(d: Vector2i) -> int:
				var n := c + d
				if stairs.has(n) or not bounds.has_point(n):
					return -100
				var l := int(level_of.call(n))
				return l if l > own else -100
			var n_up := int(higher.call(Vector2i(0, -1)))
			var w_up := int(higher.call(Vector2i(-1, 0)))
			var e_up := int(higher.call(Vector2i(1, 0)))
			var s_up := int(higher.call(Vector2i(0, 1)))
			var nw_up := int(higher.call(Vector2i(-1, -1)))
			var ne_up := int(higher.call(Vector2i(1, -1)))
			if n_up < -99 and w_up < -99 and e_up < -99 and s_up < -99 and nw_up < -99 and ne_up < -99:
				continue
			var style := str(walls.call(&"room_style_at", c)) if walls != null else ""
			if style.is_empty():
				# a pit by the room's wall: the wall's own style
				for d: Vector2i in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
					style = str(walls.call(&"room_style_at", c + d)) if walls != null else ""
					if not style.is_empty():
						break
			var entry: Dictionary = table.get(style, {})
			if entry.is_empty():
				continue
			if not textures.has(style):
				textures[style] = InteriorWalls.picture(str(entry["texture"]))
			var texture: Texture2D = textures[style]
			var pieces: Dictionary = entry["pieces"]
			var period: Dictionary = entry.get("run_period", {"n": 3, "s": 3, "w": 3, "e": 3})
			var origin := Vector2(c) * CELL
			var n_piece := "n%d" % posmod(x, int(period.get("n", 3)))
			if n_up > -100:
				_quad(holder, texture, pieces[n_piece], Rect2(origin, Vector2(CELL, CELL)), FOOT_SHADE)
				_mark(cells, c, Rect2i(0, PER - 1, PER, 1), "base", own)
				_mark(cells, c + Vector2i(0, -1), Rect2i(0, PER - 1, PER, 1), "rim", n_up)
			for side in [["w", w_up, -1, nw_up], ["e", e_up, 1, ne_up]]:
				var name: String = side[0]
				var up: int = side[1]
				var dx: int = side[2]
				var corner: int = side[3]
				var piece: Array = pieces["%s%d" % [name, posmod(y, int(period.get(name, 3)))]]
				var strip := Rect2(origin + Vector2(0.0 if dx < 0 else CELL - SIDE, 0.0), Vector2(SIDE, CELL))
				var inner := Rect2i(1 if dx < 0 else PER - 2, 0, 1, PER)
				if up > -100:
					if n_up > -100:
						# mitre: the side face below the diagonal from the rim's corner
						_tri(holder, texture, piece, strip, "ll" if dx < 0 else "lr", SIDE_SHADE)
					else:
						_quad(holder, texture, piece, strip, SIDE_SHADE)
					_mark(cells, c, inner, "base", own)
					_mark(cells, c + Vector2i(dx, 0), Rect2i(PER - 1 if dx < 0 else 0, 0, 1, PER), "rim", up)
				elif n_up < -99 and corner > -100 and level_of.call(c + Vector2i(dx, 0)) == own and not stairs.has(c + Vector2i(dx, 0)):
					# a convex corner of the upper floor: its side face comes down beside the front
					# turning round it
					var beside: Array = pieces["n%d" % posmod(x + dx, int(period.get("n", 3)))]
					var part := _part(beside, dx < 0)
					_tri(holder, texture, part, strip, "ll" if dx < 0 else "lr", FOOT_SHADE)
					_tri(holder, texture, piece, strip, "ur" if dx < 0 else "ul", SIDE_SHADE)
					_mark(cells, c, inner, "base", own)
					_mark(cells, c, Rect2i(0 if dx < 0 else PER - 2, PER - 1, 2, 1), "base", own)
			if s_up > -100:
				var s_piece: Array = pieces["s%d" % posmod(x, int(period.get("s", 3)))]
				var cap := [s_piece[0], s_piece[1] + s_piece[3] - 40, s_piece[2], 40]
				_quad(holder, texture, cap, Rect2(origin + Vector2(0.0, CELL - LIP), Vector2(CELL, LIP)), 1.0)
				_mark(cells, c, Rect2i(0, PER - 1, PER, 1), "base", own)
				_mark(cells, c + Vector2i(0, 1), Rect2i(0, 0, PER, 1), "rim", s_up)
	return {"faces": holder, "cells": cells}


## The part of a north run piece (sheet rect) a convex corner's strip shows: its far end beside the
## corner (the east end for a strip on a cell's west side).
static func _part(piece: Array, west: bool) -> Array:
	var w := float(piece[2]) * SIDE / CELL
	return [float(piece[0]) + (float(piece[2]) - w if west else 0.0), piece[1], w, piece[3]]


## Marks `r` (16-unit tiles inside cell `cell`) with `kind` for `level`; a rim wins over a base.
static func _mark(cells: Dictionary, cell: Vector2i, r: Rect2i, kind: String, level: int) -> void:
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			var at := cell * PER + Vector2i(i, j)
			var was: Array = cells.get(at, [])
			if not was.is_empty() and str(was[0]) == "rim" and kind == "base":
				continue
			cells[at] = [kind, level]


static func _quad(holder: Node2D, texture: Texture2D, piece: Array, rect: Rect2, foot: float) -> void:
	var p := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var u := [Vector2(piece[0], piece[1]), Vector2(float(piece[0]) + float(piece[2]), piece[1]),
		Vector2(float(piece[0]) + float(piece[2]), float(piece[1]) + float(piece[3])), Vector2(piece[0], float(piece[1]) + float(piece[3]))]
	_polygon(holder, texture, p, u, [1.0, 1.0, foot, foot])


## A triangle of `rect` textured from `piece`: "ll" lower-left (the corner at the rect's top-left,
## bottom-left and bottom-right), "lr", "ur", "ul" likewise.
static func _tri(holder: Node2D, texture: Texture2D, piece: Array, rect: Rect2, keep: String, foot: float) -> void:
	var corners := {"tl": [rect.position, Vector2(piece[0], piece[1]), 1.0],
		"tr": [Vector2(rect.end.x, rect.position.y), Vector2(float(piece[0]) + float(piece[2]), piece[1]), 1.0],
		"br": [rect.end, Vector2(float(piece[0]) + float(piece[2]), float(piece[1]) + float(piece[3])), foot],
		"bl": [Vector2(rect.position.x, rect.end.y), Vector2(piece[0], float(piece[1]) + float(piece[3])), foot]}
	var order: Array = {"ll": ["tl", "bl", "br"], "lr": ["tr", "br", "bl"], "ur": ["tl", "tr", "br"], "ul": ["tl", "tr", "bl"]}[keep]
	var p := []
	var u := []
	var s := []
	for k: String in order:
		p.append(corners[k][0])
		u.append(corners[k][1])
		s.append(corners[k][2])
	_polygon(holder, texture, p, u, s)


static func _polygon(holder: Node2D, texture: Texture2D, points: Array, uvs: Array, shades: Array) -> void:
	var polygon := Polygon2D.new()
	polygon.texture = texture
	polygon.polygon = PackedVector2Array(points)
	polygon.uv = PackedVector2Array(uvs)
	var colours := PackedColorArray()
	for s: float in shades:
		colours.append(Color(s, s * 0.97, s * 0.94))
	polygon.vertex_colors = colours
	holder.add_child(polygon)
