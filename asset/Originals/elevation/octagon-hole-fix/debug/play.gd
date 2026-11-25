extends SceneTree
## Plays the playground (spawn with `-- --spawn=x,y`); WALK_PLAN="seconds:action;..." holds those input actions in turn ("1.0:;3:" = stand still).
var _t := 0.0
var _held := ""
var PLAN: Array = []

func _initialize() -> void:
	var raw := OS.get_environment("WALK_PLAN")
	for part: String in raw.split(";", false):
		var bits := part.split(":")
		PLAN.append([float(bits[0]), bits[1] if bits.size() > 1 else ""])
	change_scene_to_file.call_deferred("res://game/dev/playground.tscn")

func _send(action: String, pressed: bool) -> void:
	if action.is_empty():
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

func _process(delta: float) -> bool:
	_t += delta
	var want := ""
	for step: Array in PLAN:
		if _t < float(step[0]):
			want = step[1]
			break
	if want != _held:
		_send(_held, false)
		_send(want, true)
		_held = want
	return false
