extends RefCounted
## Finds a world's layers and the overlays the code adds by what they are, never by their node name:
## a node's name is typed by hand in the editor (a room's paint layer is named "Elevation", another's
## collision layer "LevelCollisionLayer"; docs/godot/CONVENTIONS.md).
##
## Owner: shared.


## The first child of `parent` that is an instance of `script` (or of a script extending it), or null.
static func child_of(parent: Node, script: Script) -> Node:
	if parent == null:
		return null
	for child: Node in parent.get_children():
		if is_instance_of(child, script):
			return child
	return null


## The first TileMapLayer child of `parent` painted with the tile set saved at `tile_set_path`, or null.
static func layer_with_tile_set(parent: Node, tile_set_path: String) -> TileMapLayer:
	if parent == null:
		return null
	for child: Node in parent.get_children():
		var layer := child as TileMapLayer
		if layer != null and layer.tile_set != null and layer.tile_set.resource_path == tile_set_path:
			return layer
	return null


## The first TileMapLayer child of `parent` whose tile set has the custom data layer `data_layer`, or
## null.
static func layer_with_data(parent: Node, data_layer: String) -> TileMapLayer:
	if parent == null:
		return null
	for child: Node in parent.get_children():
		var layer := child as TileMapLayer
		if layer != null and layer.tile_set != null and layer.tile_set.has_custom_data_layer_by_name(data_layer):
			return layer
	return null
