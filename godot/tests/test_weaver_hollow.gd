extends RefCounted
## The Weaver Hollow, Chapter 2's dungeon (docs/godot/DUNGEONS.md "The Weaver Hollow";
## docs/design/2026-10-16-dungeon-weaver-hollow.md): its four floors, built by
## tools/build_weaver_hollow.gd (tools/weaver_hollow/hollow_floors.gd has every cell named below).
## The floors load with their camera rooms; every door between floors pairs with a door of the other
## floor on the opposite side; the gaps between rooms can be walked through (the side walls of the
## bands leave room); the Larder's cracks open the Well Room and the map nook only once blown; the
## hub's hatch opens only from below. The dungeon kit's pieces (docs/godot/DUNGEONS.md): the four
## floors are one dungeon resumed at T1; three small keys for three keyholes, one big key for the
## Crown Door, one map; a bomb on B2's cracked post lowers its drawbridge, and B6's kegs chain to the
## pillar's post and its bridge; the gallery's winch opens its stair for good; the Nursery's ambush
## shuts its doors until its enemies are beaten and brings small key 3; the Mimic spits small key 2;
## the Matron's camp raises and lowers the Crown's shutter.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const GooBlast := preload("res://game/player/abilities/goo_blast.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const DungeonScript := preload("res://game/dungeon/dungeon.gd")
const DungeonKeyPickup := preload("res://game/dungeon/dungeon_key_pickup.gd")
const DUNGEON_ID := "weaver-hollow"

const FLOORS: PackedStringArray = ["trunk", "roots", "boughs", "crown"]
const WORLD := "weaver-hollow-%s"
const SCENE := "res://game/scenes/worlds/weaver-hollow-%s.tscn"
const CELL := 64.0
## Camera rooms by floor (hollow_floors.gd).
const ROOMS := {
	"trunk": ["T4-well-room", "T3-larder", "T2-hollow-heart", "T1-root-door", "S3-nook"],
	"roots": ["R1-root-fall", "R2-bone-cellar", "R3-drop-gate", "D1-old-cellar"],
	"boughs": ["D2-dark-bough", "Hoard", "B5-wardens-den", "B6-the-pillar", "B1-bough-stair", "B2-drawbridge",
			"B4-nursery", "B3-mimics-pantry"],
	"crown": ["C2-the-crown", "C3-outer-bough", "C1-crown-stair"],
}
## Walks through the gaps between rooms of one floor: [floor, start cell (centre), key, the room it
## ends in]. Gaps a kit lock, a shutter (the Nursery's ambush, the Warden's and the Matron's fights),
## a web wall or a void will close are not walked here.
const WALKS := [
	["trunk", Vector2(12.5, 22.0), &"move_right", "T2-hollow-heart"],
	["trunk", Vector2(24.0, 24.5), &"move_down", "T1-root-door"],
	["trunk", Vector2(24.0, 31.5), &"move_up", "T2-hollow-heart"],
	["roots", Vector2(12.5, 8.0), &"move_right", "R2-bone-cellar"],
	["roots", Vector2(24.0, 11.0), &"move_down", "D1-old-cellar"],
	["roots", Vector2(7.5, 4.0), &"move_down", "R1-root-fall"],
	["boughs", Vector2(12.5, 22.0), &"move_right", "B2-drawbridge"],
	["boughs", Vector2(8.0, 17.5), &"move_up", "D2-dark-bough"],
	["boughs", Vector2(40.0, 24.5), &"move_down", "B3-mimics-pantry"],
]
const WALK_MS := 3000.0


func test_the_four_floors_load_with_their_camera_rooms(t: TestContext) -> void:
	for floor_name in FLOORS:
		var world_id := WORLD % floor_name
		if not await _enter(t, world_id):
			continue
		var root: Node2D = t.world().world_root
		var rooms := root.get_node_or_null("CameraRooms")
		if not t.check(rooms != null, "%s has no CameraRooms" % world_id):
			continue
		var names: Array = []
		for room: Node in rooms.get_children():
			names.append(str(room.name))
		for expected: String in ROOMS[floor_name]:
			t.check(names.has(expected), "%s has no camera room %s" % [world_id, expected])
		t.check(t.world().elevation != null, "%s has no elevation" % world_id)


func test_every_door_between_floors_pairs_with_the_opposite_side(t: TestContext) -> void:
	var doors := {}
	for floor_name in FLOORS:
		var root := (load(SCENE % floor_name) as PackedScene).instantiate()
		for door: Node in _doors(root):
			doors["%s|%s" % [WORLD % floor_name, str(door.get(&"door_id"))]] = {
				"side": str(door.get(&"side")), "target": "%s|%s" % [str(door.get(&"target_area_id")), str(door.get(&"target_door_id"))],
				"kind": str(door.get(&"kind"))}
		root.free()
	var opposite := {"north": "south", "south": "north", "east": "west", "west": "east", "none": "none"}
	for key: String in doors:
		var door: Dictionary = doors[key]
		var target: String = door["target"]
		if not target.begins_with("weaver-hollow-"):
			continue
		if not t.check(doors.has(target), "%s leads to %s, which does not exist" % [key, target]):
			continue
		var other: Dictionary = doors[target]
		t.equal(other["side"], opposite[door["side"]], "%s and %s are not on opposite sides" % [key, target])
		t.equal(other["target"], key, "%s does not lead back to %s" % [target, key])
	# The Well Room's floor drops onto the landing (a marker: nothing leads back up); the Hollow opens
	# from the forecourt and is left by the Outer Bough's drop.
	var roots := (load(SCENE % "roots") as PackedScene).instantiate()
	t.check(roots.find_child("roots-landing", true, false) != null, "no landing marker in the Roots")
	t.check(not doors.has("weaver-hollow-roots|roots-landing"), "the Roots' landing is a door")
	roots.free()
	t.equal(str((doors.get("weaver-hollow-trunk|trunk-entrance", {}) as Dictionary).get("target", "")),
			"gloop-forest-f4|weaver-hollow-root-gate", "the entrance does not lead to the forecourt")
	t.equal(str((doors.get("weaver-hollow-crown|crown-bough-drop", {}) as Dictionary).get("kind", "")), "fall",
			"the Outer Bough's way out is not a drop")


func test_the_gaps_between_rooms_can_be_walked_through(t: TestContext) -> void:
	var current := ""
	for walk: Array in WALKS:
		var world_id := WORLD % str(walk[0])
		if current != world_id:
			if not await _enter(t, world_id):
				continue
			current = world_id
		var start: Vector2 = walk[1] * CELL
		_teleport(t, start)
		await t.steps(4)
		# The walls are tested here, not the fights: the rooms' enemies (an orb-weaver's web halves a
		# walk) hold still.
		_hold_enemies(t)
		t.press(walk[2])
		await t.sim_wait(WALK_MS)
		t.release(walk[2])
		await t.steps(2)
		var feet := t.player_body().global_position
		var room := _room_at(t, feet)
		t.equal(room, str(walk[3]), "%s: from %s (%s) the slime ended in %s at %s (cells)" % [world_id, str(walk[1]),
				str(walk[2]), room, str((feet / CELL).snapped(Vector2(0.01, 0.01)))])


func test_the_larders_cracks_open_the_well_room_and_the_map_nook_once_blown(t: TestContext) -> void:
	if not await _enter(t, WORLD % "trunk"):
		return
	var run := Services.run()
	for crack: Array in [["larder-crack-well", Vector2(8.0, 18.0), "T4-well-room"], ["larder-crack-nook", Vector2(3.0, 18.0), "T4-well-room"]]:
		var wall: Node = t.world().world_root.get_node_or_null("Objects/" + str(crack[0]))
		if not t.check(wall != null, "no %s in the Larder" % crack[0]):
			continue
		var flag := str(wall.get(&"flag_id"))
		t.check(not run.has_flag(flag), "%s starts blown" % crack[0])
		# Shut, the crack holds the slime in the Larder.
		t.teleport_player(crack[1] * CELL)
		t.press(&"move_up")
		await t.sim_wait(1400.0)
		t.release(&"move_up")
		t.equal(_room_at(t, t.player_body().global_position), "T3-larder", "%s let the slime through shut" % crack[0])
		# A blast at its foot opens it for good.
		t.teleport_player(crack[1] * CELL + Vector2(0, 160))
		await t.steps(2)
		GooBlast.detonate((wall as Node2D).global_position + Vector2(0, 30), false)
		await t.until(func() -> bool: return run.has_flag(flag), 2000.0)
		t.check(run.has_flag(flag), "a blast did not open %s" % crack[0])
		await t.sim_wait(400.0)
		t.teleport_player(crack[1] * CELL)
		t.press(&"move_up")
		await t.sim_wait(2400.0)
		t.release(&"move_up")
		t.equal(_room_at(t, t.player_body().global_position), str(crack[2]), "%s did not lead north once blown" % crack[0])


func test_the_hubs_hatch_opens_only_from_below(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, WORLD % "trunk"):
		return
	var hatch: Node = t.world().world_root.get_node_or_null("Doors/hatch")
	if not t.check(hatch != null, "no hatch in the hub"):
		return
	t.check(not bool(hatch.call(&"is_open")), "the hatch starts open")
	# Standing on it from above does nothing: it is latched from below.
	t.teleport_player((hatch as Node2D).global_position - Vector2(0, 27))
	t.press(&"move_down")
	await t.sim_wait(1200.0)
	t.release(&"move_down")
	t.check(t.in_world(WORLD % "trunk"), "the latched hatch let the slime down")
	# From the Roots, the ladder at R3's east end climbs up through it and opens it for good.
	t.main.call(&"travel_to", WORLD % "roots", "", "roots-ladder")
	await t.until(func() -> bool: return t.in_world(WORLD % "roots") and t.player_body() != null, 8000.0)
	await t.steps(30)
	t.press(&"move_up")
	var climbed := await t.until(func() -> bool: return t.in_world(WORLD % "trunk"), 6000.0)
	t.release(&"move_up")
	t.check(climbed, "the ladder in R3 did not climb up to the hub")
	await t.steps(20)
	t.check(run.has_flag("weaver-hollow.hatch-open"), "climbing up did not open the hatch")
	hatch = t.world().world_root.get_node_or_null("Doors/hatch")
	t.check(hatch != null and bool(hatch.call(&"is_open")), "the hatch is not open after the climb")


func test_the_four_floors_are_one_dungeon_resumed_at_the_root_door(t: TestContext) -> void:
	for floor_name in FLOORS:
		var root := (load(SCENE % floor_name) as PackedScene).instantiate()
		var dungeons := _with_script(root, DungeonScript)
		if t.equal(dungeons.size(), 1, "%s has %d Dungeon nodes" % [floor_name, dungeons.size()]):
			var dungeon: Node = dungeons[0]
			t.equal(str(dungeon.get(&"dungeon_id")), DUNGEON_ID, "%s's Dungeon has another id" % floor_name)
			t.equal(str(dungeon.get(&"display_name")), "Weaver Hollow", "%s's Dungeon has another name" % floor_name)
			t.equal(str(dungeon.get(&"entrance_marker")), "dungeon-entrance", "%s resumes at another marker" % floor_name)
			t.equal(str(dungeon.get(&"entrance_map_id")), "" if floor_name == "trunk" else WORLD % "trunk",
					"%s resumes in another world" % floor_name)
		if floor_name == "trunk":
			var entrance := root.find_child("dungeon-entrance", true, false) as Node2D
			if t.check(entrance != null, "the Trunk has no dungeon-entrance marker"):
				t.equal(_room_in(root, entrance.position), "T1-root-door", "the entrance marker is not in T1")
		root.free()


func test_three_small_keys_open_three_keyholes_and_one_big_key_the_crown_door(t: TestContext) -> void:
	var counts := {"small": 0, "big": 0, "map": 0, "keyholes": 0, "big_locks": 0}
	for floor_name in FLOORS:
		var root := (load(SCENE % floor_name) as PackedScene).instantiate()
		for node: Node in root.find_children("ChestScript", "", true, false):
			var contents: Dictionary = node.get(&"initial_contents")
			counts["small"] += int(contents.get("dungeon-small-key", 0))
			counts["big"] += int(contents.get("dungeon-big-key", 0))
			counts["map"] += int(contents.get("dungeon-map", 0))
		for node: Node in _with_script(root, DungeonKeyPickup):
			counts["small" if str(node.get(&"item")) == "small-key" else "big"] += 1
		for node: Node in root.find_children("*", "", true, false):
			var overrides: Variant = node.get(&"overrides")
			if overrides is Dictionary and str((overrides as Dictionary).get("swallowed_scene_id", "")) == "object.dungeon-key":
				var settings: Dictionary = (overrides as Dictionary).get("swallowed_settings", {})
				counts["small" if str(settings.get("item", "")) == "small-key" else "big"] += 1
			if node.get_script() != null and node.get(&"keyholes") != null and node.get(&"lock") != null:
				if str(node.get(&"lock")) == "big":
					counts["big_locks"] += 1
				else:
					counts["keyholes"] += int(node.get(&"keyholes"))
		root.free()
	t.equal(counts["small"], 3, "the Hollow has %d small keys" % counts["small"])
	t.equal(counts["keyholes"], counts["small"], "%d keyholes for %d small keys" % [counts["keyholes"], counts["small"]])
	t.equal(counts["big"], 1, "the Hollow has %d big keys" % counts["big"])
	t.equal(counts["big_locks"], 1, "the Hollow has %d big-key doors" % counts["big_locks"])
	t.equal(counts["map"], 1, "the Hollow has %d maps" % counts["map"])


func test_a_bomb_on_the_cracked_post_lowers_the_drawbridge_over_the_void(t: TestContext) -> void:
	if not await _enter(t, WORLD % "boughs"):
		return
	var bridge := _node(t, "b2-drawbridge")
	var post := _node(t, "winch-post") as Node2D
	if not t.check(bridge != null and post != null, "B2 has no drawbridge or no cracked post"):
		return
	t.check(not bool(bridge.call(&"holds")), "B2's drawbridge starts down")
	t.teleport_player(Vector2(27.0, 22.0) * CELL)
	await t.steps(4)
	GooBlast.detonate(post.global_position + Vector2(0, 12), false)
	t.check(await t.until(func() -> bool: return bool(bridge.call(&"holds")), 3000.0), "the blown post did not lower the bridge")
	var falls: Array = []
	var watch := _node(t, "HazardWatch")
	if watch != null:
		watch.connect(&"fell", func(payload: Dictionary) -> void: falls.append(payload))
	t.teleport_player(Vector2(28.5, 22.0) * CELL)
	await t.steps(4)
	t.press(&"move_right")
	await t.sim_wait(2400.0)
	t.release(&"move_right")
	t.check(falls.is_empty(), "the slime fell off the lowered drawbridge")
	t.check(t.player_body().global_position.x > 34.5 * CELL, "the drawbridge did not carry the slime over the void")


func test_the_pillars_kegs_chain_to_its_post_and_its_bridge(t: TestContext) -> void:
	if not await _enter(t, WORLD % "boughs"):
		return
	var bridge := _node(t, "b6-drawbridge")
	var keg := _node(t, "keg-0") as Node2D
	if not t.check(bridge != null and keg != null, "B6 has no drawbridge or no kegs"):
		return
	t.teleport_player(Vector2(51.0, 11.0) * CELL)
	await t.steps(4)
	t.check(not bool(bridge.call(&"holds")), "B6's bridge starts down")
	GooBlast.detonate(keg.global_position, false)
	t.check(await t.until(func() -> bool: return bool(bridge.call(&"holds")), 6000.0),
			"the kegs' chain did not reach the pillar's post and its bridge")
	t.teleport_player(Vector2(52.0, 10.4) * CELL)
	await t.steps(4)
	t.press(&"move_up")
	await t.sim_wait(2200.0)
	t.release(&"move_up")
	t.check(t.player_body().global_position.y < 5.0 * CELL, "the pillar's bridge did not carry the slime to the far shore")


func test_the_gallerys_winch_opens_its_stair_for_good(t: TestContext) -> void:
	if not await _enter(t, WORLD % "trunk"):
		return
	var block := _node(t, "gallery-stair-block")
	var winch := _node(t, "gallery-winch")
	if not t.check(block != null and winch != null, "the gallery has no stair block or no winch"):
		return
	t.check(bool(block.call(&"is_shut")), "the gallery's stair starts open")
	# From the hub's floor the block holds the stair.
	_teleport(t, Vector2(44.5, 8.6) * CELL)
	await t.steps(4)
	t.press(&"move_up")
	await t.sim_wait(1500.0)
	t.release(&"move_up")
	t.check(t.player_body().global_position.y > 6.9 * CELL, "the slime climbed past the stair's block")
	# On the gallery the winch lowers it: pushed up into from the gallery's floor below it.
	_teleport(t, Vector2(42.2, 5.25) * CELL)
	await t.steps(4)
	t.press(&"move_up")
	var turned := await t.until(func() -> bool: return bool(winch.call(&"is_turned")), 3000.0)
	t.release(&"move_up")
	t.check(turned, "pushing the gallery's winch did not turn it")
	t.check(await t.until(func() -> bool: return not bool(block.call(&"is_shut")), 2000.0), "the winch did not open the stair")
	_teleport(t, Vector2(44.5, 4.4) * CELL)
	await t.steps(4)
	t.press(&"move_down")
	await t.sim_wait(2000.0)
	t.release(&"move_down")
	t.check(t.player_body().global_position.y > 7.4 * CELL, "the open stair did not lead down to the hub's floor")
	if await _enter(t, WORLD % "boughs") and await _enter(t, WORLD % "trunk"):
		t.check(not bool(_node(t, "gallery-stair-block").call(&"is_shut")), "the stair shut again when the Trunk was built again")


func test_the_nurserys_ambush_shuts_its_doors_until_won_and_brings_small_key_3(t: TestContext) -> void:
	if not await _enter(t, WORLD % "boughs"):
		return
	var fight := _node(t, "nursery-fight")
	var shutters := [_node(t, "nursery-shutter-west"), _node(t, "nursery-shutter-north")]
	var chest := _node(t, "nursery-key-chest")
	if not t.check(fight != null and chest != null and shutters[0] != null and shutters[1] != null, "the Nursery's ambush is missing a piece"):
		return
	t.check(not bool(chest.get_node("ChestScript").call(&"is_shown")), "the Nursery's key chest is there before the ambush")
	t.teleport_player(Vector2(56.0, 21.0) * CELL)
	t.check(await t.until(func() -> bool: return bool(fight.call(&"is_active")), 1500.0), "the ambush did not start")
	t.check(bool(shutters[0].call(&"is_shut")) and bool(shutters[1].call(&"is_shut")), "the Nursery's shutters did not shut")
	for enemy: Node in _enemies_in(t, Rect2((fight as Node2D).global_position, fight.get(&"size"))):
		_hit(t, enemy.get(&"damage_area") as Area2D, 9999.0)
	t.check(await t.until(func() -> bool: return not bool(fight.call(&"is_active")), 5000.0), "the ambush was not won with its enemies beaten")
	t.check(not bool(shutters[0].call(&"is_shut")) and not bool(shutters[1].call(&"is_shut")), "the Nursery's shutters stayed shut")
	t.check(bool(chest.get_node("ChestScript").call(&"is_shown")), "the chest with small key 3 did not rise")


func test_the_pantrys_mimic_spits_out_small_key_2(t: TestContext) -> void:
	if not await _enter(t, WORLD % "boughs"):
		return
	var run := Services.run()
	var placed := _node(t, "pantry-cocoon-mimic")
	if not t.check(placed != null, "the Pantry has no Cocoon Mimic"):
		return
	t.teleport_player(Vector2(42.0, 38.5) * CELL)
	await t.steps(10)
	var mimic: Node = placed.call(&"get_enemy")
	if not t.check(mimic != null and bool(mimic.call(&"has_swallowed")), "the Mimic swallowed nothing"):
		return
	var keys := DungeonState.small_keys(run, DUNGEON_ID)
	_hit(t, mimic.get(&"damage_area") as Area2D, 9999.0)
	t.check(await t.until(func() -> bool: return bool(mimic.call(&"is_defeated")), 1500.0), "the Mimic was not beaten")
	var key: Array[Node2D] = []
	var dropped := await t.until(func() -> bool:
		for node: Node in t.tree.get_nodes_in_group(&"swallowed_drops"):
			if node is Node2D and is_instance_valid(node) and node.is_inside_tree():
				key.append(node as Node2D)
				return true
		return false, 3000.0)
	if not t.check(dropped, "the beaten Mimic spat nothing out"):
		return
	t.check(key[0] is DungeonKeyPickup, "the Mimic's drop is not the kit's floor key")
	await t.sim_wait(900.0)
	t.teleport_player(key[0].global_position - Vector2(0, 20))
	t.check(await t.until(func() -> bool: return DungeonState.small_keys(run, DUNGEON_ID) == keys + 1, 3000.0),
			"walking over the Mimic's key did not give a small key")


func test_the_matrons_camp_raises_and_lowers_the_crowns_shutter(t: TestContext) -> void:
	if not await _enter(t, WORLD % "crown"):
		return
	var camp := _node(t, "BossCampScript")
	var shutter := _node(t, "crown-shutter")
	if not t.check(camp != null and shutter != null, "the Crown has no Matron camp or no shutter"):
		return
	t.check(not bool(shutter.call(&"is_shut")), "the Crown's shutter starts shut")
	t.check(camp.is_connected(&"boss_engaged", Callable(shutter, &"shut")), "the Matron's engaging does not shut the shutter")
	t.check(camp.is_connected(&"boss_defeated", Callable(shutter, &"open")), "the Matron's fall does not open the shutter")
	shutter.call(&"shut", {})
	t.check(await t.until(func() -> bool: return bool(shutter.call(&"is_shut")), 1000.0), "the Crown's shutter did not shut")
	shutter.call(&"open", {})
	t.check(await t.until(func() -> bool: return not bool(shutter.call(&"is_shut")), 1000.0), "the Crown's shutter did not open")


func _enter(t: TestContext, world_id: String) -> bool:
	t.main.call(&"travel_to", world_id)
	var arrived := await t.until(func() -> bool: return t.in_world(world_id) and t.player_body() != null, 8000.0)
	await t.steps(8)
	return t.check(arrived, "could not travel to %s" % world_id)


func _doors(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for node: Node in root.find_children("*", "", true, false):
		if node.get_script() != null and node.has_method(&"use") and node.get(&"door_id") != null \
				and node.get(&"target_area_id") != null:
			found.append(node)
	return found


func _node(t: TestContext, node_name: String) -> Node:
	var world_root: Node = t.world().world_root if t.world() != null else null
	return world_root.find_child(node_name, true, false) if world_root != null else null


## The nodes under `root` whose script is `script`.
func _with_script(root: Node, script: Script) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in root.find_children("*", "", true, false):
		if node.get_script() == script:
			out.append(node)
	return out


## The camera room of a floor scene not in the tree holding `point`.
func _room_in(root: Node, point: Vector2) -> String:
	var rooms := root.get_node_or_null("CameraRooms")
	if rooms != null:
		for room: Node in rooms.get_children():
			if Rect2((room as Node2D).position, room.get(&"size")).has_point(point):
				return str(room.name)
	return "(none)"


## Teleports the slime (its centre at `centre`) and sets its height level to the ground there, as a
## walk onto that ground would (a teleport alone keeps the level it had: onto the gallery or a ledge
## the slime would be under it).
func _teleport(t: TestContext, centre: Vector2) -> void:
	t.teleport_player(centre)
	var elevation: Node = t.world().elevation
	if elevation != null:
		elevation.call(&"track", t.player_body())


## Every placed enemy's enemy stops (its processing off): no spit, no chase, no grab.
func _hold_enemies(t: TestContext) -> void:
	for node: Node in t.tree.get_nodes_in_group(&"placed_enemy"):
		var enemy: Node = node.call(&"get_enemy") if is_instance_valid(node) else null
		if enemy != null:
			enemy.process_mode = Node.PROCESS_MODE_DISABLED


## The standing placed enemies in `rect` (their enemies).
func _enemies_in(t: TestContext, rect: Rect2) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in t.tree.get_nodes_in_group(&"placed_enemy"):
		if not is_instance_valid(node) or not rect.has_point((node as Node2D).global_position):
			continue
		var enemy: Node = node.call(&"get_enemy")
		if enemy != null and bool(node.call(&"is_standing")):
			out.append(enemy)
	return out


## A plain hit of `amount` (true damage) on the receiver of `area` (tests/test_dungeon_kit.gd).
func _hit(t: TestContext, area: Area2D, amount: float) -> void:
	if area == null:
		t.fail("no hurtbox to hit")
		return
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	router.route({"activation_id": activation, "source": source, "attack_area": attack, "target_area": area,
		"weapon_id": "test-hit", "weapon_tags": ["weapon"], "damage_types": ["physical"], "base_damage": amount,
		"true_damage": true, "effects": [], "impact": {"position": area.global_position, "knock": Vector2.UP}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()


func _room_at(t: TestContext, feet: Vector2) -> String:
	var rooms: Node = t.world().world_root.get_node_or_null("CameraRooms")
	if rooms == null:
		return ""
	for room: Node in rooms.get_children():
		if (room.call(&"rect") as Rect2).has_point(feet):
			return str(room.name)
	return "(none)"
