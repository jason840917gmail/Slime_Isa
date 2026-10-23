extends SceneTree
## Builds only the furnished storehouse interior. The exterior is an authored prefab in C4.
## Rebuilding replaces the interior; reload it in an open editor before saving.
const SceneSave := preload("res://tools/lib/scene_save.gd")
const OBJ := "res://game/scenes/objects/%s.tscn"
const INTERIOR := "res://game/scenes/worlds/rooms/c4/watchkeeper-hideout.tscn"
const MUSIC := "res://asset/audio/music/interior-b.wav"
var _root: Node2D

func _initialize() -> void:
	# Reuse the timber room's floor, structural perimeter, exit facade, ambience and music player.
	_root = (load("res://game/scenes/worlds/rooms/gloop-forest-e4/gloop-hut.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	_root.name = "watchkeeper-hideout"
	for child: Node in _root.get_children():
		if str(child.name) not in ["ground", "old-props", "cell-props", "details", "world-definition", "player-spawn", "player-entry-south", "house-door", "house-door-art", "Ambience", "MusicPlayer"]:
			_root.remove_child(child)
			child.free()
	# The storehouse plays the second interior track (the hut plays interior-a).
	_root.get_node("MusicPlayer").set(&"stream", load(MUSIC))
	var props := _root.get_node("old-props") as TileMapLayer
	for cell: Vector2i in props.get_used_cells():
		if cell.y != 19 and cell.y != 88 and cell.x != 3 and cell.x != 109:
			props.erase_cell(cell)
	for name: String in ["cell-props", "details"]:
		(_root.get_node(name) as TileMapLayer).clear()
	_root.get_node("world-definition").set(&"map_id", "watchkeeper-hideout")
	var door := _root.get_node("house-door/door-script")
	door.set(&"map_id", "watchkeeper-hideout")
	door.set(&"target_area_id", "level-1")
	door.set(&"target_door_id", "watchkeeper-hideout-door")
	# The coffer keeps its original outside-world record, including already-opened saves.
	var chest := _thing("chest-wooden", "keeper-coffer", Vector2(224, 328))
	var chest_script := chest.get_node("ChestScript")
	chest_script.set(&"map_id", "level-1-c4")
	chest_script.set(&"instance_id", "level-1-c4-watch-post-chest")
	chest_script.set(&"initial_contents", {"coins": 20, "hp-potion": 1})
	_root.set_editable_instance(chest, true)
	_thing("interiors/storage/interior-storage-shelf-empty-n", "keeper-shelf", Vector2(704, 312))
	_thing("interiors/storage/interior-storage-barrel", "water-barrel", Vector2(744, 438))
	_thing("interiors/storage/interior-storage-crate", "stored-crate", Vector2(660, 448))
	_thing("interiors/storage/interior-storage-sacks-bundled", "grain-sacks", Vector2(164, 444))
	_thing("interiors/tables/interior-tables-desk-with-chair-n", "keeper-desk", Vector2(448, 352))
	_thing("interiors/decor/interior-decor-rug-green-large", "faded-rug", Vector2(448, 528))
	for spec: Array in [["pot-west", Vector2(166, 568), "coins"], ["pot-west-small", Vector2(230, 598), "heart"],
		["pot-east", Vector2(700, 566), "energy"], ["pot-east-small", Vector2(762, 592), "random"]]:
		var pot := _thing("dungeon/dungeon-pot", str(spec[0]), spec[1])
		pot.get_node("PotLoot").set(&"loot", str(spec[2]))
		_root.set_editable_instance(pot, true)
	var before := FileAccess.get_file_as_string(INTERIOR) if FileAccess.file_exists(INTERIOR) else ""
	var err := SceneSave.save(_root, INTERIOR, before)
	print("watchkeeper interior: ", error_string(err))
	_root.free()
	quit(0 if err == OK else 1)

func _thing(id: String, node_name: String, at: Vector2) -> Node2D:
	var node := (load(OBJ % id) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	node.name = node_name
	node.position = at
	_root.add_child(node)
	node.owner = _root
	return node
