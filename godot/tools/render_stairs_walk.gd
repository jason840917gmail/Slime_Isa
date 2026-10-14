extends SceneTree
## Records the stairs walk (docs/godot/ELEVATION.md "Stairs walk") in the running game: it starts a
## world, puts the slime below (or above) a flight of stairs, holds the arrow key that walks onto
## it and saves a frame every FRAME_MS of game time, with the slime's level and feet in the log.
## Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_stairs_walk.gd -- --out=<dir>
##         [--map=playground] [--feet=<x>,<y>] [--key=move_up] [--ms=2600] [--then=move_down]
## Writes <dir>/frame-<n>.png and prints a line per frame (time, feet, level, on the stairs).
## The default is the playground park's two-level south flight (tests/test_elevation.gd STAIRS_X),
## walked up and then back down.

const Services := preload("res://game/shared/services.gd")
const MAIN_SCENE := "res://game/main.tscn"
const DEFAULT_OUT := "user://stairs-walk"
const FRAME_MS := 80.0


func _initialize() -> void:
	var out := DEFAULT_OUT
	var map := "playground"
	var feet := Vector2(18.5 * 64.0, 38 * 64.0 + 50.0)
	var keys: Array[StringName] = [&"move_up"]
	var ms := 2600.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--map="):
			map = arg.trim_prefix("--map=")
		elif arg.begins_with("--feet="):
			var xy := arg.trim_prefix("--feet=").split(",")
			feet = Vector2(float(xy[0]), float(xy[1]))
		elif arg.begins_with("--key="):
			keys = [StringName(arg.trim_prefix("--key="))]
		elif arg.begins_with("--then="):
			keys.append(StringName(arg.trim_prefix("--then=")))
		elif arg.begins_with("--ms="):
			ms = float(arg.trim_prefix("--ms="))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	DisplayServer.window_set_size(Vector2i(960, 540))
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", map)
	main.set(&"playground_abilities", false)
	root.add_child(main)
	for i in 40:
		await process_frame
	var player: Node = Services.world().player
	var body := player.get(&"body") as CharacterBody2D
	var elevation: Node = Services.world().elevation
	body.global_position = feet
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	elevation.call(&"track", body)
	for i in 20:
		await physics_frame
	var frame := 0
	for key in keys:
		_push(key, true)
		var started := Services.now_ms()
		var next := started
		while Services.now_ms() - started < ms:
			await physics_frame
			if Services.now_ms() >= next:
				next += FRAME_MS
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out.path_join("frame-%03d.png" % frame)))
				print("%s t=%5.0f feet=(%.0f, %.0f) level=%d stairs=%s" % [key, Services.now_ms() - started,
						body.global_position.x, body.global_position.y, int(elevation.call(&"level_of", body)),
						str(player.call(&"is_on_stairs"))])
				frame += 1
		_push(key, false)
		for i in 10:
			await physics_frame
	print("saved %d frames to %s" % [frame, ProjectSettings.globalize_path(out)])
	quit(0)


## The key as the game reads it (tests/lib/test_context.gd `_push`): an action event through the
## viewport.
func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)
