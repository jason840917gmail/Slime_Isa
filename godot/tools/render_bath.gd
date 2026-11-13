extends SceneTree
## Records the slime taking a bath (docs/godot/specs/interaction.md "Baths") in the running game: it
## starts a world, stands the slime in front of the world's first bath, takes `--hp` health away,
## presses `interact`, films the soak for `--soak-ms`, then holds `move_down` to get out. A frame is
## saved every `--frame-ms` of game time. Run windowed (it renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_bath.gd -- --out=<dir>
##         [--map=slime-home] [--soak-ms=4000] [--frame-ms=100] [--hp=6] [--window=1600x900]
## Writes <dir>/frame-<n>.png and prints a line per frame (time, hit points, bathing, the clip).

const Services := preload("res://game/shared/services.gd")
const MAIN_SCENE := "res://game/main.tscn"

var _frame := 0
var _out := "user://bath"
var _frame_ms := 100.0


func _initialize() -> void:
	var map := "slime-home"
	var soak_ms := 4000.0
	var hurt := 6
	var window := Vector2i(1600, 900)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--map="):
			map = arg.trim_prefix("--map=")
		elif arg.begins_with("--soak-ms="):
			soak_ms = float(arg.trim_prefix("--soak-ms="))
		elif arg.begins_with("--frame-ms="):
			_frame_ms = float(arg.trim_prefix("--frame-ms="))
		elif arg.begins_with("--hp="):
			hurt = int(arg.trim_prefix("--hp="))
		elif arg.begins_with("--window="):
			var wh := arg.trim_prefix("--window=").split("x")
			window = Vector2i(int(wh[0]), int(wh[1]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	DisplayServer.window_set_size(window)
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", map)
	main.set(&"playground_abilities", false)
	root.add_child(main)
	for i in 60:
		await process_frame
	var bath := get_first_node_in_group(&"bath")
	var player := _player()
	if bath == null or player == null:
		push_error("render_bath: no bath or no player in %s" % map)
		quit(1)
		return
	var request: Dictionary = bath.call(&"bath_request")
	player.call(&"teleport", request["out_point"])
	if hurt > 0:
		player.call(&"set_hp", maxi(1, int(player.call(&"get_hp")) - hurt)) if player.has_method(&"set_hp") else null
	for i in 20:
		await physics_frame
	await _film(600.0)
	_press(&"interact", true)
	await physics_frame
	_press(&"interact", false)
	await _film(soak_ms)
	_press(&"move_down", true)
	await _film(900.0)
	_press(&"move_down", false)
	print("saved %d frames to %s" % [_frame, ProjectSettings.globalize_path(_out)])
	quit(0)


func _film(ms: float) -> void:
	var started := Services.now_ms()
	var next := started
	while Services.now_ms() - started < ms:
		await physics_frame
		if Services.now_ms() < next:
			continue
		next += _frame_ms
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("frame-%03d.png" % _frame)))
		var player := _player()
		var animation := player.get(&"animation") as AnimationPlayer if player != null else null
		print("%03d t=%5.0f hp=%s bathing=%s clip=%s" % [_frame, Services.now_ms() - started,
				str(player.call(&"get_hp")) if player != null else "-",
				str(player.call(&"is_bathing")) if player != null else "-",
				String(animation.assigned_animation) if animation != null else "-"])
		_frame += 1


func _player() -> Node:
	var world := Services.world()
	var player: Variant = world.get(&"player") if world != null else null
	return player as Node if is_instance_valid(player) else null


func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)
