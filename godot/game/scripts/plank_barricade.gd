extends StaticBody2D
class_name PlankBarricadeScript
## Scene script `game.plank-barricade` (`object.plank-barricade`, game/scenes/objects/plank-barricade.tscn;
## Fatty's Lair, docs/godot/DUNGEONS.md "Fatty's Lair (built)"): grey old planks nailed across a
## doorway, the Heavy Roll's lock (the look book: old, grey, dead built wood lying or leaning in the
## way). It is the Heavy skin's first lock, Fatty's Lair's way out (question 132), and the
## Quartermaster's store in the Gatehouse shows the same lock before the Pearl.
##
## - It blocks as a wall, so a Roll into it bonks. A Heavy Roll's bonk (game/fattys_lair/heavy_check.gd:
##   the Stone form's `heavy` bonk, or any Roll once Pearl 1 granted the Heavy skin) smashes it: the
##   splintered planks lie in a heap that no longer collides, the screen shakes hard, dust flies, and
##   the story flag `flag_id` keeps it smashed (read when the scene is built).
## - Anything else (a plain Roll, the Spear, a throw, a bomb) is refused with `refusal_text`, the
##   clink, at most every REFUSAL_EVERY_MS.
##
## Owner: dungeons (Fatty's Lair).

const Services := preload("res://game/shared/services.gd")
const HeavyCheck := preload("res://game/fattys_lair/heavy_check.gd")

const GROUP := &"plank_barricade"
const RULE := {"priority": 0, "damageMultiplier": 1}
## No `resource` tag: the Roll's bonk (AbilityWorld.strike_area) skips resources.
const TAGS: Array[String] = []
const FRAME_WHOLE := 0
const FRAME_SMASHED := 1
const CUE_SMASH := &"BreakWood"
const CUE_REFUSED := &"HitBlocked"
const SMASH_TEXT := "Smashed!"
const DUST := &"dodge-dust"
const SPLINTERS := &"hit-spark"
const REFUSAL_EVERY_MS := 1800
const REFUSAL_RISE := 150.0
## The heap lies flat under the bodies.
const HEAP_Z := -1

## Smashed. Payload: {"flagId"}.
signal smashed(payload: Dictionary)
## Refused a hit. Payload: {"weaponId"}.
signal refused(payload: Dictionary)

## Story flag set when it is smashed.
@export var flag_id: String = ""
@export var refusal_text: String = "Old planks, nailed fast. Something heavier could smash through."
## The hard shake of the smash (ms, intensity).
@export var shake_ms: float = 450.0
@export var shake_intensity: float = 0.014

var _smashed := false
var _registered: Area2D
var _next_refusal_ms := 0


func _enter_tree() -> void:
	add_to_group(GROUP)
	var run := Services.run()
	_smashed = not flag_id.is_empty() and run != null and run.has_flag(flag_id)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if _smashed:
		_lie_smashed()
		return
	var area := get_node_or_null(^"DamageArea") as Area2D
	var router := Services.router()
	if router != null and area != null:
		router.register_area(area, self, RULE, TAGS)
		_registered = area


func _exit_tree() -> void:
	var router := Services.router()
	if _registered != null and router != null:
		router.unregister_area(_registered)
	_registered = null


func is_smashed() -> bool:
	return _smashed


## The smash: the heap, the flag, the hard shake.
func smash() -> void:
	if _smashed:
		return
	_smashed = true
	var run := Services.run()
	if run != null and not flag_id.is_empty():
		run.set_flag(flag_id)
	_lie_smashed()
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_SMASH)
		feel.shake(shake_ms, shake_intensity)
		feel.particles(DUST, global_position + Vector2(-30.0, -10.0))
		feel.particles(DUST, global_position + Vector2(30.0, -10.0))
		feel.particles(SPLINTERS, global_position - Vector2(0.0, 40.0))
		feel.floating_text(global_position - Vector2(0.0, 120.0), SMASH_TEXT, &"yellow", true)
	smashed.emit({"flagId": flag_id})


func _lie_smashed() -> void:
	var visual := get_node_or_null(^"Visual") as Sprite2D
	if visual != null:
		visual.frame = FRAME_SMASHED
		visual.z_as_relative = false
		visual.z_index = HEAP_Z
	set_deferred(&"collision_layer", 0)
	for child: Node in get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred(&"disabled", true)
	var router := Services.router()
	if _registered != null and router != null:
		router.unregister_area(_registered)
	_registered = null


func refuse(weapon_id: String) -> void:
	refused.emit({"weaponId": weapon_id})
	var now := Time.get_ticks_msec()
	if now < _next_refusal_ms:
		return
	_next_refusal_ms = now + REFUSAL_EVERY_MS
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_REFUSED)
		feel.floating_text(global_position - Vector2(0.0, REFUSAL_RISE), refusal_text, &"white", false, 2400.0)


# --- damage receiver (DamageRouter) -----------------------------------------------------------------

func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": _smashed}


func can_receive_damage(input: Dictionary) -> Dictionary:
	var request: Dictionary = input.get("request", {})
	if _smashed:
		return {"accepted": false, "reason": "pass"}
	if HeavyCheck.is_heavy_roll(request):
		return {"accepted": true, "reason": ""}
	refuse(str(request.get("weapon_id", "")))
	return {"accepted": false, "reason": "immune"}


func mitigate_damage(_input: Dictionary) -> float:
	return 1.0


func commit_damage(_commit: Dictionary) -> void:
	smash()


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass
