extends CanvasLayer

@export var show_on_desktop := false
@export var action_button_size := 76.0
@export var action_button_spacing := 12.0

@onready var root: Control = $Root
@onready var move_pad: Control = $Root/MovePad
@onready var joystick_knob: Control = $Root/MovePad/JoystickKnob
@onready var action_pad: Control = $Root/ActionPad
@onready var jump_button: Button = $Root/ActionPad/JumpButton
@onready var roll_button: Button = $Root/ActionPad/RollButton
@onready var interact_button: Button = $Root/ActionPad/InteractButton
@onready var trick_button: Button = $Root/ActionPad/TrickButton
@onready var stretch_button: Button = $Root/ActionPad/StretchButton
@onready var squash_button: Button = $Root/ActionPad/SquashButton
@onready var teleport_button: Button = $Root/ActionPad/TeleportButton
@onready var teleport_cooldown_overlay: ColorRect = $Root/ActionPad/TeleportButton/CooldownOverlay
@onready var pause_button: Button = $Root/PauseButton

var _joystick_center := Vector2.ZERO
var _joystick_radius := 1.0
var _joystick_active := false

func _ready() -> void:
	visible = show_on_desktop or OS.has_feature("mobile") or OS.is_debug_build()
	move_pad.gui_input.connect(_on_move_pad_gui_input)
	get_viewport().size_changed.connect(_reflow_controls)
	_reflow_controls()

	_bind_hold_button(jump_button, &"jump")
	_bind_hold_button(roll_button, &"roll")
	_bind_pulse_button(interact_button, &"interact")
	_bind_pulse_button(trick_button, &"trick")
	_bind_pulse_button(stretch_button, &"stretch")
	_bind_pulse_button(squash_button, &"squash")
	_bind_pulse_button(teleport_button, &"teleport")
	_bind_pulse_button(pause_button, &"pause")


func _process(_delta: float) -> void:
	_update_ability_cooldowns()


func _reflow_controls() -> void:
	if not is_inside_tree():
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var safe_rect := Rect2(Vector2.ZERO, viewport_size)

	if OS.has_feature("mobile"):
		var display_safe_area := DisplayServer.get_display_safe_area()
		if display_safe_area.size.x > 0 and display_safe_area.size.y > 0:
			safe_rect = Rect2(Vector2(display_safe_area.position), Vector2(display_safe_area.size))

	var ui_scale := clampf(viewport_size.y / 720.0, 0.82, 1.35)
	var joystick_size := 184.0 * ui_scale
	var joystick_margin := Vector2(maxf(28.0, viewport_size.x * 0.055), 30.0) * ui_scale
	var action_size := action_button_size * ui_scale
	var spacing := action_button_spacing * ui_scale

	move_pad.position = Vector2(
		safe_rect.position.x + joystick_margin.x,
		safe_rect.position.y + safe_rect.size.y - joystick_size - joystick_margin.y
	)
	move_pad.size = Vector2(joystick_size, joystick_size)

	_joystick_center = move_pad.size * 0.5
	_joystick_radius = joystick_size * 0.42
	joystick_knob.size = Vector2(action_size * 0.72, action_size * 0.72)
	_reset_joystick_knob()

	var columns := 4.0
	var rows := 2.0
	action_pad.size = Vector2((action_size * columns) + (spacing * (columns - 1.0)), (action_size * rows) + spacing)
	action_pad.position = Vector2(
		safe_rect.position.x + safe_rect.size.x - action_pad.size.x - (28.0 * ui_scale),
		safe_rect.position.y + safe_rect.size.y - action_pad.size.y - (30.0 * ui_scale)
	)

	_layout_action_button(jump_button, Vector2.ZERO, Vector2(action_size, action_size))
	_layout_action_button(roll_button, Vector2(action_size + spacing, 0.0), Vector2(action_size, action_size))
	_layout_action_button(interact_button, Vector2((action_size + spacing) * 2.0, 0.0), Vector2(action_size, action_size))
	_layout_action_button(trick_button, Vector2((action_size + spacing) * 3.0, 0.0), Vector2(action_size, action_size))
	_layout_action_button(stretch_button, Vector2(0.0, action_size + spacing), Vector2(action_size, action_size))
	_layout_action_button(squash_button, Vector2(action_size + spacing, action_size + spacing), Vector2(action_size, action_size))
	_layout_action_button(teleport_button, Vector2((action_size + spacing) * 2.0, action_size + spacing), Vector2(action_size, action_size))
	_update_ability_cooldowns()

	pause_button.size = Vector2(96.0, 44.0) * ui_scale
	pause_button.position = Vector2(
		safe_rect.position.x + safe_rect.size.x - pause_button.size.x - (18.0 * ui_scale),
		safe_rect.position.y + (18.0 * ui_scale)
	)


func _layout_action_button(button: Button, position: Vector2, size: Vector2) -> void:
	button.position = position
	button.size = size


func _on_move_pad_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_joystick_active = event.pressed
		if event.pressed:
			_update_joystick(event.position)
		else:
			_clear_joystick()
	elif event is InputEventScreenDrag and _joystick_active:
		_update_joystick(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_joystick_active = event.pressed
		if event.pressed:
			_update_joystick(event.position)
		else:
			_clear_joystick()
	elif event is InputEventMouseMotion and _joystick_active:
		_update_joystick(event.position)


func _update_joystick(local_position: Vector2) -> void:
	var vector := (local_position - _joystick_center) / _joystick_radius
	vector = vector.limit_length(1.0)
	InputManager.set_virtual_movement_vector(vector)
	joystick_knob.position = _joystick_center + (vector * _joystick_radius) - (joystick_knob.size * 0.5)


func _clear_joystick() -> void:
	InputManager.set_virtual_movement_vector(Vector2.ZERO)
	_reset_joystick_knob()


func _reset_joystick_knob() -> void:
	joystick_knob.position = _joystick_center - (joystick_knob.size * 0.5)


func _bind_hold_button(button: BaseButton, action: StringName) -> void:
	button.button_down.connect(func() -> void:
		AudioManager.play_sfx(&"click")
		InputManager.set_virtual_action(action, true)
	)
	button.button_up.connect(func() -> void: InputManager.set_virtual_action(action, false))


func _bind_pulse_button(button: BaseButton, action: StringName) -> void:
	button.pressed.connect(func() -> void:
		AudioManager.play_sfx(&"click")
		InputManager.pulse_virtual_action(action)
	)


func _update_ability_cooldowns() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_ability_cooldown_state"):
		_set_teleport_cooldown_display(0.0, 1.0)
		return

	var cooldowns: Dictionary = player.call("get_ability_cooldown_state") as Dictionary
	var teleport: Dictionary = cooldowns.get("teleport", {}) as Dictionary
	var remaining := float(teleport.get("remaining", 0.0))
	var duration := float(teleport.get("duration", 1.0))
	_set_teleport_cooldown_display(remaining, duration)


func _set_teleport_cooldown_display(remaining: float, duration: float) -> void:
	var is_cooling_down := remaining > 0.0
	teleport_button.disabled = is_cooling_down
	if is_cooling_down:
		teleport_button.text = "TP\n%.1f" % remaining
	else:
		teleport_button.text = "TP"
	teleport_cooldown_overlay.visible = is_cooling_down

	if not is_cooling_down:
		return

	var progress := clampf(remaining / maxf(duration, 0.01), 0.0, 1.0)
	teleport_cooldown_overlay.position = Vector2(0.0, teleport_button.size.y * (1.0 - progress))
	teleport_cooldown_overlay.size = Vector2(teleport_button.size.x, teleport_button.size.y * progress)
