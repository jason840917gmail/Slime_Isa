extends Node2D
## The code-drawn goo ring (body-shapes plan sections 3 "Hold = charge", 5 "The mouth" and 8 "UI"
## item 2; BODY_SHAPES.md "Shared ring"): a faint full track and a bright arc that fills clockwise
## from the top as a hold goes on (or, with `fill_both_ways`, both ways from the top over
## `fill_span`). The mouth's swallow and spit rings and the shapes' charge rings
## share it; their owner adds it where it should sit (under the slime), sets its colour (the
## essence's for the mouth) and feeds it `set_progress` every step. `drain` empties it smoothly when a
## hold is let go early (`gulp.rework.ringCancelMs`). Presentation only: the drain runs on real time.
##
## Owner: shared (rework wiring); used by the mouth and shapes modules.

## Segments of a full circle.
const SEGMENTS := 48
## The arc starts at the top and runs clockwise.
const START_ANGLE := -PI / 2.0

## Radius of the ring's centre line in px (the mouth uses `gulp.rework.ringRadiusPx`).
@export var radius_px: float = 30.0
## Line width in px.
@export var thickness_px: float = 5.0
## The fill colour; the track is the same colour at `track_alpha`.
@export var color: Color = Color(0.55, 0.95, 0.55, 0.95)
@export var track_alpha: float = 0.25
## The share of the circle a full fill covers (radians), centred on START_ANGLE when
## `fill_both_ways` (the mouth's ring: it grows both ways from the front over the arc the slime's art
## leaves visible); from START_ANGLE clockwise otherwise.
@export var fill_span: float = TAU
@export var fill_both_ways: bool = false

var _progress: float = 0.0
## A running drain: its start (real ms, < 0 when none), length and the progress it started from.
var _drain_started_ms: float = -1.0
var _drain_ms: float = 0.0
var _drain_from: float = 0.0


func _ready() -> void:
	set_process(false)


## The filled share, 0..1 (stops a running drain).
func set_progress(t: float) -> void:
	_drain_started_ms = -1.0
	set_process(false)
	var next := clampf(t, 0.0, 1.0)
	if next != _progress:
		_progress = next
		queue_redraw()


func get_progress() -> float:
	return _progress


func set_color(c: Color) -> void:
	color = c
	queue_redraw()


func set_radius(px: float) -> void:
	radius_px = maxf(1.0, px)
	queue_redraw()


func set_thickness(px: float) -> void:
	thickness_px = maxf(1.0, px)
	queue_redraw()


## Empties the ring over `duration_ms` of real time, then hides it (0 or less: at once).
func drain(duration_ms: float) -> void:
	if duration_ms <= 0.0 or _progress <= 0.0:
		_progress = 0.0
		queue_redraw()
		hide()
		return
	_drain_from = _progress
	_drain_ms = duration_ms
	_drain_started_ms = float(Time.get_ticks_msec())
	set_process(true)


## True while a drain runs.
func is_draining() -> bool:
	return _drain_started_ms >= 0.0


func _process(_delta: float) -> void:
	if _drain_started_ms < 0.0:
		set_process(false)
		return
	var t := clampf((float(Time.get_ticks_msec()) - _drain_started_ms) / _drain_ms, 0.0, 1.0)
	_progress = _drain_from * (1.0 - t)
	queue_redraw()
	if t >= 1.0:
		_drain_started_ms = -1.0
		set_process(false)
		hide()


func _draw() -> void:
	var track := Color(color.r, color.g, color.b, color.a * track_alpha)
	draw_arc(Vector2.ZERO, radius_px, 0.0, TAU, SEGMENTS, track, thickness_px, true)
	if _progress <= 0.0:
		return
	var sweep := fill_span * _progress
	var points := maxi(2, ceili(SEGMENTS * sweep / TAU) + 1)
	var from := START_ANGLE - sweep * 0.5 if fill_both_ways else START_ANGLE
	draw_arc(Vector2.ZERO, radius_px, from, from + sweep, points, color, thickness_px, true)
