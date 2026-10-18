extends SceneTree
## Rebuild separately editable room scenes from each dungeon's assembled world.
const Splitter := preload("res://tools/lib/dungeon_room_splitter.gd")
func _initialize() -> void:
	var splitter := Splitter.new()
	var failed := false
	for id: String in Splitter.WORLDS:
		if splitter.split(id) != OK:
			failed = true
	quit(1 if failed else 0)
