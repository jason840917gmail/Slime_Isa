extends RefCounted
## Separately authored dungeon rooms: Fatty's Lair's rooms are each a world (since 2026-10-18; their
## doors and records: test_lair_rooms.gd), their links kept by world and record; the room-edge mask;
## the Weaver Hollow's floors in one sealed dungeon.
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
	t.equal([str(stair.get(&"target_world")), str(stair.get(&"target_marker"))], ["fatty-lair-r8-guard-crypt", "crypt-stair-arrival"],
		"the Inner Stair's way down to the crypt's world")
	var director := world.get_node_or_null("Lair/LairDirector")
	if t.check(director != null, "the hub has no Lair director (Burr's)"):
		t.check(director.get_node_or_null(director.get(&"cell_door")) != null, "Burr's door path was lost")
		t.check(director.get_node_or_null(director.get(&"burr")) != null, "Burr is not in the hub's world")
		t.check(not director.is_in_group(&"dungeon_map_mark"), "the hub's director marks the boss on the map")
	if not await _travel(t, "fatty-lair-glow-moss-burrow"):
		return
	var returns := 0
	for hazard: Node in t.world().world_root.get_node("Hazards").get_children():
		if hazard.has_node("Return0"):
			returns += 1
	t.check(returns > 0, "hazard return markers survive in the Burrow's world")


func test_l_shaped_hall_keeps_burr_behind_the_closed_cell_door(t: TestContext) -> void:
	Services.run().set_flag("fatty-lair.burr-called")
	if not await _travel(t, HUB):
		return
	var world := t.world()
	var hub := world.world_root.get_node("CameraRooms/r3-pit-hall")
	var burr := world.world_root.get_node("Lair/burr") as Node2D
	t.check(not bool(hub.call(&"contains", burr.global_position)), "the hall outline includes Burr behind the door")
	t.teleport_player((hub.get_node("RoomEntry") as Node2D).global_position)
	world.camera.start_follow(t.player_body(), true)
	await t.steps(5)
	var mask := world.world_root.get_node("Dungeon/RoomMask")
	var material := mask.get(&"_material") as ShaderMaterial
	t.equal(int(material.get_shader_parameter(&"point_count")), 6, "L-shaped mask vertices")
	var screen: Vector2 = world.camera.world_to_screen(burr.global_position) / t.tree.root.get_visible_rect().size
	var outline: PackedVector2Array = material.get_shader_parameter(&"outline")
	outline.resize(6)
	t.check(not Geometry2D.is_point_in_polygon(screen, outline), "the hall mask reveals Burr")
	var frames: PackedVector4Array = material.get_shader_parameter(&"wall_frames")
	for i in int(material.get_shader_parameter(&"frame_count")):
		var frame := frames[i]
		t.check(not Rect2(Vector2(frame.x, frame.y), Vector2(frame.z - frame.x, frame.w - frame.y)).has_point(screen), "a wall frame exposes Burr")


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


func test_shell_keeps_each_hollow_floor_inside_the_sealed_dungeon(t: TestContext) -> void:
	for floor_name: String in ["trunk", "roots", "boughs", "crown"]:
		t.equal(DungeonState.world_dungeon_id("weaver-hollow-" + floor_name), "weaver-hollow", "cross-floor dungeon identity " + floor_name)


func _travel(t: TestContext, map_id: String) -> bool:
	if not t.in_world(map_id):
		t.main.call(&"travel_to", map_id)
	var arrived := await t.until(func() -> bool:
		return t.in_world(map_id) and t.player_body() != null and not bool(t.main.call(&"is_transitioning")), 10000.0)
	await t.steps(6)
	return t.check(arrived, "could not travel to " + map_id)
