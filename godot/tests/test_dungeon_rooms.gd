extends RefCounted
## Separate authored dungeon rooms, stable puzzle paths and the room-edge mask.
const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const MAP_ID := "fatty-lair"

func test_room_scenes_assemble_without_changing_shared_puzzle_paths(t: TestContext) -> void:
	var packed := load("res://game/scenes/worlds/fatty-lair.tscn") as PackedScene
	var state := packed.get_state()
	var count := 0
	for i in state.get_node_count():
		var instance := state.get_node_instance(i)
		if instance != null and instance.resource_path.begins_with("res://game/scenes/worlds/rooms/fatty-lair/"):
			count += 1
	t.equal(count, 24, "separate room scene instances")
	var world := t.world().world_root
	t.check(not world.has_node("RoomScenes"), "authored containers were not assembled before ready")
	var stair := world.get_node("Lair/inner-stair")
	t.check(stair.get_node_or_null(stair.get(&"target")) != null, "cross-room stair target was lost")
	var director := world.get_node("Lair/Director") if world.has_node("Lair/Director") else world.find_child("LairDirector", true, false)
	if director != null:
		t.check(director.get_node_or_null(director.get(&"cell_door")) != null, "Burr's door path was lost")
	t.check(world.has_node("Hazards/void-65-31/Return0"), "hazard return markers survive room packing")

func test_l_shaped_hall_keeps_burr_behind_the_closed_cell_door(t: TestContext) -> void:
	Services.run().set_flag("fatty-lair.burr-called")
	var world := t.world()
	var hub := world.world_root.get_node("CameraRooms/r3-pit-hall")
	var cell := world.world_root.get_node("CameraRooms/burr-cell")
	var burr := world.world_root.get_node("Lair/burr") as Node2D
	t.check(not bool(hub.call(&"contains", burr.global_position)), "the hall outline includes Burr behind the door")
	t.check(bool(cell.call(&"contains", burr.global_position)), "Burr is outside his cell's room")
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
	var door := t.world().world_root.get_node("Objects/hub-burr-cell-door")
	var frame := door.get_node_or_null("WallDoorway") as Sprite2D
	t.check(frame != null and frame.texture != null, "no integrated arch")
	if frame != null and frame.texture != null:
		t.check(frame.texture.resource_path.ends_with("masonry-arch.res"), "the Lair arch does not use its masonry")
	var leaf := door.get_node("Shut/Door") as Sprite2D
	t.check(leaf.texture.resource_path.ends_with("oak-leaf.res"), "the moving leaf still includes the old grey frame")
	var shape := door.get_node("Body/Shape") as CollisionShape2D
	t.equal((shape.shape as RectangleShape2D).size.x, 128.0, "two-cell door collision")


func test_shell_keeps_each_hollow_floor_inside_the_sealed_dungeon(t: TestContext) -> void:
	for floor_name: String in ["trunk", "roots", "boughs", "crown"]:
		t.equal(DungeonState.world_dungeon_id("weaver-hollow-" + floor_name), "weaver-hollow", "cross-floor dungeon identity " + floor_name)
