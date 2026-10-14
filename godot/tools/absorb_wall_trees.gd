extends SceneTree
## Turns groups of placed wall trees in a world scene into painted cells of its forest layer, as the
## layer's "Absorb trees" button does (docs/godot/FORESTS.md), without opening the editor: each
## group's wall trees become cells of the given mix and are removed; a group left empty goes too.
## Close or reload the scene in the editor afterwards (it holds its own copy).
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/absorb_wall_trees.gd -- \
##         --scene=res://game/scenes/worlds/chunks/level-1-c4.tscn "--groups=Forest Border:0,Fatty Maze:17"
## A group is a node path from the scene's root; the number is the mix's column in the palette's
## top row (0 mixed, 17 forest medium...).

const FOREST_LAYER := "res://game/world/forest/forest_layer.gd"


func _initialize() -> void:
	var scene_path := ""
	var groups := {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--groups="):
			for part in arg.trim_prefix("--groups=").split(","):
				var pieces := part.rsplit(":", true, 1)
				groups[pieces[0]] = int(pieces[1])
	var packed := load(scene_path) as PackedScene
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	var layer := _forest_layer(root)
	if layer == null:
		push_error("absorb_wall_trees: %s has no forest layer" % scene_path)
		quit(1)
		return
	var to_layer := _to_root(layer).affine_inverse()
	var foot_of := func(tree: Node2D) -> Vector2: return to_layer * _to_root(tree).origin
	var total := 0
	for group_path: String in groups:
		var group := root.get_node_or_null(NodePath(group_path))
		if group == null:
			push_warning("absorb_wall_trees: no group '%s'" % group_path)
			continue
		layer.set(&"absorb_into_mix", groups[group_path])
		var plan: Dictionary = layer.call(&"absorb_plan", group, foot_of)
		for cell: Vector2i in plan["cells"]:
			layer.set_cell(cell, 0, plan["cells"][cell])
		for node: Node in plan["nodes"]:
			node.get_parent().remove_child(node)
			node.free()
		total += (plan["nodes"] as Array).size()
		print("%s: %d trees into %d cells (mix %d); %d other children kept" % [group_path,
				(plan["nodes"] as Array).size(), (plan["cells"] as Dictionary).size(), groups[group_path],
				(plan["skipped"] as PackedStringArray).size()])
		if group.get_child_count() == 0 and group != root:
			group.get_parent().remove_child(group)
			group.free()
			print("  %s was left empty and is removed" % group_path)
	layer.set(&"absorb_into_mix", -1)
	layer.set(&"absorb_from", NodePath())
	var out := PackedScene.new()
	var err := out.pack(root)
	if err == OK:
		err = ResourceSaver.save(out, scene_path)
	root.free()
	print("absorbed %d trees; saved %s (%s)" % [total, scene_path, error_string(err)])
	quit(0 if err == OK else 1)


func _forest_layer(root: Node) -> TileMapLayer:
	for node in root.find_children("*", "TileMapLayer", true, false):
		if node.get_script() != null and (node.get_script() as Script).resource_path == FOREST_LAYER:
			return node as TileMapLayer
	return null


## `node`'s transform in its scene root's space (the scene is not in the tree, so no globals).
func _to_root(node: Node) -> Transform2D:
	var transform := Transform2D.IDENTITY
	var at := node
	while at != null and at.get_parent() != null:
		if at is Node2D:
			transform = (at as Node2D).transform * transform
		at = at.get_parent()
	return transform
