extends SceneTree
## Builds the mechanism lab (docs/godot/DUNGEONS.md "Mechanisms: the knock target, the ram, the
## runaway cart"; step 1 of docs/design/2026-11-23-dungeons-2-3-rework.md): a dev world to try the
## knock target, the ram with its bricked arch and the runaway cart with its rail gate.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_mechanism_lab.gd [-- --force]
## Writes res://game/dev/mechanisms/mechanism-lab.tscn (world.mechanism-lab; launch it with
## `?map=mechanism-lab` or `-- --map=mechanism-lab`). It does not overwrite an existing lab (the
## scene to edit by hand) unless given --force.
##
## One hall of cave rock (the interior walls' `cave-rock` style: docs/godot/INTERIOR_WALLS.md), three
## screens wide (48 x 14 cells, a lane a screen), lit, flat, with a pocket room north of lane A
## behind the bricked arch (so the world is 48 x 20 cells):
##
##   Lane A  pots that grow back; a void pit with a knock target on its far side; a ram aimed north
##           at the bricked arch; a chest in the pocket behind the arch
##   Lane B  a ram across a pen of three enemies, its target on the pen's edge, pots
##   Lane C  a cart that stays where it ends (its target, a rail gate on its line, the line running
##           on to a buffer stop), and a cart that is hauled back, aimed across a pen of one enemy

const SceneSave := preload("res://tools/lib/scene_save.gd")

const LAB_PATH := "res://game/dev/mechanisms/mechanism-lab.tscn"
const MAP_ID := "mechanism-lab"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const WALL_TILESET := "res://game/world/interior/interior_wall_tileset.tres"
const WALL_LAYER := "res://game/world/interior/interior_wall_layer.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CAMERA_ROOM := "res://game/world/camera_room.gd"
const PLACED_ENEMY := "res://game/scenes/encounters/placed-enemy.tscn"
const KIT := "res://game/scenes/objects/dungeon/"
const CELL := 64
const COLUMNS := 48
const ROWS := 20
## The hall's top row (the pocket and solid rock lie above it) and a screen's size in cells.
const HALL_TOP := 6
const SCREEN := Vector2i(16, 14)
## terrain_tileset.tres: the cave floor (as the playground's cliff cave). The interior walls draw
## their own floor over it.
const FLOOR_SOURCE := 1
const SHEET := 19
## interior_wall_tileset.tres, the cave rock's column: the wall and the doorway.
const WALL_TILE := Vector2i(1, 0)
const DOORWAY_TILE := Vector2i(1, 1)
## The pocket behind the arch: its floor (cells), and the doorway's two columns.
const POCKET := Rect2i(7, 2, 4, 2)
const DOOR_COLUMNS: Array[int] = [8, 9]
## Lane A's pit (cells) and its hole level (elevation_tileset.tres: levels -3 ... -1 at (0 ... 2, 0)).
const PIT := Rect2i(3, 9, 3, 7)
const PIT_LEVEL := -2

var _root: Node2D
var _objects: Node2D


func _initialize() -> void:
	if FileAccess.file_exists(LAB_PATH) and not OS.get_cmdline_user_args().has("--force"):
		print("mechanism lab: %s exists; not overwritten (add -- --force to rebuild it)" % LAB_PATH)
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
	print("mechanism lab: ", "ok" if err == OK else "failed (%d)" % err)
	quit(0 if err == OK else 1)


func _own(node: Node) -> void:
	node.owner = _root
	if node.scene_file_path.is_empty():
		for child in node.get_children():
			_own(child)


# --- painting -----------------------------------------------------------------------------------

func _is_floor(cell: Vector2i) -> bool:
	if POCKET.has_point(cell):
		return true
	return cell.x >= 2 and cell.x < COLUMNS - 2 and cell.y >= HALL_TOP + 2 and cell.y < ROWS - 2


func _paint() -> void:
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN_TILESET)
	for y in ROWS:
		for x in COLUMNS:
			ground.set_cell(Vector2i(x, y), FLOOR_SOURCE, Vector2i(x % SHEET, y % SHEET))
	ground.set_meta(&"source_cell_count", COLUMNS * ROWS)
	ground.set_meta(&"columns", COLUMNS)
	ground.set_meta(&"rows", ROWS)
	ground.set_script(load(WORLD_GROUND))
	_root.add_child(ground)
	var elevation := TileMapLayer.new()
	elevation.name = "elevation"
	elevation.z_index = -1
	elevation.tile_set = load(ELEVATION_TILESET)
	for y in range(PIT.position.y, PIT.end.y):
		for x in range(PIT.position.x, PIT.end.x):
			elevation.set_cell(Vector2i(x, y), 0, Vector2i(PIT_LEVEL + 3, 0))
	elevation.set_script(load(ELEVATION_LAYER))
	_root.add_child(elevation)
	# The walls: everything that is not floor is rock, the doorway through the band between the
	# hall and the pocket painted in both rims (two cells along, two deep each).
	var walls := TileMapLayer.new()
	walls.name = "interior-walls"
	walls.y_sort_enabled = true
	walls.tile_set = load(WALL_TILESET)
	for y in ROWS:
		for x in COLUMNS:
			var cell := Vector2i(x, y)
			if _is_floor(cell):
				continue
			var doorway := x in DOOR_COLUMNS and y >= POCKET.end.y and y < HALL_TOP + 2
			walls.set_cell(cell, 0, DOORWAY_TILE if doorway else WALL_TILE)
	walls.set_script(load(WALL_LAYER))
	_root.add_child(walls)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := _at(7.0, 16.6)
	definition.set(&"map_id", MAP_ID)
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", COLUMNS)
	definition.set(&"rows", ROWS)
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": int(spawn.x), "y": int(spawn.y)}, "entries": {}}})
	_root.add_child(definition)


# --- the pieces ---------------------------------------------------------------------------------

## A point in cells (fractions allowed) as world units.
func _at(x: float, y: float) -> Vector2:
	return Vector2(x, y) * CELL


func _kit(scene: String, name: String, at: Vector2, props: Dictionary = {}, parent: Node = null) -> Node2D:
	var node := (load(KIT + scene + ".tscn") as PackedScene).instantiate() as Node2D
	node.name = name
	node.position = at
	for key: String in props:
		node.set(key, props[key])
	(parent if parent != null else _objects).add_child(node)
	return node


func _pot(name: String, at: Vector2, loot: String) -> void:
	var pot := _kit("dungeon-pot", name, at)
	_root.set_editable_instance(pot, true)
	pot.get_node("PotLoot").set(&"loot", loot)


func _target(name: String, at: Vector2, mechanism: String, rope: PackedVector2Array = PackedVector2Array()) -> void:
	var targets: Array[NodePath] = [NodePath("../" + mechanism)]
	_kit("knock-target", name, at, {"target_id": name, "targets": targets, "rope_points": rope})


func _label(name: String, at: Vector2, text: String) -> void:
	var label := Label.new()
	label.name = name
	label.position = at
	label.size = Vector2(420, 60)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", 13)
	label.modulate = Color(1.0, 0.96, 0.84, 0.9)
	label.text = text
	_objects.add_child(label)


func _enemy(parent: Node2D, type_id: String, name: String, at: Vector2, radius: float) -> void:
	var placed := (load(PLACED_ENEMY) as PackedScene).instantiate() as Node2D
	placed.name = name
	placed.position = at
	placed.set(&"enemy_type", type_id)
	placed.set(&"wander_radius", radius)
	parent.add_child(placed)


func _place() -> void:
	# The camera rooms (the interior walls look for them under `CameraRooms`): lane A's holds the
	# pocket above the hall, so it is taller than a screen.
	var rooms := Node2D.new()
	rooms.name = "CameraRooms"
	_root.add_child(rooms)
	var entries := {"A": Vector2(7.0, 16.6), "B": Vector2(18.0, 16.0), "C": Vector2(34.0, 16.0)}
	for i in 3:
		var name: String = ["A", "B", "C"][i]
		var room := Node2D.new()
		room.set_script(load(CAMERA_ROOM))
		room.name = name
		var top := 0 if i == 0 else HALL_TOP
		room.position = Vector2(i * SCREEN.x, top) * CELL
		room.set(&"size", Vector2(SCREEN.x, ROWS - top) * CELL)
		rooms.add_child(room)
		var entry := Node2D.new()
		entry.name = "RoomEntry"
		entry.position = (entries[name] as Vector2) * CELL - room.position
		room.add_child(entry)
	_objects = Node2D.new()
	_objects.name = "Objects"
	_objects.y_sort_enabled = true
	_root.add_child(_objects)
	_kit("dungeon", "Dungeon", _at(7.0, 17.4), {"dungeon_id": MAP_ID, "display_name": "Mechanism Lab",
		"entrance_marker": "dungeon-entrance", "resume_saves": false}, _root)
	var entrance := Node2D.new()
	entrance.name = "dungeon-entrance"
	entrance.position = _at(7.0, 16.6)
	_root.add_child(entrance)
	var spawn := Node2D.new()
	spawn.name = "player-spawn"
	spawn.position = entrance.position
	_root.add_child(spawn)
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	enemies.y_sort_enabled = true
	_root.add_child(enemies)

	# Lane A: the pit with the target on its far side, the ram aimed at the bricked arch, the chest
	# in the pocket behind it, pots that grow back.
	_kit("hazard", "a-void", Vector2(PIT.position * CELL), {"kind": "void", "size": Vector2(PIT.size * CELL),
		"top_fade_px": 64.0}, _root)
	_kit("ram", "a-ram", _at(9.0, 12.0), {"toward": "north", "length": 4, "ram_id": "a-ram"})
	_kit("bricked-arch", "a-arch", _at(9.0, 8.0), {"wall": "north", "arch_id": "a-arch"})
	# its rope runs round the pit's south end and along the south wall to the ram's post
	_target("a-target", _at(2.5, 12.0), "a-ram", PackedVector2Array([Vector2(0, 322), Vector2(476, 322)]))
	var chest := _kit("dungeon-chest", "a-chest", _at(9.0, 3.0))
	chest.set(&"contents", {"coins": 30})
	chest.set(&"chest_id", "mechanism-lab-a-chest")
	_pot("a-pot-1", _at(6.4, 14.2), "none")
	_pot("a-pot-2", _at(7.2, 15.0), "coins")
	_pot("a-pot-3", _at(6.3, 15.6), "none")
	_pot("a-pot-4", _at(11.6, 15.4), "energy")
	_label("a-note", _at(10.6, 8.2), "Lane A. Suck up a pot (Q) and throw it (Q) over the pit at the target: the ram swings and bursts the bricked arch. The Spear, a Roll and a push only knock on the target. Stand in the lane to feel the ram.")

	# Lane B: a ram across a pen of three enemies.
	_kit("ram", "b-ram", _at(20.3, 12.5), {"toward": "east", "length": 5, "ram_id": "b-ram"})
	_target("b-target", _at(19.6, 15.8), "b-ram")
	_enemy(enemies, "slime-spider", "b-spider", _at(22.3, 10.6), 110.0)
	_enemy(enemies, "worm-brawler", "b-brawler", _at(24.0, 14.4), 110.0)
	_enemy(enemies, "thorn-guard", "b-guard", _at(26.2, 12.2), 120.0)
	_pot("b-pot-1", _at(17.4, 15.6), "none")
	_pot("b-pot-2", _at(18.2, 16.4), "heart")
	_pot("b-pot-3", _at(21.0, 16.6), "none")
	_pot("b-pot-4", _at(22.0, 16.2), "none")
	_label("b-note", _at(16.6, 8.2), "Lane B. Bait the enemies onto the grooves, then throw at the target: the ram flings them down its lane (walls splat). A stunned enemy is a thing to throw too. The ram winds back in 8 s; the target snaps upright when it is ready.")

	# Lane C: a cart that stays where it ends (through the rail gate to its buffer), and a cart
	# that is hauled back, across a pen of one enemy.
	_kit("ram-cart", "c-cart", _at(37.0, 9.4), {"points": PackedVector2Array([Vector2.ZERO, Vector2(0, 400)]),
		"returns": false, "cart_id": "c-cart"})
	_kit("rail-gate", "c-gate", _at(37.0, 13.0), {"rails": "north-south", "gate_id": "c-gate"})
	_target("c-target", _at(35.0, 10.0), "c-cart", PackedVector2Array([Vector2(0, -84), Vector2(168, -84)]))
	_kit("ram-cart", "c-cart-2", _at(44.5, 12.5), {"points": PackedVector2Array([Vector2.ZERO, Vector2(-260, 0)]),
		"returns": true, "cart_id": "c-cart-2"})
	_target("c-target-2", _at(44.5, 15.2), "c-cart-2")
	_enemy(enemies, "worm-swordsman", "c-swordsman", _at(42.4, 12.5), 50.0)
	_pot("c-pot-1", _at(33.4, 14.4), "none")
	_pot("c-pot-2", _at(34.2, 15.2), "none")
	_pot("c-pot-3", _at(42.6, 16.0), "none")
	_pot("c-pot-4", _at(43.4, 16.5), "coins")
	_label("c-note", _at(38.6, 8.2), "Lane C. Left: throw at the brake's target; the cart runs down, smashes the rail gate and stays at its buffer for good. Right: this cart is hauled back by its counterweight in 8 s; bait the enemy onto its rails first.")
