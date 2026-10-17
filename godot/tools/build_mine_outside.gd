extends SceneTree
## Lays the Crystal Mine's outside into three Crystal Caverns chunk worlds (docs/godot/DUNGEONS.md
## "The Crystal Mine (built)"; the design: docs/design/2026-10-16-dungeon-crystal-caverns.md "Where it
## sits in the world" and "Outside: the smith's mine camp"):
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_mine_outside.gd [-- --dry]
## then bake their elevation: res://tools/bake_elevation.gd -- --world=crystal-caverns-g4,crystal-caverns-h4.
##
## - **G4, the smith's mine camp:** the mountain along the chunk's north (level 2 on a new
##   `elevation` layer), the mine's mouth cut into its face with the mine gate (lantern_gate.gd) and
##   the cold brazier beside it (lit, it burns for good and the gate opens for good), the way in
##   (a world exit to `crystal-mine`'s `arrive-from-camp`), the smith at his anvil
##   (game/scenes/characters/smith.tscn) with the camp's director (game/crystal_mine/mine_camp.gd:
##   the Lantern, the gate's lesson, Burr), tents, the campfire, the smith's cot (a bed), rails out
##   of the mine, and `arrive-from-crystal-mine` in front of the gate (the mine's way out).
## - **H4, the Lookout:** the mountain goes on as a plateau; on top, `arrive-from-crystal-mine`
##   where the climb out of the Colossus's arena comes up into daylight, and a flight of stairs down
##   its face to the path west to the camp.
## - **G5, the cave road:** a road cleared from the west edge (Gloop Forest) and north to the camp,
##   the mine's rails along it (the leading line), lantern posts, and a Crystal Crawler circling a
##   crystal pillar by the road, alone.
##
## Each chunk is read as it is on disk and changed only inside its own rects: the placeholder's
## props, trees and worm camps there are taken out and its ground there becomes cavern floor; the
## tool's own nodes live under the node `MineOutside`, replaced on every run, and it owns the whole
## `elevation` layer of G4 and H4 (none was painted before).
##
## Owner: dungeons (the Crystal Mine).

const SceneSave := preload("res://tools/lib/scene_save.gd")

const CHUNKS := "res://game/scenes/worlds/chunks/crystal-caverns-%s.tscn"
const CELL := 64
const SHEET := 19
const CAVERN := 1
const CRYSTAL := 2
const CLUSTER := "res://game/scenes/objects/crystal-cluster-wall--%02d.tscn"
const HOLDER := "MineOutside"
const PROP_LAYERS: PackedStringArray = ["forest", "large-props", "old-props", "cell-props", "details"]
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const WORLD_EXIT := "res://game/scripts/world_exit.gd"
const RAILS := "res://game/crystal_mine/mine_rails.gd"
const MINE_CAMP := "res://game/crystal_mine/mine_camp.gd"
const SHEET_SPRITE := "res://game/runtime/sheet_sprite.gd"
const SOFT_GLOW := "res://game/prologue/soft_glow.gd"
const OBJECTS := "res://game/scenes/objects/"
const SMITH := "res://game/scenes/characters/smith.tscn"
const PLACED_ENEMY := "res://game/scenes/encounters/placed-enemy.tscn"
const WORKSHOP := "res://game/scenes/objects/interiors/workshop/"
const STORAGE := "res://game/scenes/objects/interiors/storage/"
const BEDS := "res://game/scenes/objects/interiors/beds/"
const LANTERN_ART := "res://asset/MAPS/props/mine/128x128-mine-lantern.webp"
const CART_ART := "res://asset/MAPS/props/mine/256x256-mine-cart.webp"
## elevation_tileset.tres: level 2 at (4, 0); a front flight of stairs pointing south at (0, 1).
const ROCK := Vector2i(4, 0)
const STAIRS_SOUTH := Vector2i(0, 1)

var _dry := false
var _root: Node2D
var _holder: Node2D


func _initialize() -> void:
	_dry = OS.get_cmdline_user_args().has("--dry")
	var failed := 0
	for chunk: String in ["g4", "h4", "g5"]:
		if _build(chunk) != OK:
			failed += 1
	quit(1 if failed > 0 else 0)


func _build(chunk: String) -> Error:
	var path := CHUNKS % chunk
	var before := FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))
	_root = (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	var old := _root.get_node_or_null(HOLDER)
	if old != null:
		_root.remove_child(old)
		old.free()
	_holder = Node2D.new()
	_holder.name = HOLDER
	_holder.y_sort_enabled = true
	_own(_holder, _root)
	match chunk:
		"g4":
			_g4_camp()
		"h4":
			_h4_lookout()
		"g5":
			_g5_road()
	if _dry:
		print("mine outside: %s (dry)" % chunk)
		_root.free()
		return OK
	var err := SceneSave.save(_root, path, before)
	print("mine outside: ", path, " ", error_string(err))
	_root.free()
	return err


# --- G4: the smith's mine camp --------------------------------------------------------------------

func _g4_camp() -> void:
	_clear(Rect2i(0, 0, 32, 11))
	_clear(Rect2i(3, 0, 26, 25))
	_clear(Rect2i(13, 25, 7, 7))
	_clear(Rect2i(20, 11, 12, 5))
	_remove_camps(["crystal-caverns-g4-camp-1", "crystal-caverns-g4-camp-2"])
	# The mountain: level 2 over the north rows; its face hangs over rows 9 and 10. The mine's mouth
	# is a notch two cells wide cut two rows into it: the rock above hangs its face over the notch's
	# back, so the gate stands set into the rock and the way in is just behind it.
	var rock := {}
	for y in range(0, 9):
		for x in range(0, 32):
			rock[Vector2i(x, y)] = true
	for y in range(7, 9):
		for x in [15, 16]:
			rock.erase(Vector2i(x, y))
	_elevation(rock, {})
	_crystal_top(rock)
	_clusters([Vector2(2.5, 3.2), Vector2(6, 5.6), Vector2(9.5, 2.4), Vector2(12.5, 6.4), Vector2(20, 5.8),
		Vector2(23.5, 2.6), Vector2(27, 6.2), Vector2(30.5, 3.4)])
	# The gate across the mouth (on the camp's floor line), then the cold brazier beside it.
	var gate := _scene(OBJECTS + "lantern-gate.tscn", "mine-gate", Vector2(16 * CELL, 11 * CELL))
	gate.set(&"gate_id", "crystal-mine-gate")
	gate.set(&"shut_text", "The mine's gate. Its lamp cups are cold.")
	var brazier := _scene(OBJECTS + "brazier.tscn", "mine-gate-brazier", _t(13.1, 11.9))
	brazier.set(&"burn_ms", 0.0)
	brazier.set(&"group", "mine-camp-gate")
	brazier.set(&"gate_id", "crystal-mine-gate")
	# The way in: behind the gate, in the mouth.
	_exit("exit-to-crystal-mine", Vector2(16 * CELL, int(9.7 * CELL)), Vector2(128, 48), "crystal-caverns-g4",
		"crystal-caverns-g4-to-crystal-mine", "crystal-mine", "arrive-from-camp")
	_marker("arrive-from-crystal-mine", _t(16, 12.7))
	# The smith at his anvil, the camp's director.
	var smith := _scene(SMITH, "smith", _t(19.6, 12.9))
	smith.set(&"start_facing", -1.0)
	_scene(OBJECTS + "decoration-world-solid--anvil.tscn", "smith-anvil", _t(18.2, 12.7))
	_prop(WORKSHOP + "interior-workshop-quench-tub.tscn", "quench-tub", _t(21.3, 12.2), 0.9)
	_prop(WORKSHOP + "interior-workshop-hammer-rack.tscn", "hammer-rack", _t(22.7, 11.6), 0.9)
	_prop(WORKSHOP + "interior-workshop-bellows.tscn", "bellows", _t(20.3, 11.5), 0.85)
	var camp := Node.new()
	camp.name = "MineCamp"
	camp.set_script(load(MINE_CAMP))
	_own(camp, _holder)
	camp.set(&"smith", smith)
	camp.set(&"gate", gate)
	camp.set(&"brazier", brazier)
	# The camp: tents, the campfire and the cauldron, the smith's cot, crates by the face.
	_scene(OBJECTS + "decoration-world-solid--canvas-tent.tscn", "tent", _t(8.6, 15.8))
	_scene(OBJECTS + "decoration-world-solid--canvas-tent.tscn", "tent", _t(24.6, 16.6))
	_scene(OBJECTS + "decoration-world-solid--campfire.tscn", "campfire", _t(19.6, 18.2))
	_scene(OBJECTS + "decoration-world-solid--cooking-cauldron.tscn", "cauldron", _t(21.4, 18.8))
	_scene(OBJECTS + "decoration-world-solid--wood-table.tscn", "table", _t(11.4, 14.6))
	_scene(BEDS + "interior-beds-straw-nest-s.tscn", "smith-cot", _t(9.6, 18.8))
	_scene(OBJECTS + "decoration-world-solid--lantern-post.tscn", "lantern-post", _t(12.2, 20.4))
	_scene(OBJECTS + "decoration-world-solid--lantern-post.tscn", "lantern-post", _t(22.4, 14.6))
	_prop(STORAGE + "interior-storage-crate.tscn", "crate", _t(11.9, 12.1), 1.0)
	_prop(STORAGE + "interior-storage-crate-banded.tscn", "crate", _t(12.7, 12.8), 0.9)
	_prop(WORKSHOP + "interior-workshop-ore-basket.tscn", "ore-basket", _t(18.6, 15.4), 0.9)
	_prop(WORKSHOP + "interior-workshop-lumber-stack.tscn", "lumber", _t(25.8, 19.6), 0.9)
	_lantern(_t(14.2, 9.4))
	_lantern(_t(17.8, 9.4))
	# The rails out of the mouth, south through the camp to the cave road (G5), an ore cart on them.
	_rails([_t(16, 10.3), _t(16, 14.2), _t(14, 16.2), _t(14, 22), _t(16, 24), _t(16, 32)])
	_cart(_t(14, 19.6))


# --- H4: the Lookout ------------------------------------------------------------------------------

func _h4_lookout() -> void:
	_clear(Rect2i(0, 0, 20, 16))
	_remove_camps(["crystal-caverns-h4-camp-2"])
	# The mountain goes on from G4 as a plateau; a flight of stairs down its face at x 10, 11.
	var rock := {}
	for y in range(0, 9):
		for x in range(0, 18):
			rock[Vector2i(x, y)] = true
	_elevation(rock, {Vector2i(10, 9): STAIRS_SOUTH, Vector2i(11, 9): STAIRS_SOUTH})
	_crystal_top(rock)
	_clusters([Vector2(1.5, 2.6), Vector2(3, 7), Vector2(15.6, 2.2), Vector2(16.4, 7.2)])
	# The Lookout: where the climb out of the Colossus's arena comes up.
	_marker("arrive-from-crystal-mine", _t(7.5, 4.6))
	_glow("lookout-daylight", _t(7.5, 4.2), Vector2(150, 80), Color(1.0, 0.94, 0.72, 0.28))
	_scene(OBJECTS + "rock-stump.tscn", "lookout-rock", _t(5.4, 3.6))
	_scene(OBJECTS + "rock-stump.tscn", "lookout-rock", _t(9.8, 2.8))
	_scene(OBJECTS + "ore-heap.tscn", "lookout-ore", _t(13.6, 5.2))


# --- G5: the cave road ----------------------------------------------------------------------------

func _g5_road() -> void:
	_clear(Rect2i(13, 0, 7, 21))
	_clear(Rect2i(0, 15, 20, 6))
	_clear(Rect2i(19, 8, 6, 7))
	_remove_camps(["crystal-caverns-g5-camp-1", "crystal-caverns-g5-camp-2"])
	_rails([_t(0, 18), _t(13.6, 18), _t(16, 15.6), _t(16, 0)])
	for at: Vector2 in [_t(14.6, 3.4), _t(17.4, 8.4), _t(14.6, 13.4), _t(7, 16.6)]:
		_scene(OBJECTS + "decoration-world-solid--lantern-post.tscn", "lantern-post", at)
	# The first Crystal Crawler, alone, circling its pillar by the road.
	var pillar := _t(21.5, 11.4)
	_scene(OBJECTS + "crystal-pillar.tscn", "road-pillar", pillar)
	_enemy("road-crawler", "crystal-crawler", pillar + Vector2(0, -81), 120.0)


# --- helpers --------------------------------------------------------------------------------------

static func _t(x: float, y: float) -> Vector2:
	return Vector2(x * CELL, y * CELL)


func _own(node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = _root


## Takes the placeholder out of `rect` (cells): props, trees and details; the ground becomes cavern
## floor.
func _clear(rect: Rect2i) -> void:
	for layer_name: String in PROP_LAYERS:
		var layer := _root.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			continue
		# The layers' grids differ (old-props 8 units, details 32): a cell counts by its 64-unit cell.
		var size := layer.tile_set.tile_size if layer.tile_set != null else Vector2i(CELL, CELL)
		for cell: Vector2i in layer.get_used_cells():
			var grid := Vector2i(floori(float(cell.x * size.x) / CELL), floori(float(cell.y * size.y) / CELL))
			if rect.has_point(grid):
				layer.erase_cell(cell)
	var ground := _root.get_node("ground") as TileMapLayer
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			ground.set_cell(Vector2i(x, y), CAVERN, Vector2i(x % SHEET, y % SHEET))


## Removes the placeholder's worm camps (their areas and the placed enemies near them).
func _remove_camps(names: Array) -> void:
	var enemies := _root.get_node_or_null("Enemies")
	for camp_name: String in names:
		var camp := _root.get_node_or_null(camp_name) as Node2D
		if camp == null:
			continue
		if enemies != null:
			for enemy: Node in enemies.get_children():
				if enemy is Node2D and (enemy as Node2D).position.distance_to(camp.position) < 220.0:
					enemies.remove_child(enemy)
					enemy.free()
		_root.remove_child(camp)
		camp.free()


## The chunk's `elevation` layer (made when missing), repainted: `rock` cells at level 2, `stairs`
## cells with their stair tiles.
func _elevation(rock: Dictionary, stairs: Dictionary) -> void:
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
	layer.clear()
	for cell: Vector2i in rock:
		layer.set_cell(cell, 0, ROCK)
	for cell: Vector2i in stairs:
		layer.set_cell(cell, 0, stairs[cell])


## The rock's top in crystal floor, so its walls are crystal rock and it never reads as the floor
## below.
func _crystal_top(rock: Dictionary) -> void:
	var ground := _root.get_node("ground") as TileMapLayer
	for cell: Vector2i in rock:
		ground.set_cell(cell, CRYSTAL, Vector2i(cell.x % SHEET, cell.y % SHEET))


## Crystal clusters standing on the rock's top (cells), for its mass.
func _clusters(cells: Array) -> void:
	var i := 0
	for at: Vector2 in cells:
		var path := CLUSTER % (3 + (i % 5) * 2)
		if ResourceLoader.exists(path):
			_scene(path, "rock-crystals", _t(at.x, at.y))
		i += 1


func _scene(path: String, node_name: String, at: Vector2) -> Node2D:
	var node := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	node.name = _unique(node_name)
	node.position = at
	_own(node, _holder)
	return node


func _prop(path: String, node_name: String, at: Vector2, size: float) -> void:
	if not ResourceLoader.exists(path):
		push_warning("no prop " + path)
		return
	var prop := _scene(path, node_name, at)
	prop.scale = Vector2(size, size)


func _marker(marker_name: String, at: Vector2) -> void:
	var marker := Node2D.new()
	marker.name = marker_name
	marker.position = at
	_own(marker, _holder)


func _exit(exit_name: String, at: Vector2, size: Vector2, map_id: String, exit_id: String, target: String,
		entry_marker: String) -> void:
	var exit := Area2D.new()
	exit.name = exit_name
	exit.position = at
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
	script_node.set(&"map_id", map_id)
	script_node.set(&"exit_id", exit_id)
	script_node.set(&"target_area_id", target)
	script_node.set(&"entry_marker", entry_marker)
	script_node.set(&"area", exit)
	_own(script_node, exit)


func _enemy(node_name: String, type: String, at: Vector2, wander: float) -> void:
	var placed := (load(PLACED_ENEMY) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	placed.name = _unique(node_name)
	placed.position = at
	placed.set(&"enemy_type", type)
	placed.set(&"wander_radius", wander)
	_own(placed, _holder)


func _rails(points: Array) -> void:
	var rails := Node2D.new()
	rails.name = _unique("rails")
	rails.set_script(load(RAILS))
	var first: Vector2 = points[0]
	rails.position = first
	var local := PackedVector2Array()
	for p: Vector2 in points:
		local.append(p - first)
	rails.set(&"points", local)
	_own(rails, _holder)


func _lantern(at: Vector2) -> void:
	var lamp := Sprite2D.new()
	lamp.name = _unique("mine-lantern")
	lamp.set_script(load(SHEET_SPRITE))
	lamp.set(&"sheet_path", LANTERN_ART)
	lamp.centered = false
	lamp.offset = Vector2(-64, -124)
	lamp.scale = Vector2(0.5, 0.5)
	lamp.position = at
	_own(lamp, _holder)


func _cart(at: Vector2) -> void:
	var cart := StaticBody2D.new()
	cart.name = _unique("ore-cart")
	cart.position = at
	cart.collision_mask = 0
	_own(cart, _holder)
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
	visual.set(&"sheet_path", CART_ART)
	visual.centered = false
	visual.offset = Vector2(-128, -252)
	visual.scale = Vector2(0.32, 0.32)
	_own(visual, cart)


func _glow(glow_name: String, at: Vector2, radius: Vector2, color: Color) -> void:
	var glow := Node2D.new()
	glow.name = _unique(glow_name)
	glow.set_script(load(SOFT_GLOW))
	glow.position = at
	glow.set(&"radius", radius)
	glow.set(&"color", color)
	glow.set(&"additive", true)
	glow.set(&"pulse", 0.2)
	glow.set(&"period_s", 5.0)
	glow.z_index = 3
	_own(glow, _holder)


func _unique(base: String) -> String:
	var unique := base
	var n := 2
	while _holder.has_node(NodePath(unique)):
		unique = "%s-%d" % [base, n]
		n += 1
	return unique
