extends SceneTree
## Lays the FIRST VERSION of the rebuilt Weaver Hollow's rooms (step 3 of the dungeons rework,
## docs/design/2026-11-23-dungeons-2-3-rework.md "The Weaver Hollow"; the list of links:
## docs/handover/2026-11-23-dungeons-rework.md "Step 3: the Trunk and the Roots"), one room world each,
## as Fatty's Lair is built: the root-rock interior walls (a two-cell rim) with their openings, the
## floor trim, the raised floors and voids on the `elevation` layer, the room doors, the locks, the
## prizes, the enemies and the dressing.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_weaver_hollow_rooms.gd -- --room=<name>[,<name>...] | --all [--layout] [--force]
## Rooms (the piece "the Trunk and the Roots"): t1-root-door, t2-hollow-heart, t3-larder, t3-map-nook,
## t4-well-room, r1-root-fall, r2-bone-cellar, r2-compass-pocket, r3-ram-cellar, d1-old-cellar; (the
## Boughs) stair-foot, b1-bough-stair, b2-drawbridge, b3-mimics-pantry, b4-nursery, b5-wardens-den,
## hoard, b6-spinning-loft, b7-pillar, d2-dark-bough; (the Crown) c1-crown-stair, c2-crown,
## c3-outer-bough. The review's scene edits of the first piece
## (2026-11-25: one trim, the Trunk's earth floors, the hub's paths) and the dressing after the
## cocoons and egg sacs came out (2026-11-25: T1, R1, B1, B4, B5, the Hoard, D2, C2) were made in the
## scenes. Each is
## written to res://game/scenes/worlds/rooms/weaver-hollow/<name>.tscn (world `weaver-hollow-<name>`);
## `--layout` (or a missing layout) writes the map layout `layout.tscn` too.
##
## **THE SCENES ARE HAND-EDITED AFTERWARDS** (the owner, 2026-10-18: content lives in hand-edited
## scenes; a tool writes a room's first version only). This tool refuses to overwrite a room scene (or
## the layout) that exists unless given `--force`, which throws the hand edits away: edit the scenes
## in the editor instead. After writing a room with elevation, bake its cache
## (`tools/bake_elevation.gd -- --world=weaver-hollow-<name>`), or let the next run from the project do it.
##
## Owner: dungeons (the Weaver Hollow).

const SceneSave := preload("res://tools/lib/scene_save.gd")
const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")

const DIR := "res://game/scenes/worlds/rooms/weaver-hollow/"
const LAYOUT_PATH := DIR + "layout.tscn"
const PREFIX := "weaver-hollow-"
const STYLE := "root-rock"
const CELL := 64
const DEPTH := 2
const CAVERN := 1
const SHEET := 19

const TERRAIN := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const INTERIOR_TILES := "res://game/world/interior/interior_wall_tileset.tres"
const INTERIOR_LAYER := "res://game/world/interior/interior_wall_layer.gd"
const TRIM_TILES := "res://game/world/interior/interior_trim_tileset.tres"
const TRIM_LAYER := "res://game/world/interior/interior_trim_layer.gd"
const ELEVATION_TILES := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const WEB_TILES := "res://game/world/webs/web_tileset.tres"
const WEB_LAYER := "res://game/world/webs/web_layer.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CAMERA_ROOM := "res://game/world/camera_room.gd"
const ROOM_SCENE := "res://game/dungeon/room_scene.gd"
const DOOR := "res://game/scripts/door.gd"
const DARK_ROOM := "res://game/world/darkness/dark_room.gd"
const SFX_PLAYER := "res://game/runtime/sfx_player.gd"
const MUSIC := "res://asset/audio/music/dungeon.wav"
const DUNGEON := "res://game/scenes/objects/dungeon/weaver-hollow-dungeon.tscn"
const LAYOUT_SCRIPT := "res://game/dungeon/dungeon_layout.gd"
const LAYOUT_ROOM := "res://game/dungeon/layout_room.gd"
const KIT := "res://game/scenes/objects/dungeon/"
const OBJ := "res://game/scenes/objects/"
const PLACED_ENEMY := "res://game/scenes/encounters/placed-enemy.tscn"

# --- the dressing (the Scenery dock's props, the dungeon kit, the Hollow's own pieces) -------------
const P_ROOTS_HANGING := OBJ + "interiors/mushroom-structure/interior-mushroom-structure-roots-hanging.tscn"
const P_WALL_ROOTS := OBJ + "interiors/mushroom-structure/interior-mushroom-structure-wall-hanging-roots.tscn"
const P_WALL_GLOW := OBJ + "interiors/mushroom-structure/interior-mushroom-structure-wall-glow-mushrooms.tscn"
const P_MOSS_OVERHANG := OBJ + "interiors/mushroom-structure/interior-mushroom-structure-moss-overhang.tscn"
const P_ROOT_HUMP := OBJ + "interiors/mushroom-structure/interior-mushroom-structure-root-hump.tscn"
const P_POST_ROOT := OBJ + "interiors/mushroom-structure/interior-mushroom-structure-post-root.tscn"
const P_MOSS_PATCH := OBJ + "interiors/mushroom-structure/interior-mushroom-structure-moss-patch.tscn"
const P_BRAZIER := OBJ + "brazier-lit.tscn"
const P_FAIRY_RING := OBJ + "interiors/mushroom-decor/interior-mushroom-decor-fairy-ring-glow.tscn"
const P_GLOW_CLUSTER := OBJ + "interiors/mushroom-decor/interior-mushroom-decor-glow-mushroom-cluster.tscn"
const P_GLOW_TALL := OBJ + "interiors/mushroom-decor/interior-mushroom-decor-glow-mushroom-tall.tscn"
const P_GLOW_SCONCE := OBJ + "interiors/mushroom-decor/interior-mushroom-decor-sconce-glow-mushroom.tscn"
const P_ACORN_LANTERN := OBJ + "interiors/mushroom-decor/interior-mushroom-decor-lantern-acorn-hanging.tscn"
const P_ROOT_TASSEL := OBJ + "interiors/mushroom-decor/interior-mushroom-decor-root-tassel.tscn"
const P_MF := OBJ + "interiors/mushroom-floor/interior-mushroom-floor-%s.tscn"
const P_SCONCE := OBJ + "interiors/decor/interior-decor-sconce-iron-lit.tscn"
const P_BARREL := OBJ + "interiors/storage/interior-storage-barrel.tscn"
const P_KEG := OBJ + "interiors/storage/interior-storage-keg-stand.tscn"
const P_SACK := OBJ + "interiors/storage/interior-storage-sack-grain.tscn"
const P_SACKS := OBJ + "interiors/storage/interior-storage-sacks-bundled.tscn"
const P_CRATE := OBJ + "interiors/storage/interior-storage-crate.tscn"
const P_CRATE_OPEN := OBJ + "interiors/storage/interior-storage-crate-open.tscn"
const P_SPEAR_RACK := OBJ + "interiors/workshop/interior-workshop-spear-rack.tscn"
const P_SWORD_RACK := OBJ + "interiors/workshop/interior-workshop-sword-rack.tscn"
const P_ARMOR_STAND := OBJ + "interiors/workshop/interior-workshop-armor-stand.tscn"
const P_HERB_RACK := OBJ + "interiors/workshop/interior-workshop-herb-drying-rack.tscn"
const P_HANGING_ROOTS_S := OBJ + "interiors/workshop/interior-workshop-roots-hanging.tscn"
const P_BUTCHER := OBJ + "interiors/kitchen/interior-kitchen-butcher-block.tscn"
const P_ROOT_CRATE := OBJ + "interiors/specialty/interior-specialty-root-crate.tscn"
const P_CHAIN := OBJ + "interiors/specialty/interior-specialty-chain-hanging.tscn"
const P_WEAPON_RACK := OBJ + "dungeon-decor/weapon-rack.tscn"
const P_BARREL_STACK := OBJ + "dungeon-decor/barrel-stack.tscn"
const P_BROKEN_CRATES := OBJ + "dungeon-decor/broken-crates.tscn"
const P_BROKEN_PILLAR := OBJ + "dungeon-decor/broken-pillar.tscn"
const P_BONES := OBJ + "dungeon-decor/bone-pile.tscn"
const P_CHAINS := OBJ + "dungeon-decor/hanging-chains.tscn"
const P_CAGE := OBJ + "dungeon-decor/hanging-cage.tscn"
const P_SHACKLES := OBJ + "dungeon-decor/wall-shackles.tscn"
const P_GUARD_TABLE := OBJ + "dungeon-decor/guard-table.tscn"
const P_GUARD_BENCH := OBJ + "dungeon-decor/guard-bench.tscn"
const P_CANDELABRA := OBJ + "dungeon-decor/candelabra.tscn"
const P_GRATE := OBJ + "dungeon-decor/floor-grate.tscn"
const P_WEB_CORNER := OBJ + "decoration-world-ambient--web-tree-01.tscn"
const P_WELL := OBJ + "decoration-world-solid--village-well.tscn"
const P_SPOOL := OBJ + "weaver-hollow/loft-spool.tscn"
const P_PEG_RAIL := OBJ + "weaver-hollow/loft-peg-rail.tscn"
const P_FIREFLY := OBJ + "cave-animals/firefly.tscn"
const P_GLOW_WORM := OBJ + "cave-animals/glow-worm.tscn"
const P_MOTH := OBJ + "cave-animals/lantern-moth.tscn"

## The rooms: name -> [columns, rows, the map's floor, its place on the layout].
const ROOMS := {
	"t1-root-door": [18, 16, 0, Vector2(3456, 2048)],
	"t2-hollow-heart": [36, 32, 0, Vector2(2304, 0)],
	"t3-larder": [18, 16, 0, Vector2(1152, 1024)],
	"t3-map-nook": [10, 8, 0, Vector2(512, 1152)],
	"t4-well-room": [18, 16, 0, Vector2(1152, 0)],
	"r1-root-fall": [18, 16, -1, Vector2(1152, 0)],
	"r2-bone-cellar": [36, 16, -1, Vector2(2304, 0)],
	"r2-compass-pocket": [10, 8, -1, Vector2(2624, -512)],
	"r3-ram-cellar": [18, 16, -1, Vector2(4608, 0)],
	"d1-old-cellar": [18, 16, -1, Vector2(3456, 1024)],
	# the Boughs (floor 1) and the stair foot (the Trunk), the second piece
	"stair-foot": [18, 16, 0, Vector2(2304, 2048)],
	"b1-bough-stair": [18, 16, 1, Vector2(1152, 2048)],
	"b2-drawbridge": [36, 16, 1, Vector2(1152, 1024)],
	"b3-mimics-pantry": [18, 16, 1, Vector2(0, 1024)],
	"b4-nursery": [18, 16, 1, Vector2(2304, 2048)],
	"b5-wardens-den": [18, 16, 1, Vector2(3456, 1024)],
	"hoard": [18, 16, 1, Vector2(3456, 0)],
	"b6-spinning-loft": [18, 16, 1, Vector2(2304, 0)],
	"b7-pillar": [18, 16, 1, Vector2(3456, 2048)],
	"d2-dark-bough": [18, 16, 1, Vector2(0, 2048)],
	# the Crown (floor 2), the third piece: C2 is the Matron lab's room, C3 a short bough
	"c1-crown-stair": [18, 16, 2, Vector2(2816, -1024)],
	"c2-crown": [24, 20, 2, Vector2(2752, -2304)],
	"c3-outer-bough": [18, 8, 2, Vector2(4288, -1920)],
}
## Terrain sources (terrain_tileset.tres): garden soil (packed earth), the gravel path, grass, the
## interior wood floor (one tile).
const SOIL := 20
const GRAVEL := 21
const GRASS := 7
const PLANKS := 12
const STORY_VARIANT := "res://game/scripts/story_variant.gd"
const CANDLE := "res://game/world/fire/candle.gd"
const PEARL_ART := "res://asset/MAPS/props/256x256-pearl-silk.webp"
const LEVEL_TILE := {-3: Vector2i(0, 0), -2: Vector2i(1, 0), -1: Vector2i(2, 0), 1: Vector2i(3, 0), 2: Vector2i(4, 0)}
const STAIRS_S := Vector2i(0, 1)
## The Matron's arena as her lab has it (game/dev/bosses/matron-lab.tscn, the owner's numbers): the
## rams' x along the north wall, their row, their lanes' length, the targets' row (each straight below
## its ram), her camp, the slime's way in, the twelve pots ([x, y, loot], world units).
const CAMP := "res://game/scenes/encounters/weaver-hollow-matron.tscn"
const CROWN_RAM_X: Array[float] = [288.0, 524.8, 768.0, 1011.2, 1248.0]
const CROWN_RAM_Y := 358.4
const CROWN_RAM_LENGTH := 9
const CROWN_TARGET_Y := 1075.2
const CROWN_CAMP := Vector2(768.0, 640.0)
const CROWN_SPAWN := Vector2(646.4, 1081.6)
const CROWN_POTS := [[172.8, 512.0, "none"], [172.8, 832.0, "none"], [403.2, 448.0, "none"],
	[646.4, 544.0, "none"], [646.4, 896.0, "energy"], [889.6, 416.0, "none"], [889.6, 800.0, "none"],
	[1126.4, 576.0, "none"], [1126.4, 928.0, "none"], [406.4, 1100.8, "energy"], [889.6, 1100.8, "none"],
	[1129.6, 1100.8, "none"]]

var _force := false
var _name := ""
var _cols := 0
var _rows := 0
var _root: Node2D
var _walls: TileMapLayer
var _elevation: TileMapLayer
var _trim: TileMapLayer
var _webs: TileMapLayer
var _objects: Node2D
var _scenery: Node2D
var _enemies: Node2D
var _doors: Node2D
## Floor cells the trim leaves clear (in front of openings), and the void cells.
var _clear := {}
var _wall_tiles := {}
var _trim_tiles := {}


func _initialize() -> void:
	var names: Array[String] = []
	var layout := false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--force":
			_force = true
		elif arg == "--layout":
			layout = true
		elif arg == "--all":
			for room: String in ROOMS:
				names.append(room)
		elif arg.begins_with("--room="):
			for room: String in arg.trim_prefix("--room=").split(",", false):
				names.append(room)
	if names.is_empty() and not layout:
		push_error("build_weaver_hollow_rooms: --room=<name>[,...] | --all [--layout] [--force]; rooms: " + ", ".join(ROOMS.keys()))
		quit(1)
		return
	_read_palettes()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var failed := false
	if layout or not FileAccess.file_exists(LAYOUT_PATH):
		failed = _write_layout() != OK
	for room: String in names:
		if not ROOMS.has(room):
			push_error("build_weaver_hollow_rooms: no room " + room)
			failed = true
			continue
		failed = _build(room) != OK or failed
	quit(1 if failed else 0)


func _read_palettes() -> void:
	var wall_set := load(INTERIOR_TILES) as TileSet
	var walls := wall_set.get_source(0) as TileSetAtlasSource
	for i in walls.get_tiles_count():
		var coords := walls.get_tile_id(i)
		var data := walls.get_tile_data(coords, 0)
		if str(data.get_custom_data(InteriorWalls.STYLE_DATA)) == STYLE:
			_wall_tiles[str(data.get_custom_data(InteriorWalls.OPENING_DATA))] = coords
	var trim_set := load(TRIM_TILES) as TileSet
	var trims := trim_set.get_source(0) as TileSetAtlasSource
	for i in trims.get_tiles_count():
		var coords := trims.get_tile_id(i)
		_trim_tiles[str(trims.get_tile_data(coords, 0).get_custom_data("floor_trim"))] = coords


# --- one room ------------------------------------------------------------------------------------

func _build(room: String) -> Error:
	var path := DIR + room + ".tscn"
	if FileAccess.file_exists(path) and not _force:
		print("weaver hollow rooms: %s exists and is hand-edited; not overwritten (-- --force throws the edits away)" % path)
		return OK
	var plan: Array = ROOMS[room]
	_name = room
	_cols = int(plan[0])
	_rows = int(plan[1])
	_clear = {}
	_shell()
	match room:
		"t1-root-door":
			_t1()
		"t2-hollow-heart":
			_t2()
		"t3-larder":
			_t3()
		"t3-map-nook":
			_nook()
		"t4-well-room":
			_t4()
		"r1-root-fall":
			_r1()
		"r2-bone-cellar":
			_r2()
		"r2-compass-pocket":
			_pocket()
		"r3-ram-cellar":
			_r3()
		"d1-old-cellar":
			_d1()
		"stair-foot":
			_stair_foot()
		"b1-bough-stair":
			_b1()
		"b2-drawbridge":
			_b2()
		"b3-mimics-pantry":
			_b3()
		"b4-nursery":
			_b4()
		"b5-wardens-den":
			_b5()
		"hoard":
			_hoard()
		"b6-spinning-loft":
			_b6()
		"b7-pillar":
			_b7()
		"d2-dark-bough":
			_d2()
		"c1-crown-stair":
			_c1()
		"c2-crown":
			_c2()
		"c3-outer-bough":
			_c3()
	if _elevation.get_used_cells().is_empty():
		_elevation.free()
	if _webs.get_used_cells().is_empty():
		_webs.free()
	for child in _root.get_children():
		_own(child)
	var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var err := SceneSave.save(_root, path, before)
	print("weaver hollow rooms: ", path, " ", error_string(err))
	_root.free()
	return err


## The room's layers and holders, its rim, its camera room, its world, its Dungeon node and music.
func _shell() -> void:
	_root = Node2D.new()
	_root.name = _name
	_root.y_sort_enabled = true
	_root.set_script(load(ROOM_SCENE))
	_root.set(&"world_id", PREFIX + _name)
	_root.set(&"room_id", _name)
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN)
	ground.set_script(load(WORLD_GROUND))
	for y in _rows:
		for x in _cols:
			ground.set_cell(Vector2i(x, y), CAVERN, Vector2i(x % SHEET, y % SHEET))
	ground.set_meta(&"columns", _cols)
	ground.set_meta(&"rows", _rows)
	_root.add_child(ground)
	_walls = TileMapLayer.new()
	_walls.name = "interior-walls"
	_walls.y_sort_enabled = true
	_walls.tile_set = load(INTERIOR_TILES)
	_walls.set_script(load(INTERIOR_LAYER))
	_root.add_child(_walls)
	for y in _rows:
		for x in _cols:
			if x < DEPTH or y < DEPTH or x >= _cols - DEPTH or y >= _rows - DEPTH:
				_walls.set_cell(Vector2i(x, y), 0, _wall_tiles[""])
	_elevation = TileMapLayer.new()
	_elevation.name = "elevation"
	_elevation.visible = false
	_elevation.tile_set = load(ELEVATION_TILES)
	_elevation.set_script(load(ELEVATION_LAYER))
	_elevation.set(&"room_back_faces", true)
	_root.add_child(_elevation)
	_webs = TileMapLayer.new()
	_webs.name = "webs"
	_webs.tile_set = load(WEB_TILES)
	_webs.set_script(load(WEB_LAYER))
	_root.add_child(_webs)
	_trim = TileMapLayer.new()
	_trim.name = "floor-trim"
	_trim.tile_set = load(TRIM_TILES)
	_trim.set_script(load(TRIM_LAYER))
	_root.add_child(_trim)
	var cameras := Node2D.new()
	cameras.name = "CameraRooms"
	_root.add_child(cameras)
	var camera := Node2D.new()
	camera.name = _name
	camera.set_script(load(CAMERA_ROOM))
	camera.set(&"size", Vector2(_cols * CELL, _rows * CELL))
	camera.set_meta(&"wall_bands", false)
	cameras.add_child(camera)
	var entry := Node2D.new()
	entry.name = "RoomEntry"
	camera.add_child(entry)
	_objects = _holder("Objects")
	_scenery = _holder("Scenery")
	_enemies = _holder("Enemies")
	_doors = _holder("RoomDoors")
	_doors.y_sort_enabled = false
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	definition.set(&"map_id", PREFIX + _name)
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", _cols)
	definition.set(&"rows", _rows)
	_root.add_child(definition)
	var spawn := Node2D.new()
	spawn.name = "player-spawn"
	_root.add_child(spawn)
	var dungeon := (load(DUNGEON) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	dungeon.name = "Dungeon"
	_root.add_child(dungeon)
	var music := AudioStreamPlayer.new()
	music.name = "MusicPlayer"
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	music.stream = load(MUSIC)
	music.volume_db = -6.0206
	music.bus = &"Music"
	music.set_script(load(SFX_PLAYER))
	music.set(&"loop", true)
	music.set(&"autoplay_cue", true)
	_root.add_child(music)


func _holder(holder_name: String) -> Node2D:
	var node := Node2D.new()
	node.name = holder_name
	node.y_sort_enabled = true
	_root.add_child(node)
	return node


## Where the slime starts (F6, `?map=`) and `?room=` lands: the RoomEntry and the spawn (cells).
func _spawn(at: Vector2) -> void:
	var spot := at * CELL
	(_root.get_node("player-spawn") as Node2D).position = spot
	(_root.get_node("CameraRooms/%s/RoomEntry" % _name) as Node2D).position = spot
	_root.get_node("world-definition").set(&"metadata", {"objects": [], "player": {"entries": {}, "spawn": {"x": int(spot.x), "y": int(spot.y)}}})


# --- painting ------------------------------------------------------------------------------------

## The 2 x 2 block of an opening in the rim: `side` n/s/w/e, `along` its first cell along the wall.
func _block(side: String, along: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DEPTH:
		for i in 2:
			match side:
				"n":
					out.append(Vector2i(along + i, d))
				"s":
					out.append(Vector2i(along + i, _rows - 1 - d))
				"w":
					out.append(Vector2i(d, along + i))
				_:
					out.append(Vector2i(_cols - 1 - d, along + i))
	return out


## Paints an opening (`kind`: doorway, cracked, blown, stairs, key1, key2, boss, bolt, shutter, seal,
## barricade) and keeps the two floor cells in front of it clear of the trim.
func _opening(side: String, along: int, kind: String) -> void:
	for cell: Vector2i in _block(side, along):
		_walls.set_cell(cell, 0, _wall_tiles[kind])
	for i in 2:
		match side:
			"n":
				_clear[Vector2i(along + i, DEPTH)] = true
			"s":
				_clear[Vector2i(along + i, _rows - DEPTH - 1)] = true
			"w":
				_clear[Vector2i(DEPTH, along + i)] = true
			_:
				_clear[Vector2i(_cols - DEPTH - 1, along + i)] = true


## The door object's spot for an opening: the floor line in the middle of the passage (world units).
func _gap(side: String, along: int) -> Vector2:
	match side:
		"n":
			return Vector2((along + 1) * CELL, DEPTH * CELL)
		"s":
			return Vector2((along + 1) * CELL, (_rows - DEPTH) * CELL)
		"w":
			return Vector2(DEPTH * CELL, (along + 1) * CELL)
	return Vector2((_cols - DEPTH) * CELL, (along + 1) * CELL)


## The block key the interior wall layer tags its door with (its first cell).
func _block_key(side: String, along: int) -> String:
	var first := _block(side, along)
	var cell := first[0]
	for c: Vector2i in first:
		cell = Vector2i(mini(cell.x, c.x), mini(cell.y, c.y))
	return "%d,%d" % [cell.x, cell.y]


## Paints `level` on every cell of `rect` (cells).
func _level(rect: Rect2i, level: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_elevation.set_cell(Vector2i(x, y), 0, LEVEL_TILE[level])
			if level < 0:
				_clear[Vector2i(x, y)] = true
				# a void's floor: the dark cavern stone (the ground shows in holes), as the Lair's voids
				(_root.get_node("ground") as TileMapLayer).set_cell(Vector2i(x, y), CAVERN, Vector2i(posmod(x, SHEET), posmod(y, SHEET)))


## A front flight of stairs going down south over `rect`'s cells.
func _stairs(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_elevation.set_cell(Vector2i(x, y), 0, STAIRS_S)
			_clear[Vector2i(x, y)] = true


## Floor webs over the cells of a ragged ellipse round `at` (cells), radii `rx`, `ry`.
func _web_blob(at: Vector2, rx: float, ry: float) -> void:
	for y in range(floori(at.y - ry), ceili(at.y + ry) + 1):
		for x in range(floori(at.x - rx), ceili(at.x + rx) + 1):
			var d := Vector2((x + 0.5 - at.x) / rx, (y + 0.5 - at.y) / ry)
			var ragged := 0.8 + 0.35 * float(posmod(x * 7 + y * 13, 5)) / 4.0
			if d.length() <= ragged and _walls.get_cell_source_id(Vector2i(x, y)) < 0:
				_webs.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))


## The floor trim `trim` on every floor cell but the clear ones (the layer draws only the cells beside
## a wall or a level's face).
func _trim_floor(trim: String) -> void:
	var tile: Vector2i = _trim_tiles[trim]
	for y in range(DEPTH, _rows - DEPTH):
		for x in range(DEPTH, _cols - DEPTH):
			var cell := Vector2i(x, y)
			if _walls.get_cell_source_id(cell) >= 0 or _clear.has(cell):
				continue
			_trim.set_cell(cell, 0, tile)


# --- placing -------------------------------------------------------------------------------------

func _own(node: Node) -> void:
	if node != _root:
		node.owner = _root
	if node.scene_file_path.is_empty() or node == _root:
		for child in node.get_children():
			_own(child)


func _instance(path: String, node_name: String, at: Vector2, parent: Node) -> Node2D:
	var node := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	node.name = _unique(node_name, parent)
	node.position = at
	parent.add_child(node)
	return node


## A kit piece (game/scenes/objects/dungeon/<scene>.tscn) at `at` (world units) with `props`.
func _kit(scene: String, node_name: String, at: Vector2, props: Dictionary = {}, parent: Node = null) -> Node2D:
	var node := _instance(KIT + scene + ".tscn", node_name, at, _objects if parent == null else parent)
	for key: String in props:
		node.set(key, props[key])
	return node


## Another object scene (game/scenes/objects/<scene>.tscn), in Objects.
func _object(scene: String, node_name: String, at: Vector2, props: Dictionary = {}) -> Node2D:
	var node := _instance(OBJ + scene + ".tscn", node_name, at, _objects)
	for key: String in props:
		node.set(key, props[key])
	return node


## A prop of the dressing at `at` (cells), in Scenery.
func _prop(path: String, at: Vector2, flip := false, size := 1.0) -> Node2D:
	if not ResourceLoader.exists(path):
		push_warning("weaver hollow rooms: no prop " + path)
		return null
	var node := _instance(path, path.get_file().get_basename().trim_prefix("interior-").trim_prefix("decoration-world-"), at * CELL, _scenery)
	if flip:
		node.scale.x = -size
		node.scale.y = size
	elif size != 1.0:
		node.scale = Vector2(size, size)
	return node


## A floor prop of the mushroom-floor set (`kind`: moss-2, root-5, pebbles-1, ...).
func _mf(kind: String, at: Vector2, flip := false) -> void:
	_prop(P_MF % kind, at, flip)


## An irregular bed of moss round `at` (cells): a moss patch, clumps of moss and grass about it
## (the second floor texture: the square floor tiles read as rugs).
func _moss_bed(at: Vector2, spread: float, count: int, salt: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_name) + salt
	_prop(P_MOSS_PATCH, at)
	var kinds := ["moss-1", "moss-2", "moss-3", "moss-4", "grass-moss-1", "grass-moss-2", "pebbles-mossy"]
	for i in count:
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.4, 0.4)
		var r := spread * rng.randf_range(0.55, 1.0)
		_mf(kinds[rng.randi() % kinds.size()], at + Vector2(cos(angle) * r, sin(angle) * r * 0.7), rng.randf() < 0.5)


## Stepping stones from `from` to `to` (cells), `count` of them, a little off the line: an old path.
func _stones(from: Vector2, to: Vector2, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_name) + int(from.x * 31.0 + to.y * 17.0)
	var across := (to - from).orthogonal().normalized()
	for i in count:
		var t := float(i) / float(maxi(1, count - 1))
		_mf("stepping-stone-%d" % (1 + rng.randi() % 8), from.lerp(to, t) + across * rng.randf_range(-0.22, 0.22), rng.randf() < 0.5)



func _pot(node_name: String, at: Vector2, loot := "random") -> void:
	var pot := _kit("dungeon-pot", node_name, at * CELL)
	_root.set_editable_instance(pot, true)
	pot.get_node("PotLoot").set(&"loot", loot)


func _chest(node_name: String, at: Vector2, contents: Dictionary, big := false) -> Node2D:
	var chest := _kit("dungeon-big-chest" if big else "dungeon-chest", node_name, at * CELL)
	chest.set(&"contents", contents)
	chest.set(&"chest_id", PREFIX + node_name)
	return chest


func _enemy(node_name: String, type: String, at: Vector2, wander: float) -> void:
	var placed := _instance(PLACED_ENEMY, node_name, at * CELL, _enemies)
	placed.set(&"enemy_type", type)
	placed.set(&"wander_radius", wander)


## A room door in the opening at `side`/`along` (its node on the room's outer edge).
func _room_door(door_id: String, side: String, along: int, target_room: String, target_door: String, props: Dictionary = {}) -> Node2D:
	var at: Vector2
	match side:
		"n":
			at = Vector2((along + 1) * CELL, 0)
		"s":
			at = Vector2((along + 1) * CELL, _rows * CELL)
		"w":
			at = Vector2(0, (along + 1) * CELL)
		_:
			at = Vector2(_cols * CELL, (along + 1) * CELL)
	var door := _kit("room-door", door_id, at, {}, _doors)
	door.set(&"door_id", door_id)
	door.set(&"side", {"n": "north", "s": "south", "w": "west", "e": "east"}[side])
	door.set(&"target_room", target_room)
	door.set(&"target_door", target_door)
	for key: String in props:
		door.set(key, props[key])
	return door


## A closed door object (DungeonDoor and kin) in its painted block, tagged as the wall layer tags the
## doors it adopts.
func _wall_door(scene: String, node_name: String, side: String, along: int, kind: String, props: Dictionary) -> Node2D:
	var wall := {"n": "north", "s": "south", "w": "west", "e": "east"}[side] as String
	var door := _kit(scene, node_name, _gap(side, along), {"wall": wall, "frame_drawn_by_wall": true, "interior_style": STYLE})
	for key: String in props:
		door.set(key, props[key])
	door.set_meta(&"interior_door_block", _block_key(side, along))
	door.set_meta(&"interior_door_kind", kind)
	return door


## A cracked wall in the cracked block at `side`/`along` (the wall draws the crack; a blast opens it).
func _crack(node_name: String, side: String, along: int, flag: String) -> void:
	var passage := {"n": Rect2(-32, -128, 64, 128), "s": Rect2(-32, 0, 64, 128),
		"w": Rect2(-128, -32, 128, 64), "e": Rect2(0, -32, 128, 64)}[side] as Rect2
	_object("cracked-wall", node_name, _gap(side, along), {"frame_drawn_by_wall": true, "flag_id": flag, "passage": passage})


## A stair door between worlds set in a `stairs` opening of the north wall: the wall draws the stairs,
## so the door's own picture is hidden; its well lies in the passage, behind whatever stands in it.
func _stair(node_name: String, along: int, direction: String, hatch_id: String, target_world: String, target_door: String) -> void:
	var stair := _object("stair-door", node_name, _gap("n", along), {"direction": direction, "hatch_id": hatch_id,
		"target_world": target_world, "target_door": target_door, "start_open": true,
		"arrival_offset": Vector2(0, 80), "trigger_rect": Rect2(-40, -112, 80, 56)})
	_root.set_editable_instance(stair, true)
	(stair.get_node("Visual") as CanvasItem).visible = false
	stair.set(&"visual", null)


func _unique(base: String, parent: Node) -> String:
	var unique := base
	var n := 2
	while parent.has_node(NodePath(unique)):
		unique = "%s-%d" % [base, n]
		n += 1
	return unique


# --- the Trunk -----------------------------------------------------------------------------------

## T1 the Root Door: the way in from the forecourt (south, the seal), floor webs, the corner loft (L1)
## with its chest seen from the floor, reached at the end from the hub's east gallery (north, L1).
func _t1() -> void:
	_level(Rect2i(11, 0, 7, 6), 1)
	_opening("s", 8, "seal")
	_opening("n", 7, "doorway")
	_opening("n", 13, "doorway")
	_wall_door("dungeon-seal", "t1-entrance-seal", "s", 8, "seal", {"glimpse": true, "ring_color": Color("#9a5ad8")})
	var way_out := Node2D.new()
	way_out.name = "weaver-hollow-entrance"
	way_out.position = _gap("s", 8)
	_objects.add_child(way_out)
	var door := Node.new()
	door.name = "DoorScript"
	door.set_script(load(DOOR))
	door.set(&"map_id", PREFIX + _name)
	door.set(&"door_id", "weaver-hollow-entrance")
	door.set(&"target_area_id", "gloop-forest-f4")
	door.set(&"target_door_id", "weaver-hollow-root-gate")
	door.set(&"side", "south")
	door.set(&"trigger_rect", Rect2(-64, 24, 128, 48))
	way_out.add_child(door)
	var entrance := Node2D.new()
	entrance.name = "dungeon-entrance"
	entrance.position = Vector2(9, 11.5) * CELL
	_root.add_child(entrance)
	_room_door("t1-north", "n", 7, "t2-hollow-heart", "t2-south-t1")
	_room_door("t1-loft-north", "n", 13, "t2-hollow-heart", "t2-south-gallery")
	_spawn(Vector2(9, 11.5))
	# the loft's chest, in sight from the floor
	_chest("t1-loft-chest", Vector2(13.5, 3.4), {"coins": 100, "hp-potion": 1})
	_prop(P_SPOOL, Vector2(11.7, 3.0))
	_prop(P_SACKS, Vector2(15.3, 4.6))
	_prop(P_PEG_RAIL, Vector2(15.0, 2.05))
	# floor webs across the way to the hub, silk and its makers
	_web_blob(Vector2(6.2, 9.6), 3.6, 1.7)
	_web_blob(Vector2(12.2, 9.8), 2.2, 1.5)
	_pot("t1-pot-1", Vector2(3.0, 12.6), "heart")
	_pot("t1-pot-2", Vector2(14.8, 12.6), "random")
	_prop(P_WALL_ROOTS, Vector2(4.0, 2.2))
	_prop(P_ROOTS_HANGING, Vector2(10.0, 2.2))
	_prop(P_WEB_CORNER, Vector2(2.9, 2.6))
	_prop(P_ROOT_HUMP, Vector2(3.4, 5.2))
	_prop(P_GLOW_CLUSTER, Vector2(2.7, 9.6))
	_prop(P_GLOW_TALL, Vector2(15.2, 9.0))
	_moss_bed(Vector2(4.6, 12.2), 1.3, 5, 1)
	_moss_bed(Vector2(13.0, 12.3), 1.2, 5, 2)
	_stones(Vector2(9.0, 13.0), Vector2(8.6, 11.6), 3)
	_mf("root-5", Vector2(7.0, 6.2))
	_mf("moss-2", Vector2(12.0, 7.4))
	_mf("leaves-fallen", Vector2(5.4, 11.0))
	_mf("pebbles-1", Vector2(13.4, 11.0))
	_mf("mushrooms-cream", Vector2(15.3, 7.6))
	_prop(P_FIREFLY, Vector2(6.5, 9.0))
	_prop(P_FIREFLY, Vector2(12.2, 5.4))
	_trim_floor("rubble-umber")


## T2 the Hollow Heart (2 x 2): the hub. Its gallery (L1) runs round three sides: west (key 1's
## chest, in sight from the floor), north (the Crown Door, the winch over the stair), east (behind a
## web wall: the Silk skin, a later piece). The gallery's stair comes down at row 6, cols 24-25, its
## foot shut by a stone block the winch sinks for good. South: key 1's door (to the Boughs, not built
## yet), the floor's doorway to T1, the east gallery's to T1's loft. West: T3's floor and walk.
func _t2() -> void:
	_level(Rect2i(0, 0, 36, 6), 1)
	_level(Rect2i(0, 6, 5, 20), 1)
	_level(Rect2i(31, 6, 5, 26), 1)
	_stairs(Rect2i(24, 6, 2, 1))
	_opening("w", 27, "doorway")
	_opening("w", 23, "doorway")
	_opening("s", 8, "key1")
	_opening("s", 25, "doorway")
	_opening("s", 31, "doorway")
	_opening("n", 16, "boss")
	_room_door("t2-west-floor", "w", 27, "t3-larder", "t3-east-floor")
	_room_door("t2-west-gallery", "w", 23, "t3-larder", "t3-east-walk")
	_room_door("t2-south-t1", "s", 25, "t1-root-door", "t1-north")
	_room_door("t2-south-gallery", "s", 31, "t1-root-door", "t1-loft-north")
	_wall_door("key-door", "t2-south-door", "s", 8, "key1", {"door_id": "weaver-hollow-t2-south-door", "keyholes": 1})
	_wall_door("boss-door", "t2-crown-door", "n", 16, "boss", {"door_id": "weaver-hollow-crown-door"})
	_spawn(Vector2(26, 26.5))
	# the stair block and its winch
	_kit("shutter", "t2-stair-block", Vector2(25, 7) * CELL, {"wall": "north", "starts_shut": true,
		"shutter_id": "weaver-hollow-t2-stair-block"})
	var winch_targets: Array[NodePath] = [NodePath("../t2-stair-block")]
	_kit("winch", "t2-winch", Vector2(22.2, 3.7) * CELL, {"winch_id": "weaver-hollow-t2-winch",
		"targets": winch_targets, "done_text": "The winch is wound tight. The stair is clear."})
	# key 1 on the west gallery, by its wall
	_chest("t2-key-chest", Vector2(2.75, 19.5), {"dungeon-small-key": 1})
	# the web wall across the north gallery: the east gallery is the Silk skin's (a later piece)
	_object("web-wall", "t2-east-gallery-web", Vector2(31, 4) * CELL, {"orientation": "side", "span": 256.0,
		"height": 270.0, "flag_id": "weaver-hollow.t2-east-gallery-web", "hides_secret": true})
	# the gallery: pots by the winch, the Guard's racks, silk
	_pot("t2-gallery-pot-1", Vector2(19.4, 3.6), "heart")
	_pot("t2-gallery-pot-2", Vector2(20.4, 4.4), "energy")
	_prop(P_SPEAR_RACK, Vector2(9.0, 2.3))
	_prop(P_SWORD_RACK, Vector2(12.0, 2.3))
	_prop(P_SCONCE, Vector2(14.7, 2.05))
	_prop(P_SCONCE, Vector2(19.3, 2.05))
	_prop(P_SCONCE, Vector2(27.5, 2.05))
	_prop(P_BARREL_STACK, Vector2(6.0, 2.7))
	_prop(P_WALL_ROOTS, Vector2(3.5, 2.2))
	_prop(P_WEB_CORNER, Vector2(33.0, 2.6))
	_prop(P_PEG_RAIL, Vector2(32.5, 8.1))
	_prop(P_SPOOL, Vector2(32.9, 18.0))
	_prop(P_SACKS, Vector2(3.4, 9.0))
	_prop(P_CRATE, Vector2(3.5, 13.0))
	_prop(P_GLOW_SCONCE, Vector2(2.4, 16.6))
	_prop(P_ACORN_LANTERN, Vector2(3.0, 23.0))
	# the floor: the Heart of the oak in the middle (roots round a glowing bed of moss)
	_prop(P_FAIRY_RING, Vector2(18.0, 17.0))
	_moss_bed(Vector2(18.0, 17.2), 2.2, 9, 3)
	_prop(P_BRAZIER, Vector2(14.6, 14.2))
	_prop(P_BRAZIER, Vector2(21.4, 14.2))
	_prop(P_BRAZIER, Vector2(14.6, 20.2))
	_prop(P_BRAZIER, Vector2(21.4, 20.2))
	_prop(P_POST_ROOT, Vector2(18.0, 13.2))
	_prop(P_POST_ROOT, Vector2(18.0, 21.4))
	_prop(P_GLOW_TALL, Vector2(18.0, 16.6))
	_prop(P_GLOW_CLUSTER, Vector2(17.2, 17.2))
	_prop(P_GLOW_CLUSTER, Vector2(18.9, 15.8))
	_prop(P_ROOT_HUMP, Vector2(14.0, 17.0))
	_prop(P_ROOT_HUMP, Vector2(22.4, 16.4), true)
	_prop(P_MOTH, Vector2(18.2, 14.0))
	_prop(P_FIREFLY, Vector2(16.0, 13.2))
	_prop(P_FIREFLY, Vector2(21.0, 18.4))
	# floor webs, an orb-weaver
	_web_blob(Vector2(10.4, 20.4), 2.8, 1.6)
	_web_blob(Vector2(26.0, 22.6), 2.4, 1.6)
	_web_blob(Vector2(10.6, 10.2), 1.8, 1.1)
	_enemy("t2-orb-weaver", "orb-weaver", Vector2(12.0, 15.5), 220.0)
	_pot("t2-floor-pot-1", Vector2(6.8, 27.8), "random")
	_pot("t2-floor-pot-2", Vector2(11.4, 27.6), "none")
	_pot("t2-floor-pot-3", Vector2(28.6, 27.6), "random")
	# under the gallery's face: roots and moss where the faces meet the floor
	_moss_bed(Vector2(8.4, 8.6), 1.2, 4, 4)
	_moss_bed(Vector2(27.0, 10.6), 1.3, 5, 5)
	_moss_bed(Vector2(7.6, 25.2), 1.2, 4, 6)
	_stones(Vector2(25.6, 28.8), Vector2(20.2, 21.6), 8)
	_stones(Vector2(3.0, 28.0), Vector2(14.4, 21.4), 10)
	_prop(P_BARREL_STACK, Vector2(29.0, 28.6))
	_prop(P_CRATE, Vector2(13.2, 28.7))
	_prop(P_ROOT_HUMP, Vector2(28.6, 14.6), true)
	_prop(P_ROOT_HUMP, Vector2(7.4, 19.6))
	_mf("root-6", Vector2(8.0, 14.0))
	_mf("root-2", Vector2(27.4, 16.0))
	_mf("moss-3", Vector2(13.0, 22.6))
	_mf("leaves-fallen", Vector2(22.0, 22.0))
	_mf("pebbles-2", Vector2(7.0, 22.4))
	_mf("mushrooms-brown", Vector2(28.6, 20.4))
	_mf("pebbles-mossy", Vector2(18.0, 24.0))
	_mf("root-4", Vector2(25.0, 18.0))
	_mf("moss-1", Vector2(6.6, 17.0))
	_trim_floor("rubble-umber")


## T3 the Larder: two orb-weavers on the floor. The walk (L1) along the east wall comes in from T4's
## ledge (north) and goes on into the hub's west gallery (east), cut by a gap; the drawbridge stands
## raised at the gap's near edge, chained to a cracked winch post on the far rim: a Goo Bomb thrown
## over the gap at the post lets it down. Two cracked walls: north into T4, west into the map nook.
func _t3() -> void:
	_level(Rect2i(13, 0, 5, 4), 1)
	_level(Rect2i(13, 7, 5, 2), 1)
	_opening("n", 13, "doorway")
	_opening("n", 7, "cracked")
	_opening("w", 5, "cracked")
	_opening("e", 7, "doorway")
	_opening("e", 11, "doorway")
	_crack("t3-crack-well", "n", 7, "weaver-hollow.t3-crack-well")
	_crack("t3-crack-nook", "w", 5, "weaver-hollow.t3-crack-nook")
	_room_door("t3-north-walk", "n", 13, "t4-well-room", "t4-south-ledge")
	_room_door("t3-north-crack", "n", 7, "t4-well-room", "t4-south-crack", {"requires": "flag:weaver-hollow.t3-crack-well", "locked_text": ""})
	_room_door("t3-west-nook", "w", 5, "t3-map-nook", "nook-east", {"requires": "flag:weaver-hollow.t3-crack-nook", "locked_text": "", "transition": "iris"})
	_room_door("t3-east-walk", "e", 7, "t2-hollow-heart", "t2-west-gallery")
	_room_door("t3-east-floor", "e", 11, "t2-hollow-heart", "t2-west-floor")
	_spawn(Vector2(13.5, 12.0))
	# the walk's gap: the drawbridge stands raised on the near rim (the north part, where the slime
	# comes in), held up by a chain from the cracked winch post on the far rim: a bomb thrown over the
	# gap breaks the post and the bridge falls across
	var bridge := _kit("drawbridge", "t3-bridge", Vector2(14, 4) * CELL, {"toward": "south", "length": 3,
		"width": 128.0, "bridge_id": "weaver-hollow-t3-bridge", "level": 1})
	var top := Node2D.new()
	top.name = "t3-bridge-top"
	top.position = Vector2(14.4, 4) * CELL + Vector2(0, -150)
	_objects.add_child(top)
	_object("winch-post-cracked", "t3-bridge-post", Vector2(15.45, 7.75) * CELL, {"flag_id": "weaver-hollow.t3-bridge-post", "blast_rise": 56.0,
		"target_path": NodePath("../" + String(bridge.name)), "chain_end": NodePath("../t3-bridge-top")})
	# the larder: casks, sacks, the butcher's block, prey hung up in silk
	_enemy("t3-orb-weaver-1", "orb-weaver", Vector2(5.0, 7.0), 180.0)
	_enemy("t3-orb-weaver-2", "orb-weaver", Vector2(9.0, 10.5), 180.0)
	_pot("t3-pot-1", Vector2(2.8, 12.6), "random")
	_pot("t3-pot-2", Vector2(10.6, 12.8), "none")
	_prop(P_BARREL_STACK, Vector2(3.0, 2.7))
	_prop(P_KEG, Vector2(5.0, 2.6))
	_prop(P_SACKS, Vector2(10.3, 2.8))
	_prop(P_SACK, Vector2(11.2, 3.5))
	_prop(P_HERB_RACK, Vector2(3.4, 9.6))
	_prop(P_BUTCHER, Vector2(6.6, 4.6))
	_prop(P_ROOT_CRATE, Vector2(2.9, 4.4))
	_prop(P_BARREL, Vector2(11.4, 12.4))
	_prop(P_CRATE_OPEN, Vector2(7.0, 12.7))
	_prop(P_WEB_CORNER, Vector2(2.9, 2.6))
	_prop(P_HANGING_ROOTS_S, Vector2(9.0, 2.15))
	_prop(P_SCONCE, Vector2(14.5, 2.05))
	_moss_bed(Vector2(7.4, 8.2), 1.4, 6, 7)
	_mf("seeds", Vector2(5.2, 11.6))
	_mf("leaves-fallen", Vector2(8.0, 11.4))
	_mf("root-5", Vector2(12.0, 11.0))
	_mf("pebbles-1", Vector2(4.0, 6.4))
	_prop(P_GLOW_CLUSTER, Vector2(2.6, 11.0))
	_prop(P_MOTH, Vector2(9.4, 4.0))
	_trim_floor("rubble-umber")


## T3's map nook: behind T3's west crack, the map in a chest.
func _nook() -> void:
	_opening("e", 3, "blown")
	_room_door("nook-east", "e", 3, "t3-larder", "t3-west-nook", {"transition": "iris"})
	_spawn(Vector2(6.4, 4.2))
	_chest("t3-map-chest", Vector2(4.0, 3.2), {"dungeon-map": 1})
	_prop(P_WEB_CORNER, Vector2(2.9, 2.6))
	_prop(P_SACK, Vector2(2.6, 4.4))
	_prop(P_GLOW_CLUSTER, Vector2(7.2, 2.6))
	_prop(P_SCONCE, Vector2(5.6, 2.05))
	_mf("pebbles-mossy", Vector2(5.4, 5.3))
	_trim_floor("rubble-umber")


## T4 the Well Room: the cracked floor (a Goo Bomb: the one-way fall to R1's ledge); the ledge (L1)
## down the east side, out of reach from the floor, with the Guard's stair coming up from R3 (north)
## and its doorway into T3's walk (south).
func _t4() -> void:
	_level(Rect2i(13, 0, 5, 16), 1)
	_opening("n", 13, "stairs")
	_opening("s", 13, "doorway")
	_opening("s", 7, "cracked")
	_stair("t4-guard-stair", 13, "down", PREFIX + "t4-guard-stair", PREFIX + "r3-ram-cellar", PREFIX + "r3-guard-stair")
	_crack("t4-crack-larder", "s", 7, "weaver-hollow.t3-crack-well")
	_room_door("t4-south-ledge", "s", 13, "t3-larder", "t3-north-walk")
	_room_door("t4-south-crack", "s", 7, "t3-larder", "t3-north-crack", {"requires": "flag:weaver-hollow.t3-crack-well", "locked_text": ""})
	_spawn(Vector2(8.0, 11.0))
	_object("cracked-floor", "t4-well-floor", Vector2(6.5, 6.5) * CELL, {"flag_id": "weaver-hollow.t4-well-floor",
		"target_area_id": PREFIX + "r1-root-fall", "target_door_id": PREFIX + "r1-landing",
		"door_id": PREFIX + "t4-well-floor", "kind": "fall"})
	# the old well, dry, its gear about it
	_prop(P_WELL, Vector2(9.6, 4.8))
	_prop(P_BARREL, Vector2(11.4, 3.0))
	_prop(P_CRATE, Vector2(2.8, 3.0))
	_prop(P_SACKS, Vector2(3.0, 12.4))
	_prop(P_CHAIN, Vector2(5.0, 2.1))
	_stones(Vector2(8.0, 13.2), Vector2(7.6, 8.6), 6)
	_moss_bed(Vector2(10.6, 9.4), 1.2, 5, 8)
	_mf("rock-half-buried", Vector2(3.4, 7.2))
	_mf("pebbles-3", Vector2(10.6, 11.6))
	_mf("root-6", Vector2(5.0, 11.8))
	_mf("moss-4", Vector2(11.4, 7.0))
	_prop(P_GLOW_CLUSTER, Vector2(2.7, 5.4))
	_prop(P_WEB_CORNER, Vector2(2.9, 2.6))
	# the Guard's ledge: a sconce over the stair, his racks along the wall
	_prop(P_SCONCE, Vector2(15.4, 2.05))
	_prop(P_SPEAR_RACK, Vector2(15.4, 6.2))
	_pot("t4-ledge-pot", Vector2(15.2, 10.4), "heart")
	_prop(P_WALL_ROOTS, Vector2(9.0, 2.2))
	_prop(P_FIREFLY, Vector2(6.0, 9.0))
	_trim_floor("rubble-umber")


# --- the Roots -----------------------------------------------------------------------------------

## R1 Root Fall: the slime lands on the ledge (L1) in the north-west corner, over the first egg sac;
## a front flight takes it down. East into R2.
func _r1() -> void:
	_level(Rect2i(0, 0, 7, 6), 1)
	_stairs(Rect2i(3, 6, 2, 1))
	_opening("e", 7, "doorway")
	_room_door("r1-east", "e", 7, "r2-bone-cellar", "r2-west")
	_spawn(Vector2(4.5, 3.5))
	var landing := _object("landing", "r1-landing", Vector2(4.5, 3.4) * CELL)
	landing.set(&"door_id", PREFIX + "r1-landing")
	_enemy("r1-egg-sac", "egg-sac", Vector2(11.0, 9.0), 60.0)
	_pot("r1-pot-1", Vector2(2.8, 12.6), "random")
	_pot("r1-pot-2", Vector2(14.8, 3.0), "none")
	_pot("r1-ledge-pot", Vector2(2.8, 2.9), "energy")
	# roots fall through the roof: hanging roots, humps, root posts, moss
	_prop(P_ROOTS_HANGING, Vector2(9.0, 2.2))
	_prop(P_ROOTS_HANGING, Vector2(13.0, 2.2))
	_prop(P_MOSS_OVERHANG, Vector2(4.6, 2.15))
	_prop(P_ROOT_HUMP, Vector2(13.6, 12.6))
	_prop(P_POST_ROOT, Vector2(8.0, 11.0))
	_prop(P_POST_ROOT, Vector2(14.6, 7.0))
	_moss_bed(Vector2(10.2, 11.4), 1.5, 6, 9)
	_moss_bed(Vector2(4.2, 10.4), 1.3, 5, 10)
	_stones(Vector2(4.0, 7.4), Vector2(14.6, 8.0), 9)
	_mf("root-7", Vector2(6.0, 8.2))
	_mf("root-1", Vector2(12.0, 5.0))
	_mf("moss-2", Vector2(3.2, 8.6))
	_mf("leaves-fallen", Vector2(7.0, 13.0))
	_prop(P_GLOW_CLUSTER, Vector2(15.2, 12.0))
	_prop(P_GLOW_WORM, Vector2(9.0, 12.4))
	_prop(P_FIREFLY, Vector2(11.0, 4.0))
	_trim_floor("rubble-umber")


## R2 the Bone Cellar (2 x 1): the Watcher Eye among pillars (cover from its sight), two Bone
## Throwers at the east end; the compass behind a crack in the north wall; D1's doorway south.
func _r2() -> void:
	_opening("w", 7, "doorway")
	_opening("e", 7, "doorway")
	_opening("s", 26, "doorway")
	_opening("n", 9, "cracked")
	_crack("r2-crack-pocket", "n", 9, "weaver-hollow.r2-crack-pocket")
	_room_door("r2-west", "w", 7, "r1-root-fall", "r1-east")
	_room_door("r2-east", "e", 7, "r3-ram-cellar", "r3-west")
	_room_door("r2-south", "s", 26, "d1-old-cellar", "d1-north")
	_room_door("r2-north-pocket", "n", 9, "r2-compass-pocket", "pocket-south", {"requires": "flag:weaver-hollow.r2-crack-pocket", "locked_text": "", "transition": "iris"})
	_spawn(Vector2(3.5, 8.0))
	# pillars: two rows, root posts and broken stone, cover from the Eye
	for x: float in [8.0, 13.0, 18.0, 23.0]:
		_prop(P_BROKEN_PILLAR if int(x) % 2 == 0 else P_POST_ROOT, Vector2(x, 5.4))
		_prop(P_POST_ROOT if int(x) % 2 == 0 else P_BROKEN_PILLAR, Vector2(x + 0.5, 10.6))
	_enemy("r2-watcher-eye", "watcher-eye", Vector2(16.0, 8.0), 200.0)
	_enemy("r2-bone-thrower-1", "bone-thrower", Vector2(30.5, 4.5), 60.0)
	_enemy("r2-bone-thrower-2", "bone-thrower", Vector2(30.5, 11.0), 60.0)
	_pot("r2-pot-1", Vector2(3.0, 3.0), "random")
	_pot("r2-pot-2", Vector2(3.0, 12.6), "none")
	_pot("r2-pot-3", Vector2(20.5, 12.8), "random")
	# the cellar: bones, shackles, chains, a cage, old casks
	_prop(P_SHACKLES, Vector2(5.5, 2.15))
	_prop(P_SHACKLES, Vector2(21.0, 2.15))
	_prop(P_CHAINS, Vector2(15.0, 2.15))
	_prop(P_CAGE, Vector2(27.6, 2.6))
	_prop(P_BONES, Vector2(26.0, 6.4))
	_prop(P_BONES, Vector2(11.0, 12.4))
	_prop(P_BONES, Vector2(32.6, 8.0))
	_prop(P_BARREL_STACK, Vector2(32.4, 2.7))
	_prop(P_BROKEN_CRATES, Vector2(32.6, 12.6))
	_prop(P_SCONCE, Vector2(12.0, 2.05))
	_prop(P_SCONCE, Vector2(24.5, 2.05))
	_prop(P_GRATE, Vector2(16.0, 12.6))
	_prop(P_WEB_CORNER, Vector2(2.9, 2.6))
	_stones(Vector2(3.0, 8.0), Vector2(33.0, 8.0), 22)
	_moss_bed(Vector2(20.6, 3.6), 1.2, 4, 11)
	_moss_bed(Vector2(6.0, 12.0), 1.2, 4, 12)
	_mf("root-3", Vector2(6.0, 11.6))
	_mf("pebbles-2", Vector2(21.0, 8.4))
	_mf("rock-mossy-small", Vector2(28.4, 12.0))
	_mf("moss-4", Vector2(10.4, 3.4))
	_prop(P_GLOW_WORM, Vector2(25.0, 12.0))
	_trim_floor("rubble-umber")


## R2's compass pocket: behind the Bone Cellar's north crack.
func _pocket() -> void:
	_opening("s", 4, "blown")
	_room_door("pocket-south", "s", 4, "r2-bone-cellar", "r2-north-pocket", {"transition": "iris"})
	_spawn(Vector2(5.0, 4.8))
	_chest("r2-compass-chest", Vector2(5.0, 3.0), {"dungeon-compass": 1})
	_prop(P_BONES, Vector2(2.8, 4.8))
	_prop(P_WEB_CORNER, Vector2(7.1, 2.6), true)
	_prop(P_GLOW_CLUSTER, Vector2(2.7, 2.7))
	_prop(P_SCONCE, Vector2(3.6, 2.05))
	_trim_floor("rubble-umber")


## R3 the Ram Cellar (in place of the Drop Gate): the Guard's ram hung before the bricked arch in the
## north wall, its knock target on an island in the void straight below it (the rope up to the ram's
## post), pots that grow back by the void: a pot thrown over the void lets the ram go, it bursts the
## arch, and the Guard's stair behind it climbs to T4's ledge.
func _r3() -> void:
	_level(Rect2i(8, 9, 6, 5), -2)
	for cell: Vector2i in [Vector2i(10, 11), Vector2i(11, 11), Vector2i(10, 12), Vector2i(11, 12)]:
		_elevation.erase_cell(cell)
		_clear[cell] = true
	_opening("w", 7, "doorway")
	_opening("n", 10, "stairs")
	_room_door("r3-west", "w", 7, "r2-bone-cellar", "r2-east")
	_spawn(Vector2(3.0, 8.0))
	_kit("hazard", "r3-void", Vector2(8, 9) * CELL, {"kind": "void", "size": Vector2(6, 5) * CELL, "level": -2,
		"pit_depth": 2, "draw_look": false})
	_kit("bricked-arch", "r3-arch", _gap("n", 10), {"wall": "north", "arch_id": "weaver-hollow-r3-arch", "interior_style": STYLE})
	_stair("r3-guard-stair", 10, "up", PREFIX + "r3-guard-stair", PREFIX + "t4-well-room", PREFIX + "t4-guard-stair")
	var ram := _kit("ram", "r3-ram", Vector2(11, 6) * CELL, {"toward": "north", "length": 4, "ram_id": "weaver-hollow-r3-ram"})
	var ram_targets: Array[NodePath] = [NodePath("../" + String(ram.name))]
	_kit("knock-target", "r3-target", Vector2(11, 12.3) * CELL, {"target_id": "weaver-hollow-r3-target",
		"targets": ram_targets})
	# pots that grow back, on the west rim of the void
	_pot("r3-pot-1", Vector2(5.4, 10.4), "none")
	_pot("r3-pot-2", Vector2(6.6, 11.6), "random")
	_pot("r3-pot-3", Vector2(5.2, 12.8), "none")
	_pot("r3-pot-4", Vector2(15.0, 12.6), "energy")
	# the Guard's armoury: racks, his stand, a table and bench, casks, sconces
	_prop(P_WEAPON_RACK, Vector2(4.0, 2.6))
	_prop(P_SWORD_RACK, Vector2(7.0, 2.3))
	_prop(P_ARMOR_STAND, Vector2(14.8, 3.0))
	_prop(P_BARREL_STACK, Vector2(14.6, 5.4))
	_prop(P_GUARD_TABLE, Vector2(3.6, 11.6))
	_prop(P_GUARD_BENCH, Vector2(3.6, 12.9))
	_prop(P_SCONCE, Vector2(8.6, 2.05))
	_prop(P_SCONCE, Vector2(13.4, 2.05))
	_prop(P_CHAINS, Vector2(2.6, 6.0))
	_prop(P_CANDELABRA, Vector2(2.8, 9.4))
	_stones(Vector2(2.8, 8.0), Vector2(9.0, 8.0), 6)
	_moss_bed(Vector2(14.6, 10.0), 1.0, 4, 13)
	_mf("pebbles-1", Vector2(14.4, 8.6))
	_mf("root-8", Vector2(15.0, 11.0))
	_prop(P_WEB_CORNER, Vector2(15.1, 2.6), true)
	_trim_floor("rubble-umber")


## D1 the Old Cellar, as today: dark (the Lantern, Chapter 3), a corridor down the east side parted
## from the room (today by a rock column; here a wall of old casks, solid, close enough that the slime
## cannot slip between them: a raised strip read as a walk), deadthorn at its mouth, the chest (the
## war journal's second page) at its end.
func _d1() -> void:
	var y := 8.3
	var i := 0
	while y < 13.7:
		_prop(P_BARREL_STACK, Vector2(12.5, y), i % 2 == 1)
		y += 0.6
		i += 1
	_opening("n", 8, "doorway")
	_room_door("d1-north", "n", 8, "r2-bone-cellar", "r2-south")
	_spawn(Vector2(9.0, 4.0))
	_object("deadthorn-hedge", "d1-roots", Vector2(14.5, 7.6) * CELL)
	var chest := _chest("d1-old-cellar-chest", Vector2(14.5, 12.5), {"war-journal-page-2": 1})
	# the same record as today's D1 chest, so the page is never had twice
	chest.set(&"chest_id", "weaver-hollow-roots-old-cellar-chest")
	chest.set(&"map_id", "weaver-hollow-roots")
	_kit("prize-glint", "d1-glint", Vector2(14.5, 11.7) * CELL)
	var dark := Node2D.new()
	dark.name = "DarkRooms"
	_root.add_child(dark)
	var room := Node2D.new()
	room.name = _name
	room.set_script(load(DARK_ROOM))
	room.set(&"size", Vector2(_cols * CELL, _rows * CELL))
	dark.add_child(room)
	_prop(P_BARREL_STACK, Vector2(3.0, 2.7))
	_prop(P_BROKEN_CRATES, Vector2(5.4, 3.0))
	_prop(P_ROOT_HUMP, Vector2(4.0, 11.4))
	_prop(P_BONES, Vector2(9.0, 12.4))
	_prop(P_WEB_CORNER, Vector2(2.9, 2.6))
	_prop(P_WEB_CORNER, Vector2(15.1, 2.6), true)
	_mf("root-8", Vector2(3.0, 7.0))
	_mf("root-4", Vector2(9.0, 8.0))
	_mf("pebbles-mossy", Vector2(6.0, 10.0))
	_prop(P_GLOW_WORM, Vector2(7.0, 6.0))
	_trim_floor("rubble-umber")


# --- the Boughs (the second piece of step 3, 2026-11-25) -------------------------------------------

## The ground layer painted whole with `source` (its sheet-wrap frames), the wall style's floor off:
## the room's floor is that ground (docs/godot/DUNGEONS.md "The Weaver Hollow rebuilt", Floors).
func _ground_floor(source: int) -> void:
	_walls.set(&"draw_floor", false)
	_ground_rect(Rect2i(0, 0, _cols, _rows), source)


## `rect`'s cells of the ground layer painted with `source` (a single-tile source: (0, 0) everywhere).
func _ground_rect(rect: Rect2i, source: int) -> void:
	var ground := _root.get_node("ground") as TileMapLayer
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var frame := Vector2i.ZERO if source >= PLANKS and source <= 18 else Vector2i(posmod(x, SHEET), posmod(y, SHEET))
			ground.set_cell(Vector2i(x, y), source, frame)


## A falling slab over the void at `cell`, holding bodies at `level`.
func _slab(node_name: String, cell: Vector2i, level: int) -> void:
	_kit("falling-slab", node_name, Vector2(cell) * CELL, {"size": Vector2(CELL, CELL), "level": level})


## A landing (a deck that holds for good) over the void at `cell`, at `level`.
func _deck(node_name: String, cell: Vector2i, level: int) -> void:
	_kit("hazard-deck", node_name, Vector2(cell) * CELL, {"size": Vector2(CELL, CELL), "level": level})


## A shutter in a painted shutter block, shut by the room fight `fight_id` (or `starts_shut` for good
## until `shutter_id` opens it).
func _fight_shutter(node_name: String, side: String, along: int, props: Dictionary) -> Node2D:
	return _wall_door("shutter", node_name, side, along, "shutter", props)


## The room's fight over the whole room.
func _fight(node_name: String, props: Dictionary) -> Node2D:
	var fight := _kit("room-fight", node_name, Vector2.ZERO, props)
	fight.set(&"size", Vector2(_cols * CELL, _rows * CELL))
	return fight


## A holder shown only while the story flag `flag` is set (`when_set`) or not; its StoryVariantScript.
func _variant(node_name: String, flag: String, when_set: bool) -> Node2D:
	var holder := Node2D.new()
	holder.name = node_name
	holder.y_sort_enabled = true
	_objects.add_child(holder)
	var shown := Node2D.new()
	shown.name = "shown"
	shown.y_sort_enabled = true
	holder.add_child(shown)
	var script_node := Node.new()
	script_node.name = "StoryVariantScript"
	script_node.set_script(load(STORY_VARIANT))
	script_node.set(&"flag_id", flag)
	holder.add_child(script_node)
	script_node.set(&"when_set" if when_set else &"when_unset", shown)
	return shown


## The Rafter Run's planks on a raised walk: `rect`'s cells of the ground are the wood floor.
func _planks(rect: Rect2i) -> void:
	_ground_rect(rect, PLANKS)


## The stair foot (the Trunk, floor 0): behind the hub's south key door, the Guard's stair up to B1.
func _stair_foot() -> void:
	_ground_floor(SOIL)
	_opening("n", 8, "doorway")
	_opening("n", 13, "stairs")
	_room_door("sf-north", "n", 8, "t2-hollow-heart", "t2-south-stair")
	_stair("sf-stair", 13, "up", PREFIX + "sf-stair", PREFIX + "b1-bough-stair", PREFIX + "b1-stair")
	_spawn(Vector2(9.0, 4.0))
	_ground_rect(Rect2i(8, 2, 2, 6), GRAVEL)
	_ground_rect(Rect2i(10, 6, 5, 2), GRAVEL)
	_ground_rect(Rect2i(13, 2, 2, 4), GRAVEL)
	_prop(P_WEAPON_RACK, Vector2(3.2, 2.6))
	_prop(P_SPEAR_RACK, Vector2(5.6, 2.3))
	_prop(P_SCONCE, Vector2(11.5, 2.05))
	_prop(P_SCONCE, Vector2(15.6, 2.05))
	_prop(P_ARMOR_STAND, Vector2(15.0, 5.6))
	_prop(P_GUARD_TABLE, Vector2(4.2, 10.6))
	_prop(P_GUARD_BENCH, Vector2(4.2, 12.0))
	_prop(P_BARREL_STACK, Vector2(14.8, 12.6))
	_prop(P_CRATE, Vector2(2.8, 12.8))
	_prop(P_WEB_CORNER, Vector2(15.1, 2.6), true)
	_moss_bed(Vector2(10.6, 11.4), 1.3, 5, 21)
	_prop(P_BRAZIER, Vector2(6.4, 6.4))
	_pot("sf-pot-1", Vector2(2.8, 3.0), "heart")
	_trim_floor("rubble-umber")


## B1 the Bough Stair: up from the stair foot (its stair in the north wall), a Silk Lurker, floor webs;
## north into B2, west into D2 (dark).
func _b1() -> void:
	_ground_floor(SOIL)
	_opening("n", 7, "doorway")
	_opening("n", 12, "stairs")
	_opening("w", 7, "doorway")
	_stair("b1-stair", 12, "down", PREFIX + "b1-stair", PREFIX + "stair-foot", PREFIX + "sf-stair")
	_room_door("b1-north", "n", 7, "b2-drawbridge", "b2-south-b1")
	_room_door("b1-west", "w", 7, "d2-dark-bough", "d2-east")
	_spawn(Vector2(13.0, 4.0))
	_ground_rect(Rect2i(12, 2, 2, 3), GRAVEL)
	_ground_rect(Rect2i(7, 4, 7, 2), GRAVEL)
	_ground_rect(Rect2i(7, 2, 2, 2), GRAVEL)
	_web_blob(Vector2(9.0, 9.4), 3.4, 1.8)
	_web_blob(Vector2(4.0, 12.0), 1.8, 1.2)
	_enemy("b1-silk-lurker", "silk-lurker", Vector2(8.0, 9.0), 180.0)
	_pot("b1-pot-1", Vector2(2.8, 12.8), "random")
	_pot("b1-pot-2", Vector2(14.8, 12.8), "none")
	_prop(P_ROOTS_HANGING, Vector2(4.0, 2.2))
	_prop(P_WALL_ROOTS, Vector2(15.6, 2.2))
	_prop(P_WEB_CORNER, Vector2(2.9, 2.6))
	_prop(P_ROOT_HUMP, Vector2(3.4, 8.4))
	_prop(P_POST_ROOT, Vector2(14.6, 11.0))
	_moss_bed(Vector2(11.6, 12.4), 1.2, 5, 22)
	_prop(P_GLOW_CLUSTER, Vector2(2.6, 10.6))
	_prop(P_FIREFLY, Vector2(10.0, 7.0))
	_trim_floor("rubble-umber")


## B2 the Drawbridge (2 x 1): the void down the middle (cols 17-20: a throw carries about 280 units,
## so a bomb thrown from the west rim reaches the post on the east rim's edge), the drawbridge raised
## on its west rim, chained to that cracked post; the rafters (L1) along the north wall, cut by the
## void: slab, landing, slab, slab under floor webs (a Roll sticks in the web without the Silk skin and
## falls with its slab; with the skin it crosses, westward).
func _b2() -> void:
	_ground_floor(SOIL)
	# the rafters, rows 2-3, and the rim beside them
	_level(Rect2i(0, 0, 17, 4), 1)
	_level(Rect2i(21, 0, 15, 4), 1)
	_level(Rect2i(17, 0, 4, 2), 1)
	_level(Rect2i(17, 2, 4, 12), -2)
	_planks(Rect2i(2, 2, 15, 2))
	_planks(Rect2i(21, 2, 13, 2))
	_opening("s", 7, "doorway")
	_opening("s", 25, "doorway")
	_opening("w", 7, "doorway")
	_opening("w", 2, "doorway")
	_opening("e", 7, "key1")
	_opening("n", 27, "doorway")
	_room_door("b2-south-b1", "s", 7, "b1-bough-stair", "b1-north")
	_room_door("b2-south-b4", "s", 25, "b4-nursery", "b4-north")
	_room_door("b2-west-floor", "w", 7, "b3-mimics-pantry", "b3-east-floor")
	_room_door("b2-west-rafters", "w", 2, "b3-mimics-pantry", "b3-east-rafters")
	_room_door("b2-east", "e", 7, "b5-wardens-den", "b5-west")
	_room_door("b2-north-rafters", "n", 27, "b6-spinning-loft", "b6-south")
	_wall_door("key-door", "b2-warden-door", "e", 7, "key1", {"door_id": "weaver-hollow-warden-door", "keyholes": 1})
	_spawn(Vector2(8.0, 12.0))
	# two hazards over the one void, one per level it is fallen into from (a hazard drops only bodies at
	# its rim: the lowest level painted round it): the floor's (rim 0) and the rafters' crossing (rim 1)
	_kit("hazard", "b2-void", Vector2(17, 4) * CELL, {"kind": "void", "size": Vector2(4, 10) * CELL, "level": -2,
		"pit_depth": 2, "draw_look": false})
	_kit("hazard", "b2-void-rafters", Vector2(17, 2) * CELL, {"kind": "void", "size": Vector2(4, 2) * CELL, "level": -2,
		"rim_level": 1, "pit_depth": 3, "draw_look": false})
	# the drawbridge: raised on the west rim, its chain to the post on the far rim
	var bridge := _kit("drawbridge", "b2-bridge", Vector2(17, 8) * CELL, {"toward": "east", "length": 4,
		"width": 128.0, "bridge_id": "weaver-hollow-b2-bridge"})
	var top := Node2D.new()
	top.name = "b2-bridge-top"
	top.position = Vector2(17, 8) * CELL + Vector2(0, -150)
	_objects.add_child(top)
	# thrown at from the west rim, a bomb lands at its foot: no blast rise (T3's is thrown at from the north)
	_object("winch-post-cracked", "b2-bridge-post", Vector2(21.45, 9.6) * CELL, {"flag_id": "weaver-hollow.b2-bridge-post",
		"target_path": NodePath("../" + String(bridge.name)), "chain_end": NodePath("../b2-bridge-top")})
	# the rafters' crossing westward under floor webs (L1): slab, landing, slab, slab: one quick Roll
	# from the east rim's edge to the landing, one on from its west edge (DUNGEONS.md slab timings)
	_slab("b2-slab-1", Vector2i(17, 3), 1)
	_deck("b2-landing", Vector2i(18, 3), 1)
	_slab("b2-slab-2", Vector2i(19, 3), 1)
	_slab("b2-slab-3", Vector2i(20, 3), 1)
	for x: int in [17, 19, 20]:
		_webs.set_cell(Vector2i(x, 3), 0, Vector2i(0, 0))
	# the webs over the slabs (decks draw at z -1, as the web layer does; its y 0 keeps it under bodies)
	_webs.z_index = 0
	# the floor: the way from B1 to the bridge, webs, the Guard's old hall
	_ground_rect(Rect2i(7, 6, 2, 8), GRAVEL)
	_ground_rect(Rect2i(9, 7, 8, 2), GRAVEL)
	_ground_rect(Rect2i(21, 7, 13, 2), GRAVEL)
	_ground_rect(Rect2i(25, 9, 2, 5), GRAVEL)
	_web_blob(Vector2(5.0, 10.8), 2.4, 1.5)
	_web_blob(Vector2(29.0, 11.0), 2.6, 1.4)
	_pot("b2-pot-1", Vector2(14.8, 12.6), "random")
	_pot("b2-pot-2", Vector2(15.6, 11.8), "none")
	_pot("b2-pot-3", Vector2(32.6, 5.4), "heart")
	_prop(P_SCONCE, Vector2(10.0, 2.05))
	_prop(P_SCONCE, Vector2(26.0, 2.05))
	_prop(P_PEG_RAIL, Vector2(6.0, 2.05))
	_prop(P_SPOOL, Vector2(13.8, 2.8))
	_prop(P_SACKS, Vector2(24.0, 2.8))
	_prop(P_ROOT_HUMP, Vector2(3.4, 6.0))
	_prop(P_POST_ROOT, Vector2(14.6, 10.6))
	_prop(P_POST_ROOT, Vector2(23.4, 12.6))
	_prop(P_BARREL_STACK, Vector2(32.6, 12.6))
	_moss_bed(Vector2(4.0, 12.4), 1.2, 5, 23)
	_moss_bed(Vector2(31.0, 12.8), 1.2, 4, 24)
	_prop(P_GLOW_CLUSTER, Vector2(15.4, 5.4))
	_prop(P_FIREFLY, Vector2(19.5, 9.0))
	_trim_floor("rubble-umber")


## B3 the Mimic's Pantry: the Cocoon Mimic (key 2); the rafters (L1) along the north wall with the big
## chest (the big key) in sight from the floor, their east doorway from B2's rafters, an open hole in
## them (the one-way drop to the hub's north gallery); S2's parcels behind a web wall (Silk).
func _b3() -> void:
	_ground_floor(SOIL)
	_level(Rect2i(0, 0, 18, 5), 1)
	_planks(Rect2i(2, 2, 14, 3))
	_opening("e", 7, "doorway")
	_opening("e", 2, "doorway")
	_room_door("b3-east-floor", "e", 7, "b2-drawbridge", "b2-west-floor")
	_room_door("b3-east-rafters", "e", 2, "b2-drawbridge", "b2-west-rafters")
	_spawn(Vector2(13.0, 8.0))
	_chest("b3-big-chest", Vector2(5.5, 3.6), {"dungeon-big-key": 1}, true)
	var hole := _object("open-hole", "b3-rafter-hole", Vector2(10.5, 3.4) * CELL)
	_root.set_editable_instance(hole, true)
	var door := hole.get_node_or_null("DoorScript")
	if door == null:
		door = hole.find_child("DoorScript", true, false)
	if door != null:
		door.set(&"map_id", PREFIX + _name)
		door.set(&"door_id", PREFIX + "b3-rafter-hole")
		door.set(&"target_area_id", PREFIX + "t2-hollow-heart")
		door.set(&"target_door_id", PREFIX + "gallery-landing")
	_enemy("b3-cocoon-mimic", "cocoon-mimic", Vector2(9.0, 9.4), 120.0)
	var mimic := _enemies.get_node("b3-cocoon-mimic")
	mimic.set(&"overrides", {"swallowed_flag": "weaver-hollow.b3-mimic-key", "swallowed_scene_id": "object.dungeon-key",
		"swallowed_settings": {"item": "small-key", "pickup_id": "weaver-hollow-b3-mimic-key"}})
	# S2: the nook in the south-west corner, behind casks and a web wall (the Silk skin)
	var y := 10.9
	while y < 13.9:
		_prop(P_BARREL_STACK, Vector2(5.6, y))
		y += 0.6
	_object("web-wall", "b3-s2-web", Vector2(3.5, 10.6) * CELL, {"span": 192.0, "height": 104.0,
		"flag_id": "weaver-hollow.b3-s2-web", "hides_secret": true})
	for i in 3:
		# today's S2 parcels' flags, so a save that took them never has them twice
		var parcel := _object("silk-parcel", "b3-s2-parcel-%d" % i, Vector2(2.8 + i * 0.9, 12.6) * CELL,
			{"flag_id": "weaver-hollow.s2-parcel-%d" % i})
		parcel.set(&"contents", [{"hp-potion": 1}, {"energy-potion": 1}, {}][i])
		if i == 2:
			parcel.set(&"coins", 40)
	# the pantry: casks, sacks, the Mimic's larder of wrapped prey
	_prop(P_BARREL, Vector2(15.0, 12.6))
	_prop(P_KEG, Vector2(15.2, 9.4))
	_prop(P_SACKS, Vector2(12.6, 12.8))
	_prop(P_SACK, Vector2(13.6, 12.4))
	_prop(P_HERB_RACK, Vector2(10.6, 12.8))
	_prop(P_CRATE_OPEN, Vector2(7.6, 12.8))
	_prop(P_SCONCE, Vector2(8.6, 2.05))
	_prop(P_PEG_RAIL, Vector2(13.4, 2.05))
	_prop(P_WEB_CORNER, Vector2(2.9, 2.6))
	_moss_bed(Vector2(8.6, 11.0), 1.2, 5, 25)
	_prop(P_GLOW_CLUSTER, Vector2(15.3, 6.6))
	_trim_floor("rubble-umber")


## B4 the Nursery: the optional ambush, as today (once: shutters close both doorways; three egg sacs
## in rings of webs and an orb-weaver; won once nothing lives, its chest appears).
func _b4() -> void:
	_ground_floor(SOIL)
	_opening("n", 7, "shutter")
	_opening("e", 11, "shutter")
	_room_door("b4-north", "n", 7, "b2-drawbridge", "b2-south-b4")
	_room_door("b4-east", "e", 11, "b7-pillar", "b7-west")
	_fight_shutter("b4-shutter-north", "n", 7, {"fight_id": "weaver-hollow-b4-nursery"})
	_fight_shutter("b4-shutter-east", "e", 11, {"fight_id": "weaver-hollow-b4-nursery"})
	_spawn(Vector2(8.0, 4.0))
	var chest := _chest("b4-nursery-chest", Vector2(9.0, 7.6), {"coins": 30, "hp-potion": 1})
	chest.set(&"starts_hidden", true)
	# the same record as today's nursery chest, so its coins and potion are never had twice
	chest.set(&"chest_id", "weaver-hollow-boughs-nursery-chest")
	chest.set(&"map_id", "weaver-hollow-boughs")
	_fight("b4-nursery-fight", {"fight_id": "weaver-hollow-b4-nursery", "once": true, "reward": NodePath("../b4-nursery-chest")})
	for at: Vector2 in [Vector2(5.0, 5.4), Vector2(13.0, 5.4), Vector2(13.0, 10.4)]:
		_web_blob(at, 1.6, 1.2)
		_enemy("b4-egg-sac", "egg-sac", at, 40.0)
	_enemy("b4-orb-weaver", "orb-weaver", Vector2(6.0, 10.4), 160.0)
	_prop(P_WEB_CORNER, Vector2(2.9, 2.6))
	_prop(P_WEB_CORNER, Vector2(15.1, 2.6), true)
	_prop(P_ROOTS_HANGING, Vector2(12.0, 2.2))
	_prop(P_ROOT_HUMP, Vector2(14.4, 12.6), true)
	_moss_bed(Vector2(9.0, 12.0), 1.3, 5, 26)
	_prop(P_GLOW_WORM, Vector2(7.0, 8.6))
	_trim_floor("rubble-umber")


## B5 the Warden's Den: the Brood Warden (the room fight, Pearl 2's guard); a ram across the den (its
## lane east along rows 10-11), its knock target past the lane's end in its line, the rope along the
## lane: lured onto the lane when the log swings, he is knocked flat, his plates open.
func _b5() -> void:
	_ground_floor(SOIL)
	_opening("w", 7, "shutter")
	_opening("n", 7, "shutter")
	_room_door("b5-west", "w", 7, "b2-drawbridge", "b2-east")
	_room_door("b5-north", "n", 7, "hoard", "hoard-south")
	_fight_shutter("b5-den-shutter", "w", 7, {"fight_id": "weaver-hollow-b5-warden"})
	var hoard_shutter := _fight_shutter("b5-hoard-shutter", "n", 7, {"starts_shut": true, "shutter_id": "weaver-hollow-hoard-shutter"})
	_fight("b5-warden-fight", {"fight_id": "weaver-hollow-b5-warden", "boss_id": "weaver-hollow-brood-warden",
		"reward": NodePath("../" + String(hoard_shutter.name))})
	_spawn(Vector2(3.4, 8.0))
	var ram := _kit("ram", "b5-ram", Vector2(5, 11) * CELL, {"toward": "east", "length": 8, "ram_id": "weaver-hollow-b5-ram"})
	var ram_targets: Array[NodePath] = [NodePath("../" + String(ram.name))]
	_kit("knock-target", "b5-target", Vector2(14.5, 11.2) * CELL, {"target_id": "weaver-hollow-b5-target",
		"targets": ram_targets})
	_enemy("b5-brood-warden", "brood-warden", Vector2(9.0, 6.4), 200.0)
	_enemy("b5-egg-sac", "egg-sac", Vector2(13.4, 4.0), 40.0)
	for i in 4:
		_pot("b5-pot-%d" % i, [Vector2(13.4, 9.0), Vector2(15.4, 9.2), Vector2(14.8, 3.0), Vector2(2.8, 3.0)][i], "random")
	_prop(P_BONES, Vector2(6.0, 3.6))
	_prop(P_BONES, Vector2(12.0, 12.8))
	_prop(P_WEB_CORNER, Vector2(2.9, 2.6))
	_prop(P_WEB_CORNER, Vector2(15.1, 2.6), true)
	_prop(P_SCONCE, Vector2(5.0, 2.05))
	_prop(P_SCONCE, Vector2(11.0, 2.05))
	_web_blob(Vector2(12.0, 4.6), 1.8, 1.0)
	_trim_floor("rubble-umber")


## The Hoard: Pearl 2 on the brood's altar (Silk; the seal); the loft (L1) on the west side, its front
## flight behind a web wall (the Silk skin's first lock), its doorway west into the Spinning Loft.
func _hoard() -> void:
	_ground_floor(SOIL)
	_level(Rect2i(0, 0, 6, 10), 1)
	_stairs(Rect2i(3, 10, 2, 1))
	_planks(Rect2i(2, 2, 4, 8))
	_opening("s", 7, "doorway")
	_opening("w", 7, "doorway")
	_room_door("hoard-south", "s", 7, "b5-wardens-den", "b5-north")
	_room_door("hoard-west-loft", "w", 7, "b6-spinning-loft", "b6-east")
	_spawn(Vector2(8.0, 12.0))
	_object("web-wall", "hoard-stair-web", Vector2(4.0, 11.0) * CELL, {"height": 110.0,
		"flag_id": "weaver-hollow.hoard-stair-web"})
	_prop(OBJ + "weaver-hollow/brood-altar.tscn", Vector2(11.5, 7.0))
	var pearl := _object("pearl-two", "hoard-pearl-two", Vector2(11.5, 6.0) * CELL, {"take_radius": 90.0})
	_root.set_editable_instance(pearl, true)
	(pearl.get_node("Visual") as Sprite2D).texture = load(PEARL_ART)
	var glow := _variant("hoard-pearl-glow", "pearl.orb-weaver-matron", false)
	for i in 2:
		var glint := (load(KIT + "prize-glint.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		glint.name = "hoard-pearl-glint-%d" % i
		glint.position = (Vector2(11.0, 5.4) if i == 0 else Vector2(12.2, 6.6)) * CELL
		glint.set(&"tint", Color(0.86, 0.8, 1.0))
		glint.set(&"lit_strength", 0.9)
		glint.set(&"phase", 0.6 * i)
		glow.add_child(glint)
	_ground_rect(Rect2i(9, 5, 5, 4), GRASS)
	_ground_rect(Rect2i(7, 9, 2, 5), GRAVEL)
	_ground_rect(Rect2i(9, 9, 2, 1), GRAVEL)
	# the brood's hoard: wrapped prey, eggs, the Guard's old chests, silk
	_prop(OBJ + "interiors/storage/interior-storage-chest-banded-closed-s.tscn", Vector2(13.8, 12.6))
	_prop(OBJ + "interiors/storage/interior-storage-chest-wood-open-s.tscn", Vector2(15.0, 12.8))
	_prop(OBJ + "interiors/decor/interior-decor-coin-purse.tscn", Vector2(12.6, 12.9))
	_prop(P_PEG_RAIL, Vector2(3.6, 2.05))
	_prop(P_SPOOL, Vector2(5.0, 8.6))
	_prop(P_SCONCE, Vector2(10.0, 2.05))
	_prop(P_SCONCE, Vector2(13.0, 2.05))
	_prop(P_WEB_CORNER, Vector2(15.1, 2.6), true)
	_prop(P_MOTH, Vector2(11.5, 4.4))
	_trim_floor("rubble-umber")


## B6 the Spinning Loft: the whole room up among the boughs (planks, reached only from the Rafter Run):
## two rows of web walls from wall to
## wall part it into three corridors, a Slime Spider in two, key 3 in a silk parcel at the north
## corridor's east end; in from the Hoard's loft (east, the middle corridor), out onto B2's rafters
## (south, the south corridor).
func _b6() -> void:
	# no levels inside: the whole room is reached only from upper walks, and a room door's scroll keeps
	# the walk's level on either side (a room painted wholly level 1 held the slime at its south door)
	_ground_floor(PLANKS)
	_opening("e", 7, "doorway")
	_opening("s", 9, "doorway")
	_room_door("b6-east", "e", 7, "hoard", "hoard-west-loft")
	_room_door("b6-south", "s", 9, "b2-drawbridge", "b2-north-rafters")
	_spawn(Vector2(14.0, 8.0))
	for row in 2:
		for i in 7:
			_object("web-wall", "b6-web-%d-%d" % [row, i], Vector2(3 + i * 2, 6 if row == 0 else 10) * CELL,
				{"height": 104.0, "flag_id": "weaver-hollow.b6-web-%d-%d" % [row, i]})
	_object("silk-parcel", "b6-key-parcel", Vector2(14.4, 4.2) * CELL, {"flag_id": "weaver-hollow.b6-key-parcel",
		"contents": {"dungeon-small-key": 1}})
	_enemy("b6-slime-spider-1", "slime-spider", Vector2(6.0, 4.0), 140.0)
	_enemy("b6-slime-spider-2", "slime-spider", Vector2(10.0, 12.0), 140.0)
	_prop(OBJ + "weaver-hollow/loft-rafter.tscn", Vector2(4.6, 2.05))
	_prop(P_PEG_RAIL, Vector2(9.0, 2.05))
	_prop(OBJ + "weaver-hollow/loft-rafter.tscn", Vector2(12.6, 2.05))
	_prop(P_SPOOL, Vector2(2.9, 8.6))
	_prop(OBJ + "weaver-hollow/loft-spinning-wheel.tscn", Vector2(14.6, 12.6))
	_prop(OBJ + "interiors/workshop/interior-workshop-basket-yarn.tscn", Vector2(3.0, 12.8))
	_prop(OBJ + "interiors/workshop/interior-workshop-cloth-bolt-rack.tscn", Vector2(6.0, 12.6))
	_prop(P_WEB_CORNER, Vector2(2.9, 2.6))
	_prop(P_SCONCE, Vector2(7.0, 2.05))
	_trim_floor("rubble-umber")


## B7 the Pillar: the optional wing's end, as today: the near shore (south-west), a parapet over the
## void with a chain of blast kegs, the last beside the pillar's cracked post on the parapet's end; the
## post holds the drawbridge on the far shore (north), whose chest holds coins and a potion.
func _b7() -> void:
	_ground_floor(SOIL)
	_level(Rect2i(2, 6, 14, 2), -2)
	_level(Rect2i(2, 8, 5, 1), -2)
	_level(Rect2i(13, 8, 3, 1), -2)
	_level(Rect2i(2, 9, 14, 1), -2)
	_level(Rect2i(8, 10, 8, 4), -2)
	_opening("w", 11, "doorway")
	_room_door("b7-west", "w", 11, "b4-nursery", "b4-east")
	_spawn(Vector2(4.0, 12.0))
	_kit("hazard", "b7-void", Vector2(2, 6) * CELL, {"kind": "void", "size": Vector2(14, 8) * CELL, "level": -2,
		"pit_depth": 2, "draw_look": false})
	var keg_at: Array[float] = [7.5, 8.75, 10.0, 11.25]
	for i in keg_at.size():
		_object("blast-keg", "b7-keg-%d" % i, Vector2(keg_at[i], 8.6) * CELL)
	var bridge := _kit("drawbridge", "b7-bridge", Vector2(4, 6) * CELL, {"toward": "south", "length": 4,
		"width": 128.0, "bridge_id": "weaver-hollow-b7-bridge"})
	var top := Node2D.new()
	top.name = "b7-bridge-top"
	top.position = Vector2(4, 6) * CELL + Vector2(0, -150)
	_objects.add_child(top)
	_object("winch-post-cracked", "b7-pillar-post", Vector2(12.6, 8.6) * CELL, {"flag_id": "weaver-hollow.b7-pillar-post",
		"target_path": NodePath("../" + String(bridge.name)), "chain_end": NodePath("../b7-bridge-top")})
	_chest("b7-pillar-chest", Vector2(12.5, 3.6), {"coins": 40, "energy-potion": 1})
	_pot("b7-pot", Vector2(2.8, 12.8), "random")
	_prop(P_BROKEN_PILLAR, Vector2(14.6, 3.4))
	_prop(P_BROKEN_PILLAR, Vector2(2.8, 3.4))
	_prop(P_BARREL_STACK, Vector2(6.0, 12.8))
	_prop(P_SCONCE, Vector2(9.0, 2.05))
	_prop(P_WEB_CORNER, Vector2(15.1, 2.6), true)
	_moss_bed(Vector2(4.4, 3.6), 1.2, 5, 27)
	_trim_floor("rubble-umber")


## D2 the Dark Bough, as today: dark (the Lantern), three candles that, all lit, light it for good and
## bring its chest (today's record kept, so it cannot be had twice).
func _d2() -> void:
	_ground_floor(SOIL)
	_opening("e", 7, "doorway")
	_room_door("d2-east", "e", 7, "b1-bough-stair", "b1-west")
	_spawn(Vector2(13.0, 8.0))
	var candles: Array[NodePath] = []
	for i in 3:
		var candle := Node2D.new()
		candle.name = "d2-candle-%d" % i
		candle.y_sort_enabled = true
		candle.position = Vector2(5.5 + i * 3.5, 6.5) * CELL
		candle.set_script(load(CANDLE))
		candle.set(&"unlit_scene", load(OBJ + "interiors/decor/interior-decor-candlestick-unlit.tscn"))
		candle.set(&"lit_scene", load(OBJ + "interiors/decor/interior-decor-candlestick-lit.tscn"))
		candle.set(&"flame_offset", Vector2(0, -60))
		_objects.add_child(candle)
		candles.append(NodePath("../../Objects/" + String(candle.name)))
	var shown := _variant("d2-chest-variant", "weaver-hollow.dark-bough-lit", true)
	var chest := (load(KIT + "dungeon-chest.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	chest.name = "d2-dark-bough-chest"
	chest.position = Vector2(9.0, 10.0) * CELL
	chest.set(&"contents", {"coins": 20, "hp-potion": 1})
	chest.set(&"chest_id", "weaver-hollow-boughs-dark-bough-chest")
	chest.set(&"map_id", "weaver-hollow-boughs")
	shown.add_child(chest)
	var dark := Node2D.new()
	dark.name = "DarkRooms"
	_root.add_child(dark)
	var room := Node2D.new()
	room.name = _name
	room.set_script(load(DARK_ROOM))
	room.set(&"size", Vector2(_cols * CELL, _rows * CELL))
	room.set(&"candles", candles)
	room.set(&"lit_for_good_when_all_lit", true)
	room.set(&"lit_flag", "weaver-hollow.dark-bough-lit")
	dark.add_child(room)
	_prop(P_BARREL_STACK, Vector2(3.0, 2.7))
	_prop(P_BROKEN_CRATES, Vector2(14.6, 12.6))
	_prop(P_ROOT_HUMP, Vector2(3.6, 11.6))
	_prop(P_BONES, Vector2(12.0, 3.4))
	_prop(P_WEB_CORNER, Vector2(2.9, 2.6))
	_prop(P_GLOW_WORM, Vector2(10.0, 12.0))
	_trim_floor("rubble-umber")


# --- the layout ----------------------------------------------------------------------------------

# --- the Crown (the last piece of step 3, 2026-11-25) ----------------------------------------------

## C1 the Crown Stair: up from the hub's Crown Door (south, L0) through floor webs wall to wall, the
## front flight at row 8 choked by a web wall (the Silk skin: wade it, or cut it for good), to the
## top (L1, planks): the key 3 door north and four pots, the calm spot before her.
func _c1() -> void:
	_ground_floor(SOIL)
	_level(Rect2i(0, 0, 18, 8), 1)
	_stairs(Rect2i(8, 8, 2, 1))
	_planks(Rect2i(2, 2, 14, 6))
	_opening("s", 8, "doorway")
	_opening("n", 8, "key1")
	_room_door("c1-south", "s", 8, "t2-hollow-heart", "t2-north-crown")
	_room_door("c1-north", "n", 8, "c2-crown", "c2-south")
	_wall_door("key-door", "c1-k3-door", "n", 8, "key1", {"door_id": "weaver-hollow-k3-door", "keyholes": 1})
	_spawn(Vector2(9.0, 12.0))
	_object("web-wall", "c1-stair-web", Vector2(9.0, 9.4) * CELL, {"height": 128.0,
		"flag_id": "weaver-hollow.c1-stair-web"})
	for y in range(10, 14):
		for x in range(2, 16):
			_webs.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	_pot("c1-pot-1", Vector2(4.0, 3.4), "heart")
	_pot("c1-pot-2", Vector2(5.2, 4.4), "energy")
	_pot("c1-pot-3", Vector2(12.8, 4.4), "heart")
	_pot("c1-pot-4", Vector2(14.0, 3.4), "energy")
	_prop(P_SCONCE, Vector2(6.0, 2.05))
	_prop(P_SCONCE, Vector2(12.0, 2.05))
	_prop(P_PEG_RAIL, Vector2(3.4, 2.05))
	_prop(P_SPOOL, Vector2(15.0, 5.6))
	_prop(P_SACKS, Vector2(2.9, 6.4))
	_prop(P_WEB_CORNER, Vector2(15.1, 2.6), true)
	_prop(P_ROOT_HUMP, Vector2(3.2, 12.6))
	_prop(P_ROOT_HUMP, Vector2(14.8, 12.4), true)
	_prop(P_POST_ROOT, Vector2(4.0, 9.6))
	_prop(P_POST_ROOT, Vector2(14.0, 9.6))
	_prop(P_BONES, Vector2(12.0, 12.8))
	_prop(P_GLOW_CLUSTER, Vector2(2.6, 10.6))
	_prop(P_GLOW_TALL, Vector2(15.3, 10.8))
	_prop(P_FIREFLY, Vector2(6.0, 11.0))
	_trim_floor("rubble-umber")


## C2 the Crown: the Matron's ram fight, **the Matron lab's arena at the lab's own coordinates**
## (game/dev/bosses/matron-lab.tscn as the owner steered it, docs/godot/specs/matron.md section 9):
## the same room (24 x 20 cells), five rams, each knock target straight below its lane, her camp at
## the lab's spot with the lab's arena and wake shapes, the twelve pots where the lab has them. So
## tools/film_matron.gd's films run here as in the lab (tools/film_crown.gd). The way in (south, from
## C1's key 3 door) is where the lab's slime starts, between targets 2 and 3, its boss shutter shut
## while she lives; the seal in the east wall (rows 9-10) to C3.
func _c2() -> void:
	_ground_floor(SOIL)
	_opening("s", 9, "shutter")
	_opening("e", 9, "seal")
	_room_door("c2-south", "s", 9, "c1-crown-stair", "c1-north")
	_room_door("c2-east", "e", 9, "c3-outer-bough", "c3-west")
	var shutter := _wall_door("shutter", "c2-crown-shutter", "s", 9, "shutter", {"shutter_id": "weaver-hollow-crown-shutter"})
	_wall_door("dungeon-seal", "c2-east-seal", "e", 9, "seal", {"ring_color": Color("#9a5ad8")})
	_spawn(CROWN_SPAWN / CELL)
	for i in CROWN_RAM_X.size():
		var ram := _kit("ram", "ram-%d" % (i + 1), Vector2(CROWN_RAM_X[i], CROWN_RAM_Y), {"toward": "south",
			"length": CROWN_RAM_LENGTH, "ram_id": "weaver-hollow-c2-ram-%d" % (i + 1)})
		var targets: Array[NodePath] = [NodePath("../" + String(ram.name))]
		_kit("knock-target", "target-%d" % (i + 1), Vector2(CROWN_RAM_X[i], CROWN_TARGET_Y),
			{"target_id": "weaver-hollow-c2-target-%d" % (i + 1), "targets": targets})
	var camp := _instance(CAMP, "matron-camp", CROWN_CAMP, _objects)
	_root.set_editable_instance(camp, true)
	var script_node := camp.get_node("BossCampScript")
	script_node.set(&"map_id", PREFIX + _name)
	script_node.set(&"camp_id", "weaver-hollow-matron")
	script_node.set(&"boss_id", "orb-weaver-matron")
	script_node.set(&"boss_scene", "character.orb-weaver-matron-rework")
	script_node.set(&"respawn_ms", -1.0)
	script_node.set(&"spawn", Vector2(0.0, -30.0))
	script_node.set(&"boss_overrides", {"arena_recovery_ms": 0.0, "cocoon_enabled": true})
	_shape(camp.get_node("ActivationArea/ActivationShape"), Vector2(0.0, -80.0), Vector2(1280.0, 864.0))
	_shape(camp.get_node("ArenaArea/ArenaShape"), Vector2.ZERO, Vector2(1280.0, 1024.0))
	(camp.get_node("FullHeart") as Node2D).position = Vector2.ZERO
	(camp.get_node("MatronThread") as Node2D).position = Vector2(-588.8, -422.4)
	var camp_script := camp.get_node("BossCampScript")
	camp_script.connect(&"boss_engaged", Callable(shutter, &"shut"), CONNECT_PERSIST)
	camp_script.connect(&"boss_defeated", Callable(shutter, &"open"), CONNECT_PERSIST)
	for i in CROWN_POTS.size():
		var pot: Array = CROWN_POTS[i]
		_pot("pot-%d" % (i + 1), Vector2(float(pot[0]), float(pot[1])) / CELL, str(pot[2]))
	# her nest, off every lane and away from the targets: silk on the north wall between the gantries,
	# sconces, a web in the north-east corner, the bones of her prey along the side strips. No cocoon
	# or egg sac for show (the Hollow's clarity rule: her cocoon is a lock), no floor webs (the lab's
	# floor is bare: they would slow the slime in her fight).
	_prop(P_SCONCE, Vector2(6.35, 2.05))
	_prop(P_PEG_RAIL, Vector2(10.1, 2.05))
	_prop(P_PEG_RAIL, Vector2(13.9, 2.05))
	_prop(P_SCONCE, Vector2(17.65, 2.05))
	_prop(P_BONES, Vector2(2.6, 15.0))
	_prop(P_BONES, Vector2(21.4, 11.6))
	_prop(P_GLOW_CLUSTER, Vector2(2.6, 5.4))
	_prop(P_GLOW_TALL, Vector2(21.4, 5.6))
	_prop(P_ROOT_HUMP, Vector2(21.3, 15.2), true)
	_mf("moss-2", Vector2(2.7, 10.4))
	_mf("pebbles-1", Vector2(21.3, 8.4))
	_mf("leaves-fallen", Vector2(6.35, 12.0))
	_mf("root-5", Vector2(17.65, 11.4))
	_prop(P_WEB_CORNER, Vector2(21.1, 2.6), true)
	_trim_floor("rubble-umber")


## C3 the Outer Bough (18 x 8): a timber walk out along a bough, past the sunk seal (west, rows 3-4);
## her web wall across the walk at col 6, wall to wall (wade or cut it: the Silk skin), and the open
## hole at the walk's east end, in the bark: the drop out to the forecourt, by S1's nook.
func _c3() -> void:
	_ground_floor(PLANKS)
	_opening("w", 3, "doorway")
	_room_door("c3-west", "w", 3, "c2-crown", "c2-east")
	_spawn(Vector2(3.6, 4.0))
	_object("web-wall", "c3-web-wall", Vector2(6.0, 4.0) * CELL, {"orientation": "side", "span": 256.0,
		"height": 200.0, "flag_id": "weaver-hollow.c3-web-wall"})
	var hole := _object("open-hole", "c3-drop", Vector2(13.5, 4.0) * CELL)
	_root.set_editable_instance(hole, true)
	var door := hole.get_node("DoorScript")
	door.set(&"map_id", PREFIX + _name)
	door.set(&"door_id", PREFIX + "c3-drop")
	door.set(&"target_area_id", "gloop-forest-f4")
	door.set(&"target_door_id", "weaver-hollow-silk-drop")
	# the bark round the hole: packed earth (the hole is cut in it, not in the timber)
	_ground_rect(Rect2i(12, 2, 4, 4), SOIL)
	_prop(P_WALL_ROOTS, Vector2(3.4, 2.2))
	_prop(P_ROOTS_HANGING, Vector2(9.0, 2.2))
	_prop(P_MOSS_OVERHANG, Vector2(11.4, 2.15))
	_prop(P_WEB_CORNER, Vector2(15.1, 2.6), true)
	_prop(P_SCONCE, Vector2(14.2, 2.05))
	_prop(P_GLOW_CLUSTER, Vector2(15.3, 5.4))
	_prop(P_ROOT_HUMP, Vector2(9.4, 5.5))
	_mf("leaves-fallen", Vector2(4.4, 5.2))
	_mf("twigs", Vector2(8.2, 3.0))
	_mf("leaf-big", Vector2(10.6, 4.8))
	_mf("moss-2", Vector2(12.2, 5.4))
	_prop(P_FIREFLY, Vector2(10.0, 3.4))
	_pot("c3-pot", Vector2(2.8, 5.3), "heart")
	_trim_floor("rubble-umber")


## A RectangleShape2D of `size` on the CollisionShape2D `holder`, at `at` (its parent's space).
func _shape(holder: Node, at: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	holder.set(&"shape", shape)
	(holder as Node2D).position = at


func _write_layout() -> Error:
	if FileAccess.file_exists(LAYOUT_PATH) and not _force:
		print("weaver hollow rooms: %s exists and is hand-edited; not overwritten (-- --force)" % LAYOUT_PATH)
		return OK
	var layout := Node2D.new()
	layout.name = "weaver-hollow-layout"
	layout.set_script(load(LAYOUT_SCRIPT))
	for room: String in ROOMS:
		var plan: Array = ROOMS[room]
		var node := Node2D.new()
		node.name = room
		node.set_script(load(LAYOUT_ROOM))
		node.position = plan[3]
		node.set(&"room_scene", DIR + room + ".tscn")
		node.set(&"world_id", PREFIX + room)
		node.set(&"room_name", room)
		node.set(&"size", Vector2(int(plan[0]) * CELL, int(plan[1]) * CELL))
		if int(plan[2]) != 0:
			node.set(&"floor_level", int(plan[2]))
		layout.add_child(node)
		node.owner = layout
	var before := FileAccess.get_file_as_string(LAYOUT_PATH) if FileAccess.file_exists(LAYOUT_PATH) else ""
	var err := SceneSave.save(layout, LAYOUT_PATH, before)
	print("weaver hollow rooms: ", LAYOUT_PATH, " ", error_string(err))
	layout.free()
	return err
