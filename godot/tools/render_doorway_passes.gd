extends SceneTree
## Captures the slime halfway through a doorway on each side of a room in the running game, at a
## 16:9 window (docs/godot/INTERIOR_WALLS.md "Bodies in a doorway"). Run windowed:
##     "<Godot console exe>" --path godot -s res://tools/render_doorway_passes.gd -- --out=<dir> [--prefix=after]
##         [--map=fatty-lair] [--room=r3-pit-hall]
## For each side (n, s, e, w) it takes the first open doorway of the room's interior walls and stands
## the slime's feet in the middle of its passage. Writes <dir>/<prefix>-<side>.png.

const Services := preload("res://game/shared/services.gd")
const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")


func _initialize() -> void:
	var out := "user://doorway-passes"
	var prefix := "pass"
	var map_id := "fatty-lair"
	var room_name := "r3-pit-hall"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--prefix="):
			prefix = arg.trim_prefix("--prefix=")
		elif arg.begins_with("--map="):
			map_id = arg.trim_prefix("--map=")
		elif arg.begins_with("--room="):
			room_name = arg.trim_prefix("--room=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	Services.run().ensure_started()
	Services.run().autosave_enabled = false
	Services.run().set_flag("fatty-lair.burr-called")
	var main := (load("res://game/main.tscn") as PackedScene).instantiate()
	main.set(&"map_id", map_id)
	main.set(&"ability_ceremonies", false)
	root.add_child(main)
	for i in 90:
		await process_frame
	var world := Services.world()
	var layer := InteriorWalls.find(self)
	var room := world.world_root.get_node("CameraRooms/" + room_name)
	var rect: Rect2 = room.call(&"rect")
	var done := {}
	for opening in layer.openings():
		var side := str(opening["side"])
		if done.has(side) or str(opening["kind"]) != "doorway":
			continue
		var cell := Vector2(opening["cell"] as Vector2i)
		var middle := (cell + Vector2(1, 1)) * 64.0
		if not rect.has_point(middle):
			continue
		done[side] = true
		var player = world.player
		var body := world.player_body
		var feet_offset: Vector2 = body.global_position - player.get_centre()
		player.teleport(middle - feet_offset)
		body.velocity = Vector2.ZERO
		body.reset_physics_interpolation()
		world.camera.start_follow(body, true)
		for i in 40:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join("%s-%s.png" % [prefix, side])))
	print("saved ", done.keys(), " to ", ProjectSettings.globalize_path(out))
	quit()
