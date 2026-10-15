extends SceneTree
## Turns painted props of a world into nodes under its `Scenery` node (docs/godot/PROPS.md), so
## they can be selected and moved like nodes: every prop painted on the world's prop layers becomes
## an instance of its scene, its size and mirror on its own Scale (negative x when mirrored, as in
## the Inspector; Godot keeps no changes to an instance's children unless they are made editable),
## its picture exactly where the painted one was, and its cell is erased;
## the props whose scene path (after game/scenes/objects/) starts with a --keep prefix stay painted
## (by default the ground details and the water life: flowers, clover, pebbles, leaves, roots,
## lily pads, reeds, fish). Run headless with the world closed in the editor:
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/paint_to_nodes.gd -- \
##         --scene=res://game/scenes/worlds/chunks/level-1-c4.tscn [--scene=...] \
##         [--keep=interiors/mushroom-floor/,water-life] [--dry]

const Props := preload("res://game/world/props/prop_layer.gd")
const SceneSave := preload("res://tools/lib/scene_save.gd")
const Pictures := preload("res://tools/lib/prop_pictures.gd")
const OBJECTS := "res://game/scenes/objects/"
const CONTAINER := "Scenery"
const KEEP: PackedStringArray = ["interiors/mushroom-floor/", "water-life"]


func _initialize() -> void:
	var scenes := PackedStringArray()
	var keep := KEEP
	var dry := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scenes.append(arg.trim_prefix("--scene="))
		elif arg.begins_with("--keep="):
			keep = arg.trim_prefix("--keep=").split(",", false)
		elif arg == "--dry":
			dry = true
	for path in scenes:
		_convert(path, keep, dry)
	quit(0)


func _convert(path: String, keep: PackedStringArray, dry: bool) -> void:
	var before := FileAccess.get_file_as_string(path)
	var root := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	var layers: Array[TileMapLayer] = []
	for child in root.get_children():
		if child.get_script() == Props:
			layers.append(child as TileMapLayer)
	var container := root.get_node_or_null(CONTAINER) as Node2D
	if container == null:
		container = Node2D.new()
		container.name = CONTAINER
		container.y_sort_enabled = true
		root.add_child(container)
		if not layers.is_empty():
			root.move_child(container, layers[-1].get_index() + 1)
		container.owner = root
	var to_container := container.get_global_transform().affine_inverse() if container.is_inside_tree() \
			else _to_root(container).affine_inverse()
	var made := {}
	var kept := 0
	for layer in layers:
		var to_root := _to_root(layer)
		for cell in layer.get_used_cells():
			var prop: Dictionary = layer.call(&"prop_at", cell)
			if prop.is_empty():
				continue
			var rel := str(prop["scene"]).trim_prefix(OBJECTS)
			var stays := false
			for prefix in keep:
				stays = stays or rel.begins_with(prefix)
			if stays:
				kept += 1
				continue
			var node := _node_for(prop)
			if node == null:
				continue
			node.position = to_container * (to_root * node.position)
			container.add_child(node, true)
			node.owner = container.owner
			layer.erase_cell(cell)
			made[layer.name] = int(made.get(layer.name, 0)) + 1
	var total := 0
	for count: int in made.values():
		total += count
	print("%s: %d props became nodes under %s %s, %d stay painted%s" % [path.get_file(), total, CONTAINER, made, kept,
			" (dry run)" if dry else ""])
	if dry or total == 0:
		root.free()
		return
	var err := SceneSave.save(root, path, before)
	root.free()
	if err != OK:
		push_error("paint_to_nodes: %s: %s" % [path, error_string(err)])


## An instance of `prop`'s scene (as the editor makes them) showing its picture exactly where the
## painted prop shows it (layer space), its size and mirror on its root's scale.
func _node_for(prop: Dictionary) -> Node2D:
	var painted := Props.make_prop(prop)
	if painted == null:
		return null
	var want := Pictures.bounds(painted, Transform2D.IDENTITY)
	painted.free()
	var node := (load(prop["scene"]) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	var size := float(prop["size"])
	node.scale = Vector2(-size if bool(prop["flip"]) else size, size)
	node.position = prop["at"]
	var have := Pictures.bounds(node, Transform2D.IDENTITY)
	if want.has_area() and have.has_area():
		node.position += want.position - have.position
	return node


## `node`'s transform in its scene root's space (the scene is not in the tree).
func _to_root(node: Node) -> Transform2D:
	var transform := Transform2D.IDENTITY
	var at := node
	while at != null and at.get_parent() != null:
		if at is Node2D:
			transform = (at as Node2D).transform * transform
		at = at.get_parent()
	return transform
