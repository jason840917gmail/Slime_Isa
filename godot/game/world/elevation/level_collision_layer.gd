@tool
extends TileMapLayer
class_name LevelCollisionLayer
## Hand-painted level collision (docs/godot/ELEVATION.md "Painting collision"): a TileMapLayer beside a
## world's `elevation` layer (any name: it is found by its class), painted with
## level_collision_tileset.tres (tools/pack_level_collision_tileset.gd) on a 16-unit grid. It only
## ever stands in for the collision of the levels (the cliffs, holes and raised floors); walls, trees,
## fences, props and doors collide as before. Each tile is one kind for one level:
##
## - **rim** (orange, striped): the upper floor's edge. A body on that level is held there and,
##   pushing on for `elevation.dropPushMs`, drops over it to the level painted beyond (the ledge
##   drop), landing past the wall foot (`base`) painted for that lower level when there is one;
## - **base** (red): solid for bodies on that level: the wall foot they bump into;
## - **edge** (orange with a red border): a rim for its level and a base for every level below it,
##   in one tile: a raised floor's north border, where the upper floor ends and the lower floor's
##   wall foot is the same line (no face between them), so a body below cannot walk in under it;
## - **open** (green): nothing of that level collides in the tile (an override takes the automatic
##   collision away there; where only the paint collides it is the same as no paint).
##
## Rims, bases and edges come whole or as 45° halves (`SHAPE_DATA`: "ne", "nw", "se" or "sw", the
## corner the solid half fills), so a diagonal rim is a straight line, not a stair of tiles; the other
## half of the tile is open.
##
## `mode` says what the paint does to the world's automatic level collision (Elevation
## `_build_collision`; in a dungeon room whose level changes are drawn as faces, the faces' square
## footprint, room_faces.gd):
## - **Replace** (the default): once any tile is painted, what is painted is exactly what collides.
##   Which level a body stands on, the stairs, the hazards' and kit objects' levels still come from
##   the `elevation` paint; a flight of stairs collides along its sides as it does automatically;
## - **Override**: the automatic collision stays, and each painted tile decides its own square for
##   its level: an open tile takes the automatic collision away (closed again along the tile's sides
##   where the automatic ground beyond is blocked), a rim, base or edge collides there instead. Paint
##   only where the automatic collision does not fit the art; a repainted hill keeps its collision.
## Empty, the automatic collision works as before. A deck's passage (a slab, a landing, a lowered
## drawbridge: Elevation `open_passage`) changes the paint round it as Elevation
## `_update_passage_paint` says (`segments_by_level`'s `changes`): it opens the tiles where floor of
## its level goes on past its edge and closes its other sides, so a bridge holds a body by its sides.
##
## In the editor the tiles show at `paint_opacity`, and `show_collision` draws the active collision
## over the art (the painted one's tiles; with an override the resulting outline too; in a room
## without paint the faces' footprint; else the automatic outline of every level), `show_automatic`
## the automatic outline under the paint to compare. "Fill from the automatic collision" replaces the
## paint inside `fill_area` (everywhere when empty) with the automatic collision turned into tiles,
## 45° halves where it runs diagonally (save the scene first: it is not undoable). When the `elevation`
## paint changes after the collision was painted (`painted_for`) the node shows a warning. The game
## hides the layer. The opacity is never saved in the scene (`_validate_property`).
##
## Owner: world (elevation).

const NodeFind := preload("res://game/shared/node_find.gd")

const NODE_NAME := "level-collision"
const KIND_DATA := &"collision_kind"
const LEVEL_DATA := &"collision_level"
const SHAPE_DATA := &"collision_shape"
const RIM := "rim"
const BASE := "base"
const EDGE := "edge"
const OPEN := "open"
## The whole tiles' kinds, in the palette's first columns.
const KINDS: PackedStringArray = [RIM, BASE, EDGE, OPEN]
## The kinds that also come as 45° halves (the palette's next columns, `SHAPES.size()` each).
const SLOPED_KINDS: PackedStringArray = [RIM, BASE, EDGE]
## A half tile's solid corner.
const SHAPES: PackedStringArray = ["ne", "nw", "se", "sw"]
const KIND_COLOURS := {RIM: Color("#ff9a1f"), BASE: Color("#e3343c"), EDGE: Color("#ff9a1f"), OPEN: Color("#3ccf7a")}
const MIN_LEVEL := -3
const MAX_LEVEL := 3
## The outline colours of the collision per level (the overlay; render_room_collision.gd's).
const LEVEL_COLOURS := {-3: Color(1, 0.3, 1), -2: Color(0.8, 0.3, 1), -1: Color(0.3, 0.6, 1), 0: Color(1, 0.2, 0.2),
	1: Color(1, 0.9, 0.2), 2: Color(0.2, 1, 1), 3: Color(0.6, 1, 0.4)}
const OVERLAY := "CollisionOverlay"
## A tile's sides (N, E, S, W) as steps to the neighbour across them.
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## The sides (SIDES indices) a solid tile of each shape covers whole ("" a whole tile).
const FULL_SIDES := {"": [0, 1, 2, 3], "ne": [0, 1], "nw": [0, 3], "se": [1, 2], "sw": [2, 3]}
## The pieces a tile's side is cut into to close an override's open tile against blocked ground.
const SEAM_PIECES := 4
const ELEVATION_SCRIPT := "res://game/world/elevation/elevation.gd"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const ELEVATION_DATA := "elevation_level"

enum Mode { REPLACE, OVERRIDE }

## Replace: only the paint collides. Override: the automatic collision, with each painted tile
## deciding its own square for its level.
@export var mode: Mode = Mode.REPLACE:
	set(value):
		mode = value
		_queue_overlay()
## How strongly the painted tiles show in the editor (0 hides them; the overlay stays).
@export_range(0.0, 1.0, 0.05) var paint_opacity: float = 0.55:
	set(value):
		paint_opacity = value
		self_modulate.a = value
## Draws the active collision over the art in the editor.
@export var show_collision: bool = true:
	set(value):
		show_collision = value
		_queue_overlay()
## Draws the automatic outline of every level faintly under the paint (where they differ).
@export var show_automatic: bool = false:
	set(value):
		show_automatic = value
		_queue_overlay()
## The map cells (64 units, as the `elevation` layer's) "Fill" works in; empty: the whole world.
@export var fill_area: Rect2i:
	set(value):
		fill_area = value
		_queue_overlay()
@export_tool_button("Fill from the automatic collision", "TileMap") var fill_button: Callable = fill_from_automatic
## The `elevation` paint the collision was last painted over (`_paint_hash`): when they differ the
## node warns that the collision may no longer fit.
@export_storage var painted_for: String = ""

var _overlay_queued := false
## The painted tiles as they were at the last overlay (`_cells_hash`): a change of them (not of the
## opacity) records `painted_for`.
var _own_hash := ""


func _ready() -> void:
	self_modulate.a = paint_opacity
	if not Engine.is_editor_hint():
		visible = false
		return
	_own_hash = _cells_hash()
	if painted_for.is_empty() and is_painted():
		painted_for = _paint_hash()
	changed.connect(_queue_overlay)
	var painted := _elevation_layer()
	if painted != null and not painted.changed.is_connected(_queue_overlay):
		painted.changed.connect(_queue_overlay)
	_queue_overlay()


## `self_modulate` follows `paint_opacity` (set in `_ready`): not stored, so opening a world in the
## editor never writes it into the scene.
func _validate_property(property: Dictionary) -> void:
	if property["name"] == "self_modulate":
		property["usage"] = int(property["usage"]) & ~PROPERTY_USAGE_STORAGE


func _get_configuration_warnings() -> PackedStringArray:
	if is_painted() and not painted_for.is_empty() and painted_for != _paint_hash():
		return ["The elevation was repainted after this collision was painted: check the overlay, then repaint (or Fill) where it no longer fits."]
	return []


## The layer beside `ground_layer` (a LevelCollisionLayer child of its parent, any name), or null.
static func find_beside(ground_layer: Node) -> LevelCollisionLayer:
	if ground_layer == null or ground_layer.get_parent() == null:
		return null
	var parent := ground_layer.get_parent()
	var named := parent.get_node_or_null(NodePath(NODE_NAME))
	if named != null and not (named is LevelCollisionLayer):
		push_warning("%s: %s is not a LevelCollisionLayer, so its paint is ignored" % [parent.name, NODE_NAME])
	return NodeFind.child_of(parent, LevelCollisionLayer) as LevelCollisionLayer


## The palette tile of `kind` for `level`, whole (`shape` "") or a 45° half (SHAPES).
static func tile_of(kind: String, level: int, shape: String = "") -> Vector2i:
	var column := KINDS.find(kind)
	if not shape.is_empty():
		column = KINDS.size() + SLOPED_KINDS.find(kind) * SHAPES.size() + SHAPES.find(shape)
	return Vector2i(column, level - MIN_LEVEL)


## True when something is painted (the layer then replaces or overrides the automatic collision).
func is_painted() -> bool:
	return not get_used_cells().is_empty()


## True when a body meets a wall where the paint has `role` for its level (a rim or a base).
static func blocks(role: String) -> bool:
	return role == RIM or role == BASE


## What the painted tile at `point` (world) is for bodies of `level`: "rim", "base", "open" (an open
## tile, or the open half of a 45° one) or "" (nothing painted for that level).
func kind_at(point: Vector2, level: int) -> String:
	var local := to_local(point)
	var at := local_to_map(local)
	var data := get_cell_tile_data(at)
	var role := role_of(data, level)
	if not blocks(role):
		return role
	var shape := shape_of(data)
	if shape.is_empty() or in_shape(shape, (local - _corner(at)) / _tile()):
		return role
	return OPEN


## What a painted tile (`data`, null for none) is for bodies of `level`, whatever its shape: "rim",
## "base", "open" or "". An edge is a rim for its own level and a base for every level below.
static func role_of(data: TileData, level: int) -> String:
	if data == null:
		return ""
	var own := int(data.get_custom_data(LEVEL_DATA))
	var kind := str(data.get_custom_data(KIND_DATA))
	if kind == EDGE:
		return RIM if own == level else (BASE if level < own else "")
	return kind if own == level else ""


## A painted tile's shape: "" whole, else the corner its solid half fills.
static func shape_of(data: TileData) -> String:
	return str(data.get_custom_data(SHAPE_DATA)) if data != null else ""


## True when `frac` (0..1 across a tile, y down) lies in the solid half `shape`.
static func in_shape(shape: String, frac: Vector2) -> bool:
	match shape:
		"ne":
			return frac.x >= frac.y
		"nw":
			return frac.x + frac.y <= 1.0
		"se":
			return frac.x + frac.y >= 1.0
		"sw":
			return frac.x <= frac.y
	return true


## The tiles painted for `level`: Vector2i -> "" (solid whole), a SHAPES corner (a solid half) or
## "open"; with `changes` (the decks' passages, Elevation `_update_passage_paint`: level -> {tile: ""
## left out, "rim" or "base" added whole}).
func tiles_for(level: int, changes: Dictionary = {}) -> Dictionary:
	var out := {}
	var changed: Dictionary = changes.get(level, {})
	for cell: Vector2i in get_used_cells():
		var data := get_cell_tile_data(cell)
		var role := role_of(data, level)
		if role.is_empty() or (changed.has(cell) and str(changed[cell]).is_empty()):
			continue
		out[cell] = shape_of(data) if blocks(role) else OPEN
	for cell: Vector2i in changed:
		if not str(changed[cell]).is_empty():
			out[cell] = ""
	return out


## The painted collision's solid shapes for `level` (world space): {"rects": Array[Rect2] (the whole
## tiles, merged), "triangles": Array[PackedVector2Array] (the 45° halves)}; `changes` as
## `tiles_for`. Solid, so a body put across a painted wall (a teleport, a level change) is pushed
## back out of it, as the old painted boxes did.
func solid_shapes(level: int, changes: Dictionary = {}) -> Dictionary:
	var tiles := tiles_for(level, changes)
	var whole := {}
	var triangles: Array[PackedVector2Array] = []
	for cell: Vector2i in tiles:
		var shape := str(tiles[cell])
		if shape.is_empty():
			whole[cell] = true
		elif shape != OPEN:
			triangles.append(_half_points(cell, shape))
	var rects: Array[Rect2] = []
	var size := _tile() * global_scale.abs()
	for r: Rect2i in merged(whole):
		rects.append(Rect2(_corner_point(r.position), Vector2(r.size) * size))
	return {"rects": rects, "triangles": triangles}


## The painted collision's outline per level (world space): level -> segments, every side of a solid
## tile that no solid neighbour covers and every 45° half's diagonal, joined along their lines (no
## seams between tiles for a sliding body to catch on). An edge collides for its level and every
## level below; `changes` as `tiles_for`.
func segments_by_level(changes: Dictionary = {}) -> Dictionary:
	var out := {}
	for level in range(MIN_LEVEL, MAX_LEVEL + 1):
		var solid := {}
		var tiles := tiles_for(level, changes)
		for cell: Vector2i in tiles:
			if str(tiles[cell]) != OPEN:
				solid[cell] = tiles[cell]
		var segments := outline(solid)
		if not segments.is_empty():
			out[level] = segments
	return out


## The outline (world space) of `solid` (tile -> "" or a SHAPES corner): as `segments_by_level`.
func outline(solid: Dictionary) -> PackedVector2Array:
	# Tile-corner coordinates per line: horizontal (row y), vertical (column x), a "ne"/"sw" diagonal
	# (x - y) and a "nw"/"se" one (x + y + 1); each holds the tile columns (rows) of its pieces.
	var lines := {}
	for cell: Vector2i in solid:
		var shape := str(solid[cell])
		for side in SIDES.size():
			if not _full_side(shape, side):
				continue
			var next := cell + SIDES[side]
			if solid.has(next) and _full_side(str(solid[next]), (side + 2) % 4):
				continue
			match side:
				0:
					_add_on_line(lines, Vector2i(0, cell.y), cell.x)
				1:
					_add_on_line(lines, Vector2i(1, cell.x + 1), cell.y)
				2:
					_add_on_line(lines, Vector2i(0, cell.y + 1), cell.x)
				3:
					_add_on_line(lines, Vector2i(1, cell.x), cell.y)
		if shape == "ne" or shape == "sw":
			_add_on_line(lines, Vector2i(2, cell.x - cell.y), cell.x)
		elif shape == "nw" or shape == "se":
			_add_on_line(lines, Vector2i(3, cell.x + cell.y + 1), cell.x)
	var segments := PackedVector2Array()
	for key: Vector2i in lines:
		var steps: Array = (lines[key] as Dictionary).keys()
		steps.sort()
		var first: int = steps[0]
		for i in range(1, steps.size() + 1):
			if i < steps.size() and int(steps[i]) == int(steps[i - 1]) + 1:
				continue
			var last: int = steps[i - 1]
			match key.x:
				0:
					segments.append(_corner_point(Vector2i(first, key.y)))
					segments.append(_corner_point(Vector2i(last + 1, key.y)))
				1:
					segments.append(_corner_point(Vector2i(key.y, first)))
					segments.append(_corner_point(Vector2i(key.y, last + 1)))
				2:
					segments.append(_corner_point(Vector2i(first, first - key.y)))
					segments.append(_corner_point(Vector2i(last + 1, last + 1 - key.y)))
				3:
					segments.append(_corner_point(Vector2i(last + 1, key.y - 1 - last)))
					segments.append(_corner_point(Vector2i(first, key.y - first)))
			if i < steps.size():
				first = steps[i]
	return segments


## The sides of every tile painted for `level` (`tiles_for`) that are not solid and face a tile with
## nothing painted for it, each as SEAM_PIECES pieces (world space): [from, to, the point just past
## its middle]. An override closes the ones whose point past lies on blocked automatic ground.
func open_sides(level: int, changes: Dictionary = {}) -> Array:
	var tiles := tiles_for(level, changes)
	var tile := _tile()
	var out: Array = []
	for cell: Vector2i in tiles:
		var shape := str(tiles[cell])
		if shape.is_empty():
			continue
		for side in SIDES.size():
			if shape != OPEN and _full_side(shape, side):
				continue
			if tiles.has(cell + SIDES[side]):
				continue
			var corners: Array[Vector2i] = [cell, cell + Vector2i(1, 0), cell + Vector2i.ONE, cell + Vector2i(0, 1)]
			var a := _corner_point(corners[side])
			var b := _corner_point(corners[(side + 1) % 4])
			var out_step := (to_global(Vector2(SIDES[side]) * tile) - to_global(Vector2.ZERO)).normalized() * 2.0
			for k in SEAM_PIECES:
				var from := a.lerp(b, float(k) / SEAM_PIECES)
				var to := a.lerp(b, float(k + 1) / SEAM_PIECES)
				out.append([from, to, (from + to) * 0.5 + out_step])
	return out


## The tiles painted for `level` (`tiles_for`) as merged world rectangles: where an override decides
## the collision itself.
func claimed_rects(level: int, changes: Dictionary = {}) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var size := _tile() * global_scale.abs()
	for r: Rect2i in merged(tiles_for(level, changes)):
		rects.append(Rect2(_corner_point(r.position), Vector2(r.size) * size))
	return rects


## The whole painted tiles as merged rectangles (world space) per kind and level, as painted (an edge
## once, at its own level): [{"kind", "level", "rects": Array[Rect2]}]; the 45° halves apart:
## [{"kind", "level", "points": PackedVector2Array}] (`halves`). The editor's overlay.
func rects_by_kind() -> Array[Dictionary]:
	var groups := {}
	for cell: Vector2i in get_used_cells():
		var data := get_cell_tile_data(cell)
		if data != null and shape_of(data).is_empty():
			var key := [str(data.get_custom_data(KIND_DATA)), int(data.get_custom_data(LEVEL_DATA))]
			(groups.get_or_add(key, {}) as Dictionary)[cell] = true
	var size := _tile() * global_scale.abs()
	var out: Array[Dictionary] = []
	for key: Array in groups:
		var rects: Array[Rect2] = []
		for r: Rect2i in merged(groups[key]):
			rects.append(Rect2(_corner_point(r.position), Vector2(r.size) * size))
		out.append({"kind": key[0], "level": key[1], "rects": rects})
	return out


## The 45° halves painted (world space): [{"kind", "level", "points"}], the solid half's triangle.
func halves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cell: Vector2i in get_used_cells():
		var data := get_cell_tile_data(cell)
		var shape := shape_of(data)
		if shape.is_empty():
			continue
		out.append({"kind": str(data.get_custom_data(KIND_DATA)), "level": int(data.get_custom_data(LEVEL_DATA)),
			"points": _half_points(cell, shape)})
	return out


## The solid half `shape` of the tile `cell` as a triangle (world space).
func _half_points(cell: Vector2i, shape: String) -> PackedVector2Array:
	var nw := _corner_point(cell)
	var ne := _corner_point(cell + Vector2i(1, 0))
	var se := _corner_point(cell + Vector2i.ONE)
	var sw := _corner_point(cell + Vector2i(0, 1))
	match shape:
		"ne":
			return PackedVector2Array([nw, ne, se])
		"nw":
			return PackedVector2Array([nw, ne, sw])
		"se":
			return PackedVector2Array([ne, se, sw])
	return PackedVector2Array([nw, se, sw])


## The tiles (a set of Vector2i) as few rectangles: runs along each row, stacked where the rows below
## have the same run.
static func merged(cells: Dictionary) -> Array[Rect2i]:
	var runs := {}
	for cell: Vector2i in cells:
		if cells.has(cell - Vector2i(1, 0)):
			continue
		var length := 1
		while cells.has(cell + Vector2i(length, 0)):
			length += 1
		runs[cell] = length
	var out: Array[Rect2i] = []
	var used := {}
	var starts := runs.keys()
	starts.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for start: Vector2i in starts:
		if used.has(start):
			continue
		var length := int(runs[start])
		var height := 1
		while runs.get(start + Vector2i(0, height), -1) == length and not used.has(start + Vector2i(0, height)):
			used[start + Vector2i(0, height)] = true
			height += 1
		out.append(Rect2i(start, Vector2i(length, height)))
	return out


## Puts `paint` (an override layer) over this one, tile by tile (world positions): its open tiles take
## away this layer's tile there when it collides for their level, its other tiles take its place. A
## room's faces' footprint under an override (Elevation `_choose_collision_paint`).
func apply(paint: LevelCollisionLayer) -> void:
	for cell: Vector2i in paint.get_used_cells():
		var at := local_to_map(to_local(paint.to_global(paint.map_to_local(cell))))
		var data := paint.get_cell_tile_data(cell)
		if data == null:
			continue
		if str(data.get_custom_data(KIND_DATA)) == OPEN:
			if not role_of(get_cell_tile_data(at), int(data.get_custom_data(LEVEL_DATA))).is_empty():
				erase_cell(at)
		else:
			set_cell(at, paint.get_cell_source_id(cell), paint.get_cell_atlas_coords(cell))


## Replaces the paint inside `fill_area` (everywhere when empty) with the world's automatic collision
## turned into tiles: every tile next to ground a level can walk on that it cannot is painted for that
## level, a rim where the ground past it is lower (a drop), else a base, an edge where a rim is also a
## lower level's wall foot; a 45° half where the automatic collision crosses the tile diagonally (its
## two sides on one corner blocked, the other two walkable). Interior walls collide by themselves:
## tiles on them, and ground on them, are left out. A tile bordering two levels keeps the higher
## level's. In a room drawn with faces it copies the faces' footprint (the room's collision). Returns
## the tiles painted.
func fill_from_automatic() -> int:
	var elevation := _elevation()
	if elevation == null or elevation.get(&"grid") == null:
		push_warning("level-collision: no elevation drawing to read (paint the elevation layer first)")
		return 0
	var ground := elevation.get(&"ground") as TileMapLayer
	var big := float(ground.tile_set.tile_size.x)
	var area := Rect2(ground.to_global(Vector2(fill_area.position) * big), Vector2(fill_area.size) * big)
	var inside := func(point: Vector2) -> bool: return not fill_area.has_area() or area.has_point(point)
	for cell: Vector2i in get_used_cells():
		if inside.call(to_global(map_to_local(cell))):
			erase_cell(cell)
	# a room's faces give their collision exactly: copy it
	var room: Variant = elevation.get(&"room_collision")
	if is_instance_valid(room) and room is TileMapLayer:
		var source := room as TileMapLayer
		var copied := 0
		for cell: Vector2i in source.get_used_cells():
			var centre := source.to_global(source.map_to_local(cell))
			if inside.call(centre):
				set_cell(local_to_map(to_local(centre)), 0, source.get_cell_atlas_coords(cell))
				copied += 1
		print("level-collision: painted %d tiles from the room faces' collision" % copied)
		return copied
	var used := ground.get_used_rect()
	if fill_area.has_area():
		used = used.intersection(fill_area)
	var step := _tile().x
	var per := int(round(big / step))
	var walls := _interior_walls()
	var on_wall := func(point: Vector2) -> bool:
		return walls != null and bool(walls.call(&"is_wall", walls.local_to_map(walls.to_local(point))))
	var free := func(point: Vector2, level: int) -> bool:
		return bool(elevation.call(&"automatic_walkable", point, level))
	var near: Array[Vector2] = [Vector2(step, 0), Vector2(-step, 0), Vector2(0, step), Vector2(0, -step),
		Vector2(step, step), Vector2(-step, step), Vector2(step, -step), Vector2(-step, -step)]
	# A side's middle, just inside the tile: N, E, S, W.
	var sides: Array[Vector2] = [Vector2(0, -0.4), Vector2(0.4, 0), Vector2(0, 0.4), Vector2(-0.4, 0)]
	var painted := 0
	for y in range(used.position.y * per, used.end.y * per):
		for x in range(used.position.x * per, used.end.x * per):
			var centre := ground.to_global(Vector2(x + 0.5, y + 0.5) * step)
			if on_wall.call(centre):
				continue
			for level in range(MAX_LEVEL, MIN_LEVEL - 1, -1):
				var blocked: Array[bool] = []
				for s: Vector2 in sides:
					blocked.append(not free.call(centre + s * step, level))
				var shape := _half_of(blocked)
				if free.call(centre, level) and shape.is_empty():
					continue
				var borders := not shape.is_empty()
				for d in near:
					if borders:
						break
					# ground on an interior wall does not count: the wall collides by itself
					borders = not on_wall.call(centre + d) and free.call(centre + d, level)
				if not borders:
					continue
				var lower := int(elevation.call(&"_lower_level_at", centre, level))
				var kind := RIM if lower >= MIN_LEVEL else BASE
				# a rim that is also a lower level's wall foot (a back border with no face): an edge
				if kind == RIM and _foot_below(free, on_wall, centre, near, level):
					kind = EDGE
				set_cell(local_to_map(to_local(centre)), 0, tile_of(kind, level, shape))
				painted += 1
				break
	_queue_overlay()
	print("level-collision: painted %d tiles from the automatic collision" % painted)
	return painted


## The 45° half (SHAPES) a tile is when exactly two sides meeting at one corner are `blocked` (N, E,
## S, W), else "".
static func _half_of(blocked: Array[bool]) -> String:
	var count := 0
	for b in blocked:
		count += int(b)
	if count != 2:
		return ""
	if blocked[0] and blocked[1]:
		return "ne"
	if blocked[0] and blocked[3]:
		return "nw"
	if blocked[2] and blocked[1]:
		return "se"
	if blocked[2] and blocked[3]:
		return "sw"
	return ""


## True when `centre` (a tile Fill paints a rim of `level` on) also borders ground of a lower level
## that cannot stand there: the same line is that level's wall foot.
static func _foot_below(free: Callable, on_wall: Callable, centre: Vector2, near: Array[Vector2], level: int) -> bool:
	for lower in range(level - 1, MIN_LEVEL - 1, -1):
		if bool(free.call(centre, lower)):
			continue
		for d in near:
			if not bool(on_wall.call(centre + d)) and bool(free.call(centre + d, lower)):
				return true
	return false


static func _full_side(shape: String, side: int) -> bool:
	return (FULL_SIDES.get(shape, []) as Array).has(side)


static func _add_on_line(lines: Dictionary, key: Vector2i, step: int) -> void:
	(lines.get_or_add(key, {}) as Dictionary)[step] = true


## A tile corner (tile coordinates: the top-left corner of the tile `corner`) in world space.
func _corner_point(corner: Vector2i) -> Vector2:
	return to_global(_corner(Vector2i.ZERO) + Vector2(corner) * _tile())


## The top-left corner of the tile `at` (local space).
func _corner(at: Vector2i) -> Vector2:
	return map_to_local(at) - _tile() * 0.5


func _tile() -> Vector2:
	return Vector2(tile_set.tile_size) if tile_set != null else Vector2(16, 16)


## The painted tiles, as a string that changes when they do.
func _cells_hash() -> String:
	var cells := get_used_cells()
	cells.sort()
	var parts: Array = []
	for cell in cells:
		parts.append([cell, get_cell_atlas_coords(cell)])
	return str(hash(parts))


## The `elevation` paint beside this layer, as a string that changes when it does.
func _paint_hash() -> String:
	var painted := _elevation_layer()
	if painted == null:
		return ""
	var cells := painted.get_used_cells()
	cells.sort()
	var parts: Array = []
	for cell in cells:
		parts.append([cell, painted.get_cell_atlas_coords(cell)])
	return str(hash(parts))


# --- the editor's overlay ------------------------------------------------------------------------

func _queue_overlay() -> void:
	if not Engine.is_editor_hint() or _overlay_queued or not is_inside_tree():
		return
	_overlay_queued = true
	# after the elevation's own (deferred) rebuild
	(func() -> void: _draw_overlay.call_deferred()).call_deferred()


func _draw_overlay() -> void:
	_overlay_queued = false
	# the tiles changed (not only the opacity): this is the elevation they were painted over
	var own := _cells_hash()
	if own != _own_hash:
		_own_hash = own
		painted_for = _paint_hash() if is_painted() else ""
	update_configuration_warnings()
	var overlay := get_node_or_null(OVERLAY) as Node2D
	if overlay == null:
		overlay = Node2D.new()
		overlay.name = OVERLAY
		overlay.z_index = 50
		overlay.z_as_relative = false
		overlay.top_level = true
		add_child(overlay)
		overlay.draw.connect(_paint_overlay.bind(overlay))
	overlay.visible = show_collision
	overlay.queue_redraw()


## Draws the active collision (world space) on `canvas`: the painted tiles in their kind's colour
## with their level's number; with an override outdoors the resulting outline of every level in its
## colour too; in a room the faces' footprint under an override (or alone without paint); else the
## automatic outline of every level. `show_automatic` adds the automatic outline faintly; `fill_area`
## shows as a white frame.
func _paint_overlay(canvas: Node2D) -> void:
	var elevation := _elevation()
	var built := elevation != null and elevation.get(&"grid") != null
	var room: LevelCollisionLayer = null
	if built:
		var found: Variant = elevation.get(&"room_collision")
		if is_instance_valid(found) and found is LevelCollisionLayer:
			room = found
	var painted := is_painted()
	if built and show_automatic:
		_draw_segments(canvas, elevation.call(&"collision_preview", null), 0.35, 1.0)
	if painted and mode == Mode.REPLACE:
		_draw_tiles(canvas, self, 2.0)
	elif room != null:
		_draw_tiles(canvas, room, 2.0 if not painted else 1.0)
		if painted:
			_draw_tiles(canvas, self, 2.0)
	elif painted:
		if built:
			_draw_segments(canvas, elevation.call(&"collision_preview", self), 1.0, 2.0)
		_draw_tiles(canvas, self, 1.0)
	elif built and not show_automatic:
		_draw_segments(canvas, elevation.call(&"collision_preview", null), 1.0, 2.0)
	if fill_area.has_area() and built:
		var ground := elevation.get(&"ground") as TileMapLayer
		var big := float(ground.tile_set.tile_size.x)
		canvas.draw_rect(Rect2(ground.to_global(Vector2(fill_area.position) * big), Vector2(fill_area.size) * big), Color.WHITE, false, 2.0)


## `source`'s tiles: whole ones as merged rectangles in their kind's colour (an edge with the base's
## red inside), halves as triangles, each with its level's number where it fits.
func _draw_tiles(canvas: Node2D, source: LevelCollisionLayer, width: float) -> void:
	var font := ThemeDB.fallback_font
	for group: Dictionary in source.rects_by_kind():
		var kind := str(group["kind"])
		var colour: Color = KIND_COLOURS.get(kind, Color.WHITE)
		for r: Rect2 in group["rects"]:
			canvas.draw_rect(r, colour, false, width)
			if kind == EDGE and r.size.x > 8.0 and r.size.y > 8.0:
				canvas.draw_rect(r.grow(-3.0), KIND_COLOURS[BASE], false, width)
			if font != null and r.size.x >= 14.0 and r.size.y >= 14.0:
				canvas.draw_string(font, r.position + Vector2(2, 12), str(group["level"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	for half: Dictionary in source.halves():
		var points: PackedVector2Array = half["points"]
		var closed := points.duplicate()
		closed.append(points[0])
		canvas.draw_polyline(closed, KIND_COLOURS.get(str(half["kind"]), Color.WHITE), width)


## Every level's segments (`by_level`: level -> world segments) in its level's colour.
static func _draw_segments(canvas: Node2D, by_level: Dictionary, alpha: float, width: float) -> void:
	for level: int in by_level:
		var colour: Color = LEVEL_COLOURS.get(level, Color.WHITE)
		colour.a = alpha
		var segments: PackedVector2Array = by_level[level]
		for i in range(0, segments.size() - 1, 2):
			canvas.draw_line(segments[i], segments[i + 1], colour, width)


## The elevation drawing of this world (the Elevation under its ground layer), or null.
func _elevation() -> Node:
	var ground := NodeFind.layer_with_tile_set(get_parent(), TERRAIN_TILESET)
	return NodeFind.child_of(ground, load(ELEVATION_SCRIPT)) if ground != null else null


## The `elevation` paint beside this layer, or null.
func _elevation_layer() -> TileMapLayer:
	return NodeFind.layer_with_data(get_parent(), ELEVATION_DATA)


func _interior_walls() -> TileMapLayer:
	var parent := get_parent()
	if parent == null:
		return null
	for child: Node in parent.get_children():
		if child is TileMapLayer and child.has_method(&"is_wall"):
			return child
	return null
