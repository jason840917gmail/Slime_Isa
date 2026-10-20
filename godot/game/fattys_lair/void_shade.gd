@tool
extends Node2D
## A dark shade over a world's voids (Fatty's Lair, docs/godot/DUNGEONS.md "Fatty's Lair (built)"):
## the voids are deep holes on the elevation layer, and this darkens their floors and lower walls a
## little more, so a void reads as bottomless beside the dark floors of a cave. With `from_paint` on
## (2026-10-19) it shades every cell the world's `elevation` layer paints below level 0, so it follows
## the painted holes; else `rects`, world rectangles set in the Inspector (one per run of void cells,
## as the retired builder first wrote them). Each is drawn as a dark fill a little inset from its
## edges. Presentation only; it never collides.
##
## Owner: dungeons (Fatty's Lair).

const Elevation := preload("res://game/world/elevation/elevation.gd")

const COLOR := Color(0.01, 0.01, 0.03, 0.55)
const INSET := 6.0
const CELL := 64.0

@export var rects: Array[Rect2] = []:
	set(value):
		rects = value
		queue_redraw()
## Shade the holes the world's `elevation` layer paints (below level 0) instead of `rects`.
@export var from_paint: bool = false:
	set(value):
		from_paint = value
		queue_redraw()

var _painted: Array[Rect2] = []


func _ready() -> void:
	z_index = -1
	if from_paint:
		_read_paint.call_deferred()


func _read_paint() -> void:
	_painted.clear()
	var ground := get_parent().get_node_or_null(^"ground") as TileMapLayer if get_parent() != null else null
	if ground == null:
		return
	var levels := Elevation.painted_levels(ground)
	# one rect per run of hole cells along a row
	var rows := {}
	for cell: Vector2i in levels:
		if int(levels[cell]) < 0:
			(rows.get_or_add(cell.y, []) as Array).append(cell.x)
	for y: int in rows:
		var xs: Array = rows[y]
		xs.sort()
		var start: int = xs[0]
		var last: int = xs[0]
		for i in range(1, xs.size() + 1):
			if i < xs.size() and int(xs[i]) == last + 1:
				last = xs[i]
				continue
			_painted.append(Rect2(Vector2(start, y) * CELL, Vector2(last - start + 1, 1) * CELL))
			if i < xs.size():
				start = xs[i]
				last = xs[i]
	queue_redraw()


func _draw() -> void:
	if from_paint and _painted.is_empty() and Engine.is_editor_hint():
		_read_paint()
	for rect in (_painted if from_paint else rects):
		draw_rect(rect.grow(-INSET), COLOR, true)
