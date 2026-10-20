@tool
extends ItemList
## The Scenery dock's pictures: dragging one hands the 2D view the prop's scene file, the way the
## FileSystem dock does, so Godot shows the prop under the mouse and places it as a node where it is
## dropped (the plugin then moves it under the world's Scenery node at the dock's size). An enemy's
## picture hands the placed enemy scene and its type (the plugin sets the type and moves it under
## the world's Enemies node); a suckable's, the liftable scene and its kind (set by the plugin, the
## node under Scenery).

## The dock (scenery_dock.gd), whose prepare_drop readies the plugin for the drop.
var dock: Control


func _get_drag_data(at_position: Vector2) -> Variant:
	var index := get_item_at_position(at_position, true)
	if index < 0:
		return null
	var metadata: Variant = get_item_metadata(index)
	var scene := str((metadata as Dictionary).get("scene", "")) if metadata is Dictionary else str(metadata)
	var settings: Dictionary = (metadata as Dictionary).get("settings", {}) if metadata is Dictionary else {}
	var container := str((metadata as Dictionary).get("container", "")) if metadata is Dictionary else ""
	if dock != null:
		var prepare: Callable = dock.get(&"prepare_drop")
		if prepare.is_valid() and not bool(prepare.call(scene, float(dock.call(&"drop_size")), settings, container)):
			return null
	# no picture of our own follows the mouse: over the 2D view Godot shows the prop itself
	return {"type": "files", "files": [scene], "from": self}
