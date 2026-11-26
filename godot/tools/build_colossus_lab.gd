extends SceneTree
## Builds the Colossus lab (docs/godot/DUNGEONS.md "The Crystal Colossus (roadmap 12.4)", "The Colossus
## lab"; step 2 of docs/design/2026-11-23-dungeons-2-3-rework.md): a dev world to fight the Crystal
## Colossus's plate fight (crystal_colossus.gd) before the Crystal Mine's arena was rebuilt (M15 is
## this lab's room, carried into the mine).
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_colossus_lab.gd [-- --force]
## Writes res://game/dev/bosses/colossus-lab.tscn (world.colossus-lab; launch it with
## `?map=colossus-lab` or `-- --map=colossus-lab`). It does not overwrite an existing lab (the scene to
## edit by hand) unless given --force.
##
## One big hall (24 x 20 cells, half as big again as his room in the mine each way; the owner,
## 2026-11-24: "a bigger scene"), painted as the one-scene Mine of the time was painted: crystal
## rock at level 3 round a cavern floor at level -1, so the north wall is four courses high, the wall
## he climbs. Its floor is 16 rows, all of it his arena; below its middle a nook in the south wall is
## outside the fight (the lobby: the slime starts there; walk back into it to start the fight over).
##
##   the north wall   roots up its face beside his two climb spots (climb_wall.gd `holds_at_top`)
##   the void dips    two cells wide down the west and east sides, from under the wall to the south
##                    wall (holes at level -3 with a `void` hazard each; the owner: "dips with void that
##                    damage you and set you back to the fight"): a fall costs `dungeon.void.damage` and
##                    puts the slime back where it stepped off; the fight goes on (they lie inside the
##                    arena, outside his floor: the arena's `floor_rect`)
##   two down lines   runaway cart lines tunnel to tunnel (ram_cart.gd `through`; the owner: "the cart
##                    [comes] from outside the scenes from a tunnel in the walls ... like a passing cart
##                    in a mine"), one under each climb spot: out of a tunnel in the north wall's foot,
##                    down the room (over the lower line) into a tunnel in the south wall; where he
##                    crashes off his wall (the arena's `crash_carts`). Each knock target stands beside
##                    its line, outward, a few cells below the wall (in reach of a slime off the roots
##                    while he lies), its rope up along the rails into the tunnel; pots by it. They
##                    replaced the upper line across the room under the wall (the owner, 2026-11-24:
##                    "the top ram make no sense you never use it remove it and put to verticals")
##   the lower line   across the arena's south half, rolling west out of the east wall over both dips
##                    into the west wall; its target by the east dip, pots by it
##   four braziers    one beside each down line, outward, below its target; two south of the lower line
##                    (their light's ring reaches over the rails)
##   the lobby        a nook in the south wall: the slime's start, a note; pots on the floor by it
##
## The hall is dark but not black (a dark room with its own darkness, no candles to light it for good):
## each lit brazier's pool of light is the ring that makes his plates brittle.

const SceneSave := preload("res://tools/lib/scene_save.gd")

const LAB_PATH := "res://game/dev/bosses/colossus-lab.tscn"
const MAP_ID := "colossus-lab"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CAMERA_ROOM := "res://game/world/camera_room.gd"
const DARK_ROOM := "res://game/world/darkness/dark_room.gd"
const COLOSSUS_ARENA := "res://game/crystal_mine/colossus_arena.gd"
const OBJECTS := "res://game/scenes/objects/"
const KIT := "res://game/scenes/objects/dungeon/"
const CELL := 64
const COLUMNS := 26
const ROWS := 24
const SHEET := 19
## terrain_tileset.tres sources: the cavern floor, the crystal rock's top.
const CAVERN := 1
const CRYSTAL := 2
## elevation_tileset.tres: level 3 (the rock) at (5, 0), level -1 (the floor) at (2, 0), level -3 (the
## dips) at (0, 0).
const ROCK_TILE := Vector2i(5, 0)
const FLOOR_TILE := Vector2i(2, 0)
const DIP_TILE := Vector2i(0, 0)
## The hall (cells): its first four rows are the north wall's face.
const HALL := Rect2i(1, 1, 24, 20)
const FACE_ROWS := 4
## The void dips' width (cells) down each side of the hall, under the face; their far wall (two
## levels) fades into the dark.
const DIP_CELLS := 2
const DIP_FADE_PX := 128.0
## The arena's rows: the whole floor under the face (the owner, 2026-11-24: "the fight reset every
## time i walk to the bottom of the scene": the lobby was the floor's last two rows). The lobby is a
## nook cut into the south wall below the floor's middle (cells), outside the arena: the slime starts
## there, and walking back into it starts the fight over.
const ARENA_ROWS := 16
const NOOK := Rect2i(12, 21, 2, 2)
## His two climb spots (old centres) stand this far above the wall's foot (the mine's: 2092 against
## 2112), this far either side of the floor's middle; the roots stand beside them (four, half a gap
## either side of each), and a down line runs under each.
const SPOT_ABOVE_FOOT := 20.0
const SPOT_GAP := 192.0
## The roots: their foot below the wall's foot, their top (the slime's centre at the top), their art.
const ROOTS_BELOW_FOOT := 20.0
const ROOTS_TOP := Vector2(0, -197)
const ROOTS_ART := Vector2(112, 250)
## The carts' lines run wall to wall: each cart is held this far inside its start wall's edge (its
## tunnel), its line ends as far inside the far wall; the lower line's place.
const TUNNEL_IN := 40.0
const LOWER_LINE_Y := 930.0
## The lower target, south of its line, in from the floor's east edge.
const TARGET_INSET := 58.0
const TARGET_BELOW_LINE := 180.0
## A down line's target: this far beside its line (outward) and below the wall's foot; its rope runs in
## to this far beside the rails, then up along them to this far below the wall's foot, then into the
## tunnel's mouth.
const DOWN_TARGET_SIDE := 100.0
const DOWN_TARGET_BELOW_FOOT := 200.0
const ROPE_BESIDE_RAILS := 44.0
const ROPE_TURN_BELOW_FOOT := 50.0
## The lower braziers: in from the floor's edges, south of their line; a down line's: beside it
## (outward) and below the wall's foot; their light's radius (the ring).
const BRAZIER_INSET := 320.0
const BRAZIER_BELOW_LINE := 70.0
const DOWN_BRAZIER_SIDE := 110.0
const DOWN_BRAZIER_BELOW_FOOT := 400.0
const RING_RADIUS := 150.0
## The pots by the nook: this far either side of the floor's middle (clear of the down lines' rails),
## this far above the floor's south edge.
const LOBBY_POTS_X: Array[float] = [-120.0, -60.0, 60.0, 120.0]
const LOBBY_POTS_ABOVE := 50.0
## How dark the hall is where no light reaches (dark_room.gd `darkness_override`).
const DARKNESS := 0.6

var _root: Node2D
var _objects: Node2D


func _initialize() -> void:
	if FileAccess.file_exists(LAB_PATH) and not OS.get_cmdline_user_args().has("--force"):
		print("colossus lab: %s exists; not overwritten (add -- --force to rebuild it)" % LAB_PATH)
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LAB_PATH.get_base_dir()))
	_root = Node2D.new()
	_root.name = MAP_ID
	_root.y_sort_enabled = true
	_paint()
	_place()
	for child in _root.get_children():
		_own(child)
	var before := FileAccess.get_file_as_string(LAB_PATH) if FileAccess.file_exists(LAB_PATH) else ""
	var err := SceneSave.save(_root, LAB_PATH, before)
	_root.free()
	print("colossus lab: ", "ok" if err == OK else "failed (%d)" % err)
	quit(0 if err == OK else 1)


func _own(node: Node) -> void:
	node.owner = _root
	if node.scene_file_path.is_empty():
		for child in node.get_children():
			_own(child)


# --- the paint ----------------------------------------------------------------------------------

## True for a cell of a void dip: the hall's outer columns, under the face.
static func _is_dip(cell: Vector2i) -> bool:
	if not HALL.has_point(cell) or cell.y < HALL.position.y + FACE_ROWS:
		return false
	return cell.x < HALL.position.x + DIP_CELLS or cell.x >= HALL.end.x - DIP_CELLS


func _paint() -> void:
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN_TILESET)
	var elevation := TileMapLayer.new()
	elevation.name = "elevation"
	elevation.z_index = -1
	elevation.tile_set = load(ELEVATION_TILESET)
	for y in ROWS:
		for x in COLUMNS:
			var cell := Vector2i(x, y)
			var floor := HALL.has_point(cell) or NOOK.has_point(cell)
			ground.set_cell(cell, CAVERN if floor else CRYSTAL, Vector2i(x % SHEET, y % SHEET))
			elevation.set_cell(cell, 0, DIP_TILE if _is_dip(cell) else (FLOOR_TILE if floor else ROCK_TILE))
	ground.set_meta(&"source_cell_count", COLUMNS * ROWS)
	ground.set_meta(&"columns", COLUMNS)
	ground.set_meta(&"rows", ROWS)
	ground.set_script(load(WORLD_GROUND))
	_root.add_child(ground)
	elevation.set_script(load(ELEVATION_LAYER))
	_root.add_child(elevation)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := _spawn()
	definition.set(&"map_id", MAP_ID)
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", COLUMNS)
	definition.set(&"rows", ROWS)
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": int(spawn.x), "y": int(spawn.y)}, "entries": {}}})
	_root.add_child(definition)


# --- the places ---------------------------------------------------------------------------------

## The wall's foot (world y): the first row of floor under the face.
static func _wall_foot() -> float:
	return float((HALL.position.y + FACE_ROWS) * CELL)


## The fight (world): the hall's width, dips and all, the floor's first ARENA_ROWS rows.
static func _arena_rect() -> Rect2:
	return Rect2(Vector2(HALL.position.x * CELL, _wall_foot()), Vector2(HALL.size.x * CELL, ARENA_ROWS * CELL))


## His floor (world): the arena between the dips.
static func _floor_rect() -> Rect2:
	var arena := _arena_rect()
	return arena.grow_individual(-DIP_CELLS * CELL, 0.0, -DIP_CELLS * CELL, 0.0)


## The slime's start: the nook's middle.
static func _spawn() -> Vector2:
	return (Vector2(NOOK.position) + Vector2(NOOK.size) * 0.5) * CELL


func _kit(scene: String, node_name: String, at: Vector2, props: Dictionary = {}, parent: Node = null) -> Node2D:
	var node := (load(KIT + scene + ".tscn") as PackedScene).instantiate() as Node2D
	node.name = node_name
	node.position = at
	for key: String in props:
		node.set(key, props[key])
	(parent if parent != null else _objects).add_child(node)
	return node


func _pot(node_name: String, at: Vector2, loot: String) -> void:
	var pot := _kit("dungeon-pot", node_name, at)
	_root.set_editable_instance(pot, true)
	pot.get_node("PotLoot").set(&"loot", loot)


func _target(node_name: String, at: Vector2, mechanism: String, rope: PackedVector2Array = PackedVector2Array()) -> void:
	var targets: Array[NodePath] = [NodePath("../" + mechanism)]
	_kit("knock-target", node_name, at, {"target_id": node_name, "targets": targets, "rope_points": rope})


func _brazier(node_name: String, at: Vector2) -> void:
	var brazier := (load(OBJECTS + "brazier.tscn") as PackedScene).instantiate() as Node2D
	brazier.name = node_name
	brazier.position = at
	brazier.set(&"burn_ms", -1.0)
	brazier.set(&"stomp_puts_out", true)
	brazier.set(&"light_radius", RING_RADIUS)
	brazier.set_meta(&"instance_id", "%s-%s" % [MAP_ID, node_name])
	brazier.set_meta(&"persistence_key", "%s.%s" % [MAP_ID, node_name])
	_objects.add_child(brazier)


func _roots(node_name: String, x: float) -> void:
	var roots := (load(OBJECTS + "climb-wall.tscn") as PackedScene).instantiate() as Node2D
	roots.name = node_name
	roots.position = Vector2(x, _wall_foot() + ROOTS_BELOW_FOOT)
	roots.set(&"top", ROOTS_TOP)
	roots.set(&"holds_at_top", true)
	roots.set(&"art_size", ROOTS_ART)
	roots.set_meta(&"instance_id", "%s-%s" % [MAP_ID, node_name])
	roots.set_meta(&"persistence_key", "%s.%s" % [MAP_ID, node_name])
	_objects.add_child(roots)


func _dip(node_name: String, column: int) -> void:
	var at := Vector2(column * CELL, _wall_foot())
	var rows := HALL.end.y - (HALL.position.y + FACE_ROWS)
	_kit("hazard", node_name, at, {"kind": "void", "size": Vector2(DIP_CELLS * CELL, rows * CELL), "top_fade_px": DIP_FADE_PX}, _root)


func _label(node_name: String, at: Vector2, text: String) -> void:
	var label := Label.new()
	label.name = node_name
	label.position = at
	label.size = Vector2(620, 60)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", 13)
	label.modulate = Color(1.0, 0.96, 0.84, 0.9)
	label.text = text
	_objects.add_child(label)


func _place() -> void:
	var rooms := Node2D.new()
	rooms.name = "CameraRooms"
	_root.add_child(rooms)
	var room := Node2D.new()
	room.set_script(load(CAMERA_ROOM))
	room.name = "hall"
	room.set(&"size", Vector2(COLUMNS * CELL, ROWS * CELL))
	rooms.add_child(room)
	var entry := Node2D.new()
	entry.name = "RoomEntry"
	entry.position = _spawn()
	room.add_child(entry)
	var dark := Node2D.new()
	dark.name = "dark-hall"
	dark.set_script(load(DARK_ROOM))
	dark.set(&"size", Vector2(COLUMNS * CELL, ROWS * CELL))
	dark.set(&"darkness_override", DARKNESS)
	# his braziers' circles are his brittle rings: they light only their own circle (dark_room.gd)
	dark.set(&"lifts_by_candles", false)
	_root.add_child(dark)
	# the void dips (above their decks in the tree, as every hazard: they have none)
	_dip("west-dip", HALL.position.x)
	_dip("east-dip", HALL.end.x - DIP_CELLS)
	_objects = Node2D.new()
	_objects.name = "Objects"
	_objects.y_sort_enabled = true
	_root.add_child(_objects)
	var spawn := _spawn()
	_kit("dungeon", "Dungeon", spawn + Vector2(0, 40), {"dungeon_id": MAP_ID, "display_name": "Colossus Lab",
		"entrance_marker": "dungeon-entrance", "resume_saves": false}, _root)
	var entrance := Node2D.new()
	entrance.name = "dungeon-entrance"
	entrance.position = spawn
	_root.add_child(entrance)
	var player_spawn := Node2D.new()
	player_spawn.name = "player-spawn"
	player_spawn.position = spawn
	_root.add_child(player_spawn)

	var arena_rect := _arena_rect()
	var floor := _floor_rect()
	var middle := floor.get_center().x
	# The wall: his two climb spots either side of the middle, the roots beside them.
	var spots := PackedVector2Array()
	for side in [-1.0, 1.0]:
		spots.append(Vector2(middle + side * SPOT_GAP, _wall_foot() - SPOT_ABOVE_FOOT))
	for i in 4:
		_roots("claw-roots-%d" % (i + 1), middle + (i - 1.5) * SPOT_GAP)
	# The lines, wall to wall: out of a tunnel, across the floor (over the dips), into the far wall's
	# tunnel. Each cart's node stands on the floor in its line's middle (a mechanism strikes on its
	# node's level: the floor's, not the wall's), its points out to the tunnels either side.
	var west_wall := float(HALL.position.x * CELL)
	var east_wall := float(HALL.end.x * CELL)
	var half := (east_wall - west_wall) * 0.5 + TUNNEL_IN
	var fires: Array[String] = []
	var crash_lines: Array[NodePath] = []
	# The down lines, one under each climb spot, rolling south: out of the north wall's foot, into the
	# south wall. His fall off the wall lands him across the one under him.
	var north := _wall_foot() - TUNNEL_IN
	var south := float(HALL.end.y * CELL) + TUNNEL_IN
	var down_middle := (north + south) * 0.5
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var way_name := "west" if i == 0 else "east"
		var x := middle + side * SPOT_GAP
		var cart_name := "%s-cart" % way_name
		_kit("ram-cart", cart_name, Vector2(x, down_middle), {"points": PackedVector2Array([Vector2(0, north - down_middle),
			Vector2(0, south - down_middle)]), "through": true, "buffer_stop": false, "cart_id": cart_name})
		crash_lines.append(NodePath("../" + cart_name))
		# its target beside it, outward, its rope in beside the rails and up along them into the tunnel
		var target_at := Vector2(x + side * DOWN_TARGET_SIDE, _wall_foot() + DOWN_TARGET_BELOW_FOOT)
		var beside := -side * (DOWN_TARGET_SIDE - ROPE_BESIDE_RAILS)
		_target("%s-target" % way_name, target_at, cart_name, PackedVector2Array([Vector2(beside, 0.0),
			Vector2(beside, ROPE_TURN_BELOW_FOOT - DOWN_TARGET_BELOW_FOOT)]))
		# its brazier beside it, below the target
		var brazier_name := "%s-brazier" % way_name
		_brazier(brazier_name, Vector2(x + side * DOWN_BRAZIER_SIDE, _wall_foot() + DOWN_BRAZIER_BELOW_FOOT))
		fires.append(brazier_name)
		# pots by the target, outward (off the rails and the line a throw at it takes from the side)
		_pot("%s-pot-1" % way_name, target_at + Vector2(side * 70.0, 60.0), "none")
		_pot("%s-pot-2" % way_name, target_at + Vector2(side * 20.0, 120.0), "none")
		_pot("%s-pot-3" % way_name, target_at + Vector2(side * 110.0, 140.0), "energy")
	# The lower line: across the arena's south half, rolling west; its target by the east dip.
	_kit("ram-cart", "lower-cart", Vector2(middle, LOWER_LINE_Y), {"points": PackedVector2Array([Vector2(half, 0), Vector2(-half, 0)]),
		"through": true, "buffer_stop": false, "cart_id": "lower-cart"})
	_target("lower-target", Vector2(floor.end.x - TARGET_INSET, LOWER_LINE_Y + TARGET_BELOW_LINE), "lower-cart")
	# The lower braziers: south of the lower line, in from the floor's edges.
	for i in 2:
		var brazier_name := "lower-brazier-%s" % ("west" if i == 0 else "east")
		var x := floor.position.x + BRAZIER_INSET if i == 0 else floor.end.x - BRAZIER_INSET
		_brazier(brazier_name, Vector2(x, LOWER_LINE_Y + BRAZIER_BELOW_LINE))
		fires.append(brazier_name)
	# Pots by the lower target and on the floor by the nook.
	var west := floor.position.x
	var east := floor.end.x
	_pot("lower-pot-1", Vector2(east - 170, LOWER_LINE_Y + 210), "none")
	_pot("lower-pot-2", Vector2(east - 120, LOWER_LINE_Y + 240), "heart")
	_pot("lower-pot-3", Vector2(east - 40, LOWER_LINE_Y + 90), "none")
	_pot("lower-pot-4", Vector2(east - 230, LOWER_LINE_Y + 170), "none")
	var lobby_loot: Array[String] = ["none", "none", "heart", "none"]
	for i in LOBBY_POTS_X.size():
		_pot("lobby-pot-%d" % (i + 1), Vector2(middle + LOBBY_POTS_X[i], arena_rect.end.y - LOBBY_POTS_ABOVE - (0.0 if i % 2 == 0 else 40.0)), lobby_loot[i])
	_label("lobby-note", Vector2(spawn.x + 80.0, arena_rect.end.y + 12), "Colossus lab (the crystal fight). Walk north to wake him; back into this nook to start over. His health is three crystals, one a phase: left shoulder, right shoulder, chest. Light a brazier with the Lantern (its flame flies in a line), bait him over the rails in its light, throw at that line's target: the cart bursts the glowing plate, and he kicks it back. Spear or throw at the bare crystal until it goes dark. Keep away and he leaps at you. When he rears and the floor cracks, climb the roots: the quake hurts all over the floor for 5 s. His stomps put braziers out only once all four burn and he is hurt, or 45 s after a brazier was last lit or put out. Both shoulders dark, he climbs: climb the roots and Spear his claws; on his back, the cart bursts his chest plate. The dips are void.")
	# His arena.
	var arena := Node2D.new()
	arena.name = "ColossusArena"
	arena.set_script(load(COLOSSUS_ARENA))
	arena.position = Vector2(middle, arena_rect.get_center().y + 30.0)
	arena.set(&"camp_id", MAP_ID)
	arena.set(&"boss_id", MAP_ID)
	arena.set(&"arena_rect", arena_rect)
	arena.set(&"floor_rect", floor)
	arena.set(&"post", Vector2(0, -40))
	arena.set(&"climb_spots", spots)
	arena.set(&"wall_rect", Rect2(Vector2(arena_rect.position.x, HALL.position.y * CELL), Vector2(arena_rect.size.x, FACE_ROWS * CELL + 40.0)))
	arena.set(&"refights", true)
	_objects.add_child(arena)
	var paths: Array[NodePath] = []
	for brazier_name: String in fires:
		paths.append(NodePath("../" + brazier_name))
	arena.set(&"braziers", paths)
	arena.set(&"crash_carts", crash_lines)
