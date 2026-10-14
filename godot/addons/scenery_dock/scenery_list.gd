@tool
extends ItemList
## The Scenery dock's pictures: dragging one hands the 2D view the prop's scene file, the way the
## FileSystem dock does, so Godot places it as a node where it is dropped (under the node the dock
## selects first: the world's Scenery node).

## The dock (scenery_dock.gd), whose prepare_drop selects that node.
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
	var preview := TextureRect.new()
	preview.texture = get_item_icon(index)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(fixed_icon_size)
	preview.modulate.a = 0.8
	set_drag_preview(preview)
	return {"type": "files", "files": [scene], "from": self}
