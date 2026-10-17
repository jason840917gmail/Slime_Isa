extends Node2D
## The shadow of a mud clod about to fall from the roots over Fatty One Eye's arena
## (game/fattys_lair/lair_director.gd; docs/godot/DUNGEONS.md "Fatty's Lair (built)"): a dark ground
## ellipse that grows over `grow_ms` of real time (a telegraph, presentation only; the director times
## the fall on the gameplay clock).
##
## Owner: dungeons (Fatty's Lair).

const COLOR := Color(0.03, 0.02, 0.01, 0.5)
const RING := Color(0.55, 0.38, 0.22, 0.85)
const SQUASH_Y := 0.45

var radius := 26.0
var grow_ms := 600.0
var _t := 0.0


func _ready() -> void:
	z_index = -1


func _process(delta: float) -> void:
	_t = minf(1.0, _t + delta * 1000.0 / maxf(1.0, grow_ms))
	queue_redraw()


func _draw() -> void:
	var r := radius * (0.35 + 0.65 * _t)
	var points := PackedVector2Array()
	for i in 32:
		var angle := TAU * float(i) / 32.0
		points.append(Vector2(cos(angle) * r, sin(angle) * r * SQUASH_Y))
	draw_colored_polygon(points, Color(COLOR, COLOR.a * (0.4 + 0.6 * _t)))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, RING, 2.0, true)
