extends Node2D
## The soft drifting "z" over a sleeping villager's head (docs/godot/VILLAGERS.md "Asleep until its
## Pearl comes home"): `count` small z's, each rising `rise_px` and drifting `drift_px` aside over
## `cycle_ms`, growing a little and fading in then out, one after another. Code-drawn (the fallback
## font, an outline so it reads on any ground), presentation only, on real time. `stop()` fades it
## out and frees it (the villager woke).
##
## Owner: world (Glimmerhill).

const COLOR := Color(0.93, 0.97, 1.0)
const OUTLINE := Color(0.08, 0.1, 0.2)
const OUTLINE_PX := 3
## The share of a z's cycle it takes to fade in, and from where on it fades out.
const FADE_IN := 0.2
const FADE_OUT_FROM := 0.6
const GROW_FROM := 0.75
const GROW_TO := 1.2
const STOP_FADE_S := 0.35

var count := 2
var cycle_ms := 3400.0
var rise_px := 30.0
var drift_px := 12.0
var font_size := 13
var alpha := 0.8

var _start_ms := 0.0


func _ready() -> void:
	_start_ms = float(Time.get_ticks_msec()) - randf() * cycle_ms


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if font == null or count <= 0 or cycle_ms <= 0.0:
		return
	var now := float(Time.get_ticks_msec())
	for i in count:
		var phase := fmod((now - _start_ms) / cycle_ms + float(i) / float(count), 1.0)
		var a := alpha * minf(1.0, phase / FADE_IN) if phase < FADE_IN else \
				alpha * (1.0 - clampf((phase - FADE_OUT_FROM) / (1.0 - FADE_OUT_FROM), 0.0, 1.0))
		var size := maxi(6, int(round(float(font_size) * lerpf(GROW_FROM, GROW_TO, phase))))
		var at := Vector2(sin(phase * PI) * drift_px * 0.5 + phase * drift_px, -phase * rise_px)
		draw_string_outline(font, at, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, size, OUTLINE_PX, Color(OUTLINE, a * 0.85))
		draw_string(font, at, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(COLOR, a))


## Fades out and frees itself.
func stop() -> void:
	set_meta(&"stopping", true)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, STOP_FADE_S)
	tween.tween_callback(queue_free)
