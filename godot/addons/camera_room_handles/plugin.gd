@tool
extends EditorPlugin
## Handles for camera rooms (game/world/camera_room.gd) in the 2D view (docs/godot/DUNGEON_ROOMS.md
## "Camera rooms in the editor"). With a CameraRoom selected:
## - without an `outline`: a dot on each corner of its `size` rectangle; dragging the top-left one
##   moves the node, the others resize it (the opposite corner stays put);
## - with an `outline`: a dot on each point; drag to move it, double-click an edge to add a point
##   there, right-click a point to remove it (at least three stay).
## Moves snap to the 64-unit grid; hold Alt for free moves. Every drag is one undo step.
##
## Owner: world builder.

const CameraRoom := preload("res://game/world/camera_room.gd")
const GRID := 64.0
const HANDLE_RADIUS := 7.0
const PICK_RADIUS := 12.0
const EDGE_PICK := 10.0
const COLOR := Color(0.35, 0.85, 1.0)
const COLOR_HOT := Color(1.0, 0.8, 0.25)

var _room: Node2D
var _dragging := -1
var _hover := -1
var _start_outline := PackedVector2Array()
var _start_size := Vector2.ZERO
var _start_position := Vector2.ZERO


func _handles(object: Object) -> bool:
	return object is Node2D and (object as Node).get_script() == CameraRoom


func _edit(object: Object) -> void:
	_room = object as Node2D
	_dragging = -1
	update_overlays()


func _make_visible(visible: bool) -> void:
	if not visible:
		_room = null
	update_overlays()


## The handles' points in the room's local space (corners of the size rect, or the outline).
func _points() -> PackedVector2Array:
	var outline: PackedVector2Array = _room.get(&"outline")
	if outline.size() >= 3:
		return outline
	var size: Vector2 = _room.get(&"size")
	return PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)])


func _uses_outline() -> bool:
	return (_room.get(&"outline") as PackedVector2Array).size() >= 3


func _to_screen(local: Vector2) -> Vector2:
	return _room.get_viewport_transform() * (_room.get_global_transform() * local)


func _to_local(screen: Vector2) -> Vector2:
	return _room.get_global_transform().affine_inverse() * (_room.get_viewport_transform().affine_inverse() * screen)


func _snap(local: Vector2) -> Vector2:
	if Input.is_key_pressed(KEY_ALT):
		return local.round()
	return (local / GRID).round() * GRID


func _pick(screen: Vector2) -> int:
	var points := _points()
	for i in points.size():
		if _to_screen(points[i]).distance_to(screen) <= PICK_RADIUS:
			return i
	return -1


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if _room == null or not is_instance_valid(_room) or not _room.is_inside_tree():
		return
	var points := _points()
	for i in points.size():
		var a := _to_screen(points[i])
		var b := _to_screen(points[(i + 1) % points.size()])
		overlay.draw_line(a, b, COLOR, 2.0)
	for i in points.size():
		var at := _to_screen(points[i])
		var hot := i == _hover or i == _dragging
		overlay.draw_circle(at, HANDLE_RADIUS + 2.0, Color(0, 0, 0, 0.6))
		overlay.draw_circle(at, HANDLE_RADIUS, COLOR_HOT if hot else COLOR)
	if _dragging >= 0:
		var local := points[_dragging]
		var font := ThemeDB.fallback_font
		overlay.draw_string(font, _to_screen(local) + Vector2(12, -12), "%d, %d" % [int(local.x), int(local.y)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_HOT)


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _room == null or not is_instance_valid(_room) or not _room.is_inside_tree():
		return false
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging >= 0:
			_drag_to(_snap(_to_local(motion.position)))
			update_overlays()
			return true
		var hover := _pick(motion.position)
		if hover != _hover:
			_hover = hover
			update_overlays()
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed and button.double_click and _uses_outline():
			return _insert_point(button.position)
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			var hit := _pick(button.position)
			if hit < 0:
				return false
			_dragging = hit
			_start_outline = (_room.get(&"outline") as PackedVector2Array).duplicate()
			_start_size = _room.get(&"size")
			_start_position = _room.position
			return true
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed and _dragging >= 0:
			_commit("Move camera room point")
			_dragging = -1
			update_overlays()
			return true
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed and _uses_outline():
			var hit := _pick(button.position)
			if hit >= 0 and _points().size() > 3:
				_start_outline = (_room.get(&"outline") as PackedVector2Array).duplicate()
				_start_size = _room.get(&"size")
				_start_position = _room.position
				var outline := _start_outline.duplicate()
				outline.remove_at(hit)
				_room.set(&"outline", outline)
				_commit("Remove camera room point")
				update_overlays()
				return true
	return false


func _drag_to(local: Vector2) -> void:
	if _uses_outline():
		var outline := _start_outline.duplicate()
		outline[_dragging] = local
		_room.set(&"outline", outline)
		return
	# The size rectangle: the dragged corner moves, the opposite one stays.
	var corners := PackedVector2Array([Vector2.ZERO, Vector2(_start_size.x, 0.0), _start_size, Vector2(0.0, _start_size.y)])
	var fixed := corners[(_dragging + 2) % 4]
	var moved := local
	var low := Vector2(minf(fixed.x, moved.x), minf(fixed.y, moved.y))
	var high := Vector2(maxf(fixed.x, moved.x), maxf(fixed.y, moved.y))
	var size := (high - low).max(Vector2(GRID, GRID))
	_room.position = _start_position + low.rotated(_room.rotation) * _room.scale
	_room.set(&"size", size)


func _insert_point(screen: Vector2) -> bool:
	var points := _points()
	for i in points.size():
		var a := _to_screen(points[i])
		var b := _to_screen(points[(i + 1) % points.size()])
		var near := Geometry2D.get_closest_point_to_segment(screen, a, b)
		if near.distance_to(screen) <= EDGE_PICK:
			_start_outline = points.duplicate()
			_start_size = _room.get(&"size")
			_start_position = _room.position
			var outline := points.duplicate()
			outline.insert(i + 1, _snap(_to_local(near)))
			_room.set(&"outline", outline)
			_commit("Add camera room point")
			update_overlays()
			return true
	return false


## One undo step from the values at the drag's start to the values now.
func _commit(action: String) -> void:
	var undo := get_undo_redo()
	undo.create_action(action)
	undo.add_do_property(_room, &"outline", _room.get(&"outline"))
	undo.add_do_property(_room, &"size", _room.get(&"size"))
	undo.add_do_property(_room, &"position", _room.position)
	undo.add_undo_property(_room, &"outline", _start_outline)
	undo.add_undo_property(_room, &"size", _start_size)
	undo.add_undo_property(_room, &"position", _start_position)
	undo.commit_action(false)
