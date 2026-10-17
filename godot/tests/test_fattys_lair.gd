extends RefCounted
## Fatty's Lair, the Chapter 1 dungeon (docs/godot/DUNGEONS.md "Fatty's Lair (built)";
## docs/design/2026-10-16-dungeon-fattys-lair.md), built by tools/build_fattys_lair.gd: its rooms,
## the dungeon kit's pieces as placed (keys equal keyholes, the hidden big chest, the boss door, a
## hazard under every slab), the open gaps of the main path, and the Lair's own pieces: the eye
## latches (the Spear only; the alcove's pair shut together), the drop gate and its worm lever, the
## inner winch that holds the outer gate up, the plank barricade (the Heavy Roll), Burr's cell (two
## keys) opening the Inner Stair, the stair's walk-in, Fatty's phase two (a thrown clod dizzies
## him, the Spear lands only then) with the arena's shutters, the Pearl and the Heavy skin, and the
## way in and out in level-1-d4 (the gate, the bolt-hole's mouth, Burr waiting after Fatty). Burr's
## call and the drawbridge (the kit's winch) are walked too.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const HeavyCheck := preload("res://game/fattys_lair/heavy_check.gd")
const LairDirector := preload("res://game/fattys_lair/lair_director.gd")

const MAP_ID := "fatty-lair"
const OUTSIDE := "level-1-d4"
const CELL := 64.0
## Each room's top-left cell (tools/build_fattys_lair.gd ROOMS, 16 x 14 cells a room).
const ORIGINS := {
	"r1": Vector2(32, 56), "r2": Vector2(48, 56), "hub": Vector2(32, 42), "r4": Vector2(16, 42),
	"r5": Vector2(16, 56), "r6": Vector2(64, 42), "r7": Vector2(64, 56), "r8": Vector2(16, 14),
	"r9": Vector2(0, 14), "r10": Vector2(0, 0), "r11": Vector2(32, 28), "r12": Vector2(32, 14),
	"r13": Vector2(48, 28), "r14": Vector2(48, 14), "bolt": Vector2(48, 0),
}
const ROOMS: PackedStringArray = ["r10-dung-roller-run", "bolt-hole", "r9-watcher-hall", "r8-guard-crypt",
	"r12-larder", "r14-pearl-shrine", "old-armoury", "r11-drop-gate-bridge", "r13-fattys-arena",
	"glow-moss-burrow", "map-nook", "r4-squint-den", "r3-pit-hall", "r6-pipe-gallery", "sally-port",
	"r5-eye-hall", "r1-gatehouse", "r2-slab-steps", "r7-bell-bridge"]
## The open gaps (no lock in them): [room, the slime's feet in the room's cells, the way, the room
## it ends in]. The locked ones (the bolts, the key doors, the latches, the drop gate, the slabs, the
## shutters, the barricade) are tested with their pieces.
const WALKS := [
	["r1", Vector2(14.0, 11.0), &"move_right", "r2-slab-steps"],
	["r2", Vector2(8.0, 3.6), &"move_up", "r3-pit-hall"],
	["hub", Vector2(1.6, 10.0), &"move_left", "r4-squint-den"],
	["r4", Vector2(8.0, 12.2), &"move_down", "r5-eye-hall"],
	["hub", Vector2(30.4, 7.0), &"move_right", "r6-pipe-gallery"],
	["r6", Vector2(8.0, 12.2), &"move_down", "r7-bell-bridge"],
	["r6", Vector2(8.0, 3.6), &"move_up", "glow-moss-burrow"],
	["r8", Vector2(1.6, 7.0), &"move_left", "r9-watcher-hall"],
	["r8", Vector2(1.6, 21.0), &"move_left", "old-armoury"],
	["r11", Vector2(12.0, 3.6), &"move_up", "r12-larder"],
]
const WALK_MS := 2600.0


func test_the_lair_loads_with_its_rooms_and_the_kit(t: TestContext) -> void:
	if not await _enter(t):
		return
	var root: Node2D = t.world().world_root
	t.check(t.world().elevation != null, "the Lair has no elevation")
	var rooms := root.get_node_or_null("CameraRooms")
	if t.check(rooms != null, "the Lair has no CameraRooms"):
		t.equal(rooms.get_child_count(), ROOMS.size(), "camera rooms")
		for room_name in ROOMS:
			t.check(rooms.get_node_or_null(NodePath(room_name)) != null, "no camera room " + room_name)
	var dungeon := root.get_node_or_null("Dungeon")
	if t.check(dungeon != null, "no Dungeon node"):
		t.equal(str(dungeon.get(&"dungeon_id")), MAP_ID, "dungeon id")
		t.check(DungeonState.is_inside(Services.run()), "the Lair does not count as inside a dungeon")
	var entrance := _door(t, "fatty-lair-entrance")
	if t.check(entrance != null, "no entrance door"):
		t.equal([str(entrance.get(&"target_area_id")), str(entrance.get(&"target_door_id")), str(entrance.get(&"side"))],
			[OUTSIDE, "fatty-lair-mouth", "south"], "the entrance leads to D4's gate")
	var bolt := _door(t, "fatty-lair-bolt-hole")
	if t.check(bolt != null, "no bolt-hole door"):
		t.equal([str(bolt.get(&"target_area_id")), str(bolt.get(&"target_door_id")), str(bolt.get(&"side"))],
			[OUTSIDE, "fatty-lair-bolt-hole-mouth", "north"], "the bolt-hole leads to D4's mouth")
	# Keys equal keyholes: two on the floor and one in a chest, two keyholes in Burr's door, one in door 3.
	var objects := _objects(t)
	var keys := 0
	var keyholes := 0
	for node: Node in objects.get_children():
		if str(node.get(&"item")) == "small-key":
			keys += 1
		var chest := node.get_node_or_null(^"ChestScript")
		if chest != null:
			keys += int((chest.get(&"initial_contents") as Dictionary).get("dungeon-small-key", 0))
		if node.get(&"keyholes") != null and str(node.get(&"lock")) == "small":
			keyholes += int(node.get(&"keyholes"))
	t.equal(keys, 3, "small keys")
	t.equal(keyholes, 3, "small-key keyholes")
	var big := objects.get_node_or_null(^"r12-big-chest/ChestScript")
	if t.check(big != null, "no big chest"):
		t.check(bool(big.get(&"hidden")), "the big chest is not hidden until the Larder's fight")
		t.equal(int((big.get(&"initial_contents") as Dictionary).get("dungeon-big-key", 0)), 1, "the big key")
	var boss_door := objects.get_node_or_null(^"hub-boss-door")
	t.check(boss_door != null and str(boss_door.get(&"lock")) == "big", "the boss door does not want the big key")
	# Every slab lies over a hazard (a fall goes back to the rim).
	var hazards: Array[Rect2] = []
	for node: Node in root.get_node("Hazards").get_children():
		hazards.append(node.call(&"rect") as Rect2)
	t.check(not hazards.is_empty(), "no hazards")
	var slabs := 0
	for node: Node in objects.get_children():
		if str(node.name).contains("-slab-"):
			slabs += 1
			var over := false
			for rect in hazards:
				if rect.has_point((node as Node2D).global_position + Vector2(CELL, CELL) * 0.5):
					over = true
			t.check(over, "%s is over no hazard" % node.name)
	t.equal(slabs, 24, "falling slabs")


func test_the_open_gaps_of_the_main_path_can_be_walked_through(t: TestContext) -> void:
	if not await _enter(t):
		return
	for walk: Array in WALKS:
		_stand(t, _at(walk[0], walk[1]))
		await t.steps(4)
		t.press(walk[2])
		var ended := await t.until(func() -> bool: return _room_at(t) == walk[3], WALK_MS)
		t.release(walk[2])
		t.check(ended, "walking %s from %s %s did not reach %s (in %s)" % [walk[2], walk[0], walk[1], walk[3], _room_at(t)])
		await t.steps(4)


func test_burr_calls_the_first_time_the_slime_comes_into_the_pit_hall(t: TestContext) -> void:
	if not await _enter(t, true):
		return
	var run := Services.run()
	t.check(not run.has_flag(LairDirector.FLAG_CALLED), "Burr's call is heard before the Pit Hall")
	_stand(t, _at("hub", Vector2(14.0, 11.0)))
	var called := await t.until(func() -> bool:
		var box := _box(t)
		return box != null and bool(box.call(&"is_open")), 2000.0)
	t.check(called, "Burr did not call out")
	await _close_dialogues(t, func() -> bool: return run.has_flag(LairDirector.FLAG_CALLED), 4000.0)
	t.check(run.has_flag(LairDirector.FLAG_CALLED), "Burr's call is not kept")


func test_the_winch_lowers_the_drawbridge_and_the_slime_walks_across(t: TestContext) -> void:
	if not await _enter(t):
		return
	var bridge := _objects(t).get_node("hub-drawbridge")
	t.check(not bool(bridge.call(&"is_lowered")), "the drawbridge starts down")
	var winch := _objects(t).get_node("hub-drawbridge-winch") as Node2D
	_stand(t, winch.global_position + Vector2(-72.0, -4.0))
	await t.steps(4)
	t.press(&"move_right")
	var lowered := await t.until(func() -> bool: return bool(bridge.call(&"is_lowered")), 3000.0)
	t.release(&"move_right")
	t.check(lowered, "pushing the winch did not lower the drawbridge")
	await t.sim_wait(1000.0)
	_stand(t, _at("hub", Vector2(16.0, 4.5)))
	await t.steps(4)
	t.press(&"move_down")
	var across := await t.until(func() -> bool: return t.player_body().global_position.y > _at("hub", Vector2(0.0, 10.2)).y, 3000.0)
	t.release(&"move_down")
	t.check(across, "the slime did not walk across the drawbridge (feet at %s)" % str(t.player_body().global_position / CELL))


func test_an_eye_latch_takes_only_the_spear_and_opens_its_door_for_good(t: TestContext) -> void:
	if not await _enter(t):
		return
	var latch := _objects(t).get_node("r5-latch-inner")
	var door := _objects(t).get_node("r5-inner-door/GateScript")
	_route(t, latch.get(&"area"), ["roll"])
	_route(t, latch.get(&"area"), ["thrown", "clay-pot"])
	await t.steps(2)
	t.check(not bool(latch.call(&"is_shut")), "a roll or a thrown pot shut the eye")
	t.check(not bool(door.call(&"is_open")), "the door opened without the Spear")
	_route(t, latch.get(&"area"), ["spear", "weapon"])
	await t.steps(4)
	t.check(bool(latch.call(&"is_shut")) and bool(latch.call(&"is_solved")), "the Spear did not shut the eye for good")
	t.check(bool(door.call(&"is_open")), "the door did not open")
	await t.sim_wait(4000.0)
	t.check(bool(latch.call(&"is_shut")), "the first latch opened its eye again")


func test_the_alcove_latches_must_be_shut_together(t: TestContext) -> void:
	if not await _enter(t):
		return
	var a := _objects(t).get_node("r5-latch-a")
	var b := _objects(t).get_node("r5-latch-b")
	var door := _objects(t).get_node("r5-alcove-door/GateScript")
	_route(t, a.get(&"area"), ["spear", "weapon"])
	await t.steps(2)
	t.check(bool(a.call(&"is_shut")), "the first thrust did not shut latch a")
	await t.sim_wait(3400.0)
	t.check(not bool(a.call(&"is_shut")), "latch a stayed shut past its 3 s")
	t.check(not bool(door.call(&"is_open")), "one latch alone opened the alcove")
	_route(t, a.get(&"area"), ["spear", "weapon"])
	await t.sim_wait(600.0)
	_route(t, b.get(&"area"), ["spear", "weapon"])
	await t.steps(4)
	t.check(bool(a.call(&"is_solved")) and bool(b.call(&"is_solved")), "both latches shut at once did not solve")
	t.check(bool(door.call(&"is_open")), "the alcove's door did not open")
	await t.sim_wait(3400.0)
	t.check(bool(a.call(&"is_shut")) and bool(b.call(&"is_shut")), "a solved latch opened again")


func test_the_drop_gate_rises_on_its_lever_and_drops_again(t: TestContext) -> void:
	if not await _enter(t):
		return
	var gate := _objects(t).get_node("r11-drop-gate")
	var lever := gate.get_node("Lever")
	t.equal(str(gate.call(&"state_name")), "shut", "the gate at first")
	t.check(bool(lever.call(&"can_use")), "the lever is not offered")
	t.check(bool(lever.call(&"use")), "the lever did nothing")
	t.check(not bool(lever.call(&"can_use")), "the lever is offered while the gate rises")
	await t.sim_wait(float(gate.get(&"rise_ms")) + 50.0)
	t.check(bool(gate.call(&"is_open")), "the gate is not up after its rise")
	await t.sim_wait(float(gate.get(&"open_ms")) + float(gate.get(&"drop_ms")) + 100.0)
	t.equal(str(gate.call(&"state_name")), "shut", "the gate after its moment up")
	t.check(bool(lever.call(&"can_use")), "the lever is not offered again")


func test_the_inner_winch_holds_the_outer_gate_up_for_good(t: TestContext) -> void:
	if not await _enter(t):
		return
	var run := Services.run()
	var winch := _objects(t).get_node("r1-gate-winch")
	t.check(not run.is_gate_unlocked(OUTSIDE, "fatty-lair-gate"), "the outer gate starts held")
	t.check(bool(winch.call(&"can_use")), "the winch is not offered")
	t.check(bool(winch.call(&"use")), "the winch did nothing")
	t.check(run.is_gate_unlocked(OUTSIDE, "fatty-lair-gate"), "the winch did not hold the outer gate")
	t.check(not bool(winch.call(&"can_use")), "the winch is offered again")
	if not await _travel(t, OUTSIDE):
		return
	var gate := t.world().world_root.get_node_or_null("FattysLair/fatty-lair-mouth/drop-gate")
	if t.check(gate != null, "D4 has no Lair gate"):
		t.check(bool(gate.call(&"is_held")) and bool(gate.call(&"is_open")), "the outer gate is not up for good")


func test_the_plank_barricade_breaks_only_to_a_heavy_roll(t: TestContext) -> void:
	if not await _enter(t):
		return
	var run := Services.run()
	var shrine := _objects(t).get_node("r14-barricade")
	var area := shrine.get_node("DamageArea") as Area2D
	_route(t, area, ["roll"])
	_route(t, area, ["spear", "weapon"])
	_route(t, area, ["thrown", "clay-pot"])
	await t.steps(2)
	t.check(not bool(shrine.call(&"is_smashed")), "a plain roll, a thrust or a pot smashed the planks")
	run.set_flag(HeavyCheck.SKIN_FLAG)
	_route(t, area, ["roll"])
	await t.steps(2)
	t.check(bool(shrine.call(&"is_smashed")), "the Heavy skin's roll did not smash the planks")
	t.check(run.has_flag("fatty-lair.bolt-hole-smashed"), "the smash is not kept")
	# The Stone form's roll (tagged heavy) is the Heavy check too.
	var store := _objects(t).get_node("r1-store-barricade")
	_route(t, store.get_node("DamageArea") as Area2D, ["roll", "heavy"])
	await t.steps(2)
	t.check(bool(store.call(&"is_smashed")), "a heavy roll did not smash the store's planks")


func test_burrs_cell_takes_two_keys_and_opens_the_inner_stair(t: TestContext) -> void:
	if not await _enter(t):
		return
	var run := Services.run()
	var hatch := _lair(t, "inner-stair")
	t.check(not bool(hatch.call(&"is_open")), "the Inner Stair starts open")
	DungeonState.add_small_key(run, MAP_ID, 2)
	_stand(t, _at("hub", Vector2(2.0, 8.9)))
	await t.steps(4)
	t.press(&"move_up")
	var opened := await t.until(func() -> bool:
		return bool(_objects(t).get_node("hub-burr-cell-door").call(&"is_open")), 4000.0)
	t.release(&"move_up")
	t.check(opened, "two keys did not open Burr's door")
	t.equal(DungeonState.small_keys(run, MAP_ID), 0, "keys left")
	await _close_dialogues(t, func() -> bool: return run.has_flag(LairDirector.FLAG_FREED), 8000.0)
	t.check(run.has_flag(LairDirector.FLAG_FREED), "Burr was not freed")
	t.check(bool(hatch.call(&"is_open")), "Burr did not open the Inner Stair")
	t.check(run.has_flag("fatty-lair.inner-stair-open"), "the open stair is not kept")
	await t.steps(10)
	# Walking into the open stair takes the slime down to the Crypt.
	_stand(t, _at("hub", Vector2(2.0, 11.3)))
	await t.steps(4)
	t.press(&"move_down")
	var down := await t.until(func() -> bool: return _room_at(t) == "r8-guard-crypt", 4000.0)
	t.release(&"move_down")
	t.check(down, "the Inner Stair did not lead down to the Crypt (in %s)" % _room_at(t))


func test_fatty_in_phase_two_is_dizzied_by_a_throw_then_takes_the_spear(t: TestContext) -> void:
	if not await _enter(t):
		return
	var camp := _lair(t, "fatty-camp").get_node("BossCampScript")
	_stand(t, _at("r13", Vector2(8.0, 11.5)))
	if not t.check(await t.until(func() -> bool: return bool(camp.call(&"has_live_boss")), 2000.0), "Fatty did not come"):
		return
	var fatty: Node = camp.call(&"get_live_boss")
	var south := _objects(t).get_node("r13-shutter-south")
	await t.steps(4)
	t.check(bool(south.call(&"is_shut")), "the arena's shutter did not shut")
	# The slime is kept alive and out of his reach while the fight goes on (his contact hops and
	# landings would end it); Fatty is read from the camp each step.
	# Phase one: thrusts (refused only while he hops or flies) until he is under half his health.
	var max_hp := float(fatty.get(&"max_health"))
	var two := await t.until(func() -> bool:
		var boss: Node = camp.call(&"get_live_boss")
		_keep_safe(t, boss)
		if boss == null:
			return false
		if _hp(boss) > max_hp * 0.45:
			_route(t, boss.get(&"damage_area"), ["spear", "weapon"])
		return bool(boss.call(&"is_in_phase_two")), 12000.0)
	if not t.check(two, "below half his health Fatty is not in phase two"):
		return
	var chasing := await t.until(func() -> bool:
		var boss: Node = camp.call(&"get_live_boss")
		_keep_safe(t, boss)
		return boss != null and str(boss.call(&"get_phase")) == "chase", 8000.0)
	if not t.check(chasing, "Fatty does not chase again in phase two"):
		return
	fatty = camp.call(&"get_live_boss")
	var hp := _hp(fatty)
	_route(t, fatty.get(&"damage_area"), ["spear", "weapon"])
	t.near(_hp(fatty), hp, 0.01, "a thrust before the dizzy landed")
	_route(t, fatty.get(&"damage_area"), ["thrown", "mud-ball"])
	t.check(bool(fatty.call(&"is_dizzy")), "a thrown clod did not dizzy him")
	_route(t, fatty.get(&"damage_area"), ["spear", "weapon"])
	t.check(_hp(fatty) < hp, "the Spear did not land while he was dizzy")
	# The rest of his health: a throw to dizzy him, thrusts while he is dizzy, until he falls.
	var beaten := await t.until(func() -> bool:
		if "fatty-one-eye" in (Services.run().world.get("defeated_boss_ids", []) as Array):
			return true
		var boss: Node = camp.call(&"get_live_boss")
		_keep_safe(t, boss)
		if boss == null or bool(boss.call(&"is_defeated")):
			return false
		if bool(boss.call(&"is_dizzy")):
			_route(t, boss.get(&"damage_area"), ["spear", "weapon"])
		elif str(boss.call(&"get_phase")) == "chase":
			_route(t, boss.get(&"damage_area"), ["thrown", "mud-ball"])
		return false, 20000.0)
	t.check(beaten, "Fatty's fall is not kept")
	await t.sim_wait(1200.0)
	t.check(not bool(south.call(&"is_shut")), "the arena's shutter did not open after his fall")
	t.check(DungeonState.is_boss_beaten(Services.run(), MAP_ID, "fatty-one-eye"), "the dungeon does not know he fell")
	var pearl := _lair(t, "pearl-1")
	t.check(await t.until(func() -> bool: return bool(pearl.call(&"is_shown")), 1500.0), "the Pearl did not rise")


func test_the_pearl_grants_the_heavy_skin(t: TestContext) -> void:
	if not await _enter(t):
		return
	var run := Services.run()
	var pearl := _lair(t, "pearl-1")
	await t.steps(4)
	t.check(not bool(pearl.call(&"is_shown")), "the Pearl shows before Fatty falls")
	(run.world.get_or_add("defeated_boss_ids", []) as Array).append("fatty-one-eye")
	t.check(await t.until(func() -> bool: return bool(pearl.call(&"is_shown")), 1500.0), "the Pearl did not rise")
	t.check(not HeavyCheck.has_skin(), "the Heavy skin before the Pearl")
	t.teleport_player(pearl.global_position)
	t.check(await t.until(func() -> bool: return bool(pearl.call(&"is_taken")), 1500.0), "walking into the Pearl did not take it")
	t.check(run.has_flag("pearl.fatty-one-eye"), "the Pearl's flag")
	t.check(HeavyCheck.has_skin(), "the Pearl did not grant the Heavy skin")


func test_the_way_in_and_out_in_fattys_hollow(t: TestContext) -> void:
	if not await _travel(t, OUTSIDE):
		return
	var run := Services.run()
	var holder := t.world().world_root.get_node_or_null("FattysLair")
	if not t.check(holder != null, "D4 has no FattysLair holder"):
		return
	var mouth := _door(t, "fatty-lair-mouth")
	if t.check(mouth != null, "no Lair mouth"):
		t.equal([str(mouth.get(&"target_area_id")), str(mouth.get(&"target_door_id")), str(mouth.get(&"side"))],
			[MAP_ID, "fatty-lair-entrance", "north"], "the mouth leads to R1")
	var gate := holder.get_node("fatty-lair-mouth/drop-gate")
	t.check(not bool(gate.call(&"is_open")), "the outer gate starts open")
	t.check(bool(gate.get_node("Lever").call(&"use")), "the outer lever did nothing")
	await t.sim_wait(float(gate.get(&"rise_ms")) + 50.0)
	t.check(bool(gate.call(&"is_open")), "the outer gate did not rise")
	var bolt := _door(t, "fatty-lair-bolt-hole-mouth")
	if t.check(bolt != null, "no bolt-hole mouth"):
		t.equal(str(bolt.get(&"target_area_id")), "", "the bolt-hole's mouth leads back down")
		t.equal(str(bolt.get(&"side")), "south", "the bolt-hole's mouth side")
	var burr := holder.get_node("burr-outside")
	t.check(not bool(burr.call(&"is_waiting")), "Burr waits before he is freed")
	t.check(not (burr as Node2D).visible, "Burr shows before he is freed")
	run.set_flag(LairDirector.FLAG_FREED)
	(run.world.get_or_add("defeated_boss_ids", []) as Array).append("fatty-one-eye")
	t.check(bool(burr.call(&"is_waiting")), "Burr does not wait after Fatty")
	t.check(bool(burr.call(&"use")), "talking to Burr did nothing")
	await _close_dialogues(t, func() -> bool: return run.has_flag("fatty-lair.burr-outside"), 6000.0)
	t.check(run.has_flag("fatty-lair.burr-outside"), "Burr's talk is not kept")
	t.check(not bool(burr.call(&"is_waiting")), "Burr still waits after the talk")


# --- helpers ------------------------------------------------------------------------------------

## Into the Lair. Burr's first call is marked heard (`burr_calls`: not), so the Pit Hall's
## dialogue does not hold the slime.
func _enter(t: TestContext, burr_calls: bool = false) -> bool:
	if not burr_calls:
		Services.run().set_flag(LairDirector.FLAG_CALLED)
	return await _travel(t, MAP_ID)


func _travel(t: TestContext, map_id: String) -> bool:
	if not t.in_world(map_id):
		t.main.call(&"travel_to", map_id)
	var arrived := await t.until(func() -> bool:
		return t.in_world(map_id) and t.player_body() != null and not bool(t.main.call(&"is_transitioning")), 10000.0)
	await t.steps(8)
	return t.check(arrived, "could not travel to " + map_id)


static func _at(room: String, cell: Vector2) -> Vector2:
	return (ORIGINS[room] + cell) * CELL


func _objects(t: TestContext) -> Node:
	return t.world().world_root.get_node("Objects")


func _lair(t: TestContext, node_name: String) -> Node2D:
	return t.world().world_root.get_node("Lair/" + node_name) as Node2D


func _door(t: TestContext, door_id: String) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"door"):
		if str(node.get(&"door_id")) == door_id and t.world().world_root.is_ancestor_of(node):
			return node
	return null


## Puts the slime's feet at `feet` and takes its level there.
func _stand(t: TestContext, feet: Vector2) -> void:
	var player := t.player()
	var body := t.player_body()
	var offset := body.global_position - player.get_centre()
	player.teleport(feet - offset)
	if t.world().elevation != null:
		t.world().elevation.track(body)
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()


func _room_at(t: TestContext) -> String:
	var rooms: Node = t.world().world_root.get_node_or_null("CameraRooms")
	if rooms == null or t.player_body() == null:
		return ""
	var feet := t.player_body().global_position
	for room: Node in rooms.get_children():
		if (room.call(&"rect") as Rect2).has_point(feet):
			return str(room.name)
	return "(none)"


## Fatty's fight: the slime healed, and moved to the arena's corner across from him when he comes
## near (a test of his phase two, not of dodging him).
func _keep_safe(t: TestContext, boss: Node) -> void:
	var player := t.player()
	if player == null:
		return
	player.restore_run_state({"hp": player.get_max_hp()})
	if boss == null:
		return
	var at: Vector2 = boss.call(&"get_centre")
	if at.distance_to(player.get_centre()) > 240.0:
		return
	var middle := _at("r13", Vector2(8.0, 8.0))
	var away := middle - at
	_stand(t, middle + Vector2(340.0 if away.x >= 0.0 else -340.0, 220.0 if away.y >= 0.0 else -220.0))


static func _hp(enemy: Object) -> float:
	return float((enemy.call(&"get_damage_state") as Dictionary).get("hp", -1.0))


func _box(t: TestContext) -> Node:
	return t.tree.get_first_node_in_group(&"dialogue_box")


## Closes every conversation that opens (finished) until `done` or `real_ms` of real time.
func _close_dialogues(t: TestContext, done: Callable, real_ms: float) -> void:
	var started := float(Time.get_ticks_msec())
	while float(Time.get_ticks_msec()) - started < real_ms:
		if bool(done.call()):
			return
		var box := _box(t)
		if box != null and bool(box.call(&"is_open")):
			box.call(&"close", true)
		await t.tree.physics_frame


## A hit of 20 with `tags` on `area` from a stand-in source (the barred gate tests' way).
func _route(t: TestContext, area: Area2D, tags: Array) -> void:
	if not t.check(area != null, "no area to hit"):
		return
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var areas: Array[Area2D] = [attack]
	var activation := router.begin_activation(source, areas)
	router.route({"activation_id": activation, "source": source, "attack_area": attack, "target_area": area,
		"weapon_id": "test-" + str(tags[0]), "weapon_tags": tags, "damage_types": ["physical"], "base_damage": 20.0,
		"effects": [], "impact": {"position": area.global_position, "knock": Vector2.UP}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()
