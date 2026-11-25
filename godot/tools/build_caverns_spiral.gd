extends SceneTree
## Lays the Crystal Caverns' falling-slab maze, the Spiral (roadmap 12.9, the owner's pick of
## 2026-11-20; the plan: docs/design/2026-11-20-caverns-spiral.md), into ONE chunk world a run:
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_caverns_spiral.gd -- --chunk=g4 [--dry]
## then bake that chunk and its neighbours: res://tools/bake_elevation.gd -- --world=crystal-caverns-g4,...
##
## Rings round a central peak (the smith's cave in its south face): the outer ring (side ways), the
## outer canyon (the void; only its stretch along the main ring's south side is a spike pit), the
## main ring (the main road, climbing from level 0 in G4's west to 3 in G5's west), the void, the
## inner ledge (level 3) and the peak (level 4). The void is most of the damage area (owner,
## 2026-11-20): a fall hurts and sets the slime back; spikes are rarer. Every run of falling slabs
## crosses the void; a long run has no landing (only the Charged Roll held all the way), a short
## one a landing every two slabs. Chunk lines are closed by crystal trees or the void, with five
## crossings between lantern posts (rule 11).
##
## The layout is held once for the whole region (64 x 64 cells, G4 at the north-west) and each run
## writes one chunk's part of it: its ground, its `elevation` layer (owned whole by this tool), its
## `forest` layer (the crystal trees: the region's rim and the chunk lines), and its nodes under
## `Spiral`, replaced on every run. The placeholder's props, worm camps, placed enemies and the old
## mine camp (`MineOutside`, tools/build_mine_outside.gd's, retired) are taken out. After the run
## the chunk scene is the one to edit by hand; running the tool again lays the chunk afresh.
##
## Owner: world (the Crystal Caverns).

const SceneSave := preload("res://tools/lib/scene_save.gd")

const CHUNKS := "res://game/scenes/worlds/chunks/crystal-caverns-%s.tscn"
const ORIGINS := {"g4": Vector2i(0, 0), "h4": Vector2i(32, 0), "g5": Vector2i(0, 32), "h5": Vector2i(32, 32)}
const N := 64
const SIDE := 32
const CELL := 64
const SHEET := 19
const CAVERN := 1
const CRYSTAL_FLOOR := 2
const HOLDER := "Spiral"
const OLD_HOLDER := "MineOutside"
const CLEAR_LAYERS: PackedStringArray = ["forest", "large-props", "old-props", "cell-props", "details"]
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
## forest_tileset.tres, source 0: the crystal set's tree.
const TREE_SOURCE := 0
const TREE := Vector2i(14, 0)
const VOID_LEVEL := -2
const PIT_LEVEL := -1
const STAIRS_ROW := 1
const STAIR_DIRS := {"s": 0, "sw": 1, "w": 2, "nw": 3, "n": 4, "ne": 5, "e": 6, "se": 7}
const VINE_LAYER := "res://game/world/vines/vine_layer.gd"
const VINE_TILESET := "res://game/world/vines/vine_tileset.tres"
## The Feral skin's come-back climbs (region cells, on a wall's face): the heart pinnacle on the east
## shelf (H4), and the peak's face and its shoulder's above the inner ledge (G5).
const VINES: Array[Vector2i] = [Vector2i(58, 15), Vector2i(59, 15), Vector2i(58, 16), Vector2i(59, 16),
		Vector2i(29, 35), Vector2i(29, 36)]

const OBJECTS := "res://game/scenes/objects/"
const DUNGEON := "res://game/scenes/objects/dungeon/"
const STORAGE := "res://game/scenes/objects/interiors/storage/"
const CLUSTER := "res://game/scenes/objects/crystal-cluster-wall--%02d.tscn"
const PLACED_ENEMY := "res://game/scenes/encounters/placed-enemy.tscn"
const WORLD_EXIT := "res://game/scripts/world_exit.gd"
const DOOR := "res://game/scripts/door.gd"
const SOFT_GLOW := "res://game/prologue/soft_glow.gd"
const ROLL_HINT := "res://game/crystal_mine/charged_roll_hint.gd"

## The rooms (room worlds) the cave mouths lead into, and the doors there.
const SMITH_CAVE := "crystal-caverns-smith-cave"
const CORNER_CAVE := "crystal-caverns-corner-cave"
const BAY_CAVE := "crystal-caverns-bay-cave"
const DARK_NOOK := "crystal-caverns-dark-nook"
const TUNNEL := "crystal-caverns-under-line-tunnel"

enum Kind { GROUND, CRYSTAL_TOP, VOID, SPIKES }

var _dry := false
var _chunk := ""
var _origin := Vector2i.ZERO
var _root: Node2D
var _holder: Node2D
## The whole region's layout, cell index y * N + x.
var _kind := PackedInt32Array()
var _level := PackedInt32Array()
var _tree := PackedByteArray()
## Vector2i (region cell) -> stairs direction ("s", "w", ...).
var _stairs := {}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--dry":
			_dry = true
		elif arg.begins_with("--chunk="):
			_chunk = arg.trim_prefix("--chunk=")
	if not ORIGINS.has(_chunk):
		push_error("build_caverns_spiral: give one chunk, --chunk=g4|h4|g5|h5")
		quit(1)
		return
	_origin = ORIGINS[_chunk]
	_layout()
	quit(0 if _build() == OK else 1)


# --- the layout (region cells) --------------------------------------------------------------------

static func _ring(c: Vector2i) -> int:
	return mini(mini(c.x, c.y), mini(N - 1 - c.x, N - 1 - c.y))


func _layout() -> void:
	_kind.resize(N * N)
	_level.resize(N * N)
	_tree.resize(N * N)
	for y in N:
		for x in N:
			var d := _ring(Vector2i(x, y))
			var i := y * N + x
			_tree[i] = 0
			if d <= 7:
				_set_cell(i, Kind.GROUND, 0)        # the rim and the outer ring
			elif d <= 12:
				_set_cell(i, Kind.VOID, VOID_LEVEL)  # the outer canyon
			elif d <= 18:
				_set_cell(i, Kind.GROUND, 2)        # the main ring
			elif d <= 24:
				_set_cell(i, Kind.VOID, VOID_LEVEL)  # the void
			elif d <= 27:
				_set_cell(i, Kind.GROUND, 3)        # the inner ledge
			else:
				_set_cell(i, Kind.CRYSTAL_TOP, 4)   # the peak
	# The main ring climbs as it goes round: 0 on G4's west side, 1 along the north, 2 down the east
	# and along the south, 3 on G5's west side over a low strip (the loop back to X4).
	# (Each stretch runs across the chunk line it meets, so the line's cells keep its level.)
	_fill(Rect2i(13, 13, 6, 24), Kind.GROUND, 0)
	_fill(Rect2i(19, 13, 28, 6), Kind.GROUND, 1)
	_fill(Rect2i(13, 37, 6, 5), Kind.GROUND, 3)
	# The peak and the inner ledge only south and west of it; the peak's shoulder (Feral).
	_fill(Rect2i(25, 25, 14, 11), Kind.CRYSTAL_TOP, 4)
	_fill(Rect2i(25, 33, 3, 6), Kind.GROUND, 3)
	_fill(Rect2i(25, 36, 14, 3), Kind.GROUND, 3)
	_fill(Rect2i(28, 33, 3, 2), Kind.CRYSTAL_TOP, 5)
	# The gaps the long runs cross.
	_fill(Rect2i(13, 19, 6, 6), Kind.VOID, VOID_LEVEL)    # G1, Run 1
	_fill(Rect2i(37, 13, 8, 6), Kind.VOID, VOID_LEVEL)    # G2, Run 2
	for y in range(41, 51):                               # G3, Run 3: the ring's south-east corner
		for x in range(43, 51):
			if (x >= 45 or y >= 45) and _kind[y * N + x] == Kind.GROUND:
				_set_cell(y * N + x, Kind.VOID, VOID_LEVEL)
	# The crag at the ring's north-east corner (the Corner Cave inside).
	_fill(Rect2i(45, 8, 6, 7), Kind.CRYSTAL_TOP, 3)
	_fill(Rect2i(47, 15, 4, 6), Kind.CRYSTAL_TOP, 3)
	_fill(Rect2i(45, 19, 2, 2), Kind.CRYSTAL_TOP, 3)
	# The outer ring's stretches.
	_fill(Rect2i(8, 2, 54, 6), Kind.GROUND, 1)             # the north shelf (G4), the Lookout's foot (H4)
	_fill(Rect2i(56, 8, 6, 54), Kind.GROUND, 1)            # the east shelf (H4), the south-east bay (H5)
	_fill(Rect2i(32, 56, 24, 6), Kind.GROUND, 1)
	_fill(Rect2i(35, 2, 9, 4), Kind.CRYSTAL_TOP, 2)        # the Lookout plateau (kept)
	_fill(Rect2i(57, 12, 4, 3), Kind.CRYSTAL_TOP, 3)       # the heart pinnacle
	_fill(Rect2i(13, 2, 4, 2), Kind.CRYSTAL_TOP, 3)        # the Dark Nook's rock
	_fill(Rect2i(57, 25, 4, 2), Kind.CRYSTAL_TOP, 3)       # the Under-line Tunnel's rocks
	_fill(Rect2i(57, 33, 4, 2), Kind.CRYSTAL_TOP, 3)
	_fill(Rect2i(0, 0, 8, 20), Kind.CRYSTAL_TOP, 2)        # the gate mountain
	_fill(Rect2i(3, 18, 2, 2), Kind.GROUND, 0)             # the mine's mouth, a notch in its face
	_fill(Rect2i(39, 35, 3, 3), Kind.GROUND, 2)            # the void islet (the side LONG 3)
	# Spikes, the rarer hazard: the canyon along the main ring's south side, which no run crosses.
	_fill(Rect2i(13, 51, 17, 5), Kind.SPIKES, PIT_LEVEL)
	_fill(Rect2i(34, 51, 17, 5), Kind.SPIKES, PIT_LEVEL)
	# The rim: crystal trees on the outer two rows, at the level of the ground inside them (on the gate
	# mountain they stand on its top), but for the way in from Gloop Forest (G4 rows 26-27).
	for y in N:
		for x in N:
			var c := Vector2i(x, y)
			if _ring(c) > 1:
				continue
			if x <= 1 and (y == 26 or y == 27):
				continue
			if _kind[y * N + x] == Kind.CRYSTAL_TOP:
				_tree[y * N + x] = 1
				continue
			var inside := Vector2i(clampi(x, 2, N - 3), clampi(y, 2, N - 3))
			_set_cell(y * N + x, Kind.GROUND, _level[inside.y * N + inside.x])
			_tree[y * N + x] = 1
	# The chunk lines: crystal trees on every cell of ground there (the void closes a line by
	# itself), but at the five crossings.
	var crossings: Array[Rect2i] = [Rect2i(31, 15, 2, 2), Rect2i(47, 31, 2, 2), Rect2i(31, 47, 2, 2),
			Rect2i(15, 31, 2, 2), Rect2i(31, 37, 2, 2)]
	for y in N:
		for x in N:
			if not (x == 31 or x == 32 or y == 31 or y == 32):
				continue
			var k := _kind[y * N + x]
			if k == Kind.VOID or k == Kind.SPIKES:
				continue
			var crossing := false
			for r: Rect2i in crossings:
				if r.has_point(Vector2i(x, y)):
					crossing = true
			if not crossing:
				_tree[y * N + x] = 1
	# Stairs: on the first cell past the rim, on the lower side, the arrow pointing down the flight.
	for c: Vector2i in [Vector2i(18, 15), Vector2i(18, 16)]:
		_stairs[c] = "w"   # the main ring, level 0 up to 1 (G4)
	for c: Vector2i in [Vector2i(15, 42), Vector2i(16, 42)]:
		_stairs[c] = "s"   # the south-west corner, level 2 up to 3 (G5)
	for c: Vector2i in [Vector2i(42, 6), Vector2i(43, 6)]:
		_stairs[c] = "s"   # the Lookout's flight (H4), as before
	for c: Vector2i in [Vector2i(27, 51), Vector2i(28, 51), Vector2i(38, 51), Vector2i(39, 51)]:
		_stairs[c] = "s"   # out of the spike canyon, up to the main ring
	for c: Vector2i in [Vector2i(20, 55), Vector2i(21, 55), Vector2i(45, 55), Vector2i(46, 55)]:
		_stairs[c] = "n"   # out of the spike canyon, up to the south strip (G5) and the bay (H5)


func _set_cell(i: int, kind: int, level: int) -> void:
	_kind[i] = kind
	_level[i] = level


func _fill(rect: Rect2i, kind: int, level: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_set_cell(y * N + x, kind, level)


func _kind_at(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= N or c.y >= N:
		return Kind.GROUND
	return _kind[c.y * N + c.x]


func _level_at(c: Vector2i) -> int:
	return _level[clampi(c.y, 0, N - 1) * N + clampi(c.x, 0, N - 1)]


# --- one chunk ------------------------------------------------------------------------------------

func _build() -> Error:
	var path := CHUNKS % _chunk
	var before := FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))
	_root = (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	for old_name: String in [OLD_HOLDER, HOLDER]:
		var old := _root.get_node_or_null(old_name)
		if old != null:
			_root.remove_child(old)
			old.free()
	for child: Node in _root.get_children():
		var n := String(child.name)
		if n.begins_with("crystal-caverns-%s-camp" % _chunk) or n.begins_with("enemy-safe"):
			_root.remove_child(child)
			child.free()
	var enemies := _root.get_node_or_null("Enemies")
	if enemies != null:
		for enemy: Node in enemies.get_children():
			enemies.remove_child(enemy)
			enemy.free()
	_holder = Node2D.new()
	_holder.name = HOLDER
	_holder.y_sort_enabled = true
	_own(_holder, _root)
	_paint()
	_place()
	if _dry:
		print("caverns spiral: %s (dry)" % _chunk)
		_root.free()
		return OK
	var err := SceneSave.save(_root, path, before)
	print("caverns spiral: ", path, " ", error_string(err))
	_root.free()
	return err


func _paint() -> void:
	for layer_name: String in CLEAR_LAYERS:
		var layer := _root.get_node_or_null(layer_name) as TileMapLayer
		if layer != null:
			layer.clear()
	var ground := _root.get_node("ground") as TileMapLayer
	var elevation := _elevation_layer()
	elevation.clear()
	var forest := _root.get_node("forest") as TileMapLayer
	for y in SIDE:
		for x in SIDE:
			var local := Vector2i(x, y)
			var c := _origin + local
			var i := c.y * N + c.x
			var floor_source := CRYSTAL_FLOOR if _kind[i] == Kind.CRYSTAL_TOP else CAVERN
			ground.set_cell(local, floor_source, Vector2i(c.x % SHEET, c.y % SHEET))
			if _stairs.has(c):
				elevation.set_cell(local, 0, Vector2i(int(STAIR_DIRS[str(_stairs[c])]), STAIRS_ROW))
			elif _level[i] != 0:
				elevation.set_cell(local, 0, _level_tile(_level[i]))
			if _tree[i] == 1:
				forest.set_cell(local, TREE_SOURCE, TREE)
	var vines := _vine_layer()
	vines.clear()
	for c: Vector2i in VINES:
		if _mine(Vector2(c)):
			vines.set_cell(c - _origin, 0, Vector2i(0, 0))


static func _level_tile(level: int) -> Vector2i:
	if level < 0:
		return Vector2i(level + 3, 0)
	if level <= 3:
		return Vector2i(level + 2, 0)
	if level <= 11:
		return Vector2i(level - 4, 4)
	return Vector2i(level - 12, 5)


## The chunk's `vines` VineLayer (made when missing), beside the elevation layer.
func _vine_layer() -> TileMapLayer:
	var layer := _root.get_node_or_null("vines") as TileMapLayer
	if layer == null:
		layer = TileMapLayer.new()
		layer.name = "vines"
		layer.tile_set = load(VINE_TILESET)
		layer.set_script(load(VINE_LAYER))
		_root.add_child(layer)
		_root.move_child(layer, _root.get_node("elevation").get_index() + 1)
		layer.owner = _root
	return layer


func _elevation_layer() -> TileMapLayer:
	var layer := _root.get_node_or_null("elevation") as TileMapLayer
	if layer == null:
		layer = TileMapLayer.new()
		layer.name = "elevation"
		layer.z_index = -1
		layer.tile_set = load(ELEVATION_TILESET)
		layer.set_script(load(ELEVATION_LAYER))
		_root.add_child(layer)
		_root.move_child(layer, _root.get_node("ground").get_index() + 1)
		layer.owner = _root
	return layer


# --- what stands in the chunk (region cells; only what falls inside this chunk is placed) --------

func _place() -> void:
	_hazards()
	# The yard and the mine's gate (G4).
	if _mine(Vector2(4, 22)):
		var gate := _scene(OBJECTS + "lantern-gate.tscn", "mine-gate", Vector2(4, 22))
		gate.set(&"gate_id", "crystal-mine-gate")
		gate.set(&"shut_text", "The mine's gate. Its lamp cups are cold.")
		var brazier := _scene(OBJECTS + "brazier.tscn", "mine-gate-brazier", Vector2(1.6, 22.9))
		brazier.set(&"burn_ms", 0.0)
		brazier.set(&"group", "mine-camp-gate")
		brazier.set(&"gate_id", "crystal-mine-gate")
		# Its flag (candle-lit.mine-gate-brazier) tells the smith in his cave that the gate is open.
		brazier.set_meta(&"instance_id", "mine-gate-brazier")
		_exit("exit-to-crystal-mine", Vector2(4, 20.7), Vector2(128, 48), "crystal-caverns-g4-to-crystal-mine",
				"crystal-mine-m1-mine-mouth", "mine-entrance")
		_arrival("camp-mine-mouth", Vector2(4, 23.7))
		var cart := _scene(OBJECTS + "mine-cart.tscn", "yard-cart-station", Vector2(6.4, 23.4))
		# The end of the smith's cart line (game/crystal_mine/smith_cart.gd rides it down from his cave,
		# one way): the cart stands here once ridden.
		cart.set(&"line_id", "smith-cart")
		cart.set(&"station_id", "yard")
		cart.set(&"starts_with_cart", false)
		cart.set(&"cart_flag", "smith-cart.ridden")
		_arrival("yard-cart", Vector2(6.4, 24.6))
		_move_spawn(Vector2(4.5, 27))
		_clusters([Vector2(1.5, 3), Vector2(5, 5.5), Vector2(2, 10), Vector2(5.5, 13), Vector2(1.5, 16.5)])
	# The runs.
	_short_run([Vector2i(8, 25), Vector2i(9, 25), Vector2i(11, 25), Vector2i(12, 25)], [Vector2i(10, 25)], 0, "short-1")
	_long_run(_line(Vector2i(16, 24), Vector2i(0, -1), 6), 0, "run-1")
	_short_run([Vector2i(24, 12), Vector2i(24, 11), Vector2i(24, 9), Vector2i(24, 8)], [Vector2i(24, 10)], 1, "short-2")
	_short_run([Vector2i(34, 12), Vector2i(34, 11), Vector2i(34, 9), Vector2i(34, 8)], [Vector2i(34, 10)], 1, "short-3")
	_long_run(_line(Vector2i(37, 17), Vector2i(1, 0), 8), 1, "run-2")
	var diagonal: Array[Vector2i] = []
	for i in 6:
		for c: Vector2i in [Vector2i(48 - i, 41 + i), Vector2i(47 - i, 41 + i)]:
			if _kind_at(c) == Kind.VOID:
				diagonal.append(c)
	_long_run(diagonal, 2, "run-3")
	_long_run(_line(Vector2i(19, 38), Vector2i(1, 0), 6), 3, "run-4")
	_long_run(_line(Vector2i(44, 36), Vector2i(-1, 0), 3), 2, "side-run")
	# The crossings, each between lantern posts on its own side of the line.
	for at: Vector2 in [Vector2(30.5, 14.75), Vector2(30.5, 17.25), Vector2(33.5, 14.75), Vector2(33.5, 17.25),
			Vector2(46.75, 30.5), Vector2(49.25, 30.5), Vector2(46.75, 33.5), Vector2(49.25, 33.5),
			Vector2(30.5, 46.75), Vector2(30.5, 49.25), Vector2(33.5, 46.75), Vector2(33.5, 49.25),
			Vector2(14.75, 30.5), Vector2(17.25, 30.5), Vector2(14.75, 33.5), Vector2(17.25, 33.5),
			Vector2(30.5, 37.1), Vector2(30.5, 38.95), Vector2(33.5, 37.1), Vector2(33.5, 38.95)]:
		_post(at)
	# G4: the sign before Run 1, the north side's Crawler, the north shelf.
	_post_sign(Vector2(14.2, 26.4))
	_flower(Vector2(14.5, 14.5))
	_crawler("crawler-c1", Vector2(26, 16))
	_chest("north-shelf-chest", Vector2(10.5, 4.5), {"coins": 20}, "")
	_mole("mole-m3", Vector2(20.5, 5.5))
	_cave_mouth("dark-nook-mouth", Vector2(15, 6), DARK_NOOK, "dark-nook-door", true)
	# H4: the Lookout (kept), the north side's end, the corner crag, the east side, the east shelf.
	if _mine(Vector2(39.5, 4.6)):
		_arrival("lookout-from-mine", Vector2(39.5, 4.6))
		_glow("lookout-daylight", Vector2(39.5, 4.2), Vector2(150, 80), Color(1.0, 0.94, 0.72, 0.28))
		_scene(OBJECTS + "rock-stump.tscn", "lookout-rock", Vector2(37.4, 3.4))
		_scene(OBJECTS + "ore-heap.tscn", "lookout-ore", Vector2(41.6, 3.2))
		_move_spawn(Vector2(48, 25))
	_flower(Vector2(34.5, 15))
	_cave_mouth("corner-cave-west", Vector2(46, 17), CORNER_CAVE, "corner-cave-west", false)
	_cave_mouth("corner-cave-south", Vector2(48.75, 22), CORNER_CAVE, "corner-cave-south", false)
	_mole("mole-m1", Vector2(46.6, 26.2))
	_mole("mole-m2", Vector2(49.4, 28.4))
	_chest("pinnacle-chest", Vector2(58.5, 13.2), {}, "caverns-pinnacle")
	_cave_mouth("tunnel-north", Vector2(59, 29), TUNNEL, "tunnel-north", true)
	_clusters([Vector2(46, 10), Vector2(49.5, 12), Vector2(48.5, 18)])
	# H5: the Prism Eye alone, the side run's islet, Run 3's bats, the south side, the smith, the bay.
	if _mine(Vector2(48, 36)):
		_move_spawn(Vector2(47.5, 34.5))
	_enemy("eye-e1", "prism-eye", Vector2(49.2, 36.2), 0.0)
	for at: Vector2 in [Vector2(46.3, 36.6), Vector2(47.2, 38.7), Vector2(45.6, 34.3)]:
		_scene(OBJECTS + "rock-stump.tscn", "hide-rock", at)
	_flower(Vector2(45.8, 38.4))
	_chest("islet-chest", Vector2(40.5, 36.6), {"coins": 30}, "")
	_enemy("bats-b2", "glint-bat", Vector2(49.4, 39.2), 90.0)
	_crawler("crawler-c3", Vector2(38.5, 47.5))
	_ladder_hole("bay-cave-down", Vector2(35.5, 48), BAY_CAVE, "bay-cave-north")
	_cave_mouth("smith-cave-door", Vector2(35, 37), SMITH_CAVE, "smith-cave-door", false)
	_ladder_hole("bay-cave-up", Vector2(44.5, 58.5), BAY_CAVE, "bay-cave-south")
	_crawler("crawler-c4", Vector2(58.5, 46))
	_chest("bay-chest", Vector2(59, 52.5), {"coins": 25}, "")
	_cave_mouth("tunnel-south", Vector2(59, 37), TUNNEL, "tunnel-south", true)
	# G5: the low strip, the last run's start, the inner ledge and its Prism Eye, the south side.
	if _mine(Vector2(16, 34.5)):
		_move_spawn(Vector2(16, 34.5))
	_flower(Vector2(14.5, 40.5))
	_crawler("crawler-c2", Vector2(24.5, 47.5))
	_enemy("eye-e2", "prism-eye", Vector2(26.5, 35), 0.0)
	_chest("shoulder-chest", Vector2(29.5, 34), {"coins": 40}, "")
	_chest("south-strip-chest", Vector2(5.5, 59), {"coins": 25, "energy-potion": 1}, "")
	_clusters([Vector2(27.5, 27.5), Vector2(31, 29.5), Vector2(35.5, 27), Vector2(37, 31.5), Vector2(26.5, 30.5)])


## The void and the spike canyon: one hazard a rectangle of hole cells (greedy), the void's top
## faded over the far wall above it.
func _hazards() -> void:
	for kind: int in [Kind.VOID, Kind.SPIKES]:
		var taken := {}
		for y in SIDE:
			for x in SIDE:
				var start := _origin + Vector2i(x, y)
				if taken.has(start) or _kind_at(start) != kind:
					continue
				var w := 1
				while x + w < SIDE and _kind_at(start + Vector2i(w, 0)) == kind and not taken.has(start + Vector2i(w, 0)):
					w += 1
				var h := 1
				while y + h < SIDE:
					var row_ok := true
					for dx in w:
						var c := start + Vector2i(dx, h)
						if _kind_at(c) != kind or taken.has(c):
							row_ok = false
							break
					if not row_ok:
						break
					h += 1
				for dy in h:
					for dx in w:
						taken[start + Vector2i(dx, dy)] = true
				var hole_level := VOID_LEVEL if kind == Kind.VOID else PIT_LEVEL
				var above := hole_level
				for dx in w:
					var north := start + Vector2i(dx, -1)
					if _kind_at(north) != Kind.VOID and _kind_at(north) != Kind.SPIKES:
						above = maxi(above, _level_at(north))
				var hazard := _scene(DUNGEON + "hazard.tscn", "void" if kind == Kind.VOID else "spikes",
						Vector2(start.x, start.y))
				hazard.set(&"kind", "void" if kind == Kind.VOID else "spikes")
				hazard.set(&"size", Vector2(w * CELL, h * CELL))
				hazard.set(&"top_fade_px", float((above - hole_level) * CELL))
				# Its rim as the hazard reads it from the paint (the lowest level above its floor next to
				# it, in this chunk), so its settings agree with the paint.
				var rim := _rim_of(Rect2i(start, Vector2i(w, h)), hole_level)
				hazard.set(&"rim_level", rim)
				hazard.set(&"pit_depth", maxi(1, rim - hole_level))


## The lowest level above `floor_level` on the cells next to `rect` (region cells), as hazard.gd
## reads a hazard's rim from the paint: a stairs cell counts as the ground it leads to, a cell past the
## chunk's edge as level 0.
func _rim_of(rect: Rect2i, floor_level: int) -> int:
	var rim := 99
	for y in range(rect.position.y - 1, rect.end.y + 1):
		for x in range(rect.position.x - 1, rect.end.x + 1):
			var c := Vector2i(x, y)
			if rect.has_point(c):
				continue
			if (x < rect.position.x or x >= rect.end.x) and (y < rect.position.y or y >= rect.end.y):
				continue
			# Past the chunk's edge the hazard reads no paint: level 0.
			var level := _painted_level(c) if _mine(Vector2(c)) else 0
			if level > floor_level:
				rim = mini(rim, level)
	return rim if rim != 99 else floor_level + 1


## A cell's level as the elevation reads it: a stairs cell takes the level of the ground it leads to.
func _painted_level(c: Vector2i) -> int:
	if not _stairs.has(c):
		return _level_at(c)
	var step := {"s": Vector2i(0, 1), "n": Vector2i(0, -1), "w": Vector2i(-1, 0), "e": Vector2i(1, 0)}
	var below: Vector2i = c + (step.get(str(_stairs[c]), Vector2i.ZERO) as Vector2i)
	while _stairs.has(below):
		below += step.get(str(_stairs[c]), Vector2i.ZERO) as Vector2i
	return _level_at(below)


func _short_run(slabs: Array[Vector2i], landings: Array[Vector2i], level: int, run_name: String) -> void:
	for c: Vector2i in slabs:
		_slab(c, level, run_name)
	for c: Vector2i in landings:
		if _mine(Vector2(c)):
			var deck := _scene(DUNGEON + "hazard-deck.tscn", run_name + "-landing", Vector2(c))
			deck.set(&"size", Vector2(CELL, CELL))
			deck.set(&"level", level)


func _long_run(cells: Array[Vector2i], level: int, run_name: String) -> void:
	for c: Vector2i in cells:
		_slab(c, level, run_name)


func _slab(c: Vector2i, level: int, run_name: String) -> void:
	if not _mine(Vector2(c)):
		return
	var slab := _scene(DUNGEON + "falling-slab.tscn", "%s-slab" % run_name, Vector2(c))
	slab.set(&"size", Vector2(CELL, CELL))
	slab.set(&"level", level)


static func _line(start: Vector2i, step: Vector2i, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for i in count:
		cells.append(start + step * i)
	return cells


func _post(at: Vector2) -> void:
	if _mine(at):
		_scene(OBJECTS + "decoration-world-solid--lantern-post.tscn", "lantern-post", at)


## The sign before Run 1, which says what the slime lacks without the Charged Roll
## (game/crystal_mine/charged_roll_hint.gd).
func _post_sign(at: Vector2) -> void:
	if not _mine(at):
		return
	_scene(OBJECTS + "town/props/signpost.tscn", "charged-roll-sign", at)
	var hint := Node2D.new()
	hint.name = _unique("charged-roll-hint")
	hint.set_script(load(ROLL_HINT))
	hint.position = _units(at)
	_own(hint, _holder)


func _flower(at: Vector2) -> void:
	if _mine(at):
		_scene(DUNGEON + "energy-flower.tscn", "energy-flower", at)


func _crawler(crawler_name: String, pillar: Vector2) -> void:
	if not _mine(pillar):
		return
	_scene(OBJECTS + "crystal-pillar.tscn", crawler_name + "-pillar", pillar)
	_enemy(crawler_name, "crystal-crawler", pillar + Vector2(0, -81.0 / CELL), 120.0)


## A Pick Mole and the three crates it ducks behind (north of it, as in the mine's ore store).
func _mole(mole_name: String, at: Vector2) -> void:
	if not _mine(at):
		return
	for dx: float in [-58.0, 0.0, 58.0]:
		_scene(STORAGE + "interior-storage-crate.tscn", mole_name + "-crate", at + Vector2(dx, -66.0) / CELL)
	_enemy(mole_name, "pick-mole", at, 70.0)


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
	script_node.set(&"map_id", "crystal-caverns-" + _chunk)
	script_node.set(&"instance_id", "crystal-caverns-%s-%s" % [_chunk, chest_name])
	script_node.set(&"initial_contents", contents)
	script_node.set(&"goo_heart_id", heart_id)


## A cave mouth at a cliff's foot (`at`: the threshold), a door into `room`'s `room_door`; `plugged`:
## a deadthorn hedge in front, for the Lantern's flame.
func _cave_mouth(door_id: String, at: Vector2, room: String, room_door: String, plugged: bool) -> void:
	if not _mine(at):
		return
	var mouth := _scene(OBJECTS + "cave-mouth.tscn", door_id, at)
	var door := mouth.get_node("DoorScript")
	_root.set_editable_instance(mouth, true)
	door.set(&"map_id", "crystal-caverns-" + _chunk)
	door.set(&"door_id", door_id)
	door.set(&"target_area_id", room)
	door.set(&"target_door_id", room_door)
	if plugged:
		_scene(OBJECTS + "deadthorn-hedge.tscn", door_id + "-deadthorn", at + Vector2(0, 0.45))


## A hole with a ladder down into `room` (its `arrival` child is where the way back up comes out).
func _ladder_hole(door_id: String, at: Vector2, room: String, room_door: String) -> void:
	if not _mine(at):
		return
	var hole := _scene(OBJECTS + "open-hole-ladder.tscn", door_id, at)
	var door := hole.get_node_or_null("DoorScript")
	if door != null:
		_root.set_editable_instance(hole, true)
		door.set(&"map_id", "crystal-caverns-" + _chunk)
		door.set(&"door_id", door_id)
		door.set(&"target_area_id", room)
		door.set(&"target_door_id", room_door)


func _clusters(cells: Array) -> void:
	var i := 0
	for at: Vector2 in cells:
		if _mine(at):
			var path := CLUSTER % (3 + (i % 5) * 2)
			if ResourceLoader.exists(path):
				_scene(path, "peak-crystals", at)
		i += 1


func _arrival(door_id: String, at: Vector2) -> void:
	var end := Node2D.new()
	end.name = door_id
	end.position = _units(at)
	_own(end, _holder)
	var door := Node.new()
	door.name = "DoorScript"
	door.set_script(load(DOOR))
	door.set(&"map_id", "crystal-caverns-" + _chunk)
	door.set(&"door_id", door_id)
	_own(door, end)


func _exit(exit_name: String, at: Vector2, size: Vector2, exit_id: String, target: String, target_door: String) -> void:
	var exit := Area2D.new()
	exit.name = exit_name
	exit.position = _units(at)
	exit.collision_layer = 512
	exit.collision_mask = 130
	exit.monitorable = false
	_own(exit, _holder)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	_own(shape, exit)
	var script_node := Node.new()
	script_node.name = "world-exit-script"
	script_node.set_script(load(WORLD_EXIT))
	script_node.set(&"map_id", "crystal-caverns-" + _chunk)
	script_node.set(&"exit_id", exit_id)
	script_node.set(&"target_area_id", target)
	script_node.set(&"target_door_id", target_door)
	script_node.set(&"area", exit)
	_own(script_node, exit)


func _glow(glow_name: String, at: Vector2, radius: Vector2, color: Color) -> void:
	var glow := Node2D.new()
	glow.name = _unique(glow_name)
	glow.set_script(load(SOFT_GLOW))
	glow.position = _units(at)
	glow.set(&"radius", radius)
	glow.set(&"color", color)
	glow.set(&"additive", true)
	glow.set(&"pulse", 0.2)
	glow.set(&"period_s", 5.0)
	glow.z_index = 3
	_own(glow, _holder)


func _move_spawn(at: Vector2) -> void:
	var spawn := _root.get_node_or_null("player-spawn") as Node2D
	if spawn != null:
		spawn.position = _units(at)


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
