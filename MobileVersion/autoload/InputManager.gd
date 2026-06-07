extends Node

const ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_up",
	&"move_down",
	&"jump",
	&"roll",
	&"interact",
	&"trick",
	&"stretch",
	&"squash",
	&"teleport",
	&"ability_1",
	&"ability_2",
	&"pause",
]

var _virtual_pressed: Dictionary = {}
var _virtual_just_pressed: Dictionary = {}
var _virtual_movement_vector := Vector2.ZERO

func _ready() -> void:
	_ensure_default_actions()


func get_movement_vector() -> Vector2:
	var keyboard_vector := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	return _virtual_movement_vector if _virtual_movement_vector != Vector2.ZERO else keyboard_vector


func is_action_pressed(action: StringName) -> bool:
	return Input.is_action_pressed(action) or _is_virtual_pressed(action)


func consume_action_just_pressed(action: StringName) -> bool:
	if Input.is_action_just_pressed(action):
		return true

	if bool(_virtual_just_pressed.get(action, false)):
		_virtual_just_pressed[action] = false
		return true

	return false


func set_virtual_action(action: StringName, pressed: bool) -> void:
	var was_pressed := _is_virtual_pressed(action)
	_virtual_pressed[action] = pressed

	if pressed and not was_pressed:
		_virtual_just_pressed[action] = true


func pulse_virtual_action(action: StringName) -> void:
	_virtual_pressed[action] = false
	_virtual_just_pressed[action] = true


func set_virtual_movement_vector(vector: Vector2) -> void:
	_virtual_movement_vector = vector.limit_length(1.0)


func clear_virtual_state() -> void:
	_virtual_pressed.clear()
	_virtual_just_pressed.clear()
	_virtual_movement_vector = Vector2.ZERO


func get_debug_state() -> Dictionary:
	var physical_pressed: Array[String] = []
	var virtual_pressed: Array[String] = []
	var virtual_just_pressed: Array[String] = []

	for action in ACTIONS:
		if Input.is_action_pressed(action):
			physical_pressed.append(String(action))
		if _is_virtual_pressed(action):
			virtual_pressed.append(String(action))
		if bool(_virtual_just_pressed.get(action, false)):
			virtual_just_pressed.append(String(action))

	return {
		"movement_vector": get_movement_vector(),
		"virtual_movement_vector": _virtual_movement_vector,
		"physical_pressed": physical_pressed,
		"virtual_pressed": virtual_pressed,
		"virtual_just_pressed": virtual_just_pressed,
	}


func _is_virtual_pressed(action: StringName) -> bool:
	return bool(_virtual_pressed.get(action, false))


func _ensure_default_actions() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

	_add_key(&"move_left", KEY_LEFT)
	_add_key(&"move_left", KEY_A)
	_add_key(&"move_left", KEY_I)
	_add_key(&"move_right", KEY_RIGHT)
	_add_key(&"move_right", KEY_D)
	_add_key(&"move_right", KEY_L)
	_add_key(&"move_up", KEY_UP)
	_add_key(&"move_up", KEY_W)
	_add_key(&"move_up", KEY_K)
	_add_key(&"move_down", KEY_DOWN)
	_add_key(&"move_down", KEY_S)
	_add_key(&"move_down", KEY_J)
	_add_key(&"jump", KEY_SPACE)
	_add_key(&"roll", KEY_Q)
	_add_key(&"interact", KEY_F)
	_add_key(&"trick", KEY_E)
	_add_key(&"stretch", KEY_R)
	_add_key(&"squash", KEY_T)
	_add_key(&"teleport", KEY_Y)
	_add_key(&"ability_1", KEY_E)
	_add_key(&"ability_2", KEY_R)
	_add_key(&"pause", KEY_ESCAPE)


func _add_key(action: StringName, keycode: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode

	for existing_event in InputMap.action_get_events(action):
		if existing_event is InputEventKey and existing_event.physical_keycode == keycode:
			return

	InputMap.action_add_event(action, event)
