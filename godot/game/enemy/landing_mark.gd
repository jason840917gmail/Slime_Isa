extends "res://game/enemy/ground_shadow.gd"
## The Bone Leaper's landing mark (docs/godot/BESTIARY.md "Bone Leaper"): the ground shadow where it
## will land, with a dark ring round it, so the tell still shows round the slime standing on it.
## `size` and `strength` as the ground shadow's. Presentation only.
##
## Owner: enemy builder.

const RING := Color(0.24, 0.06, 0.02, 0.85)
const RING_PX := 2.0
const FILL_SHARE := 1.4


func _draw() -> void:
	if strength <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return
	var points := PackedVector2Array()
	for i in POINTS + 1:
		var angle := TAU * float(i) / float(POINTS)
		points.append(Vector2(cos(angle) * size.x, sin(angle) * size.y))
	var fill := points.duplicate()
	fill.remove_at(fill.size() - 1)
	draw_colored_polygon(fill, Color(COLOR, minf(1.0, COLOR.a * FILL_SHARE) * strength))
	draw_polyline(points, Color(RING, RING.a * strength), RING_PX, true)
