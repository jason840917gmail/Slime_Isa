@tool
extends "res://game/dungeon/hazard_deck.gd"
## A lily pad landing (Gloop Forest's River Roads, 2026-11-21; docs/design/2026-11-21-gloop-river-roads.md
## "Lily pads"): a broad pad with a white water lily that never sinks: safe ground over the water
## hazard in a row of sinking lily pads (sinking_lily_pad.gd), where a Roll may end, as the plank
## landing in a plank bridge (plank_landing.gd). It opens the deep water's collision under it like
## the planks (plank_look.gd `open_lane`). The flower tells it from a sinking pad at a glance.
##
## Its picture is the water-life lily pad sheet's white lily (frames 8 to 15, its idle loop), drawn
## over its cell a little larger than the pads.
##
## Owner: world (water).

const PlankLook := preload("res://game/dungeon/plank_look.gd")
const SinkingLilyPad := preload("res://game/world/water/sinking_lily_pad.gd")

## The white lily's idle loop (row 1 of the sheet).
const FIRST_FRAME := 8
const DRAWN_SCALE := 1.3

var _picture: Texture2D
var _phase := 0
var _step := -1


func _init() -> void:
	draw_floor = false


func _ready() -> void:
	super()
	_phase = randi() % SinkingLilyPad.LOOP_FRAMES
	if not Engine.is_editor_hint():
		PlankLook.open_lane(self, size)


func _process(_delta: float) -> void:
	var step := SinkingLilyPad.idle_step(_phase)
	if step != _step:
		_step = step
		queue_redraw()


func _draw() -> void:
	super()
	if _picture == null:
		_picture = SheetSprite.load_picture(SinkingLilyPad.LILY_SHEET)
	SinkingLilyPad.draw_lily(self, _picture, Rect2(Vector2.ZERO, size),
		FIRST_FRAME + SinkingLilyPad.idle_step(_phase), Color.WHITE, DRAWN_SCALE)
