extends Node2D
## The worms' lever beside a drop gate (game/scripts/drop_gate.gd; Fatty's Lair, docs/godot/DUNGEONS.md
## "Fatty's Lair (built)"): a crooked post with a root handle wrapped in a red war scarf, in the open,
## never behind bars (the Spear's barred gate keeps its lever behind them). The interact key pulls it
## (it joins the interaction's `usable` group): the handle swings down and back, a chain rattle, and
## its gate (the node `gate`, else the parent) rises. While the gate is not shut (up, dropping, held)
## it is not offered.
##
## Owner: dungeons (Fatty's Lair).

const Services := preload("res://game/shared/services.gd")

const USABLE_GROUP := &"usable"
const CUE_PULL := &"DoorUse"
const PULL_DEGREES := 28.0
const PULL_S := 0.12
const BACK_S := 0.35

## The prompt the interaction shows.
@export var prompt: String = "Pull the lever"
## How near the slime's centre must be (world units).
@export var interact_radius: float = 70.0
## Where the key badge floats over it.
@export var badge_rise: float = 110.0
## Its gate (a drop gate); empty: the parent.
@export var gate: NodePath
## The handle's picture (it swings).
@export var visual: Sprite2D


func _enter_tree() -> void:
	add_to_group(USABLE_GROUP)


## The point the interaction measures from (its foot).
func origin() -> Vector2:
	return global_position


func can_use() -> bool:
	var target := _gate()
	return target != null and not bool(target.call(&"is_open")) and str(target.call(&"state_name")) == "shut"


## Pulls it: the swing, the rattle, and its gate rises.
func use() -> bool:
	var target := _gate()
	if target == null or not bool(target.call(&"raise")):
		return false
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_PULL)
	if visual != null:
		var tween := create_tween()
		tween.tween_property(visual, "rotation_degrees", PULL_DEGREES, PULL_S).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(visual, "rotation_degrees", 0.0, BACK_S).set_trans(Tween.TRANS_SINE)
	return true


func _gate() -> Node:
	if not gate.is_empty():
		return get_node_or_null(gate)
	return get_parent()
