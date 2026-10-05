extends Node
class_name TrainingDummyScript
## Scene script `game.training-dummy` (Phaser `features/scripts/TrainingDummyScript.ts`;
## abilities spec 13.6). A straw dummy for trying attacks: every hit shows its damage (orange, big,
## 96 px above the root) and wobbles the sprite away from the blow, fading out in about 0.9 s. It
## never breaks and never fights back; the attacker's usual hit feedback applies.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

const RULE := {"priority": 0, "damageMultiplier": 1}
const TEXT_RISE := 96.0
## Wobble: 0.22 rad decaying by e^(-4.5 t), cos(6 pi t); stops under 0.004 rad.
const WOBBLE_AMPLITUDE := 0.22
const WOBBLE_DECAY := 4.5
const WOBBLE_RATE := 9.0 * TAU / 3.0
const WOBBLE_END := 0.004

## JSON `damageArea`: the hurtbox Area2D.
@export var damage_area: Area2D
## JSON `visual`: the dummy Sprite2D (optional).
@export var visual: Sprite2D

## A hit landed. Payload: {"damage": float}.
signal hit(payload: Dictionary)

var hits: int = 0
var _wobble_age: float = -1.0
var _side: float = 1.0
var _registered: Area2D


func _ready() -> void:
	var router := Services.router()
	if damage_area != null and router != null:
		router.register_area(damage_area, self, RULE, [])
		_registered = damage_area


func _exit_tree() -> void:
	var router := Services.router()
	if _registered != null and router != null:
		router.unregister_area(_registered)
	_registered = null


func get_damage_state() -> Dictionary:
	return {"hp": 9999.0, "max_hp": 9999.0, "dead": false}


func can_receive_damage(_input: Dictionary) -> Dictionary:
	return {"accepted": true}


func commit_damage(commit: Dictionary) -> void:
	var result: Dictionary = commit.get("result", {})
	var actual := float(result.get("actual_damage", 0.0))
	hits += 1
	_wobble_age = 0.0
	var request: Dictionary = commit.get("request", {})
	var impact: Dictionary = request.get("impact", {})
	var knock: Vector2 = impact.get("knock", Vector2.RIGHT)
	_side = -1.0 if knock.x < 0.0 else 1.0
	var root := get_parent() as Node2D
	var feel := Services.feel()
	if feel != null and root != null:
		feel.floating_text(root.global_position - Vector2(0.0, TEXT_RISE), str(roundi(actual)), &"orange", true)
	hit.emit({"damage": actual})


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


func _process(delta: float) -> void:
	if _wobble_age < 0.0 or visual == null:
		return
	_wobble_age += delta
	var amplitude := WOBBLE_AMPLITUDE * exp(-WOBBLE_DECAY * _wobble_age)
	var lean := 0.0 if amplitude < WOBBLE_END else _side * amplitude * cos(_wobble_age * WOBBLE_RATE)
	visual.rotation = lean
	if lean == 0.0:
		_wobble_age = -1.0
