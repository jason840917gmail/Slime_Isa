extends RefCounted
## Separately authored dungeon rooms: Fatty's Lair's rooms are each a world (since 2026-10-18; their
## doors and records: test_lair_rooms.gd), their links kept by world and record; the room-edge mask;
## every room world of the rebuilt Weaver Hollow and Crystal Mine inside its dungeon.
const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const MAP_ID := "fatty-lair"
const HUB := "fatty-lair-r3-pit-hall"


func test_the_lairs_rooms_are_worlds_that_keep_their_links(t: TestContext) -> void:
	t.check(not t.world().world_root.has_node("RoomScenes"), "R1 is still a room of a shell")
	if not await _travel(t, HUB):
		return
	var world := t.world().world_root
	var stair := world.get_node("Lair/inner-stair")
	t.equal([str(stair.get(&"target_world")), str(stair.get(&"target_door"))], ["fatty-lair-r8-guard-crypt", "fatty-lair-crypt-north-stair"],
		"the Inner Stair's way down to the crypt's world")
	var director := world.get_node_or_null("Lair/LairDirector")
	if t.check(director != null, "the hub has no Lair director (Burr's)"):
		t.check(director.get_node_or_null(director.get(&"cell_door")) != null, "Burr's door path was lost")
		t.check(director.get_node_or_null(director.get(&"burr")) != null, "Burr is not in the hub's world")
		t.check(not director.is_in_group(&"dungeon_map_mark"), "the hub's director marks the boss on the map")
	if not await _travel(t, "slimeshire-glow-moss-burrow"):
		return
	var void_hazard := t.world().world_root.get_node("Hazards/void")
	t.check(void_hazard.get_node_or_null(void_hazard.get(&"fixed_return")) != null, "the Burrow's void lost its way back to the mouth")
	var moss := t.world().world_root.get_node_or_null("shadow-path/ShadowPath")
	t.check(moss != null and not (moss.get(&"cells") as Array).is_empty(), "the Burrow's painted moss built no shadow path")


## Burr's cell (its own world) is rock in the hub's world behind the hub's own bevel faces, its
## two-key door cut into the face (owner, 2026-10-19): Burr waits in the door's passage, behind its
## shut leaf, where no floor leads; the rock beyond the faces is outside the hall's L outline (masked).
func test_l_shaped_hall_keeps_burr_behind_the_closed_cell_door(t: TestContext) -> void:
	Services.run().set_flag("fatty-lair.burr-called")
	if not await _travel(t, HUB):
		return
	var world := t.world()
	var hub := world.world_root.get_node("CameraRooms/r3-pit-hall")
	var burr := world.world_root.get_node("Lair/burr") as Node2D
	var door := world.world_root.get_node("Objects/hub-burr-cell-door") as Node2D
	var walls := world.world_root.get_node("interior-walls")
	t.check(not bool(door.call(&"is_open")), "Burr's cell door starts open")
	# behind the leaf: in the door's opening, north of its floor line, on no floor of the hall
	t.check(absf(burr.global_position.x - door.global_position.x) < 32.0 and burr.global_position.y < door.global_position.y,
		"Burr does not wait behind his cell door (at %s, the door at %s)" % [burr.global_position, door.global_position])
	for cell: Vector2i in [Vector2i(3, 4), Vector2i(2, 2), Vector2i(4, 6)]:
		t.check(not bool(walls.call(&"is_floor", cell)), "the hub's world has floor in Burr's cell at %s" % cell)
	t.check(bool(walls.call(&"is_floor", Vector2i(7, 3))) and bool(walls.call(&"is_floor", Vector2i(3, 9))), "the hall lost its floor beside the cell")
	t.teleport_player((hub.get_node("RoomEntry") as Node2D).global_position)
	world.camera.start_follow(t.player_body(), true)
	await t.steps(5)
	var mask := world.world_root.get_node("Dungeon/RoomMask")
	var material := mask.get(&"_material") as ShaderMaterial
	t.equal(int(material.get_shader_parameter(&"point_count")), 6, "L-shaped mask vertices")
	t.check(not bool(hub.call(&"contains", Vector2(160.0, 224.0))), "the hall outline includes the rock of Burr's cell")


func test_door_frames_use_wall_stone_and_keep_the_two_cell_collision(t: TestContext) -> void:
	# Fatty's Lair draws its doorways with interior walls (docs/godot/INTERIOR_WALLS.md): a door in
	# a room's rim draws only its leaf, no frame of its own
	if not await _travel(t, HUB):
		return
	var door := t.world().world_root.get_node("Objects/hub-r1-shortcut")
	t.check(bool(door.get(&"frame_drawn_by_wall")), "the bolted door still draws its own frame")
	t.check(door.get_node_or_null("WallDoorway") == null, "the bolted door got an old doorway frame")
	var shape := door.get_node("Body/Shape") as CollisionShape2D
	t.equal((shape.shape as RectangleShape2D).size.x, 128.0, "two-cell door collision")
	t.check(t.world().world_root.get_node_or_null("DoorwayWalls") == null, "the Lair drew old wall bands")


## The rebuilt Weaver Hollow and Crystal Mine (2026-11-25, one world per room, as the Lair): every
## room world in the scene index reads its dungeon's id and record, so one seal, one set of keys and one
## map hold across all of them; their one-scene and four-floor worlds before are retired (RunState
## RETIRED_WORLDS), not in the index.
func test_every_room_world_of_the_rebuilt_dungeons_is_inside_its_dungeon(t: TestContext) -> void:
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/scenes/scene_index.json"))
	var folders := {"res://game/scenes/worlds/rooms/weaver-hollow/": "weaver-hollow",
		"res://game/scenes/worlds/rooms/crystal-mine-rooms/": "crystal-mine"}
	var counted := {}
	for key: String in index:
		var path := str(index[key])
		for folder: String in folders:
			if not (key.begins_with("world.") and path.begins_with(folder)):
				continue
			var world_id := key.trim_prefix("world.")
			var dungeon := str(folders[folder])
			t.equal(DungeonState.world_dungeon_id(world_id), dungeon, "%s's dungeon id" % world_id)
			t.equal(DungeonState.world_record_id(world_id), dungeon, "%s's record id" % world_id)
			counted[dungeon] = int(counted.get(dungeon, 0)) + 1
	t.check(int(counted.get("weaver-hollow", 0)) > 0, "no room world of the Weaver Hollow in the scene index")
	t.check(int(counted.get("crystal-mine", 0)) > 0, "no room world of the Crystal Mine in the scene index")
	var retired_worlds: Dictionary = (Services.run().get_script() as Script).get_script_constant_map()["RETIRED_WORLDS"]
	for retired: String in retired_worlds:
		t.check(not index.has("world." + retired), "the retired world %s is still in the scene index" % retired)


func _travel(t: TestContext, map_id: String) -> bool:
	if not t.in_world(map_id):
		t.main.call(&"travel_to", map_id)
	var arrived := await t.until(func() -> bool:
		return t.in_world(map_id) and t.player_body() != null and not bool(t.main.call(&"is_transitioning")), 10000.0)
	await t.steps(6)
	return t.check(arrived, "could not travel to " + map_id)
