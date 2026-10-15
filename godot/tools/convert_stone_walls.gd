extends SceneTree
## Turns a world's old stone walls (docs/godot/WALLS.md) into cells of its `walls` WallLayer: every
## stone wall painted on a prop layer (or still placed as a node) becomes the stone style on the wall
## cell it stands in and leaves the prop layer; the shapes then follow the neighbours by themselves.
## The world's 64-grid prop layer, until now named `walls`, is renamed `large-props` (it keeps the
## houses, rock and crystal walls). Walls built off the 64 grid (half a cell over, say) go on a
## second wall layer shifted by that offset (`walls-shifted-<x>-<y>`), so every wall keeps its
## place. Close or reload the world in the editor afterwards.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/convert_stone_walls.gd -- \
##         --scene=res://game/scenes/worlds/chunks/level-1-c4.tscn [--scene=...] [--dry]

const SceneSave := preload("res://tools/lib/scene_save.gd")
const PROP_LAYER := "res://game/world/props/prop_layer.gd"
const WALL_LAYER := "res://game/world/walls/wall_layer.gd"
const WALL_TILESET := "res://game/world/walls/wall_tileset.tres"
const OLD_WALL := "res://game/scenes/objects/wall-stone-solid"
## The stone style's palette tile.
const STONE := Vector2i(0, 0)
const CELL := 64.0
const FOOT := Vector2(32.0, 64.0)


func _initialize() -> void:
	var scenes := PackedStringArray()
	var dry := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scenes.append(arg.trim_prefix("--scene="))
		elif arg == "--dry":
			dry = true
	for path in scenes:
		_convert(path, dry)
	quit(0)


func _convert(path: String, dry: bool) -> void:
	var before := FileAccess.get_file_as_string(path)
	var root := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	var feet: Array[Vector2] = []
	var prop_cells := 0
	var nodes := 0
	var old_walls_layer: TileMapLayer = null
	for layer in root.find_children("*", "TileMapLayer", false, false):
		if layer.get_script() == null or (layer.get_script() as Script).resource_path != PROP_LAYER:
			continue
		if layer.name == &"walls":
			old_walls_layer = layer
		var to_root := _to_root(layer)
		for cell: Vector2i in (layer as TileMapLayer).get_used_cells():
			var prop: Dictionary = layer.call(&"prop_at", cell)
			if prop.is_empty() or not str(prop["scene"]).begins_with(OLD_WALL):
				continue
			feet.append(to_root * Vector2(prop["at"]))
			(layer as TileMapLayer).erase_cell(cell)
			prop_cells += 1
	for node in _wall_nodes(root, root):
		feet.append(_to_root(node).origin)
		node.get_parent().remove_child(node)
		node.free()
		nodes += 1
	if feet.is_empty():
		print("%s: no stone walls" % path.get_file())
		root.free()
		return
	var walls := _wall_layer(root, old_walls_layer)
	var to_walls := _to_root(walls).affine_inverse()
	var layers := {Vector2i.ZERO: walls}
	var doubled := 0
	for foot in feet:
		var at := to_walls * foot
		# Walls off the 64 grid go on a wall layer shifted by their offset (one per offset), so
		# every wall keeps its place.
		var offset := Vector2i((Vector2(fposmod(at.x - FOOT.x, CELL), fposmod(at.y - FOOT.y, CELL))).round())
		offset = Vector2i(offset.x % int(CELL), offset.y % int(CELL))
		if not layers.has(offset):
			layers[offset] = _shifted_layer(root, walls, offset)
		var layer: TileMapLayer = layers[offset]
		var cell := Vector2i(((at - Vector2(offset) - FOOT) / CELL).round())
		if layer.get_cell_source_id(cell) >= 0:
			doubled += 1
			continue
		layer.set_cell(cell, 0, STONE)
	var counts := PackedStringArray()
	for offset: Vector2i in layers:
		counts.append("%s %d" % [layers[offset].name, (layers[offset] as TileMapLayer).get_used_cells().size()])
	print("%s: %d stone walls (%d painted, %d nodes) -> %s; %d shared a cell%s" % [
			path.get_file(), feet.size(), prop_cells, nodes, ", ".join(counts), doubled, " (dry run)" if dry else ""])
	if dry:
		root.free()
		return
	var err := SceneSave.save(root, path, before)
	root.free()
	if err != OK:
		push_error("convert_stone_walls: %s: %s" % [path, error_string(err)])


## Old stone wall instances placed in this scene (not inside other instances).
func _wall_nodes(node: Node, root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		if child.owner != root:
			continue
		if child.scene_file_path.begins_with(OLD_WALL):
			out.append(child)
		elif child.scene_file_path.is_empty():
			out.append_array(_wall_nodes(child, root))
	return out


## The world's WallLayer `walls`, made where the old 64-grid prop layer stood (renamed
## `large-props`), else after the ground and painted layers.
func _wall_layer(root: Node, old_walls: TileMapLayer) -> TileMapLayer:
	var existing := root.get_node_or_null(^"walls") as TileMapLayer
	if existing != null and existing.get_script() != null and (existing.get_script() as Script).resource_path == WALL_LAYER:
		return existing
	var index := -1
	if old_walls != null:
		old_walls.name = &"large-props"
		index = old_walls.get_index()
	var layer := TileMapLayer.new()
	layer.name = &"walls"
	layer.tile_set = load(WALL_TILESET)
	layer.y_sort_enabled = true
	layer.set_script(load(WALL_LAYER))
	if index < 0:
		for i in root.get_child_count():
			var child := root.get_child(i)
			if child is TileMapLayer:
				index = i + 1
	root.add_child(layer)
	root.move_child(layer, maxi(index, 0))
	layer.owner = root
	return layer


## A second wall layer like `walls`, moved by `offset` (units) so walls built off the 64 grid keep
## their places; named after the offset.
func _shifted_layer(root: Node, walls: TileMapLayer, offset: Vector2i) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "walls-shifted-%d-%d" % [offset.x, offset.y]
	layer.tile_set = walls.tile_set
	layer.y_sort_enabled = true
	layer.set_script(load(WALL_LAYER))
	layer.position = walls.position + Vector2(offset)
	root.add_child(layer)
	root.move_child(layer, walls.get_index() + 1)
	layer.owner = root
	return layer


func _to_root(node: Node) -> Transform2D:
	var transform := Transform2D.IDENTITY
	var at := node
	while at != null and at.get_parent() != null:
		if at is Node2D:
			transform = (at as Node2D).transform * transform
		at = at.get_parent()
	return transform
