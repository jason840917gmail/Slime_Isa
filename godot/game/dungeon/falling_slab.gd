@tool
extends "res://game/dungeon/hazard_deck.gd"
class_name FallingSlab
## A falling slab (docs/godot/DUNGEONS.md "The void, slabs and spikes"; roadmap 5.14, decisions
## archive questions 70 and 71; `object.falling-slab`): a loose, cracked flagstone over the void or
## spikes. Touched by the slime's body, it cracks and shakes, and falls `dungeon.slab.fallDelayMs`
## later (`fall_delay_ms` to tune one); then the slime's feet over its spot are over the hazard.
## It comes back `dungeon.slab.returnMs` after it fell (10 s), rising into place.
##
## The timing is set so a Roll crosses a slab and walking never does: walking (200 units/s), the
## body is on a 64-unit slab for 450 ms from its first touch to the feet leaving it; a Roll for under
## 270 ms. The slime cannot stop on a slab between two Rolls (the Roll's cooldown is longer than the
## delay): a bridge longer than one Roll (two slabs and a bit) needs a solid landing (a HazardDeck)
## where a Roll ends, or the charged Roll held across (docs/godot/DUNGEONS.md has the numbers).
##
## A slab is not safe ground: a fall puts the slime back on the rim before the bridge. Its look is
## the slab sheet's cracked slab (SLAB_ART, frame 1), drawn over its rectangle; a landing
## (HazardDeck) draws the whole one, so the two are told apart.
##
## Owner: dungeon kit.


const SLAB_ART := "res://asset/MAPS/objects/dungeon/slab-2x1.webp"
const CUE_CRACK := &"GroundCreak"
const CUE_FALL := &"BreakStone"
const DUST := &"dodge-dust"
const FALL_SCALE := 0.55
const FALL_SINK_PX := 12.0

enum State { STANDING, GIVING, FALLING, GONE, RISING }

## Touched: it starts to give. Payload: {"slab": its name}.
signal cracked(payload: Dictionary)
## It fell. Payload: {"slab"}.
signal fell(payload: Dictionary)
## It is back. Payload: {"slab"}.
signal returned(payload: Dictionary)

## ms from the touch to its fall; < 0: `dungeon.slab.fallDelayMs`.
@export var fall_delay_ms: float = -1.0
## ms from its fall to its return; < 0: `dungeon.slab.returnMs`.
@export var return_ms: float = -1.0

var state: State = State.STANDING
var _since_ms := 0.0
var _picture: Texture2D


func _init() -> void:
	safe = false
	draw_floor = false


func _ready() -> void:
	super()
	_picture = SheetSprite.load_picture(SLAB_ART)


func holds() -> bool:
	return state == State.STANDING or state == State.GIVING


func touch() -> void:
	if state != State.STANDING:
		return
	state = State.GIVING
	_since_ms = Services.now_ms()
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_CRACK)
	cracked.emit({"slab": String(name)})
	queue_redraw()


## The fall delay in use (ms).
func delay_ms() -> float:
	return fall_delay_ms if fall_delay_ms >= 0.0 else DungeonState.number("slab.fallDelayMs", 300.0)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or state == State.STANDING:
		return
	var now := Services.now_ms()
	var held := now - _since_ms
	match state:
		State.GIVING:
			if held >= delay_ms():
				_set_state(State.FALLING, now)
				var feel := Services.feel()
				if feel != null:
					feel.audio_cue(CUE_FALL)
					feel.particles(DUST, global_position + size * 0.5)
				fell.emit({"slab": String(name)})
		State.FALLING:
			if held >= DungeonState.number("slab.dropMs", 380.0):
				_set_state(State.GONE, now)
		State.GONE:
			if held >= (return_ms if return_ms >= 0.0 else DungeonState.number("slab.returnMs", 10000.0)):
				_set_state(State.RISING, now)
		State.RISING:
			if held >= DungeonState.number("slab.riseMs", 450.0):
				_set_state(State.STANDING, now)
				returned.emit({"slab": String(name)})
	queue_redraw()


func _set_state(next: State, now: float) -> void:
	state = next
	_since_ms = now


func _draw() -> void:
	super()
	if state == State.GONE:
		return
	if _picture == null and Engine.is_editor_hint():
		_picture = SheetSprite.load_picture(SLAB_ART)
	var t := 0.0
	var now := Services.now_ms() if not Engine.is_editor_hint() else 0.0
	var scale := 1.0
	var alpha := 1.0
	var sink := 0.0
	# The broken-up slab always: it reads as loose beside a landing's whole flagstone (frame 0).
	var frame := 1
	var shake := Vector2.ZERO
	match state:
		State.GIVING:
			frame = 1
			var px := DungeonState.number("slab.shakePx", 2.5)
			var real := Time.get_ticks_msec() / 1000.0
			shake = Vector2(sin(real * 71.0), cos(real * 53.0)) * px
		State.FALLING:
			frame = 1
			t = clampf((now - _since_ms) / maxf(1.0, DungeonState.number("slab.dropMs", 380.0)), 0.0, 1.0)
			scale = lerpf(1.0, FALL_SCALE, t)
			alpha = 1.0 - t * t
			sink = FALL_SINK_PX * t
		State.RISING:
			t = clampf((now - _since_ms) / maxf(1.0, DungeonState.number("slab.riseMs", 450.0)), 0.0, 1.0)
			scale = lerpf(FALL_SCALE, 1.0, t)
			alpha = t
	var drawn := size * scale
	var box := Rect2(size * 0.5 - drawn * 0.5 + shake + Vector2(0.0, sink), drawn)
	var tint := Color(1.0, 1.0, 1.0, alpha).darkened(0.5 * (1.0 - alpha) if state == State.FALLING else 0.0)
	if _picture == null:
		draw_rect(box, Color(Color("#8b8378"), alpha))
		draw_rect(box.grow(-3.0), Color(Color("#5a524a"), alpha), false, 2.0)
		if frame == 1:
			draw_line(box.position + box.size * Vector2(0.2, 0.3), box.position + box.size * Vector2(0.75, 0.7), Color(0.15, 0.12, 0.1, alpha), 2.0)
		return
	var cell := Vector2(_picture.get_width() * 0.5, _picture.get_height())
	draw_texture_rect_region(_picture, box, Rect2(Vector2(cell.x * frame, 0.0), cell), tint)
