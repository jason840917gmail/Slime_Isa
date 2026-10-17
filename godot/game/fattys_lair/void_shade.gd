@tool
extends Node2D
## A dark shade over a world's voids (Fatty's Lair, docs/godot/DUNGEONS.md "Fatty's Lair (built)"):
## the voids are deep holes on the elevation layer, and this darkens their floors and lower walls a
## little more, so a void reads as bottomless beside the dark floors of a cave. `rects` are world
## rectangles (tools/build_fattys_lair.gd writes one per run of void cells); each is drawn as a dark
## fill a little inset from its edges. Presentation only; it never collides.
##
## Owner: dungeons (Fatty's Lair).

const COLOR := Color(0.01, 0.01, 0.03, 0.55)
const INSET := 6.0

@export var rects: Array[Rect2] = []:
	set(value):
		rects = value
		queue_redraw()


func _ready() -> void:
	z_index = -1


func _draw() -> void:
	for rect in rects:
		draw_rect(rect.grow(-INSET), COLOR, true)
