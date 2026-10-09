extends Node
class_name TomWebScript
## Scene script `game.tom-web` (owner, 2026-10-08; roadmap 8.13): the spider web Tom is caught in,
## in a Gloop Forest thicket (`object.tom-web`). Tom went there to swallow silk and got stuck; the
## slime cannot swallow yet, so it frees him with its weapon.
##
## - Weapon hits (tags "weapon" or "spear") tear at it; after `hits_to_tear` it gives way. Thrown
##   things and abilities only shake it, without a damage number.
## - It tears only while Mossy's quest `quest_id` is active; before that Tom just mumbles.
## - Torn: the story flag `freed_flag` is set for good (the scene's story variant swaps the cocoon
##   for torn strands, and the forest camp's variant shows Tom there), the quest's activate-object
##   objective counts (`object.activated` {objectId `object_id`}), and Tom calls out on his way
##   back to the camp.
##
## Owner: quests.

const Services := preload("res://game/shared/services.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")

const RULE := {"priority": 0, "damageMultiplier": 1}
const WEAPON_TAGS: Array[String] = ["weapon", "spear"]
const CUE_HIT := &"WebStruggle"
const CUE_TEAR := &"WebTear"
const TEXT_RISE := 70.0
const MUMBLE := "Mmmph! Mmph mmph! (Tom is stuck fast.)"
const SHAKE_TEXT := "It only shakes. Cut it with a weapon!"
const FREED_TEXT := "I'm free! Thank you! Meet me at Mossy's camp!"
## Hint texts at most this often (real time).
const HINT_EVERY_MS := 2500.0
const TEXT_MS := 2600.0
## Wobble of the cocoon on a hit: amplitude (rad), decay, rate.
const WOBBLE_AMPLITUDE := 0.16
const WOBBLE_DECAY := 5.0
const WOBBLE_RATE := 16.0
const PERSISTENCE_KEY_META := &"persistence_key"
## The quest arrow points at quest objects (game/quests/quest_waypoint.gd).
const QUEST_OBJECT_GROUP := &"quest_object"

## The cocoon's hurtbox Area2D.
@export var damage_area: Area2D
## The cocoon Sprite2D (it wobbles when hit).
@export var visual: Node2D
@export var hits_to_tear: int = 3
@export var quest_id: String = "tom-in-the-web"
@export var freed_flag: String = "tom-freed"
@export var object_id: String = "tom-web"

## The web gave way. Payload: {"flagId": String}.
signal torn(payload: Dictionary)

var hits: int = 0
var _registered: Area2D
var _wobble_age: float = -1.0
var _side: float = 1.0
var _next_hint_ms: float = 0.0


func _enter_tree() -> void:
	add_to_group(QUEST_OBJECT_GROUP)


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


func is_torn() -> bool:
	var run := Services.run()
	return run != null and run.has_flag(freed_flag)


func get_damage_state() -> Dictionary:
	return {"hp": float(maxi(0, hits_to_tear - hits)), "max_hp": float(hits_to_tear), "dead": is_torn()}


func can_receive_damage(input: Dictionary) -> Dictionary:
	if is_torn():
		return {"accepted": false, "reason": "dead"}
	var request: Dictionary = input.get("request", {})
	var tags: Array = request.get("weapon_tags", [])
	var by_weapon := false
	for tag: Variant in tags:
		if str(tag) in WEAPON_TAGS:
			by_weapon = true
	_start_wobble(request)
	if not _quest_active():
		_hint(MUMBLE)
		return {"accepted": false, "reason": "immune"}
	if not by_weapon:
		_hint(SHAKE_TEXT)
		return {"accepted": false, "reason": "immune"}
	return {"accepted": true}


func commit_damage(_commit: Dictionary) -> void:
	if is_torn():
		return
	hits += 1
	var feel := Services.feel()
	if hits < hits_to_tear:
		if feel != null:
			feel.audio_cue(CUE_HIT)
		return
	_tear()


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


func _tear() -> void:
	var run := Services.run()
	if run != null:
		run.set_flag(freed_flag)
	var root := get_parent() as Node2D
	var world := Services.world()
	var instance_id := str(root.get_meta(PERSISTENCE_KEY_META, root.name)) if root != null else object_id
	QuestEvents.emit(QuestEvents.OBJECT_ACTIVATED, {"objectId": object_id, "instanceId": instance_id,
		"areaId": world.map_id() if world != null else ""})
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_TEAR)
		if root != null:
			feel.particles(&"dust-puff", root.global_position)
			feel.floating_text(root.global_position - Vector2(0.0, TEXT_RISE), FREED_TEXT, &"green", true, TEXT_MS)
	torn.emit({"flagId": freed_flag})


func _quest_active() -> bool:
	var quests := get_tree().get_first_node_in_group(QuestEvents.SERVICE_GROUP)
	return quests != null and str(quests.call(&"status", quest_id)) == "active"


func _hint(text: String) -> void:
	var now := float(Time.get_ticks_msec())
	if now < _next_hint_ms:
		return
	_next_hint_ms = now + HINT_EVERY_MS
	var feel := Services.feel()
	var root := get_parent() as Node2D
	if feel != null and root != null:
		feel.audio_cue(CUE_HIT)
		feel.floating_text(root.global_position - Vector2(0.0, TEXT_RISE), text, &"white", false, TEXT_MS)


func _start_wobble(request: Dictionary) -> void:
	var impact: Dictionary = request.get("impact", {})
	var knock: Vector2 = impact.get("knock", Vector2.RIGHT)
	_side = -1.0 if knock.x < 0.0 else 1.0
	_wobble_age = 0.0


func _process(delta: float) -> void:
	if _wobble_age < 0.0 or visual == null:
		return
	_wobble_age += delta
	var amplitude := WOBBLE_AMPLITUDE * exp(-WOBBLE_DECAY * _wobble_age)
	visual.rotation = 0.0 if amplitude < 0.004 else _side * amplitude * cos(_wobble_age * WOBBLE_RATE)
	if visual.rotation == 0.0:
		_wobble_age = -1.0
