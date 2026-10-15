extends Node2D
## Stars that orbit a dazed enemy's head (combat-feel plan section 6 "By weight class": "Daze: stars
## orbit the head"). Code-drawn: a few small four-point stars on a flat ellipse over `head`, the
## ones behind the head dimmer. EnemyHitMotion.show_stars puts one on the enemy's root and keeps it
## until the daze's stun ends (`until_ms`, simulation ms); it frees itself then. It pauses with the
## tree (a hit-stop holds the stars too). Presentation only.
##
## Owner: reactions.

const Services := preload("res://game/shared/services.gd")

## Look (presentation).
const STAR_COUNT := 3
const ORBIT_RADIUS := Vector2(15.0, 5.0)
const ORBIT_TURNS_PER_S := 0.9
const STAR_OUTER_PX := 4.5
const STAR_INNER_PX := 1.6
const STAR_COLOR := Color(1.0, 0.92, 0.42)
const STAR_EDGE := Color(0.55, 0.36, 0.05)
const BEHIND_ALPHA := 0.45
const SPIN_TURNS_PER_S := 1.5

## Simulation ms at which the stars go.
var until_ms: float = 0.0
## Where the head is, in this node's space (the orbit's centre).
var head: Vector2 = Vector2.ZERO

var _age_s: float = 0.0


func _process(delta: float) -> void:
	_age_s += delta
	if Services.now_ms() >= until_ms:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for index: int in STAR_COUNT:
		var angle := _age_s * TAU * ORBIT_TURNS_PER_S + float(index) * TAU / float(STAR_COUNT)
		var point := head + Vector2(cos(angle) * ORBIT_RADIUS.x, sin(angle) * ORBIT_RADIUS.y)
		var alpha := 1.0 if sin(angle) >= 0.0 else BEHIND_ALPHA
		_draw_star(point, _age_s * TAU * SPIN_TURNS_PER_S + float(index), alpha)


func _draw_star(centre: Vector2, turn: float, alpha: float) -> void:
	var points := PackedVector2Array()
	for corner: int in 8:
		var radius := STAR_OUTER_PX if corner % 2 == 0 else STAR_INNER_PX
		var angle := turn + float(corner) * TAU / 8.0
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	var fill := Color(STAR_COLOR, STAR_COLOR.a * alpha)
	draw_colored_polygon(points, fill)
	var edge := points.duplicate()
	edge.append(points[0])
	draw_polyline(edge, Color(STAR_EDGE, STAR_EDGE.a * alpha), 1.0, true)
