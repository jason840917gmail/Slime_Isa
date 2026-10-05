extends Node2D
## Terrain lab (docs/godot/TERRAIN_LAB.md): today's hard-edged 64 px ground beside the
## 128 px ground with hand-made snow edge tiles. Built by `tools/build_terrain_lab.gd`;
## paint more snow on `EdgeTiles/SnowEdges` with the Terrains tab (Terrain Set 0, "Snow").
## Run with F6. WASD / arrows pan, mouse wheel zooms, Home resets the view.

const PAN_SPEED := 900.0
const ZOOM_STEP := 1.15
const ZOOM_MIN := 0.25
const ZOOM_MAX := 3.0

@onready var camera: Camera2D = $Camera

var _home_position := Vector2.ZERO
var _home_zoom := Vector2.ONE


func _ready() -> void:
	_home_position = camera.position
	_home_zoom = camera.zoom


func _process(delta: float) -> void:
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	camera.position += direction * PAN_SPEED * delta / camera.zoom.x


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(ZOOM_STEP)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / ZOOM_STEP)
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_HOME:
		camera.position = _home_position
		camera.zoom = _home_zoom


func _zoom_by(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
