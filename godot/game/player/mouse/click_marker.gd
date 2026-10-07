extends Node2D
## The mouse control schemes' ground marks (game/player/mouse/control_scheme.gd): a ring that
## shrinks and fades where an order was given, a steady ring under what the pointer is over, and a
## fainter one under the order's target (red: attack, gold: use, green: walk).
## A child of the world's y-sorted root at y 0, like the Goo Trail, so it draws on the ground under
## everything standing on it; freed with the world. Presentation only (real time).
##
## Owner: player builder.

const PING_MS := 380.0
const PING_RADIUS := 20.0
const RING_RADIUS := 24.0
## Rings lie flat on the ground: half as tall as wide.
const FLATTEN := 0.5
const WIDTH := 3.0
const SEGMENTS := 40
const TARGET_ALPHA := 0.55
const COLOR_WALK := Color(0.72, 1.0, 0.68, 0.95)
const COLOR_ATTACK := Color(1.0, 0.36, 0.36, 0.95)
const COLOR_USE := Color(1.0, 0.84, 0.4, 0.95)

var _ping_at: Vector2 = Vector2.ZERO
var _ping_color: Color = COLOR_WALK
var _ping_since_ms: float = -INF
## Vector2 (world) or null.
var _hover: Variant = null
var _hover_color: Color = COLOR_ATTACK
var _target: Variant = null
var _target_color: Color = COLOR_ATTACK


func _ready() -> void:
	position = Vector2.ZERO


static func color_for(kind: String) -> Color:
	match kind:
		"attack":
			return COLOR_ATTACK
		"use":
			return COLOR_USE
	return COLOR_WALK


## A fading ring at `at` (world).
func ping(at: Vector2, color: Color) -> void:
	_ping_at = at
	_ping_color = color
	_ping_since_ms = _now_ms()
	queue_redraw()


## The steady ring under the pointer's target; null hides it.
func show_hover(at: Variant, color: Color) -> void:
	if at == _hover and color == _hover_color:
		return
	_hover = at
	_hover_color = color
	queue_redraw()


## The ring under the order's target; null hides it.
func show_target(at: Variant, color: Color) -> void:
	if at == _target and color == _target_color:
		return
	_target = at
	_target_color = color
	queue_redraw()


func _process(_delta: float) -> void:
	if _now_ms() - _ping_since_ms <= PING_MS:
		queue_redraw()


func _draw() -> void:
	var t := (_now_ms() - _ping_since_ms) / PING_MS
	if t >= 0.0 and t < 1.0:
		var color := _ping_color
		color.a *= 1.0 - t
		_ring(_ping_at, lerpf(PING_RADIUS * 1.6, PING_RADIUS * 0.5, t), color)
	if _target is Vector2:
		var faint := _target_color
		faint.a *= TARGET_ALPHA
		_ring(_target, RING_RADIUS + 4.0, faint)
	if _hover is Vector2:
		_ring(_hover, RING_RADIUS, _hover_color)


func _ring(at: Vector2, radius: float, color: Color) -> void:
	var centre := to_local(at)
	var points := PackedVector2Array()
	for i in SEGMENTS + 1:
		var angle := TAU * float(i) / float(SEGMENTS)
		points.append(centre + Vector2(cos(angle) * radius, sin(angle) * radius * FLATTEN))
	draw_polyline(points, color, WIDTH, true)


static func _now_ms() -> float:
	return float(Time.get_ticks_msec())
