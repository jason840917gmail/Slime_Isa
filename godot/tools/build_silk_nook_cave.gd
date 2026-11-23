extends SceneTree
## Builds the silk nook's cave (Gloop Forest's River Roads, 2026-11-21, the owner: the silk nook's heart
## quarter lies in a chest in a cave room under a cracked ground the Goo Bomb opens, in F4's silk nook
## clearing; docs/design/2026-11-21-gloop-river-roads.md "The silk nook's cave"): a small cave room
## world, `world.silk-nook-cave`, made from the Gloop Cavern's room (its cave floor, its interior walls,
## its ladder, its music), 18 x 16 cells (no smaller than the game's 1024-unit view, as the Fatty's Lair
## bolt hole: a smaller world is pinned to the screen's top-left corner), with the heart quarter's chest
## in the middle and spider silk dressing. Its ladder climbs back to F4's crack (door `silk-nook-crack`).
##
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_silk_nook_cave.gd [-- --force]
##
## Writes res://game/scenes/worlds/rooms/gloop-forest-f4/silk-nook-cave.tscn once; an existing room is
## left alone (it is the scene to edit by hand) unless `--force`.

const SceneSave := preload("res://tools/lib/scene_save.gd")

const SOURCE := "res://game/scenes/worlds/rooms/gloop-forest-e5/gloop-cavern.tscn"
const OUT := "res://game/scenes/worlds/rooms/gloop-forest-f4/silk-nook-cave.tscn"
const MAP_ID := "silk-nook-cave"
const COLUMNS := 18
const ROWS := 16
const CELL := 64
const SHEET := 19
## The cave floor (terrain_tileset.tres) and its rougher patches; the interior walls' cave frame.
const FLOOR_SOURCE := 1
const ROUGH_SOURCE := 2
const WALL_TILE := Vector2i(5, 0)
## The crystal floor trim (interior_trim_tileset.tres: crystal studs, crystal blue), along the walls but
## not under the ladder (scripts/maps/paint-crystal-trim.py paints the other crystal rooms the same way).
const TRIM_TILE := Vector2i(10, 12)
const LADDER_HALF := 56.0
const LADDER_AT := Vector2(576, 200)
const SPAWN_AT := Vector2(576, 260)
const CHEST_AT := Vector2(576, 600)
const HEART_ID := "gloop-silk-nook"
const OBJECTS := "res://game/scenes/objects/"
## Spider silk dressing: [scene, position].
const DRESSING := [
	["decoration-world-ambient--web-cocoon-hanging-01.tscn", Vector2(200, 200)],
	["decoration-world-ambient--web-cocoon-hanging-03.tscn", Vector2(950, 196)],
	["decoration-world-ambient--web-cocoon-hanging-02.tscn", Vector2(420, 190)],
	["decoration-world-ambient--web-ground-01.tscn", Vector2(236, 840)],
	["decoration-world-ambient--web-egg-sacs-01.tscn", Vector2(930, 850)],
	["decoration-world-ambient--web-egg-sacs-02.tscn", Vector2(250, 470)],
	["decoration-world-ambient--web-ground-02.tscn", Vector2(820, 420)],
	["decoration-world-ambient--web-cocoon-ground-01.tscn", Vector2(900, 620)],
	["decoration-world-ambient--web-cocoon-ground-02.tscn", Vector2(330, 700)],
]


func _initialize() -> void:
	var force := "--force" in OS.get_cmdline_user_args()
	if ResourceLoader.exists(OUT) and not force:
		print("silk nook cave: %s exists; not overwritten (add -- --force)" % OUT)
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var root := (load(SOURCE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as Node2D
	root.name = MAP_ID
	_ground(root.get_node("ground") as TileMapLayer)
	_walls(root.get_node("interior-walls") as TileMapLayer)
	_trim(root.get_node_or_null("floor-trim") as TileMapLayer)
	var definition := root.get_node("world-definition")
	definition.set(&"map_id", MAP_ID)
	definition.set(&"columns", COLUMNS)
	definition.set(&"rows", ROWS)
	definition.set(&"metadata", {"objects": [], "player": {"entries": {}, "spawn": {"x": int(SPAWN_AT.x), "y": int(SPAWN_AT.y)}}})
	(root.get_node("player-spawn") as Node2D).position = SPAWN_AT
	var cave := root.get_node("cave")
	for gone: String in ["shard-1", "shard-2", "shard-3", "goo-heart"]:
		var node := cave.get_node_or_null(gone)
		if node != null:
			cave.remove_child(node)
			node.free()
	var ladder := cave.get_node("ladder") as Node2D
	ladder.position = LADDER_AT
	_ids(ladder, "silk-nook-cave-ladder")
	var door := ladder.get_node("DoorScript")
	door.set(&"map_id", MAP_ID)
	door.set(&"door_id", "silk-nook-cave-ladder")
	door.set(&"target_area_id", "gloop-forest")
	door.set(&"target_door_id", "silk-nook-crack")
	var chest := cave.get_node("hidden-chest") as Node2D
	chest.name = "heart-chest"
	chest.position = CHEST_AT
	_ids(chest, "silk-nook-cave-heart-chest")
	var script_node := chest.get_node("ChestScript")
	script_node.set(&"map_id", MAP_ID)
	script_node.set(&"instance_id", "silk-nook-cave-heart-chest")
	script_node.set(&"initial_contents", {})
	script_node.set(&"goo_heart_id", HEART_ID)
	for entry: Array in DRESSING:
		if not ResourceLoader.exists(OBJECTS + entry[0]):
			continue
		var decor := (load(OBJECTS + entry[0]) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		decor.name = String(entry[0]).trim_prefix("decoration-world-ambient--").trim_suffix(".tscn")
		decor.position = entry[1]
		cave.add_child(decor)
		decor.owner = root
	var err := SceneSave.save(root, OUT, "")
	print("silk nook cave: ", OUT, " ", error_string(err))
	root.free()
	quit(0 if err == OK else 1)


func _ids(node: Node, id: String) -> void:
	node.set_meta(&"instance_id", id)
	node.set_meta(&"persistence_key", MAP_ID + "." + id)


func _ground(ground: TileMapLayer) -> void:
	ground.clear()
	for y in ROWS:
		for x in COLUMNS:
			# rough patches scattered by a fixed hash, as the Gloop Cavern's floor
			var rough := ((x * 7 + y * 13) % 11) == 0
			ground.set_cell(Vector2i(x, y), ROUGH_SOURCE if rough else FLOOR_SOURCE, Vector2i(x % SHEET, y % SHEET))
	ground.set_meta(&"columns", COLUMNS)
	ground.set_meta(&"rows", ROWS)
	ground.set_meta(&"source_cell_count", COLUMNS * ROWS)


## The crystal trim on the floor cells beside the frame, none under the ladder.
func _trim(trim: TileMapLayer) -> void:
	if trim == null:
		return
	trim.clear()
	for y in range(2, ROWS - 2):
		for x in range(2, COLUMNS - 2):
			if x > 2 and y > 2 and x < COLUMNS - 3 and y < ROWS - 3:
				continue
			if y == 2 and absf((x + 0.5) * CELL - LADDER_AT.x) < LADDER_HALF:
				continue
			trim.set_cell(Vector2i(x, y), 0, TRIM_TILE)


## The cave's frame: the interior walls two cells deep all round (they join by themselves).
func _walls(walls: TileMapLayer) -> void:
	walls.clear()
	for y in ROWS:
		for x in COLUMNS:
			if x < 2 or y < 2 or x >= COLUMNS - 2 or y >= ROWS - 2:
				walls.set_cell(Vector2i(x, y), 0, WALL_TILE)
