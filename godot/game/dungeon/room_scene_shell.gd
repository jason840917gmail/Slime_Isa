@tool
extends Node2D
## The dungeon shell assembles separately editable room scenes before any gameplay node is ready.
## Authoring keeps the scene instances; runtime restores the stable paths used by shared puzzles.
## A room instance's `position` is its offset in the dungeon (a whole number of cells; zero for a
## room written in dungeon coordinates): its tile cells and its nodes are moved by it as they join
## the shell's layers and holders (docs/godot/DUNGEON_ROOMS.md).
@export var room_connections: Array[Dictionary] = []

func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED and not Engine.is_editor_hint():
		assemble()

func assemble() -> void:
	var rooms := get_node_or_null("RoomScenes")
	if rooms == null:
		return
	for room: Node in rooms.get_children():
		var offset := (room as Node2D).position if room is Node2D else Vector2.ZERO
		for content: Node in room.get_children():
			var destination := get_node_or_null(NodePath(content.name))
			if content is TileMapLayer and destination is TileMapLayer:
				var source := content as TileMapLayer
				var target := destination as TileMapLayer
				var shift := Vector2i((offset / Vector2(target.tile_set.tile_size)).round())
				var origins: Variant = target.get(&"cell_rooms")
				for cell: Vector2i in source.get_used_cells():
					target.set_cell(cell + shift, source.get_cell_source_id(cell), source.get_cell_atlas_coords(cell), source.get_cell_alternative_tile(cell))
					# interior walls remember the room that painted each cell: it faces that room only
					if origins is Dictionary:
						(origins as Dictionary)[cell + shift] = String(room.name)
			elif destination != null:
				for child: Node in content.get_children():
					_detach_owner(child, room)
					child.reparent(destination, false)
					if child is Node2D:
						(child as Node2D).position += offset
					_own(child, room)
			else:
				_detach_owner(content, room)
				content.reparent(self, false)
				if content is Node2D:
					(content as Node2D).position += offset
				_own(content, room)
	remove_child(rooms)
	rooms.free()
	for link: Dictionary in room_connections:
		var source := get_node_or_null(NodePath(str(link["source"])))
		var target := get_node_or_null(NodePath(str(link["target"])))
		if source == null or target == null:
			push_error("Dungeon room connection is missing: %s" % link)
			continue
		var callback := Callable(target, StringName(str(link["method"])))
		var binds: Array = link.get("binds", [])
		if not binds.is_empty():
			callback = callback.bindv(binds)
		var signal_name := StringName(str(link["signal"]))
		if not source.is_connected(signal_name, callback):
			source.connect(signal_name, callback, int(link["flags"]))

func _own(node: Node, previous_owner: Node) -> void:
	if node.owner == previous_owner or node.owner == null:
		node.owner = self
	for child: Node in node.get_children():
		_own(child, previous_owner)


func _detach_owner(node: Node, previous: Node) -> void:
	if node.owner == previous:
		node.owner = null
	for child: Node in node.get_children():
		_detach_owner(child, previous)
