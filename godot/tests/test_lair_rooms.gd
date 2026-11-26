extends RefCounted
## Fatty's Lair as one world per room (docs/godot/DUNGEON_ROOMS.md; the plan
## docs/design/2026-10-18-lair-rooms-as-worlds.md): every room scene is a world on the map layout,
## every room door names a door of another room that names it back; every door pair travels both
## ways with the screen scroll and arrives at the right spot; the doors whose lock stands in the
## other room refuse until its record is set (the bolts' far sides, R10's plate for R9's stone door,
## R4's shutter to the nook, the store's planks); what the slime does in one room is there when another room
## is built and after a quit and a load (chests, keys, doors, barricades, plates and statues, the
## blown crack, the seal, the Pearl, the bosses); ordinary enemies come back when their room is
## entered again, won fights and bosses do not; and the Lair is walked from D5's mouth to Fatty's
## arena and out by the bolt-hole into D4. Also: a door with no line still waits for its record; the
## editor's link check passes every door and catches a wrong wall; the compass shows the other
## rooms' chests; every room world is the Lair on the world map; a sealed Lair lets the slime from
## room to room but not out; a faint in the arena wakes at the entrance; the Inner Stair arrives
## facing out of the crypt's stair; the music carries on through a room door.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const LairDirector := preload("res://game/fattys_lair/lair_director.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const DungeonMapDraw := preload("res://game/dungeon/dungeon_map_draw.gd")
const WorldMapWindow := preload("res://game/ui/map/world_map_window.gd")

const MAP_ID := "fatty-lair"
const LAYOUT := "res://game/scenes/worlds/rooms/fatty-lair/layout.tscn"
const ROOM_DOOR_SCENE := "res://game/scenes/objects/dungeon/room-door.tscn"
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
## How close to the far door's arrival spot the slime must come out (world units).
const ARRIVAL_SLACK := 40.0
const PUSH_MS := 5000.0
## The room doors walked by each door test (the four tests share the doors, each under the runner's
## time limit).
const DOOR_GROUPS := [
	["r1-gatehouse", "r1-store", "r2-slab-steps", "r7-bell-bridge"],
	["r3-pit-hall", "burr-cell", "r4-squint-den", "map-nook", "r6-pipe-gallery"],
	["r5-eye-hall", "r8-guard-crypt", "r9-watcher-hall", "r10-dung-roller-run"],
	["c2-weigh-house", "r11-drop-gate-bridge", "r12-larder", "r13-fattys-arena", "r14-postern", "bolt-hole"],
]


func test_every_room_is_a_world_on_the_layout_and_its_doors_pair_up(t: TestContext) -> void:
	var rooms := _layout_rooms()
	# 21 since b4ca2a64 (2026-10-20): the Old Armoury, the Glow-Moss Burrow and the Sally Port moved out
	# into Slimeshire with the come-back secrets
	t.equal(rooms.size(), 21, "rooms on the layout")
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/scenes/scene_index.json"))
	var doors := {}
	var scenes := {}
	for room_name: String in rooms:
		var room: Dictionary = rooms[room_name]
		t.equal(str(index.get("world." + str(room["world"]), "")), str(room["scene"]), "%s's world in the scene index" % room_name)
		# a world of several rooms (R5: the eye hall, the lower hall, the key alcove) is read once
		if scenes.has(room["scene"]):
			continue
		scenes[room["scene"]] = true
		var scene := (load(str(room["scene"])) as PackedScene).instantiate()
		var definition := scene.get_node_or_null("world-definition")
		if t.check(definition != null, "%s has no world-definition" % room_name):
			t.equal(str(definition.get(&"map_id")), str(room["world"]), "%s's map id" % room_name)
		var dungeon := scene.get_node_or_null("Dungeon")
		if t.check(dungeon != null, "%s has no Dungeon node" % room_name):
			t.equal(str(dungeon.get(&"dungeon_id")), MAP_ID, "%s's dungeon" % room_name)
			t.equal(str(dungeon.get(&"record_map_id")), MAP_ID, "%s's records" % room_name)
			t.check(dungeon.get(&"layout") != null, "%s's Dungeon has no layout" % room_name)
		t.equal(DungeonState.world_dungeon_id(str(room["world"])), MAP_ID, "%s read as a world of the Lair" % room_name)
		for door: Node in _room_doors(scene):
			var key := "%s/%s" % [room["world"], door.get(&"door_id")]
			t.check(not doors.has(key), "two doors %s" % key)
			doors[key] = {"world": str(room["world"]), "id": str(door.get(&"door_id")), "target_room": str(door.get(&"target_room")),
				"target_door": str(door.get(&"target_door")), "side": str(door.get(&"side"))}
		scene.free()
	t.equal(doors.size(), 44, "room doors")
	for key: String in doors:
		var door: Dictionary = doors[key]
		if not t.check(rooms.has(door["target_room"]), "%s leads to no room on the layout (%s)" % [key, door["target_room"]]):
			continue
		var far: Variant = doors.get("%s/%s" % [rooms[door["target_room"]]["world"], door["target_door"]])
		if not t.check(far != null, "%s leads to %s/%s, which does not exist" % [key, door["target_room"], door["target_door"]]):
			continue
		t.equal("%s/%s" % [rooms[far["target_room"]]["world"], far["target_door"]], key, "%s's far door leads back to it" % key)
		t.equal(str(far["side"]), str(OPPOSITE[door["side"]]), "%s's far door is in the opposite wall" % key)


func test_doors_of_the_south_rooms_travel_both_ways(t: TestContext) -> void:
	await _walk_doors(t, DOOR_GROUPS[0])


func test_doors_of_the_hub_rooms_travel_both_ways(t: TestContext) -> void:
	await _walk_doors(t, DOOR_GROUPS[1])


func test_doors_of_the_west_rooms_travel_both_ways(t: TestContext) -> void:
	await _walk_doors(t, DOOR_GROUPS[2])


func test_doors_of_the_north_rooms_travel_both_ways(t: TestContext) -> void:
	await _walk_doors(t, DOOR_GROUPS[3])


## The doors whose lock stands in the other room: refused until its record is set, then through.
func test_a_door_whose_lock_is_in_the_other_room_waits_for_its_record(t: TestContext) -> void:
	var run := Services.run()
	run.set_flag(LairDirector.FLAG_CALLED)
	# R1's west doorway: the lower hall's bolt.
	if not await _push_from(t, "r1-gatehouse", "r1-to-r5-lower", false):
		t.check(t.in_world("fatty-lair"), "R1's west doorway let the slime through before the lower hall's bolt")
	DungeonState.mark_done(t.tree, "fatty-lair:fatty-lair-r5-way-back")
	# R1's bolted leaf reads the bolt's record when R1 is built (the slime comes from the lower hall,
	# where it slid the bolt): out to the store and back first.
	await _enter(t, "r1-store")
	t.check(await _push_from(t, "r1-gatehouse", "r1-to-r5-lower", true), "R1's west doorway refused with the lower hall's bolt slid")
	# R10's doorway down: R9's stone door, held only by R10's plate (a session record).
	if not await _push_from(t, "r10-dung-roller-run", "r10-to-r9", false):
		t.check(t.in_world("fatty-lair-r10-dung-roller-run"), "R10's doorway down let the slime through with R9's door shut")
	# The map nook: R4's west shutter, shut (`starts_shut`) until its room fight is won (the Squints).
	await _push_from(t, "r4-squint-den", "r4-to-nook", false)
	t.check(t.in_world("fatty-lair-r4-squint-den"), "the slime got into the map nook past R4's shut shutter")
	# The hub's ledge: R11's bolt.
	await _push_from(t, "r3-pit-hall", "hub-to-r11", false)
	t.check(t.in_world("fatty-lair-r3-pit-hall"), "the hub's north doorway let the slime into R11 before its bolt")
	# The bolted shortcut: R1's leaf holds; the hub's bolt opens both.
	await _push_from(t, "r1-gatehouse", "r1-to-hub", false)
	t.check(t.in_world("fatty-lair"), "the slime got through R1's bolted north door")
	t.check(await _push_from(t, "r3-pit-hall", "hub-to-r1", true), "the hub's bolt did not let the slime through to R1")
	t.check(DungeonState.is_done(t.tree, "fatty-lair:fatty-lair-r1-shortcut"), "the shortcut's bolt is not recorded")
	t.check(await _push_from(t, "r1-gatehouse", "r1-to-hub", true), "R1's leaf did not open with the hub's bolt")
	# The boss door wants the big key; Burr's door two small keys.
	await _push_from(t, "r3-pit-hall", "hub-to-r13", false)
	t.check(t.in_world("fatty-lair-r3-pit-hall"), "the boss door let the slime through without the big key")
	DungeonState.give_item(run, MAP_ID, DungeonState.BIG_KEY)
	t.check(await _push_from(t, "r3-pit-hall", "hub-to-r13", true), "the boss door did not open with the big key")


## What the slime does in one room is there in the others, and after a quit (the resume save at the
## entrance) and a load.
func test_what_is_done_stays_done_across_rooms_and_a_load(t: TestContext) -> void:
	var run := Services.run()
	run.set_flag(LairDirector.FLAG_CALLED)
	# The map nook's map: the chest opened in its world.
	run.set_flag("fatty-lair.nook-gap-open")
	if not await _enter(t, "map-nook"):
		return
	var chest := _objects(t).get_node("nook-map-chest/ChestScript")
	t.equal(str(chest.call(&"request_open")), "opened", "the nook's chest")
	t.check(DungeonState.has_item(run, MAP_ID, DungeonState.MAP), "the map is not held")
	# R7's small key, in its chest on the landing.
	if not await _enter(t, "r7-bell-bridge"):
		return
	var key_chest := _objects(t).get_node("r7-key-chest/ChestScript")
	t.equal(str(key_chest.call(&"request_open")), "opened", "R7's key chest")
	t.check(await t.until(func() -> bool: return DungeonState.small_keys(run, MAP_ID) == 1, 2000.0), "R7's key was not taken")
	# The Postern's barricade, smashed by a Heavy Roll.
	if not await _enter(t, "r14-postern"):
		return
	SkinState.lend(SkinState.HEAVY)
	_route(t, _objects(t).get_node("r14-barricade/DamageArea") as Area2D, ["roll", "heavy"])
	await t.steps(2)
	# R9's bolt slid from its side; R10's plate held down by its statue.
	if not await _enter(t, "r9-watcher-hall"):
		return
	_objects(t).get_node("r9-way-back").call(&"_on_push", true)
	await t.until(func() -> bool: return bool(_objects(t).get_node("r9-way-back").call(&"is_open")), 3000.0)
	if not await _enter(t, "r10-dung-roller-run"):
		return
	(_objects(t).get_node("r10-statue") as Node2D).global_position = (_objects(t).get_node("r10-plate") as Node2D).global_position
	t.check(await t.until(func() -> bool: return bool(DungeonState.session_value(run, "fatty-lair.r10-plate-held", false)), 4000.0),
		"the statue did not hold R10's plate")
	# The Pearl taken (quietly), the Big Squint beaten: the Lair is sealed.
	if not await _enter(t, "r12-larder"):
		return
	DungeonState.mark_boss_beaten(run, MAP_ID, "fatty-lair-big-squint")
	_lair(t, "pearl-1").call(&"take", true)
	t.check(DungeonState.is_sealed(run, MAP_ID), "the take did not seal")
	# Each room built again shows it all.
	await _check_kept(t, true)
	# A quit inside writes the resume save at the entrance; loading it shows it all again (the plate's
	# hold was only for the session: R9's door is shut after the load).
	t.check(run.save_slot(0), "the quit's resume save was not written")
	t.check(bool(t.main.call(&"load_run", 0)), "the resume save did not load")
	await t.until(func() -> bool: return t.player_body() != null and not bool(t.main.call(&"is_transitioning")), 6000.0)
	await t.steps(6)
	t.check(t.in_world("fatty-lair"), "the load did not start at the entrance (in %s)" % t.world().map_id())
	await _check_kept(t, false)
	# Fatty's fall: the seals break for good, in every room's world.
	DungeonState.mark_boss_beaten(run, MAP_ID, "fatty-one-eye")
	DungeonState.unseal(run, MAP_ID)
	for room: String in ["r13-fattys-arena", "r1-gatehouse"]:
		if not await _enter(t, room):
			return
		var seal := _objects(t).get_node("r1-seal" if room == "r1-gatehouse" else "r13-seal")
		t.check(not bool(seal.call(&"is_shut")), "%s's seal is shut after Fatty's fall" % room)
		if room == "r13-fattys-arena":
			_stand(t, Vector2(9.0, 12.5) * 64.0)
			await t.sim_wait(1500.0)
			t.check(not bool(_lair(t, "fatty-camp").get_node("BossCampScript").call(&"has_live_boss")), "Fatty is back after his fall")


## Ordinary enemies come back when their room is entered again; a won fight and its mini-boss do not.
func test_enemies_come_back_with_their_room_but_won_fights_stay_won(t: TestContext) -> void:
	var run := Services.run()
	run.set_flag(LairDirector.FLAG_CALLED)
	if not await _enter(t, "r4-squint-den"):
		return
	# R4's two Squints are `r4-squint-b` and `PlacedEnemy` since the owner's room (2026-11-21, DUNGEONS.md R4)
	var squint: Node = t.world().world_root.get_node("Enemies/r4-squint-b").call(&"get_enemy")
	if not t.check(squint != null, "no squint in R4"):
		return
	squint.call(&"take_reaction_damage", 9999.0)
	t.check(await t.until(func() -> bool: return not is_instance_valid(squint) or bool(squint.call(&"is_defeated")), 3000.0), "the squint did not fall")
	if not await _enter(t, "r5-eye-hall"):
		return
	if not await _enter(t, "r4-squint-den"):
		return
	await t.steps(6)
	var again: Node = t.world().world_root.get_node("Enemies/r4-squint-b").call(&"get_enemy")
	t.check(again != null and not bool(again.call(&"is_defeated")), "R4's squint did not come back with its room")
	# The Larder's ambush: won once, its Big Squint never stands again and its shutter stays open.
	if not await _enter(t, "r12-larder"):
		return
	var fight := _objects(t).get_node("r12-fight")
	_stand(t, Vector2(13.0, 11.8) * 64.0)
	t.check(await t.until(func() -> bool: return bool(fight.call(&"is_active")), 2000.0), "the Larder's ambush did not start")
	var big: Node = t.world().world_root.get_node("Enemies/r12-big-squint").call(&"get_enemy")
	big.call(&"take_reaction_damage", 9999.0)
	t.check(await t.until(func() -> bool: return not bool(fight.call(&"is_active")), 4000.0), "the ambush was not won")
	if not await _enter(t, "r11-drop-gate-bridge"):
		return
	if not await _enter(t, "r12-larder"):
		return
	await t.steps(10)
	_stand(t, Vector2(13.0, 11.8) * 64.0)
	await t.sim_wait(800.0)
	fight = _objects(t).get_node("r12-fight")
	t.check(not bool(fight.call(&"is_active")), "the won ambush ran again")
	t.check(not bool(_objects(t).get_node("r12-shutter-south").call(&"is_shut")), "the won ambush's shutter shut again")
	# A won fight's enemies are taken out of the world for good.
	var placed := t.world().world_root.get_node_or_null("Enemies/r12-big-squint")
	var gone: Node = placed.call(&"get_enemy") if placed != null else null
	t.check(gone == null or bool(gone.call(&"is_defeated")), "the Big Squint came back after his fight was won")


## The Lair walked through its doors (each pushed through, as a player does): from D5's mouth into
## R1, east to R2, north into the hub, the boss door with the big key into Fatty's arena (he has
## fallen: the walk is the doors', not the fight's), north to the Postern, through its smashed planks
## to the bolt-hole and up into D4 by the Verdant Gate.
func test_the_lair_is_walked_from_the_mouth_to_the_arena_and_out_by_the_bolt_hole(t: TestContext) -> void:
	var run := Services.run()
	run.set_flag(LairDirector.FLAG_CALLED)
	run.set_flag("fatty-lair.bolt-hole-smashed")
	DungeonState.give_item(run, MAP_ID, DungeonState.BIG_KEY)
	# D5: into the mouth (its gate opened for this test). Fatty falls only once the slime is in: with
	# him beaten the mouth caves in (lair_collapse.gd).
	run.mark_gate_unlocked("level-1-d5", "fatty-lair-gate")
	if not await _travel(t, "level-1-d5"):
		return
	var mouth := _door(t, "fatty-lair-mouth")
	if not t.check(mouth != null, "no Lair mouth in D5"):
		return
	_stand(t, (mouth.get_parent() as Node2D).global_position + Vector2(0.0, 90.0))
	await t.steps(4)
	t.press(&"move_up")
	var inside := await t.until(func() -> bool: return t.in_world("fatty-lair"), 8000.0)
	t.release(&"move_up")
	if not t.check(inside, "the mouth did not lead into R1 (in %s)" % t.world().map_id()):
		return
	await _settled(t)
	(run.world.get_or_add("defeated_boss_ids", []) as Array).append("fatty-one-eye")
	DungeonState.mark_boss_beaten(run, MAP_ID, "fatty-one-eye")
	var path := [["r1-gatehouse", "r1-to-r2", "fatty-lair-r2-slab-steps"], ["r2-slab-steps", "r2-to-hub", "fatty-lair-r3-pit-hall"],
		["r3-pit-hall", "hub-to-r13", "fatty-lair-r13-fattys-arena"], ["r13-fattys-arena", "r13-to-r14", "fatty-lair-r14-postern"],
		["r14-postern", "r14-to-bolt", "fatty-lair-bolt-hole"]]
	for step: Array in path:
		var door := _door(t, step[1])
		if not t.check(door != null and t.in_world(_world_of(step[0])), "not at %s's door %s (in %s)" % [step[0], step[1], t.world().map_id()]):
			return
		var room_door := door.get_parent() as Node2D
		var inward: Vector2 = room_door.call(&"inward")
		# Walk to the doorway from where the slime arrived, then push through it.
		_stand(t, room_door.global_position + inward * float(room_door.get(&"arrival_inset")))
		await t.steps(4)
		var action := _action(-inward)
		t.press(action)
		var through := await t.until(func() -> bool: return t.in_world(step[2]), PUSH_MS)
		t.release(action)
		if not t.check(through, "%s's door %s did not lead to %s (in %s)" % [step[0], step[1], step[2], t.world().map_id()]):
			return
		await _settled(t)
	# The bolt-hole's tunnel up to daylight: D4's mouth by the Verdant Gate.
	var up := _door(t, "fatty-lair-bolt-hole")
	if not t.check(up != null, "no way up in the bolt-hole"):
		return
	_stand(t, (up.get_parent() as Node2D).global_position + Vector2(0.0, 60.0))
	await t.steps(4)
	t.press(&"move_up")
	var out := await t.until(func() -> bool: return t.in_world("level-1-d4"), 8000.0)
	t.release(&"move_up")
	t.check(out, "the bolt-hole did not lead up into D4 (in %s)" % t.world().map_id())


## Every room door's link checks out in the editor's check (`pairing_problem`: the far door exists,
## is in the opposite wall and leads back), and a door turned to the wrong wall is caught.
func test_every_room_doors_editor_check_passes_and_catches_a_wrong_wall(t: TestContext) -> void:
	var rooms := _layout_rooms()
	var checked := 0
	var wrong: Node = null
	var wrong_room: Node = null
	var scenes := {}
	for room_name: String in rooms:
		if scenes.has(rooms[room_name]["scene"]):
			continue
		scenes[rooms[room_name]["scene"]] = true
		var scene := (load(str(rooms[room_name]["scene"])) as PackedScene).instantiate()
		for door: Node in _room_doors(scene):
			checked += 1
			t.equal(str(door.call(&"pairing_problem")), "", "%s/%s's link" % [room_name, door.get(&"door_id")])
		if wrong == null and not _room_doors(scene).is_empty():
			wrong = _room_doors(scene)[0]
			wrong_room = scene
		else:
			scene.free()
	t.equal(checked, 44, "room doors checked")
	if t.check(wrong != null, "no room door to turn"):
		wrong.set(&"side", DoorScript.opposite(str(wrong.get(&"side"))))
		t.check("wall" in str(wrong.call(&"pairing_problem")), "a door turned to the wrong wall passed the check")
		wrong_room.free()


## The compass's chest dots cover the rooms of other worlds (read from their scenes), and a chest
## opened there is no longer shown.
func test_the_compass_shows_the_chests_of_the_other_rooms(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, "r1-gatehouse"):
		return
	var dungeon := t.world().world_root.get_node("Dungeon")
	var nook: Dictionary = {}
	for room: Dictionary in dungeon.call(&"layout_rooms_elsewhere"):
		if str(room["name"]) == "map-nook":
			nook = room
	if not t.check(not nook.is_empty(), "the map nook is not a room of another world on the layout"):
		return
	var spot := (nook["rect"] as Rect2).position + Vector2(832.0, 448.0)
	var shows := func() -> bool:
		for point: Vector2 in DungeonMapDraw.chest_points(dungeon):
			if point.distance_to(spot) < 1.0:
				return true
		return false
	t.check(shows.call(), "the map nook's chest has no dot on the compass from R1")
	run.ensure_chest(MAP_ID, "nook-map-chest", {"dungeon-map": 1})
	run.set_chest_remaining(MAP_ID, "nook-map-chest", {})
	t.check(not shows.call(), "the map nook's opened chest still has a dot")


## On the world map every room world is the Lair (an interior of D5's region): its "Current area".
func test_every_room_world_is_the_lair_on_the_world_map(t: TestContext) -> void:
	var lair := WorldMapWindow.region_of(MAP_ID)
	if not t.check(not lair.is_empty(), "the Lair is no region's interior on the world map"):
		return
	for room: String in ["fatty-lair-r3-pit-hall", "fatty-lair-r13-fattys-arena", "fatty-lair-burr-cell"]:
		t.equal(str(WorldMapWindow.region_of(room).get("key", "")), str(lair.get("key", "")), "%s's region" % room)
		var label := WorldMapWindow.region_label(lair, PackedStringArray([MAP_ID]), room)
		t.check(label.ends_with(WorldMapWindow.CURRENT_TEXT), "%s is not the Lair's current area (%s)" % [room, label])


## While the Lair is sealed its room doors still go from room to room; only the ways out refuse.
func test_a_sealed_lair_lets_the_slime_from_room_to_room_but_not_out(t: TestContext) -> void:
	var run := Services.run()
	run.set_flag(LairDirector.FLAG_CALLED)
	if not await _enter(t, "r1-gatehouse"):
		return
	t.check(DungeonState.seal(run, MAP_ID, "fatty-one-eye", "test"), "the Lair did not seal")
	var out: Dictionary = t.main.call(&"request_exit", {"map_id": MAP_ID, "target_area_id": "level-1-d5",
		"target_door_id": "fatty-lair-mouth", "transition": "iris"})
	t.equal(str(out.get("status", "")), "blocked", "the way out of the sealed Lair")
	t.check(await _push_from(t, "r1-gatehouse", "r1-to-r2", true), "a sealed Lair's room door did not lead to R2")


## A faint in Fatty's arena wakes the slime at the Lair's entrance, in R1's world (respawn_elsewhere).
func test_a_faint_in_fattys_arena_wakes_at_the_entrance(t: TestContext) -> void:
	Services.run().set_flag(LairDirector.FLAG_CALLED)
	if not await _enter(t, "r1-gatehouse"):
		return
	var entrance := DungeonState.entrance(Services.run(), MAP_ID)
	if not t.check(not entrance.is_empty(), "R1 recorded no entrance"):
		return
	if not await _enter(t, "r13-fattys-arena"):
		return
	_faint(t)
	t.check(t.player().is_dead(), "the slime did not faint")
	var woke := await t.until(func() -> bool:
		return t.in_world(MAP_ID) and t.player() != null and not t.player().is_dead() and not bool(t.main.call(&"is_transitioning")), 8000.0, 10000.0)
	if not t.check(woke, "the slime did not wake in R1 (in %s)" % t.world().map_id()):
		return
	await t.steps(2)
	t.near_vec(t.player().get_centre(), Vector2(float(entrance["x"]), float(entrance["y"])), 2.0, "where the fainted slime woke")


## The Inner Stair (a stair door in the hub's north wall since 2026-10-24) goes to the Crypt's world
## and the slime comes out of the crypt's stair (its pair, `target_door`) facing down into the room,
## not the way it walked in (up).
func test_the_inner_stair_arrives_facing_out_of_the_crypts_stair(t: TestContext) -> void:
	var run := Services.run()
	run.set_flag(LairDirector.FLAG_CALLED)
	run.set_flag("fatty-lair.inner-stair-open")
	if not await _enter(t, "r3-pit-hall"):
		return
	var stair := _lair(t, "inner-stair")
	t.equal(str(stair.get(&"target_door")), "fatty-lair-crypt-north-stair", "the Inner Stair's pair")
	var rect: Rect2 = stair.get(&"trigger_rect")
	t.teleport_player(stair.global_position + rect.get_center())
	t.player().face(Vector2.UP)
	await t.steps(2)
	t.press(&"move_up")
	var down := await t.until(func() -> bool: return t.in_world("fatty-lair-r8-guard-crypt"), 5000.0)
	t.release(&"move_up")
	if not t.check(down, "the Inner Stair did not lead to the Crypt (in %s)" % t.world().map_id()):
		return
	await _settled(t)
	t.near_vec(t.player().get_facing(), Vector2.DOWN, 0.01, "the slime's facing at the stair's foot")


## The music carries on through a room door: the same track, not started over.
func test_the_music_carries_on_through_a_room_door(t: TestContext) -> void:
	if not await _enter(t, "r1-gatehouse"):
		return
	var music := Services.music()
	var before: AudioStreamPlayer = music.world_track() if music != null else null
	if before == null:
		t.note("no world track in this run: nothing to check")
		return
	if not t.check(await _push_from(t, "r1-gatehouse", "r1-to-r2", true), "R1's east door did not lead to R2"):
		return
	t.check(music.world_track() == before, "the room door started the music over")


# --- helpers ------------------------------------------------------------------------------------

## A hit the slime cannot survive (true damage), from a stand-in source.
func _faint(t: TestContext) -> void:
	var area: Area2D = t.player().get_damage_area()
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	router.route({"activation_id": activation, "source": source, "attack_area": attack, "target_area": area,
		"weapon_id": "test-hit", "weapon_tags": ["weapon"], "damage_types": ["physical"], "base_damage": 9999.0,
		"true_damage": true, "effects": [], "impact": {"position": area.global_position, "knock": Vector2.UP}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()


## Walks every room door of `room_names` with every lock opened: from its arrival spot it pushes
## out through the door and must come out in the target room at the far door's arrival spot, the
## screen scrolling.
func _walk_doors(t: TestContext, room_names: Array) -> void:
	_open_everything()
	var rooms := _layout_rooms()
	# Out of the world built before the records (the test starts in R1): every room built after them.
	if not await _enter(t, "r1-store"):
		return
	for room_name: String in room_names:
		if not await _enter(t, room_name):
			return
		_win_fights(t)
		var ids: Array[String] = []
		for door: Node in t.world().world_root.get_node("RoomDoors").get_children():
			ids.append(str(door.get(&"door_id")))
		for door_id: String in ids:
			if not t.in_world(rooms[room_name]["world"]):
				if not await _enter(t, room_name):
					return
				_win_fights(t)
			var room_door := t.world().world_root.get_node("RoomDoors/" + door_id) as Node2D
			if door_id == "r10-to-r9":
				# R9's stone door: held only while R10's statue stands on its plate.
				var plate := _objects(t).get_node("r10-plate") as Node2D
				(_objects(t).get_node("r10-statue") as Node2D).global_position = plate.global_position
				await t.until(func() -> bool: return bool(DungeonState.session_value(Services.run(), "fatty-lair.r10-plate-held", false)), 4000.0)
			var iris := str(room_door.get(&"transition")) == "iris"
			var target_room := str(room_door.get(&"target_room"))
			var target_door := str(room_door.get(&"target_door"))
			var inward: Vector2 = room_door.call(&"inward")
			_stand(t, room_door.global_position + inward * float(room_door.get(&"arrival_inset")))
			await t.steps(4)
			var action := _action(-inward)
			var scrolled := {"seen": false}
			t.press(action)
			var through := await t.until(func() -> bool:
				if t.main.get_node_or_null(^"ChunkScroll") != null:
					scrolled["seen"] = true
				return t.in_world(str(rooms[target_room]["world"])), PUSH_MS)
			t.release(action)
			if not t.check(through, "%s/%s did not lead to %s (in %s, feet %s)" % [room_name, door_id, target_room, t.world().map_id(), t.player_body().global_position]):
				continue
			await t.until(func() -> bool:
				if t.main.get_node_or_null(^"ChunkScroll") != null:
					scrolled["seen"] = true
				return not bool(t.main.call(&"is_transitioning")), 4000.0)
			await t.steps(2)
			# A door set to the iris (the closing circle: R1's store) does not scroll; it arrives in the
			# far doorway, between its arrival spot and the door's edge.
			if not iris:
				t.check(bool(scrolled["seen"]), "%s/%s did not scroll the screen" % [room_name, door_id])
			var far := t.world().world_root.get_node_or_null("RoomDoors/" + target_door) as Node2D
			if t.check(far != null, "%s has no door %s" % [target_room, target_door]):
				var spot: Vector2 = far.get_node("DoorScript").call(&"arrival_point")
				var slack := ARRIVAL_SLACK + (float(far.get(&"arrival_inset")) if iris else 0.0)
				t.check(t.player().get_centre().distance_to(spot) <= slack,
					"%s/%s came out at %s, not at %s's arrival %s" % [room_name, door_id, t.player().get_centre(), target_door, spot])


## Wins the room fights of the world the slime is in (RoomFight.finish_quietly): their shutters open.
## R4's fight is not `once`: its `starts_shut` shutters shut again each time its world is built.
func _win_fights(t: TestContext) -> void:
	for fight: Node in t.tree.get_nodes_in_group(&"room_fight"):
		fight.call(&"finish_quietly")


## Every lock of the Lair opened by its record (bolts slid, Burr's door and the boss door open,
## barricades smashed, the nook's gap clear, the latch doors open, R10's plate
## held), its fights won and Fatty fallen, so every doorway lets the slime through.
func _open_everything() -> void:
	var run := Services.run()
	run.set_flag(LairDirector.FLAG_CALLED)
	run.set_flag(LairDirector.FLAG_FREED)
	for flag: String in ["fatty-lair.store-smashed", "fatty-lair.larder-smashed", "fatty-lair.bolt-hole-smashed",
			"fatty-lair.nook-gap-open", "fatty-lair.inner-stair-open"]:
		run.set_flag(flag)
	for gate: String in ["fatty-lair-r5-inner", "fatty-lair-r5-alcove", "fatty-lair-weigh-east", "fatty-lair-weigh-west", "fatty-lair-r7-gate"]:
		run.mark_gate_unlocked(MAP_ID, gate)
	for done: String in ["fatty-lair-r5-way-back", "fatty-lair-r7-way-back", "fatty-lair-r9-way-back", "fatty-lair-r11-way-back",
			"fatty-lair-r1-shortcut", "fatty-lair-burr-cell", "fatty-lair-boss-door"]:
		var record: Dictionary = DungeonState.record(run, MAP_ID)
		(record["done"] as Array).append("%s:%s" % [MAP_ID, done])
	DungeonState.set_session_value(run, "fatty-lair.r10-plate-held", true)
	DungeonState.mark_boss_beaten(run, MAP_ID, "fatty-lair-big-squint")
	DungeonState.mark_boss_beaten(run, MAP_ID, "fatty-one-eye")
	(run.world.get_or_add("defeated_boss_ids", []) as Array).append("fatty-one-eye")


## The checks of `test_what_is_done_stays_done_across_rooms_and_a_load`, room by room.
func _check_kept(t: TestContext, plate_held: bool) -> void:
	var run := Services.run()
	t.check(DungeonState.has_item(run, MAP_ID, DungeonState.MAP), "the map is no longer held")
	t.equal(DungeonState.small_keys(run, MAP_ID), 1, "small keys held")
	t.check(DungeonState.is_sealed(run, MAP_ID), "the Lair is not sealed any more")
	if not await _enter(t, "map-nook"):
		return
	t.check(bool(_objects(t).get_node("nook-map-chest/ChestScript").call(&"is_empty")), "the nook's chest is full again")
	if not await _enter(t, "r7-bell-bridge"):
		return
	t.check(bool(_objects(t).get_node("r7-key-chest/ChestScript").call(&"is_empty")), "R7's key chest is full again")
	if not await _enter(t, "r14-postern"):
		return
	t.check(bool(_objects(t).get_node("r14-barricade").call(&"is_smashed")), "the Postern's planks are whole again")
	if not await _enter(t, "r9-watcher-hall"):
		return
	t.check(bool(_objects(t).get_node("r9-way-back").call(&"is_open")), "R9's bolt is shut again")
	t.equal(bool(_objects(t).get_node("r9-north-door/GateScript").call(&"is_open")), plate_held, "R9's north door open (R10's statue on its plate)")
	if not await _enter(t, "r8-guard-crypt"):
		return
	t.check((t.world().world_root.get_node("RoomDoors/r8-to-r9") as Node).call(&"refusal") == "", "R8's doorway to R9 still waits for R9's bolt")
	if not await _enter(t, "r12-larder"):
		return
	t.check(bool(_lair(t, "pearl-1").call(&"is_taken")), "Pearl 1 is back on its altar")
	if not await _enter(t, "r1-gatehouse"):
		return
	t.check(bool(_objects(t).get_node("r1-seal").call(&"is_shut")), "R1's seal is open while the Lair is sealed")


## Stands at `door_id`'s arrival spot in `room_name` and pushes out through it. True when the slime
## came out in the door's target room (`expect_through`: a failed check otherwise; else none).
func _push_from(t: TestContext, room_name: String, door_id: String, expect_through: bool) -> bool:
	if not await _enter(t, room_name):
		return false
	var room_door := t.world().world_root.get_node("RoomDoors/" + door_id) as Node2D
	var target := str(_layout_rooms()[str(room_door.get(&"target_room"))]["world"])
	var inward: Vector2 = room_door.call(&"inward")
	_stand(t, room_door.global_position + inward * float(room_door.get(&"arrival_inset")))
	await t.steps(4)
	var action := _action(-inward)
	t.press(action)
	var through := await t.until(func() -> bool: return t.in_world(target), 2500.0 if not expect_through else PUSH_MS)
	t.release(action)
	await _settled(t)
	return through


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


## The world of the layout's room `room_name` (R5's lower hall and key alcove are rooms of R5's world).
static func _world_of(room_name: String) -> String:
	return str(_layout_rooms()[room_name]["world"])


static func _action(direction: Vector2) -> StringName:
	if direction.y < -0.5:
		return &"move_up"
	if direction.y > 0.5:
		return &"move_down"
	return &"move_left" if direction.x < 0.0 else &"move_right"


func _enter(t: TestContext, room_name: String) -> bool:
	return await _travel(t, _world_of(room_name))


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
