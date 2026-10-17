extends SceneTree
## Builds Fatty's Lair's world, game/scenes/worlds/fatty-lair.tscn (docs/godot/DUNGEONS.md "Fatty's
## Lair (built)"; the plan: docs/design/2026-10-16-dungeon-fattys-lair.md). Re-runnable while the Lair
## is being built: it rewrites the whole scene from the layout below, so hand edits are lost when it
## runs again (once the Lair is final, the scene is the one to edit and this tool is history).
##
##     "<Godot console exe>" --headless --path godot -s res://tools/build_fattys_lair.gd
##
## The room grammar is the Weaver Hollow's (tools/weaver_hollow/hollow_canvas.gd): a mass of rock at
## ROCK_LEVEL with the rooms carved out of it at level 0, every camera room (16 x 14 cells) keeping a
## one-cell rim of rock, so two rooms side by side are parted by a two-cell band whose south face is a
## wall of two stone courses (ELEVATION.md "Side walls"); doors are gaps through the bands. Voids are
## holes at VOID_LEVEL with the kit's void hazards over them (a fall goes back to the last safe
## ground); the spike pit is a hole at PIT_LEVEL with a flight of stairs out and a spikes hazard. A
## bridge is the kit's falling slabs over hole cells (each slab opens its passage when the world is
## built), with a landing wherever a Roll ends. The upper fort's walls are masonry, the Deep's cave
## rock, painted on the `cliffs` layer.
##
## The dungeon kit's pieces (game/dungeon/, docs/godot/DUNGEONS.md) are placed from their scenes
## (`object.<kind>`, game/scenes/objects/dungeon/).
##
## Owner: dungeons (Fatty's Lair).

const OUT := "res://game/scenes/worlds/fatty-lair.tscn"
const MAP_ID := "fatty-lair"
const OUTSIDE_MAP := "level-1-d4"
const TILE := 64
const ROOM_W := 16
const ROOM_H := 14
const GRID := Vector2i(5, 5)
const ROCK_LEVEL := 2
const VOID_LEVEL := -3
const PIT_LEVEL := -1
const COBBLE := 19
const CAVERN := 1
const FOREST_FLOOR := 4
const FOREST_MOSS := 5
## The Deep's earth floors (the amberleaf sheet: rust-brown earth).
const EARTH := 0
## The rock mass's top, unlike every floor, so rooms read apart from the rock round them.
const ROCK_TOP := FOREST_FLOOR
## Stone doors (object.latch-door) stand in one-cell gaps at this scale.
const LATCH_DOOR_SCALE := Vector2(0.55, 0.55)
const SHEET_TILES := 19
const STYLE_TILES := {"masonry": 6, "cave-rock": 3, "root-rock": 7}
const STAIRS_ROW := 2
const STAIRS_COLUMNS := {"s": 0, "n": 4, "e": 6, "w": 2}

const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const CLIFF_TILESET := "res://game/world/elevation/cliffs/cliff_tileset.tres"
const CLIFF_LAYER := "res://game/world/elevation/cliffs/cliff_layer.gd"
const WALL_TILESET := "res://game/world/walls/wall_tileset.tres"
const WALL_LAYER := "res://game/world/walls/wall_layer.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CAMERA_ROOM := "res://game/world/camera_room.gd"
const DOOR := "res://game/scripts/door.gd"
const DARK_ROOM := "res://game/world/darkness/dark_room.gd"
const CANDLE := "res://game/world/fire/candle.gd"
const DUNGEON := "res://game/dungeon/dungeon.gd"
const DIRECTOR := "res://game/fattys_lair/lair_director.gd"
const SOFT_GLOW := "res://game/prologue/soft_glow.gd"
const VOID_SHADE := "res://game/fattys_lair/void_shade.gd"
const PLACED_ENEMY := "res://game/scenes/encounters/placed-enemy.tscn"
const OBJ := "res://game/scenes/objects/%s.tscn"
const SCONCE_LIT := "res://game/scenes/objects/interiors/decor/interior-decor-sconce-iron-lit.tscn"
const SCONCE_UNLIT := "res://game/scenes/objects/interiors/decor/interior-decor-sconce-iron-unlit.tscn"
## The kit's scenes (docs/godot/DUNGEONS.md), by the ids its doc gives them.
## The dungeon kit's scenes (docs/godot/DUNGEONS.md): `object.<kind>`.
const KIT := "res://game/scenes/objects/dungeon/%s.tscn"

## The rooms: grid cell (column, row: A..E, 2..6 as 0..4), size in rooms, the ground of its floor,
## its wall style, whether it is in the Deep (darker), its camera room name.
const ROOMS := {
	"r10": {"cell": Vector2i(0, 0), "size": Vector2i(2, 1), "ground": EARTH, "style": "cave-rock", "name": "r10-dung-roller-run"},
	"bolt": {"cell": Vector2i(3, 0), "size": Vector2i(1, 1), "ground": EARTH, "style": "root-rock", "name": "bolt-hole", "carve": false},
	"r9": {"cell": Vector2i(0, 1), "size": Vector2i(1, 1), "ground": COBBLE, "style": "cave-rock", "name": "r9-watcher-hall"},
	"r8": {"cell": Vector2i(1, 1), "size": Vector2i(1, 2), "ground": COBBLE, "style": "cave-rock", "name": "r8-guard-crypt"},
	"r12": {"cell": Vector2i(2, 1), "size": Vector2i(1, 1), "ground": COBBLE, "style": "cave-rock", "name": "r12-larder"},
	"r14": {"cell": Vector2i(3, 1), "size": Vector2i(1, 1), "ground": COBBLE, "style": "masonry", "name": "r14-pearl-shrine"},
	"arm": {"cell": Vector2i(0, 2), "size": Vector2i(1, 1), "ground": EARTH, "style": "cave-rock", "name": "old-armoury"},
	"r11": {"cell": Vector2i(2, 2), "size": Vector2i(1, 1), "ground": COBBLE, "style": "cave-rock", "name": "r11-drop-gate-bridge"},
	"r13": {"cell": Vector2i(3, 2), "size": Vector2i(1, 1), "ground": COBBLE, "style": "root-rock", "name": "r13-fattys-arena"},
	"bur": {"cell": Vector2i(4, 2), "size": Vector2i(1, 1), "ground": EARTH, "style": "root-rock", "name": "glow-moss-burrow"},
	"nook": {"cell": Vector2i(0, 3), "size": Vector2i(1, 1), "ground": COBBLE, "style": "masonry", "name": "map-nook", "carve": false},
	"r4": {"cell": Vector2i(1, 3), "size": Vector2i(1, 1), "ground": COBBLE, "style": "masonry", "name": "r4-squint-den"},
	"hub": {"cell": Vector2i(2, 3), "size": Vector2i(2, 1), "ground": COBBLE, "style": "masonry", "name": "r3-pit-hall"},
	"r6": {"cell": Vector2i(4, 3), "size": Vector2i(1, 1), "ground": COBBLE, "style": "masonry", "name": "r6-pipe-gallery"},
	"sally": {"cell": Vector2i(0, 4), "size": Vector2i(1, 1), "ground": COBBLE, "style": "masonry", "name": "sally-port", "carve": false},
	"r5": {"cell": Vector2i(1, 4), "size": Vector2i(1, 1), "ground": COBBLE, "style": "masonry", "name": "r5-eye-hall"},
	"r1": {"cell": Vector2i(2, 4), "size": Vector2i(1, 1), "ground": COBBLE, "style": "masonry", "name": "r1-gatehouse"},
	"r2": {"cell": Vector2i(3, 4), "size": Vector2i(1, 1), "ground": COBBLE, "style": "masonry", "name": "r2-slab-steps"},
	"r7": {"cell": Vector2i(4, 4), "size": Vector2i(1, 1), "ground": COBBLE, "style": "masonry", "name": "r7-bell-bridge"},
}

## Where the kit's `room=<CameraRoom name>` launch option starts each room (its `RoomEntry`, local
## cells): at the door it is first walked in by.
const ROOM_ENTRIES := {
	"r1": Vector2(8, 9), "r2": Vector2(2.5, 11.5), "hub": Vector2(8, 11.5), "r4": Vector2(13, 7.5),
	"r5": Vector2(8, 4.5), "r6": Vector2(3, 7.5), "r7": Vector2(8, 3.8), "r8": Vector2(4, 24.6),
	"r9": Vector2(13, 7.5), "r10": Vector2(8, 8.8), "r11": Vector2(2.5, 11.5), "r12": Vector2(12, 11.5),
	"r13": Vector2(8, 11.5), "r14": Vector2(8, 11), "arm": Vector2(13.5, 7.5), "bur": Vector2(8, 11.8),
	"nook": Vector2(13, 7.5), "sally": Vector2(13, 6.5), "bolt": Vector2(8, 9),
}

var cols := GRID.x * ROOM_W
var rows := GRID.y * ROOM_H
var ground := PackedInt32Array()
var level := PackedInt32Array()
var stairs := PackedInt32Array()
var cliffs := PackedInt32Array()
var walls := PackedByteArray()
var scene_root: Node2D
var scenery: Node2D
var enemies: Node2D
var objects: Node2D
## The hazards' looks, under every deck and body (not y-sorted: drawn before Objects).
var hazards: Node2D
var lair: Node2D
var _kit_placed := 0
## Instances whose children were given values: marked editable so the scene keeps them.
var _editable: Array[Node] = []
## Hole cells held by a deck (slabs, landings, the drawbridge): the void shade leaves them.
var deck_cells: Dictionary = {}


func _initialize() -> void:
	var count := cols * rows
	ground.resize(count)
	ground.fill(ROCK_TOP)
	level.resize(count)
	level.fill(ROCK_LEVEL)
	stairs.resize(count)
	stairs.fill(-1)
	cliffs.resize(count)
	cliffs.fill(STYLE_TILES["cave-rock"])
	walls.resize(count)
	walls.fill(0)
	_paint_styles()
	for key: String in ROOMS:
		if bool(ROOMS[key].get("carve", true)):
			_carve_room(key)
	_carve_doors()
	_carve_features()
	_build_scene()
	var err := _save()
	print("fatty-lair: %s, %d x %d cells, kit pieces %d" % [
		"saved " + OUT if err == OK else "ERROR %d" % err, cols, rows, _kit_placed])
	quit(0 if err == OK else 1)


# --- the cells ---------------------------------------------------------------------------------------

func _i(x: int, y: int) -> int:
	return y * cols + x


func _in(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < cols and y < rows


## The room's top-left cell.
func _origin(key: String) -> Vector2i:
	var cell: Vector2i = ROOMS[key]["cell"]
	return Vector2i(cell.x * ROOM_W, cell.y * ROOM_H)


func _cell(x: int, y: int, lvl: int, ground_source: int = -2) -> void:
	if not _in(x, y):
		return
	level[_i(x, y)] = lvl
	if ground_source != -2:
		ground[_i(x, y)] = ground_source


## Room-local cells (lx, ly) of room `key`, a rectangle, at `lvl` with the room's ground.
func _rect(key: String, lx: int, ly: int, w: int, h: int, lvl: int) -> void:
	var o := _origin(key)
	var source := int(ROOMS[key]["ground"])
	if lvl == VOID_LEVEL or lvl == PIT_LEVEL:
		source = CAVERN
	elif lvl == ROCK_LEVEL:
		source = ROCK_TOP
	for y in range(ly, ly + h):
		for x in range(lx, lx + w):
			_cell(o.x + x, o.y + y, lvl, source)


func _wall_cells(key: String, cells: Array) -> void:
	var o := _origin(key)
	for cell: Vector2i in cells:
		if _in(o.x + cell.x, o.y + cell.y):
			walls[_i(o.x + cell.x, o.y + cell.y)] = 1


func _stairs(key: String, lx: int, ly: int, way: String) -> void:
	var o := _origin(key)
	stairs[_i(o.x + lx, o.y + ly)] = int(STAIRS_COLUMNS[way])


## Each room's own cells (its rims) take its wall style, and so does the room above's bottom rim:
## its south face is this room's north wall.
func _paint_styles() -> void:
	for key: String in ROOMS:
		var room: Dictionary = ROOMS[key]
		var o := _origin(key)
		var size: Vector2i = room["size"]
		var tile := int(STYLE_TILES[room["style"]])
		for y in range(o.y, o.y + size.y * ROOM_H):
			for x in range(o.x, o.x + size.x * ROOM_W):
				cliffs[_i(x, y)] = tile
				ground[_i(x, y)] = ROCK_TOP
	for key: String in ROOMS:
		var room: Dictionary = ROOMS[key]
		var o := _origin(key)
		var size: Vector2i = room["size"]
		var tile := int(STYLE_TILES[room["style"]])
		for x in range(o.x, o.x + size.x * ROOM_W):
			if _in(x, o.y - 1):
				cliffs[_i(x, o.y - 1)] = tile


## The floor inside the rim, at level 0.
func _carve_room(key: String) -> void:
	var size: Vector2i = ROOMS[key]["size"]
	_rect(key, 1, 1, size.x * ROOM_W - 2, size.y * ROOM_H - 2, 0)


## A door gap through the band between two rooms: `a` above or left of `b`; `at` the first of its
## two cells along the shared wall (a column for a horizontal wall, a row for a vertical one), in
## world cells.
func _door_h(top: String, bottom: String, column: int) -> void:
	var o := _origin(bottom)
	for x in [column, column + 1]:
		_cell(x, o.y - 1, 0, int(ROOMS[top]["ground"]))
		_cell(x, o.y, 0, int(ROOMS[bottom]["ground"]))


## An east-west door also clears the two rows above it: the wall above hangs its face over them
## (DUNGEONS.md "Walls and doorways") and the slime walks under it.
func _door_v(left: String, right: String, row: int) -> void:
	var o := _origin(right)
	for y in range(row - 2, row + 2):
		_cell(o.x - 1, y, 0, int(ROOMS[left]["ground"]))
		_cell(o.x, y, 0, int(ROOMS[right]["ground"]))


## World column of room `key`'s local column `lx`; world row of its local row `ly`.
func _cx(key: String, lx: int) -> int:
	return _origin(key).x + lx


func _cy(key: String, ly: int) -> int:
	return _origin(key).y + ly


func _carve_doors() -> void:
	_door_h("hub", "r1", _cx("hub", 7))
	_door_h("hub", "r2", _cx("hub", 23))
	_door_v("r1", "r2", _cy("r1", 10))
	_door_v("r5", "r1", _cy("r1", 10))
	_door_v("r2", "r7", _cy("r2", 3))
	# The hub's west door comes in below Burr's cell (ly 3..7, its door at ly 8).
	_door_v("r4", "hub", _cy("hub", 9))
	_door_v("hub", "r6", _cy("hub", 6))
	_door_h("r4", "r5", _cx("r4", 7))
	_door_v("nook", "r4", _cy("r4", 6))
	_door_h("r6", "r7", _cx("r6", 7))
	_door_h("bur", "r6", _cx("r6", 7))
	_door_h("r11", "hub", _cx("hub", 7))
	_door_h("r13", "hub", _cx("hub", 23))
	_door_h("r14", "r13", _cx("r13", 7))
	_door_h("bolt", "r14", _cx("r14", 7))
	_door_v("r9", "r8", _cy("r8", 6))
	_door_v("arm", "r8", _cy("r8", 20))
	_door_h("r10", "r8", _cx("r8", 7))
	_door_h("r10", "r9", _cx("r9", 7))
	_door_v("r8", "r11", _cy("r11", 11))
	_door_h("r12", "r11", _cx("r11", 11))
	# The entrance from Fatty's Hollow: R1's south rim, open to the world's bottom edge.
	_cell(_cx("r1", 7), _cy("r1", 13), 0, COBBLE)
	_cell(_cx("r1", 8), _cy("r1", 13), 0, COBBLE)


func _carve_features() -> void:
	# R1 Gatehouse: the Quartermaster's store, a closet of built wall in the north-east corner, its
	# gap (lx 12..13) the plank barricade's.
	_wall_cells("r1", [Vector2i(11, 3), Vector2i(11, 4), Vector2i(11, 5), Vector2i(14, 5)])
	# R2 Slab Steps: an L of void, two slabs over its west arm; over its north arm two slabs and a
	# landing (a kit deck) where that Roll ends, against the north rim. A Roll crosses two slabs
	# from the rim's edge (DUNGEONS.md "Falling slabs"); two Rolls in a row with a landing between
	# come next door, in R7.
	_rect("r2", 1, 5, 14, 4, VOID_LEVEL)
	_rect("r2", 4, 9, 2, 4, VOID_LEVEL)
	# The Pit Hall: the void chasm round the north ledge; Burr's cell in the west gallery.
	_rect("hub", 4, 3, 25, 7, VOID_LEVEL)
	_rect("hub", 7, 3, 18, 2, 0)
	# Burr's cell: the west gallery's north end (lx 1..2, ly 3..7), its east wall on the chasm's rim,
	# its door at ly 8.
	_wall_cells("hub", [Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7)])
	# R5 Eye Hall: the inner wall (its door at lx 7..8 under the first latch) and the key alcove
	# (lx 1..3, ly 10..12) behind its stone door, the two latches on its east wall.
	var inner: Array = []
	for x in range(1, 15):
		if x != 8:
			inner.append(Vector2i(x, 7))
	_wall_cells("r5", inner)
	_wall_cells("r5", [Vector2i(1, 9), Vector2i(3, 9), Vector2i(4, 9), Vector2i(4, 10), Vector2i(4, 11), Vector2i(4, 12)])
	# R7 Bell Bridge: the spike pit, the entry rim, the key platform, the turning bridge, the bell's
	# rock; the stairs out of the pit at its north-east.
	_rect("r7", 1, 5, 14, 8, PIT_LEVEL)
	_rect("r7", 4, 3, 2, 2, PIT_LEVEL)
	_rect("r7", 1, 3, 3, 10, 0)
	_rect("r7", 1, 9, 3, 4, PIT_LEVEL)
	_rect("r7", 6, 7, 2, 2, 0)
	_rect("r7", 11, 7, 2, 2, 0)
	_wall_cells("r7", [Vector2i(1, 6), Vector2i(3, 6)])
	_stairs("r7", 13, 5, "s")
	_stairs("r7", 14, 5, "s")
	# R10 Dung Roller Run: rock over the lane's north (its face over ly 6..7), the lane (ly 8..9),
	# rock to its south with two niches and the two door corridors.
	_rect("r10", 1, 1, 30, 5, ROCK_LEVEL)
	_rect("r10", 1, 10, 30, 3, ROCK_LEVEL)
	for nx in [11, 17]:
		_rect("r10", nx, 10, 2, 2, 0)
	_rect("r10", 7, 10, 2, 3, 0)
	_rect("r10", 23, 10, 2, 3, 0)
	# R11 Drop-gate Bridge: void; the start strip (the worm lever) south of a low inner wall whose
	# gap holds the gate's oak leaf; the landing behind it; two slabs north, the turn landing, three
	# slabs east; the far platform and its walk round to the hub's ledge.
	_rect("r11", 1, 3, 14, 10, VOID_LEVEL)
	_rect("r11", 1, 10, 5, 3, 0)
	_rect("r11", 1, 7, 5, 3, 0)
	_rect("r11", 2, 3, 2, 2, 0)
	_rect("r11", 6, 3, 9, 4, 0)
	_rect("r11", 13, 7, 2, 4, 0)
	_rect("r11", 7, 11, 8, 2, 0)
	_wall_cells("r11", [Vector2i(1, 10), Vector2i(2, 10), Vector2i(3, 10)])
	# The Old Armoury: two holes in its dark floor; the gate before its chest.
	_rect("arm", 5, 6, 2, 2, VOID_LEVEL)
	_rect("arm", 9, 9, 2, 2, VOID_LEVEL)
	_wall_cells("arm", [Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5), Vector2i(13, 3), Vector2i(13, 4), Vector2i(13, 5),
		Vector2i(10, 5), Vector2i(12, 5)])
	# The Glow-moss Burrow: void, the entry strip, the islet; the hidden ledge between them stays
	# void (the kit's shadow path holds it, seen only in a light).
	_rect("bur", 1, 3, 14, 10, VOID_LEVEL)
	_rect("bur", 6, 11, 4, 2, 0)
	_rect("bur", 11, 5, 3, 3, 0)
	# The map nook and the sally port: small rooms carved in their cells against the band.
	_rect("nook", 9, 4, 6, 6, 0)
	_rect("sally", 9, 3, 6, 6, 0)
	# The bolt-hole: a short tunnel up from the shrine's north door.
	_rect("bolt", 7, 3, 2, 10, 0)


# --- the scene ---------------------------------------------------------------------------------------

func _build_scene() -> void:
	scene_root = Node2D.new()
	scene_root.name = MAP_ID
	scene_root.y_sort_enabled = true
	scene_root.add_child(_ground_layer())
	scene_root.add_child(_elevation_layer())
	scene_root.add_child(_cliff_layer())
	scene_root.add_child(_wall_layer())
	var shade := Node2D.new()
	shade.name = "VoidShade"
	shade.set_script(load(VOID_SHADE))
	scene_root.add_child(shade)
	scene_root.add_child(_definition())
	scene_root.add_child(_marker("player-spawn", _at("r1", 8.0, 9.0)))
	scene_root.add_child(_marker("dungeon-entrance", _at("r1", 8.0, 10.0)))
	scene_root.add_child(_camera_rooms())
	var dungeon := _dungeon_node()
	if dungeon != null:
		scene_root.add_child(dungeon)
	scenery = _holder("Scenery", true)
	enemies = _holder("Enemies", false)
	hazards = _holder("Hazards", false)
	objects = _holder("Objects", true)
	lair = _holder("Lair", true)
	_place_doors_out()
	_place_r1()
	_place_r2()
	_place_hub()
	_place_r4()
	_place_r5()
	_place_r6()
	_place_r7()
	_place_r8()
	_place_r9()
	_place_r10()
	_place_r11()
	_place_r12()
	_place_r13_r14()
	_place_dark_rooms()
	_place_nook_sally()
	_place_kit_doors()
	_place_hazards()
	_fill_void_shade(shade)
	_own(scene_root, scene_root)
	for node in _editable:
		scene_root.set_editable_instance(node, true)


func _holder(holder_name: String, y_sort: bool) -> Node2D:
	var node := Node2D.new()
	node.name = holder_name
	node.y_sort_enabled = y_sort
	scene_root.add_child(node)
	return node


## World units of room `key`'s local cell point (lx, ly), in cells (fractions allowed).
func _at(key: String, lx: float, ly: float) -> Vector2:
	var o := _origin(key)
	return Vector2((o.x + lx) * TILE, (o.y + ly) * TILE)


func _ground_layer() -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "ground"
	layer.z_index = -2
	layer.tile_set = load(TERRAIN_TILESET)
	for y in rows:
		for x in cols:
			layer.set_cell(Vector2i(x, y), ground[_i(x, y)], Vector2i(x % SHEET_TILES, y % SHEET_TILES))
	layer.set_meta(&"columns", cols)
	layer.set_meta(&"rows", rows)
	layer.set_script(load(WORLD_GROUND))
	return layer


func _elevation_layer() -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "elevation"
	layer.z_index = -1
	layer.tile_set = load(ELEVATION_TILESET)
	for y in rows:
		for x in cols:
			var index := _i(x, y)
			if stairs[index] >= 0:
				layer.set_cell(Vector2i(x, y), 0, Vector2i(stairs[index], STAIRS_ROW))
				continue
			var lvl := level[index]
			if lvl != 0:
				layer.set_cell(Vector2i(x, y), 0, Vector2i(lvl + 3 if lvl < 0 else lvl + 2, 0))
	layer.set_script(load(ELEVATION_LAYER))
	return layer


func _cliff_layer() -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "cliffs"
	layer.tile_set = load(CLIFF_TILESET)
	for y in rows:
		for x in cols:
			if level[_i(x, y)] > 0 or level[_i(x, y)] < 0 or (y + 1 < rows and level[_i(x, y + 1)] < 0):
				layer.set_cell(Vector2i(x, y), 0, Vector2i(cliffs[_i(x, y)], 0))
	layer.set_script(load(CLIFF_LAYER))
	return layer


func _wall_layer() -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "walls"
	layer.tile_set = load(WALL_TILESET)
	for y in rows:
		for x in cols:
			if walls[_i(x, y)] == 1:
				layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	layer.set_script(load(WALL_LAYER))
	return layer


## One dark rectangle per run of void cells along a row (not under a slab, a landing or the
## drawbridge: those draw their own floor; the shadow path stays shaded, it is void until lit).
func _fill_void_shade(shade: Node2D) -> void:
	var rects: Array[Rect2] = []
	for y in rows:
		var start := -1
		for x in cols + 1:
			var is_void := x < cols and level[_i(x, y)] == VOID_LEVEL and not deck_cells.has(Vector2i(x, y))
			if is_void and start < 0:
				start = x
			elif not is_void and start >= 0:
				rects.append(Rect2(start * TILE, y * TILE, (x - start) * TILE, TILE))
				start = -1
	shade.set(&"rects", rects)


## Rectangles of the cells at `want` (not stairs): runs along each row, merged down while they line up.
func _cell_rects(want: int) -> Array[Rect2i]:
	var done: Array[Rect2i] = []
	var open: Dictionary = {}
	for y in rows + 1:
		var runs: Array[Vector2i] = []
		if y < rows:
			var start := -1
			for x in cols + 1:
				var hit := x < cols and level[_i(x, y)] == want and stairs[_i(x, y)] < 0
				if hit and start < 0:
					start = x
				elif not hit and start >= 0:
					runs.append(Vector2i(start, x))
					start = -1
		var next: Dictionary = {}
		for run: Vector2i in runs:
			if open.has(run):
				var grown: Rect2i = open[run]
				grown.size.y += 1
				next[run] = grown
			else:
				next[run] = Rect2i(run.x, y, run.y - run.x, 1)
		for run: Vector2i in open:
			if not next.has(run):
				done.append(open[run])
		open = next
	return done


## The room whose cells hold world cell `cell` ("" outside every room).
func _room_of(cell: Vector2i) -> String:
	for key: String in ROOMS:
		var o := _origin(key)
		var size: Vector2i = ROOMS[key]["size"]
		if Rect2i(o, size * Vector2i(ROOM_W, ROOM_H)).has_point(cell):
			return key
	return ""


func _definition() -> Node:
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	definition.set(&"map_id", MAP_ID)
	definition.set(&"tile_size", TILE)
	definition.set(&"columns", cols)
	definition.set(&"rows", rows)
	definition.set(&"camera_mode", "follow")
	var spawn := _at("r1", 8.0, 9.0)
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": roundi(spawn.x), "y": roundi(spawn.y)}, "entries": {}}})
	return definition


func _marker(marker_name: String, position: Vector2) -> Node2D:
	var marker := Node2D.new()
	marker.name = marker_name
	marker.position = position
	return marker


func _camera_rooms() -> Node2D:
	var holder := Node2D.new()
	holder.name = "CameraRooms"
	for key: String in ROOMS:
		var room: Dictionary = ROOMS[key]
		var node := Node2D.new()
		node.name = str(room["name"])
		node.set_script(load(CAMERA_ROOM))
		node.position = Vector2(_origin(key) * TILE)
		node.set(&"size", Vector2(room["size"]) * Vector2(ROOM_W, ROOM_H) * TILE)
		holder.add_child(node)
		if ROOM_ENTRIES.has(key):
			node.add_child(_marker("RoomEntry", Vector2(ROOM_ENTRIES[key]) * TILE))
	return holder


func _dungeon_node() -> Node2D:
	var packed := load(KIT % "dungeon") as PackedScene
	if packed == null:
		push_error("fatty-lair: the kit has no Dungeon node")
		return null
	var node := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	node.name = "Dungeon"
	node.set(&"dungeon_id", MAP_ID)
	node.set(&"display_name", "Fatty's Lair")
	node.set(&"entrance_marker", "dungeon-entrance")
	return node


## An instance of `object.<id>` (or a scene path) under `parent` at `position`, `props` set on its
## root and `child_props` ({child path: {property: value}}) on its children.
func _add(parent: Node, scene: String, node_name: String, position: Vector2, props: Dictionary = {},
		child_props: Dictionary = {}) -> Node:
	var path := scene if scene.begins_with("res://") else OBJ % scene
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("fatty-lair: no scene " + path)
		return null
	var node := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	node.name = node_name
	if node is Node2D:
		(node as Node2D).position = position
	for key: String in props:
		node.set(key, props[key])
	for child_path: String in child_props:
		var child := node.get_node_or_null(child_path)
		if child == null:
			push_error("fatty-lair: %s has no %s" % [node_name, child_path])
			continue
		var values: Dictionary = child_props[child_path]
		for key: String in values:
			child.set(key, values[key])
	parent.add_child(node)
	if not child_props.is_empty():
		_editable.append(node)
	return node


## A dungeon kit piece (`object.<kind>`, docs/godot/DUNGEONS.md) under Objects.
func _kit(kind: String, node_name: String, position: Vector2, props: Dictionary = {}, child_props: Dictionary = {}) -> Node:
	_kit_placed += 1
	return _add(objects, KIT % kind, node_name, position, props, child_props)


## A kit chest with `contents` (its id is its name).
func _chest(kind: String, node_name: String, position: Vector2, contents: Dictionary, hidden: bool = false) -> Node:
	return _kit(kind, node_name, position, {}, {"ChestScript": {"map_id": MAP_ID, "instance_id": node_name,
		"initial_contents": contents, "hidden": hidden}})


## One falling slab over room `key`'s cell (lx, ly).
func _slab(key: String, lx: int, ly: int) -> void:
	_kit("falling-slab", "%s-slab-%d-%d" % [key, lx, ly], _at(key, lx, ly), {"size": Vector2(TILE, TILE)})
	deck_cells[_origin(key) + Vector2i(lx, ly)] = true


## A solid landing (a kit deck) over room `key`'s cells from (lx, ly), `size` cells.
func _landing(key: String, node_name: String, lx: int, ly: int, size: Vector2i) -> void:
	_kit("hazard-deck", node_name, _at(key, lx, ly), {"size": Vector2(size * TILE), "level": 0, "safe": true, "draw_floor": true})
	for y in size.y:
		for x in size.x:
			deck_cells[_origin(key) + Vector2i(lx + x, ly + y)] = true


## The kit's hazards: a void over every rectangle of hole cells, spikes over the pit's (not its
## stairs). A fall goes back to the last safe ground, or to the room's `Return` points.
func _place_hazards() -> void:
	var returns := {"bur": [Vector2(7.5, 11.6)], "arm": [Vector2(14.0, 7.0)]}
	for kind: String in ["void", "spikes"]:
		for r: Rect2i in _cell_rects(VOID_LEVEL if kind == "void" else PIT_LEVEL):
			_kit_placed += 1
			var hazard := _add(hazards, KIT % "hazard", "%s-%d-%d" % [kind, r.position.x, r.position.y], Vector2(r.position * TILE),
				{"kind": kind, "size": Vector2(r.size * TILE), "rim_level": 0, "pit_depth": 1, "draw_look": kind != "void"})
			var room := _room_of(r.position)
			var points: Array = returns.get(room, [])
			for i in points.size():
				var spot: Vector2 = points[i]
				var marker := _marker("Return%d" % i, _at(room, spot.x, spot.y) - Vector2(r.position * TILE))
				hazard.add_child(marker)


func _enemy(enemy_type: String, node_name: String, position: Vector2, wander: float = 140.0, overrides: Dictionary = {}) -> Node:
	return _add(enemies, PLACED_ENEMY, node_name, position, {"enemy_type": enemy_type, "wander_radius": wander, "overrides": overrides})


## A clay pot is the kit's (it hides a refill and grows back); a crate or a sack is a plain liftable.
func _pot(node_name: String, position: Vector2, kind: String = "clay-pot") -> Node:
	if kind == "clay-pot":
		_kit_placed += 1
		return _add(scenery, KIT % "dungeon-pot", node_name, position)
	return _add(scenery, "liftable", node_name, position, {}, {"LiftableScript": {"kind": kind}})


# --- the rooms ---------------------------------------------------------------------------------------

## The way in from Fatty's Hollow and the way out through the bolt-hole.
func _place_doors_out() -> void:
	var entrance := _door("fatty-lair-entrance", "south", "opening", _at("r1", 8.0, 13.7), OUTSIDE_MAP, "fatty-lair-mouth")
	scene_root.add_child(entrance)
	var bolt := _door("fatty-lair-bolt-hole", "north", "opening", _at("bolt", 8.0, 3.4), OUTSIDE_MAP, "fatty-lair-bolt-hole-mouth")
	scene_root.add_child(bolt)
	var glow := Node2D.new()
	glow.name = "daylight"
	glow.set_script(load(SOFT_GLOW))
	glow.position = _at("bolt", 8.0, 3.2)
	glow.set(&"radius", Vector2(120, 70))
	glow.set(&"color", Color(1.0, 0.95, 0.7, 0.55))
	lair.add_child(glow)
	var ladder := Sprite2D.new()
	ladder.name = "bolt-hole-ladder"
	ladder.texture = load("res://asset/MAPS/props/256x256-tile_8x1-gulp-props.webp")
	ladder.hframes = 8
	ladder.frame = 2
	ladder.centered = false
	ladder.offset = Vector2(-128, -256)
	ladder.scale = Vector2(0.7, 0.7)
	ladder.position = _at("bolt", 8.0, 4.2)
	scenery.add_child(ladder)


## An invisible wall over a gap (`size` centred on `centre`).
func _barrier(node_name: String, centre: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = node_name
	body.position = centre
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body


func _door(door_id: String, side: String, kind: String, position: Vector2, target_map: String, target_door: String) -> Node2D:
	var node := Node2D.new()
	node.name = door_id
	node.position = position
	var script := Node.new()
	script.name = "DoorScript"
	script.set_script(load(DOOR))
	script.set(&"map_id", MAP_ID)
	script.set(&"door_id", door_id)
	script.set(&"target_area_id", target_map)
	script.set(&"target_door_id", target_door)
	script.set(&"side", side)
	script.set(&"kind", kind)
	script.set(&"trigger_rect", Rect2(-64, -24, 128, 48))
	node.add_child(script)
	return node


func _place_r1() -> void:
	# The outer gate's inner winch: holds the drop gate in Fatty's Hollow up for good.
	_add(objects, "gate-winch", "r1-gate-winch", _at("r1", 11.0, 12.4), {"gate_id": "fatty-lair-gate", "map_id": OUTSIDE_MAP})
	# The Quartermaster's store: the barricade in the closet's gap, Gorge's pay chest inside.
	_add(objects, "plank-barricade", "r1-store-barricade", _at("r1", 13.0, 6.0), {"flag_id": "fatty-lair.store-smashed"})
	_chest("dungeon-chest", "r1-store-chest", _at("r1", 13.0, 4.2), {"coins": 100})
	for i in 2:
		_add(scenery, "decoration-world-solid--worm-bunk", "r1-bunk-%d" % i, _at("r1", 3.0 + i * 3.4, 4.8))
	_add(scenery, "decoration-world-solid--war-banner", "r1-banner", _at("r1", 9.6, 3.4))
	_pot("r1-pot-a", _at("r1", 2.0, 9.0))
	_pot("r1-pot-b", _at("r1", 2.8, 9.6))
	_pot("r1-pot-c", _at("r1", 13.4, 9.0), "crate")


func _place_r2() -> void:
	# The slabs (the kit's falling slabs over the void), each bridge two lanes wide: two over the
	# west arm (one Roll); over the north arm two, a landing where that Roll ends, and one more.
	for y in [10, 11]:
		for x in [4, 5]:
			_slab("r2", x, y)
	for y in [7, 8]:
		for x in [10, 11]:
			_slab("r2", x, y)
	_landing("r2", "r2-landing", 10, 5, Vector2i(2, 2))


func _place_hub() -> void:
	# Burr in his cell (the kit's two-keyhole door is its south wall, below).
	_add(lair, "res://game/scenes/characters/burr.tscn", "burr", _at("hub", 2.0, 4.4))
	_add(lair, "stair-hatch", "inner-stair", _at("hub", 2.0, 12.9), {"hatch_id": "fatty-lair-inner-stair",
		"open_flag": "fatty-lair.inner-stair-open", "target": NodePath("../../Lair/crypt-stair-arrival"), "arrival_facing": "up"})
	lair.add_child(_marker("hub-stair-arrival", _at("hub", 3.8, 12.2)))
	lair.add_child(_marker("burr-door", _at("hub", 2.0, 9.0)))
	lair.add_child(_marker("burr-exit", _at("hub", 8.0, 12.6)))
	# The north ledge: the calm spot (pots that grow back and the refill are the kit's).
	for i in 3:
		_pot("hub-ledge-pot-%d" % i, _at("hub", 18.0 + i * 0.9, 4.2))
	_kit("energy-flower", "hub-ledge-flower", _at("hub", 21.5, 4.4))
	# The drawbridge: hinged on the ledge's south edge, down across the chasm to the south gallery;
	# its winch beside it on the ledge.
	_kit("drawbridge", "hub-drawbridge", _at("hub", 16.0, 5.0), {"toward": "south", "length": 5, "width": 128.0,
		"bridge_id": "fatty-lair-drawbridge"})
	for y in range(5, 10):
		for x in [15, 16]:
			deck_cells[_origin("hub") + Vector2i(x, y)] = true
	var targets: Array[NodePath] = [NodePath("../hub-drawbridge")]
	_kit("winch", "hub-drawbridge-winch", _at("hub", 13.0, 4.7), {"winch_id": "fatty-lair-drawbridge-winch", "targets": targets,
		"done_text": "The bridge is down for good."})
	for i in 2:
		_add(scenery, "decoration-world-solid--war-banner", "hub-banner-%d" % i, _at("hub", 10.0 + i * 12.0, 12.4))
	_pot("hub-pot-a", _at("hub", 29.4, 12.2))


func _place_r4() -> void:
	_enemy("squint", "r4-squint-a", _at("r4", 5.0, 6.5), 150.0)
	_enemy("squint", "r4-squint-b", _at("r4", 10.5, 10.5), 150.0)
	_add(scenery, "decoration-world-solid--worm-bunk", "r4-bunk", _at("r4", 12.0, 4.4))
	_add(scenery, "decoration-world-solid--war-banner", "r4-banner", _at("r4", 3.0, 3.5))
	_pot("r4-pot", _at("r4", 13.5, 11.8))


func _place_r5() -> void:
	# The first latch: over the inner wall's door, for good.
	_add(objects, "latch-door", "r5-inner-door", _at("r5", 8.5, 8.0), {"scale": LATCH_DOOR_SCALE}, {"GateScript": {"gate_id": "fatty-lair-r5-inner", "map_id": MAP_ID}})
	_add(objects, "eye-latch", "r5-latch-inner", _at("r5", 10.5, 6.9), {"latch_id": "fatty-lair.r5-inner", "gate_id": "fatty-lair-r5-inner"},
		{"Visual": {"position": Vector2(0, -34)}})
	# The alcove: its stone door in its north side, two timed latches on its east wall, the second
	# screened by a pillar so only a diagonal thrust reaches it.
	_add(objects, "latch-door", "r5-alcove-door", _at("r5", 2.5, 10.0), {"scale": LATCH_DOOR_SCALE}, {"GateScript": {"gate_id": "fatty-lair-r5-alcove", "map_id": MAP_ID}})
	_add(objects, "eye-latch", "r5-latch-a", _at("r5", 5.4, 12.0), {"latch_id": "fatty-lair.r5-a", "gate_id": "fatty-lair-r5-alcove",
		"group_id": "fatty-lair.r5-alcove", "open_ms": 3000.0}, {"Visual": {"position": Vector2(0, -34)}})
	_add(objects, "eye-latch", "r5-latch-b", _at("r5", 5.4, 10.4), {"latch_id": "fatty-lair.r5-b", "gate_id": "fatty-lair-r5-alcove",
		"group_id": "fatty-lair.r5-alcove", "open_ms": 3000.0}, {"Visual": {"position": Vector2(0, -34)}})
	_add(scenery, "rock-world-wall-solid--field-05", "r5-screen-pillar", _at("r5", 6.6, 10.6))
	_kit("dungeon-key", "r5-small-key-1", _at("r5", 2.0, 11.6), {"item": "small-key", "pickup_id": "fatty-lair-key-1"})


func _place_r6() -> void:
	_enemy("pipe-worm", "r6-pipe-worm-a", _at("r6", 14.7, 10.6), 40.0, {"aim_direction": Vector2.LEFT})
	_enemy("pipe-worm", "r6-pipe-worm-b", _at("r6", 11.5, 3.2), 40.0, {"aim_direction": Vector2.DOWN})
	_add(scenery, "decoration-world-solid--worm-bunk", "r6-bunk", _at("r6", 3.0, 4.6))
	_pot("r6-pot", _at("r6", 2.0, 11.8))
	for i in 3:
		_add(scenery, "res://game/scenes/objects/interiors/mushroom-floor/interior-mushroom-floor-mushrooms-glow.tscn",
			"r6-burrow-moss-%d" % i, _at("r6", 6.8 + i * 1.2, 3.3))


func _place_r7() -> void:
	# The bell on its rock; it opens the platform's stone door for good.
	_add(objects, "lash-bell-post", "r7-bell", _at("r7", 12.0, 8.6), {}, {"LashBellScript": {"bell_id": "fatty-lair-r7-bell", "gate_id": "fatty-lair-r7-gate"}})
	_add(objects, "latch-door", "r7-gate", _at("r7", 2.5, 7.0), {"scale": LATCH_DOOR_SCALE}, {"GateScript": {"gate_id": "fatty-lair-r7-gate", "map_id": MAP_ID}})
	_kit("dungeon-key", "r7-small-key-2", _at("r7", 2.0, 4.6), {"item": "small-key", "pickup_id": "fatty-lair-key-2"})
	for i in 3:
		_pot("r7-pot-%d" % i, _at("r7", 9.0 + i * 1.3, 4.2))
	# The turning bridge over the spikes: two slabs south from the rim, the landing (a rock in the
	# pit), two slabs west to the platform.
	for y in [5, 6]:
		for x in [6, 7]:
			_slab("r7", x, y)
	for y in [7, 8]:
		for x in [4, 5]:
			_slab("r7", x, y)


func _place_r8() -> void:
	_add(scenery, "rock-world-wall-solid--large-02", "r8-bier-north", _at("r8", 8.0, 8.6))
	_add(scenery, "rock-world-wall-solid--large-02", "r8-bier-south", _at("r8", 8.0, 19.6))
	_enemy("bone-marcher", "r8-marcher-a", _at("r8", 5.0, 6.0), 60.0,
		{"route": PackedVector2Array([Vector2(0, 0), Vector2(384, 0), Vector2(384, 256), Vector2(0, 256)]), "route_loop": true})
	_enemy("bone-marcher", "r8-marcher-b", _at("r8", 11.0, 23.0), 60.0,
		{"route": PackedVector2Array([Vector2(0, 0), Vector2(-448, 0), Vector2(-448, -320), Vector2(0, -320)]), "route_loop": true})
	# The Inner Stair comes down here (its ladder back up).
	_add(lair, "stair-ladder", "crypt-stair", _at("r8", 2.5, 26.0), {"hatch_id": "fatty-lair-crypt-stair",
		"target": NodePath("../../Lair/hub-stair-arrival"), "arrival_facing": "down"})
	lair.add_child(_marker("crypt-stair-arrival", _at("r8", 4.0, 24.6)))
	# The Old Armoury's doorway: two cold sconces.
	for i in 2:
		_add(scenery, SCONCE_UNLIT, "r8-armoury-sconce-%d" % i, _at("r8", 1.4, 19.6 + i * 2.6))
	# The Thorn Guard's crypt: armour statues of the old garrison down the walls, candles at the
	# biers, urns in the corners, lit sconces on the north wall.
	for y: float in [10.5, 13.5, 16.5]:
		_add(scenery, "decoration-world-solid--armor-statue", "r8-guard-west-%d" % int(y), _at("r8", 1.7, y))
	for y: float in [6.5, 10.5, 14.5, 18.5, 22.0]:
		_add(scenery, "decoration-world-solid--armor-statue", "r8-guard-east-%d" % int(y), _at("r8", 14.3, y))
	var candles := "res://game/scenes/objects/interiors/decor/interior-decor-candles-triple-lit.tscn"
	for p: Vector2 in [Vector2(6.0, 8.8), Vector2(10.0, 8.8), Vector2(6.0, 19.8), Vector2(10.0, 19.8)]:
		_add(scenery, candles, "r8-candles-%d-%d" % [p.x, p.y], _at("r8", p.x, p.y))
	var urn := "res://game/scenes/objects/interiors/decor/interior-decor-urn-tall.tscn"
	for p: Vector2 in [Vector2(2.2, 3.7), Vector2(13.8, 3.7), Vector2(13.8, 27.0)]:
		_add(scenery, urn, "r8-urn-%d-%d" % [p.x, p.y], _at("r8", p.x, p.y))
	var sconce := "res://game/scenes/objects/interiors/decor/interior-decor-sconce-lit.tscn"
	for x: float in [4.0, 12.0]:
		_add(scenery, sconce, "r8-sconce-%d" % int(x), _at("r8", x, 3.1))


func _place_r9() -> void:
	for p: Vector2 in [Vector2(4, 6), Vector2(4, 10.5), Vector2(11, 6), Vector2(11, 10.5)]:
		_add(objects, "heavy-statue", "r9-statue-%d-%d" % [p.x, p.y], _at("r9", p.x + 0.5, p.y))
	_enemy("watcher-eye", "r9-watcher-eye", _at("r9", 8.0, 8.5), 120.0)
	_add(objects, "latch-door", "r9-north-door", _at("r9", 8.0, 3.0), {"scale": Vector2(0.75, 0.75)}, {"GateScript": {"gate_id": "fatty-lair-r9-north", "map_id": MAP_ID}})
	_add(objects, "eye-latch", "r9-latch", _at("r9", 11.0, 3.2), {"latch_id": "fatty-lair.r9-north", "gate_id": "fatty-lair-r9-north"})


func _place_r10() -> void:
	_enemy("dung-roller", "r10-dung-roller", _at("r10", 6.0, 9.0), 60.0,
		{"track": PackedVector2Array([Vector2(-224, 0), Vector2(1216, 0)])})
	_enemy("squint", "r10-squint", _at("r10", 27.0, 9.0), 110.0)
	_chest("dungeon-chest", "r10-chest-key-3", _at("r10", 29.6, 8.6), {"dungeon-small-key": 1})


func _place_r11() -> void:
	# The inner gate: the same old oak leaf as outside, in the gap of the low wall (no rock mound
	# here, so nothing hides the landing behind it); its worm lever at the strip's east end, a cell
	# and a half below the gap: pulled, the gate stays up too briefly to walk under, a Roll north
	# makes it.
	_add(objects, "drop-gate", "r11-drop-gate", _at("r11", 5.0, 11.0), {"gate_id": "fatty-lair-inner-gate", "open_ms": 500.0},
		{"Frame": {"visible": false}, "Mound/LeftRock": {"disabled": true}, "Mound/RightRock": {"disabled": true},
		"Lever": {"position": Vector2(38, 96)}})
	# Two slabs north from the landing to the turn, two east to the far platform.
	for y in [5, 6]:
		for x in [2, 3]:
			_slab("r11", x, y)
	for y in [3, 4]:
		for x in [4, 5]:
			_slab("r11", x, y)
	_enemy("pipe-worm", "r11-pipe-worm", _at("r11", 14.7, 3.6), 40.0, {"aim_direction": Vector2.LEFT})


func _place_r12() -> void:
	_enemy("big-squint", "r12-big-squint", _at("r12", 8.0, 7.0), 220.0)
	# The Lair's one ambush: the shutter shuts behind the slime, the Big Squint's fall opens it and
	# raises the big chest.
	_chest("dungeon-big-chest", "r12-big-chest", _at("r12", 8.0, 4.4), {"dungeon-big-key": 1}, true)
	_kit("room-fight", "r12-fight", _at("r12", 0.0, 0.0), {"fight_id": "fatty-lair-larder", "once": true,
		"size": Vector2(ROOM_W, ROOM_H) * TILE, "reward": NodePath("../r12-big-chest")})
	_kit("shutter", "r12-shutter-south", _at("r12", 12.0, 13.0), {"wall": "south", "fight_id": "fatty-lair-larder",
		"shutter_id": "fatty-lair-larder-south"})
	for i in 4:
		_add(scenery, "decoration-world-solid--hay-bale", "r12-hoard-%d" % i, _at("r12", 2.0 + i * 0.9, 11.8 - (i % 2) * 0.6))
	_add(scenery, "decoration-world-solid--cooking-cauldron", "r12-cauldron", _at("r12", 13.0, 11.6))


func _place_r13_r14() -> void:
	var camp := _add(lair, "res://game/scenes/encounters/fatty-lair-boss.tscn", "fatty-camp", _at("r13", 8.0, 8.0))
	var spots := Node2D.new()
	spots.name = "clod-spots"
	lair.add_child(spots)
	for p: Vector2 in [Vector2(3.5, 5.5), Vector2(12.5, 5.5), Vector2(3.5, 10.5), Vector2(12.5, 10.5), Vector2(8.0, 4.8), Vector2(8.0, 11.4)]:
		spots.add_child(_marker("clod-%d-%d" % [p.x, p.y], _at("r13", p.x, p.y)))
	for i in 6:
		_add(scenery, "res://game/scenes/objects/interiors/mushroom-floor/interior-mushroom-floor-root-%d.tscn" % (2 + i % 4),
			"r13-roots-%d" % i, _at("r13", 2.0 + i * 2.4, 3.4))
	_kit("shutter", "r13-shutter-south", _at("r13", 8.0, 13.0), {"wall": "south", "fight_id": "fatty-lair-boss",
		"shutter_id": "fatty-lair-arena-south"})
	_kit("shutter", "r13-shutter-north", _at("r13", 8.0, 3.0), {"wall": "north", "fight_id": "fatty-lair-boss",
		"shutter_id": "fatty-lair-arena-north"})
	var heart := _add(lair, "goo-heart", "fatty-boss-heart", _at("r13", 8.0, 8.4), {}, {"GooHeartScript": {"heart_id": "fatty-lair-boss-heart", "hearts": 2}})
	# The shrine: the altar, the Pearl over it, the green-key chest, the plank barricade over the
	# bolt-hole (the Heavy skin's first lock).
	_add(scenery, "decoration-world-solid--pearl-altar", "r14-altar", _at("r14", 8.0, 7.2))
	# Taken from any side of the altar (its base is solid): a wide reach.
	var pearl := _add(lair, "pearl", "pearl-1", _at("r14", 8.0, 5.9), {"take_radius": 90.0})
	_add(objects, "chest-wooden", "r14-green-key-chest", _at("r14", 11.6, 8.0), {}, {"ChestScript": {"map_id": MAP_ID,
		"instance_id": "fatty-lair-green-key-chest", "initial_contents": {"green-key": 1}}})
	_add(objects, "plank-barricade", "r14-barricade", _at("r14", 8.0, 3.2), {"flag_id": "fatty-lair.bolt-hole-smashed"})
	var director := Node2D.new()
	director.name = "LairDirector"
	director.set_script(load(DIRECTOR))
	# It stands in the arena: the compass's boss mark until Fatty is beaten.
	director.position = _at("r13", 8.0, 8.0)
	lair.add_child(director)
	director.set(&"burr", NodePath("../burr"))
	director.set(&"burr_door", NodePath("../burr-door"))
	director.set(&"burr_exit", NodePath("../burr-exit"))
	director.set(&"cell_door", NodePath("../../Objects/hub-burr-cell-door"))
	director.set(&"hatch", NodePath("../inner-stair"))
	director.set(&"call_rect", Rect2(_at("hub", 1.0, 3.0), Vector2(30, 10) * TILE))
	director.set(&"camp", NodePath("../fatty-camp/BossCampScript"))
	director.set(&"clod_spots", NodePath("../clod-spots"))
	director.set(&"heart", NodePath("../fatty-boss-heart"))
	director.set(&"pearl", NodePath("../pearl-1"))
	director.set(&"phase_two", {})
	# Typed (an untyped Array does not set an Array[NodePath] export).
	var gaps: Array[NodePath] = [NodePath("../../Objects/nook-blocked")]
	director.set(&"blocked_gaps", gaps)
	director.set(&"boss_shutter_fight", "fatty-lair-boss")
	if camp == null or heart == null or pearl == null:
		push_error("fatty-lair: the boss room is missing a piece")


func _place_dark_rooms() -> void:
	# The Old Armoury: dark until its four sconces burn (lit for good), which opens the stone door
	# before its chest.
	var dark := Node2D.new()
	dark.name = "armoury-dark"
	dark.set_script(load(DARK_ROOM))
	dark.position = _at("arm", 1.0, 1.0)
	dark.set(&"size", Vector2(14, 12) * TILE)
	dark.set(&"lit_for_good_when_all_lit", true)
	dark.set(&"lit_flag", "fatty-lair.armoury-lit")
	lair.add_child(dark)
	var candle_paths: Array[NodePath] = []
	for p: Vector2 in [Vector2(2.0, 3.4), Vector2(13.0, 3.4), Vector2(2.0, 12.4), Vector2(13.0, 12.4)]:
		var candle := Node2D.new()
		candle.name = "armoury-sconce-%d-%d" % [p.x, p.y]
		candle.set_script(load(CANDLE))
		candle.position = _at("arm", p.x, p.y)
		candle.set(&"unlit_scene", load(SCONCE_UNLIT))
		candle.set(&"lit_scene", load(SCONCE_LIT))
		candle.set(&"burn_ms", 0.0)
		candle.set(&"group", "fatty-lair-armoury")
		candle.set(&"gate_id", "fatty-lair-armoury-gate")
		lair.add_child(candle)
		candle_paths.append(NodePath("../" + candle.name))
	dark.set(&"candles", candle_paths)
	_add(objects, "latch-door", "armoury-door", _at("arm", 11.5, 6.0), {"scale": LATCH_DOOR_SCALE}, {"GateScript": {"gate_id": "fatty-lair-armoury-gate", "map_id": MAP_ID}})
	# The design's prize, a war journal page, is not an item yet: coins hold its place.
	_chest("dungeon-chest", "armoury-chest", _at("arm", 11.5, 4.4), {"coins": 40})
	# The Glow-moss Burrow: dark; the shadow path (the kit's glow-moss, seen only in a light) over
	# the hidden ledge; the heart on the islet, its glint drawn over the dark.
	var burrow := Node2D.new()
	burrow.name = "burrow-dark"
	burrow.set_script(load(DARK_ROOM))
	burrow.position = _at("bur", 1.0, 1.0)
	burrow.set(&"size", Vector2(14, 12) * TILE)
	lair.add_child(burrow)
	var ledge: Array[Vector2i] = [Vector2i(7, 10), Vector2i(7, 9), Vector2i(6, 8), Vector2i(5, 7), Vector2i(5, 6),
		Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 6), Vector2i(10, 6)]
	_kit("shadow-path", "burrow-shadow-path", _at("bur", 0.0, 0.0), {"cells": ledge})
	_add(lair, "goo-heart", "burrow-heart", _at("bur", 12.5, 6.6), {}, {"GooHeartScript": {"heart_id": "fatty-lair-burrow-quarter"}})
	_kit("prize-glint", "burrow-glint", _at("bur", 12.5, 5.8), {"only_in_dark": true})
	_kit("prize-glint", "armoury-glint", _at("arm", 11.5, 3.6), {"only_in_dark": true, "phase": 0.4})


func _place_nook_sally() -> void:
	# The map nook: crates jammed in its gap (light things, the Gulp) behind a barrier that goes when
	# they are all taken (the director's `blocked_gaps`), the map's chest inside.
	var blocked := Node2D.new()
	blocked.name = "nook-blocked"
	blocked.y_sort_enabled = true
	objects.add_child(blocked)
	for i in 3:
		_pot("nook-crate-%d" % i, _at("r4", 0.4 - i * 0.6, 6.5 + (i % 2) * 0.9), "crate").reparent(blocked)
	_pot("nook-sack", _at("r4", -0.2, 7.7), "flour-sack").reparent(blocked)
	blocked.add_child(_barrier("Barrier", _at("r4", 0.0, 7.0), Vector2(120, 132)))
	_chest("dungeon-chest", "nook-map-chest", _at("nook", 12.0, 6.0), {"dungeon-map": 1})
	# The sally port: a crack in R5's west wall (the Goo Bomb, Chapter 2): blown, the band opens a
	# passage into the little room (cracked_wall.gd `passage`).
	_add(objects, "cracked-wall", "r5-sally-crack", _at("r5", 1.0, 6.0), {"flag_id": "fatty-lair.sally-port-open",
		"passage": Rect2(-128, -128, 128, 128), "passage_level": 0})
	_chest("dungeon-chest", "sally-chest", _at("sally", 12.0, 5.0), {"hp-potion": 2})


## The kit's doors: Burr's cell (two keyholes), door 3, the boss door, the bolted ways back.
func _place_kit_doors() -> void:
	_kit("key-door", "hub-burr-cell-door", _at("hub", 2.0, 8.0), {"wall": "north", "keyholes": 2, "door_id": "fatty-lair-burr-cell"})
	_kit("key-door", "r8-door-3", _at("r8", 15.0, 26.0), {"wall": "east", "keyholes": 1, "door_id": "fatty-lair-door-3"})
	_kit("boss-door", "hub-boss-door", _at("hub", 24.0, 3.0), {"wall": "north", "lock": "big", "door_id": "fatty-lair-boss-door"})
	_kit("bolted-door", "hub-r1-shortcut", _at("hub", 8.0, 13.0), {"wall": "south", "door_id": "fatty-lair-r1-shortcut"})
	_kit("bolted-door", "r5-way-back", _at("r5", 15.0, 11.0), {"wall": "east", "door_id": "fatty-lair-r5-way-back"})
	_kit("bolted-door", "r7-way-back", _at("r7", 1.0, 4.0), {"wall": "west", "door_id": "fatty-lair-r7-way-back"})
	_kit("bolted-door", "r10-way-back", _at("r10", 24.0, 13.0), {"wall": "south", "door_id": "fatty-lair-r10-way-back"})
	_kit("bolted-door", "r11-way-back", _at("r11", 8.0, 13.0), {"wall": "south", "door_id": "fatty-lair-r11-way-back"})


func _save() -> Error:
	var packed := PackedScene.new()
	var err := packed.pack(scene_root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	scene_root.free()
	return err


## Gives every node under `node` without an owner the owner `owner_root` (the insides of instanced
## scenes keep theirs; nodes added under an instance, as a hazard's return points, are ours).
static func _own(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = owner_root
		_own(child, owner_root)
