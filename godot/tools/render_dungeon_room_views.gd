extends SceneTree
const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
var _out := "user://dungeon-room-review"
const SHOTS: Array[Array] = [["fatty-lair", "r1-gatehouse", "live-r1-wide"], ["fatty-lair", "r5-eye-hall", "live-r5-wide"], ["fatty-lair", "r3-pit-hall", "live-hub-wide"], ["weaver-hollow-trunk", "", "live-hollow-wide"], ["crystal-mine", "", "live-mine-wide"]]
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	Services.run().ensure_started()
	Services.run().autosave_enabled = false
	var main := (load("res://game/main.tscn") as PackedScene).instantiate()
	main.set(&"map_id", "fatty-lair")
	main.set(&"ability_ceremonies", false)
	root.add_child(main)
	for i in 90:
		await process_frame
	Services.run().set_flag("fatty-lair.burr-called")
	for shot: Array in SHOTS:
		if Services.world().map_id() != str(shot[0]):
			main.travel_to(str(shot[0]))
			while main.is_transitioning():
				await process_frame
		var world := Services.world()
		var rooms := world.world_root.get_node("CameraRooms")
		var room := rooms.get_node_or_null(NodePath(str(shot[1]))) if str(shot[1]) != "" else rooms.get_child(0)
		if room == null:
			continue
		var entry := room.get_node_or_null("RoomEntry") as Node2D
		var at: Vector2 = entry.global_position if entry != null else room.rect().get_center()
		FeetAnchor.place_at_phaser_position(world.player_body, at)
		world.player_body.reset_physics_interpolation()
		world.elevation.track(world.player_body)
		world.camera.start_follow(world.player_body, true)
		for i in 45:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join(str(shot[2]) + ".png")))
	quit()
