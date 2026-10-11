@tool
extends Node2D
## Fixed-cell tile audition. The TileMapLayer is baked and manually editable.
@export var show_collision: bool = false:
	set(value):
		show_collision = value
		queue_redraw()
var _dragging: bool = false


func _ready() -> void:
	queue_redraw()
	if not Engine.is_editor_hint():
		_overview()


func _draw() -> void:
	draw_rect(Rect2(-500, -500, 3400, 3200), Color("#3d4c27"))
	var font: Font = ThemeDB.fallback_font
	var ink := Color("#ede2bd")
	for entry: Array in [[Vector2(128, 150), "1 ROW OF WALL"], [Vector2(896, 150), "2 ROWS OF WALL"],
			[Vector2(1664, 150), "4 ROWS OF WALL"], [Vector2(128, 920), "TERRACE / FIXED TILES"],
			[Vector2(1536, 920), "L SHAPE / JOIN AUDIT"]]:
		draw_string(font, entry[0], entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)


func _overview() -> void:
	var camera := get_node("Camera2D") as Camera2D
	camera.position = Vector2(1160, 1050)
	var extent := get_viewport_rect().size
	camera.zoom = Vector2.ONE * minf(extent.x / 2600.0, extent.y / 2350.0)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var camera := get_node("Camera2D") as Camera2D
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mouse.pressed
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and mouse.ctrl_pressed:
			(get_node("Probe") as CharacterBody2D).position = get_global_mouse_position()
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor: float = 1.15 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, 0.25, 2.0)
	elif event is InputEventMouseMotion and _dragging:
		camera.position -= (event as InputEventMouseMotion).relative / camera.zoom
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed:
			return
		match key.keycode:
			KEY_C:
				show_collision = not show_collision
			KEY_HOME:
				_overview()
			KEY_1:
				camera.position = Vector2(1100, 500)
				camera.zoom = Vector2.ONE * 0.65
			KEY_2:
				camera.position = Vector2(650, 1410)
				camera.zoom = Vector2.ONE * 0.8
			KEY_3:
				camera.position = Vector2(1870, 1370)
				camera.zoom = Vector2.ONE * 0.9

