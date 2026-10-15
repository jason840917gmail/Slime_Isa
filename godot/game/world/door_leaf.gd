extends Node2D
## The swinging leaf of a real door (door.gd `kind` "door"; owner, 2026-10-14; docs/godot/CONVENTIONS.md
## "Doors"). Built in code over a door painted into a house: door.gd puts this node under the house's
## Sprite2D (so it draws with the house, in its y-sort slot) and gives it the door's rect in the
## sprite's local space. While `progress` is above 0 it draws a dark doorway over the rect, then the
## leaf on top: the house texture's own pixels under the rect (or a separate leaf picture), squashed
## horizontally toward the hinge as it swings into the house and shaded as it turns away from the
## light. At 0 it draws nothing over a painted door; a separate leaf picture is drawn closed too
## (the door it adds is always there).
##
## The rect may have an arched top (`arch`, local units): the doorway and the leaf follow that
## outline. A double door (`double`: the interior timber doors) is two leaves, each half of the rect,
## hinged on its outer edge. Owner: world objects.

## The doorway behind the open leaf.
const DARK := Color(0.06, 0.045, 0.035, 1.0)
## Points along the arch.
const ARCH_STEPS := 10
## The leaf's width share when fully open (cos of the swing).
const OPEN_SWING_RAD := 1.35
## The leaf's brightness when fully open.
const OPEN_SHADE := 0.62

## The doorway in this node's local space (the house sprite's).
var rect: Rect2 = Rect2()
## The arch height at the top of the rect (0 = square top).
var arch: float = 0.0
## True: the hinge is on the left edge.
var hinge_left: bool = true
## True: two leaves meeting in the middle, hinged on the left and right edges (`hinge_left` unused).
var double: bool = false
## The leaf's picture and its source rect in texture pixels (the house frame's region under the
## door, or the whole separate picture).
var texture: Texture2D
var source: Rect2 = Rect2()
## True for a separate leaf picture: drawn while closed too.
var draw_closed: bool = false
## 0 = closed, 1 = open.
var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	if progress <= 0.0 and not draw_closed:
		return
	if progress > 0.0:
		draw_colored_polygon(_outline(rect, 0.0, 1.0), Color(DARK, clampf(progress * 3.0, 0.0, 1.0)))
	if texture == null:
		return
	if double:
		_draw_leaf(_outline(rect, 0.0, 0.5), rect.position.x)
		_draw_leaf(_outline(rect, 0.5, 1.0), rect.end.x)
	else:
		_draw_leaf(_outline(rect, 0.0, 1.0), rect.position.x if hinge_left else rect.end.x)


## One leaf (`outline`, a part of the doorway), squashed toward `hinge_x` as it swings.
func _draw_leaf(outline: PackedVector2Array, hinge_x: float) -> void:
	var squash := cos(progress * OPEN_SWING_RAD)
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var tex_size := texture.get_size()
	for point: Vector2 in outline:
		points.append(Vector2(hinge_x + (point.x - hinge_x) * squash, point.y))
		var share := (point - rect.position) / rect.size
		uvs.append((source.position + share * source.size) / tex_size)
	var shade := lerpf(1.0, OPEN_SHADE, progress)
	var colours := PackedColorArray()
	colours.resize(points.size())
	colours.fill(Color(shade, shade, shade, 1.0))
	draw_polygon(points, colours, uvs, texture)


## The doorway outline between the shares `from` and `to` of its width: the arch from left to right
## over the top, then down to the threshold.
func _outline(area: Rect2, from: float, to: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var top := area.position.y
	var rise := clampf(arch, 0.0, area.size.y)
	out.append(Vector2(lerpf(area.position.x, area.end.x, from), area.end.y))
	for i in ARCH_STEPS + 1:
		var t := lerpf(from, to, float(i) / float(ARCH_STEPS))
		var x := lerpf(area.position.x, area.end.x, t)
		out.append(Vector2(x, top + rise * (1.0 - sin(PI * t))))
	out.append(Vector2(lerpf(area.position.x, area.end.x, to), area.end.y))
	return out
