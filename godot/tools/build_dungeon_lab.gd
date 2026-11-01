extends SceneTree
## Builds the dungeon lab (docs/godot/DUNGEONS.md "The dungeon lab"): a small dev dungeon, one
## example of every piece of the dungeon kit, so the dungeon builders and the owner can try them.
##     "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_dungeon_lab.gd [-- --force]
## Writes res://game/scenes/worlds/dev/dungeon-lab.tscn (world.dungeon-lab; launch it with
## `?map=dungeon-lab` or `-- --map=dungeon-lab`). It does not overwrite an existing lab (where you
## may have edited) unless given --force.
##
## Nine rooms of one screen (16 x 14 cells) on a 3 x 4 grid; the walls are level-2 masonry painted on
## the `elevation` layer (cobble ground), the voids level -2 holes, the spike pit a level -1 hole
## with a stair:
##
##   B0 boss room (a room fight with a boss: shutters, a Big Squint; his full heart), the dungeon's
##      boss: his fall breaks the seal
##   C1 the Pearl room (a sealed dungeon, docs/godot/DUNGEONS.md "The seal"): the Pearl on its
##      altar behind its guard (a room fight with a mini-boss's `boss_id`, a Worm Brawler); taken, it
##      seals the dungeon
##   B1 the winch and the drawbridge over the void, the big chest (the big key), the boss door north
##   A2 a dark room: the shadow path over the void to an islet, a chest (the compass) and its glint
##   B2 the hub: the door with two keyholes north (to B1)
##   C2 falling slabs: two over a narrow void (one Roll), two + a landing + two over a wide one; a
##      small key on the far side
##   A3 slabs over a spike pit with a stair out; the bolted door back east into the entrance; a worm
##      that is back each time the room is entered again
##   B3 the entrance (where a faint resumes): a small-key chest, the map chest, pots that hide
##      refills, an energy flower; the small-key door north (to B2); the way out south (a door to the
##      playground) with the dungeon's seal in its doorway
##   C3 an ambush (once): shutters, two worms, a hidden chest with a small key

const LAB_PATH := "res://game/scenes/worlds/dev/dungeon-lab.tscn"
const MAP_ID := "dungeon-lab"
const ELEVATION_TILESET := "res://game/world/elevation/elevation_tileset.tres"
const ELEVATION_LAYER := "res://game/world/elevation/elevation_layer.gd"
const TERRAIN_TILESET := "res://game/world/terrain_tileset.tres"
const WORLD_GROUND := "res://game/world/world_ground.gd"
const WORLD_DEFINITION := "res://game/scripts/world_definition.gd"
const CAMERA_ROOM := "res://game/world/camera_room.gd"
const DARK_ROOM := "res://game/world/darkness/dark_room.gd"
const PLACED_ENEMY := "res://game/scenes/encounters/placed-enemy.tscn"
const DOOR := "res://game/scripts/door.gd"
const OBJECTS := "res://game/scenes/objects/"
const ROAR := "res://asset/audio/sfx/library/boss/fatty-roar.ogg"
## The dungeon's boss (B0) and the Pearl's guard (C1).
const BOSS_ID := "dungeon-lab-boss"
const GUARD_ID := "dungeon-lab-guard"
const KIT := "res://game/scenes/objects/dungeon/"
const CELL := 64
const ROOM := Vector2i(16, 14)
const GRID := Vector2i(3, 4)
const COBBLE := 19
const SHEET_CELLS := 19
## elevation_tileset.tres: levels -3 ... -1 at (0 ... 2, 0), 1 ... 3 at (3 ... 5, 0); stairs row 1.
const WALL_LEVEL := 2
const DIRECTIONS := ["s", "sw", "w", "nw", "n", "ne", "e", "se"]
## The rooms in use (the others are solid wall).
const ROOMS := {"B0": Vector2i(1, 0), "B1": Vector2i(1, 1), "C1": Vector2i(2, 1), "A2": Vector2i(0, 2),
	"B2": Vector2i(1, 2), "C2": Vector2i(2, 2), "A3": Vector2i(0, 3), "B3": Vector2i(1, 3), "C3": Vector2i(2, 3)}

var _levels: Dictionary = {}
var _root: Node2D


func _initialize() -> void:
	if FileAccess.file_exists(LAB_PATH) and not OS.get_cmdline_user_args().has("--force"):
		print("dungeon lab: %s exists; not overwritten (add -- --force to rebuild it)" % LAB_PATH)
		quit(0)
		return
	_root = Node2D.new()
	_root.name = MAP_ID
	_root.y_sort_enabled = true
	_paint()
	_place()
	for child in _root.get_children():
		_own(child)
	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, LAB_PATH)
	_root.free()
	print("dungeon lab: ", "ok" if err == OK else "failed (%d)" % err)
	quit(0 if err == OK else 1)


func _own(node: Node) -> void:
	node.owner = _root
	if node.scene_file_path.is_empty():
		for child in node.get_children():
			_own(child)


# --- painting -----------------------------------------------------------------------------------

func _origin(room: String) -> Vector2i:
	return Vector2i(ROOMS[room].x * ROOM.x, ROOMS[room].y * ROOM.y)


func _set_level(c: Vector2i, level: int) -> void:
	if level == 0:
		_levels.erase(c)
	else:
		_levels[c] = level


func _fill(from: Vector2i, size: Vector2i, level: int) -> void:
	for y in range(from.y, from.y + size.y):
		for x in range(from.x, from.x + size.x):
			_set_level(Vector2i(x, y), level)


func _paint() -> void:
	var columns := GRID.x * ROOM.x
	var rows := GRID.y * ROOM.y
	# Everything is wall, then each room's floor is cut out of it (a one-cell border stays).
	_fill(Vector2i.ZERO, Vector2i(columns, rows), WALL_LEVEL)
	for room: String in ROOMS:
		_fill(_origin(room) + Vector2i(1, 1), ROOM - Vector2i(2, 2), 0)
	# Doorways: two cells through the walls between rooms.
	_door_vertical("B3", "B2")
	_door_vertical("B2", "B1")
	_door_vertical("B1", "B0")
	_door_vertical("C3", "C2")
	_door_vertical("C2", "C1")
	_door_vertical("A3", "A2")
	# The way out: B3's south wall, at the world's edge.
	var b3 := _origin("B3")
	for x in [7, 8]:
		_set_level(Vector2i(b3.x + x, b3.y + ROOM.y - 1), 0)
	_door_side("B3", "C3", 6)
	_door_side("B2", "C2", 3)
	_door_side("A2", "B2", 6)
	_door_side("A3", "B3", 10)
	# Voids, pits and the islet.
	var c2 := _origin("C2")
	_fill(c2 + Vector2i(1, 7), Vector2i(6, 2), -2)
	_fill(c2 + Vector2i(7, 5), Vector2i(8, 5), -2)
	var a2 := _origin("A2")
	_fill(a2 + Vector2i(1, 3), Vector2i(9, 6), -2)
	_fill(a2 + Vector2i(3, 5), Vector2i(3, 2), 0)
	var a3 := _origin("A3")
	_fill(a3 + Vector2i(1, 6), Vector2i(14, 3), -1)
	var b1 := _origin("B1")
	_fill(b1 + Vector2i(1, 6), Vector2i(14, 3), -2)
	var ground := TileMapLayer.new()
	ground.name = "ground"
	ground.z_index = -2
	ground.tile_set = load(TERRAIN_TILESET)
	for y in rows:
		for x in columns:
			ground.set_cell(Vector2i(x, y), COBBLE, Vector2i(x % SHEET_CELLS, y % SHEET_CELLS))
	ground.set_meta(&"source_cell_count", columns * rows)
	ground.set_meta(&"columns", columns)
	ground.set_meta(&"rows", rows)
	ground.set_script(load(WORLD_GROUND))
	_root.add_child(ground)
	var elevation := TileMapLayer.new()
	elevation.name = "elevation"
	elevation.z_index = -1
	elevation.tile_set = load(ELEVATION_TILESET)
	for c: Vector2i in _levels:
		var level := int(_levels[c])
		elevation.set_cell(c, 0, Vector2i(level + 3 if level < 0 else level + 2, 0))
	# The spike pit's stair: up from its floor to the south rim (a back flight, arrow down = north).
	for x in [2, 3]:
		elevation.set_cell(a3 + Vector2i(x, 8), 0, Vector2i(DIRECTIONS.find("n"), 1))
	elevation.set_script(load(ELEVATION_LAYER))
	_root.add_child(elevation)
	var definition := Node.new()
	definition.name = "world-definition"
	definition.set_script(load(WORLD_DEFINITION))
	var spawn := _at("B3", Vector2(8, 10))
	definition.set(&"map_id", MAP_ID)
	definition.set(&"tile_size", CELL)
	definition.set(&"columns", columns)
	definition.set(&"rows", rows)
	definition.set(&"metadata", {"objects": [], "player": {"spawn": {"x": int(spawn.x), "y": int(spawn.y)}, "entries": {}}})
	_root.add_child(definition)


## A doorway through the wall between `lower` and the room above it, two cells wide in the middle.
func _door_vertical(lower: String, upper: String) -> void:
	var low := _origin(lower)
	var up := _origin(upper)
	for x in [7, 8]:
		_set_level(Vector2i(low.x + x, low.y), 0)
		_set_level(Vector2i(up.x + x, up.y + ROOM.y - 1), 0)


## A doorway through the wall between `left` and the room right of it, passable on the two rows
## from `row`: the two rows above them are cleared too, for the wall above hangs its two-level face
## over them (the doorway's lintel).
func _door_side(left: String, right: String, row: int) -> void:
	var l := _origin(left)
	var r := _origin(right)
	for y in range(row - WALL_LEVEL, row + 2):
		_set_level(Vector2i(l.x + ROOM.x - 1, l.y + y), 0)
		_set_level(Vector2i(r.x, r.y + y), 0)


# --- the pieces ---------------------------------------------------------------------------------

## A point of room `room` in cells (fractions allowed) as world units.
func _at(room: String, cells: Vector2) -> Vector2:
	return (Vector2(_origin(room)) + cells) * CELL


func _kit(scene: String, name: String, at: Vector2, props: Dictionary = {}) -> Node2D:
	var node := (load(KIT + scene + ".tscn") as PackedScene).instantiate() as Node2D
	node.name = name
	node.position = at
	for key: String in props:
		node.set(key, props[key])
	_root.add_child(node)
	return node


func _node(script: String, name: String, at: Vector2, props: Dictionary = {}) -> Node2D:
	var node := Node2D.new()
	node.set_script(load(script))
	node.name = name
	node.position = at
	for key: String in props:
		node.set(key, props[key])
	_root.add_child(node)
	return node


## A game object (`res://game/scenes/objects/<scene>.tscn`): `props` on its root, or `child_props`
## ({child path: {property: value}}) on its children, "" for the root.
func _object(scene: String, name: String, at: Vector2, child_props: Dictionary = {}, props: Dictionary = {}) -> Node2D:
	var node := (load(OBJECTS + scene + ".tscn") as PackedScene).instantiate() as Node2D
	node.name = name
	node.position = at
	for key: String in props:
		node.set(key, props[key])
	for path: String in child_props:
		var child := node.get_node(path)
		var values: Dictionary = child_props[path]
		for key: String in values:
			child.set(key, values[key])
	_root.add_child(node)
	if not child_props.is_empty():
		_root.set_editable_instance(node, true)
	return node


func _chest(scene: String, name: String, at: Vector2, contents: Dictionary, hidden: bool = false) -> Node2D:
	var chest := _kit(scene, name, at)
	_root.set_editable_instance(chest, true)
	var script_node := chest.get_node("ChestScript")
	script_node.set(&"instance_id", name)
	script_node.set(&"initial_contents", contents)
	script_node.set(&"hidden", hidden)
	return chest


func _enemy(parent: Node2D, type_id: String, name: String, at: Vector2, radius: float) -> void:
	var placed := (load(PLACED_ENEMY) as PackedScene).instantiate() as Node2D
	placed.name = name
	placed.position = at
	placed.set(&"enemy_type", type_id)
	placed.set(&"wander_radius", radius)
	parent.add_child(placed)


func _place() -> void:
	# Camera rooms, the dark room, the dungeon.
	# Each room's RoomEntry: where `?room=<name>` puts the slime (safe ground).
	var entries := {"B0": Vector2(8, 10), "B1": Vector2(8, 11), "C1": Vector2(8, 10), "A2": Vector2(12, 10), "B2": Vector2(8, 8),
		"C2": Vector2(4, 11), "A3": Vector2(8, 4), "B3": Vector2(8, 10), "C3": Vector2(4, 7)}
	for room: String in ROOMS:
		var camera_room := _node(CAMERA_ROOM, room, Vector2(_origin(room) * CELL), {"size": Vector2(ROOM * CELL)})
		var entry := Node2D.new()
		entry.name = "RoomEntry"
		entry.position = (entries[room] as Vector2) * CELL
		camera_room.add_child(entry)
	_node(DARK_ROOM, "A2-dark", _at("A2", Vector2(1, 1)), {"size": Vector2(14, 12) * CELL})
	_kit("dungeon", "Dungeon", _at("B3", Vector2(8, 12.5)), {"dungeon_id": MAP_ID, "display_name": "Dungeon Lab",
		"entrance_marker": "dungeon-entrance", "resume_saves": false, "boss_id": BOSS_ID, "boss_name": "The Big Squint",
		"seal_color": Color("#d4482e"), "roar_sound": load(ROAR), "roar_pitch": 1.3, "dust_color": Color("#efe3c4")})
	var entrance := Node2D.new()
	entrance.name = "dungeon-entrance"
	entrance.position = _at("B3", Vector2(8, 10))
	_root.add_child(entrance)
	var spawn := Node2D.new()
	spawn.name = "player-spawn"
	spawn.position = entrance.position
	_root.add_child(spawn)
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	enemies.y_sort_enabled = true
	_root.add_child(enemies)

	# B3, the entrance: a small key, the map, pots that hide refills, an energy flower; the key door.
	_chest("dungeon-chest", "b3-key-chest", _at("B3", Vector2(4, 6)), {"dungeon-small-key": 1})
	_chest("dungeon-chest", "b3-map-chest", _at("B3", Vector2(12, 6)), {"dungeon-map": 1})
	var loots := ["heart", "energy", "coins"]
	for i in 3:
		var pot := _kit("dungeon-pot", "b3-pot-%d" % i, _at("B3", Vector2(3.5 + i * 1.2, 11.5)))
		_root.set_editable_instance(pot, true)
		pot.get_node("PotLoot").set(&"loot", loots[i])
	_kit("energy-flower", "b3-flower", _at("B3", Vector2(12.5, 11.5)))
	_kit("key-door", "b3-key-door", _at("B3", Vector2(8, 3)), {"door_id": "b3-north", "keyholes": 1})
	# The way out (south, to the playground) and the dungeon's seal in its doorway: down until the
	# Pearl is taken, then shut until the Big Squint falls.
	var way_out := Node2D.new()
	way_out.name = "b3-way-out"
	way_out.position = _at("B3", Vector2(8, 13.5))
	_root.add_child(way_out)
	var door := Node.new()
	door.name = "Door"
	door.set_script(load(DOOR))
	door.set(&"map_id", MAP_ID)
	door.set(&"door_id", "dungeon-lab-way-out")
	door.set(&"target_area_id", "playground")
	door.set(&"kind", "opening")
	door.set(&"side", "south")
	door.set(&"trigger_rect", Rect2(-64, 0, 128, 32))
	way_out.add_child(door)
	_kit("dungeon-seal", "b3-seal", _at("B3", Vector2(8, 13)), {"wall": "south", "glimpse": true})

	# C3, the ambush: shutters, two worms, a chest that rises with the third key.
	_kit("shutter", "c3-shutter-west", _at("C3", Vector2(1, 7)), {"wall": "west", "fight_id": "c3-ambush"})
	_kit("shutter", "c3-shutter-north", _at("C3", Vector2(8, 3)), {"wall": "north", "fight_id": "c3-ambush"})
	_enemy(enemies, "worm-swordsman", "c3-worm-1", _at("C3", Vector2(6, 9)), 120.0)
	_enemy(enemies, "worm-swordsman", "c3-worm-2", _at("C3", Vector2(11, 7)), 120.0)
	_chest("dungeon-chest", "c3-reward-chest", _at("C3", Vector2(8, 9.5)), {"dungeon-small-key": 1}, true)
	_kit("room-fight", "c3-fight", Vector2(_origin("C3") * CELL), {"size": Vector2(ROOM * CELL),
		"fight_id": "c3-ambush", "once": true, "reward": NodePath("../c3-reward-chest")})

	# C2, slabs over the void: two over a narrow gap (one quick Roll), two + a landing + two over a wide
	# one; a small key on the far side.
	_kit("hazard", "c2-void-narrow", _at("C2", Vector2(1, 7)), {"kind": "void", "size": Vector2(6, 2) * CELL,
		"top_fade_px": 128.0})
	_kit("hazard", "c2-void-wide", _at("C2", Vector2(7, 5)), {"kind": "void", "size": Vector2(8, 5) * CELL,
		"top_fade_px": 128.0})
	for y in [7, 8]:
		_kit("falling-slab", "c2-slab-narrow-%d" % y, _at("C2", Vector2(3, y)), {"size": Vector2(128, 64)})
	for y in [5, 6, 8, 9]:
		_kit("falling-slab", "c2-slab-wide-%d" % y, _at("C2", Vector2(10, y)), {"size": Vector2(128, 64)})
	_kit("hazard-deck", "c2-landing", _at("C2", Vector2(10, 7)), {"size": Vector2(128, 64)})
	var key := _kit("dungeon-key", "c2-key", _at("C2", Vector2(12, 3.6)), {"item": "small-key", "pickup_id": "c2-key"})
	key.z_index = 0

	# B2, the hub: the door with two keyholes north.
	_kit("key-door", "b2-double-door", _at("B2", Vector2(8, 3)), {"door_id": "b2-north", "keyholes": 2})

	# B1: the winch lowers the drawbridge over the void; the big key; the boss door north.
	var bridge := _kit("drawbridge", "b1-drawbridge", _at("B1", Vector2(8, 6)), {"toward": "south", "length": 3,
		"width": 128.0, "bridge_id": "b1-bridge"})
	_kit("hazard", "b1-void", _at("B1", Vector2(1, 6)), {"kind": "void", "size": Vector2(14, 3) * CELL,
		"top_fade_px": 128.0})
	var targets: Array[NodePath] = [NodePath("../" + String(bridge.name))]
	_kit("winch", "b1-winch", _at("B1", Vector2(4, 10.5)), {"winch_id": "b1-winch", "targets": targets})
	_chest("dungeon-big-chest", "b1-big-chest", _at("B1", Vector2(4, 4.6)), {"dungeon-big-key": 1})
	_kit("boss-door", "b1-boss-door", _at("B1", Vector2(8, 3)), {"door_id": "b1-boss"})

	# B0, the boss room: a trap gate, a Big Squint.
	_kit("shutter", "b0-shutter", _at("B0", Vector2(8, 13)), {"wall": "south", "fight_id": "b0-boss"})
	_enemy(enemies, "big-squint", "b0-boss", _at("B0", Vector2(8, 7)), 220.0)
	_kit("room-fight", "b0-fight", Vector2(_origin("B0") * CELL), {"size": Vector2(ROOM * CELL),
		"fight_id": "b0-boss", "boss_id": BOSS_ID})
	_object("full-heart", "b0-full-heart", _at("B0", Vector2(8, 5.5)), {"FullHeartScript": {"heart_id": BOSS_ID,
		"boss_id": BOSS_ID}})

	# C1, the Pearl room: the Pearl on its altar behind its guard (a mini-boss fight: its `boss_id`
	# is the Pearl's), its glow seen from the doorway through the fight. Taken, it seals the dungeon.
	_kit("shutter", "c1-shutter", _at("C1", Vector2(8, 13)), {"wall": "south", "fight_id": "c1-guard"})
	_enemy(enemies, "worm-brawler", "c1-guard", _at("C1", Vector2(8, 8)), 220.0)
	_kit("room-fight", "c1-fight", Vector2(_origin("C1") * CELL), {"size": Vector2(ROOM * CELL),
		"fight_id": "c1-guard", "boss_id": GUARD_ID})
	_object("decoration-world-solid--pearl-altar", "c1-altar", _at("C1", Vector2(8, 5.6)))
	_object("pearl", "c1-pearl", _at("C1", Vector2(8, 4.3)), {}, {"pearl_id": "dungeon-lab", "boss_id": GUARD_ID,
		"number": 1, "skin_id": "feral", "card_name": "Feral skin", "take_radius": 90.0,
		"card_line": "The lab's Pearl: its dungeon seals until the Big Squint falls.",
		"card_how": "Hold the interact key at a climbable wall to climb it."})
	_kit("prize-glint", "c1-glint", _at("C1", Vector2(8, 3.4)))

	# A2, dark: the shadow path over the void to the islet, the compass in a glinting chest.
	# The void round the islet: four pieces, so the islet (ground) is not drawn over; the far wall's
	# rows fade into the dark.
	_kit("hazard", "a2-void-top", _at("A2", Vector2(1, 3)), {"kind": "void", "size": Vector2(9, 2) * CELL,
		"top_fade_px": 128.0})
	_kit("hazard", "a2-void-west", _at("A2", Vector2(1, 5)), {"kind": "void", "size": Vector2(2, 4) * CELL})
	_kit("hazard", "a2-void-south", _at("A2", Vector2(3, 7)), {"kind": "void", "size": Vector2(3, 2) * CELL})
	_kit("hazard", "a2-void", _at("A2", Vector2(6, 5)), {"kind": "void", "size": Vector2(4, 4) * CELL})
	_kit("hazard-deck", "a2-islet", _at("A2", Vector2(3, 5)), {"size": Vector2(3, 2) * CELL, "draw_floor": false})
	var path_cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	_kit("shadow-path", "a2-shadow-path", _at("A2", Vector2(6, 5)), {"cells": path_cells})
	var back := Node2D.new()
	back.name = "ReturnMouth"
	back.position = Vector2(10.5, 5.5) * CELL - Vector2(6, 5) * CELL
	_root.get_node("a2-void").add_child(back)
	back.owner = _root
	_chest("dungeon-chest", "a2-compass-chest", _at("A2", Vector2(4.5, 6)), {"dungeon-compass": 1})
	_kit("prize-glint", "a2-glint", _at("A2", Vector2(4.5, 5.3)))

	# A3: slabs over a spike pit (a stair out of it), the bolted door back into the entrance.
	_kit("hazard", "a3-spikes", _at("A3", Vector2(1, 6)), {"kind": "spikes", "size": Vector2(14, 3) * CELL,
		"rim_level": 0, "pit_depth": 1, "top_fade_px": 64.0})
	_kit("falling-slab", "a3-slab-6", _at("A3", Vector2(9, 6)), {"size": Vector2(128, 64)})
	_kit("hazard-deck", "a3-landing", _at("A3", Vector2(9, 7)), {"size": Vector2(128, 64)})
	_kit("falling-slab", "a3-slab-8", _at("A3", Vector2(9, 8)), {"size": Vector2(128, 64)})
	_kit("bolted-door", "a3-bolted-door", _at("A3", Vector2(15, 11)), {"wall": "east", "door_id": "a3-bolt"})
	# A room enemy: beaten, it is back when A3 is entered again.
	_enemy(enemies, "worm-swordsman", "a3-worm", _at("A3", Vector2(12, 4)), 90.0)
