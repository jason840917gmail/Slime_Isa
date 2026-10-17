extends Node2D
## The birth (roadmap 5.18; docs/design/2026-10-16-prologue.md, "The birth"): a bubble rises out of
## the Wellspring's goo, wobbles, drifts to the shore and pops, and the last slime born from the
## Wellspring is there. Drawn here: a glossy goo bubble with its rim, its shine and a ripple ring
## under it. `play(from, to)` runs it (awaitable): it swells at `from` (RISE_S), wobbles (WOBBLE_S),
## drifts to `to` (DRIFT_S) and pops (POP_S) with a splash, then frees itself. The director shows
## the slime at the pop. Presentation only, on real time.
##
## Owner: prologue.

const Services := preload("res://game/shared/services.gd")
const SoftGlow := preload("res://game/prologue/soft_glow.gd")

const RISE_S := 1.4
const WOBBLE_S := 1.3
const DRIFT_S := 1.1
const POP_S := 0.18
const RADIUS := 34.0
const GOO := Color(0.55, 0.95, 0.35, 0.85)
const RIM := Color(0.18, 0.42, 0.12, 0.9)
const SHINE := Color(1.0, 1.0, 0.9, 0.85)
const GLOW := Color(0.6, 1.0, 0.4, 0.6)
## Its own cues (global.tscn), holding the Gulp's round-5 spit and suck takes.
const CUE_POP := &"BubblePop"
const CUE_RISE := &"BubbleRise"

## The bubble popped (the slime is born).
signal popped

var _size := 0.0
var _wobble := 0.0
var _clock := 0.0
var _ripple := 0.0


func _process(delta: float) -> void:
	_clock += delta
	_ripple = fposmod(_ripple + delta * 0.8, 1.0)
	queue_redraw()


func _draw() -> void:
	if _size <= 0.0:
		return
	var r := RADIUS * _size
	var squash := Vector2(1.0 + sin(_clock * 9.0) * 0.08 * _wobble, 1.0 - sin(_clock * 9.0) * 0.08 * _wobble)
	# The ripple ring on the goo under it.
	var ring := RADIUS * (1.1 + _ripple * 1.2) * _size
	draw_arc(Vector2(0, r * 0.55), ring, 0, TAU, 32, Color(0.85, 1.0, 0.6, 0.45 * (1.0 - _ripple)), 2.0)
	draw_texture_rect(SoftGlow.glow_texture(), Rect2(Vector2(-r, -r) * 2.2, Vector2(r, r) * 4.4), false, GLOW)
	draw_set_transform(Vector2(0, -r * 0.2), 0.0, squash)
	draw_circle(Vector2.ZERO, r, RIM)
	draw_circle(Vector2.ZERO, r * 0.9, GOO)
	draw_circle(Vector2(r * 0.12, r * 0.18), r * 0.62, Color(0.75, 1.0, 0.5, 0.55))
	draw_circle(Vector2(-r * 0.35, -r * 0.38), r * 0.22, SHINE)
	draw_circle(Vector2(-r * 0.12, -r * 0.55), r * 0.08, SHINE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The whole birth: rise at `from`, wobble, drift to `to`, pop. Awaitable; frees itself after.
func play(from: Vector2, to: Vector2) -> void:
	global_position = from
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_RISE)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: _size = v, 0.0, 1.0, RISE_S).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await tween.finished
	tween = create_tween()
	tween.tween_method(func(v: float) -> void: _wobble = v, 0.0, 1.0, WOBBLE_S * 0.3)
	tween.tween_interval(WOBBLE_S * 0.7)
	await tween.finished
	tween = create_tween()
	tween.tween_property(self, "global_position", to, DRIFT_S).set_trans(Tween.TRANS_SINE)
	await tween.finished
	tween = create_tween()
	tween.tween_method(func(v: float) -> void: _size = v, 1.0, 1.35, POP_S)
	await tween.finished
	if feel != null:
		feel.audio_cue(CUE_POP)
		feel.particles(&"slime-splash", global_position)
	popped.emit()
	queue_free()
