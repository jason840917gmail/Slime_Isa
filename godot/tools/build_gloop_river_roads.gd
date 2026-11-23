extends SceneTree
## Lays Gloop Forest's redesign, "River Roads" (the owner's pick of 2026-11-21: sketch A, developed as
## A2; the sketches and notes: output/gloop-sketches/, the plan: docs/design/2026-11-21-gloop-river-roads.md)
## into ONE chunk world a run:
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_gloop_river_roads.gd -- --chunk=e4 [--dry] [--force]
## A chunk whose scene changed since this tool last wrote it (the owner's hand edits: F4 since
## 2026-11-21) is refused without `--force` (tools/gloop_river_roads_written.json holds the hashes).
## --chunk=e3|f3|e4|f4|e5|f5 (E3 and F3 are made from F5's scene the first time), or --chunk=wilds,
## which closes the North Wilds' D3 and G3 against them. Then bake the chunk and its neighbours:
## res://tools/bake_elevation.gd -- --world=gloop-forest-e3,...
##
## The Gloop runs down the E|F line from the Mere (E3/F3), a creek along E3|E4 and one along F4|F5;
## every other chunk line is a canopy wall. Two chunks meet at one crossing: a footbridge over the
## Gloop, a ford, or a trail gap between lantern posts (rule 11). Each chunk holds four or five
## clearings joined by narrow roads. On the way to the Pearl the webs only slow (floor webs); web
## walls (the Silk skin's) close side ways and shortcuts only (owner, 2026-11-21).
##
## The layout is held once for the whole region (64 x 96 cells, E3 at the north-west) and each run
## writes one chunk's part of it: its ground, its `forest` layer (canopy walls, palette tile 18), its
## `elevation` (Tom's ledge, the knoll), `webs` and `vines` layers, and its nodes under `RiverRoads`,
## replaced on every run. The story places that stay in their chunk are moved once (the camp, the
## iron hollow, the Gloop Cavern's cracked ground; root meta `river_roads_moved`); Tom moves to E3,
## the silk nook to F4. The old props, wander areas, placed enemies, the web lane and the old webs are
## taken out. After the run the chunk scene is the one to edit by hand.
##
## Paths under the canopy (ForestLayer's canopy-path tile) carry the Firefly Tangle, X6 and the secret
## ways to the fairy ring, the glow grove and the Oak's glade; fireflies hover over the Tangle's turns.
## Also: north-south footbridges (X1, X5), the raft at the camp's jetty (Tom's crack is a door ride to
## it), the hollow log, the beaver dam, tripwires, the fairy ring, the dim glow grove, the lily pads
## to the Mere's islet, five critters in silk (and their homes in the camp), the Bow's ravine east of
## the beach, the lookout tree (F5), the bell on the Mere's islet (E3). F4 is the owner's
## hand-edited chunk since 2026-11-21 (the Watch Oak placed by hand), so the tool no longer touches
## the Oak. `--chunk=ascii` prints the
## layout as text.

const SceneSave := preload("res://tools/lib/scene_save.gd")

const CHUNKS := "res://game/scenes/worlds/chunks/gloop-forest-%s.tscn"
const TEMPLATE := "res://game/scenes/worlds/chunks/gloop-forest-f5.tscn"
const ORIGINS := {"e3": Vector2i(0, 0), "f3": Vector2i(32, 0), "e4": Vector2i(0, 32), "f4": Vector2i(32, 32),
		"e5": Vector2i(0, 64), "f5": Vector2i(32, 64)}
const NX := 64
const NY := 96
const SIDE := 32
const CELL := 64
const SHEET := 19
const HOLDER := "RiverRoads"
## {chunk: hash of the scene as this tool last wrote it}: a chunk changed since (hand edits) is not laid
## again without `--force`.
const WRITTEN := "res://tools/gloop_river_roads_written.json"
const MOVED_META := &"river_roads_moved"

## terrain_tileset.tres sources.
const FOREST_FLOOR := 4
const MOSS := 5
const SAND := 10
const DEEP := 3
const SHALLOW := 11
## forest_tileset.tres: the canopy forest wall (palette column 18).
const CANOPY_SOURCE := 0
const CANOPY_TILE := Vector2i(18, 0)
const FOREST_MIX := Vector2i(0, 0)
## forest_tileset.tres: a path under the forest canopy (palette row 1, under the canopy wall).
const CANOPY_PATH_TILE := Vector2i(18, 1)
const SOFT_GLOW := "res://game/prologue/soft_glow.gd"
const DARK_ROOM := "res://game/world/darkness/dark_room.gd"
const GLOW_MOSS := "res://game/world/darkness/glow_moss.gd"
## The glow grove is dim, not black (a DarkRoom's `darkness_override`).
const GROVE_DARKNESS := 0.72
const FAIRY_RING := "res://game/world/fairy_ring.gd"
const FAIRY_DECOR := "res://game/scenes/objects/interiors/mushroom-decor/interior-mushroom-decor-fairy-ring-glow.tscn"
## The fairy ring's picture, scaled up for an outdoor glade; its middle lies this far (cells) above
## the picture's foot.
const FAIRY_SCALE := 1.7
const FAIRY_LIFT := 2.0
const TRIPWIRE := "res://game/world/webs/tripwire.gd"
const GLOOP_OBJECTS := "res://game/scenes/objects/gloop/"
const SILK_CRITTER := "res://game/world/webs/silk_critter.gd"
const FREED_CRITTER := "res://game/world/webs/freed_critter.gd"
const ANIMALS := "res://game/scenes/objects/animals/"
const WOODEN_CHEST_ART := "res://asset/MAPS/objects/chest-wooden-2x1.webp"
## Where the freed critters run: Mossy's camp, by Sunny (region cells).
const CAMP_HOME := Vector2(15.5, 42.0)

const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const WEB_TILESET := "res://game/world/webs/web_tileset.tres"
const WEB_LAYER := "res://game/world/webs/web_layer.gd"
const VINE_LAYER := "res://game/world/vines/vine_layer.gd"
const VINE_TILESET := "res://game/world/vines/vine_tileset.tres"
const CLEAR_LAYERS: PackedStringArray = ["old-props", "cell-props", "details"]

const OBJECTS := "res://game/scenes/objects/"
const DUNGEON := "res://game/scenes/objects/dungeon/"
const PLACED_ENEMY := "res://game/scenes/encounters/placed-enemy.tscn"
const WORLD_EXIT := "res://game/scripts/world_exit.gd"
const DOOR := "res://game/scripts/door.gd"
const FOOTBRIDGE := "res://game/scenes/objects/decoration-world-floor--wooden-footbridge.tscn"
const POST := "res://game/scenes/objects/decoration-world-solid--lantern-post.tscn"
## A footbridge's deck centre lies this far above its root (bridge_deck.gd's default deck).
const BRIDGE_DECK_Y := 77.0

enum Kind { CANOPY, FLOOR, ROAD, DEEP_WATER, SHALLOW_WATER, KNOLL, LEDGE, CANOPY_PATH, RAVINE }

var _dry := false
var _force := false
var _chunk := ""
var _origin := Vector2i.ZERO
var _root: Node2D
var _holder: Node2D
var _kind := PackedInt32Array()
var _web := PackedByteArray()


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--dry":
			_dry = true
		elif arg == "--force":
			_force = true
		elif arg.begins_with("--chunk="):
			_chunk = arg.trim_prefix("--chunk=")
	if _chunk == "wilds":
		quit(0 if _close_wilds() == OK else 1)
		return
	if _chunk == "ascii":
		_layout()
		_print_ascii()
		quit(0)
		return
	if not ORIGINS.has(_chunk):
		push_error("build_gloop_river_roads: give one chunk, --chunk=e3|f3|e4|f4|e5|f5|wilds")
		quit(1)
		return
	_origin = ORIGINS[_chunk]
	_layout()
	if _chunk == "e4":
		_report_lines()
	quit(0 if _build() == OK else 1)


# --- the layout (region cells, E3's corner at 0,0) ------------------------------------------------

func _layout() -> void:
	_kind.resize(NX * NY)
	_web.resize(NX * NY)
	for i in NX * NY:
		_kind[i] = Kind.CANOPY
		_web[i] = 0
	# E4: the gate glade, Mossy's walled camp and its yard on the Gloop, the bridge-head, the fairy ring.
	_fill(2, 35, 7, 45, Kind.FLOOR)
	_fill(10, 35, 29, 46, Kind.FLOOR)
	_fill(22, 48, 29, 56, Kind.FLOOR)
	_fill(3, 50, 10, 57, Kind.FLOOR)
	_road([Vector2i(0, 40), Vector2i(2, 40)])
	_road([Vector2i(8, 40), Vector2i(10, 40)])
	_road([Vector2i(24, 31), Vector2i(24, 35)])            # north to X1 (the ford)
	_road([Vector2i(24, 46), Vector2i(24, 48)])            # down to the bridge-head
	_road([Vector2i(14, 54), Vector2i(22, 54)])            # west, then south through X7
	_road([Vector2i(14, 54), Vector2i(14, 67)])
	_path([Vector2i(4, 46), Vector2i(4, 48)])              # the fairy ring's way, under the canopy (secret)
	# E3: the landing glade, the Web Glade, the Firefly Tangle, the spider's column, the weavers'
	# road, Tom's hollow under its ledge.
	_fill(18, 24, 27, 29, Kind.FLOOR)
	_fill(3, 13, 11, 20, Kind.FLOOR)
	_fill(3, 3, 11, 8, Kind.FLOOR)
	_fill(9, 3, 11, 4, Kind.LEDGE)
	_road([Vector2i(4, 26), Vector2i(18, 26)])
	_road([Vector2i(4, 20), Vector2i(4, 26)])
	for seg: Array in [[Vector2i(11, 16), Vector2i(14, 16)], [Vector2i(14, 13), Vector2i(14, 16)],
			[Vector2i(14, 13), Vector2i(19, 13)], [Vector2i(19, 13), Vector2i(19, 20)],
			[Vector2i(19, 20), Vector2i(24, 20)],
			[Vector2i(14, 16), Vector2i(14, 22)], [Vector2i(10, 22), Vector2i(14, 22)],
			[Vector2i(10, 21), Vector2i(10, 22)], [Vector2i(19, 17), Vector2i(23, 17)]]:
		_path(seg)                                          # the Firefly Tangle, under the canopy
	_road([Vector2i(26, 10), Vector2i(26, 22)])            # the spider's column
	_fill(26, 23, 27, 23, Kind.ROAD)                       # its Silk shortcut down to the landing
	_road([Vector2i(8, 10), Vector2i(27, 10)])             # the weavers' road
	_road([Vector2i(8, 9), Vector2i(8, 10)])               # up past the fallen tree to Tom
	_road([Vector2i(28, 18), Vector2i(29, 18)])            # to X2
	_fill(22, 5, 23, 6, Kind.FLOOR)                        # the Mere's bell islet (in the water below)
	# F3: the east bank, the Clod Stompers' clearing, the beach, the lily-pad islet, the stump glade.
	_fill(34, 15, 41, 22, Kind.FLOOR)
	_fill(46, 15, 55, 24, Kind.FLOOR)
	_fill(44, 2, 51, 8, Kind.FLOOR)
	_fill(38, 25, 46, 29, Kind.FLOOR)
	_road([Vector2i(41, 18), Vector2i(46, 18)])
	_road([Vector2i(48, 9), Vector2i(48, 15)])
	_road([Vector2i(37, 22), Vector2i(37, 25)])
	_path([Vector2i(38, 30), Vector2i(38, 45)])            # X6 down to the Oak road, under the canopy
	# (west of the Oak's glade, a canopy column between: its fading treetops never show the Oak's trunk)
	# The ravine east of the beach (the Bow's secret): its glade beyond, its south bank off the beach.
	_fill(53, 2, 59, 4, Kind.FLOOR)
	_fill(52, 7, 59, 9, Kind.FLOOR)
	_fill(53, 5, 59, 6, Kind.RAVINE)
	# F4: the bridge-head, the Oak's glade and its S1 nook, the silk nook, the web-wall maze.
	_fill(34, 49, 40, 56, Kind.FLOOR)
	_fill(41, 37, 52, 48, Kind.FLOOR)                     # (row 49 would touch the bridge-head)
	_fill(53, 37, 54, 43, Kind.FLOOR)
	_fill(53, 44, 55, 46, Kind.FLOOR)
	_fill(56, 34, 61, 43, Kind.FLOOR)
	_road([Vector2i(37, 46), Vector2i(37, 49)])
	_road([Vector2i(37, 46), Vector2i(41, 46)])
	_road([Vector2i(37, 56), Vector2i(37, 62)])            # south to X5
	_road([Vector2i(53, 40), Vector2i(55, 40)])            # the silk nook's mouth
	_path([Vector2i(41, 52), Vector2i(42, 52)], 1)         # the bridge-head's hidden way to the Oak's glade
	_path([Vector2i(42, 49), Vector2i(42, 52)], 1)
	_road([Vector2i(50, 49), Vector2i(50, 53)])            # the web-wall maze
	_road([Vector2i(43, 53), Vector2i(60, 53)])
	_road([Vector2i(43, 53), Vector2i(43, 58)])
	_road([Vector2i(43, 58), Vector2i(63, 58)])
	# E5: the crossroads, the sinkhole, the glow grove, the beaver pond, the knoll and its glade.
	_fill(10, 67, 19, 75, Kind.FLOOR)
	_fill(2, 78, 11, 86, Kind.FLOOR)
	_fill(3, 89, 12, 92, Kind.FLOOR)
	_fill(21, 74, 28, 88, Kind.FLOOR)                     # (row 74: the pond's south bank, by the dam)
	_fill(22, 79, 27, 84, Kind.KNOLL)
	_road([Vector2i(6, 72), Vector2i(10, 72)])
	_road([Vector2i(6, 72), Vector2i(6, 78)])
	_path([Vector2i(6, 87), Vector2i(6, 87)])              # to the glow grove, under the canopy (deadthorn)
	_road([Vector2i(17, 75), Vector2i(17, 77)])
	_road([Vector2i(17, 77), Vector2i(21, 77)])
	_road([Vector2i(14, 75), Vector2i(14, 89)])            # the Thornball run
	_road([Vector2i(14, 89), Vector2i(29, 89)])
	_road([Vector2i(24, 88), Vector2i(24, 89)])
	# F5: the lookout glade, the iron hollow and its yard, the east shore, the secret glade.
	_fill(34, 70, 41, 88, Kind.FLOOR)
	_fill(47, 67, 55, 74, Kind.FLOOR)
	_fill(47, 75, 58, 79, Kind.FLOOR)
	_fill(57, 79, 61, 89, Kind.FLOOR)
	_fill(52, 91, 61, 93, Kind.FLOOR)
	_road([Vector2i(37, 66), Vector2i(37, 70)])
	_road([Vector2i(34, 89), Vector2i(41, 89)])
	_road([Vector2i(41, 76), Vector2i(47, 76)])
	_road([Vector2i(58, 89), Vector2i(58, 91)])
	# Water.
	_fill(20, 3, 43, 9, Kind.DEEP_WATER)                   # the Mere
	_fill(22, 5, 23, 6, Kind.FLOOR)                        # its bell islet
	_fill(22, 9, 25, 9, Kind.FLOOR)                        # a notch of shore off the weavers' road, below it
	_fill(34, 4, 36, 6, Kind.FLOOR)                        # its lily-pad islet
	_river([Vector2i(30, 9), Vector2i(30, NY - 1)], 4)     # the Gloop
	_river([Vector2i(2, 31), Vector2i(29, 31)], 3)         # north creek
	_river([Vector2i(34, 63), Vector2i(61, 63)], 3)        # south creek
	_fill(21, 67, 28, 73, Kind.DEEP_WATER)                 # the beaver pond
	_fill(42, 81, 56, 89, Kind.DEEP_WATER)                 # the pool under the long bridge
	_fill(48, 87, 50, 88, Kind.FLOOR)                      # its lens islet
	# X1 and X5 cross the creeks on north-south footbridges (their decks open the water).
	_fill(30, 89, 33, 90, Kind.SHALLOW_WATER)              # X4
	# The border: canopy two cells deep, open at the way in and the way out.
	for y in NY:
		for x in NX:
			if x < 2 or x > NX - 3 or y < 2 or y > NY - 3:
				var i := y * NX + x
				if _kind[i] != Kind.DEEP_WATER:
					_kind[i] = Kind.CANOPY
	_fill(0, 39, 1, 41, Kind.ROAD)                           # the way in: D4's gate road is 3 rows wide
	_fill(62, 58, 63, 59, Kind.ROAD)
	# Floor webs (they slow; on the main way only these).
	for r: Rect2i in [Rect2i(20, 25, 5, 3), Rect2i(4, 15, 7, 5), Rect2i(26, 13, 2, 8), Rect2i(16, 10, 8, 2),
			Rect2i(47, 19, 6, 5), Rect2i(37, 46, 5, 2), Rect2i(42, 44, 10, 5), Rect2i(35, 73, 6, 6),
			Rect2i(42, 84, 15, 2)]:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				_web[y * NX + x] = 1


func _fill(x0: int, y0: int, x1: int, y1: int, kind: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			if x >= 0 and y >= 0 and x < NX and y < NY:
				_kind[y * NX + x] = kind


## An axis-aligned road `w` cells wide; each point is the band's top-left cell.
func _road(points: Array, w: int = 2, kind: int = Kind.ROAD) -> void:
	for i in range(points.size() - 1):
		var a: Vector2i = points[i]
		var b: Vector2i = points[i + 1]
		_fill(mini(a.x, b.x), mini(a.y, b.y), maxi(a.x, b.x) + w - 1, maxi(a.y, b.y) + w - 1, kind)


## A path under the canopy (no collision, the crowns over it; ForestLayer fades them over the slime).
func _path(points: Array, w: int = 2) -> void:
	_road(points, w, Kind.CANOPY_PATH)


func _river(points: Array, w: int) -> void:
	_road(points, w, Kind.DEEP_WATER)


func _kind_at(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= NX or c.y >= NY:
		return Kind.CANOPY
	return _kind[c.y * NX + c.x]


static func _walkable(kind: int) -> bool:
	return kind == Kind.FLOOR or kind == Kind.ROAD or kind == Kind.SHALLOW_WATER or kind == Kind.CANOPY_PATH


## Prints each chunk line's open stretches (a check of rule 11; the bridges over the Gloop are not
## in the paint and are listed apart).
func _report_lines() -> void:
	var lines := [["E3|F3", true, 32, 0], ["E4|F4", true, 32, 32], ["E5|F5", true, 32, 64],
			["E3/E4", false, 32, 0], ["F3/F4", false, 32, 32], ["E4/E5", false, 64, 0], ["F4/F5", false, 64, 32]]
	for line: Array in lines:
		var vertical: bool = line[1]
		var at: int = line[2]
		var start: int = line[3]
		var open: Array[String] = []
		var run_start := -1
		for k in range(start, start + SIDE + 1):
			var ok := false
			if k < start + SIDE:
				var a := Vector2i(at - 1, k) if vertical else Vector2i(k, at - 1)
				var b := Vector2i(at, k) if vertical else Vector2i(k, at)
				ok = _walkable(_kind_at(a)) and _walkable(_kind_at(b))
			if ok and run_start < 0:
				run_start = k
			elif not ok and run_start >= 0:
				open.append("%d-%d" % [run_start - start, k - 1 - start])
				run_start = -1
		print("chunk line %s: open at %s" % [line[0], ", ".join(open) if not open.is_empty() else "none"])
	print("bridges over the Gloop: E3|F3 rows 18-19, E4|F4 rows 20-21 (region 52-53)")


## The hash of each chunk scene as this tool last wrote it (WRITTEN), {chunk: hash}.
func _written() -> Dictionary:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(WRITTEN))
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else {}
	return parsed if parsed is Dictionary else {}


func _record_written(text: String) -> void:
	var written := _written()
	written[_chunk] = str(text.hash())
	var file := FileAccess.open(ProjectSettings.globalize_path(WRITTEN), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(written, "\t", true) + "\n")


## `--chunk=ascii`: the layout as text, a character a cell (T canopy, . floor, = road, ~ deep water,
## - shallow, K knoll, L ledge, p path under the canopy, v ravine, w floor web), to plan by.
func _print_ascii() -> void:
	var chars := "T.=~-KLpv"
	var head := "    "
	for x in NX:
		head += str(x % 10)
	print(head)
	for y in NY:
		var line := "%3d " % y
		for x in NX:
			var i := y * NX + x
			line += "w" if _web[i] == 1 and _kind[i] != Kind.CANOPY else chars[_kind[i]]
		print(line)


# --- one chunk ------------------------------------------------------------------------------------

func _build() -> Error:
	var path := CHUNKS % _chunk
	var fresh := not ResourceLoader.exists(path)
	var before := "" if fresh else FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))
	# The owner's hand edits survive: a chunk whose scene changed since this tool last wrote it (saved
	# from the editor) is not laid again without `--force` (the owner, 2026-11-21: "make sure you
	# dont delete my changes").
	if not fresh and not _dry and not _force and str(before.hash()) != str(_written().get(_chunk, "")):
		push_error(("build_gloop_river_roads: %s changed since this tool wrote it (hand edits in the editor);"
				+ " not laid again. Edit it by hand, or add -- --force to lay it afresh and lose those edits.") % path)
		return ERR_ALREADY_EXISTS
	if fresh:
		_root = _new_chunk()
	else:
		_root = (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	var old := _root.get_node_or_null(HOLDER)
	if old != null:
		_root.remove_child(old)
		old.free()
	_strip()
	_holder = Node2D.new()
	_holder.name = HOLDER
	_holder.y_sort_enabled = true
	_own(_holder, _root)
	_move_story_places()
	_paint()
	_place()
	_edges()
	if _dry:
		print("gloop river roads: %s (dry)" % _chunk)
		_root.free()
		return OK
	var err := SceneSave.save(_root, path, before)
	print("gloop river roads: ", path, " ", error_string(err))
	if err == OK:
		_record_written(FileAccess.get_file_as_string(ProjectSettings.globalize_path(path)))
	_root.free()
	return err


## E3 and F3, the first time: F5's scene emptied (its layers, music, definition kept) and renamed.
func _new_chunk() -> Node2D:
	var root := (load(TEMPLATE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	root.scene_file_path = ""
	var world_id := "gloop-forest-" + _chunk
	root.name = world_id
	root.set_meta(&"world_map_chunk", _chunk.to_upper())
	root.set_meta(&"world_map_chunk_of", "gloop-forest")
	root.set_meta(&"world_map_region", "b")
	if root.has_meta(&"world_map_region_spawn"):
		root.remove_meta(&"world_map_region_spawn")
	if root.has_meta(MOVED_META):
		root.remove_meta(MOVED_META)
	for child: Node in root.get_children():
		if child is TileMapLayer:
			(child as TileMapLayer).clear()
			continue
		var n := String(child.name)
		if n in ["world-definition", "MusicPlayer", "Ambience", "player-spawn", "Enemies", "props"]:
			continue
		root.remove_child(child)
		child.free()
	for holder_name: String in ["Enemies", "props"]:
		var holder := root.get_node_or_null(holder_name)
		if holder != null:
			for c: Node in holder.get_children():
				holder.remove_child(c)
				c.free()
	var definition := root.get_node("world-definition")
	definition.set(&"map_id", world_id)
	return root


## What the old layout had that the new one replaces.
func _strip() -> void:
	for layer_name: String in CLEAR_LAYERS:
		var layer := _root.get_node_or_null(layer_name) as TileMapLayer
		if layer != null:
			layer.clear()
	var gone: Array[String] = ["Webs", "web-lane", "silk-nook", "Border", "enemy-safe-2", "tom-web", "tom-crack"]
	for child: Node in _root.get_children():
		var n := String(child.name)
		var wander := child is Area2D and (n.begins_with("gloop-") or n.begins_with("area-gloop-"))
		if n in gone or wander:
			_root.remove_child(child)
			child.free()
	for holder_name: String in ["Enemies", "props"]:
		var holder := _root.get_node_or_null(holder_name)
		if holder != null:
			for c: Node in holder.get_children():
				holder.remove_child(c)
				c.free()
	if _chunk == "f4":
		var walls := _root.get_node_or_null("walls") as TileMapLayer
		if walls != null:
			walls.clear()                                  # the old web lane's walls
	if _chunk == "e4":
		var shifted := _root.get_node_or_null("walls-shifted-32-0") as TileMapLayer
		if shifted != null:
			shifted.clear()                                # the old silk nook's pen
	if _chunk == "e5":
		_free_path("cracked-clearing/clearing-stone-gulp-spot")
	if _chunk == "f5":
		for n: String in ["iron-1", "iron-2", "iron-3", "hollow-stone-gulp-spot", "hollow-ore-pile-1", "hollow-ore-pile-2"]:
			_free_path("iron-hollow/" + n)


func _free_path(node_path: String) -> void:
	var node := _root.get_node_or_null(node_path)
	if node != null:
		node.get_parent().remove_child(node)
		node.free()


## The places that stay in their chunk, moved to the new layout once.
func _move_story_places() -> void:
	var moved := bool(_root.get_meta(MOVED_META, false))
	match _chunk:
		"e4":
			# Mossy's walled camp: from E4's south-east to its west middle (cells -11, -20).
			_set_pos("camp", Vector2(-704, -1280))
			_set_pos("hut-door", Vector2(1154, 604))
			_set_pos("enemy-safe-1", Vector2(1024, 512))
			if not moved:
				for layer_name: String in ["walls", "large-props"]:
					_shift_cells(layer_name, Vector2i(-11, -20))
		"f5":
			# The iron hollow: its pen up into the new layout's north-east (cells +7, -1).
			_set_pos("iron-hollow", Vector2(-1600, -2112))
			if not moved:
				_shift_cells("walls-shifted-32-0", Vector2i(7, -1))
			var chest := _root.get_node_or_null("iron-hollow/hollow-chest")
			if chest != null and chest.has_node("ChestScript"):
				_root.set_editable_instance(chest, true)
				chest.get_node("ChestScript").set(&"goo_heart_id", "gloop-iron-hollow")
		"e5":
			# The Gloop Cavern's cracked ground: into the sinkhole glade (the group sits at 0, -2048).
			_set_pos("cracked-clearing/cracked-ground", Vector2(416, 1184 + 2048))
	if _chunk in ["e4", "f5", "e5"]:
		_root.set_meta(MOVED_META, true)


func _set_pos(node_path: String, at: Vector2) -> void:
	var node := _root.get_node_or_null(node_path) as Node2D
	if node != null:
		node.position = at


func _shift_cells(layer_name: String, by: Vector2i) -> void:
	var layer := _root.get_node_or_null(layer_name) as TileMapLayer
	if layer == null:
		return
	var cells := []
	for c: Vector2i in layer.get_used_cells():
		cells.append([c, layer.get_cell_source_id(c), layer.get_cell_atlas_coords(c), layer.get_cell_alternative_tile(c)])
	layer.clear()
	for entry: Array in cells:
		layer.set_cell(entry[0] + by, entry[1], entry[2], entry[3])


func _paint() -> void:
	var ground := _root.get_node("ground") as TileMapLayer
	ground.clear()
	var forest := _root.get_node("forest") as TileMapLayer
	forest.clear()
	var elevation := _layer("elevation", ELEVATION_TILESET, ELEVATION_LAYER, "ground")
	elevation.clear()
	var webs := _layer("webs", WEB_TILESET, WEB_LAYER, "elevation")
	webs.clear()
	var vines := _layer("vines", VINE_TILESET, VINE_LAYER, "elevation")
	vines.clear()
	for y in SIDE:
		for x in SIDE:
			var local := Vector2i(x, y)
			var c := _origin + local
			var i := c.y * NX + c.x
			var kind := _kind[i]
			var source := FOREST_FLOOR
			match kind:
				Kind.FLOOR, Kind.KNOLL, Kind.LEDGE:
					source = MOSS
				Kind.ROAD:
					source = SAND
				Kind.DEEP_WATER:
					source = DEEP
				Kind.SHALLOW_WATER:
					source = SHALLOW
			ground.set_cell(local, source, Vector2i(x % SHEET, y % SHEET))
			if kind == Kind.CANOPY:
				forest.set_cell(local, CANOPY_SOURCE, CANOPY_TILE)
			elif kind == Kind.CANOPY_PATH:
				forest.set_cell(local, CANOPY_SOURCE, CANOPY_PATH_TILE)
			elif kind == Kind.KNOLL:
				elevation.set_cell(local, 0, Vector2i(4, 0))     # level 2
			elif kind == Kind.LEDGE:
				elevation.set_cell(local, 0, Vector2i(3, 0))     # level 1
			elif kind == Kind.RAVINE:
				elevation.set_cell(local, 0, Vector2i(1, 0))     # level -2
			if _web[i] == 1:
				webs.set_cell(local, 0, Vector2i(0, 0))
	# The knoll's south face (level 2: two rows below its top): living roots for the Feral skin.
	for c: Vector2i in [Vector2i(24, 85), Vector2i(25, 85), Vector2i(24, 86), Vector2i(25, 86)]:
		if _mine(Vector2(c)):
			vines.set_cell(c - _origin, 0, Vector2i(0, 0))


func _layer(layer_name: String, tileset: String, script: String, after: String) -> TileMapLayer:
	var layer := _root.get_node_or_null(layer_name) as TileMapLayer
	if layer == null:
		layer = TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = load(tileset)
		layer.set_script(load(script))
		if layer_name == "elevation":
			layer.z_index = -1
		_root.add_child(layer)
		var anchor := _root.get_node_or_null(after)
		if anchor != null:
			_root.move_child(layer, anchor.get_index() + 1)
		layer.owner = _root
	if layer.tile_set == null:
		layer.tile_set = load(tileset)
	return layer


# --- what stands in the chunk (region cells; only what falls inside this chunk is placed) --------

func _place() -> void:
	# The crossings: footbridges over the Gloop (one deck a chunk, at the same place), lantern posts.
	_bridge(Vector2(32, 19))                       # X2 (E3|F3)
	_bridge(Vector2(32, 53))                       # X3 (E4|F4)
	_bridge_ns(Vector2(25.0, 32.5))                # X1 (E3/E4), over the north creek
	_bridge_ns(Vector2(38.0, 64.5))                # X5 (F4/F5), over the south creek
	# The raft, moored at the camp's jetty (it came down the Gloop from Tom's old landing).
	if _mine(Vector2(31.0, 43.6)):
		_scene(GLOOP_OBJECTS + "raft.tscn", "raft", Vector2(31.0, 43.6))
	# The hollow log lying along F5's north road: the slime walks through it.
	if _mine(Vector2(38.0, 70.4)):
		_scene(GLOOP_OBJECTS + "hollow-log.tscn", "hollow-log", Vector2(38.0, 70.4))
	# The beaver dam holding E5's pond: a Goo Bomb blows it and the pond drains to a sunk chest.
	if _mine(Vector2(24.9, 74.3)):
		var dam := _scene(GLOOP_OBJECTS + "beaver-dam.tscn", "beaver-dam", Vector2(24.9, 74.3))
		dam.set(&"pond", Rect2i(Vector2i(21, 67) - _origin, Vector2i(8, 7)))
		_chest("sunk-chest", Vector2(24.6, 69.6), {"coins": 30, "energy-potion": 1}, "")
		var chest := _holder.get_node("sunk-chest")
		chest.reparent(dam)
		chest.owner = _root
		dam.set(&"sunk", chest)
	for at: Vector2 in [Vector2(43.25, 85), Vector2(47.75, 85), Vector2(52.25, 85), Vector2(56.75, 85)]:
		_bridge(at)                                # the long bridge (F5)
	for at: Vector2 in [Vector2(1.6, 38.5), Vector2(1.6, 42.9),                        # the way in
			Vector2(23.3, 30.4), Vector2(26.7, 30.4), Vector2(23.3, 35.0), Vector2(26.7, 35.0),   # X1
			Vector2(29.5, 17.3), Vector2(29.5, 20.9), Vector2(34.5, 17.3), Vector2(34.5, 20.9),   # X2
			Vector2(29.5, 51.3), Vector2(29.5, 54.9), Vector2(34.5, 51.3), Vector2(34.5, 54.9),   # X3
			Vector2(29.3, 88.3), Vector2(29.3, 91.9), Vector2(34.7, 88.3), Vector2(34.7, 91.9),   # X4
			Vector2(36.3, 62.4), Vector2(39.7, 62.4), Vector2(36.3, 66.6), Vector2(39.7, 66.6),   # X5
			Vector2(37.4, 29.6), Vector2(40.6, 29.6), Vector2(37.4, 45.6), Vector2(40.6, 45.6),   # X6
			Vector2(13.3, 62.4), Vector2(16.7, 62.4), Vector2(13.3, 65.6), Vector2(16.7, 65.6),   # X7
			Vector2(61.5, 57.3), Vector2(61.5, 60.9)]:                                       # the way out
		_post(at)
	# E3: Tom's thicket.
	if _mine(Vector2(6.5, 6)):
		_scene(OBJECTS + "tom-web.tscn", "tom-web", Vector2(6.5, 6.2))
		var crack := _scene(OBJECTS + "cracked-wall.tscn", "tom-crack", Vector2(10.5, 6.0))
		crack.set(&"flag_id", "gloop-forest.tom-crack")
		crack.set(&"refusal_text", "Too deep for a hammer. It needs a blast.")
		crack.set(&"crack_size", Vector2(56, 60))
		crack.set(&"crack_offset", Vector2(0, -34))
		crack.set(&"hole_size", Vector2(64, 76))
		crack.set(&"hole_offset", Vector2(0, -38))
		# Once blown, the hole is the old raft landing: the raft rides the Gloop down to the camp's
		# jetty (phase 2 shows the ride; here a door's fade), the way back to the start.
		crack.set(&"door_id", "tom-raft-landing")
		crack.set(&"target_area_id", "gloop-forest-e4")
		crack.set(&"target_door_id", "raft-jetty")
		crack.set(&"door_side", "north")
		_fallen_tree("tom-rubble", Vector2(9.0, 9.7), "gloop-forest.tom-rubble")
		_move_spawn(Vector2(22.5, 28.0))
	_web_wall("tangle-shortcut", Vector2(27.0, 24.0), "across", 128.0, "gloop-forest.tangle-shortcut", false)
	_critter("web-glade-critter", Vector2(4.6, 13.9), "squirrel")
	_mere_bell()
	_chest("tangle-chest", Vector2(23.6, 17.8), {"coins": 10}, "")
	# Fireflies over the Firefly Tangle's right turns (the wrong turns lead back to the Web Glade).
	for at: Vector2 in [Vector2(15.0, 17.0), Vector2(15.0, 14.0), Vector2(20.0, 14.0), Vector2(20.0, 21.0),
			Vector2(11.6, 17.0)]:
		_firefly(at)
	# The Tangle is the main way: lantern posts mark its mouth on the Web Glade's east side.
	for at: Vector2 in [Vector2(10.6, 15.6), Vector2(10.6, 18.5)]:
		_post(at)
	# The secret ways under the canopy: one firefly at the mouth is their only tell.
	for at: Vector2 in [Vector2(5.0, 45.4), Vector2(7.0, 86.4), Vector2(40.6, 52.9)]:
		_firefly(at)
	_enemy("orb-weaver-glade-1", "orb-weaver", Vector2(6.5, 15.5), 120.0)
	_enemy("orb-weaver-glade-2", "orb-weaver", Vector2(9.5, 18.5), 120.0)
	_enemy("silk-lurker-tangle", "silk-lurker", Vector2(17.5, 13.8), 0.0)
	_enemy("slime-spider-column", "slime-spider", Vector2(26.9, 10.9), 0.0)
	# A tripwire at the column's foot, a Silk Lurker over the webbed column above it.
	_enemy("silk-lurker-column", "silk-lurker", Vector2(26.9, 17.6), 0.0)
	_tripwire("column-tripwire", Vector2(27.0, 21.6), 0.0)
	_enemy("orb-weaver-road", "orb-weaver", Vector2(21.5, 10.9), 90.0)
	for at: Vector2 in [Vector2(3.3, 13.3), Vector2(11.4, 20.3), Vector2(18.5, 24.3), Vector2(27.6, 12.5)]:
		_decor("decoration-world-ambient--web-tree-0%d.tscn" % (1 + int(at.x) % 2), "web-tree", at)
	# F3: the Mere's shore.
	if _mine(Vector2(37.5, 19)):
		_move_spawn(Vector2(37.5, 19.0))
	_chest("mere-islet-chest", Vector2(35.0, 5.4), {}, "gloop-mere-islet")
	_lily_pads()
	_ravine()
	_critter("clod-critter", Vector2(54.4, 23.6), "hedgehog")
	_enemy("orb-weaver-bank", "orb-weaver", Vector2(36.5, 17.5), 100.0)
	_enemy("clod-stomper-1", "clod-stomper", Vector2(48.5, 21.5), 120.0)
	_enemy("clod-stomper-2", "clod-stomper", Vector2(52.5, 20.5), 120.0)
	_enemy("silk-lurker-stumps", "silk-lurker", Vector2(40.5, 27.6), 0.0)
	for at: Vector2 in [Vector2(46.4, 15.3), Vector2(55.6, 24.4), Vector2(38.4, 25.3)]:
		_decor("decoration-world-ambient--web-cocoon-hanging-0%d.tscn" % (1 + int(at.x) % 3), "cocoon", at)
	# E4: the freed critters' homes round Sunny in the camp's walled yard (each shows once its silk
	# is torn).
	for home: Array in [["squirrel", Vector2(13.4, 42.0)], ["hedgehog", Vector2(14.6, 42.3)],
			["snail", Vector2(16.5, 42.4)], ["robin", Vector2(13.0, 40.8)], ["bluebird", Vector2(14.9, 40.4)]]:
		_critter_home(home[0], home[1])
	# E4: the camp's jetty (where the raft from Tom's landing comes in).
	_arrival("raft-jetty", Vector2(27.6, 42.2))
	# The fairy ring in the secret glade: stand in it to heal.
	if _mine(Vector2(6.9, 53.8)):
		var decor := _scene(FAIRY_DECOR, "fairy-ring-glow", Vector2(6.9, 53.8 + FAIRY_LIFT))
		decor.scale = Vector2.ONE * FAIRY_SCALE
		var ring := Node2D.new()
		ring.name = "fairy-ring"
		ring.set_script(load(FAIRY_RING))
		ring.position = _units(Vector2(6.9, 53.8))
		_own(ring, _holder)
	_enemy("silk-lurker-bridgehead", "silk-lurker", Vector2(24.5, 50.6), 0.0)
	# F4: the Oak's glade (the forecourt stays where it was), the silk nook, the maze.
	if _mine(Vector2(36.5, 53)):
		_move_spawn(Vector2(36.5, 53.0))
	_web_wall("silk-nook-web", Vector2(55.0, 41.0), "side", 128.0, "gloop-forest.silk-nook", true)
	if _mine(Vector2(59, 37.5)):
		var heart := _scene(OBJECTS + "goo-heart.tscn", "silk-nook-heart", Vector2(59.0, 37.5))
		var heart_script := heart.get_node_or_null("GooHeartScript")
		if heart_script != null:
			_root.set_editable_instance(heart, true)
			heart_script.set(&"heart_id", "gloop-silk-nook")
		elif "heart_id" in heart:
			heart.set(&"heart_id", "gloop-silk-nook")
	_web_wall("maze-1", Vector2(51.0, 51.0), "across", 128.0, "gloop-forest.maze-1", false)
	_web_wall("maze-2", Vector2(44.0, 56.0), "across", 128.0, "gloop-forest.maze-2", false)
	_web_wall("maze-3", Vector2(49.0, 59.0), "side", 128.0, "gloop-forest.maze-3", false)
	_web_wall("maze-4", Vector2(56.0, 59.0), "side", 128.0, "gloop-forest.maze-4", false)
	_web_wall("maze-dead-end", Vector2(58.0, 54.0), "side", 128.0, "gloop-forest.maze-dead-end", true)
	_critter("maze-critter", Vector2(60.4, 54.2), "snail")
	_enemy("orb-weaver-oak-road", "orb-weaver", Vector2(39.5, 46.9), 80.0)
	_enemy("orb-weaver-oak-1", "orb-weaver", Vector2(44.5, 46.5), 120.0)
	_enemy("slime-spider-oak", "slime-spider", Vector2(51.5, 45.5), 0.0)
	_enemy("silk-lurker-bridgehead-f4", "silk-lurker", Vector2(38.5, 51.6), 0.0)
	# A tripwire on the road up to the Oak, Silk Lurkers over the road on both sides of it.
	_enemy("silk-lurker-oak-road", "silk-lurker", Vector2(40.4, 46.6), 0.0)
	_tripwire("oak-road-tripwire", Vector2(38.0, 48.6), 0.0)
	for at: Vector2 in [Vector2(41.4, 37.4), Vector2(52.4, 49.4), Vector2(34.4, 49.4)]:
		_decor("decoration-world-ambient--web-tree-0%d.tscn" % (1 + int(at.x) % 2), "web-tree", at)
	# E5: the sinkhole (the Gloop Cavern), the glow grove, the knoll, the Thornball run.
	if _mine(Vector2(14.5, 70.5)):
		_move_spawn(Vector2(14.5, 70.5))
	# The glow grove: deadthorn shuts its way under the canopy (the Lantern); inside it is dim, and
	# glow-moss shows the way to its chest.
	if _mine(Vector2(7.0, 88.6)):
		_scene(OBJECTS + "deadthorn-hedge.tscn", "glow-grove-deadthorn", Vector2(7.0, 88.6))
		var dark := Node2D.new()
		dark.name = "glow-grove-dark"
		dark.set_script(load(DARK_ROOM))
		dark.position = _units(Vector2(2.6, 88.6))
		dark.set(&"size", Vector2(10.8 * CELL, 4.6 * CELL))
		dark.set(&"darkness_override", GROVE_DARKNESS)
		_own(dark, _holder)
		for at: Vector2 in [Vector2(6.5, 89.6), Vector2(4.4, 90.8), Vector2(7.6, 91.6), Vector2(9.6, 90.2),
				Vector2(11.4, 91.6)]:
			var moss := Node2D.new()
			moss.name = _unique("glow-moss")
			moss.set_script(load(GLOW_MOSS))
			moss.position = _units(at)
			_own(moss, _holder)
	_chest("glow-grove-chest", Vector2(10.6, 90.8), {"coins": 30}, "")
	_chest("knoll-chest", Vector2(24.6, 80.8), {"coins": 25}, "")      # the Feral skin's climb
	_critter("knoll-critter", Vector2(26.6, 76.4), "robin")
	_enemy("orb-weaver-sinkhole", "orb-weaver", Vector2(8.5, 80.5), 120.0)
	_enemy("thornball-run-1", "thornball", Vector2(20.5, 89.9), 0.0)
	_enemy("thornball-run-2", "thornball", Vector2(26.5, 89.9), 0.0)
	_enemy("thornball-crossroads", "thornball", Vector2(12.5, 70.5), 0.0)
	# F5: the lookout glade, the long bridge, the iron hollow (moved), the secret glade.
	if _mine(Vector2(40.5, 71.5)):
		_move_spawn(Vector2(40.5, 71.5))
	# The lookout tree in the lookout glade's south-west: its stairs wind up to a deck over F5.
	if _mine(Vector2(36.9, 87.0)):
		_scene(GLOOP_OBJECTS + "lookout-tree.tscn", "lookout-tree", Vector2(36.9, 87.0))
	_fallen_tree("secret-glade-log", Vector2(59.0, 90.3), "gloop-forest.secret-glade-log")
	_chest("secret-glade-chest", Vector2(55.6, 92.2), {"coins": 40, "energy-potion": 1}, "")
	_critter("secret-glade-critter", Vector2(53.4, 92.3), "bluebird")
	_enemy("orb-weaver-lookout", "orb-weaver", Vector2(38.5, 75.5), 120.0)
	_enemy("orb-weaver-yard", "orb-weaver", Vector2(44.5, 76.9), 80.0)
	_enemy("slime-spider-bridge", "slime-spider", Vector2(57.6, 84.9), 0.0)
	_enemy("clod-stomper-yard", "clod-stomper", Vector2(55.5, 77.5), 120.0)


## A tripwire across a road (its thread along x, turned by `angle`): touched, it drops the Silk
## Lurkers near it.
func _tripwire(node_name: String, at: Vector2, angle: float) -> void:
	if not _mine(at):
		return
	var wire := Node2D.new()
	wire.name = _unique(node_name)
	wire.set_script(load(TRIPWIRE))
	wire.position = _units(at)
	wire.rotation = angle
	wire.set(&"length", 132.0)
	_own(wire, _holder)


## A north-south footbridge over a creek on a chunk line, `at` its middle: one deck per chunk at the
## same place (its deck, 192 units long, opens the three creek rows under it).
func _bridge_ns(at: Vector2) -> void:
	var local := at - Vector2(_origin)
	if local.x < 0.0 or local.x > SIDE or local.y < -1.5 or local.y > SIDE + 1.5:
		return
	var bridge := (load(GLOOP_OBJECTS + "footbridge-north-south.tscn") as PackedScene).instantiate(
			PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	bridge.name = _unique("footbridge-ns")
	bridge.position = local * CELL
	_own(bridge, _holder)


## A firefly: a small glow that pulses and drifts, drawn over the treetops.
func _firefly(at: Vector2) -> void:
	if not _mine(at):
		return
	var glow := Node2D.new()
	glow.name = _unique("firefly")
	glow.set_script(load(SOFT_GLOW))
	glow.position = _units(at)
	glow.set(&"radius", Vector2(22, 22))
	glow.set(&"color", Color(1.0, 0.93, 0.45, 1.0))
	glow.set(&"additive", true)
	glow.set(&"pulse", 0.6)
	glow.set(&"period_s", 1.7)
	glow.set(&"drift", Vector2(14, 9))
	glow.set(&"drift_period_s", 4.5)
	glow.set(&"phase", fposmod(at.x * 0.37 + at.y * 0.11, 1.0))
	glow.z_index = 3
	_own(glow, _holder)


func _bridge(at: Vector2) -> void:
	# A deck on the E|F line shows in both chunks (scenery across the border).
	var local_x := at.x - _origin.x
	var local_y := at.y - _origin.y
	if local_x < 0.0 or local_x > SIDE or local_y < 0.0 or local_y >= SIDE:
		return
	var bridge := (load(FOOTBRIDGE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	bridge.name = _unique("footbridge")
	bridge.position = Vector2(local_x * CELL, local_y * CELL + BRIDGE_DECK_Y)
	_own(bridge, _holder)


func _post(at: Vector2) -> void:
	if _mine(at):
		_scene(POST, "lantern-post", at)


func _decor(file: String, node_name: String, at: Vector2) -> void:
	if _mine(at) and ResourceLoader.exists(OBJECTS + file):
		_scene(OBJECTS + file, node_name, at)


func _fallen_tree(node_name: String, at: Vector2, flag: String) -> void:
	if not _mine(at):
		return
	var tree := _scene(OBJECTS + "fallen-tree.tscn", node_name, at)
	if "flag_id" in tree:
		tree.set(&"flag_id", flag)


func _web_wall(node_name: String, at: Vector2, orientation: String, span: float, flag: String, secret: bool) -> void:
	if not _mine(at - Vector2(0.01, 0.01)) and not _mine(at):
		return
	var wall := _scene(OBJECTS + "web-wall.tscn", node_name, at)
	wall.set(&"orientation", orientation)
	wall.set(&"span", span)
	wall.set(&"flag_id", flag)
	wall.set(&"hides_secret", secret)


## A forest critter wrapped in silk (silk_critter.gd): the Silk skin's Spear hit frees it, it runs
## home toward the camp, and its FreedCritter there shows it (`_critter_home`). Flag
## `gloop-forest.critter-<animal>`.
func _critter(node_name: String, at: Vector2, animal: String) -> void:
	if not _mine(at):
		return
	var parcel := _scene(OBJECTS + "silk-parcel.tscn", node_name, at)
	parcel.set_script(load(SILK_CRITTER))
	parcel.set(&"coins", 10)
	parcel.set(&"flag_id", "gloop-forest.critter-" + animal)
	parcel.set(&"critter", load(ANIMALS + animal + ".tscn"))
	parcel.set(&"run_toward", (CAMP_HOME - at).normalized())
	parcel.set(&"refusal_text", "Something wriggles inside the silk. You need something to free it.")


## The bell on the Mere's islet (as level-1 C5's lookout bell): a thrown pot (two lie in the shore's
## notch by the weavers' road) or an arrow rings it (lash_bell.gd), and a hidden chest rises in the
## notch (dungeon_chest.gd `trigger`, its record keeps it). The bell's and the chest's settings are
## on nodes inside their scenes, so the instances are editable (the editor keeps the overrides).
func _mere_bell() -> void:
	if not _mine(Vector2(23.0, 6.9)):
		return
	var bell := _scene(OBJECTS + "lash-bell-post.tscn", "mere-bell", Vector2(23.0, 6.9))
	_root.set_editable_instance(bell, true)
	var ring := bell.get_node("LashBellScript")
	ring.set(&"bell_id", "gloop-mere-bell")
	for at: Vector2 in [Vector2(22.6, 9.6), Vector2(23.7, 9.7)]:
		var pot := _scene(OBJECTS + "liftable.tscn", "mere-pot", at)
		pot.set(&"weight", "light")
		_root.set_editable_instance(pot, true)
		var lift := pot.get_node("LiftableScript")
		lift.set(&"kind", "clay-pot")
		lift.set(&"weight_class", "light")
	var chest := _scene(DUNGEON + "dungeon-chest.tscn", "mere-bell-chest", Vector2(24.9, 9.6))
	_root.set_editable_instance(chest, true)
	(chest.get_node("Visual") as Sprite2D).texture = load(WOODEN_CHEST_ART)
	var script_node := chest.get_node("ChestScript")
	script_node.set(&"hidden", true)
	script_node.set(&"map_id", "gloop-forest-" + _chunk)
	script_node.set(&"instance_id", "gloop-forest-%s-mere-bell-chest" % _chunk)
	script_node.set(&"initial_contents", {"coins": 40, "hp-potion": 1})
	ring.connect(&"rung", Callable(script_node, &"trigger"), CONNECT_PERSIST)


## Where a freed critter lives in the camp (freed_critter.gd).
func _critter_home(animal: String, at: Vector2) -> void:
	if not _mine(at):
		return
	var home := Node2D.new()
	home.name = _unique("home-" + animal)
	home.set_script(load(FREED_CRITTER))
	home.position = _units(at)
	home.set(&"flag_id", "gloop-forest.critter-" + animal)
	home.set(&"critter", load(ANIMALS + animal + ".tscn"))
	_own(home, _holder)


## The lily pads across the Mere's east bay, from the beach (col 44) west to the islet (col 36) on row
## 5: sinking pads (falling planks with a lily look) two at a time, a flowered landing between, so a
## quick Roll crosses two pads to a landing; a walk sinks them. A water hazard over the lane puts a
## slime that sinks back on the beach or the islet.
func _lily_pads() -> void:
	if not _mine(Vector2(40.0, 5.0)):
		return
	var hazard := _scene(DUNGEON + "hazard.tscn", "mere-pads-water", Vector2(37.0, 5.0))
	hazard.set(&"kind", "water")
	hazard.set(&"size", Vector2(7 * CELL, CELL))
	for side: Array in [["ReturnBeach", Vector2(44.6, 5.5)], ["ReturnIslet", Vector2(35.5, 5.5)]]:
		var back := Node2D.new()
		back.name = side[0]
		back.position = _units(side[1]) - hazard.position
		_own(back, hazard)
	for x in range(37, 44):
		var landing := x == 41 or x == 38
		_scene(GLOOP_OBJECTS + ("lily-pad-landing.tscn" if landing else "sinking-lily-pad.tscn"),
				"lily-landing" if landing else "lily-pad", Vector2(x, 5.0))


## The Bow's secret east of the beach (the owner, 2026-11-21: a secret reached by hitting a target with
## the bow, a falling bridge, a hole so the only way is the arrow): a ravine (level -2, a void hazard
## over it) between the beach's east bank and a glade with a chest. A drawbridge stands up on the
## glade's rim; a crystal lens on the glade, struck by an arrow from the bank, lowers it for good.
func _ravine() -> void:
	if not _mine(Vector2(56.0, 5.0)):
		return
	var hazard := _scene(DUNGEON + "hazard.tscn", "ravine-void", Vector2(53.0, 5.0))
	hazard.set(&"kind", "void")
	hazard.set(&"size", Vector2(7 * CELL, 2 * CELL))
	# the far wall shows at the top, sinking into the dark (all black read as a box; the hole's own
	# art alone, its two courses of wall, read as a step)
	hazard.set(&"top_fade_px", 104.0)
	var back := Node2D.new()
	back.name = "ReturnBank"
	back.position = _units(Vector2(56.0, 8.0)) - hazard.position
	_own(back, hazard)
	var bridge := _scene(DUNGEON + "drawbridge.tscn", "ravine-bridge", Vector2(56.0, 5.0))
	bridge.set(&"toward", "south")
	bridge.set(&"length", 2)
	bridge.set(&"width", 128.0)
	bridge.set(&"bridge_id", "gloop-ravine-bridge")
	var lens := _scene(OBJECTS + "crystal-lens.tscn", "ravine-lens", Vector2(58.6, 4.5))
	lens.set(&"lens_id", "gloop-ravine-lens")
	var targets: Array[NodePath] = [NodePath("../" + String(bridge.name))]
	lens.set(&"targets", targets)
	_chest("ravine-chest", Vector2(54.4, 3.6), {"coins": 60, "energy-potion": 1}, "")


func _parcel(node_name: String, at: Vector2, coins: int, flag: String) -> void:
	if not _mine(at):
		return
	var parcel := _scene(OBJECTS + "silk-parcel.tscn", node_name, at)
	parcel.set(&"coins", coins)
	parcel.set(&"flag_id", flag)


func _enemy(enemy_name: String, type: String, at: Vector2, wander: float) -> void:
	if not _mine(at):
		return
	var placed := (load(PLACED_ENEMY) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	placed.name = _unique(enemy_name)
	placed.position = _units(at)
	placed.set(&"enemy_type", type)
	placed.set(&"wander_radius", wander)
	var enemies := _root.get_node_or_null("Enemies")
	_own(placed, enemies if enemies != null else _holder)


func _chest(chest_name: String, at: Vector2, contents: Dictionary, heart_id: String) -> void:
	if not _mine(at):
		return
	var chest := _scene(OBJECTS + "chest-wooden.tscn", chest_name, at)
	var script_node := chest.get_node("ChestScript")
	_root.set_editable_instance(chest, true)
	script_node.set(&"map_id", "gloop-forest-" + _chunk)
	script_node.set(&"instance_id", "gloop-forest-%s-%s" % [_chunk, chest_name])
	script_node.set(&"initial_contents", contents)
	script_node.set(&"goo_heart_id", heart_id)


func _arrival(door_id: String, at: Vector2) -> void:
	if not _mine(at):
		return
	var end := Node2D.new()
	end.name = door_id
	end.position = _units(at)
	_own(end, _holder)
	var door := Node.new()
	door.name = "DoorScript"
	door.set_script(load(DOOR))
	door.set(&"map_id", "gloop-forest-" + _chunk)
	door.set(&"door_id", door_id)
	_own(door, end)


func _move_spawn(at: Vector2) -> void:
	var spawn := _root.get_node_or_null("player-spawn") as Node2D
	if spawn != null:
		spawn.position = _units(at)


## The edges of a new chunk (E3, F3) to its neighbours in the region, and E4's and F4's new north edges.
func _edges() -> void:
	match _chunk:
		"e3":
			_edge("edge-east", "f3", "west")
			_edge("edge-south", "e4", "north")
		"f3":
			_edge("edge-west", "e3", "east")
			_edge("edge-south", "f4", "north")
		"e4":
			_edge("edge-north", "e3", "south")
		"f4":
			_edge("edge-north", "f3", "south")


func _edge(edge_name: String, to: String, entry: String) -> void:
	if _root.has_node(edge_name):
		return
	var exit := Area2D.new()
	exit.name = edge_name
	exit.collision_layer = 512
	exit.collision_mask = 130
	exit.monitorable = false
	var size := Vector2(4, 2048)
	match edge_name:
		"edge-east":
			exit.position = Vector2(2046, 1024)
		"edge-west":
			exit.position = Vector2(2, 1024)
		"edge-south":
			exit.position = Vector2(1024, 2046)
			size = Vector2(2048, 4)
		"edge-north":
			exit.position = Vector2(1024, 2)
			size = Vector2(2048, 4)
	_own(exit, _root)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	_own(shape, exit)
	var script_node := Node.new()
	script_node.name = "world-exit-script"
	script_node.set_script(load(WORLD_EXIT))
	script_node.set(&"map_id", "gloop-forest-" + _chunk)
	script_node.set(&"exit_id", "gloop-forest-%s-to-gloop-forest-%s" % [_chunk, to])
	script_node.set(&"target_area_id", "gloop-forest-" + to)
	script_node.set(&"entry", entry)
	script_node.set(&"keep_along", true)
	script_node.set(&"area", exit)
	_own(script_node, exit)


# --- the North Wilds' D3 and G3, closed against Gloop's new E3 and F3 ----------------------------

func _close_wilds() -> Error:
	for spec: Array in [["d3", 30, "north-wilds-e3"], ["g3", 0, "north-wilds-f3"]]:
		var path := "res://game/scenes/worlds/chunks/north-wilds-%s.tscn" % spec[0]
		var before := FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))
		var root := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		for child: Node in root.get_children():
			var script_node := child.get_node_or_null("world-exit-script")
			if script_node != null and str(script_node.get(&"target_area_id")) == spec[2]:
				root.remove_child(child)
				child.free()
		var forest := root.get_node_or_null("forest") as TileMapLayer
		if forest != null:
			for y in SIDE:
				for dx in 2:
					forest.set_cell(Vector2i(int(spec[1]) + dx, y), CANOPY_SOURCE, FOREST_MIX)
		if _dry:
			root.free()
			continue
		var err := SceneSave.save(root, path, before)
		print("gloop river roads (wilds): ", path, " ", error_string(err))
		root.free()
		if err != OK:
			return err
	return OK


# --- helpers --------------------------------------------------------------------------------------

## Whether region cell point `at` lies in this chunk.
func _mine(at: Vector2) -> bool:
	var c := Vector2i(floori(at.x), floori(at.y)) - _origin
	return c.x >= 0 and c.y >= 0 and c.x < SIDE and c.y < SIDE


## A region cell point in this chunk's units.
func _units(at: Vector2) -> Vector2:
	return (at - Vector2(_origin)) * CELL


func _scene(path: String, node_name: String, at: Vector2) -> Node2D:
	var node := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	node.name = _unique(node_name)
	node.position = _units(at)
	_own(node, _holder)
	return node


func _own(node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = _root


func _unique(base: String) -> String:
	var unique := base
	var n := 2
	var enemies := _root.get_node_or_null("Enemies")
	while _holder.has_node(NodePath(unique)) or (enemies != null and enemies.has_node(NodePath(unique))):
		unique = "%s-%d" % [base, n]
		n += 1
	return unique
