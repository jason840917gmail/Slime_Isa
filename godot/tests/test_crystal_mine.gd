extends RefCounted
## The Crystal Mine, Chapter 3's dungeon, as the game enters it since 2026-11-25: one world per room
## (step 4 of the dungeons rework; docs/godot/DUNGEONS.md "The Crystal Mine rebuilt", wings 1 to 4 and
## "The switch-over (the Mine)"; every room, door, key and record id: docs/handover/
## 2026-11-23-dungeons-rework.md "Step 4: the Mine"): 15 room worlds in
## game/scenes/worlds/rooms/crystal-mine-rooms/, one dungeon record across them, `crystal-mine` (the
## retired one-scene world's id, so its records carry over).
##
## Covered: the rooms are worlds on the layout and their room doors pair up; the first rooms' doorways
## lead both ways; every room loads as the Mine and keeps the old world's record ids; keys 2 (M4's ledge chest)
## and 1 (M5's floor key) open the Foreman's Gate's two locks into the Dark Maze; the travel cart rides
## between the Chasm (M9) and the mouth (M1), across worlds; the ore lift between M4's gallery and the
## shaft's floor (M14), worked once from below; the Bow's arrow in the crystal lens lowers the Chasm's
## bridge for good, the way on to the Den; the crystal veils open only while their own room's brazier
## burns (M11, M10); the rotten timbers break only under a Heavy Roll, on both sides; the Feral skin
## clings to painted vines with one interact press (a toggle: nothing held; the next press lets go) and
## climbs them (M4's west shelf); the Feral half (the Den's ledge, the rift's two faces, the Fort Hall's
## balcony and its big key); the Den (M13): the runaway cart clangs off the Shardback's cold shell and
## shatters it brittle, Pearl 3 rises and its take seals the mine; the Den's broken rim (sunk by his
## fall) onto M14's ledge, the roots down, the boss door held without the big key and opened with it;
## the Colossus's crystal fight in M15 (the lower line's cart bursts his first hot plate without harm and
## he kicks it home, clangs off it cold; the Spear on the bare crystal from where it shows, a throw for a
## share, a blow capped at the crystal, the crystal dead and phase 2; the carts take the shoulders in
## order from whichever side, never the breastplate on the floor, which bursts on his back);
## his fall breaking the seal and the climb out to the Lookout (H4); an old save standing in the
## retired Mine moved into M1 by RunState (`RETIRED_WORLDS`), its record kept and its entrance forgotten.
##
## Not here: the candles, the dark rooms and the Dark Maze's candle gate are tested with the darkness
## work (tests/test_dark_room_candles.gd); the crystal fight's phases, wall and claws are filmed
## (tools/film_colossus_arena.gd `--film=phase1` ... `phase3`, `fight`, `wall`); his first fight (his
## weak spot while four braziers burn) went with the one-scene Mine, its code too (2026-11-25). The mine's outside (G4's gate and its
## way back, the smith) is test_mine_camp.gd. Positions in cells are the walk's
## (tools/film_crystal_mine_rooms.gd), in the room's own cells.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const MineTravel := preload("res://game/crystal_mine/mine_travel.gd")
const MineCart := preload("res://game/crystal_mine/mine_cart.gd")
const OreLift := preload("res://game/crystal_mine/ore_lift.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const PearlScript := preload("res://game/scripts/pearl.gd")
const RunStateScript := preload("res://game/autoload/run_state.gd")

## The world each test starts in (the runner reads it): the Mine's mouth.
const MAP_ID := "crystal-mine-m1-mine-mouth"
## A room's world is this and its name on the layout.
const WORLD_PREFIX := "crystal-mine-"
## The dungeon's record (every room's Dungeon node `record_map_id`).
const RECORD_ID := "crystal-mine"
## The retired one-scene Mine (a save standing in it loads into M1).
const OLD_MINE_ID := "crystal-mine"
## An old record's entrance: the retired Mine's mouth (world units).
const OLD_ENTRANCE := Vector2(1504, 4216)
const LAYOUT := "res://game/scenes/worlds/rooms/crystal-mine-rooms/layout.tscn"
const ROOM_DOOR_SCENE := "res://game/scenes/objects/dungeon/room-door.tscn"
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
## The layout's rooms (their worlds are WORLD_PREFIX + name) and their room doors.
const ROOMS: PackedStringArray = ["m1-mine-mouth", "m2-lamp-tunnel", "m4-great-shaft", "m6-bat-gallery",
	"m7-ore-store", "m5-tally-room", "m3-survey-office", "m8-dark-maze", "m9-the-chasm", "m13-shardback-den",
	"m11-crystal-veil", "m10-prism-gallery", "m12-fort-hall", "m14-shaft-floor", "m15-colossus-arena"]
const ROOM_DOORS := 38
const LOOKOUT_ID := "crystal-caverns-h4"
const COLOSSUS_ID := "crystal-colossus"
const SHARDBACK_ID := "crystal-mine-shardback"
const TIMBERS_FLAG := "crystal-mine.rotten-timbers"
const CELL := 64.0
const PUSH_MS := 5000.0
## How close to a room door's arrival spot the slime comes out (world units; test_lair_rooms.gd's).
const ARRIVAL_SLACK := 40.0
const CLIMB_MS := 5000.0
## Long enough that a staged hold (his stomps, leap, quake and mites held off) outlasts the test.
const HOLD_MS := 60000.0
## The first rooms' open doorways, walked one after another from M1: [room door, the room it leads to].
const DOOR_WALK := [["m1-north", "m2-lamp-tunnel"], ["m2-west", "m5-tally-room"], ["m5-east", "m2-lamp-tunnel"],
	["m2-north", "m4-great-shaft"], ["m4-south-m6", "m6-bat-gallery"], ["m6-north", "m4-great-shaft"],
	["m4-south-m2", "m2-lamp-tunnel"], ["m2-south", "m1-mine-mouth"]]
## Ids the rooms keep from the retired Mine (its records) and their links: [room, node, property, value].
const KEPT_IDS := [
	["m1-mine-mouth", "Objects/mine-entrance/DoorScript", "target_area_id", "crystal-caverns-g4"],
	["m1-mine-mouth", "Objects/mine-entrance/DoorScript", "target_door_id", "camp-mine-mouth"],
	["m1-mine-mouth", "Objects/M1-mouth-seal", "glimpse", true],
	["m1-mine-mouth", "Objects/m1-rail-gate", "gate_id", "crystal-mine-ore-gate"],
	["m1-mine-mouth", "Objects/M1-cart-station", "station_id", "mouth"],
	["m4-great-shaft", "Objects/foremans-gate", "door_id", "foremans-gate"],
	["m4-great-shaft", "Objects/foremans-gate", "keyholes", 2],
	["m4-great-shaft", "Objects/m4-key2-chest", "chest_id", "crystal-mine-M7-K2-chest"],
	["m4-great-shaft", "Objects/m4-lift", "lift_id", "great-shaft-lift"],
	["m5-tally-room", "Objects/M5-K1", "pickup_id", "tally-k1"],
	["m5-tally-room", "Objects/m5-cracked-wall", "flag_id", "crystal-mine.survey-wall"],
	["m3-survey-office", "Objects/m3-cracked-wall", "flag_id", "crystal-mine.survey-wall"],
	["m3-survey-office", "Objects/M3-map-chest", "chest_id", "crystal-mine-M3-map-chest"],
	["m6-bat-gallery", "Objects/m6-rotten-timbers", "flag_id", TIMBERS_FLAG],
	["m7-ore-store", "Objects/m7-rotten-timbers", "flag_id", TIMBERS_FLAG],
	["m7-ore-store", "Objects/m7-rail-gate", "gate_id", "crystal-mine-ore-gate"],
	["m8-dark-maze", "Objects/M8-S1-chest", "chest_id", "crystal-mine-M4-S1-chest"],
	["m8-dark-maze", "Objects/M8-exit-gate", "gate_id", "dark-maze-exit"],
	["m9-the-chasm", "Objects/M9-chasm-lens", "lens_id", "chasm-bridge"],
	["m9-the-chasm", "Objects/M9-cart-station", "starts_with_cart", true],
	["m13-shardback-den", "Objects/M13-den-fight", "boss_id", SHARDBACK_ID],
	["m13-shardback-den", "Objects/M13-den-cart", "returns", true],
	["m13-shardback-den", "Objects/M13-pearl-three", "pearl_id", COLOSSUS_ID],
	["m13-shardback-den", "Objects/M13-pearl-three", "boss_id", SHARDBACK_ID],
	["m10-prism-gallery", "Objects/M10-journal-chest", "chest_id", "crystal-mine-M10-journal-chest"],
	["m12-fort-hall", "Objects/M12-big-key-chest", "chest_id", "crystal-mine-M12-big-key-chest"],
	["m14-shaft-floor", "Objects/colossus-door", "door_id", "colossus-door"],
	["m14-shaft-floor", "Objects/colossus-door", "lock", "big"],
	["m15-colossus-arena", "Objects/ColossusArena", "camp_id", "crystal-mine-colossus"],
	["m15-colossus-arena", "Objects/ColossusArena", "boss_id", COLOSSUS_ID],
	["m15-colossus-arena", "Objects/ColossusArena", "refights", false],
	["m15-colossus-arena", "Objects/ColossusArena", "mark", "boss"],
	["m15-colossus-arena", "Objects/M15-root-wall", "exit_area_id", LOOKOUT_ID],
	["m15-colossus-arena", "Objects/M15-root-wall", "exit_door", "lookout-from-mine"],
	["m15-colossus-arena", "Objects/M15-full-heart/FullHeartScript", "heart_id", COLOSSUS_ID],
]
## Where the walk puts the slime (cells of its room).
const GATE_PUSH := Vector2(9.0, 2.9)
const BOSS_DOOR_PUSH := Vector2(8.0, 2.9)
const SHELF_VINES := Vector2(2.5, 7.1)
const DEN_LEDGE_VINES := Vector2(13.5, 12.1)
const RIFT_WEST_LIP := Vector2(3.5, 10.6)
const RIFT_FLOOR_WEST := Vector2(3.5, 12.5)
const RIFT_FLOOR_EAST := Vector2(12.5, 12.5)
const RIFT_EAST_FOOT := Vector2(12.5, 12.1)
const BALCONY_VINES := Vector2(4.5, 6.1)
const BALCONY_EDGE := Vector2(10.5, 4.5)
const SHAFT_ROOTS_LIP := Vector2(13.0, 4.6)
const CHASM_NEAR_RIM := Vector2(6.0, 9.5)
## The Chasm's far rim begins east of this column.
const CHASM_FAR_RIM_X := 13.0


# --- the rooms -------------------------------------------------------------------------------------

func test_every_room_is_a_world_on_the_layout_and_its_doors_pair_up(t: TestContext) -> void:
	var rooms := _layout_rooms()
	t.equal(rooms.size(), ROOMS.size(), "rooms on the layout")
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/scenes/scene_index.json"))
	var doors := {}
	for room_name: String in ROOMS:
		if not t.check(rooms.has(room_name), "%s is not on the layout" % room_name):
			continue
		var room: Dictionary = rooms[room_name]
		t.equal(str(room["world"]), _world(room_name), "%s's world" % room_name)
		t.equal(str(index.get("world." + str(room["world"]), "")), str(room["scene"]), "%s's world in the scene index" % room_name)
		var scene := (load(str(room["scene"])) as PackedScene).instantiate()
		var definition := scene.get_node_or_null("world-definition")
		if t.check(definition != null, "%s has no world-definition" % room_name):
			t.equal(str(definition.get(&"map_id")), str(room["world"]), "%s's map id" % room_name)
		var dungeon := scene.get_node_or_null("Dungeon")
		if t.check(dungeon != null, "%s has no Dungeon node" % room_name):
			t.equal(str(dungeon.get(&"dungeon_id")), RECORD_ID, "%s's dungeon" % room_name)
			t.equal(str(dungeon.get(&"record_map_id")), RECORD_ID, "%s's records" % room_name)
			t.equal(str(dungeon.get(&"boss_id")), COLOSSUS_ID, "%s's boss, whose fall breaks the seal" % room_name)
			t.check(dungeon.get(&"layout") != null, "%s's Dungeon has no layout" % room_name)
		t.equal(DungeonState.world_dungeon_id(str(room["world"])), RECORD_ID, "%s read as a world of the Mine" % room_name)
		for door: Node in _room_doors(scene):
			var key := "%s/%s" % [room["world"], door.get(&"door_id")]
			t.check(not doors.has(key), "two doors %s" % key)
			doors[key] = {"target_room": str(door.get(&"target_room")), "target_door": str(door.get(&"target_door")),
				"side": str(door.get(&"side"))}
			# the editor's link check: the far door exists, is in the opposite wall and leads back
			t.equal(str(door.call(&"pairing_problem")), "", "%s's link" % key)
		scene.free()
	t.equal(doors.size(), ROOM_DOORS, "room doors")
	for key: String in doors:
		var door: Dictionary = doors[key]
		if not t.check(rooms.has(door["target_room"]), "%s leads to no room on the layout (%s)" % [key, door["target_room"]]):
			continue
		var far: Variant = doors.get("%s/%s" % [rooms[door["target_room"]]["world"], door["target_door"]])
		if not t.check(far != null, "%s leads to %s/%s, which does not exist" % [key, door["target_room"], door["target_door"]]):
			continue
		t.equal("%s/%s" % [rooms[far["target_room"]]["world"], far["target_door"]], key, "%s's far door leads back to it" % key)
		t.equal(str(far["side"]), str(OPPOSITE[door["side"]]), "%s's far door is in the opposite wall" % key)


func test_every_room_world_loads_as_the_mine_and_keeps_the_old_worlds_record_ids(t: TestContext) -> void:
	for room_name: String in ROOMS:
		if not await _enter(t, room_name):
			continue
		var root: Node2D = t.world().world_root
		t.equal(DungeonState.current_id(t.tree), RECORD_ID, "%s's dungeon" % room_name)
		t.check(root.get_node_or_null("CameraRooms/" + room_name) != null, "%s has no camera room of its name" % room_name)
		for kept: Array in KEPT_IDS:
			if str(kept[0]) != room_name:
				continue
			var node := root.get_node_or_null(str(kept[1]))
			if t.check(node != null, "%s has no %s" % [room_name, kept[1]]):
				t.equal(node.get(StringName(str(kept[2]))), kept[3], "%s's %s %s" % [room_name, kept[1], kept[2]])


func test_the_first_rooms_doorways_lead_both_ways(t: TestContext) -> void:
	if not await _enter(t, "m1-mine-mouth"):
		return
	for step: Array in DOOR_WALK:
		if not await _push_through(t, str(step[0]), str(step[1])):
			return


# --- keys, the cart, the lift, the lens, the veils, the timbers ------------------------------------

func test_keys_two_and_one_open_the_foremans_gates_two_locks_into_the_dark_maze(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, "m4-great-shaft"):
		return
	var gate: Node = _objects(t).get_node("foremans-gate")
	await _push_at(t, GATE_PUSH * CELL, &"move_up", 800.0)
	t.check(t.in_world(_world("m4-great-shaft")) and not bool(gate.call(&"is_open")), "the Foreman's Gate let the slime through without its keys")
	t.equal(int(gate.call(&"open_keyholes")), 0, "the Foreman's Gate's locks open with no key")
	# Key 2: the chest on the hub's ledge (the High Line's prize); one lock of two.
	var chest: Node = _objects(t).get_node("m4-key2-chest/ChestScript")
	t.equal(str(chest.call(&"request_open")), "opened", "key 2's chest")
	t.check(await t.until(func() -> bool: return DungeonState.small_keys(run, RECORD_ID) == 1, 2000.0), "key 2 was not taken")
	await _push_at(t, GATE_PUSH * CELL, &"move_up", 1200.0)
	t.equal(int(gate.call(&"open_keyholes")), 1, "the Foreman's Gate's locks open with key 2")
	t.check(t.in_world(_world("m4-great-shaft")) and not bool(gate.call(&"is_open")), "the Foreman's Gate opened with one lock of two")
	t.equal(DungeonState.small_keys(run, RECORD_ID), 0, "small keys held after the first lock")
	# Key 1: the Tally Room's floor key, where its Gloomling sits.
	if not await _enter(t, "m5-tally-room"):
		return
	var key := _objects(t).get_node_or_null("M5-K1") as Node2D
	if not t.check(key != null, "no key 1 in the Tally Room"):
		return
	var record := DungeonState.object_key(key, "key:" + str(key.get(&"pickup_id")))
	t.equal(record, RECORD_ID + ":key:tally-k1", "key 1's record (the old world's)")
	_stand(t, key.global_position, Vector2.UP)
	t.check(await t.until(func() -> bool: return DungeonState.small_keys(run, RECORD_ID) == 1, 2000.0), "key 1 was not picked up")
	t.check(DungeonState.is_done(t.tree, record), "key 1's pickup is not recorded")
	# The second lock: the gate opens and the slime walks on into the Dark Maze.
	if not await _enter(t, "m4-great-shaft"):
		return
	gate = _objects(t).get_node("foremans-gate")
	t.equal(int(gate.call(&"open_keyholes")), 1, "the Foreman's Gate's first lock after the hub was built again")
	_stand(t, GATE_PUSH * CELL, Vector2.UP)
	await t.steps(4)
	t.press(&"move_up")
	var through := await t.until(func() -> bool: return t.in_world(_world("m8-dark-maze")), PUSH_MS)
	t.release(&"move_up")
	t.check(through, "keys 1 and 2 did not open the Foreman's Gate into the Dark Maze (in %s)" % t.world().map_id())
	t.equal(DungeonState.keyholes_open(run, RECORD_ID, RECORD_ID + ":foremans-gate"), 2, "the Foreman's Gate's locks kept open")


func test_the_travel_cart_rides_between_the_chasm_and_the_mouth_across_worlds(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, "m1-mine-mouth"):
		return
	var mouth: Node = _objects(t).get_node("M1-cart-station")
	var line := str(mouth.get(&"line_id"))
	t.check(not bool(mouth.call(&"has_cart")), "the cart stands at the mouth before it was ridden")
	t.check(not bool(mouth.call(&"can_use")), "the mouth's empty station can be ridden")
	t.check(not bool(mouth.call(&"use")), "riding from the empty station did something")
	if not await _enter(t, "m9-the-chasm"):
		return
	var chasm: Node = _objects(t).get_node("M9-cart-station")
	t.check(bool(chasm.call(&"has_cart")), "the cart does not start at the Chasm")
	t.check(bool(chasm.call(&"use")), "the cart at the Chasm cannot be ridden")
	var arrived := await t.until(func() -> bool: return t.in_world(_world("m1-mine-mouth")) and t.player_body() != null, 6000.0)
	if not t.check(arrived, "the ride did not bring the slime to the mouth (in %s)" % t.world().map_id()):
		return
	await _settled(t)
	mouth = _objects(t).get_node("M1-cart-station")
	t.check(bool(mouth.call(&"has_cart")), "the cart did not come to the mouth")
	t.equal(str(run.object_state(RECORD_ID, MineCart.STATE_PREFIX + line, "")), str(mouth.get(&"station_id")),
		"the cart's station kept under the Mine's record")
	_check_arrival(t, "m1-cart-arrival")
	t.check(bool(mouth.call(&"use")), "the cart cannot be ridden back")
	var back := await t.until(func() -> bool: return t.in_world(_world("m9-the-chasm")) and t.player_body() != null, 6000.0)
	if not t.check(back, "the ride back did not reach the Chasm (in %s)" % t.world().map_id()):
		return
	await _settled(t)
	t.check(bool(_objects(t).get_node("M9-cart-station").call(&"has_cart")), "the cart did not come back to the Chasm")
	_check_arrival(t, "m9-cart-arrival")


func test_the_ore_lift_rides_up_from_the_shaft_floor_once_worked_and_then_both_ways(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, "m4-great-shaft"):
		return
	var upper: Node = _objects(t).get_node("m4-lift")
	var lift := str(upper.get(&"lift_id"))
	t.equal(str(upper.get(&"role")), OreLift.UPPER, "M4's landing")
	t.check(not bool(upper.call(&"is_working")), "the lift starts worked")
	t.equal(str(upper.call(&"platform_at")), OreLift.LOWER, "where the platform waits")
	t.check(not bool(upper.call(&"can_use")), "the lift is offered on the gallery before it was worked from below")
	t.check(not bool(upper.call(&"use")), "the lift rode down from the gallery before it was worked")
	if not await _enter(t, "m14-shaft-floor"):
		return
	var lower: Node = _objects(t).get_node("m14-lift")
	t.check(bool(lower.call(&"can_use")), "the lift's crank on the shaft's floor cannot be worked")
	t.check(bool(lower.call(&"use")), "working the crank did nothing")
	var up := await t.until(func() -> bool: return t.in_world(_world("m4-great-shaft")) and t.player_body() != null, 6000.0)
	if not t.check(up, "the lift did not bring the slime up to the hub (in %s)" % t.world().map_id()):
		return
	await _settled(t)
	upper = _objects(t).get_node("m4-lift")
	t.check(bool(upper.call(&"is_working")), "the lift is not working after the ride up")
	t.equal(str(upper.call(&"platform_at")), OreLift.UPPER, "where the platform stands after the ride up")
	t.check(bool(upper.call(&"can_use")), "the worked lift is not offered on the gallery")
	t.check(bool(run.object_state(RECORD_ID, OreLift.STATE_PREFIX + lift + ":working", false)), "the lift's working is not kept under the Mine's record")
	_check_arrival(t, "m4-lift-arrival")
	t.check(bool(upper.call(&"use")), "the worked lift did not ride down from the gallery")
	var down := await t.until(func() -> bool: return t.in_world(_world("m14-shaft-floor")) and t.player_body() != null, 6000.0)
	if not t.check(down, "the lift did not bring the slime back down (in %s)" % t.world().map_id()):
		return
	await _settled(t)
	t.equal(str(_objects(t).get_node("m14-lift").call(&"platform_at")), OreLift.LOWER, "where the platform stands after the ride down")
	_check_arrival(t, "m14-lift-arrival")


func test_the_bows_arrow_in_the_lens_lowers_the_chasms_bridge_for_good_the_way_on_to_the_den(t: TestContext) -> void:
	if not await _enter(t, "m9-the-chasm"):
		return
	_calm(t)
	var lens: Node = _objects(t).get_node("M9-chasm-lens")
	var bridge: Node = _objects(t).get_node("M9-chasm-bridge")
	t.check(lens.is_in_group(&"bow_targets"), "the lens is not a Bow target")
	t.check(not bool(lens.call(&"is_struck")), "the lens starts struck")
	t.check(not bool(bridge.call(&"is_lowered")), "the Chasm's bridge starts lowered")
	var struck: Array = []
	lens.connect(&"struck", func(payload: Dictionary) -> void: struck.append(payload))
	t.check(bool(lens.call(&"on_arrow_hit", {})), "the lens did not take the arrow")
	t.check(bool(lens.call(&"is_struck")), "the lens is not struck")
	t.equal(struck, [{"lens_id": "chasm-bridge"}], "the lens's struck payloads")
	t.check(await t.until(func() -> bool: return bool(bridge.call(&"is_lowered")), 3000.0), "the struck lens did not lower the bridge")
	t.check(bool(lens.call(&"on_arrow_hit", {})), "a struck lens let a second arrow fly on")
	t.equal(struck.size(), 1, "struck signals after a second arrow")
	# Over the bridge to the far rim, and south out of the Chasm down into the Den.
	_calm(t)
	_stand(t, CHASM_NEAR_RIM * CELL, Vector2.RIGHT)
	await t.steps(4)
	t.press(&"move_right")
	var across := await t.until(func() -> bool: return t.player_body().global_position.x > CHASM_FAR_RIM_X * CELL, 4000.0)
	t.release(&"move_right")
	if not t.check(across, "the slime could not walk over the lowered bridge (at %.1f)" % (t.player_body().global_position.x / CELL)):
		return
	await t.steps(4)
	t.equal(_level(t), 0, "the slime's level on the far rim")
	if not await _push_through(t, "m9-south", "m13-shardback-den"):
		return
	# Built again, the lens is struck and the bridge down.
	if not await _enter(t, "m9-the-chasm"):
		return
	t.check(bool(_objects(t).get_node("M9-chasm-lens").call(&"is_struck")), "the lens is not struck when the Chasm is built again")
	t.check(bool(_objects(t).get_node("M9-chasm-bridge").call(&"is_down_for_good")), "the bridge is not down when the Chasm is built again")


func test_the_crystal_veils_open_only_while_their_own_rooms_brazier_burns(t: TestContext) -> void:
	if not await _enter(t, "m11-crystal-veil"):
		return
	_calm(t)
	var veil: Node = _objects(t).get_node("M11-veil")
	var brazier: Node = _objects(t).get_node("M11-brazier")
	await t.steps(2)
	t.check(not bool(veil.call(&"is_open")), "M11's veil starts open")
	var rect: Rect2 = veil.call(&"barrier_rect")
	var below := Vector2(rect.get_center().x, rect.end.y + 1.2 * CELL)
	# Walking at the grown veil from the east landing: held back.
	_stand(t, below, Vector2.UP)
	await t.steps(4)
	t.press(&"move_up")
	await t.sim_wait(800.0)
	t.release(&"move_up")
	t.check(t.in_world(_world("m11-crystal-veil")) and t.player_body().global_position.y > rect.get_center().y,
		"the slime walked through the grown veil")
	brazier.call(&"light")
	await t.steps(3)
	t.check(bool(veil.call(&"is_open")), "the veil did not open while its brazier burns")
	# Standing in the veil when its brazier goes out: pushed out to a side.
	_stand(t, rect.get_center() + Vector2(0.0, 6.0))
	await t.steps(2)
	brazier.call(&"put_out")
	await t.steps(4)
	t.check(not bool(veil.call(&"is_open")), "the veil stays open with its brazier out")
	t.check(not rect.has_point(t.player_body().global_position), "the slime was left inside the veil")
	# Lit again: through it into the Prism Gallery, whose own veil waits for its own brazier.
	brazier.call(&"light")
	await t.steps(3)
	_stand(t, below, Vector2.UP)
	await t.steps(4)
	t.press(&"move_up")
	var through := await t.until(func() -> bool: return t.in_world(_world("m10-prism-gallery")), PUSH_MS)
	t.release(&"move_up")
	if not t.check(through, "the open veil did not let the slime north into the Prism Gallery (in %s)" % t.world().map_id()):
		return
	await _settled(t)
	var far_veil: Node = _objects(t).get_node("M10-veil")
	var far_brazier: Node = _objects(t).get_node("M10-brazier")
	t.check(not bool(far_veil.call(&"is_open")), "the Prism Gallery's veil is open with its own brazier cold")
	far_brazier.call(&"light")
	await t.steps(3)
	t.check(bool(far_veil.call(&"is_open")), "the Prism Gallery's veil did not open while its brazier burns")


func test_the_rotten_timbers_break_only_under_a_heavy_roll_on_both_sides(t: TestContext) -> void:
	if not await _enter(t, "m6-bat-gallery"):
		return
	_calm(t)
	var timbers: Node = _objects(t).get_node("m6-rotten-timbers")
	var area := timbers.get_node("DamageArea") as Area2D
	_route(t, area, ["roll"])
	t.check(not bool(timbers.call(&"is_smashed")), "a plain Roll smashed the timbers")
	_route(t, area, ["weapon", "spear"])
	t.check(not bool(timbers.call(&"is_smashed")), "the Spear smashed the timbers")
	_route(t, area, ["roll", "heavy"])
	t.check(bool(timbers.call(&"is_smashed")), "a Heavy Roll did not smash the timbers")
	t.check(Services.run().has_flag(TIMBERS_FLAG), "the smashed timbers' flag is not set")
	# Through the smashed doorway: the Ore Store's side stands smashed too.
	if not await _push_through(t, "m6-south", "m7-ore-store"):
		return
	t.check(bool(_objects(t).get_node("m7-rotten-timbers").call(&"is_smashed")), "the timbers stand whole on the Ore Store's side")


# --- the Feral skin ----------------------------------------------------------------------------------

func test_the_feral_skin_clings_to_painted_vines_with_one_press_and_climbs_the_hubs_west_shelf(t: TestContext) -> void:
	if not await _enter(t, "m4-great-shaft"):
		return
	var foot := SHELF_VINES * CELL
	# Without the skin the vines are no way up.
	_stand(t, foot, Vector2.UP)
	await t.steps(4)
	await _tap(t, &"interact")
	t.press(&"move_up")
	await t.sim_wait(800.0)
	t.release(&"move_up")
	await t.steps(4)
	t.check(not t.player().is_climbing(), "the slime clings to the vines without the Feral skin")
	t.equal(_level(t), 0, "the slime's level after pushing up the vines without the Feral skin")
	# Pearl 3's skin (lent): one press clings and nothing has to be held; the next press lets go.
	SkinState.lend(SkinState.FERAL)
	_stand(t, foot, Vector2.UP)
	await t.steps(4)
	await _tap(t, &"interact")
	await t.steps(10)
	t.check(t.player().is_climbing(), "a press at the vines' foot did not cling")
	await t.sim_wait(500.0)
	t.check(t.player().is_climbing(), "the slime let go of the vines with nothing held")
	await _tap(t, &"interact")
	t.check(await t.until(func() -> bool: return not t.player().is_climbing(), 2000.0), "a second press did not let go of the vines")
	# Up the vines onto the west shelf, and through its doorway onto the Survey Office's shelf.
	if not await _climb(t, foot, Vector2.UP, 1):
		return
	if not await _push_through(t, "m4-west-shelf", "m3-survey-office"):
		return
	t.equal(_level(t), 1, "the slime's level on the Survey Office's shelf")


func test_the_feral_half_climbs_the_dens_ledge_the_rift_and_the_fort_halls_balcony_to_the_big_key(t: TestContext) -> void:
	var run := Services.run()
	SkinState.lend(SkinState.FERAL)
	# After Pearl 3: the Shardback beaten, the Den calm.
	DungeonState.mark_boss_beaten(run, RECORD_ID, SHARDBACK_ID)
	if not await _enter(t, "m13-shardback-den"):
		return
	# The teach: the vines up the Den's ledge, its east door into the rift.
	if not await _climb(t, DEN_LEDGE_VINES * CELL, Vector2.UP, 1):
		return
	if not await _push_through(t, "m13-east-ledge", "m11-crystal-veil"):
		return
	t.equal(_level(t), 1, "the slime's level on the rift's west landing")
	_calm(t)
	# The test: down the west landing's face, across the rift's floor, up the east landing's.
	if not await _climb(t, RIFT_WEST_LIP * CELL, Vector2.DOWN, 0):
		return
	_stand(t, RIFT_FLOOR_WEST * CELL, Vector2.RIGHT)
	await t.steps(4)
	t.press(&"move_right")
	var across := await t.until(func() -> bool: return t.player_body().global_position.x >= RIFT_FLOOR_EAST.x * CELL - 8.0, 6000.0)
	t.release(&"move_right")
	if not t.check(across, "the slime could not walk the rift's floor to the east face (at %.1f)" % (t.player_body().global_position.x / CELL)):
		return
	if not await _climb(t, RIFT_EAST_FOOT * CELL, Vector2.UP, 1):
		return
	if not await _push_through(t, "m11-east-landing", "m12-fort-hall"):
		return
	_calm(t)
	# The twist: up the Fort Hall's balcony, its big chest, a drop off its edge unhurt.
	if not await _climb(t, BALCONY_VINES * CELL, Vector2.UP, 1):
		return
	var chest: Node = _objects(t).get_node("M12-big-key-chest/ChestScript")
	t.equal(str(chest.call(&"request_open")), "opened", "the balcony's big chest")
	t.check(await t.until(func() -> bool: return DungeonState.has_item(run, RECORD_ID, DungeonState.BIG_KEY), 2000.0),
		"the big key did not come from the balcony's big chest")
	_stand(t, BALCONY_EDGE * CELL, Vector2.DOWN)
	await t.steps(4)
	_calm(t)
	var hp := t.player().get_hp()
	t.press(&"move_down")
	var dropped := await t.until(func() -> bool: return _level(t) == 0, 3000.0)
	t.release(&"move_down")
	await t.sim_wait(600.0)
	t.check(dropped, "the slime could not drop off the balcony (level %d)" % _level(t))
	t.equal(t.player().get_hp(), hp, "the slime's health after the drop off the balcony")


# --- the Den -----------------------------------------------------------------------------------------

func test_the_dens_cart_clangs_off_the_shardbacks_cold_shell_and_staggers_him(t: TestContext) -> void:
	var den := await _den_fight(t)
	if den.is_empty():
		return
	var shardback: Node = den["shardback"]
	t.check(bool(_objects(t).get_node("M13-den-shutter").call(&"is_shut")), "the Den's north shutter did not close behind the slime")
	t.check(not bool(shardback.call(&"is_brittle")), "his shell is brittle with no fire on it")
	var hp := _hp(shardback)
	(den["target"] as Node).call(&"strike")
	var rocked := await t.until(func() -> bool: return bool(shardback.call(&"is_staggered")), 4000.0)
	t.check(rocked, "the cart did not stagger him (cart %s)" % (den["cart"] as Node).call(&"state_name"))
	t.near(_hp(shardback), hp - float(shardback.call(&"pattern", "cartColdDamage", 0.0)), 0.5, "his health after the cart clanged off")
	t.check(not bool(shardback.call(&"is_defeated")), "the cart beat him through his cold shell")
	t.check(bool((den["fight"] as Node).call(&"is_active")), "the Den's fight ended at the clang")


func test_a_flame_makes_his_shell_brittle_the_cart_shatters_it_and_pearl_threes_take_seals_the_mine(t: TestContext) -> void:
	var run := Services.run()
	var den := await _den_fight(t)
	if den.is_empty():
		return
	var objects := _objects(t)
	var shardback: Node = den["shardback"]
	var fight: Node = den["fight"]
	var pearl: Node2D = objects.get_node("M13-pearl-three")
	t.equal(str(pearl.get(&"skin_id")), "feral", "Pearl 3's skin")
	t.check(not bool(pearl.call(&"is_shown")), "Pearl 3 shows before the Shardback falls")
	# A Lantern flame on him (a fire hit): his shell glows brittle; the cart let go shatters it. Put back
	# on the rails once the hit's stun is over (staged).
	_flame(t, shardback)
	await t.sim_wait(700.0)
	_put_on_rails(shardback, den["spot"])
	await t.steps(2)
	t.check(bool(shardback.call(&"is_brittle")), "a flame on his shell did not make it brittle")
	(den["target"] as Node).call(&"strike")
	var fell := await t.until(func() -> bool: return bool(shardback.call(&"is_defeated")), 4000.0)
	if not t.check(fell, "the cart did not shatter his brittle shell (cart %s)" % (den["cart"] as Node).call(&"state_name")):
		return
	t.check(await t.until(func() -> bool: return bool(fight.call(&"is_done")), 4000.0), "the Den's fight was not won when the Shardback fell")
	t.check(SHARDBACK_ID in (run.world.get("defeated_boss_ids", []) as Array), "the Shardback was not recorded beaten")
	var shutter: Node = objects.get_node("M13-den-shutter")
	var rim: Node = objects.get_node("M13-den-ledge")
	t.check(await t.until(func() -> bool: return not bool(shutter.call(&"is_shut")), 3000.0), "his fall did not open the north shutter")
	t.check(await t.until(func() -> bool: return not bool(rim.call(&"is_shut")), 3000.0), "his fall did not sink the broken rim's shutter")
	t.check(await t.until(func() -> bool: return bool(pearl.call(&"is_shown")), 2000.0), "Pearl 3 did not rise when the Shardback fell")
	t.check(not DungeonState.is_sealed(run, RECORD_ID), "the mine is sealed before the take")
	# The take: the Feral skin, and the mine sealed until the Colossus falls.
	MineTravel.place(t.player(), pearl.global_position, Vector2.UP)
	t.check(await t.until(func() -> bool: return bool(pearl.call(&"is_taken")), 1500.0), "the slime did not take Pearl 3")
	t.check(SkinState.is_won(SkinState.FERAL), "Pearl 3 did not grant the Feral skin")
	t.check(not (objects.get_node("M13-pearl-glint") as CanvasItem).visible, "Pearl 3's glint stayed after the take")
	t.check(DungeonState.is_sealed(run, RECORD_ID), "taking Pearl 3 did not seal the mine")
	t.equal(DungeonState.sealed_by(run, RECORD_ID), COLOSSUS_ID, "the boss who holds the seal")
	# The mouth's seal stands shut in M1.
	if not await _enter(t, "m1-mine-mouth"):
		return
	var mouth: Node = _objects(t).get_node("M1-mouth-seal")
	t.check(await t.until(func() -> bool: return bool(mouth.call(&"is_shut")), 3000.0), "the mouth's seal is not shut after the take")


func test_the_dens_broken_rim_leads_down_to_the_shaft_floor_and_the_big_key_opens_the_boss_door(t: TestContext) -> void:
	var run := Services.run()
	SkinState.lend(SkinState.FERAL)
	# The Shardback beaten: his fall sank the broken rim's shutter for good.
	DungeonState.mark_boss_beaten(run, RECORD_ID, SHARDBACK_ID)
	if not await _enter(t, "m13-shardback-den"):
		return
	var rim: Node = _objects(t).get_node("M13-den-ledge")
	t.check(await t.until(func() -> bool: return not bool(rim.call(&"is_shut")), 3000.0), "the Den's broken rim stayed shut with the Shardback beaten")
	if not await _push_through(t, "m13-south-rim", "m14-shaft-floor"):
		return
	t.equal(_level(t), 1, "the slime's level at the rim's foot, on the shaft floor's ledge")
	if not await _climb(t, SHAFT_ROOTS_LIP * CELL, Vector2.DOWN, 0):
		return
	var door: Node = _objects(t).get_node("colossus-door")
	await _push_at(t, BOSS_DOOR_PUSH * CELL, &"move_up", 1200.0)
	t.check(t.in_world(_world("m14-shaft-floor")) and not bool(door.call(&"is_open")), "the boss door let the slime through without the big key")
	DungeonState.give_item(run, RECORD_ID, DungeonState.BIG_KEY)
	_stand(t, BOSS_DOOR_PUSH * CELL, Vector2.UP)
	await t.steps(4)
	t.press(&"move_up")
	var inside := await t.until(func() -> bool: return t.in_world(_world("m15-colossus-arena")), PUSH_MS)
	t.release(&"move_up")
	t.check(inside, "the big key did not open the boss door into his arena (in %s)" % t.world().map_id())


# --- the Colossus's crystal fight (M15) --------------------------------------------------------------

func test_a_runaway_cart_bursts_his_first_hot_plate_without_harm_and_he_kicks_it_home(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var boss: Node = fight["boss"]
	var line := await _cart_line(t, true)
	var cart: Node2D = line["cart"]
	t.check(bool(boss.call(&"is_brittle")), "his first plate is not hot in the lit brazier's ring")
	t.equal(str(boss.call(&"current_plate")), "L", "the plate that glows (the first in the fixed order)")
	var bursts: Array = []
	boss.connect(&"plate_burst", func(payload: Dictionary) -> void: bursts.append(payload))
	var hp := _hp(boss)
	(line["target"] as Node).call(&"strike")
	var burst := await t.until(func() -> bool: return not bursts.is_empty(), 6000.0)
	if not t.check(burst, "the cart did not burst a plate (cart %s)" % cart.call(&"state_name")):
		return
	# the cart met his front (he faces its tunnel): it bursts his first shoulder's plate all the same
	t.equal(str((bursts[0] as Dictionary).get("plate", "")), "L", "the plate the cart burst (his first, whatever side it met)")
	t.equal(int(boss.call(&"plates_left")), 2, "his plates left after the burst")
	t.near(_hp(boss), hp, 0.1, "his health after the burst (a burst does no harm)")
	t.equal(int(boss.call(&"crystal_phase")), 1, "his phase after the burst (crystal L bare, still live)")
	t.check(not bool(boss.call(&"is_crystal_dead", "L")), "the burst killed crystal L")
	t.check(bool(cart.call(&"is_held_for_kick")), "the cart does not wait against him to be kicked")
	# His feet back, furious, he kicks it home up its line.
	boss.set_physics_process(true)
	var home_ms := float(boss.call(&"pattern", "burstStaggerMs", 0.0)) + float(boss.call(&"pattern", "kickMs", 0.0)) \
		+ float(boss.call(&"pattern", "kickBackMs", 0.0))
	var home := await t.until(func() -> bool: return bool(cart.call(&"is_held")), home_ms + 3000.0)
	t.check(home, "he did not kick the cart home (cart %s, his phase %s)" % [cart.call(&"state_name"), boss.call(&"get_phase")])


func test_a_runaway_cart_clangs_off_his_cold_first_plate_and_staggers_him(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var boss: Node = fight["boss"]
	var line := await _cart_line(t, false)
	var cart: Node2D = line["cart"]
	t.check(not bool((fight["arena"] as Node).call(&"all_lit")), "the braziers are not cold at the fight's start")
	t.check(not bool(boss.call(&"is_brittle")), "his first plate is hot with every brazier cold")
	var clangs: Array = []
	var bursts: Array = []
	boss.connect(&"plate_clanged", func(payload: Dictionary) -> void: clangs.append(payload))
	boss.connect(&"plate_burst", func(payload: Dictionary) -> void: bursts.append(payload))
	var hp := _hp(boss)
	(line["target"] as Node).call(&"strike")
	var clang := await t.until(func() -> bool: return not clangs.is_empty(), 6000.0)
	if not t.check(clang, "the cart did not clang off him (cart %s)" % cart.call(&"state_name")):
		return
	t.equal(str((clangs[0] as Dictionary).get("plate", "")), "L", "the plate the cart clanged off (his first)")
	t.equal(bursts.size(), 0, "plates the cold cart burst")
	t.equal(int(boss.call(&"plates_left")), 3, "his plates left after the clang")
	t.near(_hp(boss), hp, 0.1, "his health after the clang")
	t.equal(str(boss.call(&"get_phase")), "stagger", "his phase after the clang")


func test_the_bare_crystal_takes_the_spear_where_it_shows_then_goes_dark_into_the_next_phase(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var boss: Node = fight["boss"]
	var his_floor: Rect2 = (fight["arena"] as Node).get(&"floor_rect")
	_put_boss(boss, his_floor.get_center())
	_hold_still(t, boss, Vector2.DOWN)
	# Phase 1 (staged): plate L gone, crystal L bare and whole. Facing down, L is his right shoulder, on
	# the screen's left; it shows from his front, his back and its own side (the left), not his right.
	boss.call(&"stage_crystals", ["C", "R"])
	await t.steps(2)
	var share := float(boss.call(&"crystal_share"))
	t.near(share, 60.0, 0.01, "a crystal's share (180 health, a third each)")
	t.near(_hp(boss), 3.0 * share, 0.1, "his health: his three crystals")
	var hp := _hp(boss)
	_hit(t, boss, ["spear"], Vector2.RIGHT)
	t.near(_hp(boss), hp, 0.1, "his health after a Spear hit on his far side (plate R and his breastplate)")
	t.equal(int(boss.get(&"_clink_hinted_phase")), 1, "the phase's first clink gave no line")
	_hit(t, boss, ["weapon"], Vector2.LEFT)
	t.near(_hp(boss), hp, 0.1, "his health after a hit that is not the Spear's on the bare crystal")
	for side: Vector2 in [Vector2.DOWN, Vector2.UP, Vector2.LEFT]:
		var before := _hp(boss)
		_hit(t, boss, ["spear"], side)
		t.near(_hp(boss), before - _spear_damage(), 0.1, "a Spear hit from %s on his bare shoulder crystal" % side)
		await t.steps(2)
	var before_throw := _hp(boss)
	_hit(t, boss, ["thrown"], Vector2.DOWN)
	t.near(_hp(boss), before_throw - _spear_damage() * float(boss.call(&"pattern", "thrownShare", 0.0)), 0.1,
		"a thrown thing on the bare crystal (a share of a Spear hit)")
	await t.steps(2)
	# A blow far bigger than the crystal has left takes only the crystal: it is dead, phase 2.
	var broken: Array = []
	boss.connect(&"crystal_broken", func(payload: Dictionary) -> void: broken.append(payload))
	_hit(t, boss, ["spear"], Vector2.LEFT, 999.0)
	t.near(_hp(boss), 2.0 * share, 0.1, "his health after the blow that destroyed crystal L (no more than it had)")
	t.check(bool(boss.call(&"is_crystal_dead", "L")), "crystal L is not dead")
	t.equal(int(boss.call(&"crystal_phase")), 2, "his phase once crystal L is dead")
	t.equal(broken.size(), 1, "crystal_broken signals")
	t.equal(str(boss.call(&"get_phase")), "stagger", "his phase after his crystal broke (the beat)")
	await t.steps(2)
	# Dead, it clinks: the Spear from his left (it meets the dead crystal; R is not there).
	var after := _hp(boss)
	_hit(t, boss, ["spear"], Vector2.LEFT)
	t.near(_hp(boss), after, 0.1, "his health after a Spear hit on his dead crystal")
	t.equal(int(boss.get(&"_clink_hinted_phase")), 2, "phase 2's first clink gave no line")


func test_the_carts_take_the_shoulders_in_order_whichever_side_and_never_the_chest_on_the_floor(t: TestContext) -> void:
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var boss: Node = fight["boss"]
	var line := await _cart_line(t, true)
	var cart: Node2D = line["cart"]
	# Phase 2 (staged: crystal L dead, its plate gone), turned north: the cart from the east tunnel meets
	# his dead shoulder's side; it bursts plate R all the same.
	boss.call(&"stage_crystals", ["C", "R"], {"L": 0.0})
	_hold_still(t, boss, Vector2.UP)
	await t.steps(2)
	t.equal(int(boss.call(&"crystal_phase")), 2, "his phase with crystal L dead")
	t.equal(str(boss.call(&"current_plate")), "R", "the plate that glows in phase 2")
	t.check(bool(boss.call(&"is_brittle")), "plate R is not hot in the lit brazier's ring")
	var bursts: Array = []
	var clangs: Array = []
	boss.connect(&"plate_burst", func(payload: Dictionary) -> void: bursts.append(payload))
	boss.connect(&"plate_clanged", func(payload: Dictionary) -> void: clangs.append(payload))
	var hp := _hp(boss)
	(line["target"] as Node).call(&"strike")
	var burst := await t.until(func() -> bool: return not bursts.is_empty(), 6000.0)
	if not t.check(burst, "the cart did not burst a plate on his dead side (cart %s)" % cart.call(&"state_name")):
		return
	t.equal(str((bursts[0] as Dictionary).get("plate", "")), "R", "the plate the cart burst from his dead side")
	t.near(_hp(boss), hp, 0.1, "his health after the burst")
	t.check(bool(boss.call(&"has_plate", "C")), "the cart took his breastplate on the floor")
	# Phase 3 standing (staged): the breastplate never heats on the floor; the cart's blow clangs off it.
	boss.call(&"stage_crystals", ["C"], {"L": 0.0, "R": 0.0})
	_hold_still(t, boss, Vector2.RIGHT)
	await t.steps(2)
	t.check(not bool(boss.call(&"is_brittle")), "his breastplate is hot on the floor in the lit brazier's ring")
	boss.call(&"on_mechanism_hit", &"cart", cart)
	t.equal(clangs.size(), 1, "clangs off his breastplate on the floor")
	t.check(bool(boss.call(&"has_plate", "C")), "the cart burst his breastplate on the floor")
	# On his back (staged) it is hot, and the cart bursts it.
	boss.call(&"_transition", "stunned", t.now())
	t.check(bool(boss.call(&"is_brittle")), "his breastplate is not hot on his back")
	boss.call(&"on_mechanism_hit", &"cart", cart)
	t.check(not bool(boss.call(&"has_plate", "C")), "the cart did not burst his breastplate on his back")
	t.near(_hp(boss), float(boss.call(&"crystal_share")), 0.1, "his health after the chest plate burst (his chest crystal whole)")


func test_his_fall_breaks_the_seal_and_the_climb_out_leads_to_the_lookout(t: TestContext) -> void:
	SkinState.lend(SkinState.FERAL)
	var fight := await _start_fight(t)
	if fight.is_empty():
		return
	var run := Services.run()
	var arena: Node = fight["arena"]
	var boss: Node = fight["boss"]
	var objects := _objects(t)
	var wall: Node2D = objects.get_node("M15-root-wall")
	var seal: Node = objects.get_node("M15-climb-out-seal")
	# Pearl 3 taken: the mine sealed until he falls, the climb out shut.
	t.check(DungeonState.seal(run, RECORD_ID, COLOSSUS_ID, COLOSSUS_ID), "the mine could not be sealed")
	t.check(await t.until(func() -> bool: return bool(seal.call(&"is_shut")), 2000.0), "the climb out's seal is not shut while the mine is sealed")
	t.check(not bool(wall.call(&"can_use")), "the climb out can be used while the mine is sealed")
	# His shoulders dead, his chest bare and worn to one Spear hit (staged): the Spear from his front
	# (where his chest shows) until he falls.
	var his_floor: Rect2 = arena.get(&"floor_rect")
	_put_boss(boss, his_floor.get_center())
	_hold_still(t, boss, Vector2.DOWN)
	boss.call(&"stage_crystals", [], {"L": 0.0, "R": 0.0, "C": _spear_damage()})
	for i in 4:
		if bool(boss.call(&"is_defeated")):
			break
		_hit(t, boss, ["spear"], Vector2.DOWN)
		await t.steps(2)
	if not t.check(bool(boss.call(&"is_defeated")), "the Spear on his bare chest crystal did not fell him (health %.0f)" % _hp(boss)):
		return
	# his fall plays on
	boss.set_physics_process(true)
	await t.steps(2)
	t.check(bool(arena.call(&"is_beaten")), "his fall was not recorded")
	t.check(COLOSSUS_ID in (run.world.get("defeated_boss_ids", []) as Array), "defeated_boss_ids has no crystal-colossus")
	t.check(DungeonState.is_boss_beaten(run, RECORD_ID, COLOSSUS_ID), "the Mine's record has him standing")
	# His fall sets chapter-3-complete, and Release 1's end card opens over the game (quests spec
	# 14.6); closed, the mine goes on.
	t.check(run.has_flag("chapter-3-complete"), "his fall did not set chapter-3-complete")
	var shell := Services.shell()
	t.check(shell != null and shell.end_card.is_open(), "Release 1's end card did not open at his fall")
	if shell != null and shell.end_card.is_open():
		shell.end_card.close()
	await t.steps(2)
	t.check(not DungeonState.is_sealed(run, RECORD_ID), "his fall did not break the seal")
	t.check(bool(arena.call(&"all_lit")), "the braziers do not burn for good after his fall")
	var heart: Node = objects.get_node("M15-full-heart/FullHeartScript")
	t.check(await t.until(func() -> bool: return bool(heart.call(&"is_shown")), 1500.0), "his full heart did not rise")
	t.check(await t.until(func() -> bool: return not bool(seal.call(&"is_shut")), 3000.0), "the climb out's seal did not sink")
	t.check(bool(wall.call(&"can_use")), "the climb out cannot be used once he fell")
	# Up the roots of his wall's east end and out to the Lookout.
	_stand(t, wall.global_position + Vector2(0.0, 0.6 * CELL), Vector2.UP)
	await t.steps(4)
	if not t.check(bool(wall.call(&"use")), "the climb out did not start"):
		return
	var along := _action(wall.call(&"climb_direction") as Vector2)
	t.press(along)
	var out := await t.until(func() -> bool: return t.in_world(LOOKOUT_ID) and t.player_body() != null, 8000.0)
	t.release(along)
	t.check(out, "the climb out did not bring the slime to the Lookout (%s; in %s)" % [LOOKOUT_ID, t.world().map_id()])


# --- old saves -------------------------------------------------------------------------------------

func test_an_old_save_standing_in_the_retired_mine_wakes_in_m1_with_its_record_and_no_old_entrance(t: TestContext) -> void:
	var run := Services.run()
	var m1 := _world("m1-mine-mouth")
	t.check(RunStateScript.RETIRED_WORLDS.has(OLD_MINE_ID), "the retired Mine is not a retired world")
	t.equal(RunStateScript.moved_world(OLD_MINE_ID), m1, "the world a save in the retired Mine loads into")
	t.equal(RunStateScript.moved_world(m1), m1, "the world a save in M1 loads into")
	# A run half played in the retired Mine: Pearl 3 taken (the mine sealed), a key held, one of the
	# Foreman's Gate's locks open, the lift worked, the travel cart left at the mouth, the record's
	# entrance the retired Mine's mouth; saved standing in the retired world.
	DungeonState.add_small_key(run, RECORD_ID, 1)
	DungeonState.open_keyhole(run, RECORD_ID, RECORD_ID + ":foremans-gate")
	DungeonState.mark_boss_beaten(run, RECORD_ID, SHARDBACK_ID)
	run.set_flag(PearlScript.FLAG_PREFIX + COLOSSUS_ID)
	SkinState.grant(SkinState.FERAL, false)
	DungeonState.seal(run, RECORD_ID, COLOSSUS_ID, COLOSSUS_ID)
	var lift := OreLift.STATE_PREFIX + "great-shaft-lift"
	run.set_object_state(RECORD_ID, lift + ":working", true)
	run.set_object_state(RECORD_ID, lift, OreLift.LOWER)
	run.set_object_state(RECORD_ID, MineCart.STATE_PREFIX + "crystal-mine-cart", "mouth")
	DungeonState.set_entrance(run, RECORD_ID, OLD_MINE_ID, OLD_ENTRANCE)
	var data: Dictionary = run.serialize()
	data["location"] = {"area_id": OLD_MINE_ID, "map_id": OLD_MINE_ID, "x": OLD_ENTRANCE.x, "y": OLD_ENTRANCE.y, "facing": "down"}
	# Loaded as the game loads a slot (RunState.install, no file).
	if not t.check(run.install(data), "install refused the old save"):
		return
	t.equal(str(run.location.get("map_id", "")), m1, "the world the old save wakes in")
	t.check(not run.location.has("x"), "the old save keeps the retired world's spot (it should wake at M1's spawn)")
	t.check(DungeonState.entrance(run, RECORD_ID).is_empty(), "the record still names the retired world as its entrance")
	t.equal(DungeonState.small_keys(run, RECORD_ID), 1, "small keys kept")
	t.equal(DungeonState.keyholes_open(run, RECORD_ID, RECORD_ID + ":foremans-gate"), 1, "the Foreman's Gate's locks kept")
	t.check(DungeonState.is_sealed(run, RECORD_ID), "the mine is not sealed after the load")
	t.equal(DungeonState.sealed_by(run, RECORD_ID), COLOSSUS_ID, "the boss who holds the seal after the load")
	t.check(DungeonState.is_boss_beaten(run, RECORD_ID, SHARDBACK_ID), "the Shardback stands again after the load")
	t.check(SkinState.is_won(SkinState.FERAL), "the Feral skin was lost in the load")
	# The rooms read the old world's records.
	if not await _enter(t, "m4-great-shaft"):
		return
	t.equal(int(_objects(t).get_node("foremans-gate").call(&"open_keyholes")), 1, "the Foreman's Gate's lock opened in the retired Mine")
	t.check(bool(_objects(t).get_node("m4-lift").call(&"can_use")), "the lift worked in the retired Mine is not offered on the gallery")
	if not await _enter(t, "m13-shardback-den"):
		return
	t.check(bool(_objects(t).get_node("M13-pearl-three").call(&"is_taken")), "Pearl 3 taken in the retired Mine lies on its cradle again")
	var rim: Node = _objects(t).get_node("M13-den-ledge")
	t.check(await t.until(func() -> bool: return not bool(rim.call(&"is_shut")), 3000.0), "the Den's rim stayed shut with the Shardback beaten in the retired Mine")
	await t.steps(6)
	t.check(_placed_enemy(t, "M13-shardback") == null, "the Shardback beaten in the retired Mine stands in the Den")
	if not await _enter(t, "m9-the-chasm"):
		return
	t.check(not bool(_objects(t).get_node("M9-cart-station").call(&"has_cart")), "the cart left at the mouth in the retired Mine stands at the Chasm")
	if not await _enter(t, "m1-mine-mouth"):
		return
	var mouth: Node = _objects(t).get_node("M1-mouth-seal")
	t.check(await t.until(func() -> bool: return bool(mouth.call(&"is_shut")), 3000.0), "the mouth's seal is not shut in the sealed mine")
	t.check(bool(_objects(t).get_node("M1-cart-station").call(&"has_cart")), "the cart left at the mouth in the retired Mine is not there")
	t.equal(str(DungeonState.entrance(run, RECORD_ID).get("map_id", "")), m1, "the entrance M1 records")


# --- helpers ---------------------------------------------------------------------------------------

## The world of the layout's room `room_name`.
static func _world(room_name: String) -> String:
	return WORLD_PREFIX + room_name


func _enter(t: TestContext, room_name: String) -> bool:
	return await _travel(t, _world(room_name))


func _travel(t: TestContext, map_id: String) -> bool:
	await _settled(t)
	if not t.in_world(map_id):
		t.main.call(&"travel_to", map_id)
	var arrived := await t.until(func() -> bool:
		return t.in_world(map_id) and t.player_body() != null and not bool(t.main.call(&"is_transitioning")), 10000.0)
	await t.steps(6)
	return t.check(arrived, "could not travel to " + map_id)


func _settled(t: TestContext) -> void:
	await t.until(func() -> bool: return not bool(t.main.call(&"is_transitioning")), 6000.0)
	await t.steps(2)


func _objects(t: TestContext) -> Node:
	return t.world().world_root.get_node("Objects")


## The layout's rooms: {room name: {"world", "scene"}}.
static func _layout_rooms() -> Dictionary:
	var out := {}
	var layout := (load(LAYOUT) as PackedScene).instantiate()
	for child: Node in layout.get_children():
		if &"room_name" in child:
			out[str(child.get(&"room_name"))] = {"world": str(child.get(&"world_id")), "scene": str(child.get(&"room_scene"))}
	layout.free()
	return out


static func _room_doors(scene: Node) -> Array[Node]:
	var out: Array[Node] = []
	var holder := scene.get_node_or_null("RoomDoors")
	if holder != null:
		for child: Node in holder.get_children():
			if child.scene_file_path == ROOM_DOOR_SCENE:
				out.append(child)
	return out


static func _action(direction: Vector2) -> StringName:
	if direction.y < -0.5:
		return &"move_up"
	if direction.y > 0.5:
		return &"move_down"
	return &"move_left" if direction.x < 0.0 else &"move_right"


## Puts the slime's feet at `feet` (facing `facing`) and takes its level there.
func _stand(t: TestContext, feet: Vector2, facing: Vector2 = Vector2.ZERO) -> void:
	var player := t.player()
	var offset := t.player_body().global_position - player.get_centre()
	MineTravel.place(player, feet - offset, facing)
	t.player_body().velocity = Vector2.ZERO
	t.player_body().reset_physics_interpolation()


func _level(t: TestContext) -> int:
	var elevation := t.world().elevation
	return elevation.level_of(t.player_body()) if elevation != null else 0


## A press of `action` held three ticks (the walk's press).
func _tap(t: TestContext, action: StringName) -> void:
	t.press(action)
	await t.steps(3)
	t.release(action)
	await t.steps(1)


## The slime at `feet` walks `action`'s way into what stands there for `ms` (a door's push).
func _push_at(t: TestContext, feet: Vector2, action: StringName, ms: float) -> void:
	var ways := {&"move_up": Vector2.UP, &"move_down": Vector2.DOWN, &"move_left": Vector2.LEFT, &"move_right": Vector2.RIGHT}
	_stand(t, feet, ways.get(action, Vector2.ZERO))
	await t.steps(4)
	t.press(action)
	await t.sim_wait(ms)
	t.release(action)
	await t.steps(4)


## Stands at room door `door_id`'s arrival spot and pushes out through it. True when the slime came
## out in `room_name`'s world at the far door's arrival spot.
func _push_through(t: TestContext, door_id: String, room_name: String) -> bool:
	var from := t.world().map_id()
	var room_door := t.world().world_root.get_node_or_null("RoomDoors/" + door_id) as Node2D
	if not t.check(room_door != null, "%s has no room door %s" % [from, door_id]):
		return false
	var far_id := str(room_door.get(&"target_door"))
	var inward: Vector2 = room_door.call(&"inward")
	_stand(t, room_door.global_position + inward * float(room_door.get(&"arrival_inset")), -inward)
	await t.steps(4)
	var action := _action(-inward)
	t.press(action)
	var through := await t.until(func() -> bool: return t.in_world(_world(room_name)), PUSH_MS)
	t.release(action)
	if not t.check(through, "%s's door %s did not lead to %s (in %s)" % [from, door_id, room_name, t.world().map_id()]):
		return false
	await _settled(t)
	var far := t.world().world_root.get_node_or_null("RoomDoors/" + far_id)
	if not t.check(far != null, "%s has no door %s" % [room_name, far_id]):
		return false
	var spot: Vector2 = far.get_node("DoorScript").call(&"arrival_point")
	return t.check(t.player().get_centre().distance_to(spot) <= ARRIVAL_SLACK,
		"%s/%s came out at %s, not at %s's arrival %s" % [from, door_id, t.player().get_centre(), far_id, spot])


## The slime came out of a ride (the travel cart, the ore lift) at the arrival point `node_name`
## (under Objects): within a cell of it (a door without a side snaps to the nearest open tile).
func _check_arrival(t: TestContext, node_name: String) -> void:
	var spot: Vector2 = _objects(t).get_node(node_name + "/DoorScript").call(&"arrival_point")
	t.check(t.player().get_centre().distance_to(spot) <= CELL, "the slime came out at %s, not at %s %s" % [t.player().get_centre(), node_name, spot])


## The climb up or down painted vines from `feet` (facing `way`): one interact press clings, the
## movement key along them climbs until the slime stands off them at `level`. True when it did.
func _climb(t: TestContext, feet: Vector2, way: Vector2, level: int) -> bool:
	_stand(t, feet, way)
	await t.steps(6)
	await _tap(t, &"interact")
	var along := _action(way)
	t.press(along)
	var done := await t.until(func() -> bool: return not t.player().is_climbing() and _level(t) == level, CLIMB_MS)
	t.release(along)
	await t.steps(6)
	return t.check(done, "the climb %s from %s did not end at level %d (level %d, climbing %s)"
		% [along, feet / CELL, level, _level(t), t.player().is_climbing()])


## The room's enemies keep to themselves (the walk's staging: it proves the way, not a fight).
func _calm(t: TestContext) -> void:
	for enemy: Node in t.tree.get_nodes_in_group(&"enemy"):
		enemy.set(&"targeting_radius", 0.0)
		enemy.set(&"attack_range", 0.0)


func _placed_enemy(t: TestContext, node_name: String) -> Node:
	var placed: Node = t.world().world_root.get_node_or_null("Enemies/" + node_name)
	return placed.call(&"get_enemy") if placed != null and is_instance_valid(placed) else null


func _wait_placed(t: TestContext, node_name: String) -> Node:
	await t.until(func() -> bool: return _placed_enemy(t, node_name) != null, 3000.0)
	return _placed_enemy(t, node_name)


static func _hp(enemy: Object) -> float:
	return float((enemy.call(&"get_damage_state") as Dictionary).get("hp", -1.0))


static func _spear_damage() -> float:
	return float(Services.constants().value("shapes.spear.baseDamage", 12.0))


## A hit of `damage` with `tags` on `area` from a stand-in source (the barred gate tests' way).
func _route(t: TestContext, area: Area2D, tags: Array, damage: float = 20.0, knock: Vector2 = Vector2.UP) -> void:
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
		"weapon_id": "test-" + str(tags[0]), "weapon_tags": tags, "damage_types": ["physical"], "base_damage": damage,
		"effects": [], "impact": {"position": area.global_position, "knock": knock}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()


## A Lantern flame on `enemy` (a hit tagged as the flame's: its fire), no knock.
func _flame(t: TestContext, enemy: Node) -> void:
	_route(t, enemy.get(&"damage_area") as Area2D, ["fire", "lantern"], 20.0, Vector2.ZERO)


# --- the Den's staging -------------------------------------------------------------------------------

## Into the Den, the slime on its cart line by the target (where the walk baits him): his fight starts;
## the Shardback is put on the rails between the cart and the slime. {"fight", "shardback", "cart",
## "target", "spot"} (the spot on the rails), or {} when it did not start.
func _den_fight(t: TestContext) -> Dictionary:
	if not await _enter(t, "m13-shardback-den"):
		return {}
	var objects := _objects(t)
	var cart := objects.get_node("M13-den-cart") as Node2D
	var target := objects.get_node("M13-den-target") as Node2D
	var fight: Node = objects.get_node("M13-den-fight")
	_stand(t, Vector2(target.global_position.x - 2.4 * CELL, cart.global_position.y), Vector2.LEFT)
	var started := await t.until(func() -> bool: return bool(fight.call(&"is_active")), 3000.0)
	if not t.check(started, "the Den's fight did not start with the slime in it"):
		return {}
	var shardback := await _wait_placed(t, "M13-shardback")
	if not t.check(shardback != null, "the Shardback is not in his Den"):
		return {}
	var spot := cart.global_position + Vector2(float(cart.call(&"line_length")) * 0.55, 0.0)
	_put_on_rails(shardback, spot)
	await t.steps(4)
	if not t.check(bool(cart.call(&"is_held")), "the Den's cart is not held at the top of its line"):
		return {}
	return {"fight": fight, "shardback": shardback, "cart": cart, "target": target, "spot": spot}


## The Shardback's feet at `feet` (on the rails), his home there.
func _put_on_rails(enemy: Node, feet: Vector2) -> void:
	var body := enemy.get(&"body") as CharacterBody2D
	body.global_position = feet
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	enemy.call(&"set_home", enemy.call(&"get_centre"))


# --- the Colossus's staging ----------------------------------------------------------------------------

## Into M15, the slime walks onto his floor: the fight starts and he wakes; his stomps, leap, quake and
## mites held off (staged, as tools/film_colossus.gd holds them). {"arena", "boss"}, or {} when not.
func _start_fight(t: TestContext) -> Dictionary:
	if not await _enter(t, "m15-colossus-arena"):
		return {}
	var arena: Node = _objects(t).get_node("ColossusArena")
	var his_floor: Rect2 = arena.get(&"floor_rect")
	var rect: Rect2 = arena.get(&"arena_rect")
	_stand(t, Vector2(his_floor.get_center().x, rect.end.y - 2.0 * CELL), Vector2.UP)
	var awake := await t.until(func() -> bool:
		var live := arena.call(&"get_live_boss") as Node
		return live != null and str(live.call(&"get_phase")) == "walk", float(arena.get(&"wake_ms")) + 3000.0)
	if not t.check(awake, "the fight did not start, or he did not wake, when the slime walked onto his floor"):
		return {}
	var boss := arena.call(&"get_live_boss") as Node
	t.check(boss.call(&"plate_look") != null, "M15's Colossus has no plate look")
	for timer: StringName in [&"_stomp_ready_at", &"_hop_ready_at", &"_quake_ready_at", &"_next_throw_at"]:
		boss.set(timer, t.now() + HOLD_MS)
	return {"arena": arena, "boss": boss}


## The lower line's cart, its target and the slime by the target (off the rails, to throw at it), him
## on the line in the lower-west brazier's ring (lit when `lit`), facing the cart's tunnel (east), held
## still (staged; the cart and his hits are the game's). {"cart", "target"}.
func _cart_line(t: TestContext, lit: bool) -> Dictionary:
	var boss: Node = _objects(t).get_node("ColossusArena").call(&"get_live_boss")
	var objects := _objects(t)
	var cart := objects.get_node("lower-cart") as Node2D
	var target := objects.get_node("lower-target") as Node2D
	var brazier := objects.get_node("lower-brazier-west") as Node2D
	if lit:
		brazier.call(&"light")
	_stand(t, target.global_position + Vector2(-2.0 * CELL, 0.2 * CELL), Vector2.RIGHT)
	_put_boss(boss, Vector2(brazier.global_position.x + 0.5 * CELL, cart.global_position.y))
	_hold_still(t, boss, Vector2.RIGHT)
	await t.steps(2)
	t.check(bool(cart.call(&"is_held")), "the lower line's cart is not held in its tunnel")
	return {"cart": cart, "target": target}


func _put_boss(boss: Node, feet: Vector2) -> void:
	var body := boss.call(&"get_body") as CharacterBody2D
	body.global_position = feet
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()


## He stands still facing `way` (his walk's standing frame), his step held: what strikes him is the
## game's, only his moving is staged away.
func _hold_still(t: TestContext, boss: Node, way: Vector2) -> void:
	boss.call(&"_set_facing", way)
	boss.call(&"_transition", "walk", t.now())
	(boss.call(&"get_body") as CharacterBody2D).velocity = Vector2.ZERO
	boss.set_physics_process(false)


## A Spear's damage (or `damage`) with `tags` on the Colossus from the slime standing on his `side` (a
## unit vector from his centre toward the slime), two cells off, on his floor (its own activation).
func _hit(t: TestContext, boss: Node, tags: Array, side: Vector2, damage: float = -1.0) -> void:
	var centre: Vector2 = boss.call(&"get_centre")
	var his_floor: Rect2 = _objects(t).get_node("ColossusArena").get(&"floor_rect")
	var inset := Vector2.ONE * CELL * 0.5
	t.teleport_player((centre + side * 2.0 * CELL).clamp(his_floor.position + inset, his_floor.end - inset))
	var router := Services.router()
	var player := t.player()
	var areas: Array[Area2D] = [player.get_damage_area()]
	var activation := router.begin_activation(player, areas)
	router.route({"activation_id": activation, "source": player, "attack_area": player.get_damage_area(),
		"target_area": boss.get(&"damage_area"), "weapon_id": "test-" + str(tags[0]), "weapon_tags": tags,
		"damage_types": ["physical"], "base_damage": _spear_damage() if damage < 0.0 else damage, "effects": [],
		"impact": {"position": centre, "knock": (centre - player.get_centre()).normalized()}})
	router.end_activation(activation)
