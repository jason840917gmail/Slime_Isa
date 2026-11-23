@tool
extends EditorPlugin
## Doors' trigger areas in the 2D view (docs/godot/CONVENTIONS.md "A door's area in the editor").
## A door is a bare Node2D with a DoorScript child (game/scripts/door.gd), and the area that sets it
## off is a number on that child (`trigger_rect`), so without this the editor shows a point.
## - Every door of the open scene (the stair doors too, game/scripts/stair_hatch.gd) has its area
##   drawn: orange, its id over it, an arrow for the way the slime pushes into a door with a side;
##   grey for a door that never travels (no target: an arrival point only).
## - With a door selected (its Node2D, or its script node): a dot on each corner of the area and a
##   square grip hanging under it. Drag a corner to resize it (the opposite corner stays put), the
##   grip to move it (the door's own point stays free to drag the door); its numbers are written
##   under it and are the script node's `trigger_rect` in the Inspector.
## Drags snap the numbers to `SNAP` units; hold Alt for single units. A drag is one undo step;
## Escape during a drag puts the area back, and a release outside the 2D view ends the drag there.
## A door set off by a `trigger_shape` or a `walk_area` has those shapes outlined, without handles:
## they are edited as any collision shape.
##
## Owner: world builder.

const DoorArea := preload("res://addons/door_area_handles/door_area.gd")
const SNAP := 4.0
const SNAP_FINE := 1.0
const PICK_RADIUS := 10.0
## The open scene's doors are looked for again this often (ms), and when the scene changes.
const RESCAN_MS := 1000

## The selected door: the node carrying `trigger_rect` (DoorArea.door_of the selection).
var _door: Node
var _dragging := -1
var _hover := -1
var _start_rect := Rect2()
## Where the drag began, in the world.
var _grab := Vector2.ZERO
var _doors: Array[Node] = []
var _scanned_root: Node
var _scanned_at := 0


func _enter_tree() -> void:
	# The areas are drawn for every door, whatever is selected.
	set_force_draw_over_forwarding_enabled()
	# Undo, redo and the Inspector change the area behind the handles' back: redraw them.
	get_undo_redo().version_changed.connect(update_overlays)
	scene_changed.connect(_on_scene_changed)


func _exit_tree() -> void:
	if get_undo_redo().version_changed.is_connected(update_overlays):
		get_undo_redo().version_changed.disconnect(update_overlays)
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)


func _on_scene_changed(_root: Node) -> void:
	_scanned_root = null
	update_overlays()


func _handles(object: Object) -> bool:
	return object is Node and DoorArea.door_of(object as Node) != null


func _edit(object: Object) -> void:
	_door = DoorArea.door_of(object as Node) if object is Node else null
	_dragging = -1
	_hover = -1
	update_overlays()


func _make_visible(visible: bool) -> void:
	if not visible:
		_door = null
		_dragging = -1
	update_overlays()


## The selected door when its area can be dragged (a rect, in the tree, with a node to measure from).
func _editable_door() -> Node:
	if _door == null or not is_instance_valid(_door) or not _door.is_inside_tree():
		return null
	if DoorArea.anchor_of(_door) == null or not DoorArea.uses_rect(_door):
		return null
	return _door


## Every door under the open scene's root, the ones inside instanced scenes too.
func _scan(root: Node) -> void:
	_doors.clear()
	_scanned_root = root
	_scanned_at = Time.get_ticks_msec()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.get_script() != null and DoorArea.door_of(node) == node:
			_doors.append(node)
		stack.append_array(node.get_children())


func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	if root != _scanned_root or Time.get_ticks_msec() - _scanned_at > RESCAN_MS:
		_scan(root)
	var font := overlay.get_theme_default_font()
	var view := Rect2(Vector2.ZERO, overlay.size).grow(64.0)
	var selected := _editable_door() if _door != null and is_instance_valid(_door) else null
	for door in _doors:
		if not is_instance_valid(door) or not door.is_inside_tree() or door == _door:
			continue
		_draw_door(overlay, door, view, false, font)
	# The selected door last, over its neighbours.
	if _door != null and is_instance_valid(_door) and _door.is_inside_tree():
		_draw_door(overlay, _door, view, true, font, (_dragging if _dragging >= 0 else _hover) if selected != null else -1)


func _draw_door(overlay: Control, door: Node, view: Rect2, selected: bool, font: Font, hot: int = -1) -> void:
	var anchor := DoorArea.anchor_of(door)
	if anchor == null or not anchor.is_visible_in_tree():
		return
	var to_screen := anchor.get_viewport_transform()
	if not selected and DoorArea.uses_rect(door) and not view.intersects(DoorArea.screen_rect(door, to_screen), true):
		return
	DoorArea.draw(overlay, to_screen, door, selected, hot, font, EditorInterface.get_editor_scale())


## The handles of the selected door's area on screen.
func _screen_handles(door: Node) -> PackedVector2Array:
	var to_screen := DoorArea.anchor_of(door).get_viewport_transform()
	return DoorArea.screen_handles(DoorArea.screen_rect(door, to_screen), EditorInterface.get_editor_scale())


## The handle under `screen`: the nearest within reach, -1 for none.
func _pick(door: Node, screen: Vector2) -> int:
	var points := _screen_handles(door)
	var best := -1
	var nearest := PICK_RADIUS * EditorInterface.get_editor_scale()
	for i in points.size():
		var distance := points[i].distance_to(screen)
		if distance <= nearest:
			nearest = distance
			best = i
	return best


func _to_world(door: Node, screen: Vector2) -> Vector2:
	return DoorArea.anchor_of(door).get_viewport_transform().affine_inverse() * screen


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	var door := _editable_door()
	if door == null:
		_dragging = -1
		return false
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE and _dragging >= 0:
			_cancel_drag(door)
			return true
		return false
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging >= 0:
			if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
				# Released outside the 2D view (its release never came here): the drag ends where it was.
				_end_drag(door)
				return true
			var step := SNAP_FINE if Input.is_key_pressed(KEY_ALT) else SNAP
			door.set(&"trigger_rect", DoorArea.drag(_start_rect, _dragging, _to_world(door, motion.position) - _grab, step))
			update_overlays()
			return true
		var hover := _pick(door, motion.position)
		if hover != _hover:
			_hover = hover
			update_overlays()
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return false
		if button.pressed:
			var hit := _pick(door, button.position)
			if hit < 0:
				return false
			_dragging = hit
			_start_rect = DoorArea.rect_of(door)
			_grab = _to_world(door, button.position)
			update_overlays()
			return true
		if _dragging >= 0:
			_end_drag(door)
			return true
	return false


func _end_drag(door: Node) -> void:
	_commit(door)
	_dragging = -1
	update_overlays()


## Escape during a drag: the area as it was when the drag began, no undo step.
func _cancel_drag(door: Node) -> void:
	door.set(&"trigger_rect", _start_rect)
	_dragging = -1
	update_overlays()


## One undo step from the area at the drag's start to the area now; none when nothing changed.
func _commit(door: Node) -> void:
	var rect := DoorArea.rect_of(door)
	if rect == _start_rect:
		return
	var undo := get_undo_redo()
	undo.create_action("Change door area")
	undo.add_do_property(door, &"trigger_rect", rect)
	undo.add_undo_property(door, &"trigger_rect", _start_rect)
	undo.commit_action(false)
