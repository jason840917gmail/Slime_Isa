@tool
extends "res://game/dungeon/dungeon_door.gd"
class_name BoltedDoor
## A bolted one-way door (docs/godot/DUNGEONS.md "Doors and room logic"; `object.bolted-door`): a
## wing's way back, opened from one side, then for good. Its bolt is on its face (set `wall` so the
## face looks into the room the bolt is on): walked into from there, the bolt slides back
## (`dungeon.bolt.slideMs`) and the door opens for good. Walked into from the back it says
## `locked_text` ("Bolted from the other side.") with the locked sound.
##
## The bolt's picture (`bolt`, 2 frames: shut, slid) sits on the leaf. With the frame drawn by the
## wall the leaf is the style's `bolt` leaf on the bolt's side; the far side's leaf (`bolt_here` off)
## has no bolt to slide, so it is the style's plain shut slab (`shutter`: the sheet has no wooden leaf
## without a bolt, and a door shut from the other side reads as a shutter, as in Zelda).
##
## Owner: dungeon kit.

const CUE_SLIDE := &"HeavyBlockGrab"
const SLIDE_PX := 14.0

## The bolt slid (before the door opens). Payload: {"doorId"}.
signal bolt_slid(payload: Dictionary)

## The line from the side without the bolt.
@export var locked_text: String = "Bolted from the other side."
## False: this leaf has no bolt of its own (the far side of a passage whose bolt is on its partner's
## side, `link_id`): pushed from either side it says `locked_text`, and it opens with its partner.
@export var bolt_here: bool = true:
	set(value):
		bolt_here = value
		if is_node_ready() and frame_drawn_by_wall:
			_apply_wall_frame()
## The bolt's picture (2 frames: shut, slid back).
@export var bolt: Sprite2D

var _sliding := false


## The wall-drawn leaf: the bolt where it can be slid, the plain shut slab on the far side.
func leaf_kind() -> String:
	return "bolt" if bolt_here else "shutter"


func _on_push(from_face: bool) -> void:
	if _sliding:
		return
	if not from_face or not bolt_here:
		say(locked_text)
		return
	_sliding = true
	bolt_slid.emit({"doorId": door_id})
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_SLIDE)
	var ms := DungeonState.number("bolt.slideMs", 420.0) / 1000.0
	if bolt != null:
		if bolt.hframes > 1:
			bolt.frame = 1
		var tween := bolt.create_tween()
		tween.tween_property(bolt, "position:x", bolt.position.x - SLIDE_PX, ms).set_trans(Tween.TRANS_BACK)
	# Recorded at once (a quit right after keeps it), opened once the bolt is back.
	DungeonState.mark_done(get_tree(), record_key())
	if is_inside_tree() and ms > 0.0:
		await get_tree().create_timer(ms, false).timeout
	if is_inside_tree():
		open_for_good()


func _restore() -> void:
	super()
	if is_open() and bolt != null and bolt.hframes > 1:
		bolt.frame = 1
