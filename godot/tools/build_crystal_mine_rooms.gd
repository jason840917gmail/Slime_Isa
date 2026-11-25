extends SceneTree
## Lays the FIRST VERSION of the rebuilt Crystal Mine's rooms (step 4 of the dungeons rework,
## docs/design/2026-11-23-dungeons-2-3-rework.md "The Crystal Mine"; the wings and the list of links:
## docs/handover/2026-11-23-dungeons-rework.md "Step 4: the Mine"), one room world each, as the
## rebuilt Weaver Hollow is (tools/build_weaver_hollow_rooms.gd): the crystal-cave interior walls (a
## two-cell rim) with their openings, the crystal studs floor trim, a cavern floor painted on the
## ground with crystal and gravel patches, the raised floors and voids on the `elevation` layer,
## painted vines, the room doors, the locks, the prizes, the enemies and the dressing.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_crystal_mine_rooms.gd -- --room=<name>[,<name>...] | --all [--layout] [--force]
## Rooms (wing 1, the Mouth and the High Line): m1-mine-mouth, m2-lamp-tunnel, m4-great-shaft,
## m6-bat-gallery, m7-ore-store; (wing 2, the Lantern's half) m5-tally-room, m3-survey-office,
## m8-dark-maze, m9-the-chasm; (wing 3, the Den and the Feral half) m13-shardback-den, m11-crystal-veil,
## m10-prism-gallery, m12-fort-hall (its walls the fort's stone). Each is written to
## res://game/scenes/worlds/rooms/crystal-mine-rooms/<name>.tscn (world `crystal-mine-<name>`);
## `--layout` (or a missing layout) writes the map layout `layout.tscn` too, with the rooms listed
## here (a room door into a room not on it never travels).
##
## **THE SCENES ARE HAND-EDITED AFTERWARDS** (the owner, 2026-10-18: content lives in hand-edited
## scenes; a tool writes a room's first version only). This tool refuses to overwrite a room scene (or
## the layout) that exists unless given `--force`, which throws the hand edits away: edit the scenes
## in the editor instead. After writing a room with elevation, bake its cache
## (`tools/bake_elevation.gd -- --world=crystal-mine-<name>`), or let the next run from the project do it.
##
## Owner: dungeons (the Crystal Mine).

const SceneSave := preload("res://tools/lib/scene_save.gd")
const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")

const DIR := "res://game/scenes/worlds/rooms/crystal-mine-rooms/"
const LAYOUT_PATH := DIR + "layout.tscn"
const PREFIX := "crystal-mine-"
## Today's Mine's record id: chests keep today's records under it (docs/godot/DUNGEONS.md).
const RECORD := "crystal-mine"
const STYLE := "crystal-cave"
## The floor trim along the walls: crystal studs in crystal blue (INTERIOR_WALLS.md "Crystal cave").
const TRIM := "crystal-crystal"
const CELL := 64
const DEPTH := 2
const SHEET := 19
## terrain_tileset.tres sources: the cavern floor, the crystal floor, the gravel path.
const CAVERN := 1
const CRYSTAL := 2
const GRAVEL := 21
## The interior wood floor (one tile): the crate loft's boards.
const PLANKS := 12

const TERRAIN := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const INTERIOR_TILES := "res://game/world/interior/interior_wall_tileset.tres"
const INTERIOR_LAYER := "res://game/world/interior/interior_wall_layer.gd"
const TRIM_TILES := "res://game/world/interior/interior_trim_tileset.tres"
const TRIM_LAYER := "res://game/world/interior/interior_trim_layer.gd"
const ELEVATION_TILES := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const VINE_TILES := "res://game/world/vines/vine_tileset.tres"
const VINE_LAYER := "res://game/world/vines/vine_layer.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CAMERA_ROOM := "res://game/world/camera_room.gd"
const ROOM_SCENE := "res://game/dungeon/room_scene.gd"
const DOOR := "res://game/scripts/door.gd"
const DARK_ROOM := "res://game/world/darkness/dark_room.gd"
const CANDLE := "res://game/world/fire/candle.gd"
const RAILS := "res://game/crystal_mine/mine_rails.gd"
const SHEET_SPRITE := "res://game/runtime/sheet_sprite.gd"
const SOFT_GLOW := "res://game/prologue/soft_glow.gd"
const SFX_PLAYER := "res://game/runtime/sfx_player.gd"
const MUSIC := "res://asset/audio/music/dungeon.wav"
const DUNGEON := "res://game/scenes/objects/dungeon/crystal-mine-dungeon.tscn"
const LAYOUT_SCRIPT := "res://game/dungeon/dungeon_layout.gd"
const LAYOUT_ROOM := "res://game/dungeon/layout_room.gd"
const KIT := "res://game/scenes/objects/dungeon/"
const OBJ := "res://game/scenes/objects/"
const PLACED_ENEMY := "res://game/scenes/encounters/placed-enemy.tscn"
const LANTERN_ART := "res://asset/MAPS/props/mine/128x128-mine-lantern.webp"
const CART_ART := "res://asset/MAPS/props/mine/256x256-mine-cart.webp"

## The dressing (the Scenery dock's props): the mine's timbers, ore and tools, crystals, cave life.
const P_LUMBER := OBJ + "interiors/workshop/interior-workshop-lumber-stack.tscn"
const P_ORE_BASKET := OBJ + "interiors/workshop/interior-workshop-ore-basket.tscn"
const P_WHEELBARROW := OBJ + "interiors/workshop/interior-workshop-wheelbarrow.tscn"
const P_TOOL_RACK := OBJ + "interiors/workshop/interior-workshop-tool-rack.tscn"
const P_TOOLBOX := OBJ + "interiors/workshop/interior-workshop-toolbox.tscn"
const P_BARREL := OBJ + "interiors/storage/interior-storage-barrel.tscn"
const P_BARREL_OPEN := OBJ + "interiors/storage/interior-storage-barrel-open.tscn"
const P_CRATE := OBJ + "interiors/storage/interior-storage-crate.tscn"
const P_CRATE_BANDED := OBJ + "interiors/storage/interior-storage-crate-banded.tscn"
const P_SACK := OBJ + "interiors/storage/interior-storage-sack-grain.tscn"
const P_ORE_HEAP := OBJ + "ore-heap.tscn"
const P_ROCK_STUMP := OBJ + "rock-stump.tscn"
const P_BROKEN_CRATES := OBJ + "dungeon-decor/broken-crates.tscn"
const P_STALAGMITES := OBJ + "dungeon-decor/stalagmites.tscn"
const P_BONES := OBJ + "dungeon-decor/bone-pile.tscn"
const P_CHAINS := OBJ + "dungeon-decor/hanging-chains.tscn"
const P_BRAZIER := OBJ + "brazier-lit.tscn"
const P_CRYSTALS := OBJ + "crystal-cluster-wall--%02d.tscn"
const P_GLOW_WORM := OBJ + "cave-animals/glow-worm.tscn"
const P_SNAIL := OBJ + "cave-animals/crystal-snail.tscn"
const P_MOTH := OBJ + "cave-animals/lantern-moth.tscn"
const P_NEWT := OBJ + "cave-animals/cave-newt.tscn"
const P_PILL_BUG := OBJ + "cave-animals/pill-bug.tscn"
const P_FIREFLY := OBJ + "cave-animals/firefly.tscn"
const P_DESK := OBJ + "interiors/workshop/interior-workshop-writing-desk.tscn"
const P_WORKBENCH := OBJ + "interiors/workshop/interior-workshop-workbench.tscn"
const P_SCROLLS := OBJ + "interiors/workshop/interior-workshop-scroll-rack.tscn"
const P_PAPERS := OBJ + "interiors/workshop/interior-workshop-paper-stack.tscn"
const P_CANDLE_LIT := OBJ + "interiors/decor/interior-decor-candlestick-lit.tscn"
const P_BANNER := OBJ + "interiors/decor/interior-decor-banner-red-narrow.tscn"
const P_PILLAR := OBJ + "interiors/structure/interior-structure-pillar-stone.tscn"
const P_WEAPON_RACK := OBJ + "dungeon-decor/weapon-rack.tscn"
const P_BARREL_STACK := OBJ + "dungeon-decor/barrel-stack.tscn"
const P_ARMOR_STAND := OBJ + "interiors/workshop/interior-workshop-armor-stand.tscn"
const MINE_SHAFT_PICTURE := "res://asset/MAPS/interiors/mine-shaft.res"
## The ore lift between M4's gallery and M14 (today's lift's id: an old save that worked today's lift
## finds this one working; ore_lift.gd keeps it under the dungeon's record).
const LIFT_ID := "great-shaft-lift"
## M15 is the Colossus lab's world carried over as it is (game/dev/bosses/colossus-lab.tscn, built by
## tools/build_colossus_lab.gd): every node at the lab's coordinates; the room adds the mine's pieces.
const COLOSSUS_LAB := "res://game/dev/bosses/colossus-lab.tscn"
const COLOSSUS_ID := "crystal-colossus"
const COLOSSUS_CAMP := "crystal-mine-colossus"
## The lab's nook (cells): the way in, cut on through the south rock to the room's edge (its last row).
const M15_NOOK := Rect2i(12, 21, 2, 3)
## The lab's elevation tile for its floor (level -1) and its ground's cavern floor.
const LAB_FLOOR_TILE := Vector2i(2, 0)
## The climb out (today's M15-root-wall's numbers) at the north wall's east end, clear of his four
## claw roots and the east dip; the seal at its foot (today's: 16 above the roots' foot).
const M15_CLIMB_OUT := Vector2(1344.0, 340.0)
const M15_CLIMB_TOP := Vector2(0, -312)
const M15_CLIMB_ART := Vector2(104, 300)
## His full heart, on the floor's middle north of the lower line.
const M15_HEART := Vector2(832.0, 640.0)
const FULL_HEART_ART := "res://asset/MAPS/props/256x256-tile_8x1-gulp-props.webp"
const FULL_HEART := "res://game/scripts/full_heart.gd"
const MINE := "res://game/crystal_mine/crystal_mine.gd"
## The Shardback (the Den's fight and Pearl 3's guard; his record).
const SHARDBACK_ID := "crystal-mine-shardback"
## The Den's cart line's row (cells).
const DEN_RAIL_Y := 12.6
## terrain_tileset.tres: town cobble (the Fort Hall's floor).
const COBBLE := 19
## Rooms in another wall style than the crystal cave's: [style, floor trim].
const ROOM_STYLES := {"m12-fort-hall": ["lair-stone", "framed-cream"]}

## The rooms: name -> [columns, rows, the map's floor, its place on the layout] (wing 1).
const ROOMS := {
	"m1-mine-mouth": [18, 16, 0, Vector2(1152, 4096)],
	"m2-lamp-tunnel": [18, 16, 0, Vector2(1152, 3072)],
	"m4-great-shaft": [36, 16, 0, Vector2(1152, 2048)],
	"m6-bat-gallery": [36, 16, 0, Vector2(2304, 3072)],
	"m7-ore-store": [36, 16, 0, Vector2(2304, 4096)],
	# wing 2, the Lantern's half
	"m5-tally-room": [18, 16, 0, Vector2(0, 3072)],
	"m3-survey-office": [18, 16, 0, Vector2(0, 2048)],
	"m8-dark-maze": [36, 32, 0, Vector2(0, 0)],
	"m9-the-chasm": [18, 16, 0, Vector2(2304, 0)],
	# wing 3, the Den and the Feral half
	"m13-shardback-den": [18, 16, 0, Vector2(2304, 1024)],
	"m11-crystal-veil": [18, 16, 0, Vector2(3456, 1024)],
	"m10-prism-gallery": [18, 16, 0, Vector2(3456, 0)],
	"m12-fort-hall": [18, 16, 0, Vector2(4608, 1024)],
	# wing 4, the Shaft and the Colossus (floor -1): the shaft's floor under the Den's rim, the arena
	# north of it, its way in (the lab's nook) above M14's boss door
	"m14-shaft-floor": [18, 16, -1, Vector2(2304, 2048)],
	"m15-colossus-arena": [26, 24, -1, Vector2(1984, 512)],
}
const LEVEL_TILE := {-3: Vector2i(0, 0), -2: Vector2i(1, 0), -1: Vector2i(2, 0), 1: Vector2i(3, 0), 2: Vector2i(4, 0)}
const STAIRS_S := Vector2i(0, 1)
const PIT_DEPTH := "res://game/dungeon/pit_depth.gd"
const STORY_VARIANT := "res://game/scripts/story_variant.gd"
## The runaway cart's line in M7 and its arrival in M1 (one record, `cart_id`), and the rail gate
## between them (one record on both sides, `gate_id`).
const ORE_CART_ID := "crystal-mine-ore-cart"
const ORE_GATE_ID := "crystal-mine-ore-gate"
## Today's flag on the rotten timbers (an old save keeps them smashed).
const TIMBERS_FLAG := "crystal-mine.rotten-timbers"
## The Dark Maze's crystal partitions (cells: x, y, w, h), drawn as crystal clusters at this size (their
## collision then closes each cell to the 30-wide slime), and how long each of its four candles burns:
## the walked way from the first to the last in the best order is 128 cells (8192 units, 45.5 s at the
## slime's 180 units a second; the faces' footprint counted as whole cells), with the Lantern held on the
## north-west candle's Gloomling and four flames about 50 s; 90 s leaves room for wrong turns (docs/handover "Step 4", wing 2's fix round).
const MAZE_PARTITIONS: Array[Rect2i] = [Rect2i(2, 7, 3, 1), Rect2i(5, 2, 1, 4), Rect2i(22, 2, 1, 5),
	Rect2i(2, 12, 3, 1), Rect2i(3, 17, 3, 1), Rect2i(2, 22, 3, 1), Rect2i(28, 20, 1, 3), Rect2i(29, 24, 5, 1),
	Rect2i(22, 24, 1, 2), Rect2i(13, 26, 9, 1), Rect2i(14, 4, 1, 4), Rect2i(29, 12, 1, 4)]
## The maze's void (cells): small enough that the raised walls' faces and its own rim leave corridors.
const MAZE_VOID := Rect2i(14, 14, 8, 9)
const PARTITION_SIZE := 1.25
const MAZE_CANDLE_MS := 90000.0
## Today's flag on the Tally Room's cracked wall to the Survey Office (both sides).
const SURVEY_FLAG := "crystal-mine.survey-wall"
## The ore rails' row in M1 and M7 (the doorway between them, rows 6-7: its middle).
const RAIL_Y := 7.0

var _force := false
var _name := ""
var _cols := 0
var _rows := 0
var _root: Node2D
var _walls: TileMapLayer
var _elevation: TileMapLayer
var _vines: TileMapLayer
var _trim: TileMapLayer
var _objects: Node2D
var _scenery: Node2D
var _enemies: Node2D
var _doors: Node2D
var _rails: Node2D
## Floor cells kept clear of the trim (in front of openings, holes, stairs).
var _clear := {}
var _wall_tiles := {}
var _trim_tiles := {}
## Every style's wall tiles (style -> opening kind -> palette cell), and this room's style and trim.
var _style_tiles := {}
var _style := STYLE
var _trim_name := TRIM


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
		push_error("build_crystal_mine_rooms: --room=<name>[,...] | --all [--layout] [--force]; rooms: " + ", ".join(ROOMS.keys()))
		quit(1)
		return
	_read_palettes()
	if not _trim_tiles.has(TRIM) or not _wall_tiles.has("key2") or not _wall_tiles.has("seal"):
		push_error("build_crystal_mine_rooms: the crystal-cave sheet has no door leaves or trim %s (scripts/art/pack-interior-walls.py crystal-cave)" % TRIM)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var failed := false
	if layout or not FileAccess.file_exists(LAYOUT_PATH):
		failed = _write_layout() != OK
	for room: String in names:
		if not ROOMS.has(room):
			push_error("build_crystal_mine_rooms: no room " + room)
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
		var style := str(data.get_custom_data(InteriorWalls.STYLE_DATA))
		if not _style_tiles.has(style):
			_style_tiles[style] = {}
		_style_tiles[style][str(data.get_custom_data(InteriorWalls.OPENING_DATA))] = coords
	_wall_tiles = _style_tiles.get(STYLE, {})
	var trim_set := load(TRIM_TILES) as TileSet
	var trims := trim_set.get_source(0) as TileSetAtlasSource
	for i in trims.get_tiles_count():
		var coords := trims.get_tile_id(i)
		_trim_tiles[str(trims.get_tile_data(coords, 0).get_custom_data("floor_trim"))] = coords


# --- one room ------------------------------------------------------------------------------------

func _build(room: String) -> Error:
	var path := DIR + room + ".tscn"
	if FileAccess.file_exists(path) and not _force:
		print("crystal mine rooms: %s exists and is hand-edited; not overwritten (-- --force throws the edits away)" % path)
		return OK
	var plan: Array = ROOMS[room]
	_name = room
	_cols = int(plan[0])
	_rows = int(plan[1])
	_clear = {}
	var style: Array = ROOM_STYLES.get(room, [STYLE, TRIM])
	_style = str(style[0])
	_trim_name = str(style[1])
	_wall_tiles = _style_tiles.get(_style, {})
	if room == "m15-colossus-arena":
		return _build_m15(path)
	_shell()
	match room:
		"m1-mine-mouth":
			_m1()
		"m2-lamp-tunnel":
			_m2()
		"m4-great-shaft":
			_m4()
		"m6-bat-gallery":
			_m6()
		"m7-ore-store":
			_m7()
		"m5-tally-room":
			_m5()
		"m3-survey-office":
			_m3()
		"m8-dark-maze":
			_m8()
		"m9-the-chasm":
			_m9()
		"m13-shardback-den":
			_m13()
		"m11-crystal-veil":
			_m11()
		"m10-prism-gallery":
			_m10()
		"m12-fort-hall":
			_m12()
		"m14-shaft-floor":
			_m14()
	_trim_floor()
	if _elevation.get_used_cells().is_empty():
		_elevation.free()
	if _vines.get_used_cells().is_empty():
		_vines.free()
	if _rails.get_child_count() == 0:
		_rails.free()
	for child in _root.get_children():
		_own(child)
	var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var err := SceneSave.save(_root, path, before)
	print("crystal mine rooms: ", path, " ", error_string(err))
	_root.free()
	return err


## The room's layers and holders, its rim, its camera room, its world, its Dungeon node and music.
## The floor is the ground layer's cavern floor (the wall layer's own floor off), so crystal and
## gravel patches can be painted over it with their edges.
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
	_walls.set(&"draw_floor", false)
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
	_vines = TileMapLayer.new()
	_vines.name = "vines"
	_vines.tile_set = load(VINE_TILES)
	_vines.set_script(load(VINE_LAYER))
	_root.add_child(_vines)
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
	_rails = Node2D.new()
	_rails.name = "Rails"
	_root.add_child(_rails)
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


## A dark room over the whole room: its `candles` (node names under Objects) light it for good
## once all burn (the story flag `lit_flag`), unless `for_good` is off (a room that stays dark).
func _dark(candles: Array, lit_flag: String, for_good := true) -> void:
	var dark := Node2D.new()
	dark.name = "DarkRooms"
	_root.add_child(dark)
	var room := Node2D.new()
	room.name = _name
	room.set_script(load(DARK_ROOM))
	room.set(&"size", Vector2(_cols * CELL, _rows * CELL))
	var paths: Array[NodePath] = []
	for candle: String in candles:
		paths.append(NodePath("../../Objects/" + candle))
	room.set(&"candles", paths)
	room.set(&"lit_for_good_when_all_lit", for_good)
	room.set(&"lit_flag", lit_flag)
	dark.add_child(room)


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


## Paints an opening (`kind`: doorway, or a closed door's leaf: key1, key2, boss, bolt, shutter,
## seal, barricade) and keeps the two floor cells in front of it clear of the trim.
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


## Paints `level` on every cell of `rect` (cells); a hole's cells keep the cavern floor (the ground
## shows in holes).
func _level(rect: Rect2i, level: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_elevation.set_cell(Vector2i(x, y), 0, LEVEL_TILE[level])
			if level < 0:
				_clear[Vector2i(x, y)] = true
				_ground_rect(Rect2i(x, y, 1, 1), CAVERN)


## A front flight of stairs going down south over `rect`'s cells.
func _stairs(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_elevation.set_cell(Vector2i(x, y), 0, STAIRS_S)
			_clear[Vector2i(x, y)] = true


## Vines (the Feral skin's climb) on `rect`'s cells of a face.
func _vine(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_vines.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
			_clear[Vector2i(x, y)] = true


## `rect`'s cells of the ground layer painted with `source`.
func _ground_rect(rect: Rect2i, source: int) -> void:
	var ground := _root.get_node("ground") as TileMapLayer
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var frame := Vector2i.ZERO if source == PLANKS else Vector2i(posmod(x, SHEET), posmod(y, SHEET))
			ground.set_cell(Vector2i(x, y), source, frame)


## A patch of `source` ground over the cells of a ragged ellipse round `at` (cells), radii `rx`, `ry`
## (the ground's own edge tiles round it: the second floor texture).
func _patch(at: Vector2, rx: float, ry: float, source: int) -> void:
	for y in range(floori(at.y - ry), ceili(at.y + ry) + 1):
		for x in range(floori(at.x - rx), ceili(at.x + rx) + 1):
			if x < DEPTH or y < DEPTH or x >= _cols - DEPTH or y >= _rows - DEPTH:
				continue
			var d := Vector2((x + 0.5 - at.x) / rx, (y + 0.5 - at.y) / ry)
			var ragged := 0.82 + 0.3 * float(posmod(x * 7 + y * 13, 5)) / 4.0
			if d.length() <= ragged:
				_ground_rect(Rect2i(x, y, 1, 1), source)


## The floor trim on every floor cell but the clear ones (the layer draws only the cells beside a
## wall or a level's face).
func _trim_floor() -> void:
	var tile: Vector2i = _trim_tiles[_trim_name]
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
		push_warning("crystal mine rooms: no prop " + path)
		return null
	var node := _instance(path, path.get_file().get_basename().trim_prefix("interior-").trim_prefix("decoration-world-"), at * CELL, _scenery)
	if flip:
		node.scale = Vector2(-size, size)
	elif size != 1.0:
		node.scale = Vector2(size, size)
	return node


## A crystal cluster (`n` of the sixteen) at `at` (cells).
func _crystals(n: int, at: Vector2, flip := false, size := 1.0) -> void:
	_prop(P_CRYSTALS % n, at, flip, size)


## A mine lantern on a wall (cells; its foot at `at`), as today's Mine hangs them.
func _lantern(at: Vector2) -> void:
	var lamp := Sprite2D.new()
	lamp.name = _unique("mine-lantern", _scenery)
	lamp.set_script(load(SHEET_SPRITE))
	lamp.set(&"sheet_path", LANTERN_ART)
	lamp.centered = false
	lamp.offset = Vector2(-64, -124)
	lamp.scale = Vector2(0.5, 0.5)
	lamp.position = at * CELL
	_scenery.add_child(lamp)


## A standing ore cart (solid, dressing), as today's Mine's.
func _ore_cart(at: Vector2, flip := false) -> void:
	var cart := StaticBody2D.new()
	cart.name = _unique("ore-cart", _scenery)
	cart.position = at * CELL
	cart.collision_mask = 0
	_scenery.add_child(cart)
	var shape := CollisionShape2D.new()
	shape.name = "BodyShape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(66, 26)
	shape.shape = rect
	shape.position = Vector2(0, -13)
	cart.add_child(shape)
	var visual := Sprite2D.new()
	visual.name = "Visual"
	visual.set_script(load(SHEET_SPRITE))
	visual.set(&"sheet_path", CART_ART)
	visual.centered = false
	visual.offset = Vector2(-128, -252)
	visual.scale = Vector2(-0.32 if flip else 0.32, 0.32)
	cart.add_child(visual)


## A soft glow over crystals (additive, slow pulse), drawn by game/prologue/soft_glow.gd.
func _glow(at: Vector2, radius: Vector2, color: Color) -> void:
	var glow := Node2D.new()
	glow.name = _unique("crystal-glow", _scenery)
	glow.set_script(load(SOFT_GLOW))
	glow.position = at * CELL
	glow.set(&"radius", radius)
	glow.set(&"color", color)
	glow.set(&"additive", true)
	glow.set(&"pulse", 0.2)
	glow.set(&"period_s", 5.0)
	glow.z_index = 3
	_scenery.add_child(glow)


## The void's hazard over the hole painted at `rect` (cells; a fall costs health and puts the slime
## back), its flat abyss off, and its depth look (game/dungeon/pit_depth.gd) over the hole's floor,
## under the room's faces round it (z -2, next after the ground in the tree). Returns the look.
func _pit(node_name: String, rect: Rect2i, pattern: int) -> Node2D:
	_kit("hazard", node_name, Vector2(rect.position) * CELL, {"kind": "void", "size": Vector2(rect.size) * CELL,
		"level": -2, "pit_depth": 2, "draw_look": false})
	var depth := Node2D.new()
	depth.name = node_name + "-depth"
	depth.set_script(load(PIT_DEPTH))
	depth.position = Vector2(rect.position) * CELL
	depth.z_index = -2
	depth.set(&"size", Vector2(rect.size) * CELL)
	depth.set(&"pattern_seed", pattern)
	_root.add_child(depth)
	_root.move_child(depth, _root.get_node("ground").get_index() + 1)
	return depth


## Drawn rails (no collision) through `points` (cells).
func _rail_line(points: Array) -> void:
	var rails := Node2D.new()
	rails.name = _unique("rails", _rails)
	rails.set_script(load(RAILS))
	var first: Vector2 = points[0]
	rails.position = first * CELL
	var local := PackedVector2Array()
	for p: Vector2 in points:
		local.append((p - first) * CELL)
	rails.set(&"points", local)
	_rails.add_child(rails)


## A candle that burns `burn_ms` (an iron sconce on a wall, or a candlestick) at `at` (cells).
func _candle(node_name: String, look: String, at: Vector2, burn_ms: float) -> void:
	var candle := Node2D.new()
	candle.name = node_name
	candle.y_sort_enabled = true
	candle.position = at * CELL
	candle.set_script(load(CANDLE))
	candle.set(&"unlit_scene", load(OBJ + "interiors/decor/interior-decor-%s-unlit.tscn" % look))
	candle.set(&"lit_scene", load(OBJ + "interiors/decor/interior-decor-%s-lit.tscn" % look))
	candle.set(&"flame_offset", Vector2(0, -78) if look == "sconce-iron" else Vector2(0, -60))
	candle.set(&"burn_ms", burn_ms)
	_objects.add_child(candle)


func _pot(node_name: String, at: Vector2, loot := "random") -> void:
	var pot := _kit("dungeon-pot", node_name, at * CELL)
	_root.set_editable_instance(pot, true)
	pot.get_node("PotLoot").set(&"loot", loot)


## A landing of the ore lift between two room worlds (ore_lift.gd `partner_world`): `role` "upper" or
## "lower", its other landing in `other_room`, the slime coming out there at `other_arrival`.
func _lift(node_name: String, at: Vector2, role: String, other_room: String, other_arrival: String) -> void:
	_object("ore-lift", node_name, at * CELL, {"lift_id": LIFT_ID, "role": role, "partner_world": PREFIX + other_room,
		"partner_door": other_arrival})


## A chest with today's record (`record`: today's chest's instance id in the one-scene Mine).
func _chest(node_name: String, at: Vector2, contents: Dictionary, record: String, big := false) -> Node2D:
	var chest := _kit("dungeon-big-chest" if big else "dungeon-chest", node_name, at * CELL)
	chest.set(&"contents", contents)
	chest.set(&"chest_id", record)
	chest.set(&"map_id", RECORD)
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
func _wall_door(scene: String, node_name: String, side: String, along: int, kind: String, props: Dictionary, kit := true) -> Node2D:
	var wall := {"n": "north", "s": "south", "w": "west", "e": "east"}[side] as String
	var base := {"wall": wall, "frame_drawn_by_wall": true, "interior_style": _style}
	var door := _kit(scene, node_name, _gap(side, along), base) if kit else _object(scene, node_name, _gap(side, along), base)
	for key: String in props:
		door.set(key, props[key])
	door.set_meta(&"interior_door_block", _block_key(side, along))
	door.set_meta(&"interior_door_kind", kind)
	return door


## A holder under Objects whose `shown` child shows only while the story flag `flag` is set
## (`when_set`) or unset (game/scripts/story_variant.gd). Returns `shown`.
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


func _unique(base: String, parent: Node) -> String:
	var unique := base
	var n := 2
	while parent.has_node(NodePath(unique)):
		unique = "%s-%d" % [base, n]
		n += 1
	return unique


# --- wing 1: the Mouth and the High Line ---------------------------------------------------------

## M1 the Mine Mouth: the way in from the camp (south, the seal), north to the Lamp Tunnel, east the
## rail gate (shut, its rails running under it) that M7's runaway cart bursts: the cart then stands
## at this side's buffer stop. The travel cart's station (its other end in the Chasm, wing 2). The S5
## shelf (L1) in the north-west corner, vines up its face (the Feral skin), its chest seen from the
## floor.
func _m1() -> void:
	_level(Rect2i(0, 0, 6, 5), 1)
	_vine(Rect2i(3, 5, 2, 1))
	_opening("s", 8, "seal")
	_opening("n", 12, "doorway")
	_opening("e", 6, "doorway")
	_wall_door("dungeon-seal", "M1-mouth-seal", "s", 8, "seal", {"glimpse": true})
	var way_out := Node2D.new()
	way_out.name = "mine-entrance"
	way_out.position = _gap("s", 8)
	_objects.add_child(way_out)
	var door := Node.new()
	door.name = "DoorScript"
	door.set_script(load(DOOR))
	door.set(&"map_id", PREFIX + _name)
	door.set(&"door_id", "mine-entrance")
	door.set(&"target_area_id", "crystal-caverns-g4")
	door.set(&"target_door_id", "camp-mine-mouth")
	door.set(&"side", "south")
	door.set(&"trigger_rect", Rect2(-64, 24, 128, 48))
	way_out.add_child(door)
	var entrance := Node2D.new()
	entrance.name = "dungeon-entrance"
	entrance.position = Vector2(9, 11.5) * CELL
	_root.add_child(entrance)
	_room_door("m1-north", "n", 12, "m2-lamp-tunnel", "m2-south")
	_room_door("m1-east", "e", 6, "m7-ore-store", "m7-west")
	_spawn(Vector2(9, 11.5))
	# the rail gate, shut; the runaway cart from M7 comes to rest at this side's buffer stop
	_kit("rail-gate", "m1-rail-gate", _gap("e", 6), {"rails": "east-west", "gate_id": ORE_GATE_ID, "posts_solid_when_smashed": false})
	var arrived := _kit("ram-cart", "m1-ore-cart", Vector2(17.2, RAIL_Y) * CELL, {"cart_id": ORE_CART_ID, "arrives": true,
		"buffer_stop": true})
	arrived.set(&"points", PackedVector2Array([Vector2.ZERO, Vector2((10.6 - 17.2) * CELL, 0)]))
	# the travel cart's line: from the north doorway down to its station (the Chasm's end, wing 2)
	_rail_line([Vector2(13, 0), Vector2(13, 3.6), Vector2(12.2, 4.6), Vector2(8.6, 4.6)])
	var station := _object("mine-cart", "M1-cart-station", Vector2(8.6, 4.6) * CELL + Vector2(0, 30))
	station.set(&"station_id", "mouth")
	station.set(&"arrival", Vector2(80, -12))
	station.set(&"arrival_facing", Vector2.RIGHT)
	# its other end is the Chasm's station, in M9's world (the cart starts there)
	station.set(&"partner_world", PREFIX + "m9-the-chasm")
	station.set(&"partner_station", "chasm")
	station.set(&"partner_door", "m9-cart-arrival")
	_arrival("m1-cart-arrival", Vector2(8.6, 4.6) + (Vector2(0, 30) + Vector2(80, -12)) / CELL)
	# S5 on the shelf, seen from the floor
	_chest("M1-S5-chest", Vector2(3.4, 3.2), {"coins": 40, "energy-potion": 1}, "crystal-mine-M1-S5-chest")
	_kit("prize-glint", "M1-S5-glint", Vector2(3.4, 2.5) * CELL, {"phase": 0.3})
	_pot("m1-pot-1", Vector2(2.8, 12.6), "heart")
	_pot("m1-pot-2", Vector2(15.2, 12.6), "random")
	# the floors: cavern stone, gravel under the rails, crystal grit in the corners
	_ground_rect(Rect2i(12, 2, 2, 3), GRAVEL)
	_ground_rect(Rect2i(2, 2, 4, 3), CRYSTAL)
	_patch(Vector2(14.6, 12.4), 1.6, 1.4, CRYSTAL)
	_patch(Vector2(3.0, 9.5), 1.3, 1.6, CRYSTAL)
	# the mouth's timbers, the miners' things, crystals, a lantern each side of the way in
	_prop(P_CRATE, Vector2(6.4, 12.9))
	_prop(P_LUMBER, Vector2(11.8, 13.0))
	_prop(P_WHEELBARROW, Vector2(14.4, 4.0), true)
	_prop(P_ORE_BASKET, Vector2(2.8, 11.0))
	_prop(P_BARREL, Vector2(15.3, 9.6))
	_prop(P_SACK, Vector2(15.4, 10.6))
	_prop(P_TOOLBOX, Vector2(6.4, 5.6))
	_crystals(3, Vector2(2.6, 7.6))
	_crystals(9, Vector2(15.4, 12.0), true)
	_lantern(Vector2(7.2, 2.05))
	_lantern(Vector2(10.6, 2.05))
	_glow(Vector2(15.0, 12.2), Vector2(70, 46), Color(0.55, 0.8, 1.0, 0.5))
	_prop(P_SNAIL, Vector2(13.6, 11.6))
	_prop(P_MOTH, Vector2(9.0, 3.0))


## M2 the Lamp Tunnel: dark; rails north-south, two voids west of them (a fall puts the slime back),
## three lamps that light it for good; west to the Tally Room (wing 2).
func _m2() -> void:
	_level(Rect2i(4, 3, 5, 4), -2)
	_level(Rect2i(4, 10, 6, 3), -2)
	_opening("s", 12, "doorway")
	_opening("n", 12, "doorway")
	_opening("w", 8, "doorway")
	_room_door("m2-south", "s", 12, "m1-mine-mouth", "m1-north")
	_room_door("m2-north", "n", 12, "m4-great-shaft", "m4-south-m2")
	_room_door("m2-west", "w", 8, "m5-tally-room", "m5-east")
	_spawn(Vector2(13, 12.5))
	_pit("m2-void-north", Rect2i(4, 3, 5, 4), 1)
	_pit("m2-void-south", Rect2i(4, 10, 6, 3), 2)
	_rail_line([Vector2(13, 0), Vector2(13, 16)])
	_candle("m2-sconce-1", "sconce-iron", Vector2(2.6, 2.05), 60000.0)
	_candle("m2-sconce-2", "sconce-iron", Vector2(15.4, 2.05), 60000.0)
	_candle("m2-lamp-3", "candlestick", Vector2(15.2, 12.4), 60000.0)
	_dark(["m2-sconce-1", "m2-sconce-2", "m2-lamp-3"], "crystal-mine.lamp-tunnel-lit")
	_pot("m2-pot", Vector2(15.0, 9.6), "energy")
	_ground_rect(Rect2i(12, 2, 2, 12), GRAVEL)
	_patch(Vector2(3.0, 8.6), 1.0, 1.0, CRYSTAL)
	_patch(Vector2(15.0, 5.5), 1.0, 1.8, CRYSTAL)
	_prop(P_ORE_BASKET, Vector2(10.8, 12.9))
	_prop(P_ORE_HEAP, Vector2(15.0, 7.4))
	_prop(P_LUMBER, Vector2(10.6, 8.4))
	_prop(P_STALAGMITES, Vector2(2.6, 13.0))
	_crystals(5, Vector2(9.6, 4.6))
	_crystals(7, Vector2(2.6, 11.0))
	_crystals(12, Vector2(15.4, 4.4), true)
	_glow(Vector2(9.6, 4.4), Vector2(60, 40), Color(0.5, 0.75, 1.0, 0.45))
	_glow(Vector2(2.6, 10.8), Vector2(60, 40), Color(0.75, 0.55, 1.0, 0.45))
	_prop(P_GLOW_WORM, Vector2(10.4, 11.0))
	_prop(P_PILL_BUG, Vector2(15.0, 11.0))


## M4 the Great Shaft (2 x 1): the hub's gallery round the shaft (a void). North the Foreman's Gate
## (two keyholes, keys 1 and 2) to the Dark Maze (wing 2); key 2's chest on the high ledge (L1) in the
## south-east corner, in sight from the gallery and reached only by the High Line through M6's walk;
## the west shelf (L1, vines up its face: the Feral secret over the Survey Office, wings 2-3).
func _m4() -> void:
	_level(Rect2i(29, 8, 7, 8), 1)
	_level(Rect2i(0, 0, 5, 6), 1)
	_level(Rect2i(13, 5, 13, 7), -2)
	_vine(Rect2i(2, 6, 2, 1))
	_opening("s", 12, "doorway")
	_opening("s", 22, "doorway")
	_opening("s", 30, "doorway")
	_opening("n", 8, "key2")
	_opening("w", 2, "doorway")
	_room_door("m4-south-m2", "s", 12, "m2-lamp-tunnel", "m2-north")
	_room_door("m4-south-m6", "s", 22, "m6-bat-gallery", "m6-north")
	_room_door("m4-south-ledge", "s", 30, "m6-bat-gallery", "m6-north-walk")
	_room_door("m4-north", "n", 8, "m8-dark-maze", "m8-south")
	_room_door("m4-west-shelf", "w", 2, "m3-survey-office", "m3-east-shelf")
	_wall_door("key-door", "foremans-gate", "n", 8, "key2", {"door_id": "foremans-gate", "keyholes": 2,
		"locked_text": "Two locks. Two keys."})
	_spawn(Vector2(13, 13))
	# the shaft: deep, dust drifting down, glints far below (the lift and its cables come with wing 4)
	var shaft := _pit("m4-shaft", Rect2i(13, 5, 13, 7), 4)
	shaft.set(&"fade_px", 200.0)
	shaft.set(&"dust", 24)
	shaft.set(&"glints", 12)
	# the painted shaft under the dust and glints (tools/pack_pit_picture.gd packs it)
	if ResourceLoader.exists(MINE_SHAFT_PICTURE):
		shaft.set(&"picture", load(MINE_SHAFT_PICTURE))
	# the ore lift's upper landing on the shaft's north lip, under the painted shaft's right-hand rope
	# (M14's lower landing lies straight below it on the map); it waits down, its crank below
	_lift("m4-lift", Vector2(22.0, 4.4), "upper", "m14-shaft-floor", "m14-lift-arrival")
	_arrival("m4-lift-arrival", Vector2(20.8, 3.6))
	# key 2 on the ledge (today's K2 chest's record), glinting over the gallery
	_chest("m4-key2-chest", Vector2(31.5, 10.4), {"dungeon-small-key": 1}, "crystal-mine-M7-K2-chest")
	_kit("prize-glint", "m4-key2-glint", Vector2(31.5, 9.7) * CELL, {"phase": 0.5})
	# the ore line along the gallery's south side, from the Lamp Tunnel's doorway to the Bat Gallery's
	_rail_line([Vector2(13, 16), Vector2(13, 13.4), Vector2(14, 12.7), Vector2(22, 12.7), Vector2(23, 13.4), Vector2(23, 16)])
	_prop(P_BRAZIER, Vector2(3.2, 12.6))
	_prop(P_BRAZIER, Vector2(27.2, 3.0))
	_ground_rect(Rect2i(13, 12, 11, 2), GRAVEL)
	_patch(Vector2(8.0, 9.0), 2.2, 1.6, CRYSTAL)
	_patch(Vector2(27.5, 9.0), 1.2, 2.4, CRYSTAL)
	_ground_rect(Rect2i(29, 8, 5, 6), CRYSTAL)
	_ground_rect(Rect2i(2, 2, 3, 4), CRYSTAL)
	# the miners' gallery: timbers, a tool rack, ore, crates; crystals on the shaft's lip
	_prop(P_TOOLBOX, Vector2(11.4, 2.7))
	_prop(P_TOOL_RACK, Vector2(15.0, 2.4))
	_prop(P_LUMBER, Vector2(6.6, 13.2))
	_prop(P_BARREL, Vector2(27.2, 13.0))
	_prop(P_ORE_BASKET, Vector2(9.8, 4.0))
	_prop(P_ORE_HEAP, Vector2(9.6, 12.9))
	_prop(P_BARREL_OPEN, Vector2(33.0, 3.0))
	_ore_cart(Vector2(5.0, 9.6))
	_crystals(1, Vector2(12.6, 4.6))
	_crystals(6, Vector2(26.4, 6.0), true)
	_crystals(10, Vector2(12.6, 12.0))
	_crystals(14, Vector2(33.4, 12.6), true)
	_glow(Vector2(12.6, 4.4), Vector2(70, 46), Color(0.55, 0.8, 1.0, 0.5))
	_glow(Vector2(33.2, 12.4), Vector2(70, 46), Color(0.75, 0.55, 1.0, 0.5))
	_lantern(Vector2(8.6, 2.05))
	_lantern(Vector2(20.0, 2.05))
	_lantern(Vector2(30.0, 2.05))
	_prop(P_MOTH, Vector2(19.0, 7.0))
	_prop(P_NEWT, Vector2(29.0, 6.0))


## M6 the Bat Gallery (2 x 1): dark. The floor's way follows the rails from the hub's doorway to the
## rotten timbers in the south wall (a Heavy Roll) into the Ore Store; two Glint Bats over the rails,
## two lamps that light it for good. Over it the high walk (L1): the north leg along the north wall
## from the hub's ledge doorway, the east leg down the east wall to the Ore Store's loft; two Glint
## Bats on it, a drop off it to the floor. S3 (Silk): a chest behind a web wall in a corner
## walled off by crates.
func _m6() -> void:
	_level(Rect2i(11, 0, 25, 5), 1)
	_level(Rect2i(31, 5, 5, 11), 1)
	_opening("n", 4, "doorway")
	_opening("n", 12, "doorway")
	_opening("s", 20, "barricade")
	_opening("s", 31, "doorway")
	_room_door("m6-north", "n", 4, "m4-great-shaft", "m4-south-m6")
	_room_door("m6-north-walk", "n", 12, "m4-great-shaft", "m4-south-ledge")
	_room_door("m6-south", "s", 20, "m7-ore-store", "m7-north")
	_room_door("m6-south-walk", "s", 31, "m7-ore-store", "m7-north-loft")
	_spawn(Vector2(5, 4))
	_wall_door("rotten-timbers", "m6-rotten-timbers", "s", 20, "barricade", {"flag_id": TIMBERS_FLAG}, false)
	_object("gulp-spot-stone", "m6-stone-essence", Vector2(24.5, 12.2) * CELL)
	_rail_line([Vector2(5, 0), Vector2(5, 8.2), Vector2(6.4, 9.5), Vector2(19.6, 9.5), Vector2(21, 10.9), Vector2(21, 16)])
	_enemy("m6-bat-1", "glint-bat", Vector2(10.0, 9.0), 80.0)
	_enemy("m6-bat-2", "glint-bat", Vector2(17.0, 10.2), 80.0)
	_enemy("m6-bat-walk-1", "glint-bat", Vector2(22.0, 3.2), 40.0)
	_enemy("m6-bat-walk-2", "glint-bat", Vector2(32.6, 9.0), 40.0)
	_candle("m6-sconce-1", "sconce-iron", Vector2(8.6, 2.05), 60000.0)
	_candle("m6-lamp-2", "candlestick", Vector2(17.0, 12.6), 60000.0)
	_dark(["m6-sconce-1", "m6-lamp-2"], "crystal-mine.bat-gallery-lit")
	# S3 (the Silk skin): the south-west corner walled off by crates, a web wall across its mouth (rows
	# 11-12; a barrel closes the trim's row under it); its chest shown only to a save that never freed
	# today's silk parcel there (its flag), so the prize is never had twice
	for x: float in [2.6, 3.6, 4.6, 5.6]:
		_prop(P_CRATE, Vector2(x, 10.6))
	_prop(P_BARREL, Vector2(6.0, 13.5))
	_object("web-wall", "m6-S3-web-wall", Vector2(6.0, 12.0) * CELL, {"orientation": "side", "span": 128.0, "hides_secret": true})
	var s3 := _variant("m6-S3-variant", "silk-parcel.crystal-mine:Objects/M6-S3-parcel", false)
	var chest := _instance(KIT + "dungeon-chest.tscn", "m6-S3-chest", Vector2(3.6, 12.6) * CELL, s3)
	chest.set(&"contents", {"coins": 30, "energy-potion": 1})
	chest.set(&"chest_id", "crystal-mine-M6-S3-chest")
	chest.set(&"map_id", RECORD)
	_ground_rect(Rect2i(4, 2, 2, 7), GRAVEL)
	_ground_rect(Rect2i(6, 9, 15, 1), GRAVEL)
	_ground_rect(Rect2i(20, 10, 2, 4), GRAVEL)
	_patch(Vector2(26.0, 7.0), 2.4, 1.8, CRYSTAL)
	_patch(Vector2(9.0, 12.4), 1.6, 1.0, CRYSTAL)
	# the high walk's floor: crystal, its own (the floor below is cavern stone)
	_ground_rect(Rect2i(11, 2, 23, 3), CRYSTAL)
	_ground_rect(Rect2i(31, 5, 3, 9), CRYSTAL)
	_prop(P_WHEELBARROW, Vector2(3.0, 5.6))
	_prop(P_SACK, Vector2(14.0, 12.6))
	_prop(P_BARREL, Vector2(9.0, 12.9))
	_prop(P_ORE_HEAP, Vector2(28.0, 12.9))
	_prop(P_BROKEN_CRATES, Vector2(27.6, 11.4))
	_prop(P_STALAGMITES, Vector2(13.0, 6.0))
	_ore_cart(Vector2(13.0, 9.5))
	_crystals(2, Vector2(25.4, 8.0))
	_crystals(8, Vector2(29.4, 12.6), true)
	_crystals(11, Vector2(3.2, 2.8))
	_crystals(15, Vector2(29.4, 6.2), true)
	_glow(Vector2(25.4, 7.8), Vector2(70, 46), Color(0.55, 0.8, 1.0, 0.5))
	_glow(Vector2(29.4, 12.4), Vector2(60, 40), Color(0.75, 0.55, 1.0, 0.45))
	_glow(Vector2(3.2, 2.6), Vector2(60, 40), Color(0.55, 0.8, 1.0, 0.45))
	_prop(P_GLOW_WORM, Vector2(24.0, 10.4))
	_prop(P_GLOW_WORM, Vector2(7.6, 6.4))


## M7 the Ore Store (2 x 1): the mechanism's teach. A loaded cart held on its rails, its brake's rope
## to a round target straight above it; a pot thrown at the target lets it go: it rolls west, bursts
## the rail gate in the west doorway and rolls on into the Mine Mouth (the short way back, for good).
## The Bone Leaper in the west half. In the north-east the crate loft (L1): the Pick Mole behind his
## crates, the loft's stair the only way up, its north doorway the High Line's start. North the
## rotten timbers (from the Bat Gallery's floor).
func _m7() -> void:
	_level(Rect2i(26, 0, 10, 6), 1)
	_stairs(Rect2i(27, 6, 2, 1))
	_opening("w", 6, "doorway")
	_opening("n", 20, "barricade")
	_opening("n", 31, "doorway")
	_room_door("m7-west", "w", 6, "m1-mine-mouth", "m1-east")
	_room_door("m7-north", "n", 20, "m6-bat-gallery", "m6-south")
	_room_door("m7-north-loft", "n", 31, "m6-bat-gallery", "m6-south-walk")
	_spawn(Vector2(21, 4))
	_wall_door("rotten-timbers", "m7-rotten-timbers", "n", 20, "barricade", {"flag_id": TIMBERS_FLAG}, false)
	_kit("rail-gate", "m7-rail-gate", _gap("w", 6), {"rails": "east-west", "gate_id": ORE_GATE_ID, "posts_solid_when_smashed": false})
	# the runaway cart, held at the top of its line, the brake's target straight above the brake
	var cart := _kit("ram-cart", "m7-ore-cart", Vector2(23, RAIL_Y) * CELL, {"cart_id": ORE_CART_ID, "rolls_out": true,
		"buffer_stop": false})
	cart.set(&"points", PackedVector2Array([Vector2.ZERO, Vector2(0.6 * CELL - 23 * CELL, 0)]))
	var targets: Array[NodePath] = [NodePath("../m7-ore-cart")]
	_kit("knock-target", "m7-cart-target", Vector2(23, 4.4) * CELL, {"target_id": "crystal-mine-ore-cart-target", "targets": targets})
	# pots by the target, where the throw is made from (they grow back)
	_pot("m7-pot-1", Vector2(19.6, 3.4), "none")
	_pot("m7-pot-2", Vector2(19.0, 4.6), "random")
	_pot("m7-pot-3", Vector2(20.2, 5.0), "none")
	_enemy("m7-bone-leaper", "bone-leaper", Vector2(9.0, 11.0), 90.0)
	# the crate loft: the Pick Mole behind his crates (his picks fly at the floor's stair)
	_enemy("m7-pick-mole", "pick-mole", Vector2(30.6, 2.9), 40.0)
	for x: float in [29.0, 30.4, 31.8]:
		_prop(P_CRATE, Vector2(x, 4.2))
	_prop(P_CRATE, Vector2(27.0, 2.6))
	_prop(P_SACK, Vector2(33.2, 5.0))
	_pot("m7-loft-pot", Vector2(26.8, 4.6), "heart")
	# the floors: gravel under the rails, crystal grit, cavern stone
	_ground_rect(Rect2i(2, 6, 22, 2), GRAVEL)
	_patch(Vector2(14.0, 12.0), 2.6, 1.4, CRYSTAL)
	_patch(Vector2(30.0, 11.0), 2.4, 1.6, CRYSTAL)
	# the crate loft's boards
	_ground_rect(Rect2i(26, 2, 8, 4), PLANKS)
	_patch(Vector2(4.0, 3.2), 1.6, 1.0, CRYSTAL)
	# the store: ore carts that break the Bone Leaper's sight, heaps, lumber, barrels, lanterns
	_ore_cart(Vector2(6.0, 3.6))
	_ore_cart(Vector2(13.0, 10.4), true)
	_ore_cart(Vector2(31.0, 12.2))
	_prop(P_ORE_HEAP, Vector2(4.0, 12.6))
	_prop(P_ORE_HEAP, Vector2(24.6, 12.6))
	_prop(P_LUMBER, Vector2(10.0, 3.0))
	_prop(P_BARREL, Vector2(33.0, 8.6))
	_prop(P_BARREL_OPEN, Vector2(33.2, 9.8))
	_prop(P_ORE_BASKET, Vector2(17.0, 12.8))
	_prop(P_TOOL_RACK, Vector2(14.0, 2.4))
	_prop(P_SACK, Vector2(25.6, 12.9))
	_crystals(4, Vector2(2.6, 9.4))
	_crystals(13, Vector2(20.0, 12.8), true)
	_crystals(16, Vector2(33.4, 13.0), true)
	_glow(Vector2(2.6, 9.2), Vector2(60, 40), Color(0.55, 0.8, 1.0, 0.45))
	_lantern(Vector2(8.0, 2.05))
	_lantern(Vector2(17.0, 2.05))
	_lantern(Vector2(24.4, 2.05))
	_prop(P_PILL_BUG, Vector2(16.0, 9.6))
	_prop(P_FIREFLY, Vector2(30.0, 9.0))


# --- wing 2: the Lantern's half ------------------------------------------------------------------

## A cracked wall in the cracked block at `side`/`along` (the wall draws the crack; a blast opens it).
func _crack(node_name: String, side: String, along: int, flag: String) -> void:
	var passage := {"n": Rect2(-32, -128, 64, 128), "s": Rect2(-32, 0, 64, 128),
		"w": Rect2(-128, -32, 128, 64), "e": Rect2(0, -32, 128, 64)}[side] as Rect2
	_object("cracked-wall", node_name, _gap(side, along), {"frame_drawn_by_wall": true, "flag_id": flag, "passage": passage})


## An arrival point (a door without a target) named `door_id` at `at` (cells): where a ride from
## another world comes out.
func _arrival(door_id: String, at: Vector2) -> void:
	var marker := Node2D.new()
	marker.name = door_id
	marker.position = at * CELL
	_objects.add_child(marker)
	var door := Node.new()
	door.name = "DoorScript"
	door.set_script(load(DOOR))
	door.set(&"map_id", PREFIX + _name)
	door.set(&"door_id", door_id)
	marker.add_child(door)


## M5 the Tally Room: dark for good (no lamps): four crystal pillars, the tally desk, a Gloomling
## sitting on key 1 (light drives it off); the cracked north wall (the Goo Bomb, today's flag) to the
## Survey Office and the map.
func _m5() -> void:
	_opening("e", 8, "doorway")
	_opening("n", 4, "cracked")
	_room_door("m5-east", "e", 8, "m2-lamp-tunnel", "m2-west")
	_room_door("m5-north-crack", "n", 4, "m3-survey-office", "m3-south-crack")
	_crack("m5-cracked-wall", "n", 4, SURVEY_FLAG)
	_spawn(Vector2(14.6, 9.0))
	for at: Vector2 in [Vector2(5.5, 5.6), Vector2(12.5, 5.6), Vector2(5.5, 11.4), Vector2(12.5, 11.4)]:
		_object("crystal-pillar", "m5-pillar", at * CELL)
	_prop(P_DESK, Vector2(9.0, 7.4))
	_enemy("m5-gloomling", "gloomling", Vector2(9.0, 9.4), 96.0)
	_kit("dungeon-key", "M5-K1", Vector2(9.0, 9.4) * CELL, {"item": "small-key", "pickup_id": "tally-k1"})
	_dark([], "", false)
	_patch(Vector2(9.0, 12.4), 2.4, 1.0, CRYSTAL)
	_patch(Vector2(3.0, 8.6), 1.0, 2.0, CRYSTAL)
	_prop(P_PAPERS, Vector2(7.4, 7.7))
	_prop(P_SCROLLS, Vector2(14.6, 2.6))
	_prop(P_CRATE, Vector2(2.7, 12.8))
	_prop(P_CRATE, Vector2(3.7, 12.9))
	_prop(P_ORE_BASKET, Vector2(15.2, 12.8))
	_prop(P_STALAGMITES, Vector2(2.7, 3.2))
	_crystals(7, Vector2(15.3, 5.0), true)
	_crystals(3, Vector2(2.7, 10.2))
	_glow(Vector2(15.3, 4.8), Vector2(60, 40), Color(0.55, 0.8, 1.0, 0.45))
	_glow(Vector2(2.7, 10.0), Vector2(60, 40), Color(0.75, 0.55, 1.0, 0.45))
	_prop(P_GLOW_WORM, Vector2(9.0, 3.4))
	_prop(P_GLOW_WORM, Vector2(13.6, 9.0))


## M3 the Survey Office: lit; the map chest on the surveyor's table, a Crystal Crawler round its
## pillar; the cracked south wall from the Tally Room. The shelf (L1) along the north wall: from the
## hub's west shelf (east, the Feral secret) to a doorway north onto the Dark Maze's wall tops; out of
## reach from the floor (a drop off it lands on the floor).
func _m3() -> void:
	_level(Rect2i(0, 0, 18, 5), 1)
	_opening("s", 4, "cracked")
	_opening("e", 2, "doorway")
	_opening("n", 7, "doorway")
	_room_door("m3-south-crack", "s", 4, "m5-tally-room", "m5-north-crack")
	_room_door("m3-east-shelf", "e", 2, "m4-great-shaft", "m4-west-shelf")
	_room_door("m3-north-shelf", "n", 7, "m8-dark-maze", "m8-south-shelf")
	_crack("m3-cracked-wall", "s", 4, SURVEY_FLAG)
	_spawn(Vector2(5.0, 12.0))
	_ground_rect(Rect2i(2, 2, 14, 3), CRYSTAL)
	_prop(P_WORKBENCH, Vector2(9.0, 8.2))
	_chest("M3-map-chest", Vector2(9.0, 9.9), {"dungeon-map": 1}, "crystal-mine-M3-map-chest")
	_object("crystal-pillar", "m3-pillar", Vector2(4.4, 10.4) * CELL)
	_enemy("m3-crawler", "crystal-crawler", Vector2(4.4, 9.1), 120.0)
	_prop(P_CANDLE_LIT, Vector2(11.0, 8.0))
	_prop(P_SCROLLS, Vector2(13.6, 6.7))
	_prop(P_PAPERS, Vector2(6.8, 8.3))
	_prop(P_TOOLBOX, Vector2(15.2, 7.0))
	_prop(P_BARREL, Vector2(15.3, 12.6))
	_prop(P_BRAZIER, Vector2(13.0, 12.6))
	_prop(P_CRATE, Vector2(2.7, 7.0))
	_patch(Vector2(9.0, 12.4), 2.6, 1.0, CRYSTAL)
	_crystals(10, Vector2(15.3, 9.4), true)
	_crystals(5, Vector2(2.7, 12.6))
	_glow(Vector2(15.3, 9.2), Vector2(60, 40), Color(0.55, 0.8, 1.0, 0.45))
	_crystals(12, Vector2(3.0, 3.2))
	_prop(P_MOTH, Vector2(9.0, 6.0))
	_prop(P_SNAIL, Vector2(2.8, 8.4))


## M8 the Dark Maze (2 x 2): dark. Its inner walls are raised (L1, two cells thick, crystal tops); lines
## of crystal clusters (one cell, the `crystal walls` props, scaled so their collision closes each cell
## to the slime) part the floor into branches and dead ends: in the Lantern's small circle the way must
## be found and remembered. Each of the four candles stands at the end of its own branch (the south-east
## pocket by the way in, the north-east nook by the goal, the north-west nook its Gloomling smothers, the
## foot of the west strip's zigzag); lit at once (each burns `MAZE_CANDLE_MS`) they open the exit gate (a
## lantern gate) for good; the goal's brazier burns beyond it, in the north-east enclosure whose east
## doorway leads to the Chasm. The void across the middle and the shadow path over it. Every dead end
## holds something: S4's chest (today's record) and its Gloomling at the end of the strip under the void,
## pots in the zigzag's bays, an ore heap and pots in the bay by the way in, lumber and a pot behind the
## north corridor's stub, a Gloomling and an ore heap in the north-east hall's pocket. Three Glint Bats.
## South: the Foreman's Gate's other side. On top of the walls (the Feral secret, after Pearl 3): from the
## Survey Office's shelf through the south wall onto the west wall's top, north and east along the walls
## to S1's chest at the north wall's east end (today's record: 50 coins and the belt slot).
func _m8() -> void:
	# the walls (L1): A along the north, B down the west to the south rim, C from the east wall, and the
	# goal's enclosure (its west wall from the north rim, its south wall cut by the gate's gap)
	for wall: Rect2i in [Rect2i(7, 9, 15, 2), Rect2i(7, 11, 2, 21), Rect2i(22, 17, 14, 2), Rect2i(26, 0, 2, 10),
			Rect2i(28, 8, 2, 2), Rect2i(32, 8, 4, 2)]:
		_level(wall, 1)
		_ground_rect(wall, CRYSTAL)
	_level(MAZE_VOID, -2)
	_opening("s", 26, "doorway")
	_opening("e", 6, "doorway")
	_opening("s", 7, "doorway")
	_room_door("m8-south", "s", 26, "m4-great-shaft", "m4-north")
	_room_door("m8-east", "e", 6, "m9-the-chasm", "m9-west")
	_room_door("m8-south-shelf", "s", 7, "m3-survey-office", "m3-north-shelf")
	_spawn(Vector2(27.0, 27.6))
	_pit("M8-void", MAZE_VOID, 8)
	var cells: Array[Vector2i] = []
	for cell: Vector2i in [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0),
			Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0)]:
		cells.append(cell)
	_kit("shadow-path", "M8-shadow-path", Vector2(14, 16) * CELL, {"cells": cells})
	# the crystal partitions: runs of cells (x, y, w, h)
	var n := 0
	for run: Rect2i in MAZE_PARTITIONS:
		for y in range(run.position.y, run.end.y):
			for x in range(run.position.x, run.end.x):
				_crystals(1 + n % 16, Vector2(x + 0.5, y + 0.84), n % 3 == 1, PARTITION_SIZE)
				n += 1
	# the four candles, each at a branch's end (the slime lights it from the cell north of it)
	for spec: Array in [["M8-candle-se", Vector2(32.7, 21.6)], ["M8-candle-ne", Vector2(24.5, 3.4)],
			["M8-candle-nw", Vector2(2.6, 3.4)], ["M8-candle-sw", Vector2(3.5, 28.4)]]:
		_candle(spec[0], "candlestick", spec[1], MAZE_CANDLE_MS)
		var candle := _objects.get_node(String(spec[0]))
		candle.set(&"group", "dark-maze")
		candle.set(&"gate_id", "dark-maze-exit")
	_object("lantern-gate", "M8-exit-gate", Vector2(31.0 * CELL, 10.0 * CELL - 4.0), {"gate_id": "dark-maze-exit",
		"shut_text": "The gate is shut. The maze's four candles are cold."})
	_prop(P_BRAZIER, Vector2(30.6, 3.6))
	_enemy("M8-gloomling-candle", "gloomling", Vector2(2.6, 3.4), 60.0)
	# S4 at the end of the strip under the void, its Gloomling on it
	_enemy("M8-gloomling-hoard", "gloomling", Vector2(20.5, 24.6), 60.0)
	_chest("M8-S4-hoard", Vector2(20.5, 24.6), {"energy-potion": 2, "coins": 30}, "crystal-mine-M8-S4-hoard")
	_kit("prize-glint", "M8-S4-glint", Vector2(20.5, 24.0) * CELL, {"phase": 0.1})
	# S1 on the north wall's top (L1), at its east end: the glint seen from the maze's floor
	_chest("M8-S1-chest", Vector2(20.6, 9.4), {"coins": 50, "belt-slot": 1}, "crystal-mine-M4-S1-chest")
	_kit("prize-glint", "M8-S1-glint", Vector2(20.6, 8.8) * CELL, {"phase": 0.6})
	_enemy("M8-bat-north", "glint-bat", Vector2(10.0, 2.6), 80.0)
	_enemy("M8-bat-west", "glint-bat", Vector2(4.5, 10.0), 80.0)
	_enemy("M8-bat-south", "glint-bat", Vector2(17.0, 24.4), 80.0)
	# the dead ends' things
	_enemy("M8-gloomling-pocket", "gloomling", Vector2(31.5, 14.0), 50.0)
	_prop(P_ORE_HEAP, Vector2(32.6, 15.4))
	_prop(P_BROKEN_CRATES, Vector2(30.6, 15.4))
	_pot("M8-pot-pocket", Vector2(33.0, 12.6), "heart")
	_prop(P_ORE_HEAP, Vector2(32.4, 28.6))
	_pot("M8-pot-bay-1", Vector2(30.4, 28.4), "energy")
	_pot("M8-pot-bay-2", Vector2(31.3, 25.4), "random")
	_prop(P_LUMBER, Vector2(19.0, 2.8))
	_pot("M8-pot-stub", Vector2(18.0, 5.0), "random")
	_pot("M8-pot-zig-1", Vector2(5.4, 15.6), "heart")
	_pot("M8-pot-zig-2", Vector2(2.6, 20.6), "random")
	_ore_cart(Vector2(5.5, 26.0))
	_pot("M8-pot", Vector2(11.0, 28.6), "energy")
	_dark([], "", false)
	_patch(Vector2(16.0, 28.0), 3.0, 1.0, CRYSTAL)
	_patch(Vector2(4.0, 20.0), 1.4, 1.2, CRYSTAL)
	_patch(Vector2(30.5, 5.0), 2.0, 1.4, CRYSTAL)
	_patch(Vector2(25.0, 14.0), 1.6, 1.2, CRYSTAL)
	_prop(P_STALAGMITES, Vector2(33.2, 11.8))
	_prop(P_BARREL, Vector2(25.4, 21.4))
	_glow(Vector2(24.6, 7.2), Vector2(70, 46), Color(0.55, 0.8, 1.0, 0.5))
	_glow(Vector2(33.2, 21.4), Vector2(70, 46), Color(0.75, 0.55, 1.0, 0.5))
	_glow(Vector2(10.4, 26.8), Vector2(60, 40), Color(0.55, 0.8, 1.0, 0.45))
	_prop(P_GLOW_WORM, Vector2(26.5, 20.5))
	_prop(P_GLOW_WORM, Vector2(25.0, 13.0))
	_prop(P_PILL_BUG, Vector2(15.0, 24.5))


## M9 the Chasm: the first half's last lock. The chasm (a void) from wall to wall; the plank drawbridge
## stands raised on the far (east) rim, the crystal lens beside it: an arrow lowers it west for good.
## The Bone Thrower on the far rim, whose south doorway leads down to the Shardback's Den (wing 3).
## The travel cart's station (the cart starts here): it rides to the Mine Mouth and back.
func _m9() -> void:
	_level(Rect2i(7, 2, 6, 12), -2)
	_opening("w", 6, "doorway")
	_opening("s", 13, "doorway")
	_room_door("m9-west", "w", 6, "m8-dark-maze", "m8-east")
	_room_door("m9-south", "s", 13, "m13-shardback-den", "m13-north")
	_spawn(Vector2(3.6, 7.0))
	var chasm := _pit("M9-chasm", Rect2i(7, 2, 6, 12), 9)
	chasm.set(&"fade_px", 120.0)
	chasm.set(&"dust", 16)
	var bridge := _kit("drawbridge", "M9-chasm-bridge", Vector2(13 * CELL, 10 * CELL), {"toward": "west", "length": 6,
		"width": 128.0, "bridge_id": "chasm-bridge"})
	var lens := _object("crystal-lens", "M9-chasm-lens", Vector2(13.6, 8.0) * CELL, {"lens_id": "chasm-bridge"})
	var lens_targets: Array[NodePath] = [NodePath("../" + String(bridge.name))]
	lens.set(&"targets", lens_targets)
	_enemy("M9-bone-thrower", "bone-thrower", Vector2(14.6, 12.0), 70.0)
	var station := _object("mine-cart", "M9-cart-station", Vector2(4.0, 12.6) * CELL)
	for key: String in ["station_id", "starts_with_cart", "arrival", "arrival_facing", "partner_world", "partner_station", "partner_door"]:
		station.set(key, {"station_id": "chasm", "starts_with_cart": true, "arrival": Vector2(0, -70),
			"arrival_facing": Vector2.UP, "partner_world": PREFIX + "m1-mine-mouth", "partner_station": "mouth",
			"partner_door": "m1-cart-arrival"}[key])
	_arrival("m9-cart-arrival", Vector2(4.0, 12.6) + Vector2(0, -70) / CELL)
	_rail_line([Vector2(2.0, 12.6), Vector2(6.0, 12.6)])
	_ground_rect(Rect2i(2, 12, 5, 2), GRAVEL)
	_patch(Vector2(3.6, 3.6), 1.4, 1.2, CRYSTAL)
	_patch(Vector2(14.6, 4.0), 1.0, 1.6, CRYSTAL)
	_prop(P_ROCK_STUMP, Vector2(14.9, 5.6), false, 0.8)
	_prop(P_BARREL, Vector2(2.7, 9.6))
	_prop(P_ORE_BASKET, Vector2(5.8, 3.0))
	_prop(P_CRATE, Vector2(2.7, 2.8))
	_prop(P_SACK, Vector2(15.3, 2.8))
	_crystals(4, Vector2(6.4, 5.4))
	_crystals(13, Vector2(13.6, 2.8), true)
	_glow(Vector2(6.4, 5.2), Vector2(60, 40), Color(0.55, 0.8, 1.0, 0.45))
	_lantern(Vector2(3.0, 2.05))
	_lantern(Vector2(15.0, 2.05))
	_prop(P_MOTH, Vector2(10.0, 6.0))
	_prop(P_NEWT, Vector2(5.0, 9.0))


# --- wing 3: the Den and the Feral half ------------------------------------------------------------

## M13 Shardback's Den: dark for good. The Pearl room: the Shardback's fight (once, his `boss_id`): the
## north shutter shuts behind the slime from the Chasm; won, it opens and the broken south rim's shutter
## sinks for good (the way down to the shaft's floor, wing 4) and Pearl 3 rises on its cradle of crystal
## (the Feral skin; its take seals the mine). The cart line: across the Den's south part, the loaded
## cart held at its west end, its brake's knock target past the line's east end in its line, the rope
## along the rails (as the Brood Warden's ram in the Hollow's B5): the slime stands on the rails by the
## target, he plods toward it along them, a throw at the target lets the cart go and it strikes him from
## behind, two braziers north of the line lighting the rails where he walks (the Lantern lights them;
## his slam puts the nearest out). One line from west to east: cart, rails under the light, where he
## stands, the slime, the target. Brittle in the light, the cart shatters his shell in one blow
## (shardback.gd); cold, it clangs off. Two pots by the target for the first throws; his slams knock
## crystal chunks loose for the rest. The ledge (L1) in the
## north-east holds the east door to M11; vines up its face: the Feral skin's first, safe climb.
func _m13() -> void:
	_level(Rect2i(13, 7, 5, 4), 1)
	_vine(Rect2i(13, 11, 2, 1))
	_opening("n", 13, "shutter")
	_opening("e", 8, "doorway")
	_opening("s", 12, "shutter")
	_room_door("m13-north", "n", 13, "m9-the-chasm", "m9-south")
	_room_door("m13-east-ledge", "e", 8, "m11-crystal-veil", "m11-west-landing")
	_room_door("m13-south-rim", "s", 12, "m14-shaft-floor", "m14-north-rim")
	_spawn(Vector2(14.0, 3.4))
	_wall_door("shutter", "M13-den-shutter", "n", 13, "shutter", {"fight_id": "shardback-den", "shutter_id": "den-north"})
	_wall_door("shutter", "M13-den-ledge", "s", 12, "shutter", {"starts_shut": true, "shutter_id": "den-ledge"})
	var fight := _kit("room-fight", "M13-den-fight", Vector2.ZERO, {"fight_id": "shardback-den", "once": true,
		"boss_id": SHARDBACK_ID, "reward": NodePath("../M13-den-ledge")})
	fight.set(&"size", Vector2(_cols * CELL, _rows * CELL))
	_enemy("M13-shardback", "shardback", Vector2(8.5, 8.0), 200.0)
	# the cart line, west to east along row DEN_RAIL_Y, hauled back after each run (it never runs out)
	# no buffer stop: it would stand between the slime and the target and catch the throw; the cart halts
	# at the rails' end, a cell short of the target
	var cart := _kit("ram-cart", "M13-den-cart", Vector2(2.8, DEN_RAIL_Y) * CELL, {"cart_id": "crystal-mine-den-cart",
		"returns": true, "buffer_stop": false})
	cart.set(&"points", PackedVector2Array([Vector2.ZERO, Vector2((13.4 - 2.8) * CELL, 0)]))
	var targets: Array[NodePath] = [NodePath("../M13-den-cart")]
	_kit("knock-target", "M13-den-target", Vector2(14.8, DEN_RAIL_Y) * CELL, {"target_id": "crystal-mine-den-target", "targets": targets})
	for spec: Array in [["M13-brazier-w", Vector2(6.0, 11.0)], ["M13-brazier-e", Vector2(9.5, 11.0)]]:
		_object("brazier", spec[0], spec[1] * CELL, {"burn_ms": 20000.0, "stomp_puts_out": true})
	_pot("M13-pot-1", Vector2(12.0, 13.5), "none")
	_pot("M13-pot-2", Vector2(15.2, 13.5), "random")
	# Pearl 3 on its cradle of crystal, its glint seen from the doorway through the fight
	var pearl := _object("pearl-three", "M13-pearl-three", Vector2(7.5, 4.6) * CELL, {"boss_id": SHARDBACK_ID,
		"take_radius": 48.0, "card_line": "The beast the Pearl woke in the Colossus is yours: you climb walls of thick roots and rocky handholds."})
	var glint := _kit("prize-glint", "M13-pearl-glint", Vector2(7.5, 3.9) * CELL, {"only_in_dark": false, "tint": Color(1.0, 0.86, 0.6)})
	var mine := Node.new()
	mine.name = "CrystalMine"
	mine.set_script(load(MINE))
	_root.add_child(mine)
	mine.set(&"pearl", NodePath("../Objects/" + String(pearl.name)))
	mine.set(&"pearl_glint", NodePath("../Objects/" + String(glint.name)))
	for spec: Array in [[3, Vector2(6.1, 5.2)], [7, Vector2(8.9, 5.2)], [11, Vector2(6.5, 6.0)], [5, Vector2(8.5, 6.0)]]:
		_crystals(int(spec[0]), spec[1], false, 0.8)
	_glow(Vector2(7.5, 4.4), Vector2(90, 60), Color(1.0, 0.86, 0.6, 0.35))
	_dark([], "", false)
	_ground_rect(Rect2i(2, 12, 14, 2), GRAVEL)
	_ground_rect(Rect2i(13, 7, 3, 4), CRYSTAL)
	_patch(Vector2(7.5, 4.8), 2.2, 1.4, CRYSTAL)
	_patch(Vector2(3.0, 4.0), 1.0, 1.4, CRYSTAL)
	_prop(P_STALAGMITES, Vector2(2.8, 3.0))
	_prop(P_STALAGMITES, Vector2(11.8, 3.0), true)
	_prop(P_ORE_HEAP, Vector2(15.2, 5.4))
	_prop(P_BROKEN_CRATES, Vector2(2.8, 6.4))
	_crystals(13, Vector2(15.3, 12.4), true)
	_crystals(2, Vector2(10.4, 3.2))
	_glow(Vector2(15.3, 12.2), Vector2(60, 40), Color(0.55, 0.8, 1.0, 0.45))
	_prop(P_GLOW_WORM, Vector2(11.0, 6.4))
	_prop(P_PILL_BUG, Vector2(4.0, 6.0))


## M11 the Crystal Veil (the rift): dark for good. The Feral skin's test: two landings (L1) along the
## north, the Den's door on the west one, the Fort Hall's on the east one; the rift (L0) between them
## and along the south. Down the west landing's vines (or a drop off its edge), across the rift, up the
## east landing's vines; back the same way. The optional Lantern wing: the crystal veil across the east
## landing's north doorway to the Prism Gallery, open while its brazier on the landing burns (20 s);
## two Glint Bats roost by it.
func _m11() -> void:
	_level(Rect2i(0, 0, 6, 11), 1)
	_level(Rect2i(11, 0, 7, 11), 1)
	_vine(Rect2i(3, 11, 2, 1))
	_vine(Rect2i(12, 11, 2, 1))
	_opening("w", 8, "doorway")
	_opening("e", 8, "doorway")
	_opening("n", 13, "doorway")
	_room_door("m11-west-landing", "w", 8, "m13-shardback-den", "m13-east-ledge")
	_room_door("m11-east-landing", "e", 8, "m12-fort-hall", "m12-west")
	_room_door("m11-north", "n", 13, "m10-prism-gallery", "m10-south")
	_spawn(Vector2(3.5, 8.5))
	_object("brazier", "M11-brazier", Vector2(12.0, 3.6) * CELL, {"burn_ms": 20000.0})
	var veil := _object("crystal-veil", "M11-veil", Vector2(14.0, 2.6) * CELL, {"size": 2.0 * CELL})
	var braziers: Array[NodePath] = [NodePath("../M11-brazier")]
	veil.set(&"braziers", braziers)
	_enemy("M11-bat-1", "glint-bat", Vector2(13.4, 5.2), 40.0)
	_enemy("M11-bat-2", "glint-bat", Vector2(15.0, 6.4), 40.0)
	_pot("M11-pot", Vector2(3.0, 3.4), "energy")
	_dark([], "", false)
	_ground_rect(Rect2i(2, 2, 4, 9), CRYSTAL)
	_ground_rect(Rect2i(11, 2, 5, 9), CRYSTAL)
	_patch(Vector2(8.5, 12.4), 2.0, 1.0, GRAVEL)
	_prop(P_STALAGMITES, Vector2(8.0, 4.0))
	_prop(P_STALAGMITES, Vector2(9.4, 8.6), true)
	_prop(P_ORE_HEAP, Vector2(14.8, 12.8))
	_crystals(6, Vector2(7.2, 6.6))
	_crystals(10, Vector2(2.8, 12.8))
	_crystals(15, Vector2(15.2, 9.8), true)
	_glow(Vector2(7.2, 6.4), Vector2(70, 46), Color(0.55, 0.8, 1.0, 0.5))
	_glow(Vector2(2.8, 12.6), Vector2(60, 40), Color(0.75, 0.55, 1.0, 0.45))
	_prop(P_GLOW_WORM, Vector2(8.5, 11.0))
	_prop(P_SNAIL, Vector2(5.0, 12.8))


## M10 the Prism Gallery: lit; the optional Lantern wing's end. The Prism Eye (invulnerable: go round
## it), the iron-banded ore crate (a heavy block: the Heavy skin pushes it into the eye's line as
## cover), the war journal's third page in its chest (today's record), the veil's far brazier: the veil
## on this side of the doorway opens only while it burns.
func _m10() -> void:
	_opening("s", 13, "doorway")
	_room_door("m10-south", "s", 13, "m11-crystal-veil", "m11-north")
	_spawn(Vector2(14.0, 12.0))
	_object("brazier", "M10-brazier", Vector2(12.0, 12.4) * CELL, {"burn_ms": 20000.0})
	var veil := _object("crystal-veil", "M10-veil", Vector2(14.0, 13.4) * CELL, {"size": 2.0 * CELL})
	var braziers: Array[NodePath] = [NodePath("../M10-brazier")]
	veil.set(&"braziers", braziers)
	_chest("M10-journal-chest", Vector2(5.5, 4.0), {"war-journal-page-3": 1}, "crystal-mine-M10-journal-chest")
	_kit("prize-glint", "M10-journal-glint", Vector2(5.5, 3.4) * CELL, {"phase": 0.2})
	_enemy("M10-prism-eye", "prism-eye", Vector2(8.5, 7.5), 40.0)
	_object("heavy-ore-crate", "M10-ore-crate", Vector2(3.5, 10.4) * CELL)
	_object("gulp-spot-stone", "M10-stone-essence", Vector2(2.7, 12.8) * CELL)
	_rail_line([Vector2(2.5, 11.4), Vector2(11.0, 11.4), Vector2(11.0, 13.6)])
	_ground_rect(Rect2i(2, 11, 9, 1), GRAVEL)
	_patch(Vector2(5.5, 4.6), 2.0, 1.2, CRYSTAL)
	_patch(Vector2(13.0, 6.0), 1.6, 2.0, CRYSTAL)
	_prop(P_ROCK_STUMP, Vector2(12.8, 9.0), false, 0.7)
	_prop(P_ORE_BASKET, Vector2(15.2, 3.0))
	_prop(P_TOOL_RACK, Vector2(9.0, 2.4))
	_prop(P_BARREL, Vector2(2.7, 3.0))
	_ore_cart(Vector2(7.5, 11.4), true)
	_crystals(8, Vector2(15.3, 8.4), true)
	_crystals(4, Vector2(2.7, 6.6))
	_glow(Vector2(15.3, 8.2), Vector2(70, 46), Color(0.75, 0.55, 1.0, 0.5))
	_lantern(Vector2(4.0, 2.05))
	_lantern(Vector2(12.0, 2.05))
	_prop(P_MOTH, Vector2(10.0, 5.0))


## M12 the Fort Hall: the old fort under the mountain, in fort stone (its walls the Lair's style),
## cobble floors; lit. The Feral skin's twist: the balcony (L1) along the north wall holds the big
## chest (the big key, today's record), and two stretches of vines climb its face; a climber cannot
## hide: the Watcher Eye's beam finds it, and the Bone Marcher's loop passes the vines' feet. Five
## armour statues (heavy blocks: cover from the eye), two watch-fires. A drop off the balcony lands on
## the hall's floor, and the west door leads back to the rift.
func _m12() -> void:
	_ground_rect(Rect2i(0, 0, _cols, _rows), COBBLE)
	_level(Rect2i(0, 0, 18, 5), 1)
	_vine(Rect2i(4, 5, 2, 1))
	_vine(Rect2i(12, 5, 2, 1))
	_opening("w", 8, "doorway")
	_room_door("m12-west", "w", 8, "m11-crystal-veil", "m11-east-landing")
	_spawn(Vector2(3.0, 9.0))
	_chest("M12-big-key-chest", Vector2(8.5, 3.2), {"dungeon-big-key": 1}, "crystal-mine-M12-big-key-chest", true)
	_kit("prize-glint", "M12-big-key-glint", Vector2(8.5, 2.4) * CELL, {"phase": 0.5, "only_in_dark": false})
	for at: Vector2 in [Vector2(8.5, 10.9), Vector2(4.4, 11.9), Vector2(13.8, 11.6), Vector2(6.8, 12.7), Vector2(10.6, 12.7)]:
		_object("heavy-statue", "M12-statue", at * CELL)
	_enemy("M12-watcher-eye", "watcher-eye", Vector2(8.5, 8.8), 150.0)
	var marcher := _instance(PLACED_ENEMY, "M12-bone-marcher", Vector2(3.4, 7.2) * CELL, _enemies)
	marcher.set(&"enemy_type", "bone-marcher")
	marcher.set(&"wander_radius", 40.0)
	marcher.set(&"overrides", {"route": PackedVector2Array([Vector2.ZERO, Vector2(704, 0), Vector2(704, 100), Vector2(0, 100)]), "route_loop": true})
	_prop(P_BRAZIER, Vector2(2.6, 10.6))
	_prop(P_BRAZIER, Vector2(15.4, 10.6))
	_object("gulp-spot-stone", "M12-stone-essence", Vector2(2.8, 13.0) * CELL)
	_prop(P_BANNER, Vector2(6.3, 2.05))
	_prop(P_BANNER, Vector2(10.7, 2.05))
	_prop(P_PILLAR, Vector2(15.0, 13.0))
	_prop(P_WEAPON_RACK, Vector2(15.0, 6.2))
	_prop(P_BARREL_STACK, Vector2(2.8, 6.0))
	_prop(P_ARMOR_STAND, Vector2(13.0, 3.0))
	_patch(Vector2(8.5, 13.0), 3.0, 0.9, GRAVEL)
	_prop(P_MOTH, Vector2(9.0, 6.4))


## M14 the Shaft Floor (wing 4): the bottom of the Great Shaft, a room of its own on floor -1, the calm
## spot before the Colossus. North-east, the foot of the Den's broken rim: a ledge (L1) that the rim's
## doorway opens onto, roots (vines) down its face (Feral). North-west, the ore lift's lower landing
## straight below M4's upper one (the shaft's floor under the painted shaft's right-hand rope): its crank
## is here, so the first ride is up, and from then on it runs both ways. North, the boss door (the big
## key, today's `colossus-door`) into the arena's nook. The calm room's three pots (two hearts, one
## energy) and its energy flower, as today's M14; under the shaft the ore and rubble that fell down it.
func _m14() -> void:
	_level(Rect2i(11, 0, 4, 5), 1)
	_vine(Rect2i(12, 5, 2, 1))
	_opening("n", 12, "doorway")
	_opening("n", 7, "boss")
	_room_door("m14-north-rim", "n", 12, "m13-shardback-den", "m13-south-rim")
	_room_door("m14-north-boss", "n", 7, "m15-colossus-arena", "m15-south")
	_wall_door("boss-door", "colossus-door", "n", 7, "boss", {"door_id": "colossus-door"})
	_spawn(Vector2(9.0, 9.5))
	# the lift's lower landing (its crank), the slime coming out beside it from above
	_lift("m14-lift", Vector2(4.0, 4.4), "lower", "m4-great-shaft", "m4-lift-arrival")
	_arrival("m14-lift-arrival", Vector2(5.4, 5.0))
	# the calm room: today's three pots and its flower
	_pot("M14-pot", Vector2(13.4, 11.4), "heart")
	_pot("M14-pot-2", Vector2(14.4, 12.1), "heart")
	_pot("M14-pot-3", Vector2(12.4, 12.3), "energy")
	_kit("energy-flower", "M14-flower", Vector2(10.4, 6.8) * CELL)
	# under the shaft (its footprint: cols 2-7 x rows 5-12 on the map): what fell down it, a cold light
	# from far above
	_patch(Vector2(4.4, 9.0), 1.4, 1.0, CRYSTAL)
	_prop(P_ORE_HEAP, Vector2(3.0, 9.6))
	_prop(P_BROKEN_CRATES, Vector2(6.4, 10.8))
	_prop(P_ORE_BASKET, Vector2(2.9, 11.6))
	_prop(P_ROCK_STUMP, Vector2(6.8, 7.6))
	_ore_cart(Vector2(4.4, 12.4))
	_glow(Vector2(4.8, 8.2), Vector2(170, 120), Color(0.62, 0.78, 1.0, 0.35))
	# the rim's foot: crystals either side of the roots; the room's lamps
	_crystals(3, Vector2(10.6, 5.6))
	_crystals(12, Vector2(15.4, 5.4), true)
	_crystals(7, Vector2(15.4, 12.6), true)
	_glow(Vector2(15.4, 5.2), Vector2(70, 46), Color(0.55, 0.8, 1.0, 0.5))
	_lantern(Vector2(9.6, 2.05))
	_lantern(Vector2(2.6, 2.05))
	_prop(P_BRAZIER, Vector2(9.0, 12.8))
	_prop(P_SNAIL, Vector2(11.8, 9.4))
	_prop(P_FIREFLY, Vector2(13.0, 8.0))


## M15 the Colossus's Arena (wing 4): the Colossus lab's world as it is (every node at the lab's own
## coordinates, its paint, its pots and their loot, his arena's shapes), the room adding the mine's
## pieces: its name and world, the Dungeon (the crystal mine's, in place of the lab's), the way in (the
## lab's nook cut on south to the room's edge: the room door from M14's boss door), his camp's ids
## (today's: `crystal-mine-colossus`, `crystal-colossus`), the fight once (not the lab's refights),
## the crystal over the nook behind the slime while he lives (`seal_cells`), the climb out (today's
## roots to the Lookout, sealed until he falls) and his full heart. The lab's note goes. His fight is
## the lab's: nothing in it changes.
func _build_m15(path: String) -> Error:
	var lab := (load(COLOSSUS_LAB) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as Node2D
	_root = lab
	lab.name = _name
	lab.scene_file_path = ""
	lab.set_script(load(ROOM_SCENE))
	lab.set(&"world_id", PREFIX + _name)
	lab.set(&"room_id", _name)
	_objects = lab.get_node("Objects") as Node2D
	# the pots keep their loot (their PotLoot child is set in the lab)
	for node: Node in _objects.get_children():
		if not node.scene_file_path.is_empty() and node.get_node_or_null(^"PotLoot") != null:
			lab.set_editable_instance(node, true)
	# the lab's pieces the mine has its own of
	for gone: String in ["Dungeon", "dungeon-entrance", "Objects/lobby-note"]:
		var node := lab.get_node_or_null(gone)
		if node != null:
			node.get_parent().remove_child(node)
			node.free()
	# the world
	var definition := lab.get_node("world-definition")
	definition.set(&"map_id", PREFIX + _name)
	var camera := lab.get_node("CameraRooms/hall") as Node2D
	camera.name = _name
	camera.set_meta(&"wall_bands", false)
	# the way in: the nook cut on through the south rock to the room's edge
	var ground := lab.get_node("ground") as TileMapLayer
	var elevation := lab.get_node("elevation") as TileMapLayer
	for y in range(M15_NOOK.position.y, M15_NOOK.end.y):
		for x in range(M15_NOOK.position.x, M15_NOOK.end.x):
			ground.set_cell(Vector2i(x, y), CAVERN, Vector2i(x % SHEET, y % SHEET))
			elevation.set_cell(Vector2i(x, y), 0, LAB_FLOOR_TILE)
	_doors = Node2D.new()
	_doors.name = "RoomDoors"
	lab.add_child(_doors)
	var door := _kit("room-door", "m15-south", Vector2(M15_NOOK.end.x * CELL - CELL, M15_NOOK.end.y * CELL), {}, _doors)
	door.set(&"door_id", "m15-south")
	door.set(&"side", "south")
	door.set(&"target_room", "m14-shaft-floor")
	door.set(&"target_door", "m14-north-boss")
	# the Dungeon: the crystal mine's (its record, its seal, its entrance in M1), where the lab's stood
	var dungeon := (load(DUNGEON) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	dungeon.name = "Dungeon"
	dungeon.position = Vector2(828, 1330)
	lab.add_child(dungeon)
	# the climb out to the Lookout, sealed until he falls, and the seal at its foot (today's)
	var climb := _object("climb-wall", "M15-root-wall", M15_CLIMB_OUT, {"top": M15_CLIMB_TOP,
		"exit_area_id": "crystal-caverns-h4", "exit_door": "lookout-from-mine", "art_size": M15_CLIMB_ART})
	_kit("dungeon-seal", "M15-climb-out-seal", M15_CLIMB_OUT - Vector2(0, 16))
	# his full heart (its values on nodes of this room, not on an instance's inner node)
	var heart := Node2D.new()
	heart.name = "M15-full-heart"
	heart.y_sort_enabled = true
	heart.position = M15_HEART
	_objects.add_child(heart)
	var look := Sprite2D.new()
	look.name = "Visual"
	look.texture = load(FULL_HEART_ART)
	look.scale = Vector2(0.62, 0.62)
	look.centered = false
	look.offset = Vector2(-128, -250)
	look.hframes = 8
	look.frame = 5
	heart.add_child(look)
	var heart_script := Node.new()
	heart_script.name = "FullHeartScript"
	heart_script.set_script(load(FULL_HEART))
	heart_script.set(&"heart_id", COLOSSUS_ID)
	heart_script.set(&"boss_id", COLOSSUS_ID)
	heart.add_child(heart_script)
	heart_script.set(&"visual", look)
	# his camp: today's ids, the fight once, the crystal over the nook while he lives, the climb out
	var arena := _objects.get_node("ColossusArena")
	arena.set(&"camp_id", COLOSSUS_CAMP)
	arena.set(&"boss_id", COLOSSUS_ID)
	arena.set(&"refights", false)
	arena.set(&"climb_wall", arena.get_path_to(climb))
	var seal := PackedVector2Array()
	for x in range(M15_NOOK.position.x, M15_NOOK.end.x):
		seal.append(Vector2((x + 0.5) * CELL, (M15_NOOK.position.y + 0.5) * CELL))
	arena.set(&"seal_cells", seal)
	# the mine's music (his fight's is the boss camp's)
	var music := AudioStreamPlayer.new()
	music.name = "MusicPlayer"
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	music.stream = load(MUSIC)
	music.volume_db = -6.0206
	music.bus = &"Music"
	music.set_script(load(SFX_PLAYER))
	music.set(&"loop", true)
	music.set(&"autoplay_cue", true)
	lab.add_child(music)
	for child in lab.get_children():
		_own(child)
	var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var err := SceneSave.save(lab, path, before)
	print("crystal mine rooms: ", path, " ", error_string(err))
	lab.free()
	return err


# --- the layout ----------------------------------------------------------------------------------

func _write_layout() -> Error:
	if FileAccess.file_exists(LAYOUT_PATH) and not _force:
		print("crystal mine rooms: %s exists and is hand-edited; not overwritten (-- --force)" % LAYOUT_PATH)
		return OK
	var layout := Node2D.new()
	layout.name = "crystal-mine-layout"
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
	print("crystal mine rooms: ", LAYOUT_PATH, " ", error_string(err))
	layout.free()
	return err
