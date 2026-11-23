@tool
extends "res://game/dungeon/falling_plank.gd"
## A sinking lily pad (Gloop Forest's River Roads, 2026-11-21; docs/design/2026-11-21-gloop-river-roads.md
## "Lily pads"): the falling plank's twin with a lily pad's look (falling_plank.gd: the same states
## and numbers, `dungeon.slab.fallDelayMs` and `returnMs`; the lane it opens through deep water, and
## the water hazard laid over the lane). Touched by the slime's body it dips and wobbles,
## `fall_delay_ms` later it sinks with a splash and rings, and it comes back up `returnMs` after.
## A walk sinks it under the slime; a Roll crosses two pads to a lily pad landing
## (lily_pad_landing.gd), which never sinks.
##
## Its picture is the water-life lily pad sheet's single round pad (frames 16 to 23, its idle loop:
## it bobs on the water while it waits), drawn over its cell a little larger than the cell.
##
## Owner: world (water).

const LILY_SHEET := "res://asset/MAPS/water/128x128-tile_8x4-water-lilypads.webp"
const SHEET_COLUMNS := 8
const SHEET_ROWS := 4
## The single round pad's idle loop (row 2 of the sheet).
const FIRST_FRAME := 16
const LOOP_FRAMES := 8
## The sheet's idle loop runs at three frames a second (water-life--lilypad-single.tscn).
const FRAME_MS := 333.0
## Drawn this much larger than its cell (the pad's leaf fills about 0.86 of its frame).
const DRAWN_SCALE := 1.12
## The dip as the slime steps on it (the footsteps' wading cue).
const CUE_DIP := &"WaterEnter"
## Without the picture: a leaf's colours.
const LEAF := Color("#6f9a34")
const LEAF_EDGE := Color("#3f5f1c")

## A pad's place in its idle loop, so a row of pads never bobs in step.
var _phase := 0
var _step := -1


func _ready() -> void:
	super()
	_phase = randi() % LOOP_FRAMES


func _art_path() -> String:
	return LILY_SHEET


func _crack_cue() -> StringName:
	return CUE_DIP


func _process(_delta: float) -> void:
	# The idle loop: a frame every FRAME_MS of real time (presentation only).
	var step := idle_step(_phase)
	if step != _step:
		_step = step
		queue_redraw()


func _draw_piece(box: Rect2, _frame: int, tint: Color, _alpha: float) -> void:
	# Sinking, it takes the water's colour as it fades.
	var wet := tint
	if state == State.FALLING:
		wet = Color(tint.r * 0.7, tint.g * 0.85, tint.b, tint.a)
	draw_lily(self, _picture, box, FIRST_FRAME + idle_step(_phase), wet, DRAWN_SCALE)


## The idle loop's frame now (0 … LOOP_FRAMES - 1), from `phase`.
static func idle_step(phase: int) -> int:
	return (int(Time.get_ticks_msec() / FRAME_MS) + phase) % LOOP_FRAMES


## Draws the lily sheet's frame `frame` on `canvas`, centred on `box` and `scale` times its size.
static func draw_lily(canvas: CanvasItem, texture: Texture2D, box: Rect2, frame: int, tint: Color, scale: float) -> void:
	var drawn := Rect2(box.get_center() - box.size * scale * 0.5, box.size * scale)
	if texture == null:
		canvas.draw_circle(drawn.get_center(), drawn.size.x * 0.42, Color(LEAF, tint.a))
		canvas.draw_arc(drawn.get_center(), drawn.size.x * 0.42, 0.0, TAU, 24, Color(LEAF_EDGE, tint.a), 2.0)
		return
	var cell := Vector2(texture.get_width() / float(SHEET_COLUMNS), texture.get_height() / float(SHEET_ROWS))
	var region := Rect2(Vector2(frame % SHEET_COLUMNS, frame / SHEET_COLUMNS) * cell, cell)
	canvas.draw_texture_rect_region(texture, drawn, region, tint)
