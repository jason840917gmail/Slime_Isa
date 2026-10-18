extends SceneTree
## Builds the Crystal Mine, Chapter 3's dungeon (docs/godot/DUNGEONS.md "The Crystal Mine (built)";
## the design: docs/design/2026-10-16-dungeon-crystal-caverns.md), into
## res://game/scenes/worlds/crystal-mine.tscn (`world.crystal-mine`):
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_crystal_mine.gd [-- --dry]
##
## One world of 5 x 5 screens (80 x 70 tiles of 64 units; a screen is a camera room of 16 x 14
## tiles): the rock is painted at level 2 on the `elevation` layer and every room is carved out of it
## (its walls are the rock's cliffs, drawn with side walls; the rock's top is crystal floor, so its walls are crystal rock and it never reads as the
## rooms' cavern floor; masonry round the old fort's hall, whose floor and rock are cobble). Doorways are gaps in the rock: two tiles wide
## through a north or south wall, two walkable rows under a two-row lintel through an east or west
## wall. Holes: the void (level -2 or -3, the kit's hazard over it), the Great Shaft (-2) with its
## floor and the Colossus's arena (-2). Then the rooms' contents: camera rooms, dark rooms, candles and braziers, the mine's
## own objects (the cart, the lift, the lens, the veil, the gates, the timbers, the climbable walls,
## Pearl 3), placed enemies, scenery, and the dungeon kit's pieces (docs/godot/DUNGEONS.md: the
## Dungeon node, keys, keyed doors, the boss door, shutters, the room fight, the crank, drawbridges,
## chests, the void, the shadow path, pots and the flower that grow back, glints); `KitMarkers`
## holds a marker for what nothing builds yet (the war journal's pages, heart quarters).
##
## Since 2026-10-17 the mine keeps its Pearl inside, before the Colossus (the plan:
## docs/design/2026-10-17-pearl-mid-dungeon.md "The Crystal Mine"): the first half ends at the Chasm
## (the Bow), whose far side leads down a stair into the Shardback's Den (M13, the Pearl room: Pearl
## 3 rises when he falls; its take seals the mine's mouth until the Colossus falls). The second half
## teaches the Feral skin: the root wall up to the Den's ledge door, M11's rift (down, across, up),
## M12's balcony with the big key under the Watcher Eye and the Bone Marcher, and the roots down the
## shaft's north wall to the calm floor; the Colossus's claws are its exam. M9's old door to M10 is
## bricked: M10 and M11's veil are an optional Lantern wing off M11's east landing.
##
## It rebuilds the whole world: hand edits to the scene are lost when it runs again.
##
## Owner: dungeons (the Crystal Mine).
## Also writes the editable room scenes through tools/lib/dungeon_room_splitter.gd.

const RoomSplitter := preload("res://tools/lib/dungeon_room_splitter.gd")

const SceneSave := preload("res://tools/lib/scene_save.gd")

const OUT := "res://game/scenes/worlds/crystal-mine.tscn"
const MAP_ID := "crystal-mine"
const COLUMNS := 80
const ROWS := 70
const CELL := 64
const SHEET := 19
## terrain_tileset.tres sources.
const CAVERN := 1
const CRYSTAL := 2
const COBBLE := 19
## elevation_tileset.tres: levels -3 .. -1 at (0 .. 2, 0), 1 .. 3 at (3 .. 5, 0).
const ROCK := 2
## fence_tileset.tres: the stone column's all-neighbour tile (the gallery's floor is cavern rock).
const FENCE_STONE := Vector2i(2, 0)
## elevation_tileset.tres row 2: a flight of stairs per direction (the arrow points down them).
const STAIRS_ROW := 2
const STAIRS_SOUTH := 0

const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const FENCE_TILESET := "res://game/world/fences/fence_tileset.tres"
const FENCE_LAYER := "res://game/world/fences/fence_layer.gd"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const WORLD_EXIT := "res://game/scripts/world_exit.gd"
const CAMERA_ROOM := "res://game/world/camera_room.gd"
const DARK_ROOM := "res://game/world/darkness/dark_room.gd"
const CANDLE := "res://game/world/fire/candle.gd"
const SHEET_SPRITE := "res://game/runtime/sheet_sprite.gd"
const RAILS := "res://game/crystal_mine/mine_rails.gd"
const MINE := "res://game/crystal_mine/crystal_mine.gd"
const COLOSSUS_ARENA := "res://game/crystal_mine/colossus_arena.gd"
const OBJECTS := "res://game/scenes/objects/"
const DECOR := "res://game/scenes/objects/interiors/decor/"
const STORAGE := "res://game/scenes/objects/interiors/storage/"
const WORKSHOP := "res://game/scenes/objects/interiors/workshop/"
const STRUCTURE := "res://game/scenes/objects/interiors/structure/"
const PLACED_ENEMY := "res://game/scenes/encounters/placed-enemy.tscn"
const LANTERN_ART := "res://asset/MAPS/props/mine/128x128-mine-lantern.webp"
## The dungeon kit's scenes (docs/godot/DUNGEONS.md).
const KIT := "res://game/scenes/objects/dungeon/"
const FULL_HEART := "res://game/scenes/objects/full-heart.tscn"
## The seal (docs/godot/DUNGEONS.md "The seal"): the Colossus holds it from Pearl 3's take.
const COLOSSUS_ID := "crystal-colossus"
const SHARDBACK_ID := "crystal-mine-shardback"
const SEAL_COLOR := Color("#8a68c0")
const SEAL_DUST := Color("#c8d4f0")
const ROAR := "res://asset/audio/sfx/library/boss/fatty-roar.ogg"
const ROAR_PITCH := 0.6
## The floor of the Shardback's Den (one level down from the Chasm, by a stair).
const DEN_LEVEL := -1
## The slime's feet below its centre (a climb's `top` is its centre).
const FEET_TO_CENTRE := 27.56

## The rooms: [key, name, cell x, cell y, cells wide, cells high, dark]. A room's tiles: x from 16 * cx
## to 16 * (cx + w) - 1, y from 14 * cy to 14 * (cy + h) - 1; its edge row and column are rock.
const ROOMS := [
	["M1", "M1-mine-mouth", 1, 4, 1, 1, false],
	["M2", "M2-lamp-tunnel", 1, 3, 1, 1, true],
	["M5", "M5-tally-room", 0, 3, 1, 1, true],
	["M3", "M3-survey-office", 0, 2, 1, 1, false],
	["M4", "M4-great-shaft", 1, 2, 2, 1, false],
	["M6", "M6-bat-gallery", 2, 3, 2, 1, true],
	["M7", "M7-ore-store", 2, 4, 2, 1, false],
	["M8", "M8-dark-maze", 0, 0, 2, 2, true],
	["M9", "M9-the-chasm", 2, 0, 1, 1, false],
	["M10", "M10-prism-gallery", 3, 0, 1, 1, false],
	["M11", "M11-crystal-veil", 3, 1, 1, 1, true],
	["M12", "M12-fort-hall", 4, 1, 1, 1, false],
	["M13", "M13-shardback-den", 2, 1, 1, 1, true],
	["M15", "M15-colossus-arena", 3, 2, 1, 1, true],
]

var _root: Node2D
var _ground: TileMapLayer
var _elevation: TileMapLayer
var _fences: TileMapLayer
var _levels := {}
var _grounds := {}
## Stairs cells: Vector2i -> the elevation tileset's stairs column.
var _stairs := {}
var _nodes := {}


func _initialize() -> void:
	var dry := OS.get_cmdline_user_args().has("--dry")
	var before := FileAccess.get_file_as_string(ProjectSettings.globalize_path(OUT)) if FileAccess.file_exists(OUT) else ""
	_root = Node2D.new()
	_root.name = MAP_ID
	_root.y_sort_enabled = true
	_paint()
	_layers()
	_definition()
	_holders()
	_camera_rooms()
	_m1_mine_mouth()
	_m2_lamp_tunnel()
	_m5_tally_room()
	_m3_survey_office()
	_m4_great_shaft()
	_m6_bat_gallery()
	_m7_ore_store()
	_m8_dark_maze()
	_m9_chasm()
	_m10_prism_gallery()
	_m11_crystal_veil()
	_m12_fort_hall()
	_m13_shardback_den()
	_m15_colossus_arena()
	_dark_rooms()
	if dry:
		print("crystal mine: dry run, %d cells of rock" % _levels.size())
		_root.free()
		quit(0)
		return
	var err := SceneSave.save(_root, OUT, before)
	print("crystal mine: ", OUT, " ", error_string(err))
	_root.free()
	if err == OK:
		err = RoomSplitter.new().split(MAP_ID)
	quit(0 if err == OK else 1)


# --- the paint: rock, rooms, doorways, holes ---------------------------------------------------------

func _paint() -> void:
	for y in ROWS:
		for x in COLUMNS:
			_levels[Vector2i(x, y)] = ROCK
			# The rock's top is crystal (its walls crystal rock), so it never reads as floor.
			_grounds[Vector2i(x, y)] = CRYSTAL
	for room: Array in ROOMS:
		var x0: int = room[2] * 16
		var y0: int = room[3] * 14
		var x1: int = (room[2] + room[4]) * 16 - 1
		var y1: int = (room[3] + room[5]) * 14 - 1
		_rect(x0 + 1, y0 + 1, x1 - x0 - 1, y1 - y0 - 1, DEN_LEVEL if room[0] == "M13" else 0)
		_ground_rect(x0 + 1, y0 + 1, x1 - x0 - 1, y1 - y0 - 1, CAVERN)
	# The old fort's hall: cobble floor and masonry round it.
	_ground_rect(64, 14, 16, 14, COBBLE)
	# Doorways through a north or south wall: [x, y, w, h] two wide; through an east or west wall:
	# two walkable rows under a two-row lintel (the rock above hangs its face over the top two).
	var doorways := [
		[23, 69, 2, 1, 0],    # M1 south: out to the camp
		[27, 55, 2, 2, 0],    # M1 - M2
		[31, 59, 2, 4, 0],    # M1 east - M7 (the shutter)
		[27, 41, 2, 2, 0],    # M2 - M4
		[15, 47, 2, 4, 0],    # M2 west - M5
		[45, 41, 2, 2, 0],    # M4 - M6
		[56, 55, 2, 2, 0],    # M6 - M7 (the rotten timbers)
		[23, 27, 2, 2, 0],    # M4 - M8 (the Foreman's Gate)
		[31, 3, 2, 4, 0],     # M8 - M9 (after the maze's exit gate)
		# (M9 - M10 across the bridge is bricked since 2026-10-17: M10 is the optional Lantern wing.)
		[44, 13, 2, 2, 0],    # M9's far side - M13: the stair down into the Den
		[60, 13, 2, 2, 0],    # M10 - M11 (the veil across its mouth)
		[47, 19, 2, 4, 0],    # M13's ledge door - M11's west landing
		[63, 19, 2, 4, 0],    # M11's east landing - M12
		[42, 27, 4, 2, DEN_LEVEL],  # M13 south: the broken rim over the shaft (shut till the Shardback falls)
	]
	for d: Array in doorways:
		_rect(d[0], d[1], d[2], d[3], d[4])
	# M13 the Den: the stair down from the Chasm's far side (a front flight in the doorway's face),
	# and the ledge (level 0) in the north-east before the east door, its face the first root wall.
	for x in [44, 45]:
		_stairs[Vector2i(x, 15)] = STAIRS_SOUTH
	_rect(44, 20, 3, 4, 0)
	# M11: the rift (-2) between the west landing (the Den's door) and the east landing (M12's door, the
	# veil north to M10): its stem from the north wall down between them, its floor along the south.
	_rect(54, 15, 4, 8, -2)
	_rect(49, 23, 14, 4, -2)
	# M12 the Fort Hall: the balcony (level 2) along the north wall, held apart from the mine's rock
	# (level 2) by the hall's north band and corner blocks raised to level 3.
	_rect(64, 13, 16, 2, 3)
	_rect(65, 15, 1, 3, 3)
	_rect(78, 15, 1, 3, 3)
	_rect(66, 15, 12, 3, 2)
	# M5 Tally Room's north wall: no doorway painted; the cracked wall there opens a passage north
	# through the rock into M3, the map's room, when a blast blows it (Elevation.open_passage).
	# M1: the Feral skin's shelf over the north wall (secret S5): level 1, its face the root wall.
	_rect(18, 56, 3, 2, 1)
	# M6: secret S3's nook in the east wall, at the walkway's far end (two rows under its lintel),
	# behind a web wall.
	_rect(63, 46, 2, 4, 0)
	_ground_rect(63, 46, 2, 4, CAVERN)
	# M2: two pits of the void west of the rails.
	_rect(19, 46, 5, 4, -2)
	_rect(18, 51, 6, 3, -2)
	# M4: the Great Shaft (its floor at -2, the calm room; the spire at 0 in it); the boss door's way
	# east at -2, under a four-row lintel (its two walkable rows 35, 36).
	_rect(33, 29, 14, 9, -2)
	_rect(37, 33, 5, 2, 0)
	_rect(47, 31, 2, 6, -2)
	# M15: the Colossus's arena at -2 (its north wall four courses: the wall he climbs).
	_rect(49, 29, 14, 12, -2)
	# M8: the Dark Maze's inner walls (level 1), its void and the shadow path.
	_rect(6, 8, 14, 1, 1)
	_rect(6, 10, 1, 11, 1)
	_rect(21, 16, 10, 1, 1)
	_rect(26, 3, 1, 5, 1)
	_rect(26, 7, 2, 1, 1)
	_rect(30, 7, 1, 1, 1)
	_rect(11, 11, 10, 11, -2)
	for wall: Array in [[6, 8, 14, 1], [6, 10, 1, 11], [21, 16, 10, 1], [26, 3, 1, 5], [26, 7, 2, 1], [30, 7, 1, 1]]:
		_ground_rect(wall[0], wall[1], wall[2], wall[3], CRYSTAL)
	# M9: the chasm, deep (-3), north to south.
	_rect(38, 1, 6, 12, -3)
	# M7: nothing raised; M12: nothing raised (the dais is a floor prop).


func _shadow_path() -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	for x in range(11, 14):
		path.append(Vector2i(x, 18))
	for y in range(15, 18):
		path.append(Vector2i(13, y))
	for x in range(14, 21):
		path.append(Vector2i(x, 15))
	return path


func _rect(x: int, y: int, w: int, h: int, level: int) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if xx < 0 or yy < 0 or xx >= COLUMNS or yy >= ROWS:
				continue
			if level == 0:
				_levels.erase(Vector2i(xx, yy))
			else:
				_levels[Vector2i(xx, yy)] = level


func _ground_rect(x: int, y: int, w: int, h: int, source: int) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_grounds[Vector2i(xx, yy)] = source


func _layers() -> void:
	_ground = TileMapLayer.new()
	_ground.name = "ground"
	_ground.z_index = -2
	_ground.tile_set = load(TERRAIN_TILESET)
	for y in ROWS:
		for x in COLUMNS:
			var cell := Vector2i(x, y)
			_ground.set_cell(cell, int(_grounds[cell]), Vector2i(x % SHEET, y % SHEET))
	_ground.set_meta(&"source_cell_count", COLUMNS * ROWS)
	_ground.set_meta(&"columns", COLUMNS)
	_ground.set_meta(&"rows", ROWS)
	_ground.set_script(load(WORLD_GROUND))
	_own(_ground, _root)
	_elevation = TileMapLayer.new()
	_elevation.name = "elevation"
	_elevation.z_index = -1
	_elevation.tile_set = load(ELEVATION_TILESET)
	for cell: Vector2i in _levels:
		var level := int(_levels[cell])
		_elevation.set_cell(cell, 0, Vector2i(level + 3 if level < 0 else level + 2, 0))
	# A stairs cell takes the level of the ground it leads down to (Elevation.painted_levels).
	for cell: Vector2i in _stairs:
		_elevation.set_cell(cell, 0, Vector2i(int(_stairs[cell]), STAIRS_ROW))
	_elevation.set_script(load(ELEVATION_LAYER))
	_own(_elevation, _root)
	_fences = TileMapLayer.new()
	_fences.name = "fences"
	_fences.z_index = -1
	_fences.tile_set = load(FENCE_TILESET)
	# The Great Shaft's gallery rim: no drop to the floor (the lift is the way down); it starts
	# below the north wall's face (rows 29-30 lie behind it).
	for y in range(31, 38):
		_fences.set_cell(Vector2i(32, y), 0, FENCE_STONE)
	for x in range(32, 47):
		# The gap at the spire plank's foot (x 38, 39: the S1 drawbridge lands there).
		if x == 38 or x == 39:
			continue
		_fences.set_cell(Vector2i(x, 38), 0, FENCE_STONE)
	_fences.set_script(load(FENCE_LAYER))
	_own(_fences, _root)


func _definition() -> void:
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := _t(23.5, 66.5)
	definition.set(&"map_id", MAP_ID)
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", COLUMNS)
	definition.set(&"rows", ROWS)
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": int(spawn.x), "y": int(spawn.y)},
		"entries": {"south": {"x": int(spawn.x), "y": int(spawn.y)}}}})
	_own(definition, _root)
	_marker(_root, "player-spawn", spawn)
	_marker(_root, "dungeon-entrance", spawn)
	_marker(_root, "arrive-from-camp", spawn)
	var dungeon := (load(KIT + "dungeon.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	dungeon.name = "Dungeon"
	dungeon.set(&"dungeon_id", MAP_ID)
	dungeon.set(&"display_name", "The Crystal Mine")
	dungeon.set(&"entrance_marker", "dungeon-entrance")
	# The seal: Pearl 3's take seals the mine until the Colossus falls.
	dungeon.set(&"boss_id", COLOSSUS_ID)
	dungeon.set(&"boss_name", "The Crystal Colossus")
	dungeon.set(&"seal_color", SEAL_COLOR)
	dungeon.set(&"dust_color", SEAL_DUST)
	if ResourceLoader.exists(ROAR):
		dungeon.set(&"roar_sound", load(ROAR))
	dungeon.set(&"roar_pitch", ROAR_PITCH)
	dungeon.position = spawn + Vector2(0, -40)
	_own(dungeon, _root)
	var mine := Node.new()
	mine.name = "CrystalMine"
	mine.set_script(load(MINE))
	_own(mine, _root)
	# Out to the smith's camp (G4): the south doorway of the Mine Mouth.
	var exit := Area2D.new()
	exit.name = "exit-to-camp"
	exit.position = Vector2(24 * CELL, ROWS * CELL - 14)
	exit.collision_layer = 512
	exit.collision_mask = 130
	exit.monitorable = false
	_own(exit, _root)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(128, 24)
	shape.shape = rect
	_own(shape, exit)
	var script_node := Node.new()
	script_node.name = "world-exit-script"
	script_node.set_script(load(WORLD_EXIT))
	script_node.set(&"map_id", MAP_ID)
	script_node.set(&"exit_id", "crystal-mine-to-camp")
	script_node.set(&"target_area_id", "crystal-caverns-g4")
	script_node.set(&"entry_marker", "arrive-from-crystal-mine")
	script_node.set(&"area", exit)
	_own(script_node, exit)


func _holders() -> void:
	for holder_name: String in ["CameraRooms", "DarkRooms", "Rails", "Objects", "Scenery", "Enemies", "KitMarkers"]:
		var holder := Node2D.new()
		holder.name = holder_name
		holder.y_sort_enabled = holder_name in ["Objects", "Scenery", "Enemies"]
		_own(holder, _root)
		_nodes[holder_name] = holder


func _camera_rooms() -> void:
	var script := load(CAMERA_ROOM)
	for room: Array in ROOMS:
		var node := Node2D.new()
		node.name = room[1]
		node.set_script(script)
		node.position = Vector2(room[2] * 16 * CELL, room[3] * 14 * CELL)
		node.set(&"size", Vector2(room[4] * 16 * CELL, room[5] * 14 * CELL))
		_own(node, _nodes["CameraRooms"])


func _dark_rooms() -> void:
	var script := load(DARK_ROOM)
	for room: Array in ROOMS:
		if not bool(room[6]):
			continue
		var node := Node2D.new()
		node.name = "dark-" + str(room[1])
		node.set_script(script)
		node.position = Vector2(room[2] * 16 * CELL, room[3] * 14 * CELL)
		node.set(&"size", Vector2(room[4] * 16 * CELL, room[5] * 14 * CELL))
		_own(node, _nodes["DarkRooms"])
		_nodes["dark-" + str(room[0])] = node
	# M2: its three sconces light it for good once all burn (dark room 1's lesson).
	var lamp_tunnel := _nodes["dark-M2"] as Node2D
	lamp_tunnel.set(&"lit_for_good_when_all_lit", true)
	lamp_tunnel.set(&"candles", _paths(lamp_tunnel, ["M2-sconce-1", "M2-sconce-2", "M2-sconce-3"]))
	# M6: two sconces light the gallery for good, and wake every bat.
	var gallery := _nodes["dark-M6"] as Node2D
	gallery.set(&"lit_for_good_when_all_lit", true)
	gallery.set(&"candles", _paths(gallery, ["M6-sconce-1", "M6-sconce-2"]))
	# M15: the arena is lit while all four braziers burn.
	var arena := _nodes["dark-M15"] as Node2D
	arena.set(&"candles", _paths(arena, ["M15-brazier-nw", "M15-brazier-ne", "M15-brazier-sw", "M15-brazier-se"]))


func _paths(from: Node, keys: Array) -> Array[NodePath]:
	var out: Array[NodePath] = []
	for key: String in keys:
		out.append(from.get_path_to(_nodes[key]))
	return out


# --- the rooms ---------------------------------------------------------------------------------------

func _m1_mine_mouth() -> void:
	var objects := _nodes["Objects"] as Node2D
	_rails([_t(27.5, 56), _t(27.5, 64), _t(25, 66.5), _t(19.5, 66.5)])
	var station := _scene(objects, OBJECTS + "mine-cart.tscn", "M1-cart-station", _t(19.5, 66.5) + Vector2(0, 30))
	station.set(&"station_id", "mouth")
	station.set(&"arrival", Vector2(80, -12))
	station.set(&"arrival_facing", Vector2.RIGHT)
	# Secret S5: the shelf over the north wall (level 1), its root wall for the Feral skin, a chest on it.
	var up := _scene(objects, OBJECTS + "climb-wall.tscn", "M1-root-wall", _t(19.5, 59) + Vector2(0, -6))
	up.set(&"top", Vector2(0, -120))
	up.set(&"art_size", Vector2(190, 76))
	var down := _scene(objects, OBJECTS + "climb-wall.tscn", "M1-root-wall-down", _t(19.5, 57) + Vector2(0, 20))
	down.set(&"top", Vector2(0, 110))
	down.set(&"prompt", "Climb down")
	down.set(&"show_art", false)
	_chest("M1-S5-chest", "dungeon-chest", _t(18.4, 57.2), {"coins": 40, "energy-potion": 1})
	_piece("prize-glint", "M1-S5-glint", _t(18.4, 56.5), {"phase": 0.3})
	_kit("lore", "M1-S5-journal-page", _t(18.4, 57.2), {"contents": "a page of the Thorn Guard's war journal (the fort under the mountain), for the S5 chest once pages exist"})
	# The seal (docs/godot/DUNGEONS.md "The seal"): from Pearl 3's take until the Colossus falls, the
	# mouth is shut; the take's glimpse shows it slam up.
	_piece("dungeon-seal", "M1-mouth-seal", Vector2(24 * CELL, 69 * CELL), {"wall": "south", "glimpse": true})
	# The east wing's way back: the iron shutter the crank in M7 lifts for good.
	_piece("shutter", "M1-east-shutter", Vector2(31 * CELL, 62 * CELL), {"wall": "east", "starts_shut": true,
		"shutter_id": "mouth-shutter"})
	_lanterns([_t(22, 59.2), _t(29.5, 59.2)])
	for spec: Array in [["M1-pot-a", "clay-pot", _t(17.6, 61)], ["M1-pot-b", "clay-pot", _t(29.6, 67.6)], ["M1-crate", "crate", _t(17.7, 64)]]:
		_liftable(objects, spec[0], spec[1], spec[2])
	_props([
		[STRUCTURE + "interior-structure-beam-wood-vertical.tscn", _t(22.2, 68.6), 1.0],
		[STRUCTURE + "interior-structure-beam-wood-vertical.tscn", _t(25.8, 68.6), 1.0],
		[WORKSHOP + "interior-workshop-wheelbarrow.tscn", _t(28.6, 61.4), 0.9],
		[WORKSHOP + "interior-workshop-ore-basket.tscn", _t(17.8, 67.3), 0.9],
		[STORAGE + "interior-storage-barrel.tscn", _t(30, 65), 0.9],
	])


func _m2_lamp_tunnel() -> void:
	var objects := _nodes["Objects"] as Node2D
	_rails([_t(27.5, 42), _t(27.5, 55)])
	_candle(objects, "M2-sconce-1", "sconce-iron", _t(17.3, 45.4), 60000.0)
	_candle(objects, "M2-sconce-2", "sconce-iron", _t(30.6, 45.4), 60000.0)
	_candle(objects, "M2-sconce-3", "sconce-iron", _t(17.3, 54.5), 60000.0)
	# Two pits of the void: a fall puts the slime back at the room's south door.
	_hazard("M2-void-north", Vector2i(19, 46), Vector2i(5, 4), [_t(28, 54.4)])
	_hazard("M2-void-south", Vector2i(18, 51), Vector2i(6, 3), [_t(28, 54.4)])
	_pot("M2-pot", _t(29.6, 44.6), "energy")


func _m5_tally_room() -> void:
	var objects := _nodes["Objects"] as Node2D
	for at: Vector2 in [_t(5, 46), _t(10.5, 46), _t(5, 52), _t(10.5, 52)]:
		_scene(objects, OBJECTS + "crystal-pillar.tscn", "M5-pillar", at)
	_prop(_nodes["Scenery"], WORKSHOP + "interior-workshop-writing-desk.tscn", _t(7.8, 48.6), 0.9, "M5-tally-desk")
	_enemy("M5-gloomling", "gloomling", _t(7.8, 50.4), 96.0)
	_piece("dungeon-key", "M5-K1", _t(7.8, 50.4), {"item": "small-key", "pickup_id": "tally-k1"})
	# The cracked wall in the north wall: its passage north through the rock into M3, the map's room.
	var crack := _scene(objects, OBJECTS + "cracked-wall.tscn", "M5-cracked-wall", Vector2(5 * CELL, 45 * CELL))
	crack.set(&"flag_id", "crystal-mine.survey-wall")
	crack.set(&"passage", Rect2(-64, -256, 128, 256))
	crack.set(&"crack_size", Vector2(120, 118))
	crack.set(&"crack_offset", Vector2(0, -64))
	crack.set(&"hole_size", Vector2(120, 124))
	crack.set(&"hole_offset", Vector2(0, -58))


func _m3_survey_office() -> void:
	var objects := _nodes["Objects"] as Node2D
	_prop(_nodes["Scenery"], WORKSHOP + "interior-workshop-workbench.tscn", _t(8, 34.5), 0.95, "M3-survey-table")
	_prop(_nodes["Scenery"], WORKSHOP + "interior-workshop-scroll-rack.tscn", _t(12.5, 31.4), 0.9, "M3-scroll-rack")
	_prop(_nodes["Scenery"], WORKSHOP + "interior-workshop-paper-stack.tscn", _t(3, 31.6), 0.9, "M3-papers")
	_scene(objects, OBJECTS + "crystal-pillar.tscn", "M3-pillar", _t(4, 37))
	_enemy("M3-crawler", "crystal-crawler", _t(4, 37) + Vector2(0, -81), 120.0)
	_candle(objects, "M3-lamp", "candlestick", _t(10.5, 34.2), 0.0, true)
	_chest("M3-map-chest", "dungeon-chest", _t(8, 36.5), {"dungeon-map": 1})


func _m4_great_shaft() -> void:
	var objects := _nodes["Objects"] as Node2D
	_rails([_t(27.5, 41), _t(27.5, 33), _t(22, 31.5)])
	_candle(objects, "M4-brazier-w", "brazier", _t(18.4, 31.8), 0.0, true)
	_candle(objects, "M4-brazier-e", "brazier", _t(31.3, 39.6), 0.0, true)
	# The ore lift: its upper landing on the gallery, the lower on the shaft's floor.
	var upper := _scene(objects, OBJECTS + "ore-lift.tscn", "M4-lift-upper", _t(31.5, 35.2))
	upper.set(&"role", "upper")
	upper.set(&"arrival", Vector2(-40, 0))
	upper.set(&"arrival_facing", Vector2.LEFT)
	var lower := _scene(objects, OBJECTS + "ore-lift.tscn", "M4-lift-lower", _t(34, 35.6))
	lower.set(&"role", "lower")
	lower.set(&"arrival", Vector2(56, 0))
	lower.set(&"arrival_facing", Vector2.RIGHT)
	# Secret S1: the spire's lens (the Bow) and its heart quarter; the plank to it is the kit's.
	# The plank lowers from the spire south onto the gallery (the fence's gap at x 38, 39).
	var plank := _piece("drawbridge", "M4-spire-plank", Vector2(39 * CELL, 35 * CELL), {"toward": "south",
		"length": 3, "width": 128.0, "bridge_id": "great-shaft-spire-plank"})
	var lens := _scene(objects, OBJECTS + "crystal-lens.tscn", "M4-spire-lens", _t(37.6, 33.7))
	lens.set(&"lens_id", "great-shaft-spire")
	var plank_path: Array[NodePath] = [lens.get_path_to(plank)]
	lens.set(&"targets", plank_path)
	_chest("M4-S1-chest", "dungeon-chest", _t(40.7, 33.9), {"coins": 50})
	_piece("prize-glint", "M4-S1-glint", _t(40.7, 33.3), {"phase": 0.6})
	_kit("lore", "M4-S1-heart-quarter", _t(40.7, 33.9), {"contents": "a heart quarter for the S1 chest once heart quarters exist (coins until then)"})
	# The shaft's north wall (the Feral skin, known; seen from the gallery on the first visit): from the
	# Den's broken south rim (x 42 to 45, level -1) roots and handholds run down the face to the shaft's
	# floor: climbed down (or let go: no cost), and the short way back up to the Den.
	_climb_pair("M14-shaft-roots", Vector2(44 * CELL, 29 * CELL), 1, Vector2(150, 160))
	# The calm room on the shaft's floor (M14): pots, two with hearts, a flower; the boss door east.
	_piece("energy-flower", "M14-flower", _t(46.0, 33.6), {})
	_pot("M14-pot", _t(42.4, 36.6), "heart")
	_pot("M14-pot", _t(43.4, 36.9), "heart")
	_pot("M14-pot", _t(44.4, 36.6), "energy")
	_piece("boss-door", "M14-boss-door", Vector2(47 * CELL, 36 * CELL), {"wall": "east", "door_id": "colossus-door"})
	# North: the Foreman's Gate, two keyholes (K1 and K2).
	_piece("key-door", "M4-foremans-gate", Vector2(24 * CELL, 31 * CELL), {"wall": "north", "door_id": "foremans-gate",
		"keyholes": 2, "locked_text": "Two locks. Two keys."})
	_props([
		[STRUCTURE + "interior-structure-beam-wood-vertical.tscn", _t(17.4, 37.6), 1.0],
		[WORKSHOP + "interior-workshop-lumber-stack.tscn", _t(19.8, 39.4), 0.9],
		[WORKSHOP + "interior-workshop-tool-rack.tscn", _t(17.8, 34.6), 0.9],
		[STORAGE + "interior-storage-crate-banded.tscn", _t(30.4, 31.6), 0.85],
		[WORKSHOP + "interior-workshop-ore-basket.tscn", _t(36, 39.5), 0.85],
	])
	_lanterns([_t(20, 31.1), _t(26.8, 31.1)])


func _m6_bat_gallery() -> void:
	var objects := _nodes["Objects"] as Node2D
	_rails([_t(45.5, 41), _t(45.5, 44), _t(43, 50.5), _t(34, 50.5)])
	_rails([_t(45.5, 50.5), _t(61.5, 50.5)])
	_enemy("M6-bat-1", "glint-bat", _t(42, 50.5), 80.0)
	_enemy("M6-bat-2", "glint-bat", _t(50, 50.5), 80.0)
	_enemy("M6-bat-3", "glint-bat", _t(55, 50.5), 80.0)
	_candle(objects, "M6-sconce-1", "sconce-iron", _t(37, 45.4), 60000.0)
	_candle(objects, "M6-sconce-2", "sconce-iron", _t(58.5, 45.4), 60000.0)
	var timbers := _scene(objects, OBJECTS + "rotten-timbers.tscn", "M6-rotten-timbers", _t(57, 55.4))
	timbers.set(&"flag_id", "crystal-mine.rotten-timbers")
	_scene(objects, OBJECTS + "gulp-spot-stone.tscn", "M6-stone-essence", _t(60.5, 53.4))
	# Secret S3: the east nook behind a web wall (the Silk skin), a silk parcel in it.
	var web := _scene(objects, OBJECTS + "web-wall.tscn", "M6-S3-web-wall", Vector2(63 * CELL + 14, 49 * CELL))
	web.set(&"orientation", "side")
	web.set(&"span", 128.0)
	web.set(&"hides_secret", true)
	var parcel := _scene(objects, OBJECTS + "silk-parcel.tscn", "M6-S3-parcel", _t(64.4, 49.6))
	parcel.set(&"coins", 30)
	parcel.set(&"contents", {"energy-potion": 1})
	_props([
		[WORKSHOP + "interior-workshop-wheelbarrow.tscn", _t(34.5, 46.2), 0.9],
		[STORAGE + "interior-storage-sack-grain.tscn", _t(48.3, 53.6), 0.85],
		[STRUCTURE + "interior-structure-beam-wood-vertical.tscn", _t(40, 54.4), 1.0],
		[STRUCTURE + "interior-structure-beam-wood-vertical.tscn", _t(52, 54.4), 1.0],
	])


func _m7_ore_store() -> void:
	var objects := _nodes["Objects"] as Node2D
	var scenery := _nodes["Scenery"] as Node2D
	# The east half: the Pick Mole behind its crates; K2 in the chest behind it.
	var mole := _t(53, 64.8)
	_enemy("M7-pick-mole", "pick-mole", mole, 70.0)
	for dx: float in [-58.0, 0.0, 58.0]:
		_prop(scenery, STORAGE + "interior-storage-crate.tscn", mole + Vector2(dx, -66), 1.0, "M7-mole-crate")
	_chest("M7-K2-chest", "dungeon-chest", mole + Vector2(0, 110), {"dungeon-small-key": 1})
	for spec: Array in [[_t(57.5, 60.5)], [_t(50, 61)], [_t(60.5, 65.5)]]:
		_ore_cart(scenery, spec[0])
	# The divider between the halves: ore carts, crates and a heap, a gap in the middle.
	_prop(scenery, OBJECTS + "rock-stump.tscn", _t(47.5, 59.6), 1.0, "M7-divider")
	_ore_cart(scenery, _t(47.6, 61.6))
	_prop(scenery, STORAGE + "interior-storage-crate-banded.tscn", _t(47.5, 66.2), 1.0, "M7-divider")
	_prop(scenery, OBJECTS + "ore-heap.tscn", _t(47.5, 67.8), 1.0, "M7-divider")
	# The west half: the Bone Leaper, met here first and alone; ore carts break its sight.
	_enemy("M7-bone-leaper", "bone-leaper", _t(38, 64), 90.0)
	_ore_cart(scenery, _t(41.5, 61))
	_ore_cart(scenery, _t(36, 66.6))
	# The crank lifts M1's shutter for good (the east wing's way back).
	var crank := _piece("winch", "M7-crank", _t(35, 59.8), {"winch_id": "ore-store-crank",
		"done_text": "The shutter to the mine mouth is up."})
	var crank_targets: Array[NodePath] = [crank.get_path_to(_nodes["M1-east-shutter"])]
	crank.set(&"targets", crank_targets)
	_lanterns([_t(38, 59.2), _t(55, 59.2), _t(61, 59.2)])
	_props([
		[WORKSHOP + "interior-workshop-lumber-stack.tscn", _t(34, 67.8), 0.9],
		[STORAGE + "interior-storage-barrel-open.tscn", _t(61.6, 62.5), 0.9],
		[WORKSHOP + "interior-workshop-ore-basket.tscn", _t(44.6, 67.8), 0.9],
	])


func _m8_dark_maze() -> void:
	var objects := _nodes["Objects"] as Node2D
	# The four corner candles: all four at once open the exit gate for good (60 s each).
	for spec: Array in [["M8-candle-nw", _t(2.2, 4.3)], ["M8-candle-ne", _t(24.2, 4.3)],
			["M8-candle-sw", _t(2.2, 25.5)], ["M8-candle-se", _t(29.4, 25.5)]]:
		var candle := _candle(objects, spec[0], "candlestick", spec[1], 60000.0)
		candle.set(&"group", "dark-maze")
		candle.set(&"gate_id", "dark-maze-exit")
	var gate := _scene(objects, OBJECTS + "lantern-gate.tscn", "M8-exit-gate", Vector2(29 * CELL, 9 * CELL - 4))
	gate.set(&"gate_id", "dark-maze-exit")
	gate.set(&"shut_text", "The gate is shut. The maze's four candles are cold.")
	# The goal's glow, seen from afar: a brazier burning beyond the gate.
	_candle(objects, "M8-goal-brazier", "brazier", _t(28.5, 4), 0.0, true)
	_enemy("M8-gloomling-candle", "gloomling", _t(2.2, 4.3), 80.0)
	_enemy("M8-gloomling-hoard", "gloomling", _t(8.5, 10.6), 80.0)
	_chest("M8-S4-hoard", "dungeon-chest", _t(8.5, 10.6), {"energy-potion": 2, "coins": 30})
	_piece("prize-glint", "M8-S4-glint", _t(8.5, 10.0), {"phase": 0.1})
	_enemy("M8-bat-top", "glint-bat", _t(14, 5), 80.0)
	_enemy("M8-bat-west", "glint-bat", _t(3, 15), 80.0)
	_enemy("M8-bat-bottom", "glint-bat", _t(16, 24.5), 80.0)
	# The void across the middle and the shadow path over it (the short way between the corners): a
	# fall puts the slime back at the path's mouth.
	_hazard("M8-void", Vector2i(11, 11), Vector2i(10, 11), [_t(10.5, 18.5)])
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _shadow_path():
		cells.append(cell - Vector2i(11, 15))
	_piece("shadow-path", "M8-shadow-path", _t(11, 15), {"cells": cells})
	_pot("M8-pot", _t(6, 24.5), "energy")


func _m9_chasm() -> void:
	var objects := _nodes["Objects"] as Node2D
	var station := _scene(objects, OBJECTS + "mine-cart.tscn", "M9-cart-station", _t(34.5, 11.2))
	station.set(&"station_id", "chasm")
	station.set(&"starts_with_cart", true)
	station.set(&"arrival", Vector2(0, -70))
	station.set(&"arrival_facing", Vector2.UP)
	_rails([_t(32.8, 11.2), _t(37, 11.2)])
	# The plank drawbridge stands raised on the far (east) rim; an arrow in the lens beside it lowers
	# it west across the chasm for good (rows 8, 9: below the chasm's far wall, whose five courses
	# hang over its first rows). A fall puts the slime back on the near edge.
	var bridge := _piece("drawbridge", "M9-chasm-bridge", Vector2(44 * CELL, 9 * CELL), {"toward": "west",
		"length": 6, "width": 128.0, "bridge_id": "chasm-bridge"})
	var lens := _scene(objects, OBJECTS + "crystal-lens.tscn", "M9-chasm-lens", _t(45.3, 7.7))
	lens.set(&"lens_id", "chasm-bridge")
	var bridge_path: Array[NodePath] = [lens.get_path_to(bridge)]
	lens.set(&"targets", bridge_path)
	_hazard("M9-chasm", Vector2i(38, 1), Vector2i(6, 12), [_t(36.5, 9)])
	# The far side's way on: the stair down into the Den (the Pearl room), x 44, 45.
	_enemy("M9-bone-thrower", "bone-thrower", _t(45.5, 10.2), 70.0)
	_prop(_nodes["Scenery"], OBJECTS + "rock-stump.tscn", _t(45.9, 5.6), 0.8, "M9-stump")
	_lanterns([_t(34, 3.2), _t(46, 3.2)])
	for at: Vector2 in [_t(39, 3), _t(42.5, 8), _t(40, 11.5)]:
		_glow(_nodes["Scenery"], "M9-vein-glow", at, Vector2(60, 26), Color(0.45, 0.75, 1.0, 0.28))


func _m10_prism_gallery() -> void:
	var objects := _nodes["Objects"] as Node2D
	# The optional Lantern wing (since 2026-10-17, behind M11's veil; its old door from the Chasm is
	# bricked): the Prism Eye, the heavy ore crate, and the war journal page that lay on M12's stand.
	_chest("M10-journal-chest", "dungeon-chest", _t(53.4, 3.9), {"coins": 30})
	_kit("lore", "M10-war-journal", _t(53.4, 3.9), {"contents": "a page of the Thorn Guard's war journal (it lay on M12's stand before 2026-10-17), for the M10 chest once pages exist"})
	# The veil's brazier on this side (M11's veil): lit, it opens the veil on the way back.
	_candle(objects, "M11-brazier-north", "brazier", _t(62.3, 11.6), 20000.0)
	_enemy("M10-prism-eye", "prism-eye", _t(55.5, 7.5), 40.0)
	_scene(objects, OBJECTS + "heavy-ore-crate.tscn", "M10-ore-crate", _t(50.5, 10.4))
	_rails([_t(49.5, 10.4), _t(59.5, 10.4), _t(59.5, 11.6)])
	_scene(objects, OBJECTS + "gulp-spot-stone.tscn", "M10-stone-essence", _t(49.6, 12.2))
	_lanterns([_t(51, 3.2), _t(60, 3.2)])
	_props([
		[OBJECTS + "rock-stump.tscn", _t(57, 11.8), 0.7],
		[WORKSHOP + "interior-workshop-ore-basket.tscn", _t(61.8, 4), 0.85],
	])


func _m11_crystal_veil() -> void:
	var objects := _nodes["Objects"] as Node2D
	# The test (the Feral skin's second room): the rift two levels deep across the way from the Den's door
	# (the west landing) to M12's (the east landing). Climb down the west landing's face, cross the rift's
	# floor, climb up the east landing's; back the other way with the big key. Dark: the slime's ember
	# shows the handholds.
	_climb_pair("M11-west-roots", Vector2(51.5 * CELL, 23 * CELL), 2)
	_climb_pair("M11-east-roots", Vector2(59.5 * CELL, 23 * CELL), 2)
	# The optional Lantern wing: the veil across the mouth of the doorway north to M10, its brazier on
	# the east landing (20 s) and one on M10's side; two Glint Bats roost over it.
	var south := _candle(objects, "M11-brazier-south", "brazier", _t(58.7, 18.1), 20000.0)
	var north := _nodes["M11-brazier-north"] as Node2D
	var veil := _scene(objects, OBJECTS + "crystal-veil.tscn", "M11-veil", Vector2(61 * CELL, 17 * CELL))
	veil.set(&"size", 3 * CELL)
	var linked: Array[NodePath] = [veil.get_path_to(north), veil.get_path_to(south)]
	veil.set(&"braziers", linked)
	_enemy("M11-bat-1", "glint-bat", _t(60.5, 15.4), 40.0)
	_enemy("M11-bat-2", "glint-bat", _t(61.5, 14.6), 40.0)
	_pot("M11-pot", _t(50.3, 18.6), "energy")


func _m12_fort_hall() -> void:
	var objects := _nodes["Objects"] as Node2D
	# The twist (the Feral skin's third room): the balcony two levels up along the north wall holds the big
	# chest, and two root walls climb to it. A climber cannot hide or dodge: the Watcher Eye's beam finds
	# it and the Bone Marcher's loop passes the walls' feet, so a climb starts when the eye looks away
	# and the Marcher has passed. Off the balcony's west end a drop lands by the west door.
	_climb_pair("M12-west-roots", Vector2(68 * CELL, 18 * CELL), 2)
	_climb_pair("M12-east-roots", Vector2(75 * CELL, 18 * CELL), 2)
	_chest("M12-big-key-chest", "dungeon-big-chest", _t(71.5, 16.8), {"dungeon-big-key": 1})
	_piece("prize-glint", "M12-big-key-glint", _t(71.5, 15.9), {"phase": 0.5, "only_in_dark": false})
	# The five armour statues (heavy blocks), cover from the eye, at least three cells from the roots.
	for at: Vector2 in [_t(71.5, 23.9), _t(67.4, 24.9), _t(76.8, 24.6), _t(69.8, 25.7), _t(73.6, 25.7)]:
		_scene(objects, OBJECTS + "heavy-statue.tscn", "M12-statue", at)
	_enemy("M12-watcher-eye", "watcher-eye", _t(71.5, 21.8), 150.0)
	var marcher := _enemy("M12-bone-marcher", "bone-marcher", _t(66.4, 20.9), 40.0)
	marcher.set(&"overrides", {"route": PackedVector2Array([Vector2.ZERO, Vector2(704, 0), Vector2(704, 100), Vector2(0, 100)]), "route_loop": true})
	_candle(objects, "M12-watchfire-w", "brazier", _t(65.5, 23.6), 0.0, true)
	_candle(objects, "M12-watchfire-e", "brazier", _t(78.4, 23.6), 0.0, true)
	_scene(objects, OBJECTS + "gulp-spot-stone.tscn", "M12-stone-essence", _t(65.8, 26.0))
	_props([
		[DECOR + "interior-decor-banner-red-narrow.tscn", _t(70.3, 20.05), 1.0],
		[DECOR + "interior-decor-banner-red-narrow.tscn", _t(72.7, 20.05), 1.0],
		[STRUCTURE + "interior-structure-pillar-stone.tscn", _t(78, 25.9), 1.0],
	])


func _m13_shardback_den() -> void:
	var objects := _nodes["Objects"] as Node2D
	var scenery := _nodes["Scenery"] as Node2D
	# The Pearl room (the plan's M13): down the stair from the Chasm's far side, one level below it. The
	# Shardback's fight as built (dark 6: fire light makes his shell brittle, the Lantern's twist), once,
	# his `boss_id` recorded: the north shutter closes the stair behind the slime; won, it opens, the
	# south rim's shutter sinks for good (the way down the shaft's wall) and Pearl 3 rises in its vault
	# of crystal, where the Colossus kept it (it fed the crystal he grew from).
	var west := _candle(objects, "M13-brazier-w", "brazier", _t(35.6, 20.6), 20000.0)
	var east := _candle(objects, "M13-brazier-e", "brazier", _t(41.6, 19.6), 20000.0)
	west.set(&"stomp_puts_out", true)
	east.set(&"stomp_puts_out", true)
	_enemy("M13-shardback", "shardback", _t(38.4, 22.0), 200.0)
	_piece("shutter", "M13-den-shutter", Vector2(45 * CELL, 16 * CELL), {"wall": "north", "fight_id": "shardback-den",
		"shutter_id": "den-north"})
	# The broken south rim (four cells, x 42 to 45): two shutters, shut until he falls.
	var rim := _piece("shutter", "M13-den-ledge", Vector2(43 * CELL, 27 * CELL), {"wall": "south", "starts_shut": true,
		"shutter_id": "den-ledge"})
	var rim_east := _piece("shutter", "M13-den-ledge-east", Vector2(45 * CELL, 27 * CELL), {"wall": "south", "starts_shut": true,
		"shutter_id": "den-ledge-east"})
	var fight := _piece("room-fight", "M13-den-fight", Vector2(32 * CELL, 14 * CELL), {"size": Vector2(16, 14) * CELL,
		"fight_id": "shardback-den", "once": true, "boss_id": SHARDBACK_ID})
	fight.connect(&"cleared", Callable(rim, &"trigger"), CONNECT_PERSIST)
	fight.connect(&"cleared", Callable(rim_east, &"trigger"), CONNECT_PERSIST)
	# Pearl 3 on its crystal cradle, its glint seen from the stair through the whole fight; the
	# Shardback guards it (`boss_id`): it rises when he falls.
	var pearl := _scene(objects, OBJECTS + "pearl-three.tscn", "M13-pearl-three", _t(39.5, 24.7))
	pearl.set(&"boss_id", SHARDBACK_ID)
	pearl.set(&"take_radius", 48.0)
	pearl.set(&"card_line", "The beast the Pearl woke in the Colossus is yours: you climb walls of thick roots and rocky handholds.")
	var glint := _piece("prize-glint", "M13-pearl-glint", _t(39.5, 23.5), {"only_in_dark": false, "tint": Color(1.0, 0.86, 0.6)})
	var mine := _root.get_node("CrystalMine")
	mine.set(&"pearl", mine.get_path_to(pearl))
	mine.set(&"pearl_glint", mine.get_path_to(glint))
	for spec: Array in [[3, _t(37.9, 25.3)], [7, _t(41.1, 25.3)], [11, _t(38.4, 26.2)], [5, _t(40.6, 26.2)]]:
		_prop(scenery, OBJECTS + "crystal-cluster-wall--%02d.tscn" % int(spec[0]), spec[1], 0.8, "M13-vault-crystal")
	# The teach (the Feral skin's first lock, safe: no enemy, no fall, no timer): the root wall up the
	# ledge's face (one level) to the east door, the way on to M11.
	_climb_pair("M13-ledge-roots", Vector2(45.5 * CELL, 24 * CELL), 1)


func _m15_colossus_arena() -> void:
	var objects := _nodes["Objects"] as Node2D
	for spec: Array in [["M15-brazier-nw", _t(51.2, 35.4)], ["M15-brazier-ne", _t(60.8, 35.4)],
			["M15-brazier-sw", _t(51.2, 39.6)], ["M15-brazier-se", _t(60.8, 39.6)]]:
		var brazier := _candle(objects, spec[0], "brazier", spec[1], -1.0)
		brazier.set(&"stomp_puts_out", true)
	var arena := Node2D.new()
	arena.name = "ColossusArena"
	arena.set_script(load(COLOSSUS_ARENA))
	arena.position = _t(56, 36.5)
	arena.set(&"arena_rect", Rect2(_t(49, 33), Vector2(14 * CELL, 8 * CELL)))
	arena.set(&"post", Vector2(0, -150))
	arena.set(&"seal_cells", PackedVector2Array([_t(48.5, 35.9), _t(48.5, 36.9)]))
	# His climb spots on the north wall's foot (old centres), and the roots beside them.
	arena.set(&"climb_spots", PackedVector2Array([Vector2(51.5 * CELL, 2092), Vector2(54.5 * CELL, 2092), Vector2(57.5 * CELL, 2092)]))
	arena.set(&"wall_rect", Rect2(_t(49, 29), Vector2(14 * CELL, 4 * CELL + 40)))
	_own(arena, objects)
	arena.set(&"braziers", _paths(arena, ["M15-brazier-nw", "M15-brazier-ne", "M15-brazier-sw", "M15-brazier-se"]))
	# The Feral skin's exam: roots beside each climb spot run up the wall to his height and end on the face
	# (`holds_at_top`); from there the Spear strikes his claws (crystal_colossus.gd).
	for x: float in [50.0, 53.0, 56.0, 59.0]:
		var roots := _scene(objects, OBJECTS + "climb-wall.tscn", "M15-claw-roots", Vector2(x * CELL, 33 * CELL + 20))
		roots.set(&"top", Vector2(0, -197))
		roots.set(&"holds_at_top", true)
		roots.set(&"art_size", Vector2(112, 250))
	# The climb out to the Lookout, beside them: its top is sealed (Pearl 3's take) until he falls.
	var climb := _scene(objects, OBJECTS + "climb-wall.tscn", "M15-root-wall", Vector2(61.2 * CELL, 33 * CELL + 20))
	climb.set(&"top", Vector2(0, -312))
	climb.set(&"exit_area_id", "crystal-caverns-h4")
	climb.set(&"exit_marker", "arrive-from-crystal-mine")
	climb.set(&"art_size", Vector2(104, 300))
	arena.set(&"climb_wall", arena.get_path_to(climb))
	# The seal stands at the climb-out's foot, in front of its roots, until he falls.
	_piece("dungeon-seal", "M15-climb-out-seal", Vector2(61.2 * CELL, 33 * CELL + 4), {"wall": "north"})
	_glow(_nodes["Scenery"], "M15-daylight", _t(61.2, 28.6), Vector2(110, 64), Color(1.0, 0.93, 0.7, 0.32))
	# His full heart (+20 max HP, +20 max energy): it rises when he falls.
	var heart := _scene(objects, FULL_HEART, "M15-full-heart", _t(58.4, 38.4))
	_root.set_editable_instance(heart, true)
	heart.get_node("FullHeartScript").set(&"heart_id", "crystal-colossus")
	heart.get_node("FullHeartScript").set(&"boss_id", "crystal-colossus")


# --- helpers -------------------------------------------------------------------------------------------

## The centre of tile (x, y) for fractional x, y: tile units to world units.
static func _t(x: float, y: float) -> Vector2:
	return Vector2(x * CELL, y * CELL)


func _own(node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = _root


func _marker(parent: Node, marker_name: String, at: Vector2) -> Node2D:
	var marker := Node2D.new()
	marker.name = marker_name
	marker.position = at
	_own(marker, parent)
	return marker


func _unique(parent: Node, base: String) -> String:
	var unique := base
	var n := 2
	while parent.has_node(NodePath(unique)):
		unique = "%s-%d" % [base, n]
		n += 1
	return unique


func _scene(parent: Node, path: String, node_name: String, at: Vector2) -> Node2D:
	var node := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	node.name = _unique(parent, node_name)
	node.position = at
	_own(node, parent)
	node.set_meta(&"instance_id", "%s-%s" % [MAP_ID, node.name])
	node.set_meta(&"persistence_key", "%s.%s-%s" % [MAP_ID, MAP_ID, node.name])
	_nodes[node_name] = node
	return node


func _prop(parent: Node, path: String, at: Vector2, size: float, node_name: String) -> Node2D:
	if not ResourceLoader.exists(path):
		push_warning("no prop " + path)
		return null
	var prop := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	prop.name = _unique(parent, node_name)
	prop.position = at
	prop.scale = Vector2(size, size)
	_own(prop, parent)
	return prop


func _props(specs: Array) -> void:
	for spec: Array in specs:
		_prop(_nodes["Scenery"], spec[0], spec[1], spec[2], (spec[0] as String).get_file().get_basename())


func _ore_cart(parent: Node, at: Vector2) -> void:
	var cart := StaticBody2D.new()
	cart.name = _unique(parent, "ore-cart")
	cart.position = at
	cart.collision_mask = 0
	_own(cart, parent)
	var shape := CollisionShape2D.new()
	shape.name = "BodyShape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(66, 26)
	shape.shape = rect
	shape.position = Vector2(0, -13)
	_own(shape, cart)
	var visual := Sprite2D.new()
	visual.name = "Visual"
	visual.set_script(load(SHEET_SPRITE))
	visual.set(&"sheet_path", "res://asset/MAPS/props/mine/256x256-mine-cart.webp")
	visual.centered = false
	visual.offset = Vector2(-128, -252)
	visual.scale = Vector2(0.32, 0.32)
	_own(visual, cart)


func _liftable(parent: Node, node_name: String, kind: String, at: Vector2) -> void:
	var thing := (load(OBJECTS + "liftable.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	thing.name = _unique(parent, node_name)
	thing.position = at
	_own(thing, parent)
	_root.set_editable_instance(thing, true)
	thing.get_node("LiftableScript").set(&"kind", kind)


## A candle, sconce or brazier: `look` "sconce-iron", "candlestick" (interior props with lit and
## unlit looks) or "brazier" (object.brazier). `burn_ms` as candle.gd's.
func _candle(parent: Node, node_name: String, look: String, at: Vector2, burn_ms: float, lit: bool = false) -> Node2D:
	var node: Node2D
	if look == "brazier":
		node = _scene(parent, OBJECTS + "brazier.tscn", node_name, at)
	else:
		node = Node2D.new()
		node.name = _unique(parent, node_name)
		node.y_sort_enabled = true
		node.position = at
		node.set_script(load(CANDLE))
		node.set(&"unlit_scene", load(DECOR + "interior-decor-%s-unlit.tscn" % look))
		node.set(&"lit_scene", load(DECOR + "interior-decor-%s-lit.tscn" % look))
		if look == "sconce-iron":
			node.set(&"flame_offset", Vector2(0, -78))
		_own(node, parent)
		node.set_meta(&"instance_id", "%s-%s" % [MAP_ID, node.name])
		node.set_meta(&"persistence_key", "%s.%s-%s" % [MAP_ID, MAP_ID, node.name])
		_nodes[node_name] = node
	node.set(&"burn_ms", burn_ms)
	node.set(&"lit_at_start", lit)
	return node


func _enemy(node_name: String, type: String, at: Vector2, wander: float) -> Node2D:
	var holder := _nodes["Enemies"] as Node2D
	var placed := (load(PLACED_ENEMY) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	placed.name = _unique(holder, node_name)
	placed.position = at
	placed.set(&"enemy_type", type)
	placed.set(&"wander_radius", wander)
	_own(placed, holder)
	return placed


## A dungeon-kit piece (docs/godot/DUNGEONS.md): `KIT + kit_scene + ".tscn"` under Objects, with its
## properties.
func _piece(kit_scene: String, node_name: String, at: Vector2, props: Dictionary) -> Node2D:
	var node := _scene(_nodes["Objects"], KIT + kit_scene + ".tscn", node_name, at)
	for key: String in props:
		node.set(StringName(key), props[key])
	return node


## A dungeon chest (`dungeon-chest` or `dungeon-big-chest`) with `contents`; `hidden` until set off.
func _chest(node_name: String, kit_scene: String, at: Vector2, contents: Dictionary, hidden: bool = false) -> Node2D:
	var chest := _piece(kit_scene, node_name, at, {})
	_root.set_editable_instance(chest, true)
	var script_node := chest.get_node("ChestScript")
	script_node.set(&"instance_id", "%s-%s" % [MAP_ID, chest.name])
	script_node.set(&"initial_contents", contents)
	script_node.set(&"hidden", hidden)
	return chest


## A pot that grows back with its room, hiding `loot` ("heart", "energy", "coins", "random").
func _pot(node_name: String, at: Vector2, loot: String) -> void:
	var pot := _piece("dungeon-pot", node_name, at, {})
	_root.set_editable_instance(pot, true)
	pot.get_node("PotLoot").set(&"loot", loot)


## The void over an elevation hole (cells `from`, `cells` big; the hole draws itself), with the
## points a fall puts the slime back at (its children `Return...`).
func _hazard(node_name: String, from: Vector2i, cells: Vector2i, returns: Array) -> Node2D:
	var hazard := _piece("hazard", node_name, Vector2(from * CELL), {"kind": "void", "size": Vector2(cells * CELL),
		"rim_level": 0, "draw_look": false})
	var i := 0
	for at: Vector2 in returns:
		var back := Node2D.new()
		back.name = "Return%d" % i
		back.position = at - hazard.position
		_own(back, hazard)
		i += 1
	return hazard


## A root wall up a south face and its way back down from the lip (the Feral skin; climb_wall.gd, the
## placing rules in docs/godot/SKINS.md "Feral"): `rim` is the face's top edge at the climb's middle,
## `levels` its height. The up climb stands at the foot (its feet 20 px below the face's foot line) and
## ends 40 px inside the rim; the down climb on the lip (20 px inside the rim) ends 30 px below the
## foot line, sharing the up climb's picture.
func _climb_pair(base: String, rim: Vector2, levels: int, art: Vector2 = Vector2.ZERO) -> Node2D:
	var objects := _nodes["Objects"] as Node2D
	var foot := rim.y + levels * CELL
	var up := _scene(objects, OBJECTS + "climb-wall.tscn", base, Vector2(rim.x, foot + 20.0))
	up.set(&"top", Vector2(0, (rim.y - 40.0) - (foot + 20.0)))
	up.set(&"art_size", art if art != Vector2.ZERO else Vector2(130, levels * CELL + 44))
	var down := _scene(objects, OBJECTS + "climb-wall.tscn", base + "-down", Vector2(rim.x, rim.y - 20.0))
	down.set(&"top", Vector2(0, (foot + 30.0 - FEET_TO_CENTRE) - (rim.y - 20.0)))
	down.set(&"prompt", "Climb down (hold)")
	down.set(&"show_art", false)
	down.set(&"grab_width", 130.0)
	return up


## A kit marker: where something nothing builds yet goes, with what it is.
func _kit(kind: String, node_name: String, at: Vector2, data: Dictionary) -> void:
	var marker := _marker(_nodes["KitMarkers"], node_name, at)
	marker.set_meta(&"kit", kind)
	for key: String in data:
		marker.set_meta(StringName(key), data[key])


func _rails(points: Array) -> void:
	var rails := Node2D.new()
	rails.name = _unique(_nodes["Rails"], "rails")
	rails.set_script(load(RAILS))
	var first: Vector2 = points[0]
	rails.position = first
	var local := PackedVector2Array()
	for p: Vector2 in points:
		local.append(p - first)
	rails.set(&"points", local)
	_own(rails, _nodes["Rails"])


func _lanterns(points: Array) -> void:
	for at: Vector2 in points:
		var lamp := Sprite2D.new()
		lamp.name = _unique(_nodes["Scenery"], "mine-lantern")
		lamp.set_script(load(SHEET_SPRITE))
		lamp.set(&"sheet_path", LANTERN_ART)
		lamp.centered = false
		lamp.offset = Vector2(-64, -124)
		lamp.scale = Vector2(0.5, 0.5)
		lamp.position = at
		_own(lamp, _nodes["Scenery"])


## A soft additive glow (crystal veins, daylight), drawn by game/prologue/soft_glow.gd.
func _glow(parent: Node, glow_name: String, at: Vector2, radius: Vector2, color: Color) -> void:
	var glow := Node2D.new()
	glow.name = _unique(parent, glow_name)
	glow.set_script(load("res://game/prologue/soft_glow.gd"))
	glow.position = at
	glow.set(&"radius", radius)
	glow.set(&"color", color)
	glow.set(&"additive", true)
	glow.set(&"pulse", 0.2)
	glow.set(&"period_s", 5.0)
	glow.z_index = 3
	_own(glow, parent)
