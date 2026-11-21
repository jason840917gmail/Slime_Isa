extends SceneTree
## Lays the Crystal Caverns' cave rooms (the Spiral's caves: roadmap 12.9; the plan
## docs/design/2026-11-20-caverns-spiral.md "The caves"), ONE room world a run:
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_caverns_rooms.gd -- --room=smith-cave [--dry]
## Rooms: smith-cave, corner-cave, bay-cave, dark-nook, under-line-tunnel. Each is its own world
## (`crystal-caverns-<room>`, game/scenes/worlds/rooms/crystal-caverns-<chunk>/<room>.tscn): a
## two-cell crystal-cave rim (INTERIOR_WALLS.md "Crystal cave") round a cavern floor, its doorways
## cut into the south rim, each with a door node to its cave mouth outside (the chunk world it stands
## in and the mouth's door id, as the mine's doors do: tools/build_caverns_spiral.gd lays the
## mouths), and what stands inside. A room
## laid once is the scene to edit by hand; running the tool again for it lays it afresh.
##
## Owner: world (the Crystal Caverns).

const ROOMS := "res://game/scenes/worlds/rooms/"
const CELL := 64
const SHEET := 19
const CAVERN := 1
const STYLE_COLUMN := 5
const WALL := Vector2i(STYLE_COLUMN, 0)
const DOORWAY := Vector2i(STYLE_COLUMN, 1)
const REGION := "crystal-caverns"
const G4 := "crystal-caverns-g4"
const H4 := "crystal-caverns-h4"
const H5 := "crystal-caverns-h5"

const TERRAIN := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const INTERIOR_TILES := "res://game/world/interior/interior_wall_tileset.tres"
const INTERIOR_LAYER := "res://game/world/interior/interior_wall_layer.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const DOOR := "res://game/scripts/door.gd"
const DARK_ROOM := "res://game/world/darkness/dark_room.gd"
const SFX_PLAYER := "res://game/runtime/sfx_player.gd"
const MUSIC := "res://asset/audio/music/cave-a.wav"
const RAILS := "res://game/crystal_mine/mine_rails.gd"
const MINE_CAMP := "res://game/crystal_mine/mine_camp.gd"
const SMITH_CART := "res://game/crystal_mine/smith_cart.gd"

const OBJECTS := "res://game/scenes/objects/"
const DUNGEON := "res://game/scenes/objects/dungeon/"
const WORKSHOP := "res://game/scenes/objects/interiors/workshop/"
const STORAGE := "res://game/scenes/objects/interiors/storage/"
const BEDS := "res://game/scenes/objects/interiors/beds/"
const CLUSTER := "res://game/scenes/objects/crystal-cluster-wall--%02d.tscn"
const PLACED_ENEMY := "res://game/scenes/encounters/placed-enemy.tscn"
const SMITH := "res://game/scenes/characters/smith.tscn"

## room -> [chunk folder, columns, rows, dark]
const PLANS := {
	"smith-cave": ["crystal-caverns-h5", 24, 15, false],
	"corner-cave": ["crystal-caverns-h4", 18, 12, false],
	"bay-cave": ["crystal-caverns-h5", 22, 10, false],
	"dark-nook": ["crystal-caverns-g4", 14, 10, true],
	"under-line-tunnel": ["crystal-caverns-h4", 26, 9, true],
}

var _dry := false
var _room := ""
var _map_id := ""
var _root: Node2D
var _objects: Node2D
var _enemies: Node2D
var _columns := 0
var _rows := 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--dry":
			_dry = true
		elif arg.begins_with("--room="):
			_room = arg.trim_prefix("--room=")
	if not PLANS.has(_room):
		push_error("build_caverns_rooms: give one room, --room=" + "|".join(PLANS.keys()))
		quit(1)
		return
	quit(0 if _build() == OK else 1)


func _build() -> Error:
	var plan: Array = PLANS[_room]
	_map_id = "%s-%s" % [REGION, _room]
	_columns = int(plan[1])
	_rows = int(plan[2])
	_root = Node2D.new()
	_root.name = _map_id
	_root.y_sort_enabled = true
	_ground()
	_walls()
	_definition()
	_objects = _group("Objects")
	_enemies = _group("Enemies")
	match _room:
		"smith-cave":
			_smith_cave()
		"corner-cave":
			_corner_cave()
		"bay-cave":
			_bay_cave()
		"dark-nook":
			_dark_nook()
		"under-line-tunnel":
			_under_line_tunnel()
	if bool(plan[3]):
		var dark := Node2D.new()
		dark.name = "DarkRoom"
		dark.set_script(load(DARK_ROOM))
		dark.position = Vector2(-48, -48)
		dark.set(&"size", Vector2(_columns * CELL + 96, _rows * CELL + 96))
		var candles: Array[NodePath] = []
		for node: Node in _objects.get_children():
			if String(node.name).begins_with("brazier"):
				candles.append(dark.get_path_to(node) if dark.is_inside_tree() else NodePath("../Objects/" + String(node.name)))
		dark.set(&"candles", candles)
		dark.set(&"lit_for_good_when_all_lit", true)
		dark.set(&"lit_flag", _map_id + ".lit")
		_own(dark, _root)
	_music()
	var path := ROOMS + "%s/%s.tscn" % [plan[0], _room]
	if _dry:
		print("caverns rooms: %s (dry)" % path)
		_root.free()
		return OK
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOMS + str(plan[0])))
	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("caverns rooms: ", path, " ", error_string(err))
	_root.free()
	return err


# --- the room's shell -----------------------------------------------------------------------------

func _ground() -> void:
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN)
	ground.set_script(load(WORLD_GROUND))
	for y in _rows:
		for x in _columns:
			ground.set_cell(Vector2i(x, y), CAVERN, Vector2i(x % SHEET, y % SHEET))
	ground.set_meta(&"tile_seed", 20261121)
	ground.set_meta(&"columns", _columns)
	ground.set_meta(&"rows", _rows)
	_own(ground, _root)


## The room's `interior-walls` layer (its rim painted by `_rim`).
func _walls() -> void:
	var layer := TileMapLayer.new()
	layer.name = "interior-walls"
	layer.tile_set = load(INTERIOR_TILES)
	layer.set_script(load(INTERIOR_LAYER))
	layer.set(&"draw_floor", false)
	_own(layer, _root)


## The two-cell rim, the doorway blocks (each: its first column, in the south rim) cut into it.
func _rim(doorways: Array[int]) -> void:
	var layer := _root.get_node("interior-walls") as TileMapLayer
	for y in _rows:
		for x in _columns:
			if x < 2 or y < 2 or x >= _columns - 2 or y >= _rows - 2:
				layer.set_cell(Vector2i(x, y), 0, WALL)
	for column: int in doorways:
		for y in [_rows - 2, _rows - 1]:
			for x in [column, column + 1]:
				layer.set_cell(Vector2i(x, y), 0, DOORWAY)


func _definition() -> void:
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	definition.set(&"map_id", _map_id)
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", _columns)
	definition.set(&"rows", _rows)
	_own(definition, _root)
	var spawn := Node2D.new()
	spawn.name = "player-spawn"
	spawn.y_sort_enabled = true
	_own(spawn, _root)


func _spawn(at: Vector2) -> void:
	(_root.get_node("player-spawn") as Node2D).position = _t(at)
	var definition := _root.get_node("world-definition")
	definition.set(&"metadata", {"objects": [], "player": {"entries": {}, "spawn": {"x": int(at.x * CELL), "y": int(at.y * CELL)}}})


func _group(group_name: String) -> Node2D:
	var node := Node2D.new()
	node.name = group_name
	node.y_sort_enabled = true
	_own(node, _root)
	return node


func _music() -> void:
	var player := AudioStreamPlayer.new()
	player.name = "MusicPlayer"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = load(MUSIC)
	player.volume_db = -6.0206
	player.bus = &"Music"
	player.set_script(load(SFX_PLAYER))
	player.set(&"loop", true)
	player.set(&"autoplay_cue", true)
	_own(player, _root)


## A way out through the south doorway whose block starts at `column`: a door on the floor line, in
## the middle of the passage, to `target_door` in chunk world `chunk` outside.
func _south_door(door_id: String, column: int, chunk: String, target_door: String) -> void:
	var end := Node2D.new()
	end.name = door_id
	end.position = Vector2((column + 1) * CELL, (_rows - 2) * CELL)
	_own(end, _objects)
	var door := Node.new()
	door.name = "DoorScript"
	door.set_script(load(DOOR))
	door.set(&"map_id", _map_id)
	door.set(&"door_id", door_id)
	door.set(&"target_area_id", chunk)
	door.set(&"target_door_id", target_door)
	door.set(&"side", "south")
	door.set(&"trigger_rect", Rect2(-64, -24, 128, 48))
	_own(door, end)


# --- the rooms (cells; the floor is inside the two-cell rim) -------------------------------------

## The smith's camp (roadmap 12.3, 12.9): tents, fire, cot, anvil; his lamp and his cart.
func _smith_cave() -> void:
	_rim([11])
	_south_door("smith-cave-door", 11, H5, "smith-cave-door")
	_spawn(Vector2(12, 11.4))
	_scene(OBJECTS + "decoration-world-solid--canvas-tent.tscn", "tent", Vector2(4.6, 4.8), _objects)
	_scene(OBJECTS + "decoration-world-solid--canvas-tent.tscn", "tent", Vector2(8.6, 4.2), _objects)
	_scene(OBJECTS + "decoration-world-solid--campfire.tscn", "campfire", Vector2(6.6, 8.4), _objects)
	_scene(OBJECTS + "decoration-world-solid--cooking-cauldron.tscn", "cauldron", Vector2(8.4, 9.1), _objects)
	_scene(BEDS + "interior-beds-straw-nest-s.tscn", "smith-cot", Vector2(3.6, 10.6), _objects)
	_scene(OBJECTS + "decoration-world-solid--wood-table.tscn", "table", Vector2(10.4, 10.6), _objects)
	_scene(OBJECTS + "decoration-world-solid--anvil.tscn", "smith-anvil", Vector2(12.2, 6.6), _objects)
	_prop(WORKSHOP + "interior-workshop-quench-tub.tscn", "quench-tub", Vector2(15.3, 6.2), 0.9)
	_prop(WORKSHOP + "interior-workshop-hammer-rack.tscn", "hammer-rack", Vector2(16.6, 5.4), 0.9)
	_prop(WORKSHOP + "interior-workshop-bellows.tscn", "bellows", Vector2(14.2, 5.4), 0.85)
	_prop(WORKSHOP + "interior-workshop-ore-basket.tscn", "ore-basket", Vector2(19.8, 9.8), 0.9)
	_prop(STORAGE + "interior-storage-crate.tscn", "crate", Vector2(2.9, 3.2), 1.0)
	_prop(STORAGE + "interior-storage-crate-banded.tscn", "crate", Vector2(20.6, 11.2), 0.9)
	var smith := _scene(SMITH, "smith", Vector2(13.6, 6.9), _objects)
	smith.set(&"start_facing", -1.0)
	# His lamp beside the cart: the Lantern's first lock (lit for good: its flag frees the cart).
	var lamp := _scene(OBJECTS + "brazier.tscn", "smith-cave-lamp", Vector2(17.6, 4.6), _objects)
	lamp.set(&"burn_ms", 0.0)
	lamp.set_meta(&"instance_id", "smith-cave-lamp")
	# The cart at the end of its line, rails running into the tunnel in the north-east corner.
	var rails := Node2D.new()
	rails.name = "rails"
	rails.set_script(load(RAILS))
	rails.position = _t(Vector2(19.6, 6.0))
	rails.set(&"points", PackedVector2Array([Vector2.ZERO, Vector2(0, -150), Vector2(90, -250)]))
	_own(rails, _objects)
	var cart := _scene(OBJECTS + "mine-cart.tscn", "smith-cart", Vector2(19.6, 5.2), _objects)
	cart.set_script(load(SMITH_CART))
	cart.set(&"line_id", "smith-cart")
	cart.set(&"station_id", "smith")
	cart.set(&"empty_text", "The cart went down the line to the gate.")
	cart.set(&"target_area_id", G4)
	cart.set(&"target_door_id", "yard-cart")
	var camp := Node.new()
	camp.name = "MineCamp"
	camp.set_script(load(MINE_CAMP))
	_own(camp, _objects)
	camp.set(&"smith", smith)
	camp.set(&"lamp", lamp)
	_clusters([Vector2(2.6, 6.5), Vector2(21.4, 3.2), Vector2(21.2, 7.6), Vector2(16.2, 11.6)])


## The ring's north-east corner (main path, lit): in from Run 2's strip (level 1 outside), out onto
## the east side (level 2); the first Glint Bats.
func _corner_cave() -> void:
	_rim([3, 13])
	_south_door("corner-cave-west", 3, H4, "corner-cave-west")
	_south_door("corner-cave-south", 13, H4, "corner-cave-south")
	_spawn(Vector2(4, 8.4))
	for at: Vector2 in [Vector2(6, 4), Vector2(10, 3.4), Vector2(13.6, 5.2)]:
		_enemy("glint-bat", "glint-bat", at, 90.0)
	var pot := _scene(DUNGEON + "dungeon-pot.tscn", "energy-pot", Vector2(2.8, 3.0), _objects)
	var loot := pot.get_node_or_null("PotLoot")
	if loot != null:
		_root.set_editable_instance(pot, true)
		loot.set(&"loot", "energy")
	_clusters([Vector2(2.6, 6.2), Vector2(8.2, 2.6), Vector2(15.4, 2.8), Vector2(9.4, 8.6)])


## Under the spike canyon (side way, lit): a ladder up to the ring's south side, one up to the bay.
func _bay_cave() -> void:
	_rim([])
	_ladder("bay-cave-north", Vector2(5, 3.1), H5, "bay-cave-down")
	_ladder("bay-cave-south", Vector2(17, 3.1), H5, "bay-cave-up")
	_spawn(Vector2(5, 4.6))
	_scene(OBJECTS + "crystal-pillar.tscn", "pillar", Vector2(11, 6.2), _objects)
	_enemy("crawler", "crystal-crawler", Vector2(11, 6.2 - 81.0 / CELL), 120.0)
	_scene(DUNGEON + "energy-flower.tscn", "energy-flower", Vector2(3.4, 6.6), _objects)
	_clusters([Vector2(8, 2.6), Vector2(14, 2.6), Vector2(19.4, 6.8)])


## Off the north shelf, behind deadthorn (the Lantern, later): a Gloomling sits on the chest.
func _dark_nook() -> void:
	_rim([6])
	_south_door("dark-nook-door", 6, G4, "dark-nook-mouth")
	_spawn(Vector2(7, 7.2))
	for at: Vector2 in [Vector2(3, 3.4), Vector2(11, 3.4)]:
		var brazier := _scene(OBJECTS + "brazier.tscn", "brazier", at, _objects)
		brazier.set(&"burn_ms", 60000.0)
	_chest("nook-chest", Vector2(7, 3.6), {"coins": 30, "energy-potion": 1})
	_enemy("gloomling", "gloomling", Vector2(7, 4.2), 60.0)


## Under the H4|H5 line (the Lantern, later): the heart's east shelf to the south-east bay.
func _under_line_tunnel() -> void:
	_rim([3, 21])
	_south_door("tunnel-north", 3, H4, "tunnel-north")
	_south_door("tunnel-south", 21, H5, "tunnel-south")
	_spawn(Vector2(4, 5.6))
	for at: Vector2 in [Vector2(9, 3.3), Vector2(17, 3.3)]:
		var brazier := _scene(OBJECTS + "brazier.tscn", "brazier", at, _objects)
		brazier.set(&"burn_ms", 60000.0)
	_chest("tunnel-chest", Vector2(13, 3.4), {"coins": 40})
	_enemy("gloomling", "gloomling", Vector2(7, 4.4), 70.0)
	_enemy("gloomling", "gloomling", Vector2(19.4, 4.4), 70.0)


# --- helpers --------------------------------------------------------------------------------------

static func _t(at: Vector2) -> Vector2:
	return at * CELL


func _own(node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = _root


func _scene(path: String, node_name: String, at: Vector2, parent: Node) -> Node2D:
	var node := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	node.name = _unique(node_name, parent)
	node.position = _t(at)
	_own(node, parent)
	return node


func _prop(path: String, node_name: String, at: Vector2, size: float) -> void:
	if not ResourceLoader.exists(path):
		push_warning("no prop " + path)
		return
	var prop := _scene(path, node_name, at, _objects)
	prop.scale = Vector2(size, size)


func _clusters(cells: Array) -> void:
	var i := 0
	for at: Vector2 in cells:
		var path := CLUSTER % (3 + (i % 5) * 2)
		if ResourceLoader.exists(path):
			_scene(path, "crystals", at, _objects)
		i += 1


func _enemy(enemy_name: String, type: String, at: Vector2, wander: float) -> void:
	var placed := (load(PLACED_ENEMY) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	placed.name = _unique(enemy_name, _enemies)
	placed.position = _t(at)
	placed.set(&"enemy_type", type)
	placed.set(&"wander_radius", wander)
	_own(placed, _enemies)


func _chest(chest_name: String, at: Vector2, contents: Dictionary) -> void:
	var chest := _scene(OBJECTS + "chest-wooden.tscn", chest_name, at, _objects)
	var script_node := chest.get_node("ChestScript")
	_root.set_editable_instance(chest, true)
	script_node.set(&"map_id", _map_id)
	script_node.set(&"instance_id", "%s-%s" % [_map_id, chest_name])
	script_node.set(&"initial_contents", contents)


## A cave ladder against the north wall, up to the hole `target_door` in chunk world `chunk` (its arrival).
func _ladder(door_id: String, at: Vector2, chunk: String, target_door: String) -> void:
	var ladder := _scene(OBJECTS + "cave-ladder.tscn", door_id, at, _objects)
	var door := ladder.get_node("DoorScript")
	_root.set_editable_instance(ladder, true)
	door.set(&"map_id", _map_id)
	door.set(&"door_id", door_id)
	door.set(&"target_area_id", chunk)
	door.set(&"target_door_id", target_door)


func _unique(base: String, parent: Node) -> String:
	var unique := base
	var n := 2
	while parent.has_node(NodePath(unique)):
		unique = "%s-%d" % [base, n]
		n += 1
	return unique
