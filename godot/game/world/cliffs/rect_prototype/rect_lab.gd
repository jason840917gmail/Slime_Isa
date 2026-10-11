@tool
extends Node2D
## Standalone visual audition; F6 runs directly, without world registration or saves.
@export var pan_speed: float = 900.0

var _dragging: bool = false


func _ready() -> void:
	queue_redraw()
	if not Engine.is_editor_hint():
		_fit_overview()


func _draw() -> void:
	draw_rect(Rect2(-600, -600, 3400, 3000), Color("#3d4c27"))
	var font: Font = ThemeDB.fallback_font
	var ink := Color("#ede2bd")
	draw_string(font, Vector2(80, 250), "ONE LEVEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	draw_string(font, Vector2(760, 250), "TWO LEVELS", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	draw_string(font, Vector2(1440, 250), "FOUR LEVELS", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	draw_string(font, Vector2(80, 840), "THREE-LEVEL TERRACE", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	draw_string(font, Vector2(1320, 900), "EDITABLE RECTANGLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	draw_string(font, Vector2(1130, 1640), "Slime scale reference", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var camera := get_node("Camera2D") as Camera2D
	camera.position += direction * pan_speed * delta / camera.zoom.x


func _fit_overview() -> void:
	var camera := get_node("Camera2D") as Camera2D
	var viewport_size := get_viewport_rect().size
	var factor: float = minf(viewport_size.x / 2220.0, viewport_size.y / 2100.0)
	camera.position = Vector2(1040, 950)
	camera.zoom = Vector2.ONE * factor


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var camera := get_node("Camera2D") as Camera2D
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = button.pressed
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before := get_global_mouse_position()
			var factor: float = 1.15 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, 0.25, 2.0)
			camera.force_update_scroll()
			camera.position += before - get_global_mouse_position()
	elif event is InputEventMouseMotion and _dragging:
		camera.position -= (event as InputEventMouseMotion).relative / camera.zoom
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed:
			return
		var editable := get_node("EditableRectangle") as Node2D
		match key.keycode:
			KEY_HOME:
				_fit_overview()
			KEY_1:
				camera.position = Vector2(1040, 510)
				camera.zoom = Vector2.ONE * 0.8
			KEY_2:
				camera.position = Vector2(650, 1280)
				camera.zoom = Vector2.ONE * 0.9
			KEY_3:
				camera.position = Vector2(1640, 1240)
				camera.zoom = Vector2.ONE
			KEY_UP, KEY_DOWN:
				var amount: int = 1 if key.keycode == KEY_UP else -1
				var property: StringName = &"depth_cells" if key.shift_pressed else &"wall_levels"
				var minimum: int = 2 if key.shift_pressed else 1
				var maximum: int = 24 if key.shift_pressed else 8
				editable.set(property, clampi(int(editable.get(property)) + amount, minimum, maximum))
			KEY_LEFT, KEY_RIGHT:
				var amount: int = 1 if key.keycode == KEY_RIGHT else -1
				editable.set("width_cells", clampi(int(editable.get("width_cells")) + amount, 4, 32))
