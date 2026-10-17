extends Node2D
## A soft ellipse on the ground under something that leaves it (the bestiary's hopper and rook,
## docs/godot/BESTIARY.md): `size` is its half axes, `strength` (0..1) how dark it is. The owner
## grows and darkens it as a tell (the hopper's landing spot, the rook's swoop). Presentation only.
##
## Owner: enemy builder.

const COLOR := Color(0.03, 0.07, 0.05, 0.34)
const POINTS := 24

var size: Vector2 = Vector2(18.0, 7.0):
	set(value):
		size = value
		queue_redraw()
var strength: float = 1.0:
	set(value):
		strength = clampf(value, 0.0, 1.0)
		queue_redraw()
## Its colour at full strength (COLOR; the Shardback's slam zone is a darker red).
var tint: Color = COLOR:
	set(value):
		tint = value
		queue_redraw()


func _ready() -> void:
	z_index = -1
	z_as_relative = true


func _draw() -> void:
	if strength <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return
	var points := PackedVector2Array()
	for i in POINTS:
		var angle := TAU * float(i) / float(POINTS)
		points.append(Vector2(cos(angle) * size.x, sin(angle) * size.y))
	draw_colored_polygon(points, Color(tint, tint.a * strength))
