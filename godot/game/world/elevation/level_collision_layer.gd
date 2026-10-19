@tool
extends TileMapLayer
class_name LevelCollisionLayer
## Hand-painted level collision (docs/godot/ELEVATION.md "Painting collision"): a TileMapLayer named
## `level-collision` beside a world's `elevation` layer, painted with level_collision_tileset.tres
## (tools/pack_level_collision_tileset.gd) on a 16-unit grid. Each tile is one kind for one level:
##
## - **rim** (orange, striped): the upper floor's edge. A body on that level is held there and,
##   pushing on for `elevation.dropPushMs`, drops over it to the level painted beyond (the ledge
##   drop), landing past the wall foot (`base`) painted for that lower level when there is one;
## - **base** (red): solid for bodies on that level: the wall foot they bump into.
##
## When the layer has any cell painted it replaces the world's automatic level collision (Elevation
## `_build_collision`): what is painted is exactly what collides. Which level a body stands on, the
## stairs, the hazards' and kit objects' levels still come from the `elevation` paint. Empty, the
## automatic collision works as before.
##
## In the editor the tiles show at `paint_opacity`, and `show_collision` draws the active collision
## over the art (the painted one's outlines, else a room's faces' collision, else the automatic
## outlines of every level). "Fill from
## the automatic collision" replaces the paint with the automatic collision turned into cells, to
## start from (save the scene first: it is not undoable). The game hides the layer.
##
## Owner: world (elevation).

const NODE_NAME := "level-collision"
const KIND_DATA := &"collision_kind"
const LEVEL_DATA := &"collision_level"
const KINDS: PackedStringArray = ["rim", "base"]
const KIND_COLOURS := {"rim": Color("#ff9a1f"), "base": Color("#e3343c")}
const MIN_LEVEL := -3
const MAX_LEVEL := 3
## The outline colours of the automatic collision per level (the overlay; render_room_collision.gd's).
const LEVEL_COLOURS := {-3: Color(1, 0.3, 1), -2: Color(0.8, 0.3, 1), -1: Color(0.3, 0.6, 1), 0: Color(1, 0.2, 0.2),
	1: Color(1, 0.9, 0.2), 2: Color(0.2, 1, 1), 3: Color(0.6, 1, 0.4)}
const OVERLAY := "CollisionOverlay"

## How strongly the painted tiles show in the editor (0 hides them; the overlay stays).
@export_range(0.0, 1.0, 0.05) var paint_opacity: float = 0.55:
	set(value):
		paint_opacity = value
		self_modulate.a = value
## Draws the active collision over the art in the editor (painted: its outlines; else the automatic
## outlines of every level).
@export var show_collision: bool = true:
	set(value):
		show_collision = value
		_queue_overlay()
@export_tool_button("Fill from the automatic collision", "TileMap") var fill_button: Callable = fill_from_automatic

var _overlay_queued := false


func _ready() -> void:
	self_modulate.a = paint_opacity
	if not Engine.is_editor_hint():
		visible = false
		return
	changed.connect(_queue_overlay)
	var painted := _elevation_layer()
	if painted != null and not painted.changed.is_connected(_queue_overlay):
		painted.changed.connect(_queue_overlay)
	_queue_overlay()


## The layer beside `ground_layer` (a sibling named `level-collision`), or null.
static func find_beside(ground_layer: Node) -> LevelCollisionLayer:
	if ground_layer == null or ground_layer.get_parent() == null:
		return null
	return ground_layer.get_parent().get_node_or_null(NodePath(NODE_NAME)) as LevelCollisionLayer


## True when something is painted (the layer then replaces the automatic collision).
func is_painted() -> bool:
	return not get_used_cells().is_empty()


## The kind painted at `point` (world) for bodies of `level`: "rim", "base" or "".
func kind_at(point: Vector2, level: int) -> String:
	var cell := local_to_map(to_local(point))
	var data := get_cell_tile_data(cell)
	if data == null or int(data.get_custom_data(LEVEL_DATA)) != level:
		return ""
	return str(data.get_custom_data(KIND_DATA))


## The painted collision as rectangles (world space), merged: level -> Array[Rect2]. `open`: the
## passages decks opened ([{"rect", "level"}], Elevation `open_passage`): the cells they open are left
## out (`opens`).
func rects_by_level(open: Array = []) -> Dictionary:
	var cells_of := {}
	for cell: Vector2i in get_used_cells():
		var data := get_cell_tile_data(cell)
		if data == null:
			continue
		var level := int(data.get_custom_data(LEVEL_DATA))
		if not open.is_empty() and opens(open, to_global(map_to_local(cell)), level):
			continue
		(cells_of.get_or_add(level, {}) as Dictionary)[cell] = true
	var size := Vector2(tile_set.tile_size) if tile_set != null else Vector2(16, 16)
	var out := {}
	for level: int in cells_of:
		var rects: Array[Rect2] = []
		for r: Rect2i in merged(cells_of[level]):
			var top_left := to_global(map_to_local(r.position) - size * 0.5)
			rects.append(Rect2(top_left, Vector2(r.size) * size * global_scale.abs()))
		out[level] = rects
	return out


## True when a passage of `open` ([{"rect", "level"}], world) opens the painted cell at `point` for
## `level`: inside the passage, or on a rim painted along one of its edges (one tile out, within the
## passage's span along that edge: where a slab, a landing or a lowered drawbridge joins a floor).
static func opens(open: Array, point: Vector2, level: int) -> bool:
	for passage: Dictionary in open:
		if int(passage["level"]) != level:
			continue
		var rect: Rect2 = passage["rect"]
		if rect.grow_individual(0.0, 16.0, 0.0, 16.0).has_point(point) or rect.grow_individual(16.0, 0.0, 16.0, 0.0).has_point(point):
			return true
	return false


## The cells (a set of Vector2i) as few rectangles: runs along each row, stacked where the rows below
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


## Replaces the paint with the world's automatic collision turned into cells: every cell next to
## ground a level can walk on that it cannot is painted for that level, a rim where the ground past it
## is lower (a drop), else a base. Interior walls collide by themselves: cells on them, and ground on
## them, are left out.
## A cell bordering two levels keeps the higher level's. Returns the cells painted.
func fill_from_automatic() -> int:
	var elevation := _elevation()
	if elevation == null or elevation.get(&"grid") == null:
		push_warning("level-collision: no elevation drawing to read (paint the elevation layer first)")
		return 0
	clear()
	# a room's faces give their collision exactly: copy it
	var room: Variant = elevation.get(&"room_collision")
	if room is TileMapLayer and is_instance_valid(room):
		var copied := 0
		for cell: Vector2i in (room as TileMapLayer).get_used_cells():
			set_cell(cell, 0, (room as TileMapLayer).get_cell_atlas_coords(cell))
			copied += 1
		print("level-collision: painted %d cells from the room faces' collision" % copied)
		return copied
	# read the automatic walkability, not the paint just cleared
	elevation.set(&"_painted_on", false)
	var ground := elevation.get(&"ground") as TileMapLayer
	var used := ground.get_used_rect()
	var step := float(tile_set.tile_size.x) if tile_set != null else 16.0
	var big := float(ground.tile_set.tile_size.x)
	var per := int(round(big / step))
	var walls := _interior_walls()
	var levels: Array[int] = []
	for level in range(MAX_LEVEL, MIN_LEVEL - 1, -1):
		levels.append(level)
	var painted := 0
	var near: Array[Vector2] = [Vector2(step, 0), Vector2(-step, 0), Vector2(0, step), Vector2(0, -step),
		Vector2(step, step), Vector2(-step, step), Vector2(step, -step), Vector2(-step, -step)]
	for y in range(used.position.y * per, used.end.y * per):
		for x in range(used.position.x * per, used.end.x * per):
			var centre := ground.to_global(Vector2(x + 0.5, y + 0.5) * step)
			if walls != null and bool(walls.call(&"is_wall", walls.local_to_map(walls.to_local(centre)))):
				continue
			for level in levels:
				if bool(elevation.call(&"is_walkable", centre, level)):
					continue
				var borders := false
				for d in near:
					# ground on an interior wall does not count: the wall collides by itself
					if walls != null and bool(walls.call(&"is_wall", walls.local_to_map(walls.to_local(centre + d)))):
						continue
					if bool(elevation.call(&"is_walkable", centre + d, level)):
						borders = true
						break
				if not borders:
					continue
				var lower := int(elevation.call(&"_lower_level_at", centre, level))
				var kind := "rim" if lower >= MIN_LEVEL else "base"
				set_cell(local_to_map(to_local(centre)), 0, Vector2i(KINDS.find(kind), level - MIN_LEVEL))
				painted += 1
				break
	print("level-collision: painted %d cells from the automatic collision" % painted)
	return painted


# --- the editor's overlay ------------------------------------------------------------------------

func _queue_overlay() -> void:
	if not Engine.is_editor_hint() or _overlay_queued or not is_inside_tree():
		return
	_overlay_queued = true
	# after the elevation's own (deferred) rebuild
	(func() -> void: _draw_overlay.call_deferred()).call_deferred()


func _draw_overlay() -> void:
	_overlay_queued = false
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


## Draws the active collision (world space) on `canvas`: the painted cells' merged outlines in their
## kind's colour and their level's number; else (inside rooms) the room faces' collision the same
## way; else the automatic outline of every level in its colour.
func _paint_overlay(canvas: Node2D) -> void:
	var source: LevelCollisionLayer = self if is_painted() else null
	var elevation_now := _elevation()
	if source == null and elevation_now != null:
		var room: Variant = elevation_now.get(&"room_collision")
		if room is LevelCollisionLayer and is_instance_valid(room):
			source = room
	if source != null:
		var font := ThemeDB.fallback_font
		var rects := source.rects_by_level()
		for level: int in rects:
			for r: Rect2 in rects[level]:
				var kind := source.kind_at(r.get_center(), level)
				var colour: Color = KIND_COLOURS.get(kind, Color.WHITE)
				canvas.draw_rect(r, colour, false, 2.0)
				if font != null and r.size.x >= 14.0 and r.size.y >= 14.0:
					canvas.draw_string(font, r.position + Vector2(2, 12), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		return
	var elevation := _elevation()
	if elevation == null or elevation.get(&"grid") == null:
		return
	var origin: Vector2 = (elevation as Node2D).global_position
	var outlines: Variant = elevation.get(&"_outlines")
	for level in range(MIN_LEVEL, MAX_LEVEL + 1):
		if outlines is Dictionary:
			(outlines as Dictionary).clear()
		var segments: PackedVector2Array = elevation.call(&"_level_segments", level)
		var colour: Color = LEVEL_COLOURS.get(level, Color.WHITE)
		for i in range(0, segments.size() - 1, 2):
			canvas.draw_line(origin + segments[i], origin + segments[i + 1], colour, 2.0)


## The elevation drawing of this world (mounted under its ground layer), or null.
func _elevation() -> Node:
	var parent := get_parent()
	var ground := parent.get_node_or_null(^"ground") if parent != null else null
	return ground.get_node_or_null(^"Elevation") if ground != null else null


func _elevation_layer() -> TileMapLayer:
	var parent := get_parent()
	return parent.get_node_or_null(^"elevation") as TileMapLayer if parent != null else null


func _interior_walls() -> TileMapLayer:
	var parent := get_parent()
	if parent == null:
		return null
	for child: Node in parent.get_children():
		if child is TileMapLayer and child.has_method(&"is_wall"):
			return child
	return null
