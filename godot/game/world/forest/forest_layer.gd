@tool
class_name ForestLayer
extends TileMapLayer
## A tree wall painted like a terrain (docs/godot/FORESTS.md): Add Node > ForestLayer in a world
## scene (beside the ground layer, on the same grid), then paint cells with the palette of
## forest_tileset.tres. The top row of the palette holds mixes (each tree picks a tree of its
## cell's mix); the rows below hold single trees (the cell takes exactly that tree). Erase cells to
## cut gaps and paths.
##
## The trees are the big trees of the region sets (BigTrees: forest, autumn, frost, desert cacti,
## volcano, swamp, crystal, ruins, village), two to three cells wide, so they grow on about one
## painted cell in three: one candidate per 2 x 2 block, never two side by side, and every painted
## cell has one in or around it, so a one-cell row still reads as a wall. A single tree painted from
## the palette always grows. A tree stands where the old wall trees stood in their cell, with a
## seeded shift, size and flip (`variation` rerolls them all), casts a soft shade on the ground, and
## sways in tree_sway.gdshader unless it is rigid (cacti, crystals, mushrooms, bare trees).
##
## The trees are drawn by this layer and saved nowhere: the scene stores only the painted cells.
## In the game the whole painted area is solid along its trunk line (one shape per run of cells).
## The squares are a painting aid, drawn at `paint_opacity` in the editor and hidden in the game.
##
## "Absorb trees" turns placed wall trees (tree-forest-wall--* instances, the children of the node
## `absorb_from`) into painted cells of the mix `absorb_into_mix`, and removes them (undoable);
## tools/absorb_wall_trees.gd does the same without the editor.
##
## Owner: world (forest).

const TILESET := "res://game/world/forest/forest_tileset.tres"
const BigTrees := preload("res://game/world/forest/big_trees.gd")
const MIX_DATA_LAYER := "forest_mix"
const TREES_DATA_LAYER := "forest_trees"
## One candidate cell per block of this many cells a side.
const BLOCK := 2
## Where a tree stands in its cell (its trunk's foot), and the trunk's height above it: the old
## wall tree scenes (trunk box 48 x 44 above the foot) placed on the grid.
const FOOT := Vector2(32.0, 54.0)
const TRUNK_HEIGHT := 44.0
## Trees may stand this much further across than `shift` says (they have room).
const SHIFT_SCALE := Vector2(1.6, 1.0)
## Placed wall tree scenes "Absorb trees" takes.
const WALL_SCENE_PREFIX := "tree-forest-wall--"
const HOLDER := "Trees"
## The holder of the trees' shades (each shade draws at BigTrees.SHADOW_Z).
const SHADOWS := "Shadows"
const COLLISION := "Collision"

## Another number shifts, sizes and flips every tree, picks other trees of a mix and other cells
## to grow them.
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
## The mix the absorbed trees' cells are painted with: its column in the palette's top row (0 mixed,
## 1 pine, 2 green... 17 forest medium).
@export var absorb_into_mix: int = 0
@export_tool_button("Absorb trees", "Add") var absorb_button: Callable = _absorb_pressed

var _queued := false


func _ready() -> void:
	if tile_set == null:
		tile_set = load(TILESET)
	y_sort_enabled = true
	_apply_opacity()
	if not changed.is_connected(_queue_rebuild):
		changed.connect(_queue_rebuild)
	_rebuild()


func _apply_opacity() -> void:
	self_modulate.a = paint_opacity if Engine.is_editor_hint() else 0.0


func _queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()


## The trees of a painted cell's tile, by name (BigTrees).
func trees_of(cell: Vector2i) -> PackedStringArray:
	var data := get_cell_tile_data(cell)
	if data == null or not tile_set.has_custom_data_layer_by_name(TREES_DATA_LAYER):
		return PackedStringArray()
	return str(data.get_custom_data(TREES_DATA_LAYER)).split(",", false)


func _rebuild() -> void:
	_queued = false
	if not is_inside_tree() or tile_set == null:
		return
	var holder := _holder(HOLDER, true)
	var shadows := _holder(SHADOWS, false)
	var cells := get_used_cells()
	cells.sort()
	var growing := _growing_cells(cells)
	for cell in cells:
		if not growing.has(cell):
			continue
		var trees := trees_of(cell)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([cell.x, cell.y, variation])
		var sprite := Sprite2D.new()
		if not BigTrees.configure(sprite, trees[rng.randi_range(0, trees.size() - 1)]):
			sprite.free()
			continue
		sprite.flip_h = rng.randf() < 0.5
		sprite.scale *= rng.randf_range(size_range.x, size_range.y)
		var reach := shift * SHIFT_SCALE
		sprite.position = Vector2(cell) * Vector2(tile_set.tile_size) + FOOT \
				+ Vector2(rng.randf_range(-reach.x, reach.x), rng.randf_range(-reach.y, reach.y))
		holder.add_child(sprite)
		shadows.add_child(BigTrees.shadow_for(sprite))
	if not Engine.is_editor_hint():
		_build_collision(cells)


## The child `holder_name` (unowned, so never saved), emptied.
func _holder(holder_name: String, y_sorted: bool) -> Node2D:
	var holder := get_node_or_null(holder_name) as Node2D
	if holder == null:
		holder = Node2D.new()
		holder.name = holder_name
		holder.y_sort_enabled = y_sorted
		add_child(holder)
	for child in holder.get_children():
		child.free()
	return holder


## The painted cells that grow a tree: one candidate per BLOCK x BLOCK block (seeded), kept when no
## tree grows beside it (diagonal neighbours may), then every cell still without one in or around
## it (so thin rows fill); single trees always grow.
func _growing_cells(cells: Array[Vector2i]) -> Dictionary:
	var growing := {}
	var painted := {}
	for cell in cells:
		var trees := trees_of(cell)
		if trees.is_empty():
			continue
		painted[cell] = true
		if trees.size() == 1:
			growing[cell] = true
	var blocks := {}
	for cell: Vector2i in painted:
		blocks[Vector2i(floori(cell.x / float(BLOCK)), floori(cell.y / float(BLOCK)))] = true
	var order := blocks.keys()
	order.sort()
	for block: Vector2i in order:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([block.x, block.y, variation, "block"])
		var cell := block * BLOCK + Vector2i(rng.randi_range(0, BLOCK - 1), rng.randi_range(0, BLOCK - 1))
		if painted.has(cell) and not growing.has(cell) and not _tree_near(growing, cell, false):
			growing[cell] = true
	for cell in cells:
		if painted.has(cell) and not growing.has(cell) and not _tree_near(growing, cell, true):
			growing[cell] = true
	return growing


## True when a tree grows beside `cell` (the four cells across and up/down, and the diagonal ones
## too when `diagonals`).
static func _tree_near(growing: Dictionary, cell: Vector2i, diagonals: bool) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 and dy != 0 and not diagonals) or (dx == 0 and dy == 0):
				continue
			if growing.has(cell + Vector2i(dx, dy)):
				return true
	return false


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
## nodes: [the trees taken], skipped: [names of children that are no wall tree]}. A wall tree is a
## tree-forest-wall--* instance; its cell is the one whose tree place is nearest its foot
## (`foot_of(tree)` in this layer's space when given, for tools working outside the scene tree) and
## takes the mix `absorb_into_mix`; the first tree in a cell wins.
func absorb_plan(group: Node, foot_of := Callable()) -> Dictionary:
	var cells := {}
	var nodes: Array[Node] = []
	var skipped: PackedStringArray = []
	var size := Vector2(tile_set.tile_size)
	for child in group.get_children():
		var tree := child as Node2D
		if tree == null or not tree.scene_file_path.get_file().begins_with(WALL_SCENE_PREFIX):
			skipped.append(str(child.name))
			continue
		var foot: Vector2 = foot_of.call(tree) if foot_of.is_valid() else to_local(tree.global_position)
		var cell := Vector2i(((foot - FOOT) / size + Vector2(0.5, 0.5)).floor())
		if not cells.has(cell):
			cells[cell] = Vector2i(maxi(absorb_into_mix, 0), 0)
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


## Applies an `absorb_plan` without undo: paints its cells and frees its trees.
func apply_absorb(plan: Dictionary) -> void:
	for cell: Vector2i in plan["cells"]:
		set_cell(cell, 0, plan["cells"][cell])
	for node: Node in plan["nodes"]:
		node.get_parent().remove_child(node)
		node.queue_free()
