extends Node2D
## The lever behind a barred gate's bars (game/scripts/barred_gate.gd; roadmap 5.22): a damage
## receiver on its own hurtbox (`area`) that takes only the Spear's thrust (a hit tagged `spear`).
## Tagged `resource` (a thrown pot's blast never reaches it, and a hit on it plays no enemy feel).
## Pulled, it drops (frame 1 of its sheet, with a clack and a sparkle) and opens its gate, the
## parent; anything else is refused with the gate's line, the clink.
##
## Owner: prologue.

const Services := preload("res://game/shared/services.gd")
const RULE := {"priority": 0, "damageMultiplier": 1}
const TAGS: Array[String] = ["resource"]
const FRAME_SHUT := 0
const FRAME_PULLED := 1
const CUE_PULL := &"DoorUse"
const SPARKLE := &"loot-sparkle"
const SPARKLE_RISE := 30.0

## The lever was pulled. Payload: {"gateId"}.
signal pulled(payload: Dictionary)

## The hurtbox the thrust must reach.
@export var area: Area2D
## The lever's picture (2 frames: shut, pulled).
@export var visual: Sprite2D

var _pulled := false
var _registered: Area2D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var router := Services.router()
	if router != null and area != null:
		router.register_area(area, self, RULE, TAGS)
		_registered = area


func _exit_tree() -> void:
	var router := Services.router()
	if _registered != null and router != null:
		router.unregister_area(_registered)
	_registered = null


## True once pulled.
func is_pulled() -> bool:
	return _pulled


## Shows the lever pulled (the gate is open), quietly.
func show_pulled() -> void:
	_pulled = true
	if visual != null:
		visual.frame = FRAME_PULLED


func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": _pulled}


## Only the Spear's thrust pulls it; anything else is the gate's refusal.
func can_receive_damage(input: Dictionary) -> Dictionary:
	var request: Dictionary = input.get("request", {})
	var gate := get_parent()
	if gate != null and gate.has_method(&"is_spear") and bool(gate.call(&"is_spear", request)):
		return {"accepted": true, "reason": ""}
	if gate != null and gate.has_method(&"refuse"):
		gate.call(&"refuse", str(request.get("weapon_id", "")))
	return {"accepted": false, "reason": "immune"}


## A thrust always lands (the Spear's harvest gate would otherwise make a `resource` take nothing).
func mitigate_damage(_input: Dictionary) -> float:
	return 1.0


func commit_damage(_commit: Dictionary) -> void:
	if _pulled:
		return
	show_pulled()
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_PULL)
		feel.particles(SPARKLE, global_position - Vector2(0.0, SPARKLE_RISE))
	var gate := get_parent()
	pulled.emit({"gateId": str(gate.get(&"gate_id")) if gate != null else ""})
	if gate != null and gate.has_method(&"open"):
		gate.call(&"open")


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass
