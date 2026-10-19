extends SceneTree
## Captures a dungeon room in the running game at a real 16:9 window (docs/godot/INTERIOR_WALLS.md,
## the Lair showcase): the game starts in `--map` (default fatty-lair) and, for each shot, the slime
## stands at a point of the room, the camera follows and the screen is saved. Run windowed:
##     "<Godot console exe>" --path godot -s res://tools/render_lair_room.gd -- --out=<dir> [--prefix=after]
##         [--map=fatty-lair] [--shot=<name>:<x>,<y>] ... [--all-rooms] [--hide=<node path>,...]
## Without --shot it takes the Gatehouse's (R1): its middle and a shot at each wall's door. Shutters
## and the seal show shut with `--shut`.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
## World units: the Gatehouse is cells (32, 56) .. (48, 70).
const R1_SHOTS := {
	"middle": Vector2(2560, 4000),
	"north-doorway": Vector2(2560, 3820),
	"south-seal": Vector2(2560, 4250),
	"west-doorway": Vector2(2250, 4280),
	"east-doorway": Vector2(2880, 4280),
	"store-barricade": Vector2(2880, 4180),
}


func _initialize() -> void:
	var out := "user://lair-room"
	var prefix := "lair-room"
	var map_id := "fatty-lair"
	var shut := false
	var shots := {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--prefix="):
			prefix = arg.trim_prefix("--prefix=")
		elif arg.begins_with("--map="):
			map_id = arg.trim_prefix("--map=")
		elif arg == "--shut":
			shut = true
		elif arg.begins_with("--shot="):
			var parts := arg.trim_prefix("--shot=").split(":")
			var xy := parts[1].split(",")
			shots[parts[0]] = Vector2(float(xy[0]), float(xy[1]))
	var all_rooms := OS.get_cmdline_user_args().has("--all-rooms")
	if shots.is_empty() and not all_rooms:
		shots = R1_SHOTS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	Services.run().ensure_started()
	Services.run().autosave_enabled = false
	var main := (load("res://game/main.tscn") as PackedScene).instantiate()
	main.set(&"map_id", map_id)
	main.set(&"ability_ceremonies", false)
	root.add_child(main)
	for i in 90:
		await process_frame
	var world := Services.world()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hide="):
			for path: String in arg.trim_prefix("--hide=").split(","):
				var node := world.world_root.get_node_or_null(path) as CanvasItem
				if node != null:
					node.visible = false
	if shut:
		for node: Node in world.world_root.find_children("*", "Node2D", true, false):
			if node.has_method(&"shut_quietly"):
				node.call(&"shut_quietly")
			elif node.has_method(&"shut") and node.has_method(&"is_shut"):
				node.call(&"shut")
	if all_rooms:
		# every camera room at its RoomEntry (its middle without one)
		for room: Node in world.world_root.get_node("CameraRooms").get_children():
			var entry := room.get_node_or_null("RoomEntry") as Node2D
			shots[String(room.name)] = entry.global_position if entry != null else (room.call(&"rect") as Rect2).get_center()
	for name: String in shots:
		FeetAnchor.place_at_phaser_position(world.player_body, shots[name])
		world.player_body.reset_physics_interpolation()
		if world.elevation != null:
			world.elevation.track(world.player_body)
		world.camera.start_follow(world.player_body, true)
		for i in 50:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join("%s-%s.png" % [prefix, name])))
	print("saved to ", ProjectSettings.globalize_path(out))
	quit()
