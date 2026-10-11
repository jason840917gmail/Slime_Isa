@tool
class_name ForestLayer
extends TileMapLayer
## A tree wall painted like a terrain (docs/godot/FORESTS.md): Add Node > ForestLayer in a world
## scene (beside the ground layer, on the same grid), then paint cells with the palette of
## forest_tileset.tres. Every painted cell grows one tree, standing where the old wall trees stood
## in their cell, with a small seeded shift, size and flip (`variation` rerolls them all). The top
## row of the palette holds mixes (each cell picks a tree of the mix); the rows below hold single
## trees (the cell takes exactly that tree). Erase cells to cut gaps and paths.
##
## The trees are drawn by this layer and saved nowhere: the scene stores only the painted cells.
## In the game the painted area is solid along its trunk line (one shape per run of cells) and the
## trees sway. The squares are a painting aid, drawn at `paint_opacity` in the editor and hidden in
## the game.
##
## "Absorb trees" turns tree instances already in the scene (wall trees from the trees sway sheet,
## the children of the node `absorb_from`, like a world's "Forest Border") into painted cells of
## the same tree, and removes them (undoable).
##
## Owner: world (forest).

const TILESET := "res://game/world/forest/forest_tileset.tres"
const SHEET := "res://asset/MAPS/trees/128x170-tile_16x22-trees-sway.webp"
const MIX_DATA_LAYER := "forest_mix"
const TREES_DATA_LAYER := "forest_trees"
const SHEET_COLUMNS := 16
const SHEET_ROWS := 22
const SWAY_FRAMES := 8
## Sway frames per second (presentation only, real time).
const SWAY_FPS := 4.0
## Where a tree stands in its cell (its trunk's foot), and the trunk's height above it: the wall
## tree scenes (tree-forest-wall--*.tscn: frame offset (-64, -170), trunk box 48 x 44 above the
## foot) placed on the grid.
const FOOT := Vector2(32.0, 54.0)
const TRUNK_HEIGHT := 44.0
const FRAME_OFFSET := Vector2(-64.0, -170.0)
## Palette tile of a single tree: first frame 8k at (k % 16, 1 + k / 16).
const SINGLE_ROW := 1
const HOLDER := "Trees"
const COLLISION := "Collision"

## Another number shifts, sizes and flips every tree (and picks other trees of a mix) anew.
@export var variation: int = 0:
	set(value):
		variation = value
		_queue_rebuild()
## How far a tree may stand from its place (world units, across and down).
@export var shift := Vector2(10.0, 6.0):
	set(value):
		shift = value
		_queue_rebuild()
## Smallest and largest tree size.
@export var size_range := Vector2(0.98, 1.1):
	set(value):
		size_range = value
		_queue_rebuild()
## How strongly the painted squares show over the trees in the editor (0 hides them).
@export_range(0.0, 1.0) var paint_opacity: float = 0.3:
	set(value):
		paint_opacity = value
		_apply_opacity()
@export_group("Absorb trees")
## The node whose children (wall tree instances) "Absorb trees" turns into painted cells.
@export_node_path("Node2D") var absorb_from: NodePath
@export_tool_button("Absorb trees", "Add") var absorb_button: Callable = _absorb_pressed

var _queued := false
## Per tree sprite: its first sway frame and its phase.
var _sway: Array[Array] = []
var _sheet: Texture2D
var _tick := -1


func _ready() -> void:
	if tile_set == null:
		tile_set = load(TILESET)
	y_sort_enabled = true
	_apply_opacity()
	if not changed.is_connected(_queue_rebuild):
		changed.connect(_queue_rebuild)
	set_process(not Engine.is_editor_hint())
	_rebuild()


func _process(_delta: float) -> void:
	var tick := int(Time.get_ticks_msec() * SWAY_FPS / 1000.0)
	var holder := get_node_or_null(HOLDER)
	if holder == null or tick == _tick:
		return
	_tick = tick
	var sprites := holder.get_children()
	for i in mini(sprites.size(), _sway.size()):
		(sprites[i] as Sprite2D).frame = int(_sway[i][0]) + (tick + int(_sway[i][1])) % SWAY_FRAMES


func _apply_opacity() -> void:
	self_modulate.a = paint_opacity if Engine.is_editor_hint() else 0.0


func _queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()


## The trees of a painted cell's tile: their first sway frames.
func trees_of(cell: Vector2i) -> PackedInt32Array:
	var data := get_cell_tile_data(cell)
	var out := PackedInt32Array()
	if data == null or not tile_set.has_custom_data_layer_by_name(TREES_DATA_LAYER):
		return out
	for part in str(data.get_custom_data(TREES_DATA_LAYER)).split(",", false):
		out.append(int(part))
	return out


func _rebuild() -> void:
	_queued = false
	if not is_inside_tree() or tile_set == null:
		return
	if _sheet == null:
		_sheet = load(SHEET) as Texture2D
	var holder := get_node_or_null(HOLDER) as Node2D
	if holder == null:
		holder = Node2D.new()
		holder.name = HOLDER
		holder.y_sort_enabled = true
		add_child(holder)
	for child in holder.get_children():
		child.free()
	_sway.clear()
	var cells := get_used_cells()
	cells.sort()
	for cell in cells:
		var trees := trees_of(cell)
		if trees.is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([cell.x, cell.y, variation])
		var first := trees[rng.randi_range(0, trees.size() - 1)]
		var sprite := Sprite2D.new()
		sprite.texture = _sheet
		sprite.hframes = SHEET_COLUMNS
		sprite.vframes = SHEET_ROWS
		sprite.centered = false
		sprite.offset = FRAME_OFFSET
		sprite.flip_h = rng.randf() < 0.5
		var size := rng.randf_range(size_range.x, size_range.y)
		sprite.scale = Vector2(size, size)
		sprite.position = Vector2(cell) * Vector2(tile_set.tile_size) + FOOT \
				+ Vector2(rng.randf_range(-shift.x, shift.x), rng.randf_range(-shift.y, shift.y))
		var phase := rng.randi_range(0, SWAY_FRAMES - 1)
		sprite.frame = first + phase
		holder.add_child(sprite)
		_sway.append([first, phase])
	if not Engine.is_editor_hint():
		_build_collision(cells)


## Solid along the trunk line: per painted cell from its trees' trunk tops (from the cell's top
## when the cell above is painted too) to their feet (to the cell's bottom when the cell below is
## painted), joined into one rectangle per run of cells along a row.
func _build_collision(cells: Array[Vector2i]) -> void:
	var old := get_node_or_null(COLLISION)
	if old != null:
		old.free()
	var body := StaticBody2D.new()
	body.name = COLLISION
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var painted := {}
	for cell in cells:
		if not trees_of(cell).is_empty():
			painted[cell] = true
	var size := Vector2(tile_set.tile_size)
	var done := {}
	for cell: Vector2i in cells:
		if not painted.has(cell) or done.has(cell):
			continue
		var top := 0.0 if painted.has(cell + Vector2i.UP) else FOOT.y - TRUNK_HEIGHT
		var bottom := size.y if painted.has(cell + Vector2i.DOWN) else FOOT.y
		var end := cell
		while true:
			var next := end + Vector2i.RIGHT
			if not painted.has(next) or done.has(next):
				break
			var next_top := 0.0 if painted.has(next + Vector2i.UP) else FOOT.y - TRUNK_HEIGHT
			var next_bottom := size.y if painted.has(next + Vector2i.DOWN) else FOOT.y
			if next_top != top or next_bottom != bottom:
				break
			end = next
		for x in range(cell.x, end.x + 1):
			done[Vector2i(x, cell.y)] = true
		var rect := Rect2(Vector2(cell) * size + Vector2(0.0, top), Vector2((end.x - cell.x + 1) * size.x, bottom - top))
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.get_center()
		body.add_child(shape)


# --- absorbing placed trees ----------------------------------------------------------------

## What "Absorb trees" would do with the children of `group`: {cells: {Vector2i: atlas coords},
## nodes: [the trees taken], skipped: [names of children that are no wall tree of the sheet]}.
## A tree's cell is the one whose tree place is nearest its foot; the first tree in a cell wins.
func absorb_plan(group: Node) -> Dictionary:
	var cells := {}
	var nodes: Array[Node] = []
	var skipped: PackedStringArray = []
	var size := Vector2(tile_set.tile_size)
	for child in group.get_children():
		var tree := child as Node2D
		var visual := tree.get_node_or_null(^"Visual") as Sprite2D if tree != null else null
		if visual == null or visual.texture == null or visual.texture.resource_path != SHEET:
			skipped.append(str(child.name))
			continue
		var foot := to_local(tree.global_position)
		var cell := Vector2i(((foot - FOOT) / size + Vector2(0.5, 0.5)).floor())
		if not cells.has(cell):
			var k := int(visual.frame) / SWAY_FRAMES
			cells[cell] = Vector2i(k % SHEET_COLUMNS, SINGLE_ROW + k / SHEET_COLUMNS)
		nodes.append(child)
	return {"cells": cells, "nodes": nodes, "skipped": skipped}


func _absorb_pressed() -> void:
	var group := get_node_or_null(absorb_from)
	if group == null:
		push_warning("ForestLayer: set 'Absorb From' to the node holding the trees first.")
		return
	var plan := absorb_plan(group)
	var editor := Engine.get_singleton(&"EditorInterface") if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface") else null
	var undo: Object = editor.call(&"get_editor_undo_redo") if editor != null else null
	if undo == null:
		apply_absorb(plan)
		return
	undo.call(&"create_action", "Absorb trees into %s" % name)
	for cell: Vector2i in plan["cells"]:
		undo.call(&"add_do_method", self, &"set_cell", cell, 0, plan["cells"][cell])
		if get_cell_source_id(cell) >= 0:
			undo.call(&"add_undo_method", self, &"set_cell", cell, get_cell_source_id(cell), get_cell_atlas_coords(cell))
		else:
			undo.call(&"add_undo_method", self, &"erase_cell", cell)
	for node: Node in plan["nodes"]:
		var parent := node.get_parent()
		undo.call(&"add_do_method", parent, &"remove_child", node)
		undo.call(&"add_undo_method", parent, &"add_child", node)
		undo.call(&"add_undo_method", parent, &"move_child", node, node.get_index())
		undo.call(&"add_undo_method", node, &"set_owner", node.owner)
		undo.call(&"add_undo_reference", node)
	undo.call(&"commit_action")
	print("ForestLayer: absorbed %d trees into %d cells; %d children skipped %s" % [
			(plan["nodes"] as Array).size(), (plan["cells"] as Dictionary).size(),
			(plan["skipped"] as PackedStringArray).size(), plan["skipped"]])


## Applies an `absorb_plan` without undo (tools): paints its cells and frees its trees.
func apply_absorb(plan: Dictionary) -> void:
	for cell: Vector2i in plan["cells"]:
		set_cell(cell, 0, plan["cells"][cell])
	for node: Node in plan["nodes"]:
		node.get_parent().remove_child(node)
		node.queue_free()
