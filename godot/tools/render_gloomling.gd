extends SceneTree
## Films the Gloomling (docs/godot/BESTIARY.md "23. Gloomling") in the running game, in the
## playground's Bestiary corner: `flee` in pen 23 (the pen lends the Lantern: the slime walks at the
## shadow with its ember glowing and it runs) and `attack` in pen 34 (the pen lends the Goo Bomb, so
## the slime has no light: it stands in the dark until the shadows come and bite, walks into the
## brazier's glow, where they give up, and steps out into the dark again). A frame is saved every `--frame-ms` of
## game time, with each shadow's phase and place and the slime's health in the log. Run windowed (it
## renders), from the repo:
##     "<Godot 4.7.2 console exe>" --path godot -s res://tools/render_gloomling.gd -- --out=<dir>
##         [--scene=flee|attack] [--see] [--zoom=<camera zoom>] [--frame-ms=80]
##         [--slow=<time scale, 0.25>] [--window=<w>x<h>, 960x540]
## `--see` thins the dark rooms' darkness for the picture (the bodies show; in the game a dark room
## is black and only the eyes show). Saving a frame takes real time, so the game runs slowed.
## Writes <dir>/<scene>-<n>.png. Nothing is saved; the scenes are not changed.

const Services := preload("res://game/shared/services.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const MAIN_SCENE := "res://game/main.tscn"
const DEFAULT_OUT := "user://gloomling"
const CORNER := "bestiary-corner"
const DARK_ROOM_GROUP := &"dark_rooms"
const SEE_DARKNESS := 0.6
## Per scene: the pen, where the slime starts (its feet, from the pen's top-left) and its steps
## [label, where it walks to (from the pen's top-left; INF: it stands), ms].
const SCENES := {
	"flee": {"pen": 23, "feet": Vector2(256, 430), "steps": [
		["wait", Vector2.INF, 900.0],
		["walk-at-it", Vector2(256, 300), 1600.0],
		["after-it", Vector2(390, 150), 1800.0],
		["stand", Vector2.INF, 1200.0],
	]},
	"attack": {"pen": 34, "feet": Vector2(100, 250), "steps": [
		["in-the-dark", Vector2.INF, 4000.0],
		["to-the-brazier", Vector2(200, 262), 3600.0],
		["out-again", Vector2(90, 330), 3600.0],
	]},
}
const MOVE_KEYS := {&"move_left": Vector2.LEFT, &"move_right": Vector2.RIGHT, &"move_up": Vector2.UP, &"move_down": Vector2.DOWN}
## A walk stops this near its point (px), and a key is held only for more than this much of the way.
const ARRIVE_PX := 6.0

var _frame := 0
var _out := DEFAULT_OUT
var _frame_ms := 80.0
var _scene := "attack"
var _pen: Node
## The walk keys held now (action -> bool).
var _held: Dictionary = {}
var _zoom := 0.0


func _initialize() -> void:
	var slow := 0.25
	var see := false
	var window := Vector2i(960, 540)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--scene="):
			_scene = arg.trim_prefix("--scene=")
		elif arg == "--see":
			see = true
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--frame-ms="):
			_frame_ms = float(arg.trim_prefix("--frame-ms="))
		elif arg.begins_with("--slow="):
			slow = clampf(float(arg.trim_prefix("--slow=")), 0.05, 1.0)
		elif arg.begins_with("--window="):
			var wh := arg.trim_prefix("--window=").split("x")
			window = Vector2i(int(wh[0]), int(wh[1]))
	if not SCENES.has(_scene):
		push_error("render_gloomling: no scene '%s'" % _scene)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	DisplayServer.window_set_size(window)
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set(&"map_id", "playground")
	main.set(&"ability_ceremonies", false)
	root.add_child(main)
	for i in 120:
		await process_frame
	var plan: Dictionary = SCENES[_scene]
	var corner := root.find_child(CORNER, true, false)
	_pen = corner.call(&"pen", int(plan["pen"])) if corner != null else null
	if _pen == null:
		push_error("render_gloomling: no pen %d" % int(plan["pen"]))
		quit(1)
		return
	if see:
		for room: Node in root.get_tree().get_nodes_in_group(DARK_ROOM_GROUP):
			var overlay := room.get_node_or_null(^"Darkness") as ColorRect
			if overlay != null and overlay.material is ShaderMaterial:
				(overlay.material as ShaderMaterial).set_shader_parameter(&"darkness", SEE_DARKNESS)
	var body := _body()
	body.global_position = (_pen as Node2D).global_position + (plan["feet"] as Vector2)
	body.velocity = Vector2.ZERO
	body.reset_physics_interpolation()
	var elevation: Node = Services.world().elevation
	if elevation != null:
		elevation.call(&"track", body)
	# The camera settles on the slime first; then fresh shadows at their posts, filmed from their
	# first step (the tell).
	for i in 30:
		await physics_frame
	_pen.call(&"respawn")
	for i in 2:
		await physics_frame
	Engine.time_scale = slow
	for step: Array in plan["steps"]:
		var to: Vector2 = step[1]
		await _film(str(step[0]), to + (_pen as Node2D).global_position if to != Vector2.INF else to, float(step[2]))
	print("saved %d frames to %s" % [_frame, ProjectSettings.globalize_path(_out)])
	quit(0)


## Films for `ms` of game time, the slime walking to the world point `to` (INF: standing).
func _film(label: String, to: Vector2, ms: float) -> void:
	var started := Services.now_ms()
	var next := started
	while Services.now_ms() - started < ms:
		await physics_frame
		_steer(to)
		if _zoom > 0.0 and root.get_camera_2d() != null:
			root.get_camera_2d().zoom = Vector2(_zoom, _zoom)
		if Services.now_ms() < next:
			continue
		next += _frame_ms
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join("%s-%03d.png" % [_scene, _frame])))
		var world := Services.world()
		var player: Node = world.get(&"player")
		var body := _body()
		var shadows := PackedStringArray()
		for enemy: Node in _pen.call(&"living"):
			var at: Vector2 = enemy.call(&"get_centre")
			shadows.append("%s(%.0f, %.0f) dread=%.2f" % [enemy.call(&"get_phase"), at.x, at.y, float(enemy.call(&"get_dread"))])
		print("%03d %-18s t=%5.0f hp=%d box=%s feet=(%.0f, %.0f) | %s" % [_frame, label, Services.now_ms() - started,
				int(player.call(&"get_hp")), AbilityBox.selected(player), body.global_position.x, body.global_position.y,
				"  ".join(shadows)])
		_frame += 1


## Holds the walk keys that lead the slime's feet to `to` (none once it is there, or for INF).
func _steer(to: Vector2) -> void:
	var body := _body()
	var way := to - body.global_position if to != Vector2.INF and body != null else Vector2.ZERO
	for action: StringName in MOVE_KEYS:
		var along := way.dot(MOVE_KEYS[action] as Vector2)
		var hold := along > ARRIVE_PX
		if bool(_held.get(action, false)) != hold:
			_held[action] = hold
			_push(action, hold)


func _body() -> CharacterBody2D:
	var world := Services.world()
	if world == null or not is_instance_valid(world.player_body):
		return null
	return world.player_body


## The key as the game reads it (tests/lib/test_context.gd `_push`): an action event through the
## viewport.
func _push(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event)
