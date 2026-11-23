@tool
extends RefCounted
## What the door area handles (plugin.gd) know about a door's trigger area, with nothing of the
## editor in it (the tests and the render tools use it too): which node carries the area, where it
## is in the world, what a dragged handle makes of it, and how it is drawn
## (docs/godot/CONVENTIONS.md "A door's area in the editor").
##
## The area is the door's `trigger_rect`: a rectangle in world units measured from the door node's
## place (game/scripts/door.gd: the DoorScript's parent; a stair door, game/scripts/stair_hatch.gd:
## the node itself), never turned or scaled with it. A door with a `trigger_shape` or a `walk_area`
## is set off by those collision shapes instead: they are outlined, and edited as any shape.
##
## Owner: world builder.

const Door := preload("res://game/scripts/door.gd")
const StairHatch := preload("res://game/scripts/stair_hatch.gd")

## The handles: the four corners, clockwise from the top-left one, then the grip under the area
## (moves it). The grip hangs under the bottom edge, clear of the door node's own point: most areas
## are centred on it, and a handle there would take the drags meant for the door.
const HANDLE_MOVE := 4
## How far under the area the grip hangs (screen pixels at display scale 1).
const GRIP_DROP := 18.0
## A dragged area is never smaller than this (world units).
const MIN_SIZE := 4.0
const COLOR := Color(1.0, 0.6, 0.15)
## A door that never travels (no target: an arrival point only).
const COLOR_IDLE := Color(0.72, 0.72, 0.72)
const COLOR_HOT := Color(1.0, 0.95, 0.4)
const FILL_ALPHA := 0.16
const HANDLE_RADIUS := 5.0
const FONT_SIZE := 12
## An unselected door's name is written only when its area is at least this wide on screen.
const LABEL_MIN_WIDTH := 20.0


## The node whose `trigger_rect` selecting `node` edits: `node` itself (a door's script node, a
## stair door), else its first DoorScript child (the door's Node2D, what a click in the 2D view
## selects). Null when `node` is no door.
static func door_of(node: Node) -> Node:
	if node == null:
		return null
	if is_a(node, Door) or is_a(node, StairHatch):
		return node
	if node is Node2D:
		for child: Node in node.get_children():
			if is_a(child, Door):
				return child
	return null


## True when `node`'s script is `script` or extends it.
static func is_a(node: Node, script: Script) -> bool:
	var own := node.get_script() as Script
	while own != null:
		if own == script:
			return true
		own = own.get_base_script()
	return false


## The node the area is measured from: a door's parent, a stair door itself.
static func anchor_of(door: Node) -> Node2D:
	if is_a(door, Door):
		return door.get_parent() as Node2D
	return door as Node2D


## True when the door's `trigger_rect` is what sets it off (no `trigger_shape`, no `walk_area`).
static func uses_rect(door: Node) -> bool:
	return shape_nodes(door).is_empty()


## The collision shapes that set the door off instead of its rect: its `trigger_shape`, else its
## `walk_area`'s shapes. Empty for a door set off by its `trigger_rect`.
static func shape_nodes(door: Node) -> Array[CollisionShape2D]:
	var shapes: Array[CollisionShape2D] = []
	if not is_a(door, Door):
		return shapes
	var shape := _node_of(door, &"trigger_shape") as CollisionShape2D
	if shape != null:
		shapes.append(shape)
		return shapes
	var area := _node_of(door, &"walk_area")
	if area != null:
		for child: Node in area.get_children():
			if child is CollisionShape2D:
				shapes.append(child as CollisionShape2D)
	return shapes


## The node an exported node property points at (in the editor it is held as a path).
static func _node_of(door: Node, property: StringName) -> Node:
	var value: Variant = door.get(property)
	if value is Node:
		return value as Node
	if value is NodePath and not (value as NodePath).is_empty():
		return door.get_node_or_null(value as NodePath)
	return null


static func rect_of(door: Node) -> Rect2:
	var value: Variant = door.get(&"trigger_rect")
	return value as Rect2 if value is Rect2 else Rect2()


## The door's area in the world (door.gd `trigger_global`).
static func world_rect(door: Node) -> Rect2:
	var anchor := anchor_of(door)
	var rect := rect_of(door)
	return Rect2((anchor.global_position if anchor != null else Vector2.ZERO) + rect.position, rect.size)


## The door's id, as its crossing knows it.
static func id_of(door: Node) -> String:
	return str(door.get(&"door_id" if is_a(door, Door) else &"hatch_id"))


## False for a door that never travels: no target, an arrival point only (door.gd).
static func travels(door: Node) -> bool:
	return not is_a(door, Door) or not str(door.get(&"target_area_id")).is_empty()


## The way the slime pushes to go through a door with a side (door.gd `side`); ZERO without one.
static func push_direction(door: Node) -> Vector2:
	if not is_a(door, Door):
		return Vector2.ZERO
	match str(door.get(&"side")):
		"north":
			return Vector2.UP
		"south":
			return Vector2.DOWN
		"east":
			return Vector2.RIGHT
		"west":
			return Vector2.LEFT
	return Vector2.ZERO


## The corners of `rect`, clockwise from the top-left one.
static func corners(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)])


## The handles of an area drawn at `screen` (canvas pixels): its corners, then the grip under it.
static func screen_handles(screen: Rect2, ui_scale: float = 1.0) -> PackedVector2Array:
	var points := corners(screen)
	points.append(Vector2(screen.get_center().x, screen.end.y + GRIP_DROP * ui_scale))
	return points


## The door's area on a canvas that `to_screen` takes world points to.
static func screen_rect(door: Node, to_screen: Transform2D) -> Rect2:
	var world := world_rect(door)
	return Rect2(to_screen * world.position, world.size * to_screen.get_scale()).abs()


## `start` after its handle `handle` was dragged by `by` (world units), its numbers on a grid of
## `step`. The grip moves the area; a corner resizes it, the opposite corner staying put and the
## area never smaller than `MIN_SIZE` or turned inside out.
static func drag(start: Rect2, handle: int, by: Vector2, step: float) -> Rect2:
	if handle == HANDLE_MOVE:
		return Rect2(_snap(start.position + by, step), start.size)
	var points := corners(start)
	var to := _snap(points[handle] + by, step)
	var fixed := points[(handle + 2) % 4]
	var smallest := maxf(MIN_SIZE, step)
	var left := handle == 0 or handle == 3
	var top := handle == 0 or handle == 1
	var x0 := minf(to.x, fixed.x - smallest) if left else fixed.x
	var x1 := fixed.x if left else maxf(to.x, fixed.x + smallest)
	var y0 := minf(to.y, fixed.y - smallest) if top else fixed.y
	var y1 := fixed.y if top else maxf(to.y, fixed.y + smallest)
	return Rect2(x0, y0, x1 - x0, y1 - y0)


static func _snap(point: Vector2, step: float) -> Vector2:
	return (point / step).round() * step if step > 0.0 else point


## Draws the door's area on `canvas`: `to_screen` takes world points to the canvas (in the editor
## the 2D view's transform). The rect filled and outlined, the door's id over it, an arrow for the
## way the slime pushes; selected, its handles (`hot` drawn lit) and its numbers under it. A door set
## off by collision shapes gets those outlined instead. `ui_scale` sizes the lines, the handles and
## the text (the editor's display scale).
static func draw(canvas: CanvasItem, to_screen: Transform2D, door: Node, selected: bool, hot: int, font: Font,
		ui_scale: float = 1.0) -> void:
	var color := COLOR if travels(door) else COLOR_IDLE
	var width := (2.0 if selected else 1.5) * ui_scale
	var font_size := roundi(FONT_SIZE * ui_scale)
	var gap := 6.0 * ui_scale
	var shapes := shape_nodes(door)
	if not shapes.is_empty():
		var top := Vector2(INF, INF)
		for shape_node in shapes:
			if shape_node.shape == null:
				continue
			var local := shape_node.shape.get_rect()
			var outline := PackedVector2Array()
			for corner: Vector2 in corners(local):
				outline.append(to_screen * (shape_node.global_transform * corner))
			outline.append(outline[0])
			canvas.draw_polyline(outline, color, width)
			for point in outline:
				if point.y < top.y:
					top = point
		if selected and top.is_finite():
			_text(canvas, font, top + Vector2(0.0, -gap), "%s: set off by its collision shape" % id_of(door), font_size, color)
		return
	var screen := screen_rect(door, to_screen)
	if screen.has_area():
		canvas.draw_rect(screen, Color(color, FILL_ALPHA))
		canvas.draw_rect(screen, color, false, width)
	var push := push_direction(door)
	if push != Vector2.ZERO and screen.has_area():
		_arrow(canvas, screen.get_center(), push, clampf(minf(screen.size.x, screen.size.y) * 0.3, 5.0 * ui_scale, 16.0 * ui_scale),
			color, 2.0 * ui_scale)
	if selected or screen.size.x >= LABEL_MIN_WIDTH * ui_scale:
		var label := id_of(door) if travels(door) else "%s (arrival only)" % id_of(door)
		_text(canvas, font, screen.position + Vector2(0.0, -gap), label, font_size, color)
	if not selected:
		return
	var rect := rect_of(door)
	var points := screen_handles(screen, ui_scale)
	var radius := HANDLE_RADIUS * ui_scale
	var rim := 1.5 * ui_scale
	_text(canvas, font, Vector2(screen.position.x, points[HANDLE_MOVE].y + radius + rim + font_size + gap * 0.5),
		"%s x %s at (%s, %s)" % [_number(rect.size.x), _number(rect.size.y), _number(rect.position.x), _number(rect.position.y)],
		font_size, COLOR_HOT if hot >= 0 else color)
	for i in points.size():
		var fill := COLOR_HOT if i == hot else color
		if i == HANDLE_MOVE:
			# The grip: a square on a stem, with a cross (it moves the area).
			var at := points[i]
			var box := Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
			canvas.draw_line(Vector2(at.x, screen.end.y), at, color, width)
			canvas.draw_rect(box.grow(rim), Color(0.0, 0.0, 0.0, 0.7))
			canvas.draw_rect(box, fill)
			var arm := radius * 0.6
			canvas.draw_line(at - Vector2(arm, 0.0), at + Vector2(arm, 0.0), Color(0.0, 0.0, 0.0, 0.8), rim)
			canvas.draw_line(at - Vector2(0.0, arm), at + Vector2(0.0, arm), Color(0.0, 0.0, 0.0, 0.8), rim)
		else:
			canvas.draw_circle(points[i], radius + rim, Color(0.0, 0.0, 0.0, 0.7))
			canvas.draw_circle(points[i], radius, fill)


static func _arrow(canvas: CanvasItem, middle: Vector2, direction: Vector2, length: float, color: Color, width: float) -> void:
	var tip := middle + direction * length
	var back := middle - direction * length
	var side := direction.orthogonal() * length * 0.5
	canvas.draw_line(back, tip, color, width)
	canvas.draw_line(tip, tip - direction * length * 0.7 + side, color, width)
	canvas.draw_line(tip, tip - direction * length * 0.7 - side, color, width)


static func _text(canvas: CanvasItem, font: Font, at: Vector2, text: String, size: int, color: Color) -> void:
	if font == null:
		return
	canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(2, size / 3), Color(0.0, 0.0, 0.0, 0.75))
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## A world number as the Inspector shows it: whole when it is whole.
static func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
