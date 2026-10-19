extends RefCounted
## Fatty's Lair, the Chapter 1 dungeon (docs/godot/DUNGEONS.md "Fatty's Lair (built)";
## docs/design/2026-10-16-dungeon-fattys-lair.md and, since 2026-10-17, the Pearl inside it:
## docs/design/2026-10-17-pearl-mid-dungeon.md). Since 2026-10-18 every room is its own world
## (docs/godot/DUNGEON_ROOMS.md; its doors and records: test_lair_rooms.gd): its rooms, the dungeon
## kit's pieces as placed (keys equal keyholes, the hidden big chest in R9, the boss door, a hazard
## under every slab, the two seals), the open gaps of the main path, and the Lair's own pieces: the
## eye latches (the Spear only; the alcove's pair shut together), the drop gate and its worm lever,
## the inner winch that holds the outer gate up, the plank barricades (the Heavy Roll), Burr's cell
## (two keys) opening the Inner Stair, the stair's walk-in; the Pearl room (the Larder's Big Squint
## guards Pearl 1, its take grants the Heavy skin and seals the Lair); the second half's Heavy locks
## (the Weigh House's two plates, R10's plate held by a statue, R9's plate raising the big chest, the
## hub's counterweight plate lowering the drawbridge, heavy blocks back when their room is entered
## again); Fatty's phase two, the Heavy exam (a Heavy Roll knocks him off balance, a thrown clod only
## splats, the Spear lands only while he is off balance) with the arena's shutter, his fall breaking
## the seals; and the way in and out: the gate on level-1-d5's hill, the bolt-hole's mouth in
## level-1-d4 with Burr waiting after Fatty. Burr's call is walked too.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const HeavyCheck := preload("res://game/fattys_lair/heavy_check.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const LairDirector := preload("res://game/fattys_lair/lair_director.gd")

## The Lair's dungeon id and R1's world (the way in).
const MAP_ID := "fatty-lair"
## The way out (the bolt-hole's mouth, Burr) and the way in (the drop gate, the mouth).
const OUTSIDE := "level-1-d4"
const ENTRANCE := "level-1-d5"
const CELL := 64.0
const ROOMS_DIR := "res://game/scenes/worlds/rooms/fatty-lair/"
## Each room's world (the rooms' short names, as the design names them).
const WORLDS := {
	"r1": "fatty-lair", "r2": "fatty-lair-r2-slab-steps", "hub": "fatty-lair-r3-pit-hall",
	"r4": "fatty-lair-r4-squint-den", "r5": "fatty-lair-r5-eye-hall", "r5-lower": "fatty-lair-r5-lower-hall",
	"r6": "fatty-lair-r6-pipe-gallery", "r7": "fatty-lair-r7-bell-bridge", "r8": "fatty-lair-r8-guard-crypt",
	"r9": "fatty-lair-r9-watcher-hall", "r10": "fatty-lair-r10-dung-roller-run", "r11": "fatty-lair-r11-drop-gate-bridge",
	"r12": "fatty-lair-r12-larder", "r13": "fatty-lair-r13-fattys-arena", "r14": "fatty-lair-r14-postern",
	"bolt": "fatty-lair-bolt-hole", "weigh": "fatty-lair-c2-weigh-house",
}
## Each room's layout's top-left cell in its own world (rooms of 18 x 16 cells, each layout one
## cell in from its room's corner).
const ORIGIN := Vector2(1, 1)
const ROOMS: PackedStringArray = ["burr-cell", "r1-store", "r5-lower-hall", "r5-key-alcove", "r10-dung-roller-run", "c2-weigh-house", "bolt-hole", "r9-watcher-hall",
	"r8-guard-crypt", "r12-larder", "r14-postern", "old-armoury", "r11-drop-gate-bridge", "r13-fattys-arena",
	"glow-moss-burrow", "map-nook", "r4-squint-den", "r3-pit-hall", "r6-pipe-gallery", "sally-port",
	"r5-eye-hall", "r1-gatehouse", "r2-slab-steps", "r7-bell-bridge"]
## The Larder's mini-boss fight (Pearl 1's guard) and Fatty.
const GUARD := "fatty-lair-big-squint"
const BOSS := "fatty-one-eye"
## The open gaps (no lock in them): [room, the slime's feet in the room's cells, the way, the room
## it ends in]. Walking on through the doorway goes into the next room's world.
const WALKS := [
	["r1", Vector2(14.0, 11.0), &"move_right", "r2-slab-steps"],
	["r2", Vector2(8.0, 3.6), &"move_up", "r3-pit-hall"],
	["hub", Vector2(1.6, 10.0), &"move_left", "r4-squint-den"],
	["r4", Vector2(8.0, 12.2), &"move_down", "r5-eye-hall"],
	["hub", Vector2(30.4, 7.0), &"move_right", "r6-pipe-gallery"],
	["r6", Vector2(8.0, 12.2), &"move_down", "r7-bell-bridge"],
	["r6", Vector2(8.0, 3.6), &"move_up", "glow-moss-burrow"],
	["r8", Vector2(1.6, 21.0), &"move_left", "old-armoury"],
	# Door 3: an open doorway since 2026-10-17.
	["r8", Vector2(14.4, 25.6), &"move_right", "r11-drop-gate-bridge"],
	["r11", Vector2(12.0, 3.6), &"move_up", "r12-larder"],
	# The Weigh House's west corridor out into R10's lane.
	["weigh", Vector2(1.6, 9.0), &"move_left", "r10-dung-roller-run"],
]
const WALK_MS := 4000.0


func test_the_lair_loads_with_its_rooms_and_the_kit(t: TestContext) -> void:
	if not await _enter(t, "r1"):
		return
	var root: Node2D = t.world().world_root
	var dungeon := root.get_node_or_null("Dungeon")
	if t.check(dungeon != null, "no Dungeon node"):
		t.equal(str(dungeon.get(&"dungeon_id")), MAP_ID, "dungeon id")
		t.check(DungeonState.is_inside(Services.run()), "the Lair does not count as inside a dungeon")
		t.equal(str(dungeon.get(&"boss_id")), BOSS, "the Lair's seal boss")
		# The map knows every room (its layout), this world's among them.
		var names := []
		for room: Dictionary in dungeon.call(&"rooms"):
			names.append(str(room["name"]))
		for room_name in ROOMS:
			t.check(room_name in names, "the map has no room " + room_name)
	var entrance := _door(t, "fatty-lair-entrance")
	if t.check(entrance != null, "no entrance door"):
		t.equal([str(entrance.get(&"target_area_id")), str(entrance.get(&"target_door_id")), str(entrance.get(&"side"))],
			[ENTRANCE, "fatty-lair-mouth", "south"], "the entrance leads to D5's gate")
	# The rest is read from the room scenes (each its own world).
	var objects := {}
	var hazards: Array[Rect2] = []
	var slab_rooms := {}
	for room_name in ROOMS:
		var scene := (load(ROOMS_DIR + room_name + ".tscn") as PackedScene).instantiate()
		t.check(scene.get_node_or_null("world-definition") != null, "%s is not a world" % room_name)
		var holder := scene.get_node_or_null("Objects")
		if holder != null:
			for node: Node in holder.get_children():
				objects["%s/%s" % [room_name, node.name]] = node.duplicate()
		if room_name in ["r2-slab-steps", "r7-bell-bridge", "r11-drop-gate-bridge"]:
			var room_hazards: Array[Rect2] = []
			for node: Node in scene.get_node("Hazards").get_children():
				room_hazards.append(Rect2((node as Node2D).position, node.get(&"size")))
			var slabs := 0
			for node: Node in holder.get_children():
				if str(node.name).contains("-slab-"):
					slabs += 1
					var over := false
					for rect in room_hazards:
						if rect.has_point((node as Node2D).position + Vector2(CELL, CELL) * 0.5):
							over = true
					t.check(over, "%s/%s is over no hazard" % [room_name, node.name])
			slab_rooms[room_name] = slabs
		scene.free()
	var total_slabs := 0
	for n: int in slab_rooms.values():
		total_slabs += n
	t.equal(total_slabs, 24, "falling slabs")
	# Keys equal keyholes: two on the floor (R5's alcove, R7), two keyholes in Burr's door.
	var keys := 0
	var keyholes := 0
	for key: String in objects:
		var node: Node = objects[key]
		if str(node.get(&"item")) == "small-key":
			keys += 1
		var chest := node.get_node_or_null(^"ChestScript")
		if chest != null:
			keys += int((chest.get(&"initial_contents") as Dictionary).get("dungeon-small-key", 0))
		if node.get(&"keyholes") != null and str(node.get(&"lock")) == "small":
			keyholes += int(node.get(&"keyholes"))
	t.equal(keys, 2, "small keys")
	t.equal(keyholes, 2, "small-key keyholes")
	var big: Node = objects.get("r9-watcher-hall/r9-big-chest")
	if t.check(big != null, "no big chest in R9"):
		var script := big.get_node(^"ChestScript")
		t.check(bool(script.get(&"hidden")), "the big chest is not hidden until R9's plate")
		t.equal(int((script.get(&"initial_contents") as Dictionary).get("dungeon-big-key", 0)), 1, "the big key")
	var boss_door: Node = objects.get("r3-pit-hall/hub-boss-door")
	t.check(boss_door != null and str(boss_door.get(&"lock")) == "big", "the boss door does not want the big key")
	t.check(not objects.has("r3-pit-hall/hub-drawbridge-winch"), "the ledge's winch is still there")
	# The seal: in the way in and in the way out past Fatty.
	t.check(objects.has("r1-gatehouse/r1-seal") and objects.has("r13-fattys-arena/r13-seal"), "a seal is missing")
	t.check(not objects.has("r13-fattys-arena/r13-shutter-north"), "the arena's north shutter stands in the seal's doorway")
	t.check(not bool(_objects(t).get_node("r1-seal").call(&"is_shut")), "R1's seal is shut before the Pearl")
	for node: Node in objects.values():
		node.free()


func test_the_open_gaps_of_the_main_path_can_be_walked_through(t: TestContext) -> void:
	for walk: Array in WALKS:
		if not await _enter(t, walk[0]):
			return
		_stand(t, _at(walk[0], walk[1]))
		await t.steps(4)
		t.press(walk[2])
		var target := _world_of(walk[3])
		var ended := await t.until(func() -> bool: return t.in_world(target), WALK_MS)
		t.release(walk[2])
		t.check(ended, "walking %s from %s %s did not reach %s (in %s)" % [walk[2], walk[0], walk[1], walk[3], t.world().map_id()])
		await _settled(t)


func test_burr_calls_the_first_time_the_slime_comes_into_the_pit_hall(t: TestContext) -> void:
	if not await _enter(t, "r2", true):
		return
	var run := Services.run()
	t.check(not run.has_flag(LairDirector.FLAG_CALLED), "Burr's call is heard before the Pit Hall")
	if not await _enter(t, "hub", true):
		return
	_stand(t, _at("hub", Vector2(14.0, 11.0)))
	var called := await t.until(func() -> bool:
		var box := _box(t)
		return box != null and bool(box.call(&"is_open")), 2000.0)
	t.check(called, "Burr did not call out")
	await _close_dialogues(t, func() -> bool: return run.has_flag(LairDirector.FLAG_CALLED), 4000.0)
	t.check(run.has_flag(LairDirector.FLAG_CALLED), "Burr's call is not kept")


func test_the_counterweight_plate_lowers_the_drawbridge_only_with_the_heavy_skin(t: TestContext) -> void:
	if not await _enter(t, "hub"):
		return
	var bridge := _objects(t).get_node("hub-drawbridge")
	var plate := _objects(t).get_node("hub-counterweight-plate") as Node2D
	t.check(not bool(bridge.call(&"is_lowered")), "the drawbridge starts down")
	# The first visit: the light slime stands on it in vain.
	_stand(t, plate.global_position)
	await t.sim_wait(3600.0)
	t.near(float(plate.call(&"depth")), 0.0, 0.01, "the plate's depth under a light slime")
	t.check(not bool(bridge.call(&"is_lowered")), "a light slime lowered the drawbridge")
	# With the Heavy skin it sinks over 3 s and the bridge comes down for good.
	SkinState.lend(SkinState.HEAVY)
	var lowered := await t.until(func() -> bool: return bool(bridge.call(&"is_lowered")), 4500.0)
	t.check(lowered, "the sunk counterweight plate did not lower the drawbridge")
	_stand(t, _at("hub", Vector2(22.0, 11.5)))
	await t.sim_wait(5600.0)
	t.check(bool(bridge.call(&"is_lowered")), "the bridge rose again with the plate")
	_stand(t, _at("hub", Vector2(16.0, 4.5)))
	await t.steps(4)
	t.press(&"move_down")
	var across := await t.until(func() -> bool: return t.player_body().global_position.y > _at("hub", Vector2(0.0, 10.2)).y, 3000.0)
	t.release(&"move_down")
	t.check(across, "the slime did not walk across the drawbridge (feet at %s)" % str(t.player_body().global_position / CELL))


func test_an_eye_latch_takes_only_the_spear_and_opens_its_door_for_good(t: TestContext) -> void:
	if not await _enter(t, "r5"):
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
	# The lower hall (its own world) finds its side of the door open.
	if not await _enter(t, "r5-lower"):
		return
	t.check(bool(_objects(t).get_node("r5-inner-door/GateScript").call(&"is_open")), "the lower hall's side of the inner door is shut")


func test_the_alcove_latches_must_be_shut_together(t: TestContext) -> void:
	if not await _enter(t, "r5-lower"):
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
	if not await _enter(t, "r11"):
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
	if not await _enter(t, "r1"):
		return
	var run := Services.run()
	var winch := _objects(t).get_node("r1-gate-winch")
	t.check(not run.is_gate_unlocked(ENTRANCE, "fatty-lair-gate"), "the outer gate starts held")
	t.check(bool(winch.call(&"can_use")), "the winch is not offered")
	t.check(bool(winch.call(&"use")), "the winch did nothing")
	t.check(run.is_gate_unlocked(ENTRANCE, "fatty-lair-gate"), "the winch did not hold the outer gate")
	t.check(not bool(winch.call(&"can_use")), "the winch is offered again")
	if not await _travel(t, ENTRANCE):
		return
	var gate := t.world().world_root.get_node_or_null("FattysLair/fatty-lair-mouth/drop-gate")
	if t.check(gate != null, "D5 has no Lair gate"):
		t.check(bool(gate.call(&"is_held")) and bool(gate.call(&"is_open")), "the outer gate is not up for good")


func test_the_plank_barricade_breaks_only_to_a_heavy_roll(t: TestContext) -> void:
	if not await _enter(t, "r14"):
		return
	var run := Services.run()
	var shrine := _objects(t).get_node("r14-barricade")
	var area := shrine.get_node("DamageArea") as Area2D
	_route(t, area, ["roll"])
	_route(t, area, ["spear", "weapon"])
	_route(t, area, ["thrown", "clay-pot"])
	await t.steps(2)
	t.check(not bool(shrine.call(&"is_smashed")), "a plain roll, a thrust or a pot smashed the planks")
	SkinState.lend(SkinState.HEAVY)
	_route(t, area, ["roll"])
	await t.steps(2)
	t.check(bool(shrine.call(&"is_smashed")), "the Heavy skin's roll did not smash the planks")
	t.check(run.has_flag("fatty-lair.bolt-hole-smashed"), "the smash is not kept")
	# A Roll's bonk tagged heavy (what the Roll sends with the Heavy skin on) smashes them too: R1's
	# store, found by its record (the owner repainted it as a barricade tile, which renamed the node).
	if not await _enter(t, "r1"):
		return
	var store: Node = null
	for node: Node in _objects(t).get_children():
		if str(node.get(&"flag_id")) == "fatty-lair.store-smashed":
			store = node
	if not t.check(store != null, "no barricade keeps the store's record"):
		return
	_route(t, store.get_node("DamageArea") as Area2D, ["roll", "heavy"])
	await t.steps(2)
	t.check(bool(store.call(&"is_smashed")), "a heavy roll did not smash the store's planks")


## The Heavy skin's first lock: the Larder's north doorway, nailed shut, right by the Pearl. A
## Heavy Roll smashes it and the slime walks on into the Weigh House.
func test_the_larders_barricade_is_the_heavy_skins_first_lock(t: TestContext) -> void:
	if not await _enter(t, "r12"):
		return
	var barricade := _objects(t).get_node("r12-barricade")
	var area := barricade.get_node("DamageArea") as Area2D
	_route(t, area, ["roll"])
	await t.steps(2)
	t.check(not bool(barricade.call(&"is_smashed")), "a plain roll smashed the Larder's planks")
	_stand(t, _at("r12", Vector2(11.0, 4.6)))
	await t.steps(4)
	t.press(&"move_up")
	await t.sim_wait(1200.0)
	t.release(&"move_up")
	t.check(t.in_world(WORLDS["r12"]), "the slime walked through the nailed doorway")
	SkinState.lend(SkinState.HEAVY)
	_route(t, area, ["roll", "heavy"])
	await t.steps(4)
	t.check(bool(barricade.call(&"is_smashed")), "a Heavy Roll did not smash the Larder's planks")
	t.check(Services.run().has_flag("fatty-lair.larder-smashed"), "the smash is not kept")
	_stand(t, _at("r12", Vector2(11.0, 4.6)))
	await t.steps(4)
	t.press(&"move_up")
	var through := await t.until(func() -> bool: return t.in_world(WORLDS["weigh"]), WALK_MS)
	t.release(&"move_up")
	t.check(through, "the slime did not walk through the smashed doorway into the Weigh House (in %s)" % t.world().map_id())


func test_burrs_cell_takes_two_keys_and_opens_the_inner_stair(t: TestContext) -> void:
	if not await _enter(t, "hub"):
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
	# Walking into the open stair takes the slime down to the Crypt (its own world).
	_stand(t, _at("hub", Vector2(2.0, 11.3)))
	await t.steps(4)
	t.press(&"move_down")
	var down := await t.until(func() -> bool: return t.in_world(WORLDS["r8"]), 4000.0)
	t.release(&"move_down")
	t.check(down, "the Inner Stair did not lead down to the Crypt (in %s)" % t.world().map_id())
	await _settled(t)
	# Its ladder brings the slime back up (the second half's way back to the hub, from R9's bolt).
	await t.sim_wait(1200.0)
	_stand(t, _at("r8", Vector2(2.5, 26.7)))
	await t.steps(4)
	t.press(&"move_up")
	var up := await t.until(func() -> bool: return t.in_world(WORLDS["hub"]), 4000.0)
	t.release(&"move_up")
	t.check(up, "the crypt's ladder did not lead back up to the hub (in %s, feet at %s)" % [t.world().map_id(), str(t.player_body().global_position / CELL - ORIGIN)])


func test_fatty_in_phase_two_is_toppled_by_a_heavy_roll_then_takes_the_spear(t: TestContext) -> void:
	if not await _enter(t, "r13"):
		return
	# The Pearl was taken: the Lair is sealed while he lives.
	var dungeon := DungeonState.current(t.tree)
	t.check(bool(dungeon.call(&"seal_now", "test", false)), "the Lair did not seal")
	var seal := _objects(t).get_node("r13-seal")
	t.check(bool(seal.call(&"is_shut")), "the arena's seal is not shut after the take")
	var camp := _lair(t, "fatty-camp").get_node("BossCampScript")
	_stand(t, _at("r13", Vector2(8.0, 11.5)))
	if not t.check(await t.until(func() -> bool: return bool(camp.call(&"has_live_boss")), 2000.0), "Fatty did not come"):
		return
	var fatty: Node = camp.call(&"get_live_boss")
	var south := _objects(t).get_node("r13-shutter-south")
	await t.steps(4)
	t.check(bool(south.call(&"is_shut")), "the arena's shutter did not shut")
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
	t.near(_hp(fatty), hp, 0.01, "a thrust landed while his eye is shut")
	# A thrown clod only splats; a plain Roll (no Heavy skin) bonks off him.
	_route(t, fatty.get(&"damage_area"), ["thrown", "mud-ball"])
	t.check(not bool(fatty.call(&"is_dizzy")), "a thrown clod still knocks him off balance")
	_route(t, fatty.get(&"damage_area"), ["roll"])
	t.check(not bool(fatty.call(&"is_dizzy")), "a plain Roll knocked him off balance")
	t.near(_hp(fatty), hp, 0.01, "a throw or a plain Roll hurt him")
	# The Heavy Roll (the Roll's bonk tagged heavy) knocks him off balance; the Spear lands then.
	SkinState.lend(SkinState.HEAVY)
	_route(t, fatty.get(&"damage_area"), ["roll", "heavy"])
	t.check(bool(fatty.call(&"is_dizzy")), "a Heavy Roll did not knock him off balance")
	_route(t, fatty.get(&"damage_area"), ["spear", "weapon"])
	t.check(_hp(fatty) < hp, "the Spear did not land while he was off balance")
	await t.sim_wait(400.0)
	var art := fatty.get(&"visual") as Node2D
	t.check(art != null and absf(art.rotation) > 0.2, "he does not rock back while off balance (tilt %s)" % str(art.rotation if art != null else 0.0))
	await t.sim_wait(float(fatty.get(&"phase_two_dizzy_ms")) + 400.0)
	t.check(not bool(fatty.call(&"is_dizzy")), "he stays off balance past its time")
	# The rest of his health: a Heavy Roll on the ground, thrusts while he is off balance, until he falls.
	var beaten := await t.until(func() -> bool:
		if BOSS in (Services.run().world.get("defeated_boss_ids", []) as Array):
			return true
		var boss: Node = camp.call(&"get_live_boss")
		_keep_safe(t, boss)
		if boss == null or bool(boss.call(&"is_defeated")):
			return false
		if bool(boss.call(&"is_dizzy")):
			_route(t, boss.get(&"damage_area"), ["spear", "weapon"])
		elif str(boss.call(&"get_phase")) == "chase":
			_route(t, boss.get(&"damage_area"), ["roll", "heavy"])
		return false, 20000.0)
	t.check(beaten, "Fatty's fall is not kept")
	await t.sim_wait(1200.0)
	t.check(not bool(south.call(&"is_shut")), "the arena's shutter did not open after his fall")
	t.check(DungeonState.is_boss_beaten(Services.run(), MAP_ID, BOSS), "the dungeon does not know he fell")
	# His fall breaks the seals: the way out past him here, the way in when R1 is built again.
	t.check(not DungeonState.is_sealed(Services.run(), MAP_ID), "the Lair is still sealed after his fall")
	t.check(await t.until(func() -> bool: return not bool(seal.call(&"is_shut")), 3000.0), "the arena's seal did not sink after his fall")
	var heart := _lair(t, "fatty-boss-heart")
	t.check(heart != null and heart.visible, "his full heart does not show after his fall")
	if not await _enter(t, "r1"):
		return
	t.check(not bool(_objects(t).get_node("r1-seal").call(&"is_shut")), "R1's seal is still shut after his fall")


## The Pearl room: the Larder's ambush shuts its shutter until the Big Squint falls (a mini-boss
## fight, recorded beaten); Pearl 1 rises on the worms' altar; walked into, it grants the Heavy skin
## and seals the Lair: the way in and the way out past Fatty shut, travel out refused.
func test_the_big_squint_guards_pearl_one_and_its_take_seals_the_lair(t: TestContext) -> void:
	if not await _enter(t, "r12"):
		return
	var run := Services.run()
	var pearl := _lair(t, "pearl-1")
	var fight := _objects(t).get_node("r12-fight")
	var shutter := _objects(t).get_node("r12-shutter-south")
	await t.steps(4)
	t.equal(str(pearl.get(&"boss_id")), GUARD, "the Pearl's guard")
	t.check(not bool(pearl.call(&"is_shown")), "the Pearl shows before the Big Squint falls")
	_stand(t, _at("r12", Vector2(12.0, 10.8)))
	var started := await t.until(func() -> bool: return bool(fight.call(&"is_active")), 2000.0)
	t.check(started, "the Larder's ambush did not start")
	t.check(bool(shutter.call(&"is_shut")), "the Larder's shutter did not shut behind the slime")
	t.check(not bool(pearl.call(&"is_shown")), "the Pearl shows during the fight")
	var squint: Node = (t.world().world_root.get_node("Enemies/r12-big-squint") as Node).call(&"get_enemy")
	if not t.check(squint != null, "no Big Squint in the Larder"):
		return
	squint.call(&"take_reaction_damage", 9999.0)
	var won := await t.until(func() -> bool: return not bool(fight.call(&"is_active")), 4000.0)
	t.check(won, "the Larder's fight was not won with the Big Squint beaten")
	t.check(GUARD in (run.world.get("defeated_boss_ids", []) as Array), "the Big Squint is not recorded beaten")
	t.check(await t.until(func() -> bool: return bool(pearl.call(&"is_shown")), 2000.0), "Pearl 1 did not rise")
	t.check(not bool(shutter.call(&"is_shut")), "the Larder's shutter stayed shut")
	t.check(not HeavyCheck.has_skin(), "the Heavy skin before the Pearl")
	t.check(not DungeonState.is_sealed(run, MAP_ID), "the Lair is sealed before the take")
	t.teleport_player(pearl.global_position + Vector2(0.0, 60.0))
	t.check(await t.until(func() -> bool: return bool(pearl.call(&"is_taken")), 1500.0), "walking into the Pearl did not take it")
	t.check(run.has_flag("pearl.fatty-one-eye"), "the Pearl's flag")
	t.check(HeavyCheck.has_skin(), "the Pearl did not grant the Heavy skin")
	t.check(SkinState.is_won(SkinState.HEAVY), "the Heavy skin is not won for good")
	t.equal(SkinState.look(), &"", "the Pearl changed the everyday look (a skin shows only while it works)")
	t.check(not run.has_flag("skin.heavy"), "the Pearl still sets the old stand-in flag")
	# The seal: shut in the way in and the way out past Fatty until he falls.
	t.check(DungeonState.is_sealed(run, MAP_ID), "the take did not seal the Lair")
	t.equal(DungeonState.sealed_by(run, MAP_ID), BOSS, "the seal's boss")
	var done := await t.until(func() -> bool:
		return t.world().world_root.find_child("SealMoment", true, false) == null and not t.tree.paused, 60000.0, 8000.0)
	t.check(done, "the take's moment did not end")
	t.check(str(DungeonState.exit_refusal(t.tree, ENTRANCE)).begins_with("Sealed."), "the way in is not refused while sealed")
	t.check(str(DungeonState.exit_refusal(t.tree, OUTSIDE)).begins_with("Sealed."), "the bolt-hole is not refused while sealed")
	t.equal(str(DungeonState.exit_refusal(t.tree, WORLDS["r11"])), "", "a room of the Lair is refused while sealed")
	# The seals of the other rooms' worlds read the record when they are built.
	for room: String in ["r1", "r13"]:
		if not await _enter(t, room):
			return
		var seal_name := "r1-seal" if room == "r1" else "r13-seal"
		t.check(bool(_objects(t).get_node(seal_name).call(&"is_shut")), "%s is not shut after the take" % seal_name)


## The Weigh House, the Heavy skin's teach: the first plate opens the east door once it is down and
## keeps it open while it rises; the second holds the west door only while a weight stays on it,
## so the statue goes on it.
func test_the_weigh_house_teaches_the_heavy_skins_plates(t: TestContext) -> void:
	if not await _enter(t, "weigh"):
		return
	var east := _objects(t).get_node("c2-east-door/GateScript")
	var west := _objects(t).get_node("c2-west-door/GateScript")
	var stand := _objects(t).get_node("c2-plate-stand") as Node2D
	var held := _objects(t).get_node("c2-plate-statue") as Node2D
	var statue := _objects(t).get_node("c2-statue") as Node2D
	t.check(not bool(east.call(&"is_open")) and not bool(west.call(&"is_open")), "a Weigh House door starts open")
	# Without the skin the plate does not budge.
	_stand(t, stand.global_position)
	await t.sim_wait(3400.0)
	t.check(not bool(east.call(&"is_open")), "a light slime opened the east door")
	SkinState.lend(SkinState.HEAVY)
	await t.sim_wait(1500.0)
	t.check(not bool(east.call(&"is_open")), "the east door opened before its plate was down")
	t.check(await t.until(func() -> bool: return bool(east.call(&"is_open")), 2500.0), "the sunk plate did not open the east door")
	# Off the plate the door stays open while it rises: the slime walks through, north.
	_stand(t, _at("weigh", Vector2(10.5, 8.6)))
	await t.steps(4)
	t.press(&"move_up")
	var north := await t.until(func() -> bool: return t.player_body().global_position.y < _at("weigh", Vector2(0.0, 6.0)).y, 2500.0)
	t.release(&"move_up")
	t.check(north, "the slime did not walk through the east door (feet at %s)" % str(t.player_body().global_position / CELL - ORIGIN))
	t.check(await t.until(func() -> bool: return not bool(east.call(&"is_open")), 6000.0), "the east door stayed open once its plate was up")
	# The second plate: the slime alone opens the west door only while it stands there.
	_stand(t, held.global_position)
	t.check(await t.until(func() -> bool: return bool(west.call(&"is_open")), 3600.0), "the second plate did not open the west door")
	_stand(t, _at("weigh", Vector2(8.5, 4.5)))
	await t.steps(3)
	t.check(not bool(west.call(&"is_open")), "the west door stayed open once the slime stepped off")
	# The statue on it holds the door.
	statue.global_position = held.global_position
	t.check(await t.until(func() -> bool: return bool(west.call(&"is_open")), 3600.0), "the statue on the plate did not open the west door")
	await t.sim_wait(6000.0)
	t.check(bool(west.call(&"is_open")), "the statue did not hold the west door open")


## R10, the test: the statue pushed onto the lane's plate holds R9's stone door open (R9 is its own
## world: the plate's session record `fatty-lair.r10-plate-held`); the slime alone does not, and
## without the statue the doorway down refuses.
func test_the_dung_roller_runs_plate_holds_r9s_door_only_with_the_statue(t: TestContext) -> void:
	if not await _enter(t, "r10"):
		return
	SkinState.lend(SkinState.HEAVY)
	var run := Services.run()
	var plate := _objects(t).get_node("r10-plate") as Node2D
	var statue := _objects(t).get_node("r10-statue") as Node2D
	t.check(not bool(DungeonState.session_value(run, "fatty-lair.r10-plate-held", false)), "R10's plate starts held")
	_stand(t, plate.global_position)
	t.check(await t.until(func() -> bool: return bool(DungeonState.session_value(run, "fatty-lair.r10-plate-held", false)), 3600.0),
		"the Heavy slime on the plate did not hold R9's door")
	_stand(t, _at("r10", Vector2(7.5, 9.6)))
	await t.steps(3)
	t.check(not bool(DungeonState.session_value(run, "fatty-lair.r10-plate-held", false)), "R9's door stayed held once the slime stepped off")
	# Without the statue the doorway down to R9 refuses.
	_stand(t, _at("r10", Vector2(8.0, 12.8)))
	await t.steps(4)
	t.press(&"move_down")
	await t.sim_wait(1500.0)
	t.release(&"move_down")
	t.check(t.in_world(WORLDS["r10"]), "the slime went down to R9 with its door shut")
	statue.global_position = plate.global_position
	t.check(await t.until(func() -> bool: return bool(DungeonState.session_value(run, "fatty-lair.r10-plate-held", false)), 3600.0),
		"the statue on the plate did not hold R9's door")
	_stand(t, _at("r10", Vector2(8.0, 12.0)))
	await t.steps(4)
	t.press(&"move_down")
	var through := await t.until(func() -> bool: return t.in_world(WORLDS["r9"]), WALK_MS)
	t.release(&"move_down")
	t.check(through, "the slime did not go down through R9's held door (in %s)" % t.world().map_id())
	await _settled(t)
	t.check(bool(_objects(t).get_node("r9-north-door/GateScript").call(&"is_open")), "R9's north door is shut although R10's statue holds it")


## R9, the twist: a plate in the Watcher Eye's sight raises the hidden big chest for good; its east
## door's bolt opens from R9 into R8, and from R8 the doorway refuses until then.
func test_the_watcher_halls_plate_raises_the_big_chest(t: TestContext) -> void:
	if not await _enter(t, "r9"):
		return
	SkinState.lend(SkinState.HEAVY)
	var chest := _objects(t).get_node("r9-big-chest/ChestScript")
	var plate := _objects(t).get_node("r9-plate") as Node2D
	var statue := _objects(t).get_node("r9-statue-11-10") as Node2D
	await t.steps(4)
	t.check(not bool(chest.call(&"is_shown")), "the big chest shows before the plate")
	var start := statue.global_position
	statue.global_position = plate.global_position
	t.check(await t.until(func() -> bool: return bool(chest.call(&"is_shown")), 3800.0), "the statue on the plate did not raise the big chest")
	statue.global_position = start
	await t.sim_wait(5600.0)
	t.check(bool(chest.call(&"is_shown")), "the big chest sank again with the plate")
	# The bolted door: from R8 it holds (its doorway refuses), from R9 it opens for good.
	if not await _enter(t, "r8"):
		return
	_stand(t, _at("r8", Vector2(1.6, 7.0)))
	await t.steps(4)
	t.press(&"move_left")
	await t.sim_wait(1400.0)
	t.release(&"move_left")
	t.check(t.in_world(WORLDS["r8"]), "the slime got past R9's bolted door from R8")
	if not await _enter(t, "r9"):
		return
	var bolted := _objects(t).get_node("r9-way-back")
	_stand(t, _at("r9", Vector2(13.6, 7.0)))
	await t.steps(4)
	t.press(&"move_right")
	var out := await t.until(func() -> bool: return bool(bolted.call(&"is_open")) or t.in_world(WORLDS["r8"]), 3000.0)
	out = out and await t.until(func() -> bool: return t.in_world(WORLDS["r8"]), WALK_MS)
	t.release(&"move_right")
	t.check(out, "R9's bolt did not open into R8 (in %s)" % t.world().map_id())
	t.check(t.in_world(WORLDS["r8"]), "the slime did not go through R9's opened bolt into R8")


## Heavy blocks go back to where they stood each time their room is entered again (the guide's
## no-softlock rule): a statue pushed into a corner never blocks the way. A room is built afresh
## each time it is entered.
func test_heavy_blocks_reset_with_their_room(t: TestContext) -> void:
	if not await _enter(t, "weigh"):
		return
	var statue := _objects(t).get_node("c2-statue") as Node2D
	var start := statue.global_position
	statue.global_position = _at("weigh", Vector2(13.5, 3.5))
	if not await _enter(t, "r10"):
		return
	if not await _enter(t, "weigh"):
		return
	statue = _objects(t).get_node("c2-statue") as Node2D
	t.check(statue.global_position.is_equal_approx(start), "the statue is not back when its room is entered again (at %s)" % str(statue.global_position / CELL))


func test_the_way_in_and_out_in_fattys_hollow(t: TestContext) -> void:
	# The way in: the drop gate in the notch of D5's hill.
	if not await _travel(t, ENTRANCE):
		return
	var run := Services.run()
	var holder := t.world().world_root.get_node_or_null("FattysLair")
	if not t.check(holder != null, "D5 has no FattysLair holder"):
		return
	var mouth := _door(t, "fatty-lair-mouth")
	if t.check(mouth != null, "no Lair mouth"):
		t.equal([str(mouth.get(&"target_area_id")), str(mouth.get(&"target_door_id")), str(mouth.get(&"side"))],
			[MAP_ID, "fatty-lair-entrance", "north"], "the mouth leads to R1")
		t.equal(str(mouth.get(&"map_id")), ENTRANCE, "the mouth's world")
	var gate := holder.get_node("fatty-lair-mouth/drop-gate")
	t.equal(str(gate.get(&"map_id")), ENTRANCE, "the gate's record world (the inner winch's)")
	t.check(not bool(gate.call(&"is_open")), "the outer gate starts open")
	t.check(bool(gate.get_node("Lever").call(&"use")), "the outer lever did nothing")
	await t.sim_wait(float(gate.get(&"rise_ms")) + 50.0)
	t.check(bool(gate.call(&"is_open")), "the outer gate did not rise")
	# The way out: the bolt-hole's mouth by the Verdant Gate, Burr beside it.
	if not await _travel(t, OUTSIDE):
		return
	holder = t.world().world_root.get_node_or_null("FattysLair")
	if not t.check(holder != null, "D4 has no FattysLair holder"):
		return
	t.check(holder.get_node_or_null("fatty-lair-mouth") == null, "D4 still has the Lair's old mouth")
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
	# The bolt-hole's own way out (its world, at the top of its tunnel) leads to that mouth.
	if not await _enter(t, "bolt"):
		return
	var up := _door(t, "fatty-lair-bolt-hole")
	if t.check(up != null, "no bolt-hole door"):
		t.equal([str(up.get(&"map_id")), str(up.get(&"target_area_id")), str(up.get(&"target_door_id")), str(up.get(&"side"))],
			[WORLDS["bolt"], OUTSIDE, "fatty-lair-bolt-hole-mouth", "north"], "the bolt-hole leads to D4's mouth")


## R7 the Bell Bridge: a slime that fell into the spike pit walks to the pit's stairs and up them
## onto the north floor (the owner, 2026-10-18: there was no way out).
func test_the_bell_bridges_pit_has_its_stairs_out(t: TestContext) -> void:
	if not await _enter(t, "r7"):
		return
	_stand(t, _at("r7", Vector2(10.0, 11.0)))
	await t.steps(20)
	var level := t.world().elevation.level_of(t.player_body())
	t.check(level < 0, "the pit's floor is not sunken (level %d)" % level)
	# the spikes hurt all the way: kept healthy, so the walk is not cut short by a faint
	var heal := func() -> void: t.player().restore_run_state({"hp": t.player().get_max_hp()})
	t.press(&"move_right")
	await t.until(func() -> bool:
		heal.call()
		return t.player().get_centre().x > _at("r7", Vector2(14.0, 0.0)).x, 4000.0)
	t.release(&"move_right")
	t.press(&"move_up")
	var out := await t.until(func() -> bool:
		heal.call()
		return t.player().get_centre().y < _at("r7", Vector2(0.0, 4.4)).y, 6000.0)
	t.release_all()
	t.check(out, "the slime could not climb out of the spike pit by its stairs (at %s)" % t.player().get_centre())


## R7: a quick Roll from the landing crosses the two west slabs onto the platform (the owner,
## 2026-10-18: something stopped the Roll).
func test_a_roll_crosses_the_bell_bridges_west_slabs(t: TestContext) -> void:
	if not await _enter(t, "r7"):
		return
	Services.run().learn_session_ability("dodge")
	_stand(t, _at("r7", Vector2(7.0, 8.0)))
	t.player().face(Vector2.LEFT)
	await t.steps(4)
	t.press(&"move_left")
	t.press(&"dodge")
	var crossed := await t.until(func() -> bool: return t.player().get_centre().x < _at("r7", Vector2(3.7, 0.0)).x, 3000.0)
	t.release_all()
	await t.sim_wait(600.0)
	t.check(crossed, "the Roll did not cross the slabs (stopped at %s)" % t.player().get_centre())
	t.check(t.world().elevation.level_of(t.player_body()) == 0, "the slime fell into the pit")


## R7: the hazards and slabs work by level (the owner, 2026-10-18: walking under the bridge cracked
## its slabs; one spikes hazard over the whole room hurts only on the pit's floor). A slime walking
## the channel under the north slabs cracks none and stands in the spikes; on level 0 inside the
## hazard's rectangle it is never hurt; walking onto the slabs from the landing cracks them.
func test_the_bell_bridges_slabs_and_spikes_go_by_level(t: TestContext) -> void:
	if not await _enter(t, "r7"):
		return
	var slabs: Array[Node] = []
	for node: Node in _objects(t).get_children():
		if str(node.name).begins_with("r7-slab"):
			slabs.append(node)
	t.check(slabs.size() == 8, "R7 has %d slabs, not 8" % slabs.size())
	var all_standing := func() -> bool:
		for slab: Node in slabs:
			if int(slab.get(&"state")) != 0:
				return false
		return true
	# the channel under the north slabs, at the pit's level
	_stand(t, _at("r7", Vector2(11.5, 6.0)))
	await t.steps(10)
	t.check(t.world().elevation.level_of(t.player_body()) == -1, "the channel is not the pit's level")
	t.press(&"move_left")
	await t.until(func() -> bool: return t.player().get_centre().x < _at("r7", Vector2(5.0, 0.0)).x, 4000.0)
	t.release_all()
	await t.steps(10)
	t.check(t.player().get_centre().x < _at("r7", Vector2(6.5, 0.0)).x, "the slime did not walk under the slabs (at %s)" % t.player().get_centre())
	t.check(all_standing.call(), "walking under the bridge cracked a slab")
	t.check(t.player().get_hp() < t.player().get_max_hp(), "the spikes did not hurt the slime in the pit")
	# level 0 inside the hazard's rectangle: never hurt
	t.player().restore_run_state({"hp": t.player().get_max_hp()})
	_stand(t, _at("r7", Vector2(2.0, 3.0)))
	await t.sim_wait(1500.0)
	t.equal(t.player().get_hp(), t.player().get_max_hp(), "the spikes hurt the slime on the level-0 floor")
	t.check(t.world().elevation.level_of(t.player_body()) == 0, "the slime fell on the level-0 floor")
	# from the landing onto the west slabs: they crack
	_stand(t, _at("r7", Vector2(7.2, 7.55)))
	await t.steps(6)
	t.press(&"move_left")
	var cracked := await t.until(func() -> bool: return not all_standing.call(), 2000.0)
	t.release_all()
	t.check(cracked, "walking onto the bridge cracked no slab")


## R7 played end to end like a player, with inputs only (the owner, 2026-10-19: "a test in R7 that
## manages to reach the other side"): in by the north door from R6, a ledge drop off the north floor
## into the spike channel (landing in front of the wall face, never behind it), out by the pit's
## stairs, a Roll across the north slabs onto the landing, a Roll across the west slabs, the bell
## (rung here as a thrown pot rings it), through the gate, the key, out by the west door into R2.
func test_the_bell_bridge_is_played_from_its_north_door_to_r2(t: TestContext) -> void:
	await _play_the_bell_bridge(t, true)


## The same with R7's automatic collision (its painted `level-collision` layer cleared).
func test_the_bell_bridge_is_played_with_its_automatic_collision(t: TestContext) -> void:
	await _play_the_bell_bridge(t, false)


func _play_the_bell_bridge(t: TestContext, painted: bool) -> void:
	Services.run().learn_session_ability("dodge")
	Services.run().set_flag(LairDirector.FLAG_CALLED)
	await _settled(t)
	t.main.call(&"travel_to", WORLDS["r7"], "", "r7-to-r6")
	if not t.check(await t.until(func() -> bool:
			return t.in_world(WORLDS["r7"]) and not bool(t.main.call(&"is_transitioning")), 10000.0), "could not come into R7"):
		return
	await t.steps(10)
	var elevation: Node = t.world().elevation
	var paint := t.world().world_root.get_node_or_null("level-collision") as TileMapLayer
	if not painted and paint != null:
		paint.clear()
		elevation.call(&"rebuild")
		await t.steps(4)
	var feet := func() -> Vector2: return t.player_body().global_position
	var level := func() -> int: return int(elevation.call(&"level_of", t.player_body()))
	var heal := func() -> void: t.player().restore_run_state({"hp": t.player().get_max_hp()})
	# down the north floor to x = 672, then over its south rim into the channel
	await _walk_to(t, Vector2(672.0, 300.0), 4000.0)
	t.press(&"move_down")
	var dropped := await t.until(func() -> bool:
		heal.call()
		return int(level.call()) == -1 and not bool(t.player().call(&"is_airborne")), 3000.0)
	t.release_all()
	await t.steps(4)
	t.check(dropped, "pushing on the north floor's rim did not drop the slime (at %s)" % feet.call())
	t.check(float((feet.call() as Vector2).y) >= 448.0, "the slime landed behind the wall face (feet %s; the face's foot is at 448)" % feet.call())
	# east along the channel to the stairs and up them
	await _walk_to(t, Vector2(960.0, 520.0), 5000.0, heal)
	t.press(&"move_up")
	var out := await t.until(func() -> bool:
		heal.call()
		return float((feet.call() as Vector2).y) < 372.0 and int(level.call()) == 0, 6000.0)
	t.release_all()
	if not t.check(out, "the slime did not climb out by the stairs (at %s, level %d)" % [feet.call(), level.call()]):
		return
	# west along the rim (south of the pots) to the north bridge, then a Roll south across its two
	# slabs onto the landing
	await _walk_to(t, Vector2(float((feet.call() as Vector2).x), 374.0), 1000.0)
	await _walk_to(t, Vector2(512.0, 374.0), 5000.0)
	t.player().face(Vector2.DOWN)
	t.press(&"move_down")
	await t.until(func() -> bool: return float((feet.call() as Vector2).y) > 376.0, 1000.0)
	t.press(&"dodge")
	var landed := await t.until(func() -> bool: return float((feet.call() as Vector2).y) > 524.0, 2000.0)
	t.release_all()
	await t.sim_wait(500.0)
	t.check(landed and int(level.call()) == 0, "the Roll did not cross the north slabs onto the landing (at %s, level %d)" % [feet.call(), level.call()])
	if int(level.call()) != 0:
		return
	# from the landing's west edge (clear of the slabs: a touch cracks them) a Roll west across the
	# west slabs, holding the way on after it
	await _walk_to(t, Vector2(472.0, 576.0), 3000.0)
	t.player().face(Vector2.LEFT)
	t.press(&"move_left")
	t.press(&"dodge")
	var crossed := await t.until(func() -> bool: return float((feet.call() as Vector2).x) < 316.0, 2000.0)
	t.release_all()
	await t.sim_wait(500.0)
	t.check(crossed and int(level.call()) == 0, "the Roll did not cross the west slabs (at %s, level %d)" % [feet.call(), level.call()])
	if int(level.call()) != 0:
		return
	# the bell, then north through the gate to the key and out by the west door
	_objects(t).get_node("r7-bell").find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.has_method(&"ring"))[0].call(&"ring")
	await t.sim_wait(800.0)
	await _walk_to(t, Vector2(224.0, 560.0), 3000.0)
	await _walk_to(t, Vector2(200.0, 360.0), 4000.0)
	t.check(float((feet.call() as Vector2).y) < 420.0, "the slime did not go through the gate (at %s)" % feet.call())
	t.press(&"move_left")
	var left := await t.until(func() -> bool: return t.in_world(WORLDS["r2"]), 6000.0)
	t.release_all()
	t.check(left, "the slime did not leave by the west door into R2 (at %s)" % feet.call())


## Walks the slime toward `target` (feet) with the arrow keys, one axis then the other, until it is
## within 10 units or `ms` pass; `each` runs every step (keep it healthy).
func _walk_to(t: TestContext, target: Vector2, ms: float, each: Callable = Callable()) -> void:
	for axis in [0, 1]:
		var action: StringName
		var delta := target[axis] - t.player_body().global_position[axis]
		if absf(delta) < 10.0:
			continue
		if axis == 0:
			action = &"move_right" if delta > 0.0 else &"move_left"
		else:
			action = &"move_down" if delta > 0.0 else &"move_up"
		t.press(action)
		var sign_of := signf(delta)
		await t.until(func() -> bool:
			if each.is_valid():
				each.call()
			return (target[axis] - t.player_body().global_position[axis]) * sign_of < 10.0, ms)
		t.release_all()
		await t.steps(3)


## Every Lair room with slabs or ledges (R2, R7, R11, the hub), the same checks, from the rooms'
## own paint (owner, 2026-10-19: procedures that work anywhere): each falling slab cracks under a
## slime that walks onto it from the floor beside it, and the slime ends on open ground, never in a
## wall; a ledge drop off each upper floor's south edge over a pit lands in front of the wall face
## (one cell a level lower on screen), never behind it.
func test_every_lair_room_drops_in_front_of_its_faces_and_its_slabs_crack(t: TestContext) -> void:
	for room in ["r2", "r7", "r11", "hub"]:
		if not await _enter(t, room):
			return
		var world := t.world()
		var elevation: Node = world.elevation
		var heal := func() -> void: t.player().restore_run_state({"hp": t.player().get_max_hp()})
		# the room's enemies wait (a worm's hit would stop the push)
		var enemies := world.world_root.get_node_or_null("Enemies")
		if enemies != null:
			enemies.process_mode = Node.PROCESS_MODE_DISABLED
		# the slabs
		for deck: Node in t.tree.get_nodes_in_group(&"hazard_deck"):
			if not world.world_root.is_ancestor_of(deck) or not deck.has_method(&"delay_ms"):
				continue
			var rect: Rect2 = (deck.call(&"deck_rects") as Array)[0]
			var level := int(deck.call(&"deck_level"))
			var from := Vector2.INF
			var toward := Vector2.ZERO
			for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				var p := rect.get_center() + d * (rect.size * 0.5 + Vector2(22.0, 22.0))
				if _on_any_deck(t, p) or int(elevation.call(&"level_at", p, -99)) != level or not bool(elevation.call(&"body_fits", p, level)):
					continue
				from = p
				toward = -d
				break
			if not from.is_finite():
				continue
			heal.call()
			_stand(t, from)
			elevation.call(&"track", t.player_body(), level)
			await t.steps(4)
			t.press(_action_of(toward))
			var cracked := await t.until(func() -> bool:
				heal.call()
				return int(deck.get(&"state")) != 0, 1500.0)
			t.release_all()
			await t.sim_wait(1400.0)
			heal.call()
			t.check(cracked, "%s: %s did not crack under the slime walking onto it" % [room, deck.name])
			var at := t.player_body().global_position
			var now := int(elevation.call(&"level_of", t.player_body()))
			t.check(bool(elevation.call(&"body_fits", at, now)), "%s: after %s the slime is inside a wall (%s, level %d)" % [room, deck.name, at, now])
		# the ledges: an upper floor's south edge over lower ground with no deck on it
		var painted := elevation.get(&"layer") as TileMapLayer
		var tried := 0
		for cell: Vector2i in painted.get_used_cells():
			if tried >= 2:
				break
			if painted.get_cell_atlas_coords(cell).y > 0:
				continue
			var lower := int(painted.get_cell_tile_data(cell).get_custom_data(&"elevation_level"))
			var up_cell := cell + Vector2i(0, -1)
			var up_data := painted.get_cell_tile_data(up_cell)
			var upper := int(up_data.get_custom_data(&"elevation_level")) if up_data != null else 0
			if up_data != null and painted.get_cell_atlas_coords(up_cell).y > 0:
				continue
			if upper <= lower:
				continue
			# a straight stretch of the edge (not a corner, where the rim turns and the body slides)
			var straight := true
			for side in [Vector2i(-1, 0), Vector2i(1, 0)]:
				var beside := painted.get_cell_tile_data(cell + side)
				var above := painted.get_cell_tile_data(up_cell + side)
				if beside == null or int(beside.get_custom_data(&"elevation_level")) != lower or painted.get_cell_atlas_coords(cell + side).y > 0:
					straight = false
				if (int(above.get_custom_data(&"elevation_level")) if above != null else 0) != upper:
					straight = false
			if not straight:
				continue
			var edge := painted.to_global(painted.map_to_local(cell)) - Vector2(0.0, 32.0)
			var start := edge - Vector2(0.0, 16.0)
			if _on_any_deck(t, edge + Vector2(0.0, 8.0)) or not bool(elevation.call(&"body_fits", start, upper)):
				continue
			tried += 1
			heal.call()
			_stand(t, start)
			elevation.call(&"track", t.player_body(), upper)
			await t.steps(4)
			t.press(&"move_down")
			var deepest := -INF
			await t.until(func() -> bool:
				if bool(t.main.call(&"is_transitioning")) or t.world() != world:
					return true
				heal.call()
				deepest = maxf(deepest, t.player_body().global_position.y)
				return int(elevation.call(&"level_of", t.player_body())) < upper and not bool(t.player().call(&"is_airborne")), 2500.0)
			t.release_all()
			if bool(t.main.call(&"is_transitioning")) or t.world() != world:
				# the edge is a way out (a hole down to another room): it travels, it does not drop
				break
			await t.steps(2)
			deepest = maxf(deepest, t.player_body().global_position.y)
			var face_foot := edge.y + CELL * float(upper - lower if upper - lower < 2 else 1)
			t.check(deepest >= face_foot - 2.0, "%s: the drop off (%s) landed behind the wall face (feet down to %.0f, the face's foot at %.0f)" % [room, edge, deepest, face_foot])
			await t.sim_wait(1200.0)


func _on_any_deck(t: TestContext, point: Vector2) -> bool:
	for deck: Node in t.tree.get_nodes_in_group(&"hazard_deck"):
		if t.world().world_root.is_ancestor_of(deck):
			for r: Rect2 in deck.call(&"deck_rects"):
				if r.grow(14.0).has_point(point):
					return true
	return false


static func _action_of(d: Vector2) -> StringName:
	if d.x < 0.0:
		return &"move_left"
	if d.x > 0.0:
		return &"move_right"
	return &"move_up" if d.y < 0.0 else &"move_down"


## The passage from the Gatehouse to the Pit Hall: its two leaves (R1's north door, the hub's bolted
## shortcut) are one door: shut on both sides, R1's refuses, the bolt slid from the hub opens it, and
## R1's world built again finds its leaf open (the shared record; owner, 2026-10-18).
func test_the_gatehouse_shortcut_opens_on_both_sides(t: TestContext) -> void:
	if not await _enter(t, "r1"):
		return
	var north := _objects(t).get_node_or_null("r1-north-door")
	if not t.check(north != null, "R1's north door is missing"):
		return
	t.check(not bool(north.call(&"is_open")), "R1's leaf starts open")
	north.call(&"_on_push", true)
	await t.steps(4)
	t.check(not bool(north.call(&"is_open")), "R1's side opened the passage")
	if not await _enter(t, "hub"):
		return
	var hub := _objects(t).get_node("hub-r1-shortcut")
	t.check(not bool(hub.call(&"is_open")), "the hub's leaf starts open")
	hub.call(&"_on_push", true)
	t.check(await t.until(func() -> bool: return bool(hub.call(&"is_open")), 3000.0), "the hub's bolt did not open its leaf")
	if not await _enter(t, "r1"):
		return
	await t.steps(6)
	t.check(bool(_objects(t).get_node("r1-north-door").call(&"is_open")), "R1's leaf is shut although the hub's bolt was slid")
	# The world built again (after a visit outside) finds both leaves open.
	t.main.call(&"travel_to", "level-1-d5")
	await t.until(func() -> bool: return t.in_world("level-1-d5") and not bool(t.main.call(&"is_transitioning")), 10000.0)
	if not await _enter(t, "hub"):
		return
	await t.steps(6)
	t.check(bool(_objects(t).get_node("hub-r1-shortcut").call(&"is_open")), "the hub's leaf is shut again after the world was built again")


# --- helpers ------------------------------------------------------------------------------------

## Into the Lair's room `room` (its world). Burr's first call is marked heard (`burr_calls`: not),
## so the Pit Hall's dialogue does not hold the slime.
func _enter(t: TestContext, room: String, burr_calls: bool = false) -> bool:
	if not burr_calls:
		Services.run().set_flag(LairDirector.FLAG_CALLED)
	return await _travel(t, WORLDS[room])


func _travel(t: TestContext, map_id: String) -> bool:
	await _settled(t)
	if not t.in_world(map_id):
		t.main.call(&"travel_to", map_id)
	var arrived := await t.until(func() -> bool:
		return t.in_world(map_id) and t.player_body() != null and not bool(t.main.call(&"is_transitioning")), 10000.0)
	await t.steps(8)
	return t.check(arrived, "could not travel to " + map_id)


## Waits out a travel under way (a door's scroll).
func _settled(t: TestContext) -> void:
	await t.until(func() -> bool: return not bool(t.main.call(&"is_transitioning")), 6000.0)
	await t.steps(2)


## The world of the Lair's room scene `room_name`.
static func _world_of(room_name: String) -> String:
	return "fatty-lair" if room_name == "r1-gatehouse" else "fatty-lair-" + room_name


static func _at(room: String, cell: Vector2) -> Vector2:
	# a room two grid cells wide or tall grows two more cells past its insert (the builder's INSERT)
	var at := cell
	if room == "hub" and cell.x >= 20.0:
		at.x += 2.0
	elif room == "r10" and cell.x >= 16.0:
		at.x += 2.0
	elif room == "r8" and cell.y >= 14.0:
		at.y += 2.0
	return (ORIGIN + at) * CELL


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
