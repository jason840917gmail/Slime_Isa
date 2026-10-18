@tool
extends Node2D
class_name CameraRoom
## A camera room (docs/godot/PROLOGUE.md "Camera rooms"): a rect of a world, from this node's
## position, `size` world units across. While the slime stands in it the world camera
## (game/world/world_camera.gd) keeps the view inside it instead of the whole world, and walking into
## another room slides the view there, as a Zelda screen scroll inside one world. The prologue's
## Wellspring and glade are one screen each (1024 x 896, the play area above the HUD console), so
## neither sees the other or the West village's town that shares chunk B4 with them (question 112).
## A room smaller than the view pins the view's top-left corner to it; keep rooms at least a screen.
## In the editor it draws its outline and name; in the game it draws nothing.
##
## Owner: world builder.

## Every room joins this group (the camera looks rooms up by it).
const GROUP := &"camera_room"
## The play area of one screen (16 x 14 tiles of 64 units).
const SCREEN := Vector2(1024, 896)
const OUTLINE := Color(0.45, 0.85, 1.0, 0.8)
const OUTLINE_WIDTH := 4.0

## Optional simple room outline in local coordinates, up to 64 vertices (empty: size rectangle).
@export var outline: PackedVector2Array = PackedVector2Array():
	set(value):
		outline = value
		queue_redraw()

## The room's size in world units (at least SCREEN).
@export var size: Vector2 = SCREEN:
	set(value):
		size = value
		queue_redraw()


func _enter_tree() -> void:
	add_to_group(GROUP)


## The room in world coordinates.
func rect() -> Rect2:
	if outline.size() < 3:
		return Rect2(global_position, size)
	var bounds := Rect2(global_position + outline[0], Vector2.ZERO)
	for point: Vector2 in outline:
		bounds = bounds.expand(global_position + point)
	return bounds


func contains(point: Vector2) -> bool:
	return rect().has_point(point) if outline.size() < 3 else Geometry2D.is_point_in_polygon(to_local(point), outline)


func outline_global() -> PackedVector2Array:
	var result := PackedVector2Array()
	var polygon := outline if outline.size() >= 3 else PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	for point: Vector2 in polygon:
		result.append(to_global(point))
	return result


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
