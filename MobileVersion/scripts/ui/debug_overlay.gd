extends CanvasLayer

@export var show_by_default := false

@onready var info_label: Label = $Root/Panel/InfoLabel

var _save_status := "No save activity yet."
var _scene_status := "SceneLoader idle."

func _ready() -> void:
	visible = show_by_default
	SaveSystem.save_status_changed.connect(func(message: String) -> void: _save_status = message)
	SceneLoader.loading_status_changed.connect(func(message: String) -> void: _scene_status = message)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		visible = not visible
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F5:
		SceneLoader.reload_current_scene()


func _process(_delta: float) -> void:
	if not visible:
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D
	var camera: Camera2D = null
	if player != null:
		camera = player.get_node_or_null("Camera2D") as Camera2D

	var input_state := InputManager.get_debug_state()
	var movement := input_state["movement_vector"] as Vector2
	var virtual_movement := input_state["virtual_movement_vector"] as Vector2
	var position := player.global_position if player != null else Vector2.ZERO

	var lines: Array[String] = [
		"Debug Overlay (F3, F5 reload)",
		"FPS: %d" % Engine.get_frames_per_second(),
		"Level: %s" % String(GameState.current_level),
		"Player: %.1f, %.1f" % [position.x, position.y],
		"Move: %.2f, %.2f" % [movement.x, movement.y],
		"Virtual Move: %.2f, %.2f" % [virtual_movement.x, virtual_movement.y],
		"Physical: %s" % _join_array(input_state["physical_pressed"] as Array),
		"Virtual Held: %s" % _join_array(input_state["virtual_pressed"] as Array),
		"Virtual Just: %s" % _join_array(input_state["virtual_just_pressed"] as Array),
		"Save: %s" % _save_status,
		"Scene: %s" % _scene_status,
	]

	if camera != null:
		lines.append("Camera Zoom: %.2f, %.2f" % [camera.zoom.x, camera.zoom.y])
		lines.append("Camera Limits: L%d T%d R%d B%d" % [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom])

	info_label.text = "\n".join(PackedStringArray(lines))


func _join_array(values: Array) -> String:
	if values.is_empty():
		return "-"

	var strings: Array[String] = []
	for value in values:
		strings.append(str(value))
	return ", ".join(PackedStringArray(strings))
