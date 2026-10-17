extends Node2D
class_name GateWinchScript
## Scene script `game.gate-winch` (`object.gate-winch`, game/scenes/objects/gate-winch.tscn; Fatty's
## Lair, docs/godot/DUNGEONS.md "Fatty's Lair (built)"): the old gatehouse winch, worked from one side.
## The interact key turns it (the interaction's `usable` group): the drum shakes, the chain rattles,
## and every gate with its `gate_id` opens for good: a drop gate (game/scripts/drop_gate.gd) is held
## up (`hold_open_for_good`), a plain gate (game/scripts/gate.gd) opened (`open_for_good`). Both keep
## their record in RunState, so a turned winch is not offered again (`can_use`).
##
## Owner: dungeons (Fatty's Lair).

const Services := preload("res://game/shared/services.gd")

const USABLE_GROUP := &"usable"
const DROP_GATE_GROUP := &"drop_gate"
const GATE_GROUP := &"gate"
const CUE_TURN := &"GateUnlock"
const CUE_CHAIN := &"DoorUse"
const SHAKE_PX := 3.0
const TURN_S := 0.6

## Emitted when it is turned. Payload: {"gateId"}.
signal turned(payload: Dictionary)

## The gates it works (their `gate_id`).
@export var gate_id: String = ""
## The map whose record keeps them ("" = the world's).
@export var map_id: String = ""
@export var prompt: String = "Turn the winch"
@export var interact_radius: float = 80.0
@export var badge_rise: float = 120.0
@export var visual: Sprite2D


func _enter_tree() -> void:
	add_to_group(USABLE_GROUP)


func origin() -> Vector2:
	return global_position


## Offered until its gates are open for good.
func can_use() -> bool:
	var run := Services.run()
	return run == null or not run.is_gate_unlocked(_record_map_id(), gate_id)


func use() -> bool:
	if not can_use():
		return false
	for node: Node in get_tree().get_nodes_in_group(DROP_GATE_GROUP):
		if str(node.get(&"gate_id")) == gate_id:
			node.call(&"hold_open_for_good")
	for node: Node in get_tree().get_nodes_in_group(GATE_GROUP):
		if str(node.get(&"gate_id")) == gate_id and node.has_method(&"open_for_good"):
			node.call(&"open_for_good")
	var run := Services.run()
	if run != null:
		run.mark_gate_unlocked(_record_map_id(), gate_id)
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_TURN)
		feel.audio_cue(CUE_CHAIN)
	if visual != null:
		var start := visual.position
		var tween := create_tween()
		for i in 4:
			tween.tween_property(visual, "position", start + Vector2(SHAKE_PX * (1.0 if i % 2 == 0 else -1.0), 0.0), TURN_S / 8.0)
		tween.tween_property(visual, "position", start, TURN_S / 8.0)
	turned.emit({"gateId": gate_id})
	return true


func _record_map_id() -> String:
	if not map_id.is_empty():
		return map_id
	var world := Services.world()
	return world.map_id() if world != null else ""
