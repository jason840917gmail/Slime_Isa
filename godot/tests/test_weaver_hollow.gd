extends RefCounted
## The Weaver Hollow, Chapter 2's dungeon, rebuilt one world per room (step 3 of the dungeons rework,
## entered since the switch-over of 2026-11-25: docs/godot/DUNGEONS.md "The Weaver Hollow rebuilt",
## "The Boughs", "The Crown", "The switch-over"; every room, door and record in the handover's lists
## of links, docs/handover/2026-11-23-dungeons-rework.md "Step 3"). The 23 room worlds are scenes in
## game/scenes/worlds/rooms/weaver-hollow/ on its map layout, one dungeon (`weaver-hollow`), resumed
## at T1. Positions are the room's own (cells of 64 from its top-left), most of them where
## tools/film_weaver_hollow_rooms.gd's walk stands the slime.
##
## Every room is a world of the Hollow on its layout; every room door pairs with one in the opposite
## wall that leads back; the stairs pair up, the drops land on their landings, and nothing leads to a
## retired floor. The forecourt's root gate holds until a Goo Bomb blows it and leads into T1, whose
## way out leads back to it. The Larder's cracks open the Well Room and the map nook once blown; the
## Well Room's cracked floor drops onto R1's ledge; R3's ram bursts the bricked arch before the Guard's
## stair; the gallery's winch opens the hub's stair for good; key 1 opens the hub's south door and the
## big key the Crown Door; three small keys for three keyholes, one big key, one map, one compass. B2's
## cracked post lowers its drawbridge, B7's kegs chain to the pillar's post; the Nursery's ambush (the
## optional wing); the Mimic's key 2; the Brood Warden's fight guards Pearl 2, whose take grants the
## Silk skin and seals the Hollow (a Warden beaten in the retired Boughs opens the Hoard's shutter when B5
## is built); the webs only the Silk slime passes (the Hoard's stair, the Spinning Loft's rows, C1's
## flight); the Crown's shutter; the seals in T1's way out and C2's east doorway, broken by her fall;
## C3's drop to the forecourt. Old saves: the prizes keep the old floors' records (none is had twice), and a
## save standing in one of the retired floors wakes in T1 with its record (RunState `moved_world`).
## Her fight itself: tests/test_matron.gd.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const GooBlast := preload("res://game/player/abilities/goo_blast.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const DungeonKeyPickup := preload("res://game/dungeon/dungeon_key_pickup.gd")
const DungeonSeal := preload("res://game/dungeon/dungeon_seal.gd")
const SilkParcelScript := preload("res://game/scripts/silk_parcel.gd")
const WebWallScript := preload("res://game/scripts/web_wall.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const ChestRoot := preload("res://game/scripts/chest_root.gd")
const KeyDoorType := preload("res://game/dungeon/key_door.gd")
const LandingType := preload("res://game/scripts/landing.gd")
const BossCampType := preload("res://game/scripts/boss_camp.gd")
const WebLayerType := preload("res://game/world/webs/web_layer.gd")
const RunStateScript := preload("res://game/autoload/run_state.gd")

const DUNGEON_ID := "weaver-hollow"
const ROOM := "weaver-hollow-%s"
const SCENE := "res://game/scenes/worlds/rooms/weaver-hollow/%s.tscn"
const LAYOUT := "res://game/scenes/worlds/rooms/weaver-hollow/layout.tscn"
const SCENE_INDEX := "res://game/scenes/scene_index.json"
const ROOM_DOOR_SCENE := "res://game/scenes/objects/dungeon/room-door.tscn"
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
const CELL := 64.0
## The Matron (the Hollow's boss: her fall breaks the seals) and the Brood Warden (Pearl 2's guard).
const MATRON := "orb-weaver-matron"
const WARDEN := "weaver-hollow-brood-warden"
## The rooms (the handover's lists: the Trunk, the Roots, the Boughs, the Crown) and their room doors.
const ROOM_NAMES: PackedStringArray = ["t1-root-door", "t2-hollow-heart", "t3-larder", "t3-map-nook", "t4-well-room",
	"r1-root-fall", "r2-bone-cellar", "r2-compass-pocket", "r3-ram-cellar", "d1-old-cellar", "stair-foot",
	"b1-bough-stair", "b2-drawbridge", "b3-mimics-pantry", "b4-nursery", "b5-wardens-den", "hoard", "b6-spinning-loft",
	"b7-pillar", "d2-dark-bough", "c1-crown-stair", "c2-crown", "c3-outer-bough"]
const ROOM_DOORS := 50
const T1 := "weaver-hollow-t1-root-door"
## The forecourt (the Watch Oak's chunk), its root gate (the way in, blown by a Goo Bomb) and the
## landing of C3's drop, with their door ids.
const FORECOURT := "gloop-forest-f4"
const ROOT_GATE := "weaver-hollow-forecourt/root-gate"
const ROOT_GATE_DOOR := "weaver-hollow-root-gate"
const SILK_DROP := "weaver-hollow-forecourt/weaver-hollow-silk-drop"
const SILK_DROP_DOOR := "weaver-hollow-silk-drop"
const ENTRANCE_DOOR := "weaver-hollow-entrance"
## The four floor worlds, retired: a save standing in one wakes in T1 (RunState RETIRED_WORLDS).
const OLD_FLOORS: PackedStringArray = ["weaver-hollow-trunk", "weaver-hollow-roots", "weaver-hollow-boughs", "weaver-hollow-crown"]
## The prizes that keep the old floors' records (so an old save never has one twice): [room, chest root,
## the old chest id, the old map id], and S2's parcels [room, parcel, the old flag].
const PRIZE_CHESTS := [
	["d1-old-cellar", "Objects/d1-old-cellar-chest", "weaver-hollow-roots-old-cellar-chest", "weaver-hollow-roots"],
	["d2-dark-bough", "Objects/d2-chest-variant/shown/d2-dark-bough-chest", "weaver-hollow-boughs-dark-bough-chest", "weaver-hollow-boughs"],
	["b4-nursery", "Objects/b4-nursery-chest", "weaver-hollow-boughs-nursery-chest", "weaver-hollow-boughs"],
]
const PRIZE_PARCELS := [
	["b3-mimics-pantry", "Objects/b3-s2-parcel-0", "weaver-hollow.s2-parcel-0"],
	["b3-mimics-pantry", "Objects/b3-s2-parcel-1", "weaver-hollow.s2-parcel-1"],
	["b3-mimics-pantry", "Objects/b3-s2-parcel-2", "weaver-hollow.s2-parcel-2"],
]
## The stairs between rooms, each leading to the other: [room, stair, room, stair].
const STAIRS := [
	["t4-well-room", "Objects/t4-guard-stair", "r3-ram-cellar", "Objects/r3-guard-stair"],
	["stair-foot", "Objects/sf-stair", "b1-bough-stair", "Objects/b1-stair"],
]
## The one-way drops: [room, the node holding the door's target, room below, its landing].
const DROPS := [
	["t4-well-room", "Objects/t4-well-floor", "r1-root-fall", "Objects/r1-landing"],
	["b3-mimics-pantry", "Objects/b3-rafter-hole/DoorScript", "t2-hollow-heart", "Objects/gallery-landing"],
]
## Where the slime stands (cells), from the walk's film: T1's way out; the hub's south key door, the
## Crown Door on the north gallery, the stair's foot, the winch, the stair's top; R3's Guard's stair;
## B2's west rim by the bridge (and the east rim's edge past it); B6 between its rows; the Hoard's
## stair below its web wall; C1's flight foot and its key 3 door; C3's walk west of her web wall and its
## hole.
const T1_WAY_OUT := Vector2(9.0, 13.2)
const T2_KEY_DOOR := Vector2(9.0, 28.5)
const T2_CROWN_DOOR := Vector2(17.0, 2.8)
const T2_STAIR_FOOT := Vector2(25.0, 8.4)
const T2_WINCH := Vector2(22.2, 4.6)
const T2_STAIR_TOP := Vector2(24.9, 5.2)
const R3_STAIR := Vector2(11.0, 2.6)
const B2_WEST_RIM := Vector2(16.2, 7.6)
const B2_EAST_RIM_X := 21.2
const B6_BETWEEN_ROWS := Vector2(14.4, 7.4)
const HOARD_STAIR := Vector2(4.0, 12.4)
const C1_FLIGHT_FOOT := Vector2(9.0, 12.4)
const C1_K3_DOOR := Vector2(9.0, 2.8)
const C3_WALK := Vector2(3.6, 4.0)
const C3_DROP := Vector2(12.3, 4.0)
## A room's floor starts two cells in (its rim), an 18-column room's floor ends at column 16.
const RIM_CELLS := 2.0
const ROOM_COLUMNS := 18.0
const PUSH_MS := 5000.0
const HELD_MS := 1500.0


# --- the rooms and their links ----------------------------------------------------------------------

func test_every_room_is_a_world_of_the_hollow_on_its_layout(t: TestContext) -> void:
	var rooms := _layout_rooms()
	t.equal(rooms.size(), ROOM_NAMES.size(), "rooms on the Hollow's layout")
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCENE_INDEX))
	for room_name: String in ROOM_NAMES:
		var world_id := ROOM % room_name
		if not t.check(rooms.has(room_name), "%s is not on the Hollow's layout" % room_name):
			continue
		var room: Dictionary = rooms[room_name]
		t.equal(str(room["world"]), world_id, "%s's world on the layout" % room_name)
		t.equal(str(index.get("world." + world_id, "")), str(room["scene"]), "%s's world in the scene index" % room_name)
		var scene := (load(str(room["scene"])) as PackedScene).instantiate()
		var definition := scene.get_node_or_null(^"world-definition")
		if t.check(definition != null, "%s has no world-definition" % room_name):
			t.equal(str(definition.get(&"map_id")), world_id, "%s's map id" % room_name)
		var camera := scene.get_node_or_null(NodePath("CameraRooms/" + room_name)) as Node2D
		t.check(camera != null, "%s has no camera room of its own" % room_name)
		var dungeon := scene.get_node_or_null(^"Dungeon")
		if t.check(dungeon != null, "%s has no Dungeon node" % room_name):
			t.equal([str(dungeon.get(&"dungeon_id")), str(dungeon.get(&"record_map_id")), str(dungeon.get(&"entrance_map_id")),
					str(dungeon.get(&"boss_id"))], [DUNGEON_ID, DUNGEON_ID, T1, MATRON], "%s's Dungeon (id, records, entrance, boss)" % room_name)
			var layout: Variant = dungeon.get(&"layout")
			t.check(layout is PackedScene and (layout as PackedScene).resource_path == LAYOUT, "%s's Dungeon has another layout" % room_name)
		t.equal(DungeonState.world_dungeon_id(world_id), DUNGEON_ID, "%s read as a world of the Hollow" % room_name)
		t.equal(DungeonState.world_record_id(world_id), DUNGEON_ID, "%s keeps its records under the Hollow's" % room_name)
		# The Hollow resumes at T1's entrance marker (a faint, a quit).
		if room_name == "t1-root-door" and camera != null:
			var entrance := scene.get_node_or_null(^"dungeon-entrance") as Node2D
			if t.check(entrance != null, "T1 has no dungeon-entrance marker"):
				t.check(Rect2(camera.position, camera.get(&"size")).has_point(entrance.position), "T1's entrance marker is outside its room")
		scene.free()


func test_every_room_door_pairs_with_one_in_the_opposite_wall_that_leads_back(t: TestContext) -> void:
	var rooms := _layout_rooms()
	var doors := {}
	for room_name: String in ROOM_NAMES:
		if not t.check(rooms.has(room_name), "%s is not on the layout" % room_name):
			continue
		var scene := (load(str(rooms[room_name]["scene"])) as PackedScene).instantiate()
		for door: Node in _room_doors(scene):
			var key := "%s/%s" % [room_name, str(door.get(&"door_id"))]
			t.check(not doors.has(key), "two doors %s" % key)
			doors[key] = {"target": "%s/%s" % [str(door.get(&"target_room")), str(door.get(&"target_door"))], "side": str(door.get(&"side"))}
			# The editor's own check: the far door exists, stands in the opposite wall and leads back.
			t.equal(str(door.call(&"pairing_problem")), "", "%s's link" % key)
		scene.free()
	t.equal(doors.size(), ROOM_DOORS, "room doors in the Hollow")
	for key: String in doors:
		var door: Dictionary = doors[key]
		var far: Variant = doors.get(door["target"])
		if not t.check(far is Dictionary, "%s leads to %s, which does not exist" % [key, door["target"]]):
			continue
		t.equal(str((far as Dictionary)["target"]), key, "%s's far door does not lead back to it" % key)
		t.equal(str((far as Dictionary)["side"]), str(OPPOSITE.get(door["side"], "")), "%s's far door is not in the opposite wall" % key)


func test_the_stairs_and_drops_between_rooms_land_on_their_pair_and_nothing_leads_to_a_retired_floor(t: TestContext) -> void:
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCENE_INDEX))
	var scenes := {}
	for room_name: String in ROOM_NAMES:
		scenes[room_name] = (load(SCENE % room_name) as PackedScene).instantiate()
	# The stairs (the Guard's stair from R3 up to T4's ledge, the stair foot's up to B1): each leads to
	# the other's world and names it.
	for pair: Array in STAIRS:
		var a := (scenes[pair[0]] as Node).get_node_or_null(NodePath(str(pair[1])))
		var b := (scenes[pair[2]] as Node).get_node_or_null(NodePath(str(pair[3])))
		if not t.check(a != null and b != null, "no stair %s/%s or %s/%s" % pair):
			continue
		t.equal([str(a.get(&"target_world")), str(a.get(&"target_door"))], [ROOM % str(pair[2]), str(b.get(&"hatch_id"))],
				"%s/%s's way" % [pair[0], pair[1]])
		t.equal([str(b.get(&"target_world")), str(b.get(&"target_door"))], [ROOM % str(pair[0]), str(a.get(&"hatch_id"))],
				"%s/%s's way" % [pair[2], pair[3]])
		t.check(bool(a.get(&"start_open")) and bool(b.get(&"start_open")), "the stair %s/%s is shut" % [pair[0], pair[1]])
	# The drops (T4's cracked floor onto R1's ledge, B3's rafter hole onto the hub's gallery): one way,
	# onto a landing in the room below.
	for drop: Array in DROPS:
		var from := (scenes[drop[0]] as Node).get_node_or_null(NodePath(str(drop[1])))
		var landing := (scenes[drop[2]] as Node).get_node_or_null(NodePath(str(drop[3])))
		if not t.check(from != null and landing != null and landing.get_script() == LandingType, "no drop %s/%s or no landing %s/%s" % drop):
			continue
		t.equal([str(from.get(&"target_area_id")), str(from.get(&"target_door_id"))], [ROOM % str(drop[2]), str(landing.get(&"door_id"))],
				"%s/%s's drop" % [drop[0], drop[1]])
	# The ways out, both to the forecourt: T1's way out to the root gate, C3's hole by S1's nook.
	var way_out := (scenes["t1-root-door"] as Node).get_node_or_null(^"Objects/weaver-hollow-entrance/DoorScript")
	if t.check(way_out != null, "T1 has no way out"):
		t.equal([str(way_out.get(&"door_id")), str(way_out.get(&"target_area_id")), str(way_out.get(&"target_door_id")), str(way_out.get(&"side"))],
				[ENTRANCE_DOOR, FORECOURT, ROOT_GATE_DOOR, "south"], "T1's way out")
	var hole := (scenes["c3-outer-bough"] as Node).get_node_or_null(^"Objects/c3-drop/DoorScript")
	if t.check(hole != null, "C3 has no hole"):
		t.equal([str(hole.get(&"target_area_id")), str(hole.get(&"target_door_id")), str(hole.get(&"kind"))],
				[FORECOURT, SILK_DROP_DOOR, "fall"], "C3's hole")
	# Every crossing that names a world names one that exists, never one of the retired four floors.
	for room_name: String in scenes:
		var scene: Node = scenes[room_name]
		for node: Node in scene.find_children("*", "", true, false):
			for property: StringName in [&"target_area_id", &"target_world"]:
				var target: Variant = node.get(property)
				if not target is String or (target as String).is_empty():
					continue
				t.check(index.has("world." + str(target)) and not OLD_FLOORS.has(str(target)),
						"%s/%s leads to %s" % [room_name, scene.get_path_to(node), target])
	for room_name: String in scenes:
		(scenes[room_name] as Node).free()


func test_three_small_keys_for_three_keyholes_one_big_key_for_the_crown_door_one_map_one_compass(t: TestContext) -> void:
	var counts := {"small": 0, "big": 0, "map": 0, "compass": 0, "keyholes": 0, "big_locks": 0}
	for room_name: String in ROOM_NAMES:
		var root := (load(SCENE % room_name) as PackedScene).instantiate()
		for node: Node in root.find_children("*", "", true, false):
			# The chests (key 1 on the hub's gallery, the big key on B3's rafters, the map, the compass).
			if node.get_script() == ChestRoot:
				_count_contents(counts, node.get(&"contents"))
			# A key wrapped in silk (key 3, the Spinning Loft's parcel) drops as the kit's floor key.
			if node.get_script() == SilkParcelScript:
				_count_contents(counts, node.get(&"contents"))
			if node.get_script() == DungeonKeyPickup:
				counts["small" if str(node.get(&"item")) == "small-key" else "big"] += 1
			# A key swallowed (key 2, the Mimic's).
			var overrides: Variant = node.get(&"overrides")
			if overrides is Dictionary and str((overrides as Dictionary).get("swallowed_scene_id", "")) == "object.dungeon-key":
				var settings: Dictionary = (overrides as Dictionary).get("swallowed_settings", {})
				counts["small" if str(settings.get("item", "")) == "small-key" else "big"] += 1
			if node.get_script() == KeyDoorType:
				if str(node.get(&"lock")) == "big":
					counts["big_locks"] += 1
				else:
					counts["keyholes"] += int(node.get(&"keyholes"))
		root.free()
	t.equal(counts["small"], 3, "the Hollow's small keys")
	t.equal(counts["keyholes"], counts["small"], "keyholes for the small keys")
	t.equal(counts["big"], 1, "the Hollow's big keys")
	t.equal(counts["big_locks"], 1, "the Hollow's big-key doors")
	t.equal(counts["map"], 1, "the Hollow's maps")
	t.equal(counts["compass"], 1, "the Hollow's compasses")


# --- the way in --------------------------------------------------------------------------------------

## The forecourt's root gate (the switch-over of 2026-11-25): bricked, it holds; a Goo Bomb's blast
## blows it for good, and up through it the slime walks into the rebuilt T1, which records itself as
## the Hollow's entrance; T1's room doors scroll to the hub and back; T1's way out lands at the gate.
func test_the_forecourts_root_gate_holds_until_blown_and_leads_into_t1_and_out_again(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, FORECOURT):
		return
	var gate := t.world().world_root.get_node_or_null(ROOT_GATE) as Node2D
	if not t.check(gate != null, "the forecourt has no root gate"):
		return
	t.equal([str(gate.get(&"flag_id")), str(gate.get(&"door_id")), str(gate.get(&"target_area_id")), str(gate.get(&"target_door_id"))],
			["weaver-hollow.root-gate", ROOT_GATE_DOOR, T1, ENTRANCE_DOOR], "the root gate's flag and where it leads")
	var flag := str(gate.get(&"flag_id"))
	t.check(not run.has_flag(flag) and not bool(gate.call(&"is_broken")), "the root gate starts blown")
	var front := gate.global_position + (gate.get(&"arrival_offset") as Vector2)
	# Bricked, it holds the slime out.
	_stand(t, front)
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(900.0)
	t.release(&"move_up")
	t.check(t.in_world(FORECOURT) and not bool(t.main.call(&"is_transitioning")), "the bricked root gate let the slime in")
	# A blast at its foot (the slime stood back) blows it for good.
	_stand(t, gate.global_position + Vector2(0.0, 3.0 * CELL))
	await t.steps(2)
	GooBlast.detonate(gate.global_position + Vector2(0.0, 20.0), false)
	t.check(await t.until(func() -> bool: return run.has_flag(flag), 1000.0), "a blast at its foot did not blow the root gate")
	await t.sim_wait(400.0)
	# Up through the hole: the rebuilt T1, by its way out, recorded as the Hollow's entrance.
	_stand(t, front)
	await t.steps(2)
	t.press(&"move_up")
	var inside := await t.until(func() -> bool: return t.in_world(T1), PUSH_MS)
	t.release(&"move_up")
	if not t.check(inside, "the blown root gate did not lead into T1 (in %s)" % t.world().map_id()):
		return
	await _settled(t)
	var way_out := _object(t, "weaver-hollow-entrance")
	t.check(way_out != null and t.player_body().global_position.distance_to(way_out.global_position) < 3.0 * CELL,
			"the slime did not come in by T1's way out (feet %s)" % t.player_body().global_position)
	t.equal(str(DungeonState.entrance(run, DUNGEON_ID).get("map_id", "")), T1, "T1 does not record itself as the Hollow's entrance")
	# T1's north doorway scrolls into the hub, and the hub's back.
	_calm(t)
	t.check(await _push_through(t, "t1-north", ROOM % "t2-hollow-heart"), "T1's north doorway did not lead into the hub")
	_calm(t)
	t.check(await _push_through(t, "t2-south-t1", T1), "the hub's south doorway did not lead back into T1")
	# T1's way out: down out of its south doorway to the forecourt, at the gate (blown for good).
	_stand(t, T1_WAY_OUT * CELL)
	await t.steps(2)
	t.press(&"move_down")
	var out := await t.until(func() -> bool: return t.in_world(FORECOURT), PUSH_MS)
	t.release(&"move_down")
	if not t.check(out, "T1's way out did not lead to the forecourt (in %s)" % t.world().map_id()):
		return
	await _settled(t)
	gate = t.world().world_root.get_node_or_null(ROOT_GATE) as Node2D
	if t.check(gate != null, "no root gate after coming out"):
		t.check(bool(gate.call(&"is_broken")), "the root gate is whole again")
		t.check(t.player_body().global_position.distance_to(gate.global_position) < 2.0 * CELL,
				"T1's way out does not land at the root gate (%.0f px from it)" % t.player_body().global_position.distance_to(gate.global_position))


# --- the Trunk and the Roots ------------------------------------------------------------------------

## The Larder's two cracks (each a room door that waits for its flag): shut, they hold the slime in
## the Larder; blown, the north one leads into the Well Room (its own side blown with the same flag),
## the west one into the map nook (the iris), whose chest holds the map.
func test_the_larders_cracks_open_the_well_room_and_the_map_nook_once_blown(t: TestContext) -> void:
	var run := Services.run()
	for crack: Array in [["t3-crack-well", "t3-north-crack", "t4-well-room"], ["t3-crack-nook", "t3-west-nook", "t3-map-nook"]]:
		if not await _enter(t, ROOM % "t3-larder"):
			return
		_calm(t)
		var wall := _object(t, str(crack[0]))
		var door := t.world().world_root.get_node_or_null(NodePath("RoomDoors/" + str(crack[1]))) as Node2D
		if not t.check(wall != null and door != null, "the Larder has no %s or no %s" % [crack[0], crack[1]]):
			continue
		var flag := str(wall.get(&"flag_id"))
		t.check(not run.has_flag(flag), "%s starts blown" % crack[0])
		t.equal(str(door.get(&"requires")), "flag:" + flag, "%s waits for %s's flag" % [crack[1], crack[0]])
		var through_shut := await _push_through(t, str(crack[1]), ROOM % str(crack[2]), HELD_MS)
		t.check(not through_shut, "%s let the slime through shut" % crack[0])
		if through_shut and not await _enter(t, ROOM % "t3-larder"):
			return
		wall = _object(t, str(crack[0]))
		door = t.world().world_root.get_node_or_null(NodePath("RoomDoors/" + str(crack[1]))) as Node2D
		# A blast at its foot (the slime stood back) opens it for good.
		var inward: Vector2 = door.call(&"inward")
		_stand(t, wall.global_position + inward * 3.0 * CELL)
		await t.steps(2)
		GooBlast.detonate(wall.global_position + inward * 30.0, false)
		t.check(await t.until(func() -> bool: return run.has_flag(flag), 1000.0), "a blast did not open %s" % crack[0])
		await t.sim_wait(400.0)
		if not t.check(await _push_through(t, str(crack[1]), ROOM % str(crack[2])), "%s did not lead on once blown" % crack[0]):
			continue
		if str(crack[2]) == "t4-well-room":
			var far := _object(t, "t4-crack-larder")
			t.check(far != null and bool(far.call(&"is_broken")), "the Well Room's side of the crack is whole")
		else:
			var chest := _object(t, "t3-map-chest")
			var script := chest.get_node_or_null(^"ChestScript") if chest != null else null
			if t.check(script != null, "the map nook has no chest"):
				t.equal(str(script.call(&"request_open")), "opened", "the map nook's chest")
				t.check(DungeonState.has_item(run, DUNGEON_ID, DungeonState.MAP), "the map nook's chest did not give the map")


## The Well Room's cracked floor: shut, it holds; blown, a fall (one way) onto R1's landing ledge.
func test_the_well_rooms_cracked_floor_drops_onto_r1s_landing_ledge(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, ROOM % "t4-well-room"):
		return
	var crack := _object(t, "t4-well-floor") as Node2D
	if not t.check(crack != null, "the Well Room has no cracked floor"):
		return
	var flag := str(crack.get(&"flag_id"))
	t.check(not run.has_flag(flag), "the Well Room's floor starts broken")
	var below := crack.global_position + Vector2(0.0, 1.2 * CELL)
	_stand(t, below)
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(700.0)
	t.release(&"move_up")
	t.check(t.in_world(ROOM % "t4-well-room") and not bool(t.main.call(&"is_transitioning")), "the slime fell through the floor whole")
	_stand(t, crack.global_position + Vector2(0.0, 3.0 * CELL))
	await t.steps(2)
	GooBlast.detonate(crack.global_position, false)
	t.check(await t.until(func() -> bool: return run.has_flag(flag), 1000.0), "a blast did not break the Well Room's floor")
	await t.sim_wait(1500.0)
	_stand(t, below)
	await t.steps(2)
	t.press(&"move_up")
	var fell := await t.until(func() -> bool: return t.in_world(ROOM % "r1-root-fall"), PUSH_MS)
	t.release(&"move_up")
	if not t.check(fell, "the broken floor did not drop the slime into R1 (in %s)" % t.world().map_id()):
		return
	await _settled(t)
	await t.sim_wait(600.0)
	t.equal(_level(t), 1, "the slime's level in R1 (on its landing ledge)")


## R3: the bricked arch holds the Guard's stair; its knock target (a thrown thing knocks it: the walk
## throws a pot over the void) lets the ram go, whose log bursts the arch for good; up the stair the
## slime comes out on T4's ledge, above the room it left.
func test_r3s_ram_bursts_the_bricked_arch_and_the_guards_stair_climbs_to_t4s_ledge(t: TestContext) -> void:
	if not await _enter(t, ROOM % "r3-ram-cellar"):
		return
	var arch := _object(t, "r3-arch")
	var target := _object(t, "r3-target")
	var ram := _object(t, "r3-ram")
	if not t.check(arch != null and target != null and ram != null, "R3 has no arch, no target or no ram"):
		return
	t.check(not bool(arch.call(&"is_burst")), "R3's arch starts burst")
	t.check(ram.call(&"get_knock_target") == target, "R3's target does not hold its ram")
	_stand(t, R3_STAIR * CELL)
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(1000.0)
	t.release(&"move_up")
	t.check(t.in_world(ROOM % "r3-ram-cellar"), "the bricked arch let the slime up the stair")
	# Off the ram's lane, the target knocked: the log bursts the arch.
	_stand(t, Vector2(3.0, 8.0) * CELL)
	await t.steps(2)
	target.call(&"strike")
	t.check(await t.until(func() -> bool: return bool(arch.call(&"is_burst")), 3000.0), "the ram's log did not burst the bricked arch")
	await t.sim_wait(DungeonState.number("ram.holdMs", 150.0) + DungeonState.number("ram.returnMs", 600.0) + 100.0)
	_stand(t, R3_STAIR * CELL)
	await t.steps(2)
	t.press(&"move_up")
	var up := await t.until(func() -> bool: return t.in_world(ROOM % "t4-well-room"), 8000.0)
	t.release(&"move_up")
	if not t.check(up, "the Guard's stair did not climb to T4 (in %s)" % t.world().map_id()):
		return
	await _settled(t)
	await t.sim_wait(600.0)
	t.check(_level(t) == 1 and t.player_body().global_position.x > 12.9 * CELL,
			"out of the stair not on T4's ledge (level %d, feet %s)" % [_level(t), t.player_body().global_position])
	if await _enter(t, ROOM % "r3-ram-cellar"):
		t.check(bool(_object(t, "r3-arch").call(&"is_burst")), "R3's arch stood whole again when R3 was built again")


## The hub's gallery stair: a stone block holds its foot; the winch on the gallery sinks it for good.
func test_the_gallerys_winch_opens_the_hubs_stair_for_good(t: TestContext) -> void:
	if not await _enter(t, ROOM % "t2-hollow-heart"):
		return
	_calm(t)
	var block := _object(t, "t2-stair-block")
	var winch := _object(t, "t2-winch")
	if not t.check(block != null and winch != null, "the hub has no stair block or no winch"):
		return
	t.check(bool(block.call(&"is_shut")), "the hub's stair starts open")
	var targets: Array = winch.get(&"targets")
	t.check(not targets.is_empty() and winch.get_node_or_null(targets[0] as NodePath) == block, "the winch does not hold the stair block")
	# From the hub's floor the block holds the stair.
	_stand(t, T2_STAIR_FOOT * CELL)
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(900.0)
	t.release(&"move_up")
	t.check(_level(t) == 0 and t.player_body().global_position.y > 7.0 * CELL, "the slime climbed past the stair's block")
	# On the gallery the winch, pushed, sinks it.
	_stand(t, T2_WINCH * CELL)
	t.equal(_level(t), 1, "the slime's level on the gallery")
	t.press(&"move_up")
	var turned := await t.until(func() -> bool: return bool(winch.call(&"is_turned")), 3000.0)
	t.release(&"move_up")
	t.check(turned, "pushing the gallery's winch did not turn it")
	t.check(await t.until(func() -> bool: return not bool(block.call(&"is_shut")), 2000.0), "the winch did not sink the stair block")
	# Down the stair to the floor.
	_stand(t, T2_STAIR_TOP * CELL)
	await t.steps(2)
	t.press(&"move_down")
	await t.sim_wait(2000.0)
	t.release(&"move_down")
	await t.steps(10)
	t.check(_level(t) == 0 and t.player_body().global_position.y > 7.0 * CELL, "the open stair did not lead down to the hub's floor")
	if await _enter(t, T1) and await _enter(t, ROOM % "t2-hollow-heart"):
		t.check(not bool(_object(t, "t2-stair-block").call(&"is_shut")), "the stair shut again when the hub was built again")


## Key 1 opens the hub's south door (for good, the key spent) to the stair foot; the Crown Door on the
## north gallery wants the big key, which opens it into C1 and stays held.
func test_key_1_opens_the_hubs_south_door_and_the_big_key_the_crown_door(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, ROOM % "t2-hollow-heart"):
		return
	_calm(t)
	var south := _object(t, "t2-south-door")
	var crown := _object(t, "t2-crown-door")
	if not t.check(south != null and crown != null, "the hub has no south door or no Crown Door"):
		return
	t.equal([str(south.get(&"lock")), int(south.get(&"keyholes")), str(crown.get(&"lock"))], ["small", 1, "big"], "the hub's locks")
	_stand(t, T2_KEY_DOOR * CELL)
	await t.steps(2)
	t.press(&"move_down")
	await t.sim_wait(900.0)
	t.release(&"move_down")
	t.check(t.in_world(ROOM % "t2-hollow-heart") and t.player_body().global_position.y < 30.0 * CELL, "the south door let the slime through without key 1")
	DungeonState.add_small_key(run, DUNGEON_ID, 1)
	_stand(t, T2_KEY_DOOR * CELL)
	await t.steps(2)
	t.press(&"move_down")
	var through := await t.until(func() -> bool: return t.in_world(ROOM % "stair-foot"), PUSH_MS)
	t.release(&"move_down")
	t.check(through, "key 1 did not open the south door onto the stair foot (in %s)" % t.world().map_id())
	t.equal(DungeonState.small_keys(run, DUNGEON_ID), 0, "small keys after the south door")
	if not await _enter(t, ROOM % "t2-hollow-heart"):
		return
	t.check(bool(_object(t, "t2-south-door").call(&"is_open")), "the south door shut again")
	_calm(t)
	_stand(t, T2_CROWN_DOOR * CELL)
	t.equal(_level(t), 1, "the slime's level on the north gallery")
	t.press(&"move_up")
	await t.sim_wait(900.0)
	t.release(&"move_up")
	t.check(t.in_world(ROOM % "t2-hollow-heart") and t.player_body().global_position.y > 2.0 * CELL, "the Crown Door let the slime through without the big key")
	DungeonState.give_item(run, DUNGEON_ID, DungeonState.BIG_KEY)
	_stand(t, T2_CROWN_DOOR * CELL)
	await t.steps(2)
	t.press(&"move_up")
	var crowned := await t.until(func() -> bool: return t.in_world(ROOM % "c1-crown-stair"), PUSH_MS)
	t.release(&"move_up")
	if not t.check(crowned, "the big key did not open the Crown Door into C1 (in %s)" % t.world().map_id()):
		return
	await _settled(t)
	t.equal(_level(t), 0, "the slime's level in C1 (its floor)")
	t.check(DungeonState.has_item(run, DUNGEON_ID, DungeonState.BIG_KEY), "the big key was spent")


# --- the Boughs --------------------------------------------------------------------------------------

func test_a_bomb_on_b2s_cracked_post_lowers_its_drawbridge_over_the_void(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, ROOM % "b2-drawbridge"):
		return
	var bridge := _object(t, "b2-bridge")
	var post := _object(t, "b2-bridge-post")
	if not t.check(bridge != null and post != null, "B2 has no drawbridge or no cracked post"):
		return
	t.check(not bool(bridge.call(&"holds")), "B2's drawbridge starts down")
	t.check(post.get_node_or_null(post.get(&"target_path") as NodePath) == bridge, "B2's post does not hold its bridge")
	_stand(t, B2_WEST_RIM * CELL)
	await t.steps(4)
	GooBlast.detonate((post.call(&"blast_point") as Vector2) + Vector2(0.0, 12.0), false)
	t.check(await t.until(func() -> bool: return bool(bridge.call(&"holds")), 3000.0), "the blown post did not lower the bridge")
	t.check(run.has_flag(str(post.get(&"flag_id"))), "the blown post's flag")
	_stand(t, B2_WEST_RIM * CELL)
	await t.steps(4)
	t.press(&"move_right")
	await t.sim_wait(2300.0)
	t.release(&"move_right")
	t.check(t.in_world(ROOM % "b2-drawbridge") and t.player_body().global_position.x > B2_EAST_RIM_X * CELL,
			"the drawbridge did not carry the slime over the void (feet %s)" % t.player_body().global_position)
	if await _enter(t, ROOM % "b1-bough-stair") and await _enter(t, ROOM % "b2-drawbridge"):
		t.check(bool(_object(t, "b2-bridge").call(&"holds")), "B2's drawbridge stood up again when B2 was built again")


## B7, the optional wing's end: a blast on the first of the parapet's kegs chains along them to the
## pillar's cracked post, which lowers the drawbridge to the far shore.
func test_b7s_kegs_chain_to_the_pillars_post_and_its_bridge(t: TestContext) -> void:
	if not await _enter(t, ROOM % "b7-pillar"):
		return
	var bridge := _object(t, "b7-bridge")
	var keg := _object(t, "b7-keg-0")
	var post := _object(t, "b7-pillar-post")
	if not t.check(bridge != null and keg != null and post != null, "B7 has no drawbridge, no kegs or no post"):
		return
	t.check(not bool(bridge.call(&"holds")), "B7's bridge starts down")
	_stand(t, Vector2(4.0, 10.6) * CELL)
	await t.steps(4)
	GooBlast.detonate(keg.global_position, false)
	t.check(await t.until(func() -> bool: return bool(bridge.call(&"holds")), 6000.0), "the kegs' chain did not reach the pillar's post and its bridge")
	t.check(bool(post.call(&"is_broken")), "the pillar's post is whole")
	_stand(t, Vector2(4.0, 10.6) * CELL)
	await t.steps(4)
	t.press(&"move_up")
	await t.sim_wait(2400.0)
	t.release(&"move_up")
	t.check(t.in_world(ROOM % "b7-pillar") and t.player_body().global_position.y < 6.0 * CELL,
			"the pillar's bridge did not carry the slime to the far shore (feet %s)" % t.player_body().global_position)


func test_the_nurserys_ambush_shuts_its_doors_until_won_and_brings_coins_and_a_potion(t: TestContext) -> void:
	if not await _enter(t, ROOM % "b4-nursery"):
		return
	var fight := _object(t, "b4-nursery-fight")
	var shutters := [_object(t, "b4-shutter-north"), _object(t, "b4-shutter-east")]
	var chest := _object(t, "b4-nursery-chest")
	if not t.check(fight != null and chest != null and shutters[0] != null and shutters[1] != null, "the Nursery's ambush is missing a piece"):
		return
	t.check(bool(fight.get(&"once")), "the Nursery's ambush runs again")
	t.check(fight.get_node_or_null(fight.get(&"reward") as NodePath) == chest, "the ambush's reward is not its chest")
	var script := chest.get_node(^"ChestScript")
	t.check(not bool(script.call(&"is_shown")), "the Nursery's chest is there before the ambush")
	# The optional wing: its chest holds coins and a potion, no key.
	var contents: Dictionary = chest.get(&"contents")
	t.check(not contents.has("dungeon-small-key") and int(contents.get("coins", 0)) > 0 and contents.has("hp-potion"),
			"the Nursery's chest holds %s" % contents)
	_stand(t, Vector2(9.0, 9.0) * CELL)
	t.check(await t.until(func() -> bool: return bool(fight.call(&"is_active")), 1500.0), "the ambush did not start")
	t.check(bool(shutters[0].call(&"is_shut")) and bool(shutters[1].call(&"is_shut")), "the Nursery's shutters did not shut")
	t.check(await _win(t, fight), "the ambush was not won with its enemies beaten")
	t.check(not bool(shutters[0].call(&"is_shut")) and not bool(shutters[1].call(&"is_shut")), "the Nursery's shutters stayed shut")
	t.check(await t.until(func() -> bool: return bool(script.call(&"is_shown")), 1500.0), "the Nursery's chest did not rise")


func test_the_pantrys_mimic_spits_out_small_key_2(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, ROOM % "b3-mimics-pantry"):
		return
	var placed := t.world().world_root.get_node_or_null(^"Enemies/b3-cocoon-mimic")
	if not t.check(placed != null, "the Pantry has no Cocoon Mimic"):
		return
	_stand(t, Vector2(9.0, 12.8) * CELL)
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
			if is_instance_valid(node) and node is Node2D and node.is_inside_tree():
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


## B5: the Brood Warden's fight (a boss fight, its reward the Hoard's shutter) shuts the den; won, the
## shutter sinks and the Warden is recorded beaten; in the Hoard Pearl 2 rises on the brood's altar, and
## its take grants the Silk skin and seals the Hollow until the Matron falls.
func test_the_wardens_fight_guards_pearl_two_and_its_take_seals_the_hollow(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, ROOM % "b5-wardens-den"):
		return
	_calm(t)
	var fight := _object(t, "b5-warden-fight")
	var den_shutter := _object(t, "b5-den-shutter")
	var hoard_shutter := _object(t, "b5-hoard-shutter")
	if not t.check(fight != null and den_shutter != null and hoard_shutter != null, "the Warden's Den is missing a piece"):
		return
	t.equal(str(fight.get(&"boss_id")), WARDEN, "the den's fight is not the Warden's")
	t.check(fight.get_node_or_null(fight.get(&"reward") as NodePath) == hoard_shutter, "the Warden's fight does not open the Hoard's shutter")
	t.check(bool(hoard_shutter.call(&"is_shut")), "the Hoard's shutter starts open")
	_stand(t, Vector2(8.0, 12.0) * CELL)
	t.check(await t.until(func() -> bool: return bool(fight.call(&"is_active")), 1500.0), "the Warden's fight did not start")
	t.check(bool(den_shutter.call(&"is_shut")), "the den's shutter did not shut")
	# Won (the room's enemies beaten: the walk's way; the ram's lesson is its film's).
	t.check(await _win(t, fight), "the Warden's fight was not won with its enemies beaten")
	t.check(DungeonState.is_boss_beaten(run, DUNGEON_ID, WARDEN), "the Warden is not recorded beaten")
	t.check(await t.until(func() -> bool: return not bool(hoard_shutter.call(&"is_shut")), 1500.0), "the Hoard's shutter did not sink")
	t.check(not bool(den_shutter.call(&"is_shut")), "the den's shutter stayed shut")
	if not t.check(await _push_through(t, "b5-north", ROOM % "hoard"), "B5's north doorway did not lead into the Hoard"):
		return
	var pearl := _object(t, "hoard-pearl-two")
	if not t.check(pearl != null, "the Hoard has no Pearl 2"):
		return
	t.equal([int(pearl.get(&"number")), str(pearl.get(&"skin_id")), str(pearl.get(&"boss_id"))], [2, "silk", WARDEN], "Pearl 2's number, skin and guard")
	t.check(await t.until(func() -> bool: return bool(pearl.call(&"is_shown")), 1000.0), "Pearl 2 does not show once the Warden fell")
	t.check(_shown(t, "hoard-pearl-glint-0"), "no glow over the altar")
	t.check(not t.player().crosses_webs(), "the slime crossed webs before Pearl 2")
	t.teleport_player(pearl.global_position + Vector2(60, 50))
	t.check(await t.until(func() -> bool: return bool(pearl.call(&"is_taken")), 2000.0), "walking into Pearl 2 did not take it")
	t.check(SkinState.is_won(SkinState.SILK), "Pearl 2 did not grant the Silk skin")
	t.check(t.player().crosses_webs(), "the slime does not cross webs after Pearl 2")
	t.check(DungeonState.is_sealed(run, DUNGEON_ID), "the take did not seal the Hollow")
	t.equal(DungeonState.sealed_by(run, DUNGEON_ID), MATRON, "the seal's boss")
	t.check(await t.until(func() -> bool: return not _shown(t, "hoard-pearl-glint-0"), 1500.0), "the Pearl's glow stayed after the take")
	await t.until(func() -> bool: return not t.tree.paused, 6000.0)


## A save from the retired Boughs whose Warden fell there (the Hollow's record, `defeated_boss_ids`), never
## in B5's fight: built, B5 gives the fight's reward (room_fight.gd `_reward_if_beaten_elsewhere`): the
## Hoard's shutter sinks for good, the fight is recorded won, the Warden never stands; Pearl 2 waits.
func test_the_hoards_shutter_opens_when_the_warden_fell_elsewhere(t: TestContext) -> void:
	var run := Services.run()
	DungeonState.mark_boss_beaten(run, DUNGEON_ID, WARDEN)
	if not await _enter(t, ROOM % "b5-wardens-den"):
		return
	var fight := _object(t, "b5-warden-fight")
	var shutter := _object(t, "b5-hoard-shutter")
	if not t.check(fight != null and shutter != null, "the Warden's Den has no fight or no Hoard shutter"):
		return
	t.check(await t.until(func() -> bool: return not bool(shutter.call(&"is_shut")), 2000.0), "the Hoard's shutter stayed shut for a Warden beaten elsewhere")
	t.check(bool(fight.call(&"is_done")), "B5's fight is not recorded won")
	t.check(DungeonState.is_done(t.tree, DungeonState.object_key(fight, "fight:" + str(fight.get(&"fight_id")))), "B5's fight's record")
	_stand(t, Vector2(8.0, 12.0) * CELL)
	await t.sim_wait(800.0)
	t.check(not bool(fight.call(&"is_active")), "the won fight ran again")
	t.check(_enemies_of_type(t, "brood-warden").is_empty(), "the Warden stands again")
	if await _enter(t, ROOM % "hoard"):
		var pearl := _object(t, "hoard-pearl-two")
		t.check(pearl != null and bool(pearl.call(&"is_shown")), "Pearl 2 is not on the altar")
	if await _enter(t, ROOM % "b5-wardens-den"):
		await t.steps(4)
		t.check(not bool(_object(t, "b5-hoard-shutter").call(&"is_shut")), "the Hoard's shutter shut again when B5 was built again")


## The Hoard's loft (the Silk skin's first lock): its stair's foot is choked by a web wall that holds
## the plain slime; the Silk slime wades it, climbs to the loft and goes west into the Spinning Loft.
func test_the_hoards_stair_is_choked_by_a_web_wall_the_silk_slime_passes(t: TestContext) -> void:
	if not await _enter(t, ROOM % "hoard"):
		return
	var web := _object(t, "hoard-stair-web") as WebWallScript
	if not t.check(web != null, "the Hoard's stair has no web wall"):
		return
	_stand(t, HOARD_STAIR * CELL)
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(1200.0)
	t.release(&"move_up")
	t.check(_level(t) == 0 and t.player_body().global_position.y > web.global_position.y, "the slime passed the stair's web wall without the Silk skin")
	SkinState.lend(SkinState.SILK)
	_stand(t, HOARD_STAIR * CELL)
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(2600.0)
	t.release(&"move_up")
	await t.steps(10)
	t.check(_level(t) == 1 and t.player_body().global_position.y < 10.0 * CELL,
			"the Silk slime did not wade the web wall up to the loft (level %d, feet %s)" % [_level(t), t.player_body().global_position])
	t.check(await _push_through(t, "hoard-west-loft", ROOM % "b6-spinning-loft"), "the loft's west doorway did not lead into the Spinning Loft")


## B6, the Spinning Loft: two rows of web walls part it wall to wall; two Slime Spiders; the plain
## slime cannot cross a row, the Silk slime wades it; the Spear cuts a lane for good; small key 3 lies
## in its silk parcel beyond the rows: freed, it drops as a floor key, taken once.
func test_the_spinning_loft_is_parted_by_rows_of_web_walls_and_frees_small_key_3(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, ROOM % "b6-spinning-loft"):
		return
	_hold_enemies(t)
	var rows := {}
	for node: Node in t.world().world_root.find_children("b6-web-*", "", true, false):
		var wall := node as WebWallScript
		if wall == null:
			continue
		var y := snappedf(wall.global_position.y, 1.0)
		var reach: Vector2 = rows.get(y, Vector2(INF, -INF))
		var solid := wall.solid_rect()
		rows[y] = Vector2(minf(reach.x, wall.global_position.x + solid.position.x), maxf(reach.y, wall.global_position.x + solid.end.x))
	t.equal(rows.size(), 2, "the Spinning Loft's rows of web walls")
	for y: float in rows:
		var reach: Vector2 = rows[y]
		t.check(reach.x <= RIM_CELLS * CELL + 1.0 and reach.y >= (ROOM_COLUMNS - RIM_CELLS) * CELL - 1.0,
				"the row at y %.0f does not reach wall to wall (%s)" % [y, reach])
	t.equal(_enemies_of_type(t, "slime-spider").size(), 2, "Slime Spiders in the Spinning Loft")
	# The plain slime cannot cross the north row; the Silk slime wades it at half speed.
	var north_row: float = rows.keys().min() if not rows.is_empty() else 0.0
	_stand(t, B6_BETWEEN_ROWS * CELL)
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(1600.0)
	t.release(&"move_up")
	t.check(t.player_body().global_position.y > north_row, "the plain slime crossed the north row")
	SkinState.lend(SkinState.SILK)
	_stand(t, B6_BETWEEN_ROWS * CELL)
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(1800.0)
	t.release(&"move_up")
	t.check(t.player_body().global_position.y < north_row - 20.0, "the Silk slime did not wade the north row")
	# The Spear cuts a lane for good.
	var lane := _object(t, "b6-web-0-3") as WebWallScript
	if t.check(lane != null, "no web wall b6-web-0-3"):
		_cut(t, lane.get_node_or_null(^"DamageArea") as Area2D)
		await t.steps(2)
		t.check(lane.is_cut() and run.has_flag(lane.save_key()), "a Spear hit did not cut a lane")
	var parcel := _object(t, "b6-key-parcel") as SilkParcelScript
	if not t.check(parcel != null, "the Spinning Loft has no silk parcel"):
		return
	t.check(parcel.global_position.y < north_row, "the parcel is not beyond the rows")
	var keys := DungeonState.small_keys(run, DUNGEON_ID)
	_cut(t, parcel.get_node_or_null(^"DamageArea") as Area2D)
	await t.steps(4)
	t.check(parcel.is_open(), "a Spear hit did not free the parcel")
	var dropped := _floor_keys(t)
	if not t.check(dropped.size() == 1, "the freed parcel dropped %d floor keys" % dropped.size()):
		return
	t.teleport_player(dropped[0].global_position - Vector2(0, 20))
	t.check(await t.until(func() -> bool: return DungeonState.small_keys(run, DUNGEON_ID) == keys + 1, 3000.0),
			"walking over the parcel's key did not give small key 3")
	if await _enter(t, ROOM % "hoard") and await _enter(t, ROOM % "b6-spinning-loft"):
		await t.steps(10)
		t.equal(_floor_keys(t).size(), 0, "the parcel's key came back once taken")


# --- the Crown ---------------------------------------------------------------------------------------

## C1, behind the Crown Door: floor webs wall to wall on its floor, the flight up choked by a web wall
## (the plain slime is held, the Silk slime wades up to the top), the key 3 door into C2.
func test_the_crown_stairs_web_wall_and_its_k3_door(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, ROOM % "c1-crown-stair"):
		return
	var web := _object(t, "c1-stair-web") as Node2D
	var door := _object(t, "c1-k3-door")
	if not t.check(web != null and door != null, "C1 has no web wall or no key 3 door"):
		return
	t.equal([str(door.get(&"lock")), int(door.get(&"keyholes"))], ["small", 1], "the key 3 door's lock and keyholes")
	var layer := t.world().world_root.get_node_or_null(^"webs") as WebLayerType
	if t.check(layer != null, "C1 has no webs layer"):
		for cell: Vector2 in [Vector2(2, 10), Vector2(15, 10), Vector2(8, 11), Vector2(2, 13), Vector2(15, 13)]:
			t.check(layer.has_web_at((cell + Vector2(0.5, 0.5)) * CELL), "no floor web in C1's cell %s" % cell)
		t.check(not layer.has_web_at(Vector2(8.5, 4.5) * CELL), "a floor web on C1's top")
	_stand(t, C1_FLIGHT_FOOT * CELL)
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(2600.0)
	t.release(&"move_up")
	t.check(_level(t) == 0 and t.player_body().global_position.y > web.global_position.y, "the plain slime passed C1's web wall")
	SkinState.lend(SkinState.SILK)
	_stand(t, C1_FLIGHT_FOOT * CELL)
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(3200.0)
	t.release(&"move_up")
	await t.steps(10)
	t.check(_level(t) == 1 and t.player_body().global_position.y < 7.6 * CELL,
			"the Silk slime did not climb the flight to C1's top (level %d, feet %s)" % [_level(t), t.player_body().global_position])
	# The key 3 door wants key 3, which opens it into C2.
	_stand(t, C1_K3_DOOR * CELL)
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(900.0)
	t.release(&"move_up")
	t.check(t.in_world(ROOM % "c1-crown-stair") and t.player_body().global_position.y > 2.0 * CELL, "the key 3 door let the slime through without key 3")
	DungeonState.add_small_key(run, DUNGEON_ID, 1)
	_stand(t, C1_K3_DOOR * CELL)
	await t.steps(2)
	t.press(&"move_up")
	var crowned := await t.until(func() -> bool: return t.in_world(ROOM % "c2-crown"), PUSH_MS)
	t.release(&"move_up")
	t.check(crowned, "key 3 did not open the key 3 door into C2 (in %s)" % t.world().map_id())
	t.equal(DungeonState.small_keys(run, DUNGEON_ID), 0, "small keys after the key 3 door")


## C2: her camp's `boss_engaged` shuts the boss shutter behind the slime as she wakes, and her fall
## (`boss_defeated`; ended here as the walk's film ends it) opens it; her full heart lies in the arena.
func test_the_matrons_camp_shuts_the_crowns_shutter_and_her_fall_opens_it(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, ROOM % "c2-crown"):
		return
	var encounter := _object(t, "matron-camp")
	var camp := encounter.get_node_or_null(^"BossCampScript") as BossCampType if encounter != null else null
	var shutter := _object(t, "c2-crown-shutter")
	if not t.check(camp != null and shutter != null, "the Crown has no Matron camp or no shutter"):
		return
	t.equal([camp.camp_id, camp.boss_id, camp.map_id], ["weaver-hollow-matron", MATRON, ROOM % "c2-crown"], "her camp's ids")
	t.check(camp.is_connected(&"boss_engaged", Callable(shutter, &"shut")), "her waking does not shut the shutter")
	t.check(camp.is_connected(&"boss_defeated", Callable(shutter, &"open")), "her fall does not open the shutter")
	t.check(not bool(shutter.call(&"is_shut")), "the Crown's shutter starts shut")
	t.check(encounter.get_node_or_null(^"Pearl") == null, "her camp holds a Pearl (Pearl 2 lies in the Hoard)")
	# The slime walks in: she wakes, the shutter shuts behind it and holds the way back.
	_stand(t, Vector2(10.1, 11.25) * CELL)
	t.check(await t.until(func() -> bool: return camp.has_live_boss(), 1000.0), "she did not wake as the slime walked in")
	t.check(await t.until(func() -> bool: return bool(shutter.call(&"is_shut")), 1000.0), "the shutter did not shut behind the slime")
	var matron := camp.get_live_boss()
	if not t.check(matron != null, "no Matron"):
		return
	_stand(t, Vector2(10.0, 16.8) * CELL)
	await t.steps(2)
	t.press(&"move_down")
	await t.sim_wait(800.0)
	t.release(&"move_down")
	t.check(t.in_world(ROOM % "c2-crown"), "the shut shutter let the slime out while she stands")
	matron.set(&"_hp", 0.0)
	matron.call(&"_defeat")
	t.check(await t.until(func() -> bool: return not bool(shutter.call(&"is_shut")), 3000.0), "her fall did not open the shutter")
	t.check(MATRON in (run.world.get("defeated_boss_ids", []) as Array), "her fall is not in defeated_boss_ids")
	t.check(DungeonState.is_boss_beaten(run, DUNGEON_ID, MATRON), "the Hollow's record does not have her beaten")
	var heart := encounter.get_node_or_null(^"FullHeart/FullHeartScript")
	if t.check(heart != null, "her camp has no full heart"):
		t.check(await t.until(func() -> bool: return bool(heart.call(&"is_shown")), 1500.0), "her full heart is not in the arena")


## The seals: one in T1's way out (south), one in C2's east doorway, and nowhere else. Sealed (the
## take), T1's shuts and holds, every way out of the Hollow refuses (C3's hole too) and the ways
## between its rooms do not; C2's is built shut; her fall breaks both.
func test_the_seals_stand_in_the_hollows_two_doorways_out(t: TestContext) -> void:
	var run := Services.run()
	var found: Array = []
	for room_name: String in ROOM_NAMES:
		var root := (load(SCENE % room_name) as PackedScene).instantiate()
		for seal: Node in _with_script(root, DungeonSeal):
			found.append([room_name, str(seal.get(&"wall"))])
		root.free()
	t.equal(found, [["t1-root-door", "south"], ["c2-crown", "east"]], "the Hollow's seals (room, wall)")
	if not await _enter(t, T1):
		return
	var seal := _object(t, "t1-entrance-seal")
	if not t.check(seal != null and not bool(seal.call(&"is_shut")), "T1's seal is missing or shut before the take"):
		return
	t.check(bool(DungeonState.current(t.tree).call(&"seal_now", "test", false)), "the Hollow did not seal")
	t.check(bool(seal.call(&"is_shut")), "T1's seal did not shut")
	t.check(str(DungeonState.exit_refusal(t.tree, FORECOURT)).begins_with("Sealed."), "the way out to the forecourt is open while sealed")
	t.equal(DungeonState.exit_refusal(t.tree, ROOM % "c3-outer-bough"), "", "a way between the Hollow's rooms is refused while sealed")
	_stand(t, T1_WAY_OUT * CELL)
	await t.steps(2)
	t.press(&"move_down")
	await t.sim_wait(1400.0)
	t.release(&"move_down")
	await t.steps(2)
	t.check(t.in_world(T1) and not bool(t.main.call(&"is_transitioning")), "the slime walked out past T1's seal")
	if not await _enter(t, ROOM % "c3-outer-bough"):
		return
	t.check(str(DungeonState.exit_refusal(t.tree, FORECOURT)).begins_with("Sealed."), "C3's hole is open while sealed")
	if not await _enter(t, ROOM % "c2-crown"):
		return
	var east := _object(t, "c2-east-seal")
	if not t.check(east != null and bool(east.call(&"is_shut")), "C2's east seal is missing or not shut while sealed"):
		return
	DungeonState.mark_boss_beaten(run, DUNGEON_ID, MATRON)
	t.check(await t.until(func() -> bool: return not bool(east.call(&"is_shut")), 3000.0), "her fall did not break C2's east seal")
	t.check(not DungeonState.is_sealed(run, DUNGEON_ID), "the Hollow is still sealed after her fall")
	if await _enter(t, T1):
		t.check(not bool(_object(t, "t1-entrance-seal").call(&"is_shut")), "T1's seal stands after her fall")
		t.equal(DungeonState.exit_refusal(t.tree, FORECOURT), "", "the way out after her fall")


## C3, the Outer Bough: her web wall across the walk holds the plain slime and lets the Silk slime
## wade it; its hole (refused while the Hollow is sealed) drops the slime to the forecourt, by S1's nook.
func test_c3s_hole_drops_the_slime_to_the_forecourt(t: TestContext) -> void:
	var run := Services.run()
	if not await _enter(t, ROOM % "c3-outer-bough"):
		return
	var wall := _object(t, "c3-web-wall") as Node2D
	if not t.check(wall != null, "C3 has no web wall"):
		return
	_stand(t, C3_WALK * CELL)
	await t.steps(2)
	t.press(&"move_right")
	await t.sim_wait(1500.0)
	t.release(&"move_right")
	t.check(t.player_body().global_position.x < wall.global_position.x, "the plain slime passed her web wall")
	DungeonState.seal(run, DUNGEON_ID, MATRON, "test")
	t.check(str(DungeonState.exit_refusal(t.tree, FORECOURT)).begins_with("Sealed."), "C3's hole is open while sealed")
	DungeonState.unseal(run, DUNGEON_ID)
	t.equal(DungeonState.exit_refusal(t.tree, FORECOURT), "", "C3's hole is refused once the seal is gone")
	SkinState.lend(SkinState.SILK)
	_stand(t, C3_WALK * CELL)
	await t.steps(2)
	t.press(&"move_right")
	await t.sim_wait(2000.0)
	t.release(&"move_right")
	t.check(t.player_body().global_position.x > wall.global_position.x + CELL, "the Silk slime did not wade her web wall")
	_stand(t, C3_DROP * CELL)
	await t.steps(2)
	t.press(&"move_right")
	var fell := await t.until(func() -> bool: return t.in_world(FORECOURT), PUSH_MS)
	t.release(&"move_right")
	if not t.check(fell, "C3's hole did not drop the slime to the forecourt (in %s)" % t.world().map_id()):
		return
	await _settled(t)
	var landing := t.world().world_root.get_node_or_null(SILK_DROP) as Node2D
	if t.check(landing != null, "the forecourt has no landing for C3's drop"):
		t.equal(str(landing.get(&"door_id")), SILK_DROP_DOOR, "the forecourt's landing's door id")
		t.check(t.player_body().global_position.distance_to(landing.global_position) < 2.0 * CELL,
				"the slime did not land by S1's nook (%.0f px from the landing)" % t.player_body().global_position.distance_to(landing.global_position))


# --- old saves -----------------------------------------------------------------------------------------

## The prizes keep the old floors' records (D1's page, D2's chest, B4's chest, S2's three parcels), so a save
## that took them in the four-floor Hollow finds them spent in the rebuilt rooms.
func test_the_rebuilt_prizes_keep_the_old_floors_records_so_none_is_had_twice(t: TestContext) -> void:
	var run := Services.run()
	for prize: Array in PRIZE_CHESTS:
		var scene := (load(SCENE % str(prize[0])) as PackedScene).instantiate()
		var chest := scene.get_node_or_null(NodePath(str(prize[1])))
		if t.check(chest != null and chest.get_script() == ChestRoot, "%s has no chest %s" % [prize[0], prize[1]]):
			t.equal([str(chest.get(&"chest_id")), str(chest.get(&"map_id"))], [prize[2], prize[3]], "%s's chest's record" % prize[0])
		scene.free()
	for parcel: Array in PRIZE_PARCELS:
		var scene := (load(SCENE % str(parcel[0])) as PackedScene).instantiate()
		var node := scene.get_node_or_null(NodePath(str(parcel[1])))
		if t.check(node != null and node.get_script() == SilkParcelScript, "%s has no parcel %s" % [parcel[0], parcel[1]]):
			t.equal(str(node.get(&"flag_id")), str(parcel[2]), "%s's flag" % parcel[1])
		scene.free()
	# Taken in the four-floor Hollow.
	for prize: Array in PRIZE_CHESTS:
		run.set_chest_remaining(str(prize[3]), str(prize[2]), {})
	for parcel: Array in PRIZE_PARCELS:
		run.set_flag(str(parcel[2]))
	for prize: Array in PRIZE_CHESTS:
		# D2's chest stands only once its candles are lit: its record is checked above.
		if str(prize[0]) == "d2-dark-bough" or not await _enter(t, ROOM % str(prize[0])):
			continue
		_calm(t)
		var script := t.world().world_root.get_node_or_null(NodePath(str(prize[1]) + "/ChestScript"))
		if t.check(script != null, "no chest %s in %s" % [prize[1], prize[0]]):
			t.equal([str(script.get(&"map_id")), str(script.get(&"instance_id"))], [prize[3], prize[2]], "%s's chest's record in the game" % prize[0])
			t.check(bool(script.call(&"is_empty")), "%s's chest is full again after the old one was opened" % prize[0])
	if await _enter(t, ROOM % "b3-mimics-pantry"):
		for parcel: Array in PRIZE_PARCELS:
			var node := t.world().world_root.get_node_or_null(NodePath(str(parcel[1])))
			t.check(node != null and bool(node.call(&"is_open")), "%s is wrapped again after the old one was freed" % parcel[1])


## A save standing in one of the retired floors (retired: RunState `RETIRED_WORLDS`, `moved_world`) wakes
## in T1 at its entrance (no spot kept), its record the same dungeon's (keys, items, the Warden, the
## seal) but its entrance naming a retired floor forgotten; T1 records it again and stands sealed.
func test_an_old_save_in_the_retired_boughs_wakes_in_t1_with_its_record(t: TestContext) -> void:
	var run := Services.run()
	for old: String in OLD_FLOORS:
		t.equal(RunStateScript.moved_world(old), T1, "the world a save in %s loads into" % old)
	t.equal(RunStateScript.moved_world(ROOM % "hoard"), ROOM % "hoard", "a rebuilt room moved")
	t.equal(RunStateScript.moved_world(FORECOURT), FORECOURT, "the forecourt moved")
	var data := run.serialize()
	data["location"] = {"area_id": OLD_FLOORS[2], "map_id": OLD_FLOORS[2], "x": 1200.0, "y": 900.0, "facing": "down"}
	var world: Dictionary = data["world"]
	var dungeons: Dictionary = world.get_or_add(DungeonState.RECORD_KEY, {})
	dungeons[DUNGEON_ID] = {"small_keys": 1, "keys_found": 2, "items": [DungeonState.MAP, DungeonState.BIG_KEY], "keyholes": {},
		"done": [], "bosses": [WARDEN], "visited": [], "entrance": {"map_id": OLD_FLOORS[0], "x": 1536.0, "y": 2400.0},
		"seal": {"boss_id": MATRON, "by": MATRON}}
	(world.get_or_add("defeated_boss_ids", []) as Array).append(WARDEN)
	if not t.check(run.install(data), "the old save did not install"):
		return
	t.equal([str(run.location.get("map_id", "")), str(run.location.get("area_id", ""))], [T1, T1], "the old save's world")
	t.check(not run.location.has("x"), "the old floor's spot was kept: %s" % run.location)
	t.check(DungeonState.entrance(run, DUNGEON_ID).is_empty(), "the entrance naming the retired Trunk was kept")
	t.equal(DungeonState.small_keys(run, DUNGEON_ID), 1, "small keys held after the move")
	t.check(DungeonState.has_item(run, DUNGEON_ID, DungeonState.MAP) and DungeonState.has_item(run, DUNGEON_ID, DungeonState.BIG_KEY),
			"the map or the big key lost in the move")
	t.check(DungeonState.is_boss_beaten(run, DUNGEON_ID, WARDEN), "the Warden's fall lost in the move")
	t.equal(DungeonState.sealed_by(run, DUNGEON_ID), MATRON, "the seal after the move")
	if not await _enter(t, T1):
		return
	t.equal(str(DungeonState.entrance(run, DUNGEON_ID).get("map_id", "")), T1, "T1 did not record the entrance again")
	var seal := _object(t, "t1-entrance-seal")
	t.check(seal != null and bool(seal.call(&"is_shut")), "T1's seal is open in a sealed old save")


# --- helpers -----------------------------------------------------------------------------------------

## Travels to `world_id` unless the slime is there already. False (a failed check) when it did not
## arrive.
func _enter(t: TestContext, world_id: String) -> bool:
	await _settled(t)
	if not t.in_world(world_id):
		t.main.call(&"travel_to", world_id)
	var arrived := await t.until(func() -> bool: return t.in_world(world_id) and t.player_body() != null \
			and not bool(t.main.call(&"is_transitioning")), 8000.0)
	await t.steps(8)
	return t.check(arrived, "could not travel to %s" % world_id)


func _settled(t: TestContext) -> void:
	await t.until(func() -> bool: return not bool(t.main.call(&"is_transitioning")), 6000.0)
	await t.steps(2)


## Stands at room door `door_id`'s arrival spot and pushes out through it; true when the slime came
## out in `target_world` within `ms`.
func _push_through(t: TestContext, door_id: String, target_world: String, ms: float = PUSH_MS) -> bool:
	var door := t.world().world_root.get_node_or_null(NodePath("RoomDoors/" + door_id)) as Node2D
	if not t.check(door != null, "no room door %s in %s" % [door_id, t.world().map_id()]):
		return false
	var inward: Vector2 = door.call(&"inward")
	_stand(t, door.global_position + inward * float(door.get(&"arrival_inset")))
	await t.steps(4)
	var action := _action(-inward)
	t.press(action)
	var through := await t.until(func() -> bool: return t.in_world(target_world), ms)
	t.release(action)
	await _settled(t)
	return through


static func _action(direction: Vector2) -> StringName:
	if direction.y < -0.5:
		return &"move_up"
	if direction.y > 0.5:
		return &"move_down"
	return &"move_left" if direction.x < 0.0 else &"move_right"


## Puts the slime's feet at `feet` and takes its level there (as a walk onto that ground would: a
## teleport alone keeps the level it had).
func _stand(t: TestContext, feet: Vector2) -> void:
	var player := t.player()
	var body := t.player_body()
	var offset := body.global_position - player.get_centre()
	player.teleport(feet - offset)
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	if t.world().elevation != null:
		t.world().elevation.track(body)


## The slime's height level (0 in a world without levels).
func _level(t: TestContext) -> int:
	var elevation := t.world().elevation
	return elevation.level_of(t.player_body()) if elevation != null else 0


func _object(t: TestContext, path: String) -> Node2D:
	var root: Node = t.world().world_root if t.world() != null else null
	return root.get_node_or_null(NodePath("Objects/" + path)) as Node2D if root != null else null


## True when the node named `node_name` stands in the world, drawn.
func _shown(t: TestContext, node_name: String) -> bool:
	var node := t.world().world_root.find_child(node_name, true, false) as CanvasItem
	return node != null and not node.is_queued_for_deletion() and node.is_visible_in_tree()


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
	var holder := scene.get_node_or_null(^"RoomDoors")
	if holder != null:
		for child: Node in holder.get_children():
			if child.scene_file_path == ROOM_DOOR_SCENE:
				out.append(child)
	return out


## The nodes under `root` whose script is `script`.
static func _with_script(root: Node, script: Script) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in root.find_children("*", "", true, false):
		if node.get_script() == script:
			out.append(node)
	return out


## Adds a chest's or a parcel's dungeon items to `counts`.
static func _count_contents(counts: Dictionary, contents: Variant) -> void:
	if not contents is Dictionary:
		return
	var held: Dictionary = contents
	counts["small"] += int(held.get("dungeon-small-key", 0))
	counts["big"] += int(held.get("dungeon-big-key", 0))
	counts["map"] += int(held.get("dungeon-map", 0))
	counts["compass"] += int(held.get("dungeon-compass", 0))


## The kit's floor keys lying in the world.
func _floor_keys(t: TestContext) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for node: Node in t.world().world_root.find_children("*", "", true, false):
		if node is DungeonKeyPickup and not node.is_queued_for_deletion():
			out.append(node as Node2D)
	return out


## The living enemies of `enemy_type` in the world.
func _enemies_of_type(t: TestContext, enemy_type: String) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in t.tree.get_nodes_in_group(&"enemy"):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and str(node.get(&"enemy_type")) == enemy_type \
				and not bool(node.call(&"is_defeated")):
			out.append(node)
	return out


## The world's enemies calmed (no chase, no attack: the tests check the rooms, not the fights) and the
## slime's health full.
func _calm(t: TestContext) -> void:
	for node: Node in t.tree.get_nodes_in_group(&"enemy"):
		if is_instance_valid(node):
			node.set(&"targeting_radius", 0.0)
			node.set(&"attack_range", 0.0)
	t.player().heal(t.player().get_max_hp())


## Every placed enemy's enemy stops (its processing off): no spit, no chase, no grab.
func _hold_enemies(t: TestContext) -> void:
	for node: Node in t.tree.get_nodes_in_group(&"placed_enemy"):
		var enemy: Node = node.call(&"get_enemy") if is_instance_valid(node) else null
		if enemy != null:
			enemy.process_mode = Node.PROCESS_MODE_DISABLED


## A room fight won: every living enemy in its room beaten (those that hatch meanwhile too) until it
## ends. True when it was won.
func _win(t: TestContext, fight: Node) -> bool:
	return await t.until(func() -> bool:
		for enemy: Variant in fight.call(&"members"):
			if is_instance_valid(enemy):
				(enemy as Node).call(&"take_reaction_damage", 99999.0)
		t.player().heal(t.player().get_max_hp())
		return not bool(fight.call(&"is_active")), 6000.0)


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


## A Spear's cut on the receiver of `area` (silk: its rule's damage is 0, so the hit's knockback is
## what commits it; tests/test_weaver_webs.gd `_hit`).
func _cut(t: TestContext, area: Area2D) -> void:
	if area == null:
		t.fail("no hurtbox to cut")
		return
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	router.route({"activation_id": activation, "source": source, "attack_area": attack, "target_area": area,
		"weapon_id": "test-spear", "weapon_tags": ["weapon", "spear"], "damage_types": ["physical"], "base_damage": 10.0,
		"effects": [{"effect_id": "knockback", "potency": 100.0}], "impact": {"position": area.global_position, "knock": Vector2.UP}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()
