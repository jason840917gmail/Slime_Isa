@tool
extends ItemList
## The Scenery dock's pictures: dragging one hands the 2D view the prop's scene file, the way the
## FileSystem dock does, so Godot shows the prop under the mouse and places it as a node where it is
## dropped (the plugin then moves it under the world's Scenery node at the dock's size).

## The dock (scenery_dock.gd), whose prepare_drop readies the plugin for the drop.
var dock: Control


func _get_drag_data(at_position: Vector2) -> Variant:
	var index := get_item_at_position(at_position, true)
	if index < 0:
		return null
	var scene := str(get_item_metadata(index))
	if dock != null:
		var prepare: Callable = dock.get(&"prepare_drop")
		if prepare.is_valid() and not bool(prepare.call(scene, float(dock.call(&"drop_size")))):
			return null
	# no picture of our own follows the mouse: over the 2D view Godot shows the prop itself
	return {"type": "files", "files": [scene], "from": self}
