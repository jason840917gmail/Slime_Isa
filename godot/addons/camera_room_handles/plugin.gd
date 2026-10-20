@tool
extends EditorPlugin
## Handles for camera rooms (game/world/camera_room.gd) in the 2D view (docs/godot/DUNGEON_ROOMS.md
## "Camera rooms in the editor"). With a CameraRoom selected:
## - without an `outline`: a dot on each corner of its `size` rectangle; dragging the top-left one
##   moves the node, the others resize it (the opposite corner stays put; at least one 64-unit cell);
## - with an `outline`: a dot on each point; drag to move it, double-click an edge (not a dot) to add
##   a point there (up to CameraRoom.MAX_POINTS), right-click a point to remove it (at least three
##   stay).
## Moves snap to the world's 64-unit grid (also for a room or a parent placed off the grid); hold Alt
## for free moves. Every drag that changes something is one undo step; Escape during a drag puts the
## room back, and a release outside the 2D view ends the drag where it was.
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
## The room's local and global transforms when the drag began (a top-left drag moves the room).
var _start_transform := Transform2D.IDENTITY
var _start_global := Transform2D.IDENTITY


func _enter_tree() -> void:
	# Undo and redo change the room behind the handles' back: redraw them.
	get_undo_redo().version_changed.connect(update_overlays)


func _exit_tree() -> void:
	if get_undo_redo().version_changed.is_connected(update_overlays):
		get_undo_redo().version_changed.disconnect(update_overlays)


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


## The screen point `screen` snapped on the world grid (Alt: to whole units), in the local space of
## a room whose global transform is `room_global`.
func _snapped_local(screen: Vector2, room_global: Transform2D) -> Vector2:
	return snapped_local(_room.get_viewport_transform().affine_inverse() * screen, room_global, Input.is_key_pressed(KEY_ALT))


## The world point `world` snapped on the world's 64-unit grid (`free`: to whole units), in the local
## space of a room whose global transform is `room_global` (so a room or a parent placed off the grid
## still gets its points on the world's grid).
static func snapped_local(world: Vector2, room_global: Transform2D, free: bool) -> Vector2:
	var snapped := world.round() if free else (world / GRID).round() * GRID
	return room_global.affine_inverse() * snapped


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
	if _dragging >= 0 and _dragging < points.size():
		var local := points[_dragging]
		var font := ThemeDB.fallback_font
		overlay.draw_string(font, _to_screen(local) + Vector2(12, -12), "%d, %d" % [int(local.x), int(local.y)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_HOT)


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _room == null or not is_instance_valid(_room) or not _room.is_inside_tree():
		return false
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE and _dragging >= 0:
			_cancel_drag()
			return true
		return false
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging >= 0:
			if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
				# Released outside the 2D view (its release never came here): the drag ends where it was.
				_end_drag()
				return true
			_drag_to(_snapped_local(motion.position, _start_global))
			update_overlays()
			return true
		var hover := _pick(motion.position)
		if hover != _hover:
			_hover = hover
			update_overlays()
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			var hit := _pick(button.position)
			if hit < 0:
				# A double-click on an edge adds a point (one on a dot drags it, as a click does).
				return _insert_point(button.position) if button.double_click and _uses_outline() else false
			_dragging = hit
			_remember_start()
			return true
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed and _dragging >= 0:
			_end_drag()
			return true
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed and _uses_outline():
			var hit := _pick(button.position)
			if hit >= 0 and _points().size() > 3:
				_remember_start()
				var outline := _start_outline.duplicate()
				outline.remove_at(hit)
				_room.set(&"outline", outline)
				_commit("Remove camera room point")
				update_overlays()
				return true
	return false


func _remember_start() -> void:
	_start_outline = (_room.get(&"outline") as PackedVector2Array).duplicate()
	_start_size = _room.get(&"size")
	_start_position = _room.position
	_start_transform = _room.transform
	_start_global = _room.get_global_transform()


func _end_drag() -> void:
	_commit("Move camera room point")
	_dragging = -1
	update_overlays()


## Escape during a drag: the room as it was when the drag began, no undo step.
func _cancel_drag() -> void:
	_room.set(&"outline", _start_outline)
	_room.set(&"size", _start_size)
	_room.position = _start_position
	_dragging = -1
	update_overlays()


## Moves the dragged point to `local` (in the room's space at the drag's start).
func _drag_to(local: Vector2) -> void:
	if _uses_outline():
		var outline := _start_outline.duplicate()
		outline[_dragging] = local
		_room.set(&"outline", outline)
		return
	var moved := corner_drag(_start_transform, _start_size, _dragging, local)
	_room.position = moved.position
	_room.set(&"size", moved.size)


## A size rectangle's corner `corner` (0 top-left, then clockwise) dragged to `local` (the room's
## space at the drag's start, `start` its transform in its parent, `start_size` its size): the
## opposite corner stays put. Returns the room's new position (in its parent) and size (one 64-unit
## cell at least).
static func corner_drag(start: Transform2D, start_size: Vector2, corner: int, local: Vector2) -> Rect2:
	var corners := PackedVector2Array([Vector2.ZERO, Vector2(start_size.x, 0.0), start_size, Vector2(0.0, start_size.y)])
	var fixed := corners[(corner + 2) % 4]
	var low := Vector2(minf(fixed.x, local.x), minf(fixed.y, local.y))
	var high := Vector2(maxf(fixed.x, local.x), maxf(fixed.y, local.y))
	# The new top-left corner, from local to the parent's space through the room's own basis.
	return Rect2(start.origin + start.basis_xform(low), (high - low).max(Vector2(GRID, GRID)))


func _insert_point(screen: Vector2) -> bool:
	var points := _points()
	for i in points.size():
		var a := _to_screen(points[i])
		var b := _to_screen(points[(i + 1) % points.size()])
		var near := Geometry2D.get_closest_point_to_segment(screen, a, b)
		if near.distance_to(screen) <= EDGE_PICK:
			if points.size() >= CameraRoom.MAX_POINTS:
				push_warning("Camera room handles: %s already has %d points, the most a room mask cuts" % [_room.name, points.size()])
				return true
			_remember_start()
			var outline := points.duplicate()
			outline.insert(i + 1, _snapped_local(near, _start_global))
			_room.set(&"outline", outline)
			_commit("Add camera room point")
			update_overlays()
			return true
	return false


## One undo step from the values at the drag's start to the values now; none when nothing changed.
func _commit(action: String) -> void:
	var outline: PackedVector2Array = _room.get(&"outline")
	var size: Vector2 = _room.get(&"size")
	if outline == _start_outline and size == _start_size and _room.position == _start_position:
		return
	var undo := get_undo_redo()
	undo.create_action(action)
	undo.add_do_property(_room, &"outline", outline)
	undo.add_do_property(_room, &"size", size)
	undo.add_do_property(_room, &"position", _room.position)
	undo.add_undo_property(_room, &"outline", _start_outline)
	undo.add_undo_property(_room, &"size", _start_size)
	undo.add_undo_property(_room, &"position", _start_position)
	undo.commit_action(false)
