extends Node2D
## Terrain lab (docs/godot/TERRAIN_LAB.md): every ground pair and water shore with the hand-made
## edge tiles, on the real terrain tile set. Built by `tools/build_terrain_lab.gd`; paint more on
## `Ground` in the editor (the edges follow). Run with F6. WASD / arrows pan, mouse wheel zooms,
## Home resets the view, T switches the edges off and on (before / after).

const PAN_SPEED := 900.0
const ZOOM_STEP := 1.15
const ZOOM_MIN := 0.25
const ZOOM_MAX := 3.0

@onready var camera: Camera2D = $Camera
@onready var ground: TileMapLayer = $Ground
@onready var status: Label = $Ui/Status

var _home_position := Vector2.ZERO
var _home_zoom := Vector2.ONE


func _ready() -> void:
	_home_position = camera.position
	_home_zoom = camera.zoom
	_show_status()


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
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_HOME:
		camera.position = _home_position
		camera.zoom = _home_zoom
	elif key.keycode == KEY_T:
		var edges := ground.get_node_or_null(^"TerrainEdges") as CanvasItem
		if edges != null:
			edges.visible = not edges.visible
		_show_status()


func _zoom_by(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)


func _show_status() -> void:
	var edges := ground.get_node_or_null(^"TerrainEdges") as CanvasItem
	var on := edges != null and edges.visible
	status.text = "Edge tiles: %s   (T switches, WASD pans, wheel zooms, Home resets)" % ("ON" if on else "OFF - hard edges as before")
