extends RefCounted
## The objects a painted layer keeps in its painted cells: the interior walls' doors
## (interior_wall_layer.gd `sync_doors`) and the fences' divider gates (fence_layer.gd `sync_gates`).
## This decides what such a layer may take away by itself (docs/godot/INTERIOR_WALLS.md "Painting a
## room", docs/godot/FENCES.md "Dungeon dividers").
##
## A layer that makes an object remembers its settings as made (`remember`). When the object's cells
## stop holding it, `retire` removes it only if the layer made it and nobody has changed it since.
## An object placed by hand (adopted), or one whose settings were changed in the Inspector, stays:
## the layer's tags come off, a warning names it, and the layer adopts it again, settings and all,
## when its cells are painted back. So a stroke through a half-painted block, an erased cell undone
## with Ctrl+Z, or a moved camera room never costs a door its records. The layers free outside the
## editor's undo, which is why they never free what the designer set up.
##
## Owner: world.

## The settings of an object as the layer made it (`state`).
const MADE_META := &"painted_object_made"


## Remembers `node`'s settings as the layer made (or last placed) them.
static func remember(node: Node) -> void:
	node.set_meta(MADE_META, state(node))


## True when the layer made `node` and nothing of it has changed since.
static func is_untouched(node: Node) -> bool:
	return node.has_meta(MADE_META) and str(node.get_meta(MADE_META)) == state(node)


## `node`'s cells no longer hold it. It is freed if untouched (`is_untouched`); otherwise its `tags`
## (the layer's metas) come off and a warning from `layer_name` names it. True when it was freed.
static func retire(node: Node, tags: Array[StringName], layer_name: String) -> bool:
	if is_untouched(node):
		node.free()
		return true
	for tag: StringName in tags:
		if node.has_meta(tag):
			node.remove_meta(tag)
	if node.has_meta(MADE_META):
		node.remove_meta(MADE_META)
	push_warning("%s: '%s' no longer stands in its painted cells; it is kept for its settings (paint its cells back to keep it, or delete it by hand)"
			% [layer_name, node.name])
	return false


## `node`'s exported settings, its own and those of the nodes of its scene, and its position, as text.
static func state(node: Node) -> String:
	var values := {}
	_collect(node, node, values)
	if node is Node2D:
		values["position"] = (node as Node2D).position
	return var_to_str(values)


static func _collect(root: Node, node: Node, values: Dictionary) -> void:
	var prefix := str(root.get_path_to(node)) if node != root else "."
	for property: Dictionary in node.get_property_list():
		var usage := int(property["usage"])
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		var value: Variant = node.get(property["name"])
		if value is Node:
			value = str(node.get_path_to(value))
		elif value is Resource:
			value = (value as Resource).resource_path
		elif value is Object:
			value = null
		values["%s:%s" % [prefix, property["name"]]] = value
	# only the object's own scene: what its scripts build at run time is not a setting
	for child: Node in node.get_children():
		if child.owner == root:
			_collect(root, child, values)
