extends Node
class_name LashBellScript
## Scene script `game.lash-bell` (Phaser `features/scripts/LashBellScript.ts`; abilities spec
## 13.4). A bell post rung from a distance by the Stretch Lash (and, with `lash_only` off, by
## weapon hits and the slam): it swings (frames 1, 2, 1, 2, 1, 0 every 90 ms), opens every gate
## with `gate_id`, plays BellRing with a sparkle, and emits `rung`. It never breaks.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

const GROUP := &"lash-bell"
const GATE_GROUP := &"gate"
const RULE := {"priority": 0, "damageMultiplier": 1}
const SWING_FRAMES: Array[int] = [1, 2, 1, 2, 1, 0]
const SWING_STEP := 0.09
const SPARKLE_RISE := 70.0
const CUE_RING := &"BellRing"

## JSON `bellId`.
@export var bell_id: String = ""
## JSON `gateId`: the gates it opens ("" = none).
@export var gate_id: String = ""
## JSON `lashOnly`: only the lash rings it (no weapon hits).
@export var lash_only: bool = true
## JSON `damageArea`: the shape the lash (and, when not lash-only, weapons) must touch.
@export var damage_area: Area2D
## JSON `visual`: the bell Sprite2D (optional).
@export var visual: Sprite2D

## The bell rang. Payload: {"bellId"}.
signal rung(payload: Dictionary)

var _ring_step: int = -1
var _elapsed: float = 0.0
var _registered: Area2D


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	var router := Services.router()
	if not lash_only and damage_area != null and router != null:
		router.register_area(damage_area, self, RULE, [])
		_registered = damage_area


func _exit_tree() -> void:
	var router := Services.router()
	if _registered != null and router != null:
		router.unregister_area(_registered)
	_registered = null


func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": false}


func can_receive_damage(_input: Dictionary) -> Dictionary:
	return {"accepted": true}


func commit_damage(_commit: Dictionary) -> void:
	ring()


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


func ring() -> void:
	_ring_step = 0
	_elapsed = 0.0
	if visual != null:
		visual.frame = SWING_FRAMES[0]
	if not gate_id.is_empty():
		for gate: Node in get_tree().get_nodes_in_group(GATE_GROUP):
			if str(gate.get(&"gate_id")) == gate_id:
				gate.call(&"open")
	var root := get_parent() as Node2D
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_RING)
		if root != null:
			feel.particles(&"loot-sparkle", root.global_position - Vector2(0.0, SPARKLE_RISE))
	rung.emit({"bellId": bell_id})


func _process(delta: float) -> void:
	if _ring_step < 0:
		return
	_elapsed += delta
	if _elapsed < SWING_STEP:
		return
	_elapsed = 0.0
	_ring_step += 1
	if _ring_step >= SWING_FRAMES.size():
		_ring_step = -1
		if visual != null:
			visual.frame = 0
		return
	if visual != null:
		visual.frame = SWING_FRAMES[_ring_step]
