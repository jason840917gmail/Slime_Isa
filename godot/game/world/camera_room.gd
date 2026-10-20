@tool
extends Node2D
class_name CameraRoom
## A camera room (docs/godot/PROLOGUE.md "Camera rooms"): a rect of a world, from this node's
## position, `size` world units across. While the slime stands in it the world camera
## (game/world/world_camera.gd) keeps the view inside it instead of the whole world, and walking into
## another room slides the view there, as a Zelda screen scroll inside one world. The prologue's
## Wellspring and glade are one screen each (1024 x 896, the play area above the HUD console), so
## neither sees the other or the West village's town that shares chunk B4 with them (question 112).
## A room may be smaller than a screen (the Lair's store is 448 x 448): the camera grows it about its
## middle to the view (world_camera.gd `fit_to_view`), so the view shows a little of what lies
## around it. The editor's handles (addons/camera_room_handles) keep it at least one 64-unit cell.
## Its outline, `rect()` and `contains()` all follow the node's whole transform (a turned or scaled
## room too). In the editor it draws its outline and name; in the game it draws nothing.
##
## Owner: world builder.

## Every room joins this group (the camera looks rooms up by it).
const GROUP := &"camera_room"
## The play area of one screen (16 x 14 tiles of 64 units).
const SCREEN := Vector2(1024, 896)
## The most outline points the room mask can cut (game/dungeon/room_mask.gd `MAX_POINTS`).
const MAX_POINTS := 64
const OUTLINE := Color(0.45, 0.85, 1.0, 0.8)
const OUTLINE_WIDTH := 4.0

## Optional simple room outline in local coordinates, up to MAX_POINTS points (more: a warning, and
## the room mask cuts only the first MAX_POINTS); empty: the size rectangle.
@export var outline: PackedVector2Array = PackedVector2Array():
	set(value):
		outline = value
		queue_redraw()
		update_configuration_warnings()

## The room's size in local units (any size from one 64-unit cell; a screen is SCREEN).
@export var size: Vector2 = SCREEN:
	set(value):
		size = value
		queue_redraw()


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if not Engine.is_editor_hint() and outline.size() > MAX_POINTS:
		push_warning("CameraRoom %s: %d outline points, the room mask cuts only the first %d" % [get_path(), outline.size(), MAX_POINTS])


## The room's points in local coordinates: its outline, or its size rectangle's corners.
func outline_local() -> PackedVector2Array:
	if outline.size() >= 3:
		return outline
	return PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])


## The room's bounds in world coordinates (its outline's, through the whole transform).
func rect() -> Rect2:
	var points := outline_global()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


## True when the world point `point` is in the room (its outline, or its size rectangle).
func contains(point: Vector2) -> bool:
	var local := to_local(point)
	if outline.size() < 3:
		return Rect2(Vector2.ZERO, size).has_point(local)
	return Geometry2D.is_point_in_polygon(local, outline)


## The room's points in world coordinates.
func outline_global() -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in outline_local():
		result.append(to_global(point))
	return result


func _get_configuration_warnings() -> PackedStringArray:
	if outline.size() > MAX_POINTS:
		return PackedStringArray(["The outline has %d points; the room mask cuts only the first %d." % [outline.size(), MAX_POINTS]])
	return PackedStringArray()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if outline.size() >= 3:
		var border := outline.duplicate()
		border.append(outline[0])
		draw_polyline(border, OUTLINE, OUTLINE_WIDTH)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), OUTLINE, false, OUTLINE_WIDTH)
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, Vector2(12, 28), "camera room: " + name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, OUTLINE)
