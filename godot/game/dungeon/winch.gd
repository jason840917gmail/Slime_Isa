@tool
extends Node2D
class_name Winch
## A winch or crank (docs/godot/DUNGEONS.md "Doors and room logic"; `object.winch`): something to
## turn that opens a door, a bridge or a hatch for good. The slime walks into its body and keeps
## pushing for `dungeon.winch.turnMs` (PushProbe; letting go starts again): the crank turns with a
## creak, then every node in `targets` is set off (DungeonState.fire: its `trigger()`, else
## `appear()`, `open_for_good()`, `lower()` or `open()`: a Shutter, a Drawbridge, a gate, a hidden
## chest), `turned` fires, and its
## record (`winch_id`) keeps it turned (a turned winch sets nothing off again: what it opened stays
## open by its own record).
##
## Its look (`look`, 2 frames: the crank up, the crank down) swaps while it turns.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const PushProbe := preload("res://game/dungeon/push_probe.gd")

const CUE_TURN := &"HeavyBlockGrab"
const CUE_DONE := &"GateUnlock"
const CRANK_EVERY_MS := 160.0
const TEXT_RISE := 110.0

## It was turned. Payload: {"winchId"}.
signal turned(payload: Dictionary)

## Its id in the record.
@export var winch_id: String = ""
## What it sets off.
@export var targets: Array[NodePath] = []
## Its body (the push box).
@export var body: StaticBody2D
## Its picture (2 frames: crank up, crank down).
@export var look: Sprite2D
## A line once turned and walked into again ("" = none).
@export var done_text: String = ""

var _turned := false
var _push_ms := 0.0
var _next_crank_ms := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_restore_in_tree.call_deferred()


func is_turned() -> bool:
	return _turned


## `_restore`, deferred from `_ready`, only while still in the tree: a world run on its own (F6)
## is the current scene for a moment before it swaps itself for main.tscn, and this piece of that
## copy has left the tree by then.
func _restore_in_tree() -> void:
	if is_inside_tree():
		_restore()


func _restore() -> void:
	if DungeonState.is_done(get_tree(), _record_key()):
		_turned = true
		if look != null and look.hframes > 1:
			look.frame = 1


func _record_key() -> String:
	return DungeonState.object_key(self, "winch:" + (winch_id if not winch_id.is_empty() else String(name)))


## Turns it now (as a full push does).
func turn() -> void:
	if _turned:
		return
	_turned = true
	DungeonState.mark_done(get_tree(), _record_key())
	if look != null and look.hframes > 1:
		look.frame = 1
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_DONE)
	for path: NodePath in targets:
		DungeonState.fire(get_node_or_null(path), {"winchId": winch_id})
	turned.emit({"winchId": winch_id})


func _physics_process(delta: float) -> void:
	var direction := PushProbe.push_direction(PushProbe.shapes_box(body), DungeonState.number("winch.reachPx", 8.0))
	if direction == Vector2.ZERO:
		_push_ms = 0.0
		return
	if _turned:
		if _push_ms == 0.0 and not done_text.is_empty():
			var feel := Services.feel()
			if feel != null:
				feel.floating_text(global_position - Vector2(0.0, TEXT_RISE), done_text, &"white", false, 1800.0)
		_push_ms += delta * 1000.0
		return
	_push_ms += delta * 1000.0
	var now := Services.now_ms()
	if now >= _next_crank_ms:
		_next_crank_ms = now + CRANK_EVERY_MS
		if look != null and look.hframes > 1:
			look.frame = 1 - look.frame
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(CUE_TURN)
	if _push_ms >= DungeonState.number("winch.turnMs", 900.0):
		turn()
