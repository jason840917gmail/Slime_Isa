extends RefCounted
class_name AttackActivations
## Attack activation registry (Phaser `features/combat/AttackActivation.ts`): one token per
## swing window / enemy attack; remembers accepted receivers and terminal rejections so a
## receiver is hit at most once per activation, while retryable rejections (dodge, i-frames) can
## still land later in the same activation. Combat spec 7.1 steps 2, 5, 7.
##
## Owner: combat builder.

const REASON_DUPLICATE := "duplicate"
const REASON_INACTIVE := "inactive-attack"

## id -> {"source": Object, "areas": Array[Area2D], "accepted": {receiver_id: true},
##        "terminal": {receiver_id: {area_signature: true}}}
var _activations: Dictionary = {}
var _next_id: int = 1


## New activation id (> 0). `attack_areas` may be a typed or untyped Array of Area2D.
func begin(source: Object, attack_areas: Array) -> int:
	if source == null or attack_areas.is_empty():
		push_error("AttackActivations.begin: an activation needs a source and at least one attack area")
		return 0
	var area_ids: Dictionary = {}
	for area: Variant in attack_areas:
		if not (area is Area2D) or not is_instance_valid(area):
			push_error("AttackActivations.begin: invalid attack area")
			return 0
		area_ids[(area as Area2D).get_instance_id()] = true
	var activation_id := _next_id
	_next_id += 1
	_activations[activation_id] = {
		"source_id": source.get_instance_id(),
		"areas": area_ids,
		"accepted": {},
		"terminal": {},
	}
	return activation_id


func end(activation_id: int) -> void:
	_activations.erase(activation_id)


## Drops every activation of `source` (Phaser `clearSource`).
func clear_source(source: Object) -> void:
	if source == null:
		return
	var source_id := source.get_instance_id()
	for activation_id: int in _activations.keys():
		if _activations[activation_id]["source_id"] == source_id:
			_activations.erase(activation_id)


func is_active(activation_id: int) -> bool:
	return _activations.has(activation_id)


## Active, same source, and `attack_area` belongs to the activation.
func validate(activation_id: int, source: Object, attack_area: Area2D) -> bool:
	var attack: Dictionary = _activations.get(activation_id, {})
	if attack.is_empty() or source == null or attack_area == null:
		return false
	if attack["source_id"] != source.get_instance_id():
		return false
	return (attack["areas"] as Dictionary).has(attack_area.get_instance_id())


## "" when the attempt may proceed, else "duplicate" (receiver already accepted, or this area
## signature was terminally rejected for the receiver); "inactive-attack" for an unknown id.
func before_attempt(activation_id: int, receiver: Object, area_signature: String) -> String:
	var attack: Dictionary = _activations.get(activation_id, {})
	if attack.is_empty():
		return REASON_INACTIVE
	var receiver_id := receiver.get_instance_id()
	if (attack["accepted"] as Dictionary).has(receiver_id):
		return REASON_DUPLICATE
	var signatures: Dictionary = (attack["terminal"] as Dictionary).get(receiver_id, {})
	if signatures.has(area_signature):
		return REASON_DUPLICATE
	return ""


## Records a routed result: accepted -> receiver done; rejected and not retryable -> signature
## terminal; retryable -> nothing.
func record(activation_id: int, receiver: Object, area_signature: String, result: Dictionary) -> void:
	var attack: Dictionary = _activations.get(activation_id, {})
	if attack.is_empty():
		return
	var receiver_id := receiver.get_instance_id()
	if result.get("status", "") == "accepted":
		(attack["accepted"] as Dictionary)[receiver_id] = true
		return
	if bool(result.get("retryable", false)):
		return
	var terminal: Dictionary = attack["terminal"]
	if not terminal.has(receiver_id):
		terminal[receiver_id] = {}
	(terminal[receiver_id] as Dictionary)[area_signature] = true
