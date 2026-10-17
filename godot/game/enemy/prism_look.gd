extends Node2D
## What the Prism Eye draws in code (the bestiary's row 26, docs/godot/BESTIARY.md "Prism Eye"):
## presentation only, made by game/scripts/prism_eye.gd.
##
## - `Mode.GAZE` (on the ground, under the bodies): what it looks along, `reach` px from its feet,
##   brighter while it charges: the wedge `gaze` (radians) +- `half_angle` (free aim), or, with
##   `half_width` (line aim), a band that wide either side of its line. `line_only` (the Watcher
##   Eye) draws a dim line instead.
## - `Mode.BEAM` (over the bodies): while it charges, a thin flickering aim line from the orb to
##   `beam_end` (the first solid thing on its line); while it fires, the beam itself (a glow and a
##   white-violet core) along the same line, fading over the beam's time (`beam`, 1..0).
## - `Mode.PUPIL` (a child of its Visual, over the art): the pupil on the orb (`orb_px`, the orb's
##   middle in the 256 px cell), looking along `gaze`, a pinpoint while it charges; with `iris_px`
##   (the Watcher Eye's blank eyeball) an iris round it.
##
## Owner: enemy builder.

enum Mode { GAZE, BEAM, PUPIL }

const GAZE_COLOR := Color(0.78, 0.62, 1.0, 0.07)
const GAZE_CHARGE_COLOR := Color(1.0, 0.7, 1.0, 0.16)
const AIM_COLOR := Color(1.0, 0.75, 1.0, 0.55)
const BEAM_GLOW := Color(0.85, 0.55, 1.0, 0.45)
const BEAM_CORE := Color(1.0, 0.96, 1.0, 0.95)
const PUPIL_COLOR := Color("#3a1d5c")
const PUPIL_HOT := Color(1.0, 0.92, 1.0)
const POINTS := 14
const GAZE_POINTS := 10

var mode: Mode = Mode.GAZE
## Where it looks (radians, 0 = right).
var gaze: float = PI * 0.5:
	set(value):
		gaze = value
		queue_redraw()
var half_angle: float = 0.24
## Line aim: the band's half width (0: the wedge).
var half_width: float = 0.0
var reach: float = 300.0
## GAZE: a dim line along the gaze instead of the wedge.
var line_only: bool = false
## 0: watching; 1: charging (the tell).
var charging: float = 0.0:
	set(value):
		charging = value
		queue_redraw()
## 1..0 while the beam burns (0: none).
var beam: float = 0.0:
	set(value):
		beam = value
		queue_redraw()
## BEAM: the orb (the line's start) and the line's end, in this node's parent's space.
var beam_from: Vector2 = Vector2.ZERO
var beam_end: Vector2 = Vector2.ZERO
var beam_width: float = 12.0
## BEAM: its colours (the Prism Eye's white-violet; the Watcher Eye's are orange-red).
var beam_glow: Color = BEAM_GLOW
var beam_core: Color = BEAM_CORE
var aim_color: Color = AIM_COLOR
## PUPIL: the orb's middle in the sheet cell, the pupil's reach and size (cell px).
var orb_px: Vector2 = Vector2(131.0, 72.0)
var pupil_reach_px: Vector2 = Vector2(14.0, 9.0)
var pupil_px: float = 9.0
## PUPIL: an iris this big round the pupil (cell px; 0: none) and its colours, calm and charging.
var iris_px: float = 0.0
var iris_color: Color = Color("#7a4a1e")
var iris_hot: Color = Color("#ff7a2a")
var shown: bool = true:
	set(value):
		shown = value
		queue_redraw()


func _draw() -> void:
	if not shown:
		return
	match mode:
		Mode.GAZE:
			_draw_gaze()
		Mode.BEAM:
			_draw_beam()
		Mode.PUPIL:
			_draw_pupil()


func _draw_gaze() -> void:
	if line_only:
		var tint := GAZE_COLOR.lerp(GAZE_CHARGE_COLOR, charging)
		draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(gaze) * reach, Color(tint, tint.a * 3.0), 2.0)
		return
	var points := PackedVector2Array()
	if half_width > 0.0:
		var along := Vector2.RIGHT.rotated(gaze)
		var side := along.orthogonal() * half_width
		points = PackedVector2Array([side, along * reach + side, along * reach - side, -side])
	else:
		points.append(Vector2.ZERO)
		for i in GAZE_POINTS + 1:
			var angle := gaze - half_angle + 2.0 * half_angle * float(i) / float(GAZE_POINTS)
			points.append(Vector2.RIGHT.rotated(angle) * reach)
	draw_colored_polygon(points, GAZE_COLOR.lerp(GAZE_CHARGE_COLOR, charging))


func _draw_beam() -> void:
	var flicker := 0.6 + 0.4 * sin(float(Time.get_ticks_msec()) / 22.0)
	if beam > 0.0:
		draw_line(beam_from, beam_end, Color(beam_glow, beam_glow.a * beam), beam_width * 2.0)
		draw_line(beam_from, beam_end, Color(beam_core, beam_core.a * beam), beam_width * 0.6)
		_disc(beam_end, beam_width * 1.2, Color(beam_core, 0.7 * beam))
		_disc(beam_from, beam_width * 1.1, Color(beam_core, 0.8 * beam))
	elif charging > 0.0:
		draw_line(beam_from, beam_end, Color(aim_color, aim_color.a * charging * flicker), 1.5)


func _draw_pupil() -> void:
	var visual := get_parent() as Sprite2D
	if visual == null:
		return
	var look := Vector2.RIGHT.rotated(gaze)
	var at := visual.offset + orb_px + Vector2(look.x * pupil_reach_px.x, look.y * pupil_reach_px.y)
	if visual.flip_h:
		at.x = visual.offset.x + (256.0 - orb_px.x) + look.x * pupil_reach_px.x
	var size := lerpf(pupil_px, pupil_px * 0.45, charging)
	if iris_px > 0.0:
		_disc(at, iris_px, iris_color.lerp(iris_hot, charging))
	_disc(at, size, PUPIL_COLOR.lerp(PUPIL_HOT, charging))
	_disc(at + Vector2(-size * 0.35, -size * 0.35), size * 0.3, Color(1.0, 1.0, 1.0, 0.8))


func _disc(at: Vector2, r: float, tint: Color) -> void:
	var polygon := PackedVector2Array()
	for i in POINTS:
		var angle := TAU * float(i) / float(POINTS)
		polygon.append(at + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(polygon, tint)
