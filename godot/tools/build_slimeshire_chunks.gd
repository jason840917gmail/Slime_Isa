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
##   door. A cracked wall in the hill's face (the Goo Bomb, Chapter 2) opens a cave pocket with the
##   grove's goo heart, seen from the terrace.
## - **D4, the Verdant Gate:** the Lair's old mouth leaves Fatty's old camp clearing (a torn banner and
##   crates stay); an old Thorn Guard pen by the road, its gap shut by grey planks (the Heavy Roll), holds
##   the lake's goo heart (moved out of reach of deep water); the south-east field's way into D5 closes
##   with trees (the hill stands behind it).
## - **C4, the village:** a road from the forest path (the prologue's way in) to the town; the first bell
##   near the town's edge, on an islet in a little pond, with pots on its shore: rung by a thrown pot, it
##   opens the stone door of an old watch post, a chest inside.
## - **C5, the lake:** the lake road on to D5 and a path to the camp; a copse and a lookout rock in the
##   south meadow, a bell on its top (a pot thrown from its foot rings it and raises a chest); the south
##   meadow's way east closed with trees. The meadow's west half stays open (test_enemy_ranged's ground).
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
	for chunk: String in ["d5", "d4", "c4", "c5"]:
		if not only.is_empty() and not only.has(chunk):
			continue
		if _build(chunk) != OK:
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

## The hill (level 3), its cave pocket and the gate's notch (level 1), the forecourt (level 1), the
## moat (a void hole), cells.
const D5_HILL := Rect2i(13, 2, 16, 8)
const D5_POCKET := Rect2i(15, 4, 3, 4)
const D5_NOTCH := Rect2i(20, 8, 4, 2)
const D5_FORECOURT := Rect2i(15, 10, 14, 6)
const D5_MOAT := Rect2i(15, 17, 2, 8)
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
	# Ground: the hill's autumn soil (red rock under it), the pocket's dark earth, the paved notch,
	# forecourt and stairs; the old fort's field (the maze) in grass, so the rust hill stands out of it;
	# the roads of forest soil, the meadows round them in moss.
	_fill(ground, Rect2i(7, 0, 25, 16), FOREST_MOSS, frame)
	_fill(ground, D5_HILL, AMBERLEAF, frame)
	_fill(ground, D5_POCKET, FOREST_FLOOR, frame)
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
	for rect: Rect2i in [D5_POCKET, D5_NOTCH, D5_FORECOURT]:
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
	# The hill's crown: maples and ginkgos on its back and east, clear of the pocket and the notch.
	for cell: Vector2i in [Vector2i(13, 2), Vector2i(14, 3), Vector2i(19, 2), Vector2i(18, 3), Vector2i(21, 2),
			Vector2i(23, 3), Vector2i(24, 2), Vector2i(26, 3), Vector2i(27, 2), Vector2i(28, 4), Vector2i(25, 5),
			Vector2i(27, 6), Vector2i(26, 8), Vector2i(28, 8), Vector2i(13, 6), Vector2i(20, 4), Vector2i(22, 5),
			Vector2i(24, 7), Vector2i(16, 2)]:
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
	# The grove's goo heart moves into the hill's pocket, behind the crack.
	_move("Encounters/level-1-goo-heart-meadow-autumn-thicket", _t(16.5, 6.5))
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
	# The crack in the hill's face, west of the gate: a blast opens the passage into the pocket.
	var foot := _t(D5_CRACK.x, D5_CRACK.y)
	var top := float(D5_POCKET.position.y + 2) * CELL
	_scene(OBJ % "cracked-wall", "hill-crack", foot, {
		"flag_id": "level-1.hollow-hill-crack",
		"passage": Rect2(-64.0, top - foot.y, 128.0, foot.y - top + 8.0),
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
		"twigs", "grass-moss-1"], 9, D5_POCKET.grow(1))
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
	# The Lair's mouth left for D5's hill; a torn banner and two crates mark Fatty's old camp there.
	var lair := _root.get_node("FattysLair")
	var mouth := lair.get_node_or_null("fatty-lair-mouth")
	if mouth != null:
		lair.remove_child(mouth)
		mouth.free()
	_scene(OBJ % "decoration-world-solid--war-banner", "old-camp-banner", _t(2.6, 15.4))
	_liftable("old-camp-crate-a", _t(3.6, 15.9), "crate")
	_liftable("old-camp-crate-b", _t(1.6, 16.2), "crate")
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
	_goo_heart("level-1-goo-heart-meadow-lakeside", "meadow-lakeside", _t(18.5, 4.9))


# --- C4: the village ---------------------------------------------------------------------------------

## The old watch post by the town's edge (fieldstone round a floor), its stone door in the south wall.
const C4_POST := Rect2i(1, 20, 6, 4)
const C4_POST_DOOR := Vector2i(3, 23)
## The bell's pond and its islet.
const C4_POND := Rect2i(2, 28, 3, 3)
const C4_ISLET := Vector2i(3, 29)


func _c4() -> void:
	var frame := FRAME_OFFSET["c4"]
	var ground := _layer("ground")
	# The road from the forest path (the prologue's way in) to the town's south gate.
	_fill(ground, Rect2i(0, 26, 6, 2), FOREST_FLOOR, frame)
	for block: Vector2i in [Vector2i(5, 25), Vector2i(6, 24), Vector2i(7, 23), Vector2i(7, 22), Vector2i(8, 21),
			Vector2i(8, 20), Vector2i(9, 19), Vector2i(9, 18)]:
		_fill(ground, Rect2i(block, Vector2i(2, 2)), FOREST_FLOOR, frame)
	# The pond: deep water round the bell's islet.
	_fill(ground, C4_POND, DEEP_WATER, frame)
	_paint(ground, C4_ISLET, GRASS, frame)
	for layer_name: String in PROP_LAYERS:
		var layer := _root.get_node_or_null(layer_name) as TileMapLayer
		if layer != null:
			_clear_props(layer, C4_POND.grow(1))
			_clear_props(layer, C4_POST)
			_clear_props(layer, Rect2i(0, 26, 6, 2))
	# The watch post's walls (the old stub at x 5 goes into them).
	var walls := _layer("walls")
	_clear_layer_rect(walls, Rect2i(0, 19, 8, 7))
	for y in range(C4_POST.position.y, C4_POST.end.y):
		for x in range(C4_POST.position.x, C4_POST.end.x):
			var edge := x == C4_POST.position.x or x == C4_POST.end.x - 1 or y == C4_POST.position.y or y == C4_POST.end.y - 1
			if edge and Vector2i(x, y) != C4_POST_DOOR:
				walls.set_cell(Vector2i(x, y), 0, WALL_STONE)
	# Trees out of the post, the pond and the road (the quests' tree-004 stays where it is).
	_move("Nature/level-1-tree-007", _t(0.9, 24.6))
	_move("Nature/level-1-tree-005", _t(1.0, 29.2))
	_move("Nature/level-1-tree-002", _t(4.9, 31.3))
	_move("Nature/level-1-tree-001", _t(9.4, 25.8))
	_move("Resources/Trees/level-1-tree-02", _t(9.4, 23.4))
	for tree_name: String in ["level-1-tree-01", "level-1-tree-03"]:
		var tree := _root.get_node_or_null("Resources/Trees/" + tree_name)
		if tree != null:
			tree.get_parent().remove_child(tree)
			tree.free()
	# The first bell (a thrown pot rings it), the pots on the shore, the door it opens, the chest.
	_scene(OBJ % "lash-bell-post", "first-bell", _t(C4_ISLET.x + 0.5, C4_ISLET.y + 0.85), {},
		{"LashBellScript": {"bell_id": "level-1-first-bell", "gate_id": "level-1-c4-watch-post"}})
	_liftable("bell-pot-a", _t(5.6, 28.3), "clay-pot")
	_liftable("bell-pot-b", _t(5.9, 29.5), "clay-pot")
	_liftable("bell-pot-c", _t(1.5, 28.9), "clay-pot")
	_scene(OBJ % "latch-door", "watch-post-door", _t(C4_POST_DOOR.x + 0.5, C4_POST_DOOR.y + 1.0),
		{"scale": Vector2(0.55, 0.55)}, {"GateScript": {"gate_id": "level-1-c4-watch-post", "map_id": "level-1-c4",
		"locked_message": "Shut fast. The bell on the pond opens it."}})
	_chest("level-1-c4-watch-post-chest", _t(5.2, 21.6), {"coins": 20, "hp-potion": 1})


# --- C5: the lake -----------------------------------------------------------------------------------

## The lookout rock in the south meadow (level 2): its top, cells.
const C5_ROCK := Rect2i(16, 21, 3, 2)


func _c5() -> void:
	var frame := FRAME_OFFSET["c5"]
	var ground := _layer("ground")
	# The lake road: on from the east shore's track (x 28-29) to D5's road (rows 8-9), and a path
	# from it to the campfire.
	_fill(ground, Rect2i(28, 8, 4, 2), FOREST_FLOOR, frame)
	_fill(ground, Rect2i(23, 10, 6, 2), FOREST_FLOOR, frame)
	for layer_name: String in PROP_LAYERS:
		var layer := _root.get_node_or_null(layer_name) as TileMapLayer
		if layer != null:
			_clear_props(layer, Rect2i(28, 8, 4, 2))
			_clear_props(layer, Rect2i(23, 10, 6, 2))
	# The south meadow's east side closes with trees, as D5's west does.
	var forest := _layer("ForestLayer")
	for y in range(16, 34):
		for x in [30, 31, 32]:
			forest.set_cell(Vector2i(x, y), 0, MIX_AUTUMN if x >= 31 else MIX_GREEN)
	# The south meadow: a copse of oaks and birches east of the open field, and the field's flowers.
	_clear_layer_rect(forest, Rect2i(14, 20, 16, 10))
	for cell: Vector2i in [Vector2i(21, 22), Vector2i(23, 23), Vector2i(22, 25), Vector2i(24, 26),
			Vector2i(26, 24), Vector2i(27, 27), Vector2i(25, 29), Vector2i(21, 28)]:
		forest.set_cell(cell, 0, MIX_GREEN)
	# The lookout rock by the copse (level 2, no way up): a bell on its top, rung by a pot thrown from
	# its foot, raises a chest beside it.
	var elevation := _layer("elevation")
	elevation.clear()
	for y in range(C5_ROCK.position.y, C5_ROCK.end.y):
		for x in range(C5_ROCK.position.x, C5_ROCK.end.x):
			_level(elevation, Vector2i(x, y), 2)
	for layer_name: String in PROP_LAYERS:
		var layer := _root.get_node_or_null(layer_name) as TileMapLayer
		if layer != null:
			_clear_props(layer, C5_ROCK.grow(1))
	var bell := _scene(OBJ % "lash-bell-post", "lookout-bell", _t(17.5, 21.85), {},
		{"LashBellScript": {"bell_id": "level-1-c5-lookout-bell"}})
	_liftable("lookout-pot-a", _t(17.5, 26.1), "clay-pot")
	_liftable("lookout-pot-b", _t(15.7, 26.4), "clay-pot")
	var chest := _scene(KIT % "dungeon-chest", "level-1-c5-lookout-chest", _t(14.9, 25.3), {}, {"ChestScript": {
		"map_id": "level-1-c5", "instance_id": "level-1-c5-lookout-chest", "initial_contents": {"coins": 25, "energy-potion": 1},
		"hidden": true}})
	bell.get_node("LashBellScript").connect(&"rung", Callable(chest.get_node("ChestScript"), &"trigger"), CONNECT_PERSIST)
	_scatter_decals(Rect2i(15, 20, 15, 9), 22, ["flowers-daisy", "flowers-buttercup", "flowers-pink", "clover-2",
		"clover-6", "grass-tuft-1", "grass-tuft-2", "mushrooms-red", "pebbles-mossy", "rock-mossy-small"], 13)
	# The goo heart that waited behind deep water moved to D4's pen (_d4).
	var heart := _root.get_node_or_null("Encounters/level-1-goo-heart-meadow-lakeside")
	if heart != null:
		heart.get_parent().remove_child(heart)
		heart.free()


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


## A goo heart under the chunk's `Encounters` (its ids as level-1's hearts have them), or the one there
## moved to `at`.
func _goo_heart(node_name: String, heart_id: String, at: Vector2) -> void:
	var parent := _root.get_node("Encounters") as Node2D
	var heart := parent.get_node_or_null(node_name) as Node2D
	if heart == null:
		heart = _scene_under(parent, OBJ % "goo-heart", node_name, Vector2.ZERO, {}, {"GooHeartScript": {"heart_id": heart_id}})
		heart.set_meta(&"instance_id", node_name)
		heart.set_meta(&"persistence_key", "level-1." + node_name)
	_move("Encounters/" + node_name, at)


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
