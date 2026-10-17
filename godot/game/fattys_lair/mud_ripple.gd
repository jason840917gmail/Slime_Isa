extends Node2D
## The mud ripple of Fatty One Eye's second landing in his phase two (game/scripts/fatty.gd
## `configure_phase_two`; docs/godot/DUNGEONS.md "Fatty's Lair (built)"; the design's open point 4):
## a low ring of mud with a raised crest spreading over the floor from where he landed. Fatty moves
## it (`set_radius`) and hits the slime as the crest passes it; this node only draws: a ground ellipse
## (flattened like every ground telegraph), dark mud with a pale crest, fading as it spreads.
## Presentation only.
##
## Owner: dungeons (Fatty's Lair).

const MUD := Color(0.36, 0.24, 0.14, 0.75)
const CREST := Color(0.78, 0.62, 0.42, 0.9)
const SQUASH_Y := 0.5
const SEGMENTS := 72

var radius := 0.0
var width := 26.0
var max_radius := 520.0


func _ready() -> void:
	z_index = -1


func set_radius(value: float) -> void:
	radius = value
	queue_redraw()


func _draw() -> void:
	if radius <= 0.0:
		return
	var fade := clampf(1.0 - radius / maxf(1.0, max_radius), 0.15, 1.0)
	var outer := _ring(radius + width * 0.5)
	var inner := _ring(maxf(0.0, radius - width * 0.5))
	draw_polyline(outer, Color(MUD, MUD.a * fade), width * 0.6 * SQUASH_Y + 2.0, true)
	draw_polyline(_ring(radius), Color(CREST, CREST.a * fade), 3.0, true)
	draw_polyline(inner, Color(MUD, MUD.a * fade * 0.6), 2.0, true)


func _ring(r: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in SEGMENTS + 1:
		var angle := TAU * float(i) / float(SEGMENTS)
		points.append(Vector2(cos(angle) * r, sin(angle) * r * SQUASH_Y))
	return points
