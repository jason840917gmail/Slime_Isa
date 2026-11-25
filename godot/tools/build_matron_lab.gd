extends SceneTree
## Builds the Matron lab (docs/godot/specs/matron.md section 9, the ram fight; step 2 of
## docs/design/2026-11-23-dungeons-2-3-rework.md): her ram fight in the room the plan gives the
## Weaver Hollow's rebuilt Crown, before the Crown itself is rebuilt (step 3).
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_matron_lab.gd [-- --force]
## Writes res://game/dev/bosses/matron-lab.tscn (world.matron-lab; launch it with `?map=matron-lab`
## or `-- --map=matron-lab`; `dungeon.devPowers.matron-lab` lends the Spear, the Roll, the Heavy and
## Silk skins and the Goo Bomb). It does not overwrite an existing lab unless given --force.
##
## One room of root rock (the interior walls' `root-rock` style), its floor 20 x 16 cells, five rams
## along its north wall swinging south down the room (the owner's drawing of 2026-11-24). Each ram's
## knock target stands straight below it, past its lane's end by the south wall, its rope running up
## the lane to its ram (the owner, the same day: the targets "should align vertically with the ram",
## the crossed ropes were too hard to follow in a room this big). Round 2 rings the targets with web
## walls. Her camp (`character.orb-weaver-matron-rework`) is in the middle; each cocoon she spins
## hangs over a lane picked at random. Pots in the gaps between the lanes. The slime starts by the
## south wall, between two targets; she wakes when it walks in.

const SceneSave := preload("res://tools/lib/scene_save.gd")

const LAB_PATH := "res://game/dev/bosses/matron-lab.tscn"
const MAP_ID := "matron-lab"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const WALL_TILESET := "res://game/world/interior/interior_wall_tileset.tres"
const WALL_LAYER := "res://game/world/interior/interior_wall_layer.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CAMERA_ROOM := "res://game/world/camera_room.gd"
const CAMP := "res://game/scenes/encounters/weaver-hollow-matron.tscn"
const KIT := "res://game/scenes/objects/dungeon/"
const CELL := 64
const COLUMNS := 24
const ROWS := 20
## The floor (cells): the walls are two cells deep all round.
const FLOOR := Rect2i(2, 2, 20, 16)
const FLOOR_SOURCE := 1
const SHEET := 19
## interior_wall_tileset.tres, the root rock's column: the wall.
const WALL_TILE := Vector2i(2, 0)
## Her camp (cells): she spawns here and moves at once over the lane her first cocoon hangs in.
const HOME := Vector2(12.0, 10.0)
const SPAWN := Vector2(10.1, 16.9)
## The rams' columns along the north wall (cells), their row and their lanes' length (they end two
## cells above the bottom row, where the targets stand clear of the logs).
const RAM_COLUMNS: Array[float] = [4.5, 8.2, 12.0, 15.8, 19.5]
const RAM_ROW := 5.6
const RAM_LENGTH := 9
## Each ram's knock target (cells): straight below its ram, by the south wall (TARGET_ROW).
const TARGET_ROW := 16.8

var _root: Node2D
var _objects: Node2D


func _initialize() -> void:
	if FileAccess.file_exists(LAB_PATH) and not OS.get_cmdline_user_args().has("--force"):
		print("matron lab: %s exists; not overwritten (add -- --force to rebuild it)" % LAB_PATH)
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
	if err == OK:
		_drop_copied_connections()
	print("matron lab: ", "ok" if err == OK else "failed (%d)" % err)
	quit(0 if err == OK else 1)


## The saver writes the camp scene's own connection (its roar) again for the editable instance; the
## instance already has it, so it would connect twice. The copy goes.
func _drop_copied_connections() -> void:
	var text := FileAccess.get_file_as_string(LAB_PATH)
	var kept: PackedStringArray = []
	for line: String in text.split("\n"):
		if line.begins_with("[connection") and line.contains("from=\"Objects/matron-camp/"):
			continue
		kept.append(line)
	var file := FileAccess.open(LAB_PATH, FileAccess.WRITE)
	file.store_string("\n".join(kept))
	file.close()


func _own(node: Node) -> void:
	node.owner = _root
	if node.scene_file_path.is_empty():
		for child in node.get_children():
			_own(child)


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
	var walls := TileMapLayer.new()
	walls.name = "interior-walls"
	walls.y_sort_enabled = true
	walls.tile_set = load(WALL_TILESET)
	for y in ROWS:
		for x in COLUMNS:
			if not FLOOR.has_point(Vector2i(x, y)):
				walls.set_cell(Vector2i(x, y), 0, WALL_TILE)
	walls.set_script(load(WALL_LAYER))
	_root.add_child(walls)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := _at(SPAWN.x, SPAWN.y)
	definition.set(&"map_id", MAP_ID)
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", COLUMNS)
	definition.set(&"rows", ROWS)
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": int(spawn.x), "y": int(spawn.y)}, "entries": {}}})
	_root.add_child(definition)


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


func _target(name: String, at: Vector2, mechanism: String) -> void:
	var targets: Array[NodePath] = [NodePath("../" + mechanism)]
	_kit("knock-target", name, at, {"target_id": name, "targets": targets})


func _label(name: String, at: Vector2, text: String) -> void:
	var label := Label.new()
	label.name = name
	label.position = at
	label.size = Vector2(560, 60)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", 13)
	label.modulate = Color(1.0, 0.96, 0.84, 0.9)
	label.text = text
	_objects.add_child(label)


func _rect_shape(holder: Node, at: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	holder.set(&"shape", shape)
	(holder as Node2D).position = at


func _place() -> void:
	var rooms := Node2D.new()
	rooms.name = "CameraRooms"
	_root.add_child(rooms)
	var room := Node2D.new()
	room.set_script(load(CAMERA_ROOM))
	room.name = "Crown"
	room.position = Vector2.ZERO
	room.set(&"size", Vector2(COLUMNS, ROWS) * CELL)
	rooms.add_child(room)
	var entry := Node2D.new()
	entry.name = "RoomEntry"
	entry.position = _at(SPAWN.x, SPAWN.y)
	room.add_child(entry)
	_objects = Node2D.new()
	_objects.name = "Objects"
	_objects.y_sort_enabled = true
	_root.add_child(_objects)
	_kit("dungeon", "Dungeon", _at(SPAWN.x, SPAWN.y + 0.8), {"dungeon_id": MAP_ID, "display_name": "Matron Lab",
		"entrance_marker": "dungeon-entrance", "resume_saves": false}, _root)
	var entrance := Node2D.new()
	entrance.name = "dungeon-entrance"
	entrance.position = _at(SPAWN.x, SPAWN.y)
	_root.add_child(entrance)
	var spawn := Node2D.new()
	spawn.name = "player-spawn"
	spawn.position = entrance.position
	_root.add_child(spawn)

	# The rams (owner's drawing, 2026-11-24): five along the north wall, each swinging south down the
	# room; each ram's target straight below it by the south wall, its rope up the lane to its ram.
	for i in RAM_COLUMNS.size():
		_kit("ram", "ram-%d" % (i + 1), _at(RAM_COLUMNS[i], RAM_ROW), {"toward": "south", "length": RAM_LENGTH,
			"ram_id": "matron-lab-ram-%d" % (i + 1)})
		_target("target-%d" % (i + 1), _at(RAM_COLUMNS[i], TARGET_ROW), "ram-%d" % (i + 1))

	# Her camp at her spot: the whole floor is her arena; she wakes when the slime walks in past the
	# south rows.
	var camp := (load(CAMP) as PackedScene).instantiate() as Node2D
	camp.name = "matron-camp"
	camp.position = _at(HOME.x, HOME.y)
	_objects.add_child(camp)
	_root.set_editable_instance(camp, true)
	var script_node := camp.get_node("BossCampScript")
	script_node.set(&"map_id", MAP_ID)
	script_node.set(&"camp_id", "matron-lab-matron")
	script_node.set(&"boss_scene", "character.orb-weaver-matron-rework")
	# the camp spawns at an old Phaser centre (her feet 30 below it): her feet on HOME
	script_node.set(&"spawn", Vector2(0.0, -30.0))
	script_node.set(&"respawn_ms", 4000.0)
	script_node.set(&"boss_overrides", {"arena_recovery_ms": 0.0, "cocoon_enabled": true})
	var floor_middle := (Vector2(FLOOR.position) + Vector2(FLOOR.size) * 0.5) * CELL - camp.position
	_rect_shape(camp.get_node("ArenaArea/ArenaShape"), floor_middle, Vector2(FLOOR.size) * CELL)
	var wake := Rect2(Vector2(FLOOR.position) * CELL, Vector2(FLOOR.size.x, FLOOR.size.y - 2.5) * CELL)
	_rect_shape(camp.get_node("ActivationArea/ActivationShape"), wake.get_center() - camp.position, wake.size)
	# her full heart rises in the room's middle (owner, 2026-11-24)
	(camp.get_node("FullHeart") as Node2D).position = floor_middle
	(camp.get_node("MatronThread") as Node2D).position = _at(2.8, 3.4) - camp.position

	# Pots round the walls: ammo for the targets, and for her while she is down.
	# (in the gaps between the lanes and between the targets, clear of round 2's web rings)
	var pots := [Vector2(2.7, 8.0), Vector2(2.7, 13.0), Vector2(6.3, 7.0), Vector2(10.1, 8.5),
		Vector2(10.1, 14.0), Vector2(13.9, 6.5), Vector2(13.9, 12.5), Vector2(17.6, 9.0),
		Vector2(17.6, 14.5), Vector2(6.35, 17.2), Vector2(13.9, 17.2), Vector2(17.65, 17.2)]
	for i in pots.size():
		_pot("pot-%d" % (i + 1), _at(pots[i].x, pots[i].y), "energy" if i % 5 == 4 else "none")
	_label("note", _at(2.4, 17.4), "Matron lab (her ram fight). Five rams, each target straight below its ram. Her cocoon hangs over one ram's lane, a different one each time: knock it down with that ram, or (round 1) a Goo Bomb on its shadow. Round 2: bait her dive onto a lane's lower end, step off and throw at its target, or stand in her lane while she lies after a dive and step out when she spits: her own ram hits her. She trips rams at you too.")
