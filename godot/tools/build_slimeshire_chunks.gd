extends SceneTree
## Reworks Slimeshire Meadow's four chunk worlds for Chapter 1 (docs/story/chapters/chapter-1-the-clearing.md
## "Slimeshire's places"; the level design guide, docs/design/2026-10-16-level-design.md "Slimeshire's
## chunks and the West village"):
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_slimeshire_chunks.gd [-- --only=d5,c4 --dry]
## then bake the changed worlds' elevation: res://tools/bake_elevation.gd -- --world=level-1-d5,...
##
## - **D5, Fatty's Hollow:** a red-rock hill (level 3) crowned with maples, the Lair's mouth (the drop
##   gate, `object.fatty-lair-mouth`) set in a notch of its south face over a paved terrace (level 1,
##   the forecourt: a campfire, crates, an energy flower); in front of it the old fort's field walls,
##   a maze of fieldstone walls with a loop and a dead end with pots, cut in two by a dry moat (a void
##   hole) that a bridge of two falling slabs crosses (one Roll; a fall puts the slime back on the
##   rim); stairs up from the maze's far end; the terrace's west rim is a ledge drop back to the maze's
##   door. A cracked wall in the hill's face (the Goo Bomb, Chapter 2) opens a separate cave room with the
##   grove's goo heart hidden in a chest.
## - **D4, the Verdant Gate:** the Lair's old mouth leaves Fatty's old camp clearing (a torn banner and
##   crates stay); an old Thorn Guard pen by the road, its gap shut by grey planks (the Heavy Roll), holds
##   the lake's goo heart (moved out of reach of deep water); the south-east field's way into D5 closes
##   with trees (the hill stands behind it).
## - **C4, the village:** a road from the forest path (the prologue's way in) to the town; the first bell
##   near the town's edge, on an islet in a little pond, with pots on its shore: rung by a thrown pot, it
##   unlocks a keeper's storehouse with its coffer and furnishings in a separate interior.
## - **C5, the lake:** the lake road on to D5 and a path to the camp; a copse and a lookout rock in the
##   south meadow, a bell on its top (a pot thrown from its foot rings it and raises a chest); the south
##   meadow's way east closed with trees. The expanded lake holds a ford islet, jetty and a charged-Roll island.
##
## Each chunk is read as it is on disk and changed only inside its own rects: paint there is replaced,
## the scenery and resource nodes there are taken out or moved; the tool's own nodes live under
## `Chapter1` (objects) and `Chapter1Hazards` (in D5, under every deck), replaced on every run; D5's
## `FattysLair` (the Lair's mouth) is the tool's too, and it owns D5's whole `elevation`, `cliffs` and
## forest layers and C5's `elevation`. Hand edits inside those rects are lost when it runs again.
## Packing drops the child overrides of an instance that is not editable, so every instance the file
## overrode a child of is marked editable before the save (`_keep_overrides`).
##
## Owner: world (Chapter 1's maps).

const SceneSave := preload("res://tools/lib/scene_save.gd")

const CHUNKS := "res://game/scenes/worlds/chunks/level-1-%s.tscn"
const OBJ := "res://game/scenes/objects/%s.tscn"
const KIT := "res://game/scenes/objects/dungeon/%s.tscn"
const PLACED_ENEMY := "res://game/scenes/encounters/placed-enemy.tscn"
const WORLD_AREA := "res://game/scripts/world_area.gd"
const HOLDER := "Chapter1"
const HAZARDS := "Chapter1Hazards"
const CELL := 64
const SHEET := 19
## terrain_tileset.tres sources.
const AMBERLEAF := 0
const FOREST_FLOOR := 4
const FOREST_MOSS := 5
const GRASS := 7
const SAND := 10
const WATER := 11
const DEEP_WATER := 3
const COBBLE := 19
## Each chunk's sheet-wrap frame offset (the frame of cell (x, y) is ((x, y) + offset) mod 19), as the
## chunks were cut from level-1.
const FRAME_OFFSET := {"c4": Vector2i(0, 0), "c5": Vector2i(0, 0), "d4": Vector2i(13, 0), "d5": Vector2i(13, 13)}
## forest_tileset.tres mixes (row 0).
const MIX_GREEN := Vector2i(2, 0)
const MIX_AUTUMN := Vector2i(4, 0)
const MIX_MIXED := Vector2i(0, 0)
## wall_tileset.tres: the stone style's auto tile.
const WALL_STONE := Vector2i(0, 0)
## elevation_tileset.tres: a front flight of stairs pointing south.
const STAIRS_SOUTH := Vector2i(0, 1)
const STAIRS_NORTH := Vector2i(4, 1)
## fence_tileset.tres: the wood column's all-neighbour tile (row 0) and its east arrow (row 3).
const FENCE_WOOD := Vector2i(0, 0)
const FENCE_WOOD_EAST := Vector2i(0, 3)
const FENCE_TILESET := "res://game/world/fences/fence_tileset.tres"
const FENCE_LAYER := "res://game/world/fences/fence_layer.gd"
## cliff_tileset.tres: the red-rock wall style.
const RED_ROCK := Vector2i(8, 0)
const CLIFF_TILESET := "res://game/world/elevation/cliffs/cliff_tileset.tres"
const CLIFF_LAYER := "res://game/world/elevation/cliffs/cliff_layer.gd"
const DECALS := "res://game/scenes/objects/interiors/mushroom-floor/interior-mushroom-floor-%s.tscn"
const ROCK_DECAL := "res://game/scenes/objects/rock-world-wall-decorative--field-%02d.tscn"
const PROP_LAYERS: PackedStringArray = ["old-props", "large-props", "cell-props", "details"]

var _dry := false
var _chunk := ""
var _root: Node2D
var _holder: Node2D
var _hazards: Node2D
var _editable: Array[Node] = []


func _initialize() -> void:
	var only := PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--dry":
			_dry = true
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
	var failed := 0
	for chunk: String in ["d5", "c5", "d4", "c4"]:
		if not only.is_empty() and not only.has(chunk):
			continue
		if _build(chunk) != OK:
			failed += 1
	if only.is_empty() and _caves() != OK:
		failed += 1
	quit(1 if failed > 0 else 0)


func _build(chunk: String) -> Error:
	_chunk = chunk
	_editable.clear()
	var path := CHUNKS % chunk
	var before := FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))
	_root = (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	for old_name: String in [HOLDER, HAZARDS]:
		var old := _root.get_node_or_null(old_name)
		if old != null:
			_root.remove_child(old)
			old.free()
	_hazards = null
	_holder = Node2D.new()
	_holder.name = HOLDER
	_holder.y_sort_enabled = true
	_root.add_child(_holder)
	_holder.owner = _root
	match chunk:
		"d5":
			_d5()
		"d4":
			_d4()
		"c4":
			_c4()
		"c5":
			_c5()
	for node in _editable:
		_root.set_editable_instance(node, true)
	_keep_overrides(before)
	if _dry:
		print("slimeshire: %s (dry)" % chunk)
		_root.free()
		return OK
	var err := SceneSave.save(_root, path, before)
	print("slimeshire: ", path, " ", error_string(err))
	_root.free()
	return err


## Marks editable every instance the file overrode a child of (a collectible's or a resource's ids,
## a goo heart's id): packing drops the child overrides of an instance that is not editable.
func _keep_overrides(before: String) -> void:
	var override := RegEx.create_from_string("\\[node name=\"[^\"]+\" parent=\"([^\"]+)\"([^\\]]*)\\]")
	for found in override.search_all(before):
		var rest := found.get_string(2)
		if rest.contains("type=") or rest.contains("instance="):
			continue
		var node := _root.get_node_or_null(found.get_string(1))
		while node != null and node != _root and node.scene_file_path.is_empty():
			node = node.get_parent()
		if node != null and node != _root:
			_root.set_editable_instance(node, true)


# --- D5: Fatty's Hollow ------------------------------------------------------------------------------

## The hill (level 3), the gate's notch (level 1), the forecourt (level 1), the
## moat (a void hole), cells.
const D5_HILL := Rect2i(13, 2, 16, 8)
const D5_NOTCH := Rect2i(20, 8, 4, 2)
const D5_FORECOURT := Rect2i(15, 10, 14, 6)
const D5_MOAT := Rect2i(15, 17, 2, 8)
## Where every fall from the moat returns the slime (units): the maze's top gap, cells (12-13, 17).
const MOAT_SAFE_SPOT := Vector2(832, 1110)
const D5_STAIRS: Array[Vector2i] = [Vector2i(27, 16), Vector2i(28, 16)]
## The maze: its wall rows and columns (inclusive bounds), the rooms between them two cells each.
const D5_MAZE := Rect2i(2, 16, 28, 10)
const D5_WALL_COLUMNS: Array[int] = [2, 5, 8, 11, 14, 17, 20, 23, 26, 29]
const D5_WALL_ROWS: Array[int] = [16, 19, 22, 25]
## The openings through the maze's walls (cells), by the rooms they join (W0..W3 west of the moat at
## x 3, 6, 9, 12; E0..E3 east of it at x 18, 21, 24, 27; R0..R2 at y 17, 20, 23).
const D5_OPENINGS: Array[Rect2i] = [
	Rect2i(12, 16, 2, 1), # the maze's door, from the plaza into W3R0
	Rect2i(11, 17, 1, 2), # W3R0 - W2R0
	Rect2i(8, 17, 1, 2), # W2R0 - W1R0 (the loop's long side)
	Rect2i(5, 17, 1, 2), # W1R0 - W0R0
	Rect2i(3, 19, 2, 1), # W0R0 - W0R1
	Rect2i(3, 22, 2, 1), # W0R1 - W0R2, the dead end with the pots
	Rect2i(5, 20, 1, 2), # W0R1 - W1R1
	Rect2i(9, 19, 2, 1), # W2R0 - W2R1 (the loop's short side)
	Rect2i(8, 20, 1, 2), # W2R1 - W1R1
	Rect2i(6, 22, 2, 1), # W1R1 - W1R2
	Rect2i(8, 23, 1, 2), # W1R2 - W2R2
	Rect2i(11, 23, 1, 2), # W2R2 - W3R2
	Rect2i(12, 22, 2, 1), # W3R2 - W3R1
	Rect2i(14, 20, 1, 2), # W3R1 - the slab bridge (the moat's west rim)
	Rect2i(17, 20, 1, 2), # the slab bridge - E0R1 (the east rim)
	Rect2i(18, 22, 2, 1), # E0R1 - E0R2
	Rect2i(20, 23, 1, 2), # E0R2 - E1R2
	Rect2i(23, 23, 1, 2), # E1R2 - E2R2
	Rect2i(24, 22, 2, 1), # E2R2 - E2R1
	Rect2i(23, 20, 1, 2), # E2R1 - E1R1
	Rect2i(21, 19, 2, 1), # E1R1 - E1R0
	Rect2i(20, 17, 1, 2), # E1R0 - E0R0, the dead end with the chest
	Rect2i(24, 19, 2, 1), # E2R1 - E2R0
	Rect2i(26, 17, 1, 2), # E2R0 - E3R0, under the stairs
	Rect2i(26, 23, 1, 2), # E2R2 - E3R2
	Rect2i(27, 22, 2, 1), # E3R2 - E3R1
	Rect2i(27, 19, 2, 1), # E3R1 - E3R0
]
## The mouth (the drop gate's floor line, the middle of the notch) and the crack's foot (cells).
const D5_MOUTH := Vector2(22.0, 12.0)
const D5_CRACK := Vector2(16.0, 12.0)


func _d5() -> void:
	var frame := FRAME_OFFSET["d5"]
	var ground := _layer("ground")
	# Ground: the hill's autumn soil (red rock under it), the paved notch,
	# forecourt and stairs; the old fort's field (the maze) in grass, so the rust hill stands out of it;
	# the roads of forest soil, the meadows round them in moss.
	_fill(ground, Rect2i(7, 0, 25, 16), FOREST_MOSS, frame)
	_fill(ground, D5_HILL, AMBERLEAF, frame)
	_fill(ground, Rect2i(D5_NOTCH.position.x, D5_NOTCH.position.y, D5_NOTCH.size.x, 2), COBBLE, frame)
	_fill(ground, D5_FORECOURT, COBBLE, frame)
	for cell in D5_STAIRS:
		_paint(ground, cell, COBBLE, frame)
	_fill(ground, Rect2i(0, 16, 32, 16), GRASS, frame)
	_fill(ground, Rect2i(0, 16, 2, 16), FOREST_MOSS, frame)
	_fill(ground, Rect2i(30, 16, 2, 16), FOREST_MOSS, frame)
	_fill(ground, Rect2i(0, 26, 32, 6), AMBERLEAF, frame)
	_fill(ground, D5_MOAT, FOREST_FLOOR, frame)
	# The roads: down from D4's clearing (x 5-6), in from C5 (rows 8-9), to the plaza before the maze.
	_fill(ground, Rect2i(5, 0, 2, 10), FOREST_FLOOR, frame)
	_fill(ground, Rect2i(0, 8, 11, 2), FOREST_FLOOR, frame)
	_fill(ground, Rect2i(9, 10, 2, 3), FOREST_FLOOR, frame)
	_fill(ground, Rect2i(8, 12, 7, 4), FOREST_FLOOR, frame)
	# The wall styles: the hill's red rock (also the moat's walls, which hang from the field's grass).
	var cliffs := _cliff_layer()
	cliffs.clear()
	for y in range(D5_HILL.position.y, D5_HILL.end.y):
		for x in range(D5_HILL.position.x, D5_HILL.end.x):
			cliffs.set_cell(Vector2i(x, y), 0, RED_ROCK)
	for y in range(D5_MOAT.position.y - 1, D5_MOAT.end.y + 1):
		for x in range(D5_MOAT.position.x - 1, D5_MOAT.end.x + 1):
			cliffs.set_cell(Vector2i(x, y), 0, RED_ROCK)
	# Elevation: owned whole.
	var elevation := _layer("elevation")
	elevation.clear()
	for y in range(D5_HILL.position.y, D5_HILL.end.y):
		for x in range(D5_HILL.position.x, D5_HILL.end.x):
			_level(elevation, Vector2i(x, y), 3)
	for rect: Rect2i in [D5_NOTCH, D5_FORECOURT]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				_level(elevation, Vector2i(x, y), 1)
	for y in range(D5_MOAT.position.y, D5_MOAT.end.y):
		for x in range(D5_MOAT.position.x, D5_MOAT.end.x):
			_level(elevation, Vector2i(x, y), -3)
	for cell in D5_STAIRS:
		elevation.set_cell(cell, 0, STAIRS_SOUTH)
	# Walls: the maze's fieldstone.
	var walls := _layer("walls")
	_clear_layer_rect(walls, Rect2i(0, 14, 32, 18))
	for y in range(D5_MAZE.position.y, D5_MAZE.end.y):
		for x in range(D5_MAZE.position.x, D5_MAZE.end.x):
			var on_line := D5_WALL_COLUMNS.has(x) or D5_WALL_ROWS.has(y)
			if not on_line:
				continue
			if y == 16 and x >= D5_FORECOURT.position.x:
				continue # the forecourt's own face is the wall there
			if D5_MOAT.has_point(Vector2i(x, y)) or (y == 16 and (x == 15 or x == 16)):
				continue
			var open := false
			for gap: Rect2i in D5_OPENINGS:
				if gap.has_point(Vector2i(x, y)):
					open = true
			if not open:
				walls.set_cell(Vector2i(x, y), 0, WALL_STONE)
	# Forest: owned whole (the old north rows, the east and south bands kept as bands).
	var forest := _layer("ForestLayer")
	forest.clear()
	for y in range(-1, 2):
		for x in range(-1, 33):
			if x == 5 or x == 6:
				continue
			forest.set_cell(Vector2i(x, y), 0, MIX_GREEN if x < 13 else MIX_AUTUMN)
	for cell: Vector2i in [Vector2i(8, 2), Vector2i(9, 2), Vector2i(11, 2), Vector2i(12, 2), Vector2i(8, 3),
			Vector2i(12, 3), Vector2i(9, 4), Vector2i(12, 5), Vector2i(1, 4), Vector2i(2, 5), Vector2i(0, 2)]:
		forest.set_cell(cell, 0, MIX_GREEN)
	# The hill's crown: maples and ginkgos on its back and east, over the closed former pocket, clear of the notch.
	for cell: Vector2i in [Vector2i(13, 2), Vector2i(14, 3), Vector2i(19, 2), Vector2i(18, 3), Vector2i(21, 2),
			Vector2i(23, 3), Vector2i(24, 2), Vector2i(26, 3), Vector2i(27, 2), Vector2i(28, 4), Vector2i(25, 5),
			Vector2i(27, 6), Vector2i(26, 8), Vector2i(28, 8), Vector2i(13, 6), Vector2i(20, 4), Vector2i(22, 5),
			Vector2i(24, 7), Vector2i(16, 2), Vector2i(15, 5), Vector2i(17, 4), Vector2i(16, 7)]:
		forest.set_cell(cell, 0, MIX_AUTUMN)
	for y in range(2, 34):
		for x in [30, 31, 32]:
			forest.set_cell(Vector2i(x, y), 0, MIX_GREEN if y < 16 else MIX_AUTUMN)
	for y in range(16, 34):
		for x in [-1, 0, 1]:
			forest.set_cell(Vector2i(x, y), 0, MIX_AUTUMN)
	for y in range(29, 34):
		for x in range(-1, 33):
			forest.set_cell(Vector2i(x, y), 0, MIX_AUTUMN)
	# Painted scenery out of the built ground (the west meadow keeps its flowers and stones).
	for layer_name: String in PROP_LAYERS:
		var layer := _root.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			continue
		_clear_props(layer, Rect2i(7, 0, 25, 32))
		_clear_props(layer, Rect2i(0, 16, 7, 16))
		_clear_props(layer, Rect2i(0, 7, 11, 3))
	# Placed scenery and resources inside the build: out (the rocks of the west meadow stay).
	_remove_children_in("Scenery", [Rect2(7, 0, 25, 32), Rect2(0, 16, 7, 16)])
	_remove_children_in("Nature", [Rect2(7, 0, 25, 32), Rect2(0, 16, 7, 16)], ["purple-berry"])
	_move("Nature/level-1-ancient-dark", _t(2.0, 6.6))
	_move("Nature/level-1-purple-berry-004", _t(3.4, 6.9))
	_move("Nature/level-1-purple-berry-005", _t(7.6, 14.7))
	_move("Nature/level-1-purple-berry-006", _t(2.6, 14.2))
	# The grove's goo heart is hidden in the separate hill cave's chest.
	_remove_node("Encounters/level-1-goo-heart-meadow-autumn-thicket")
	_d5_lair()
	_d5_maze_things()
	_d5_camps()


## The Lair's mouth, the forecourt's camp and the crack in the hill.
func _d5_lair() -> void:
	var old := _root.get_node_or_null("FattysLair")
	if old != null:
		_root.remove_child(old)
		old.free()
	var lair := Node2D.new()
	lair.name = "FattysLair"
	lair.y_sort_enabled = true
	_root.add_child(lair)
	_root.move_child(lair, _holder.get_index())
	lair.owner = _root
	_scene_under(lair, OBJ % "fatty-lair-mouth", "fatty-lair-mouth", _t(D5_MOUTH.x, D5_MOUTH.y))
	# The forecourt, the calm spot before the Lair: the worms' campfire, light things to throw, an
	# energy flower that grows back, a pot hiding a heart, the war banner, lamps.
	_scene(OBJ % "decoration-world-solid--campfire", "forecourt-campfire", _t(18.2, 14.3))
	_scene(OBJ % "decoration-world-solid--war-banner", "forecourt-banner", _t(19.2, 12.25))
	_scene(OBJ % "decoration-world-solid--lantern-post", "forecourt-lamp-west", _t(15.4, 15.6))
	_scene(OBJ % "decoration-world-solid--lantern-post", "forecourt-lamp-stairs", _t(26.4, 15.3))
	_liftable("forecourt-crate-a", _t(16.4, 15.4), "crate")
	_liftable("forecourt-crate-b", _t(17.2, 15.7), "crate")
	_liftable("forecourt-sack", _t(20.3, 15.5), "flour-sack")
	_pot("forecourt-pot", _t(15.9, 14.5), "heart")
	_scene(KIT % "energy-flower", "forecourt-flower", _t(25.2, 14.6))
	# The crack in the hill's face, west of the gate: a blast opens the door into the separate cave room.
	var foot := _t(D5_CRACK.x, D5_CRACK.y)
	_scene(OBJ % "cracked-wall", "hill-crack", foot, {
		"flag_id": "level-1.hollow-hill-crack",
		"door_id": HILL_CAVE_MOUTH,
		"target_area_id": HILL_CAVE,
		"target_door_id": HILL_CAVE_DOOR,
		"door_side": "north",
		"passage": Rect2(-32.0, -124.0, 64.0, 124.0),
		"passage_level": 1,
	})


## The moat's bridge, its void, the maze's prizes and lamps.
func _d5_maze_things() -> void:
	_hazards = Node2D.new()
	_hazards.name = HAZARDS
	_root.add_child(_hazards)
	_root.move_child(_hazards, _holder.get_index())
	_hazards.owner = _root
	# The void under the bridge: a fall puts the slime back on the rim it fell from (the nearer of
	# the bridge's two ends), and costs little (the first crossing teaches).
	var hazard := _scene_under(_hazards, KIT % "hazard", "moat-void", _t(D5_MOAT.position.x, D5_MOAT.position.y), {
		"kind": "void", "size": Vector2(D5_MOAT.size * CELL), "rim_level": 0, "draw_look": true,
		"top_fade_px": 192.0, "damage": 5.0})
	for spot: Vector2 in [Vector2(14.5, 21.0), Vector2(17.5, 21.0)]:
		var marker := Node2D.new()
		marker.name = "Return%d" % hazard.get_child_count()
		marker.position = _t(spot.x, spot.y) - (hazard as Node2D).position
		hazard.add_child(marker)
		marker.owner = _root
	# Every fall from the moat puts the slime back on one safe spot at the maze's top gap (owner,
	# 2026-10-18: one known spot, so a fall never misplaces it or leaves it stuck).
	var safe := Node2D.new()
	safe.name = "moat-safe-spot"
	safe.position = MOAT_SAFE_SPOT
	_hazards.add_child(safe)
	_hazards.move_child(safe, 0)
	safe.owner = _root
	hazard.set(&"fixed_return", hazard.get_path_to(safe))
	# The bridge: two slabs east-west, two lanes (one quick Roll from the rim's edge crosses it).
	for y in [20, 21]:
		for x in [15, 16]:
			_scene(KIT % "falling-slab", "moat-slab-%d-%d" % [x, y], _t(x, y), {"size": Vector2(CELL, CELL)})
	# The dead end (W0R2): two pots, one hiding a heart; the far dead end (E0R0): a chest.
	_pot("maze-pot-heart", _t(3.6, 24.4), "heart")
	_pot("maze-pot-coins", _t(4.5, 23.8), "coins")
	_chest("level-1-d5-maze-chest", _t(19.0, 18.3), {"coins": 30, "hp-potion": 1})
	# The field's floor: clover, flowers, leaves and pebbles in the rooms (none on the walls or the moat),
	# stepping stones from the plaza to the maze's door.
	_scatter_decals(Rect2i(3, 17, 26, 8), 46, ["clover-1", "clover-3", "clover-5", "flowers-daisy", "flowers-buttercup",
		"leaves-fallen", "leaf-big", "pebbles-1", "pebbles-2", "grass-tuft-1", "grass-tuft-2", "acorns-leaves",
		"mushrooms-brown", "twigs"], 5)
	_scatter_decals(Rect2i(14, 3, 14, 6), 14, ["leaves-fallen", "leaf-big", "acorns-leaves", "mushrooms-red",
		"twigs", "grass-moss-1"], 9)
	for i in 3:
		_scene(DECALS % ("stepping-stone-%d" % (i + 2)), "maze-door-stone-%d" % i, _t(12.6 + 0.5 * (i % 2), 14.0 + 0.7 * i))
	# Lamps at the maze's door and on the plaza.
	_scene(OBJ % "decoration-world-solid--lantern-post", "maze-door-lamp", _t(11.4, 15.6))
	_scene(OBJ % "decoration-world-solid--lantern-post", "junction-lamp", _t(7.4, 10.4))


## The camps: an archer alone in the west half's long row (seen down it from the maze's door), an
## archer by the far chest, the two brawlers under the stairs.
func _d5_camps() -> void:
	var areas := _root.get_node("Areas") as Node2D
	_wander_area(areas, "level-1-autumn-grove", Rect2(21, 17, 8, 5))
	_area_here("level-1-hollow-maze-west", Rect2(3, 17, 5, 2))
	_place_enemy("worm-archer-1", _t(4.0, 18.0), "level-1-hollow-maze-west")
	_place_enemy("worm-archer-2", _t(21.8, 18.0), "level-1-autumn-grove")
	_place_enemy("worm-brawler-1", _t(25.0, 21.0), "level-1-autumn-grove")
	_place_enemy("worm-brawler-2", _t(27.8, 20.8), "level-1-autumn-grove")


## Scatters `count` floor decals over the open cells of `rect` (cells), never on a wall, the moat, the
## stairs or `avoid`; seeded, so a rebuild puts them back where they were.
func _scatter_decals(rect: Rect2i, count: int, kinds: Array, seed: int, avoid: Rect2i = Rect2i()) -> void:
	var walls := _layer("walls")
	var elevation := _layer("elevation")
	var random := RandomNumberGenerator.new()
	random.seed = seed
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 20:
		tries += 1
		var at := Vector2(random.randf_range(rect.position.x, rect.end.x), random.randf_range(rect.position.y, rect.end.y))
		var cell := Vector2i(floori(at.x), floori(at.y))
		if walls.get_cell_source_id(cell) != -1 or avoid.has_point(cell):
			continue
		var below := Vector2i(cell.x, cell.y + 1)
		if walls.get_cell_source_id(below) != -1 and at.y - cell.y > 0.4:
			continue
		var data := elevation.get_cell_tile_data(cell)
		if data != null and (int(data.get_custom_data("elevation_level")) < 0 or str(data.get_custom_data("elevation_kind")) != ""):
			continue
		var kind: String = kinds[random.randi_range(0, kinds.size() - 1)]
		_scene(DECALS % kind, "decal-%s-%d" % [kind, placed], _t(at.x, at.y))
		placed += 1


# --- D4: the Verdant Gate ----------------------------------------------------------------------------

## The old Thorn Guard pen by the road, its gap shut by grey planks (a Heavy Roll smashes them): cells.
const D4_PEN := Rect2i(16, 3, 5, 4)


func _d4() -> void:
	var frame := FRAME_OFFSET["d4"]
	var ground := _layer("ground")
	for y in 32:
		for x in 3:
			var source := SAND
			if (y <= 26 and x <= 1) or (y == 27 and x == 0):
				source = DEEP_WATER
			if y == 9 and x == 2:
				source = FOREST_FLOOR
			_paint(ground, Vector2i(x, y), source, frame)
	var neighbor := _chunk_ground("d5")
	if neighbor != null:
		for x in 32:
			_paint(ground, Vector2i(x, 31), neighbor.get_cell_source_id(Vector2i(x, 0)), frame)
		var neighbor_world := neighbor.get_parent()
		neighbor_world.free()
	_clear_layer_rect(_layer("ForestLayer"), Rect2i(-2, -2, 5, 33))
	_remove_node("Nature/level-1-tree-035")
	_remove_node("Nature/level-1-tree-037")
	_river_bridge(Vector2(0, RIVER_BRIDGE_ROW * CELL))

	# The Lair's mouth left for D5's hill; a torn banner and two crates mark Fatty's old camp there.
	var lair := _root.get_node("FattysLair")
	var mouth := lair.get_node_or_null("fatty-lair-mouth")
	if mouth != null:
		lair.remove_child(mouth)
		mouth.free()
	_scene(OBJ % "decoration-world-solid--war-banner", "old-camp-banner", _t(3.6, 15.0))
	_liftable("old-camp-crate-a", _t(4.6, 15.9), "crate")
	_liftable("old-camp-crate-b", _t(4.4, 16.8), "crate")
	# The south-east field ends in trees (D5's hill stands behind); the bottom margin matches D5's
	# top rows, so the trees on the border look the same from both sides.
	var forest := _layer("ForestLayer")
	for y in range(30, 34):
		for x in range(20, 30):
			forest.set_cell(Vector2i(x, y), 0, MIX_AUTUMN if y >= 31 else MIX_GREEN)
	for y in range(31, 34):
		for x in range(-1, 33):
			if x == 5 or x == 6:
				continue
			if y == 31 and x < 20:
				continue
			forest.set_cell(Vector2i(x, y), 0, MIX_GREEN if x < 13 else MIX_AUTUMN)
	# The pen: fieldstone round a grass floor, the planks across its south gap.
	var walls := _layer("walls")
	_clear_layer_rect(walls, D4_PEN)
	for y in range(D4_PEN.position.y, D4_PEN.end.y):
		for x in range(D4_PEN.position.x, D4_PEN.end.x):
			var edge := x == D4_PEN.position.x or x == D4_PEN.end.x - 1 or y == D4_PEN.position.y or y == D4_PEN.end.y - 1
			var gap := y == D4_PEN.end.y - 1 and (x == 17 or x == 18)
			if edge and not gap:
				walls.set_cell(Vector2i(x, y), 0, WALL_STONE)
	_fill(_layer("ground"), Rect2i(17, 4, 3, 2), GRASS, frame)
	for layer_name: String in PROP_LAYERS:
		var layer := _root.get_node_or_null(layer_name) as TileMapLayer
		if layer != null:
			_clear_props(layer, D4_PEN)
	_scene(OBJ % "plank-barricade", "pen-planks", _t(18.0, 7.0), {"flag_id": "level-1.d4-pen-planks-smashed"})
	# The lake's goo heart (out of reach behind deep water before) waits in the pen.
	_heart_chest("meadow-lakeside", _t(18.5, 4.9))
	_remove_node("Encounters/level-1-goo-heart-cliff-secret")
	_remove_node("Encounters/level-1-goo-heart-meadow-lakeside")
	_heart_chest("meadow-cliff-secret", _t(29.2, 22.6))


# --- C4: the village ---------------------------------------------------------------------------------

## The plateau south of the town (level 1, its cells): from the west edge to the river, from the
## town's old south fence line to the south face over the lake (the wall in row 30, its foot in row
## 31); its south-east corner steps back where the river turns.
const C4_TOP: Array[Rect2i] = [Rect2i(0, 18, 30, 9), Rect2i(0, 27, 29, 1), Rect2i(0, 28, 27, 2)]
## Stairs: a back flight north into the town where the plaza's road comes down (the cells above the
## rim), a front flight south in the wall's row where the road goes on into C5 (its foot in row 31,
## inside C4, so the slime crosses into C5 at level 0).
const C4_STAIRS_NORTH: Array[Vector2i] = [Vector2i(10, 17), Vector2i(11, 17)]
const C4_STAIRS_SOUTH: Array[Vector2i] = [Vector2i(18, 30), Vector2i(19, 30)]
## The plateau's wood fence as level-1-c4.tscn paints it (hand-repainted 2026-10-17): the north
## rim's row of east arrows (cols 0-28, open over the north stairs: an arrow run that joins only
## along the row), and all-neighbour tiles down the east rim, round the south-east corner and along
## the south rim (open over the south stairs). The west rim (the map's edge) is not fenced.
const C4_FENCE_ARROW_ROW := 18
const C4_FENCE_ARROW_END := 28
const C4_FENCE_ALL: Array[Rect2i] = [Rect2i(29, 18, 1, 9), Rect2i(26, 27, 3, 1), Rect2i(26, 28, 1, 1),
		Rect2i(0, 29, 18, 1), Rect2i(20, 29, 7, 1)]
## Two lone east arrows on the river bank, either side of the town bridge's deck (row 9).
const C4_FENCE_BRIDGE: Array[Vector2i] = [Vector2i(29, 8), Vector2i(29, 10)]
## The river on the C4/D4 border: C4's last two columns (D4 the first two) from the top to row 26,
## then it turns south-west into C5 (C4 cols 27-30 from row 28).
const C4_RIVER_X := 30
## The keeper's storehouse replaces the old exposed watch-post enclosure.
const C4_POST := Rect2i(1, 20, 6, 4)
## The bell's pond on the plateau and its islet.
const C4_POND := Rect2i(7, 26, 3, 3)
const C4_ISLET := Vector2i(8, 27)
## The town road's bridge over the river, half in C4 and half in D4 (its middle on the border): the
## deck's row.
const RIVER_BRIDGE_ROW := 9


func _c4() -> void:
	var frame := FRAME_OFFSET["c4"]
	var ground := _layer("ground")
	# The old river (cols 27-28) and its banks become the town's ground; the river runs on the border.
	for y in 18:
		for x in range(26, 32):
			var source := GRASS
			if x == 29:
				source = SAND
			elif x >= C4_RIVER_X:
				source = DEEP_WATER
			if y == RIVER_BRIDGE_ROW and x <= 29:
				source = FOREST_FLOOR
			_paint(ground, Vector2i(x, y), source, frame)
	# The plateau's east part (the old river and its banks) is meadow; the river beside it and its turn.
	for y in range(18, 30):
		for x in range(25, 32):
			var cell := Vector2i(x, y)
			if _c4_top(cell):
				if x >= 26 or ground.get_cell_source_id(cell) in [WATER, DEEP_WATER, SAND]:
					_paint(ground, cell, GRASS, frame)
			else:
				_paint(ground, cell, _c4_river_at(cell), frame)
	# Old water on the plateau's top (the old pond) is meadow again; the new pond and its islet.
	for rect: Rect2i in C4_TOP:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)
				if ground.get_cell_source_id(cell) in [WATER, DEEP_WATER] and not C4_POND.has_point(cell):
					_paint(ground, cell, FOREST_MOSS, frame)
	_fill(ground, C4_POND, DEEP_WATER, frame)
	_paint(ground, C4_ISLET, GRASS, frame)
	# The road on the top to the south stairs.
	_fill(ground, Rect2i(18, 27, 2, 3), FOREST_FLOOR, frame)
	# The wall's row and its foot: the lake, the river road and the river, as C5's first row (the
	# grounds meet the border the same way on both sides).
	var seam := _c5_first_row()
	for x in 32:
		_paint(ground, Vector2i(x, 31), seam[x], frame)
		_paint(ground, Vector2i(x, 30), seam[x] if x < 31 else SAND, frame)
	# Elevation: the plateau (level 1) and its two flights; the town's own rows above stay.
	var elevation := _layer("elevation")
	_clear_layer_rect(elevation, Rect2i(-1, 17, 34, 16))
	for rect: Rect2i in C4_TOP:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				_level(elevation, Vector2i(x, y), 1)
	for cell in C4_STAIRS_NORTH:
		elevation.set_cell(cell, 0, STAIRS_NORTH)
	for cell in C4_STAIRS_SOUTH:
		elevation.set_cell(cell, 0, STAIRS_SOUTH)
	# The plateau's fence (C4_FENCE_*): the north row of arrows, all-neighbour tiles elsewhere.
	var fences := _fence_layer()
	fences.clear()
	for x in range(0, C4_FENCE_ARROW_END + 1):
		var cell := Vector2i(x, C4_FENCE_ARROW_ROW)
		if not C4_STAIRS_NORTH.has(cell + Vector2i.UP):
			fences.set_cell(cell, 0, FENCE_WOOD_EAST)
	for rect: Rect2i in C4_FENCE_ALL:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				fences.set_cell(Vector2i(x, y), 0, FENCE_WOOD)
	for cell: Vector2i in C4_FENCE_BRIDGE:
		fences.set_cell(cell, 0, FENCE_WOOD_EAST)
	# Painted scenery out of the river, the rim, the wall, its foot and the ponds.
	for layer_name: String in PROP_LAYERS:
		var layer := _root.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			continue
		_clear_props(layer, Rect2i(26, -1, 7, 34))
		_clear_props(layer, Rect2i(0, 29, 32, 4))
		_clear_props(layer, C4_POND.grow(1))
		_clear_props(layer, Rect2i(1, 27, 5, 4))
		_clear_props(layer, C4_POST)
	# Walls: the starter camp's south side goes (the rim's fence closes it), and anything over the river.
	var walls := _layer("walls")
	_clear_layer_rect(walls, Rect2i(-1, 28, 34, 6))
	_clear_layer_rect(walls, Rect2i(26, 17, 8, 15))
	_c4_post(walls)
	# Forest: the trees along the old east side stood where the river runs now.
	var forest := _layer("ForestLayer")
	_clear_layer_rect(forest, Rect2i(28, -3, 8, 40))
	_c4_nodes()
	_c4_things()


## True for a cell of the plateau's top.
static func _c4_top(cell: Vector2i) -> bool:
	for rect: Rect2i in C4_TOP:
		if rect.has_point(cell):
			return true
	return false


## The ground of a cell off the plateau in C4's rows 18-29 east of col 25: the river or its bank.
static func _c4_river_at(cell: Vector2i) -> int:
	if cell.y <= 26:
		return DEEP_WATER if cell.x >= C4_RIVER_X else GRASS
	if cell.y == 27:
		return DEEP_WATER if cell.x >= 29 else GRASS
	return SAND if cell.x == 31 else DEEP_WATER


## Clear the former enclosure; the storehouse's own facade contains its doorway.
func _c4_post(walls: TileMapLayer) -> void:
	_clear_layer_rect(walls, Rect2i(0, 19, 8, 7))


## Nodes out of the river, the rim and the wall; the town's old south fence goes (the plateau's back
## rim and its fence are the town's edge now).
func _c4_nodes() -> void:
	_remove_children_in("Scenery", [Rect2(28.5, -1, 5, 34), Rect2(0, 29.0, 32, 4)])
	var scenery := _root.get_node_or_null("Scenery")
	if scenery != null:
		for child: Node in scenery.get_children():
			var child_name := str(child.name)
			if child_name.begins_with("reinforced-fence") or child_name.begins_with("palisade-gap"):
				scenery.remove_child(child)
				child.free()
	_remove_children_in("Landmarks", [Rect2(24, 0, 9, 32)])
	_remove_children_in("Nature", [Rect2(28.5, -1, 5, 34)])
	for tree_name: String in ["level-1-tree-002", "level-1-tree-005", "level-1-tree-006"]:
		var tree := _root.get_node_or_null("Nature/" + tree_name)
		if tree != null:
			tree.get_parent().remove_child(tree)
			tree.free()
	for tree_name: String in ["level-1-tree-01", "level-1-tree-03"]:
		var tree := _root.get_node_or_null("Resources/Trees/" + tree_name)
		if tree != null:
			tree.get_parent().remove_child(tree)
			tree.free()
	# Trees out of the post, the ponds and the rim (the quests' tree-004 stays where it is).
	_move("Nature/level-1-tree-007", _t(0.9, 24.6))
	_move("Nature/level-1-tree-001", _t(5.2, 28.9))
	_move("Nature/level-1-tree-003", _t(1.0, 29.0))
	_move("Resources/Trees/level-1-tree-02", _t(9.4, 23.4))
	_move("Resources/Berries/level-1-purple-berry-02", _t(3.6, 28.7))


## The first bell, the keeper's storehouse, the bridge's west half, lamps.
func _c4_things() -> void:
	# The first bell (a thrown pot rings it), the pots on the shore, the door it opens, the chest.
	_scene(OBJ % "lash-bell-post", "first-bell", _t(C4_ISLET.x + 0.5, C4_ISLET.y + 0.85), {},
		{"LashBellScript": {"bell_id": "level-1-first-bell", "gate_id": "level-1-c4-watch-post"}})
	_liftable("bell-pot-a", _t(6.4, 26.5), "clay-pot")
	_liftable("bell-pot-b", _t(6.5, 28.6), "clay-pot")
	_liftable("bell-pot-c", _t(8.3, 29.4), "clay-pot")
	_scene(OBJ % "watchkeeper-hideout", "watchkeeper-hideout", _t(4.0, 24.0))
	# The town road's bridge: its west half (the same bridge stands in D4, its middle on the border).
	_river_bridge(Vector2(32.0 * CELL, RIVER_BRIDGE_ROW * CELL))
	# Lamps at the stairs' tops and feet, at the plateau's east end over the river.
	_scene(OBJ % "decoration-world-solid--lantern-post", "stairs-south-lamp", _t(17.4, 29.2))
	_scene(OBJ % "decoration-world-solid--lantern-post", "river-road-lamp", _t(20.6, 31.6))
	_scene(OBJ % "decoration-world-solid--lantern-post", "plateau-east-lamp", _t(28.6, 24.4))
	_scene(OBJ % "decoration-world-solid--lantern-post", "bridge-west-lamp", _t(28.6, 8.6))


## A half of the town road's bridge at `foot` (the deck's middle on the border, chunk units): the same
## footbridge in both chunks; each chunk's deck opens its own water cells.
func _river_bridge(foot: Vector2) -> void:
	var deck_middle := 77.0
	_scene(OBJ % "decoration-world-floor--wooden-footbridge", "river-bridge",
		Vector2(foot.x, foot.y + CELL * 0.5 + deck_middle))


# --- C5: the lake -----------------------------------------------------------------------------------

## The lake: C5's west half from the top to the south shore (row 29), the blossom tree's island and
## the west islet kept; the new island at its top-left (water between it and C4's south face), its
## rock (level 2, the crack in its face) and the falling planks' lane from it to the land by the
## south stairs; the islet in the south-west reached by a ford; the light shallows with a dark square.
const C5_LAKE := Rect2i(0, 0, 16, 29)
const C5_ISLAND := Rect2i(2, 1, 8, 7)
const C5_ISLAND_ROCK := Rect2i(3, 1, 4, 2)
const C5_PLANKS := Rect2i(10, 5, 6, 2)
const C5_ISLET := Rect2i(3, 21, 4, 4)
const C5_FORD := Rect2i(5, 25, 1, 4)
const C5_SHALLOWS := Rect2i(10, 15, 4, 4)
const C5_DARK_SQUARE := Rect2i(11, 16, 2, 2)
const C5_KEEP_ISLANDS := Rect2i(0, 10, 11, 5)
## The river's water on each of C5's first rows (first and last column): from C4's turn south-west
## into the lake; the main road crosses it on a bridge in row 2 (exactly the deck's four cells).
const C5_RIVER: Array[Vector2i] = [Vector2i(27, 30), Vector2i(27, 30), Vector2i(26, 29), Vector2i(25, 29),
	Vector2i(23, 28), Vector2i(21, 27), Vector2i(19, 25), Vector2i(16, 23), Vector2i(16, 21)]
const C5_ROAD_BRIDGE := Vector2(28.0, 2.0)
## The lookout rock in the south meadow (level 2): its top, cells.
const C5_ROCK := Rect2i(16, 21, 3, 2)


## C5's first row as this tool paints it (C4's wall row and foot copy it, so the border matches).
static func _c5_first_row() -> Array[int]:
	var row: Array[int] = []
	for x in 32:
		var source := GRASS
		if x < 16:
			source = DEEP_WATER
		elif x >= C5_RIVER[0].x and x <= C5_RIVER[0].y:
			source = DEEP_WATER
		elif x == 31:
			source = FOREST_FLOOR
		elif x == 18 or x == 19:
			source = FOREST_FLOOR
		elif x == 16 or x == C5_RIVER[0].x - 1:
			source = SAND
		row.append(source)
	return row


func _c5() -> void:
	var frame := FRAME_OFFSET["c5"]
	var ground := _layer("ground")
	var before := _ground_classes(ground)
	# The lake (the blossom tree's island and the west islet stay as they are), its south shore.
	for y in range(C5_LAKE.position.y, C5_LAKE.end.y):
		for x in range(C5_LAKE.position.x, C5_LAKE.end.x):
			var cell := Vector2i(x, y)
			if C5_KEEP_ISLANDS.has_point(cell) and ground.get_cell_source_id(cell) == FOREST_MOSS:
				continue
			_paint(ground, cell, DEEP_WATER, frame)
	_fill(ground, Rect2i(0, 29, 16, 1), SAND, frame)
	_fill(ground, Rect2i(0, 30, 16, 2), FOREST_MOSS, frame)
	_fill(ground, C5_ISLAND, GRASS, frame)
	_fill(ground, C5_ISLET, GRASS, frame)
	_fill(ground, C5_FORD, WATER, frame)
	_fill(ground, C5_SHALLOWS, WATER, frame)
	_fill(ground, C5_DARK_SQUARE, DEEP_WATER, frame)
	# The east shore, and the land north of the camp down to the river.
	for y in range(9, 29):
		var cell := Vector2i(16, y)
		_paint(ground, cell, SAND, frame)
		for x in range(17, 20):
			if ground.get_cell_source_id(Vector2i(x, y)) in [WATER, DEEP_WATER]:
				_paint(ground, Vector2i(x, y), GRASS, frame)
	_fill(ground, Rect2i(16, 0, 15, 9), GRASS, frame)
	for y in C5_RIVER.size():
		var span: Vector2i = C5_RIVER[y]
		_fill(ground, Rect2i(span.x, y, span.y - span.x + 1, 1), DEEP_WATER, frame)
	# The road: from the south stairs' foot east along the river to its bridge, then down the east
	# bank to the lake road (rows 8-9, on to D5) and the path to the camp.
	_fill(ground, Rect2i(18, 0, 2, 1), FOREST_FLOOR, frame)
	_fill(ground, Rect2i(18, 1, 8, 2), FOREST_FLOOR, frame)
	_fill(ground, Rect2i(30, 2, 1, 2), FOREST_FLOOR, frame)
	_fill(ground, Rect2i(29, 4, 2, 4), FOREST_FLOOR, frame)
	_fill(ground, Rect2i(28, 8, 4, 2), FOREST_FLOOR, frame)
	_fill(ground, Rect2i(23, 10, 6, 2), FOREST_FLOOR, frame)
	# Sand where meadow meets water (not on roads or the rocks' tops).
	_sand_shores(ground, Rect2i(0, 0, 31, 30), frame, [C5_ISLAND_ROCK, C5_ROCK])
	# The border with D5 is D5's own column (its pond across the border included), and the first row
	# is C4's last.
	var d5 := _chunk_ground("d5")
	if d5 != null:
		for y in 32:
			var source := d5.get_cell_source_id(Vector2i(0, y))
			if source != -1:
				_paint(ground, Vector2i(31, y), source, frame)
		var world := d5.get_parent()
		world.free()
	var seam := _c5_first_row()
	for x in 31:
		_paint(ground, Vector2i(x, 0), seam[x], frame)
	# Painted scenery out of every cell that turned from land to water or back, and off the rocks.
	var after := _ground_classes(ground)
	var changed: Array[Vector2i] = []
	for cell: Vector2i in after:
		if before.get(cell, -1) != after[cell]:
			changed.append(cell)
	for layer_name: String in PROP_LAYERS:
		var layer := _root.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			continue
		_clear_prop_cells(layer, changed)
		_clear_props(layer, C5_ROCK.grow(1))
		_clear_props(layer, C5_ISLAND)
		_clear_props(layer, Rect2i(16, 0, 16, 10))
		_clear_props(layer, C5_ISLET.grow(1))
	_clear_layer_rect(_layer("walls"), Rect2i(-1, -1, 34, 4))
	# Forest: none in the lake or on the river's land; the south meadow's east side closes with trees,
	# as D5's west does; a copse east of the lookout rock.
	var forest := _layer("ForestLayer")
	_clear_layer_rect(forest, Rect2i(-2, -2, 18, 32))
	_clear_layer_rect(forest, Rect2i(16, -2, 18, 11))
	for y in range(16, 34):
		for x in [30, 31, 32]:
			forest.set_cell(Vector2i(x, y), 0, MIX_AUTUMN if x >= 31 else MIX_GREEN)
	_clear_layer_rect(forest, Rect2i(14, 20, 16, 10))
	for cell: Vector2i in [Vector2i(21, 22), Vector2i(23, 23), Vector2i(22, 25), Vector2i(24, 26),
			Vector2i(26, 24), Vector2i(27, 27), Vector2i(25, 29), Vector2i(21, 28)]:
		forest.set_cell(cell, 0, MIX_GREEN)
	# Elevation: owned whole: the lookout rock and the island's rock (level 2 each, no way up).
	var elevation := _layer("elevation")
	elevation.clear()
	for rect: Rect2i in [C5_ROCK, C5_ISLAND_ROCK]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				_level(elevation, Vector2i(x, y), 2)
	_clear_dry_lake_props(ground)
	_c5_nodes()
	_c5_lookout()
	_c5_island()
	_c5_lake_life()
	# The goo heart that waited behind deep water moved to D4's pen (_d4).
	var heart := _root.get_node_or_null("Encounters/level-1-goo-heart-meadow-lakeside")
	if heart != null:
		heart.get_parent().remove_child(heart)
		heart.free()


## Placed scenery and resources out of the lake, the river and its land; the old river's bridge goes.
func _c5_nodes() -> void:
	var lake := [Rect2(0, 0, 16, 29.5)]
	for parent_name: String in ["Scenery", "Nature", "Landmarks"]:
		_remove_children_in(parent_name, lake, ["ancient-blossom", "footbridge-004"])
	_remove_children_in("Scenery", [Rect2(16, 0, 16, 9.6)])
	_remove_children_in("Nature", [Rect2(16, -1, 16, 8.4)], ["purple-berry"])
	_remove_children_in("Landmarks", [Rect2(16, 0, 16, 9)])
	_move("Nature/level-1-purple-berry-001", _t(17.4, 9.5))
	# The road's bridge over the river (row 2).
	_scene(OBJ % "decoration-world-floor--wooden-footbridge", "river-road-bridge",
		_t(C5_ROAD_BRIDGE.x, C5_ROAD_BRIDGE.y + 0.5) + Vector2(0.0, 77.0))
	_scene(OBJ % "decoration-world-solid--lantern-post", "river-road-bridge-lamp", _t(31.0, 3.6))
	_scene(OBJ % "decoration-world-solid--lantern-post", "lake-jetty-lamp", _t(16.7, 20.4))


## The lookout rock by the copse (level 2, no way up): a bell on its top, rung by a pot thrown from
## its foot, raises a chest beside it.
func _c5_lookout() -> void:
	var bell := _scene(OBJ % "lash-bell-post", "lookout-bell", _t(17.5, 21.85), {},
		{"LashBellScript": {"bell_id": "level-1-c5-lookout-bell"}})
	_liftable("lookout-pot-a", _t(17.2, 25.7), "clay-pot")
	_liftable("lookout-pot-b", _t(18.7, 26.3), "clay-pot")
	var chest := _scene(KIT % "dungeon-chest", "level-1-c5-lookout-chest", _t(20.3, 24.9), {}, {"ChestScript": {
		"map_id": "level-1-c5", "instance_id": "level-1-c5-lookout-chest", "initial_contents": {"coins": 25, "energy-potion": 1},
		"hidden": true}})
	bell.get_node("LashBellScript").connect(&"rung", Callable(chest.get_node("ChestScript"), &"trigger"), CONNECT_PERSIST)
	_scatter_decals(Rect2i(17, 20, 13, 9), 20, ["flowers-daisy", "flowers-buttercup", "flowers-pink", "clover-2",
		"clover-6", "grass-tuft-1", "grass-tuft-2", "mushrooms-red", "pebbles-mossy", "rock-mossy-small"], 13)


## The island at the lake's top-left: Gorge's worms keep it, a crack in its rock's face (the Goo
## Bomb, Chapter 2) opens a cave room (`lake-island-cave`), pots to throw; the falling planks to the
## land by the south stairs require a continuous charged Roll (no landing).
func _c5_island() -> void:
	var foot := _t(C5_ISLAND_ROCK.position.x + C5_ISLAND_ROCK.size.x * 0.5, C5_ISLAND_ROCK.end.y + 2.0)
	_scene(OBJ % "cracked-wall", "island-crack", foot, {
		"flag_id": "level-1.lake-island-crack",
		"passage": Rect2(-32.0, -124.0, 64.0, 124.0),
		"passage_level": 0,
		"door_id": LAKE_CAVE_MOUTH,
		"target_area_id": LAKE_CAVE,
		"target_door_id": LAKE_CAVE_DOOR,
		"door_side": "north",
	})
	_area_here("level-1-lake-island", Rect2(2.2, 5.0, 7.6, 2.8))
	_place_enemy("worm-swordsman-1", _t(3.6, 6.4), "level-1-lake-island")
	_place_enemy("worm-swordsman-2", _t(8.2, 6.2), "level-1-lake-island")
	_area_here("level-1-lake-island-east", Rect2(7.1, 1.2, 2.7, 3.6))
	_place_enemy("worm-archer-1", _t(8.5, 2.8), "level-1-lake-island-east")
	_liftable("island-pot-a", _t(2.7, 5.6), "clay-pot")
	_liftable("island-pot-b", _t(6.9, 7.3), "clay-pot")
	_pot("island-pot-coins", _t(2.6, 2.4), "coins")
	for spot: Vector2 in [Vector2(2.5, 1.6), Vector2(9.3, 7.2), Vector2(4.4, 7.4)]:
		_scene(DECALS % "grass-tuft-2", "island-tuft-%d" % roundi(spot.x * 10.0), _t(spot.x, spot.y))

	_hazards = Node2D.new()
	_hazards.name = HAZARDS
	_root.add_child(_hazards)
	_root.move_child(_hazards, _holder.get_index())
	_hazards.owner = _root
	var hazard := _scene_under(_hazards, KIT % "hazard", "island-water", _t(10, 5), {
		"kind": "water", "size": Vector2(6 * CELL, 2 * CELL)})
	for bank: Vector2 in [Vector2(9.4, 6.0), Vector2(16.6, 6.0)]:
		var marker := Node2D.new()
		marker.name = "Return%d" % hazard.get_child_count()
		marker.position = _t(bank.x, bank.y) - hazard.position
		hazard.add_child(marker)
		marker.owner = _root
	for y in range(5, 7):
		for x in range(10, 16):
			_scene(KIT % "falling-plank", "island-plank-%d-%d" % [x, y], _t(x, y), {
				"size": Vector2(CELL, CELL), "east_west": true})



## The lake's other things: an islet in the south-west with a chest and pots (a ford of shallows from
## the south shore), the fishing jetty off the east shore, the shallows with a dark square in them (a
## Swim secret, later) and a glint over it, lily pads, reeds, fish and rocks.
func _c5_lake_life() -> void:
	_chest("level-1-c5-islet-chest", _t(4.9, 21.9), {"coins": 15, "energy-potion": 1})
	_pot("islet-pot-heart", _t(3.6, 23.9), "heart")
	_pot("islet-pot-coins", _t(6.4, 24.2), "coins")
	for spot: Vector2 in [Vector2(3.5, 21.6), Vector2(6.3, 22.6), Vector2(4.8, 24.6)]:
		_scene(DECALS % "flowers-mixed", "islet-flowers-%d" % roundi(spot.x * 10.0), _t(spot.x, spot.y))
	# The jetty: a footbridge off the east shore into the lake (its deck opens the water under it).
	_scene(OBJ % "decoration-world-floor--wooden-footbridge", "lake-jetty", Vector2(14.0 * CELL, 20.5 * CELL + 77.0))
	_liftable("jetty-crate", _t(12.5, 20.6), "crate")
	# The dark square under the shallows: the Swim skin's secret, later; a glint over it seen from
	# the jetty's end.
	_scene(KIT % "prize-glint", "shallows-glint", _t(12.0, 17.0), {"phase": 0.4})
	var swim := _kit_marker("lake-dark-square", _t(12.0, 17.0))
	swim.set_meta(&"contents", "the Swim skin's secret under the dark square in the shallows (after Release 1)")
	var life := [
		["lilypad-pink", 1.5, 9.0], ["lilypad-white", 12.5, 8.6], ["lilypad-single", 14.3, 12.0],
		["lilypad-small", 2.4, 17.6], ["lilypad-pink", 8.2, 19.6], ["lilypad-white", 13.6, 24.6],
		["lilypad-single", 1.2, 26.8], ["lilypad-small", 9.6, 27.5], ["lilypad-single", 11.8, 2.4],
		["lilypad-pink", 14.7, 3.6], ["lilypad-white", 9.0, 23.2], ["lilypad-small", 13.2, 14.4],
		["frog-lilypad", 10.8, 9.6], ["frog-lilypad", 7.6, 26.2],
		["reeds-cattails", 15.4, 10.6], ["reeds-reeds", 15.5, 15.4], ["reeds-rushes", 15.4, 27.8],
		["reeds-sedge", 0.6, 28.5], ["reeds-cattails", 2.6, 28.6], ["reeds-reeds", 11.2, 28.6],
		["reeds-rushes", 1.6, 4.6], ["reeds-cattails", 10.3, 1.8], ["reeds-reeds", 2.5, 24.6],
		["reeds-sedge", 7.4, 21.6], ["reeds-rushes", 15.6, 7.4], ["reeds-sedge", 13.8, 0.6],
		["fish-koi-lane", 8.0, 9.2], ["fish-carp-oval", 3.5, 16.2], ["fish-perch-lane", 11.8, 25.6],
		["fish-minnow-oval", 13.5, 6.6], ["deep-fish-shadow-lane", 6.6, 18.6], ["deep-fish-shadow-oval", 10.2, 22.8],
		["fish-minnow-lane", 22.0, 6.0], ["fish-perch-oval", 28.0, 1.2],
	]
	for entry: Array in life:
		var kind := str(entry[0])
		_scene(OBJ % ("water-life--" + kind), "lake-%s-%d" % [kind, roundi(float(entry[1]) * 10.0)], _t(float(entry[1]), float(entry[2])))
	for entry: Array in [[3, 14.4, 9.2], [7, 0.8, 20.6], [12, 15.2, 22.4], [5, 7.2, 29.5], [9, 10.4, 7.6]]:
		_scene(ROCK_DECAL % int(entry[0]), "lake-rock-%d" % int(entry[0]), _t(float(entry[1]), float(entry[2])))


# --- the cave rooms ----------------------------------------------------------------------------------

## The two cave rooms behind the cracked walls (interior worlds this tool writes whole): the island's
## (`lake-island-cave`, chests, pots, the spot for a secret placed later) and Fatty's Hollow's hill's
## (`hollow-hill-cave`, the grove's goo heart). A mass of rock (level 2) with one room carved out at
## level 0 and a gap through its south band to the door.
const LAKE_CAVE := "lake-island-cave"
const LAKE_CAVE_DOOR := "lake-island-cave-door"
const LAKE_CAVE_MOUTH := "lake-island-cave-mouth"
const HILL_CAVE := "hollow-hill-cave"
const HILL_CAVE_DOOR := "hollow-hill-cave-door"
const HILL_CAVE_MOUTH := "hollow-hill-cave-mouth"
const CAVE_PATH := "res://game/scenes/worlds/%s.tscn"
const CAVE_SIZE := Vector2i(16, 13)
const CAVE_ROOM := Rect2i(1, 2, 14, 9)
const CAVE_GAP := Rect2i(7, 11, 2, 2)
const CAVERN := 1
## cliff_tileset.tres: the cave rock style.
const CAVE_ROCK := Vector2i(3, 0)
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const DOOR := "res://game/scripts/door.gd"


func _caves() -> Error:
	var failed := 0
	if _cave(LAKE_CAVE, "level-1-c5", LAKE_CAVE_DOOR, LAKE_CAVE_MOUTH, CAVE_ROCK) != OK:
		failed += 1
	if _cave(HILL_CAVE, "level-1-d5", HILL_CAVE_DOOR, HILL_CAVE_MOUTH, RED_ROCK) != OK:
		failed += 1
	return FAILED if failed > 0 else OK


func _cave(map_id: String, outside: String, door_id: String, mouth_id: String, style: Vector2i) -> Error:
	_chunk = map_id
	_editable.clear()
	var path := CAVE_PATH % map_id
	var before := FileAccess.get_file_as_string(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else ""
	_root = Node2D.new()
	_root.name = map_id
	_root.y_sort_enabled = true
	var room := func(cell: Vector2i) -> bool: return CAVE_ROOM.has_point(cell) or CAVE_GAP.has_point(cell)
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN_TILESET)
	var elevation := TileMapLayer.new()
	elevation.name = "elevation"
	elevation.z_index = -1
	elevation.tile_set = load(ELEVATION_TILESET)
	var cliffs := TileMapLayer.new()
	cliffs.name = "cliffs"
	cliffs.tile_set = load(CLIFF_TILESET)
	for y in CAVE_SIZE.y:
		for x in CAVE_SIZE.x:
			var cell := Vector2i(x, y)
			var open: bool = room.call(cell)
			ground.set_cell(cell, CAVERN if open else FOREST_FLOOR, Vector2i(x % SHEET, y % SHEET))
			if not open:
				_level(elevation, cell, 2)
				cliffs.set_cell(cell, 0, style)
	ground.set_meta(&"columns", CAVE_SIZE.x)
	ground.set_meta(&"rows", CAVE_SIZE.y)
	ground.set_script(load(WORLD_GROUND))
	elevation.set_script(load(ELEVATION_LAYER))
	cliffs.set_script(load(CLIFF_LAYER))
	for layer: Node in [ground, elevation, cliffs]:
		_root.add_child(layer)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	definition.set(&"map_id", map_id)
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", CAVE_SIZE.x)
	definition.set(&"rows", CAVE_SIZE.y)
	definition.set(&"camera_mode", "follow")
	var spawn := _t(8.0, 9.6)
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": roundi(spawn.x), "y": roundi(spawn.y)}, "entries": {}}})
	_root.add_child(definition)
	var spawn_marker := Node2D.new()
	spawn_marker.name = "player-spawn"
	spawn_marker.position = spawn
	_root.add_child(spawn_marker)
	# The way out: the gap's south end, back to the crack it was entered by.
	var door := Node2D.new()
	door.name = door_id
	door.position = Vector2(8.0 * CELL, CAVE_SIZE.y * CELL - 24.0)
	var door_script := Node.new()
	door_script.name = "DoorScript"
	door_script.set_script(load(DOOR))
	door_script.set(&"map_id", map_id)
	door_script.set(&"door_id", door_id)
	door_script.set(&"target_area_id", outside)
	door_script.set(&"target_door_id", mouth_id)
	door_script.set(&"side", "south")
	door_script.set(&"kind", "opening")
	door_script.set(&"trigger_rect", Rect2(-64, -24, 128, 48))
	door.add_child(door_script)
	_root.add_child(door)
	_holder = Node2D.new()
	_holder.name = "Cave"
	_holder.y_sort_enabled = true
	_root.add_child(_holder)
	if map_id == LAKE_CAVE:
		_lake_cave_things()
	else:
		_hill_cave_things()
	_own_all(_root)
	for node in _editable:
		_root.set_editable_instance(node, true)
	if _dry:
		print("slimeshire: %s (dry)" % map_id)
		_root.free()
		return OK
	var err := SceneSave.save(_root, path, before)
	print("slimeshire: ", path, " ", error_string(err))
	_root.free()
	return err


## The island's cave: two chests (coins; a tonic), pots to throw, mushrooms, and the spot for the
## secret placed later (owner, 2026-10-17: "we will place a secret there later").
func _lake_cave_things() -> void:
	_cave_chest("lake-island-cave-chest-west", _t(3.5, 4.9), {"coins": 30})
	_cave_chest("lake-island-cave-chest-east", _t(12.5, 4.9), {"coins": 10, "hp-potion": 1})
	_pot("cave-pot-a", _t(2.2, 9.2), "coins")
	_pot("cave-pot-b", _t(2.9, 9.8), "heart")
	_pot("cave-pot-c", _t(13.2, 9.6), "energy")
	_pot("cave-pot-d", _t(13.9, 9.0), "random")
	_liftable("cave-rock-pot", _t(5.6, 7.6), "clay-pot")
	for entry: Array in [["mushrooms-glow", 1.8, 5.2], ["mushrooms-ring", 9.6, 8.6], ["pebbles-2", 6.4, 6.2],
			["mushrooms-glow", 14.0, 5.6], ["rock-mossy", 10.8, 4.6], ["pebbles-1", 4.6, 9.4]]:
		_scene(DECALS % str(entry[0]), "cave-%s-%d" % [entry[0], roundi(float(entry[1]) * 10.0)], _t(float(entry[1]), float(entry[2])))
	var secret := _kit_marker("cave-secret-spot", _t(8.0, 4.8))
	secret.set_meta(&"contents", "a secret placed later (owner, 2026-10-17: \"we will place a secret there later\"); nothing here yet")


## The hill's cave: the grove's goo heart hidden in a chest, pots.
func _hill_cave_things() -> void:
	_heart_chest("meadow-autumn-thicket", _t(8.0, 5.2))
	_pot("cave-pot-a", _t(2.4, 9.4), "heart")
	_pot("cave-pot-b", _t(13.6, 9.2), "coins")
	_pot("cave-pot-c", _t(13.0, 9.8), "energy")
	for entry: Array in [["leaves-fallen", 3.0, 5.4], ["acorns-leaves", 12.4, 5.8], ["mushrooms-red", 5.4, 8.8],
			["leaf-big", 10.6, 9.0], ["twigs", 7.0, 7.2]]:
		_scene(DECALS % str(entry[0]), "cave-%s-%d" % [entry[0], roundi(float(entry[1]) * 10.0)], _t(float(entry[1]), float(entry[2])))



func _cave_chest(instance_id: String, at: Vector2, contents: Dictionary) -> Node2D:
	return _scene(OBJ % "chest-wooden", instance_id, at, {}, {"ChestScript": {
		"map_id": _chunk, "instance_id": instance_id, "initial_contents": contents}})


## A marker under `KitMarkers` for what nothing builds yet (metadata `contents` says what).
func _kit_marker(marker_name: String, at: Vector2) -> Node2D:
	var holder := _root.get_node_or_null("KitMarkers") as Node2D
	if holder == null:
		holder = Node2D.new()
		holder.name = "KitMarkers"
		_root.add_child(holder)
		holder.owner = _root
	var old := holder.get_node_or_null(marker_name)
	if old != null:
		holder.remove_child(old)
		old.free()
	var marker := Node2D.new()
	marker.name = marker_name
	marker.position = at
	marker.set_meta(&"kit", "chapter-1")
	holder.add_child(marker)
	marker.owner = _root
	return marker


## Sets `root` as the owner of every node under it not owned yet (a new scene built from nothing).
func _own_all(node: Node) -> void:
	for child: Node in node.get_children():
		if child.owner == null:
			child.owner = _root
		if child.scene_file_path.is_empty():
			_own_all(child)


# --- seams -------------------------------------------------------------------------------------------

## Each cell's water class (1 water or deep water, 0 land), for telling which cells changed.
static func _ground_classes(ground: TileMapLayer) -> Dictionary:
	var out := {}
	for cell: Vector2i in ground.get_used_cells():
		out[cell] = 1 if ground.get_cell_source_id(cell) in [WATER, DEEP_WATER] else 0
	return out


## Meadow cells of `rect` touching water (4 ways) become sand; roads, `skip` rects and cells off the
## map stay.
func _sand_shores(ground: TileMapLayer, rect: Rect2i, frame: Vector2i, skip: Array) -> void:
	var to_sand: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if ground.get_cell_source_id(cell) != GRASS:
				continue
			var skipped := false
			for other: Rect2i in skip:
				if other.has_point(cell):
					skipped = true
			if skipped:
				continue
			for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if ground.get_cell_source_id(cell + step) in [WATER, DEEP_WATER]:
					to_sand.append(cell)
					break
	for cell in to_sand:
		_paint(ground, cell, SAND, frame)


## Another chunk's ground layer as it is on disk (free its world with `.get_parent().free()`).
func _chunk_ground(chunk: String) -> TileMapLayer:
	var packed := load(CHUNKS % chunk) as PackedScene
	if packed == null:
		return null
	var world := packed.instantiate()
	return world.get_node_or_null("ground") as TileMapLayer


## Erases a prop layer's cells whose 64-unit cell is one of `cells`.
func _clear_prop_cells(layer: TileMapLayer, cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	var lookup := {}
	for cell in cells:
		lookup[cell] = true
	var size := layer.tile_set.tile_size if layer.tile_set != null else Vector2i(CELL, CELL)
	for cell: Vector2i in layer.get_used_cells():
		var grid := Vector2i(floori(float(cell.x * size.x) / CELL), floori(float(cell.y * size.y) / CELL))
		if lookup.has(grid):
			layer.erase_cell(cell)


## The chunk's `fences` layer, made when missing.
func _fence_layer() -> TileMapLayer:
	var layer := _root.get_node_or_null("fences") as TileMapLayer
	if layer == null:
		layer = TileMapLayer.new()
		layer.name = "fences"
		layer.z_index = -1
		layer.tile_set = load(FENCE_TILESET)
		layer.set_script(load(FENCE_LAYER))
		_root.add_child(layer)
		_root.move_child(layer, _root.get_node("elevation").get_index() + 1)
		layer.owner = _root
	return layer




# --- helpers ----------------------------------------------------------------------------------------

static func _t(x: float, y: float) -> Vector2:
	return Vector2(x * CELL, y * CELL)


func _layer(layer_name: String) -> TileMapLayer:
	return _root.get_node(layer_name) as TileMapLayer


func _paint(layer: TileMapLayer, cell: Vector2i, source: int, offset: Vector2i) -> void:
	layer.set_cell(cell, source, Vector2i(posmod(cell.x + offset.x, SHEET), posmod(cell.y + offset.y, SHEET)))


func _fill(layer: TileMapLayer, rect: Rect2i, source: int, offset: Vector2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x >= 0 and y >= 0 and x < 32 and y < 32:
				_paint(layer, Vector2i(x, y), source, offset)


## The chunk's `cliffs` layer (the wall styles), made when missing.
func _cliff_layer() -> TileMapLayer:
	var layer := _root.get_node_or_null("cliffs") as TileMapLayer
	if layer == null:
		layer = TileMapLayer.new()
		layer.name = "cliffs"
		layer.tile_set = load(CLIFF_TILESET)
		layer.set_script(load(CLIFF_LAYER))
		_root.add_child(layer)
		_root.move_child(layer, _root.get_node("elevation").get_index() + 1)
		layer.owner = _root
	return layer


func _level(layer: TileMapLayer, cell: Vector2i, lvl: int) -> void:
	layer.set_cell(cell, 0, Vector2i(lvl + 3 if lvl < 0 else lvl + 2, 0))


func _clear_layer_rect(layer: TileMapLayer, rect: Rect2i) -> void:
	for cell: Vector2i in layer.get_used_cells():
		if rect.has_point(cell):
			layer.erase_cell(cell)


## Erases a prop layer's cells whose 64-unit cell is in `rect` (the layers' grids differ).
func _clear_props(layer: TileMapLayer, rect: Rect2i) -> void:
	var size := layer.tile_set.tile_size if layer.tile_set != null else Vector2i(CELL, CELL)
	for cell: Vector2i in layer.get_used_cells():
		var grid := Vector2i(floori(float(cell.x * size.x) / CELL), floori(float(cell.y * size.y) / CELL))
		if rect.has_point(grid):
			layer.erase_cell(cell)


## A node's place in the chunk (its parents' offsets added).
func _chunk_position(node: Node2D) -> Vector2:
	var at := node.position
	var parent := node.get_parent()
	while parent != null and parent != _root and parent is Node2D:
		at += (parent as Node2D).position
		parent = parent.get_parent()
	return at


## Takes out the children of `parent_name` standing in any of `rects` (cells), except those whose
## name holds one of `keep`.
func _remove_children_in(parent_name: String, rects: Array, keep: Array = []) -> void:
	var parent := _root.get_node_or_null(parent_name)
	if parent == null:
		return
	for child: Node in parent.get_children():
		if not child is Node2D:
			continue
		var kept := false
		for word: String in keep:
			if str(child.name).contains(word):
				kept = true
		if kept:
			continue
		var at := _chunk_position(child as Node2D) / float(CELL)
		for rect: Rect2 in rects:
			if rect.has_point(at):
				parent.remove_child(child)
				child.free()
				break





## Moves an existing node to `at` (chunk units).
func _move(node_path: String, at: Vector2) -> void:
	var node := _root.get_node_or_null(node_path) as Node2D
	if node == null:
		push_warning("slimeshire %s: no %s to move" % [_chunk, node_path])
		return
	var parent_at := _chunk_position(node) - node.position
	node.position = at - parent_at


func _scene(path: String, node_name: String, at: Vector2, props: Dictionary = {}, child_props: Dictionary = {}) -> Node2D:
	return _scene_under(_holder, path, node_name, at, props, child_props)


func _scene_under(parent: Node, path: String, node_name: String, at: Vector2, props: Dictionary = {},
		child_props: Dictionary = {}) -> Node2D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("slimeshire %s: no scene %s" % [_chunk, path])
		return null
	var node := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	node.name = node_name
	node.position = at
	for key: String in props:
		node.set(key, props[key])
	for child_path: String in child_props:
		var child := node.get_node_or_null(child_path)
		if child == null:
			push_error("slimeshire %s: %s has no %s" % [_chunk, node_name, child_path])
			continue
		var values: Dictionary = child_props[child_path]
		for key: String in values:
			child.set(key, values[key])
	parent.add_child(node)
	node.owner = _root
	if not child_props.is_empty():
		_editable.append(node)
	return node


func _liftable(node_name: String, at: Vector2, kind: String) -> Node2D:
	return _scene(OBJ % "liftable", node_name, at, {}, {"LiftableScript": {"kind": kind}})


## A clay pot hiding `loot` (heart, energy, coins), back each time the chunk is built.
func _pot(node_name: String, at: Vector2, loot: String) -> Node2D:
	return _scene(KIT % "dungeon-pot", node_name, at, {}, {"PotLoot": {"loot": loot}})


func _chest(instance_id: String, at: Vector2, contents: Dictionary) -> Node2D:
	return _scene(OBJ % "chest-wooden", instance_id, at, {}, {"ChestScript": {
		"map_id": "level-1-" + _chunk, "instance_id": instance_id, "initial_contents": contents}})


## An existing enemy-wander area moved and resized (`rect` in cells), or a new one under `parent`.
func _wander_area(parent: Node2D, area_id: String, rect: Rect2) -> void:
	var area := parent.get_node_or_null(area_id) as Area2D
	if area == null:
		_area_here(area_id, rect)
		return
	area.position = (rect.get_center() * CELL) - _chunk_position(parent)
	var shape := area.get_node("wander-shape") as CollisionShape2D
	var box := RectangleShape2D.new()
	box.size = rect.size * CELL
	shape.shape = box
	shape.position = Vector2.ZERO


## A new enemy-wander area under the tool's holder.
func _area_here(area_id: String, rect: Rect2) -> void:
	var area := Area2D.new()
	area.name = area_id
	area.position = rect.get_center() * CELL
	area.collision_layer = 512
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	_holder.add_child(area)
	area.owner = _root
	var shape := CollisionShape2D.new()
	shape.name = "wander-shape"
	var box := RectangleShape2D.new()
	box.size = rect.size * CELL
	shape.shape = box
	area.add_child(shape)
	shape.owner = _root
	var script_node := Node.new()
	script_node.name = "world-area-script"
	script_node.set_script(load(WORLD_AREA))
	script_node.set(&"area_kind", "enemy-wander")
	script_node.set(&"area_id", area_id)
	script_node.set(&"area", area)
	script_node.set(&"shape", shape)
	area.add_child(script_node)
	script_node.owner = _root


## An existing placed enemy (under `Enemies`) moved into its camp, or a new one.
func _place_enemy(node_name: String, at: Vector2, area_id: String, enemy_type: String = "") -> void:
	var enemies := _root.get_node("Enemies") as Node2D
	var placed := enemies.get_node_or_null(node_name) as Node2D
	if placed == null:
		placed = (load(PLACED_ENEMY) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		placed.name = node_name
		placed.set(&"enemy_type", enemy_type if not enemy_type.is_empty() else node_name.left(node_name.rfind("-")))
		enemies.add_child(placed)
		placed.owner = _root
	placed.position = at - enemies.position
	placed.set(&"wander_area_id", area_id)


func _remove_node(path: String) -> void:
	var node := _root.get_node_or_null(path)
	if node != null:
		node.get_parent().remove_child(node)
		node.free()


func _heart_chest(heart_id: String, at: Vector2) -> void:
	_scene(OBJ % "chest-wooden", "heart-chest-" + heart_id, at, {}, {"ChestScript": {
		"map_id": str(_root.name), "instance_id": "heart-chest-" + heart_id,
		"initial_contents": {}, "goo_heart_id": heart_id}})


## Legacy flower and ground decals must not float where the enlarged lake now lies.
func _clear_dry_lake_props(ground: TileMapLayer) -> void:
	for layer_name: String in PROP_LAYERS:
		var layer := _root.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			continue
		for cell: Vector2i in layer.get_used_cells():
			var prop: Dictionary = layer.call(&"prop_at", cell)
			if prop.is_empty() or str(prop["scene"]).contains("water-life--"):
				continue
			var at: Vector2 = prop["at"]
			var grid := Vector2i(floori(at.x / CELL), floori(at.y / CELL))
			if ground.get_cell_source_id(grid) in [WATER, DEEP_WATER]:
				layer.erase_cell(cell)
