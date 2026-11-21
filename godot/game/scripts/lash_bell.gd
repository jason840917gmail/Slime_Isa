extends Node
class_name LashBellScript
## Scene script `game.lash-bell` (Phaser `features/scripts/LashBellScript.ts`; abilities spec
## 13.4): a bell on a post, a ranged lock (owner, 2026-10-16, questions 115 and 127). A thrown thing
## rings it (a pot, a rock, a skull: any hit tagged `thrown`, game/player/gulp/thrown_object.gd),
## and so does the Bow's arrow (`on_arrow_hit`, group `bow_targets`; game/player/abilities/bow_arrow.gd). The
## Spear, the Stretch Lash and every other hit never ring it: they are refused as `immune` (the
## clink). Rung, it swings (frames 1, 2, 1, 2, 1, 0 every 90 ms), opens every gate with `gate_id`
## for good (a lock solved once, owner 2026-10-16, question 136: game/scripts/gate.gd
## `open_for_good` keeps the gate's record unlocked in RunState, so it stays open through a chunk
## entered again, a save and a load), plays BellRing with a sparkle, and emits `rung`. It never
## breaks; ringing it again changes nothing more. Its post (group `lash-bell`)
## is an anchor the Lash pulls on (game/player/abilities/ability_world.gd `lash_probe`), not a
## bell it rings.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

## The Lash's anchors (ability_world.gd `first_bell_along`).
const GROUP := &"lash-bell"
## What the Bow shoots at (docs/godot/BESTIARY.md "The Bow"): `on_arrow_hit(hit) -> bool`.
const BOW_TARGETS := &"bow_targets"
const GATE_GROUP := &"gate"
const RULE := {"priority": 0, "damageMultiplier": 1}
## The hit tag that rings it: a thrown thing's.
const RINGING_TAG := "thrown"
const REASON_IMMUNE := "immune"
const SWING_FRAMES: Array[int] = [1, 2, 1, 2, 1, 0]
const SWING_STEP := 0.09
const SPARKLE_RISE := 70.0
const CUE_RING := &"BellRing"

## JSON `bellId`.
@export var bell_id: String = ""
## JSON `gateId`: the gates it opens ("" = none).
@export var gate_id: String = ""
## JSON `damageArea`: the shape a thrown thing must hit (and the Lash's hook catches on).
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
	add_to_group(BOW_TARGETS)


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
	return {"hp": 1.0, "max_hp": 1.0, "dead": false}


## Only a thrown thing rings it; anything else (the Spear, a sword, the Roll's bonk, a slam, a
## blast, a flame) is refused: the clink.
func can_receive_damage(input: Dictionary) -> Dictionary:
	var request: Dictionary = input.get("request", {})
	if rings_to(request):
		return {"accepted": true}
	return {"accepted": false, "reason": REASON_IMMUNE}


## A ringing hit deals no damage (no number over the bell); its effect still lands, so it commits.
func mitigate_damage(_input: Dictionary) -> float:
	return 0.0


func commit_damage(_commit: Dictionary) -> void:
	ring()


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


## The Bow's arrow (bow_arrow.gd, as the bestiary's targets have it): it rings the
## bell. Always true.
func on_arrow_hit(_hit: Dictionary) -> bool:
	ring()
	return true


## True when `request` (a DamageRouter request) is a thrown thing's hit: its `weapon_tags` hold
## `thrown`.
static func rings_to(request: Dictionary) -> bool:
	var tags: Variant = request.get("weapon_tags", [])
	return tags is Array and (tags as Array).has(RINGING_TAG)


func ring() -> void:
	_ring_step = 0
	_elapsed = 0.0
	if visual != null:
		visual.frame = SWING_FRAMES[0]
	if not gate_id.is_empty():
		for gate: Node in get_tree().get_nodes_in_group(GATE_GROUP):
			if str(gate.get(&"gate_id")) == gate_id:
				gate.call(&"open_for_good" if gate.has_method(&"open_for_good") else &"open")
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
