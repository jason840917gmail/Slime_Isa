extends SceneTree
## Turns the scenery props placed in world scenes into paint on their prop layers
## (docs/godot/PROPS.md): every instance of a palette scene becomes a painted cell of the `walls` or
## `props` PropLayer (made when the world has none) and is removed, so the scene tree loses its many
## prop nodes. A prop goes on the first layer that holds it where it stands: the walls layer's
## 64-unit grid only when it sits exactly on it, else the props layer's 8-unit grid (moved at most 4
## units). A prop is absorbed only when nothing about it would be lost: its overrides are only
## its position, its Visual's size, mirror and offset, and save ids; it has no signal connections,
## groups or added children of its own; its cell is free. Every other prop stays a node and is
## counted by reason. Uids the save drops are put back.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/absorb_props.gd -- \
##         --scene=res://game/scenes/worlds/level-1.tscn [--scene=...] [--dry]
## Close or reload the scenes in the editor afterwards (it holds its own copy).

const Props := preload("res://game/world/props/prop_layer.gd")
const LAYERS := {
	"walls": "res://game/world/props/walls_tileset.tres",
	"props": "res://game/world/props/props_tileset.tres",
}
## Metadata a prop may carry and lose (save ids of the Phaser conversion, editor locks).
const DROPPED_META: PackedStringArray = ["instance_id", "persistence_key", "_edit_group_", "_edit_lock_"]
## Visual overrides that become the cell's size, mirror and position.
const VISUAL_OVERRIDES: PackedStringArray = ["scale", "flip_h", "offset"]
const SIZE_TOLERANCE := 0.06

var _fresh := {}


func _initialize() -> void:
	var scenes := PackedStringArray()
	var dry := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scenes.append(arg.trim_prefix("--scene="))
		elif arg == "--dry":
			dry = true
	var index := _index()
	for path in scenes:
		_absorb(path, index, dry)
	for node: Node in _fresh.values():
		node.free()
	quit(0)


## scene path -> its places, walls layer first: [{layer, source, anchor, tile, tiles: [[coords, size]]}].
func _index() -> Dictionary:
	var index := {}
	for layer_name: String in LAYERS:
		var tile_set := load(LAYERS[layer_name]) as TileSet
		for s in tile_set.get_source_count():
			var source_id := tile_set.get_source_id(s)
			var source := tile_set.get_source(source_id) as TileSetAtlasSource
			for t in source.get_tiles_count():
				var coords := source.get_tile_id(t)
				var data := source.get_tile_data(coords, 0)
				var scene := str(data.get_custom_data(Props.SCENE_DATA))
				if scene.is_empty():
					continue
				if not index.has(scene):
					index[scene] = []
				var places: Array = index[scene]
				if places.is_empty() or places[-1]["layer"] != layer_name or places[-1]["source"] != source_id:
					places.append({"layer": layer_name, "source": source_id, "tile": tile_set.tile_size,
							"anchor": data.get_custom_data(Props.ANCHOR_DATA), "tiles": []})
				(places[-1]["tiles"] as Array).append([coords, float(data.get_custom_data(Props.SIZE_DATA))])
	return index


func _absorb(path: String, index: Dictionary, dry: bool) -> void:
	var before := FileAccess.get_file_as_string(path)
	var root := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	var found: Array[Node] = []
	_collect(root, root, index, found)
	var layers := {}
	var kept := {}
	var absorbed := 0
	var emptied := {}
	for node: Node in found:
		var why := _unsupported(node)
		if why.is_empty():
			for entry: Dictionary in index[node.scene_file_path]:
				var layer := _layer(root, layers, entry["layer"])
				var place := _place(node, layer, entry, (entry["tile"] as Vector2i).x > 8)
				why = str(place.get("why", ""))
				if why.is_empty():
					layer.set_cell(place["cell"], entry["source"], place["coords"],
							TileSetAtlasSource.TRANSFORM_FLIP_H if place["flip"] else 0)
					break
			if why.is_empty():
				var parent := node.get_parent()
				parent.remove_child(node)
				node.free()
				emptied[parent] = true
				absorbed += 1
				continue
		kept[why] = int(kept.get(why, 0)) + 1
	for parent: Node in emptied:
		if parent != root and parent.get_child_count() == 0 and parent.scene_file_path.is_empty():
			parent.get_parent().remove_child(parent)
			parent.free()
	print("%s: %d props absorbed, %d kept %s%s" % [path.get_file(), absorbed, found.size() - absorbed, kept,
			" (dry run)" if dry else ""])
	if dry or absorbed == 0:
		root.free()
		return
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		push_error("absorb_props: %s: %s" % [path, error_string(err)])
		return
	_restore_uids(path, before)


## Instances of palette scenes placed in this scene (not inside other instances).
func _collect(node: Node, root: Node, index: Dictionary, out: Array[Node]) -> void:
	for child in node.get_children():
		if child.owner != root:
			continue
		if index.has(child.scene_file_path):
			out.append(child)
		elif child.scene_file_path.is_empty():
			_collect(child, root, index, out)


## Why `node` cannot become paint, or "".
func _unsupported(node: Node) -> String:
	var fresh := _fresh_of(node.scene_file_path)
	var why := _differs(node, fresh, true)
	if not why.is_empty():
		return why
	for meta in node.get_meta_list():
		if not DROPPED_META.has(str(meta)) and not (fresh.has_meta(meta) and fresh.get_meta(meta) == node.get_meta(meta)):
			return "meta " + str(meta)
	var own_groups := node.get_groups().filter(func(g): return not str(g).begins_with("_"))
	var fresh_groups := fresh.get_groups().filter(func(g): return not str(g).begins_with("_"))
	if own_groups != fresh_groups:
		return "groups"
	if not _same_tree(node, fresh, node):
		return "children"
	if _wired_outside(node, node):
		return "connections"
	return ""


func _fresh_of(scene: String) -> Node:
	if not _fresh.has(scene):
		_fresh[scene] = (load(scene) as PackedScene).instantiate()
	return _fresh[scene]


## The first stored property of `node` that differs from `fresh` (allowed: the root's position, the
## Visual's size, mirror and offset), as "name: property", or "".
func _differs(node: Node, fresh: Node, is_root: bool) -> String:
	for property in node.get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_STORAGE):
			continue
		var name := str(property["name"])
		if name.begins_with("metadata/") or name == "script":
			continue
		if is_root and name == "position":
			continue
		if node.name == &"Visual" and VISUAL_OVERRIDES.has(name):
			continue
		if not _same_value(node.get(name), fresh.get(name)):
			return "%s: %s" % ["root" if is_root else str(node.name), name]
	return ""


static func _same_value(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Object:
		if a == b:
			return true
		if a is Resource and b is Resource:
			var ra := a as Resource
			var rb := b as Resource
			return (not ra.resource_path.is_empty() and ra.resource_path == rb.resource_path) \
					or (ra.get_class() == rb.get_class() and var_to_str(ra) == var_to_str(rb))
		return false
	return a == b


## True when `node`'s subtree matches `fresh`'s node for node, property for property.
func _same_tree(node: Node, fresh: Node, top: Node) -> bool:
	if node.get_child_count() != fresh.get_child_count():
		return false
	for i in node.get_child_count():
		var a := node.get_child(i)
		var b := fresh.get_child(i)
		if a.name != b.name or not _differs(a, b, false).is_empty() or not _same_tree(a, b, top):
			return false
	return true


## True when a signal in `node`'s subtree is wired to or from a node outside `top`.
func _wired_outside(node: Node, top: Node) -> bool:
	for signal_info in node.get_signal_list():
		for connection in node.get_signal_connection_list(signal_info["name"]):
			var target: Object = (connection["callable"] as Callable).get_object()
			if target is Node and not (top == target or top.is_ancestor_of(target)):
				return true
	for connection in node.get_incoming_connections():
		var source: Object = connection["signal"].get_object()
		if source is Node and not (top == source or top.is_ancestor_of(source)):
			return true
	for child in node.get_children():
		if _wired_outside(child, top):
			return true
	return false


## The world's prop layer `layer_name`, made after the forest (or ground) layer when missing.
func _layer(root: Node, layers: Dictionary, layer_name: String) -> TileMapLayer:
	if layers.has(layer_name):
		return layers[layer_name]
	var layer := root.get_node_or_null(NodePath(layer_name)) as TileMapLayer
	if layer == null:
		layer = TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = load(LAYERS[layer_name])
		layer.y_sort_enabled = true
		layer.set_script(Props)
		var after := 0
		for i in root.get_child_count():
			var child := root.get_child(i)
			if child is TileMapLayer and (child.name == &"ground" or child.get_script() != null):
				after = i + 1
		root.add_child(layer)
		root.move_child(layer, after)
		layer.owner = root
	layers[layer_name] = layer
	return layer


## Where `node` goes on `layer`: {cell, coords, flip} or {why}; with `exact`, only where the
## layer's grid holds it within a unit.
func _place(node: Node, layer: TileMapLayer, entry: Dictionary, exact: bool) -> Dictionary:
	var fresh := _fresh_of(node.scene_file_path)
	var foot := _to_root(node).origin
	var size := 1.0
	var flip := false
	var visual := node.get_node_or_null(^"Visual") as Node2D
	var fresh_visual := fresh.get_node_or_null(^"Visual") as Node2D
	if visual != null and fresh_visual != null:
		if &"offset" in visual:
			var delta: Vector2 = visual.get(&"offset") - fresh_visual.get(&"offset")
			foot += (_to_root(visual).basis_xform(delta))
		if absf(visual.scale.x - visual.scale.y) > 0.01 or fresh_visual.scale.x == 0.0:
			return {"why": "stretched"}
		size = visual.scale.x / fresh_visual.scale.x
		if &"flip_h" in visual:
			flip = bool(visual.get(&"flip_h")) != bool(fresh_visual.get(&"flip_h"))
	var best: Array = []
	for tile: Array in entry["tiles"]:
		if best.is_empty() or absf(float(tile[1]) - size) < absf(float(best[1]) - size):
			best = tile
	if absf(float(best[1]) - size) > SIZE_TOLERANCE:
		return {"why": "size %.2f" % size}
	var at := _to_root(layer).affine_inverse() * foot
	var tile_size := Vector2(entry["tile"])
	var cell := Vector2i(((at - Vector2(entry["anchor"])) / tile_size).round())
	if exact and at.distance_to(Vector2(cell) * tile_size + Vector2(entry["anchor"])) > 1.0:
		return {"why": "off the grid"}
	if layer.get_cell_source_id(cell) >= 0:
		return {"why": "cell taken"}
	return {"cell": cell, "coords": best[0], "flip": flip}


## `node`'s transform in its scene root's space (the scene is not in the tree).
func _to_root(node: Node) -> Transform2D:
	var transform := Transform2D.IDENTITY
	var at := node
	while at != null and at.get_parent() != null:
		if at is Node2D:
			transform = (at as Node2D).transform * transform
		at = at.get_parent()
	return transform


## Puts back the uids of the scene and of its external resources that a headless save drops.
func _restore_uids(path: String, before: String) -> void:
	var uids := {}
	var with_uid := RegEx.create_from_string("\\[ext_resource type=\"([^\"]+)\" uid=\"([^\"]+)\" path=\"([^\"]+)\" id=\"([^\"]+)\"\\]")
	for found in with_uid.search_all(before):
		uids[found.get_string(1) + "|" + found.get_string(3)] = found.get_string(2)
	var text := FileAccess.get_file_as_string(path)
	var bare := RegEx.create_from_string("\\[ext_resource type=\"([^\"]+)\" path=\"([^\"]+)\" id=\"([^\"]+)\"\\]")
	var matches := bare.search_all(text)
	for i in range(matches.size() - 1, -1, -1):
		var found := matches[i]
		var uid: Variant = uids.get(found.get_string(1) + "|" + found.get_string(2))
		if uid == null and found.get_string(2).ends_with(".gd") and FileAccess.file_exists(found.get_string(2) + ".uid"):
			uid = FileAccess.get_file_as_string(found.get_string(2) + ".uid").strip_edges()
		if uid != null:
			text = text.substr(0, found.get_start()) + "[ext_resource type=\"%s\" uid=\"%s\" path=\"%s\" id=\"%s\"]" % [
					found.get_string(1), uid, found.get_string(2), found.get_string(3)] + text.substr(found.get_end())
	var own := RegEx.create_from_string("^\\[gd_scene [^\\]]*uid=\"([^\"]+)\"").search(before)
	var header := text.get_slice("\n", 0)
	if own != null and header.begins_with("[gd_scene") and header.find("uid=") < 0:
		text = header.trim_suffix("]") + " uid=\"%s\"]" % own.get_string(1) + text.substr(header.length())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
