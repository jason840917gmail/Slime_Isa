extends SceneTree
## Records the slime going through a door (docs/godot/CONVENTIONS.md "Doors") in the running game:
## it starts a world, puts the slime in front of a door, holds the arrow key that pushes into it
## until the world changes, keeps filming the arrival on the other side, and (with `--then=`) holds
## a second key to go back out the same way. A frame is saved every `--frame-ms` of game time, with
## the world, the slime's feet and its picture's place and alpha in the log. Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_door_walk.gd -- --out=<dir>
##         --map=<world id> --feet=<x>,<y> [--key=move_up] [--then=move_down] [--frame-ms=40]
##         [--after-ms=1400] [--max-ms=4000] [--zoom=<camera zoom>] [--slow=<time scale, 0.25>] [--window=<w>x<h>, 960x540]
## Saving a frame takes real time, so the game runs slowed (`--slow`) to get close frames.
## Writes <dir>/frame-<n>.png and prints a line per frame (key, time, world, feet, art, alpha, the feet on screen, the clip).

const Services := preload("res://game/shared/services.gd")
const MAIN_SCENE := "res://game/main.tscn"
const DEFAULT_OUT := "user://door-walk"

var _frame := 0
var _out := DEFAULT_OUT
var _frame_ms := 40.0


func _initialize() -> void:
	var map := "level-1-c4"
	var feet := Vector2(1532.0, 408.0)
	var keys: Array[StringName] = [&"move_up"]
	var after_ms := 1400.0
	var max_ms := 4000.0
	var zoom := 0.0
	var slow := 0.25
	var window := Vector2i(960, 540)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--map="):
			map = arg.trim_prefix("--map=")
		elif arg.begins_with("--feet="):
			var xy := arg.trim_prefix("--feet=").split(",")
			feet = Vector2(float(xy[0]), float(xy[1]))
		elif arg.begins_with("--key="):
			keys = [StringName(arg.trim_prefix("--key="))]
		elif arg.begins_with("--then="):
			keys.append(StringName(arg.trim_prefix("--then=")))
		elif arg.begins_with("--frame-ms="):
			_frame_ms = float(arg.trim_prefix("--frame-ms="))
		elif arg.begins_with("--after-ms="):
			after_ms = float(arg.trim_prefix("--after-ms="))
		elif arg.begins_with("--max-ms="):
			max_ms = float(arg.trim_prefix("--max-ms="))
		elif arg.begins_with("--zoom="):
			zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--window="):
			var wh := arg.trim_prefix("--window=").split("x")
			window = Vector2i(int(wh[0]), int(wh[1]))
		elif arg.begins_with("--slow="):
			slow = clampf(float(arg.trim_prefix("--slow=")), 0.05, 1.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	DisplayServer.window_set_size(window)
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", map)
	main.set(&"playground_abilities", false)
	root.add_child(main)
	for i in 40:
		await process_frame
	var body := _body()
	body.global_position = feet
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	var elevation: Node = Services.world().elevation
	if elevation != null:
		elevation.call(&"track", body)
	for i in 20:
		await physics_frame
	Engine.time_scale = slow
	for key in keys:
		if zoom > 0.0 and root.get_camera_2d() != null:
			root.get_camera_2d().zoom = Vector2(zoom, zoom)
		# Push into the door until the world changes (or `max_ms`), then film the arrival.
		var from := _world_id()
		_push(key, true)
		await _film(key, max_ms, func() -> bool: return _world_id() != from)
		_push(key, false)
		if zoom > 0.0 and root.get_camera_2d() != null:
			root.get_camera_2d().zoom = Vector2(zoom, zoom)
		await _film(&"arrive", after_ms, func() -> bool: return false)
	print("saved %d frames to %s" % [_frame, ProjectSettings.globalize_path(_out)])
	quit(0)


## Films for `ms` of game time, or until `done` says so.
func _film(label: StringName, ms: float, done: Callable) -> void:
	var started := Services.now_ms()
	var next := started
	while Services.now_ms() - started < ms and not bool(done.call()):
		await physics_frame
		if Services.now_ms() < next:
			continue
		next += _frame_ms
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("frame-%03d.png" % _frame)))
		var body := _body()
		var at := body.global_position if body != null else Vector2.ZERO
		var art := _art()
		var art_at := art.global_position if art != null else Vector2.ZERO
		var on_screen := Vector2.ZERO
		if body != null:
			var view := body.get_viewport()
			on_screen = view.get_screen_transform() * (view.get_canvas_transform() * body.global_position)
		print("%03d %s t=%5.0f world=%s feet=(%.0f, %.0f) art=(%.0f, %.0f) alpha=%.2f screen=(%.0f, %.0f) clip=%s" % [_frame, label,
				Services.now_ms() - started, _world_id(), at.x, at.y, art_at.x, art_at.y,
				art.modulate.a if art != null else 0.0, on_screen.x, on_screen.y, _clip()])
		_frame += 1


func _body() -> CharacterBody2D:
	var world := Services.world()
	if world == null or not is_instance_valid(world.player_body):
		return null
	return world.player_body


## The slime's picture (the doors' walk in and out move and fade it, not the body).
func _art() -> Sprite2D:
	var world := Services.world()
	var player: Node = world.get(&"player") if world != null else null
	return player.call(&"get_visual") as Sprite2D if is_instance_valid(player) else null


## The clip the slime plays ("-" when it stands on a stopped one).
func _clip() -> String:
	var world := Services.world()
	var player: Node = world.get(&"player") if world != null else null
	var animation := player.get(&"animation") as AnimationPlayer if is_instance_valid(player) else null
	if animation == null:
		return "-"
	return String(animation.assigned_animation) + ("" if animation.is_playing() else " (stopped)")


func _world_id() -> String:
	var world := Services.world()
	return world.map_id() if world != null else ""


## The key as the game reads it (tests/lib/test_context.gd `_push`): an action event through the
## viewport.
func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)
