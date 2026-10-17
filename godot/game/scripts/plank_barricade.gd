extends StaticBody2D
class_name PlankBarricadeScript
## Scene script `game.plank-barricade`: old wood the Heavy Roll smashes (docs/godot/SKINS.md "Heavy";
## the look book: old, grey, dead or built wood lying or leaning in the way; question 93). Its
## scenes: `object.plank-barricade` (grey old planks nailed across a doorway: the Heavy skin's first
## lock, Fatty's Lair's way out, question 132; the Quartermaster's store in the Gatehouse shows the
## same lock before the Pearl), game/scenes/objects/rotten-timbers.tscn (rotten mine timbers),
## `object.old-trunk` (a flat, mossy, hollow trunk across a path) and `object.old-fence` (a grey,
## broken-backed old fence, never on a rim: question 128). The rocks are rubble_heap.gd's.
##
## - It blocks as a wall, so a Roll into it bonks. A Heavy Roll's bonk (the Heavy skin on:
##   game/fattys_lair/heavy_check.gd) smashes it: the splinters lie in a heap that no longer
##   collides, the screen shakes hard, dust flies, the slime shows its Heavy skin, and the story flag
##   `flag_id` keeps it smashed (read when the scene is built).
## - Anything else (a plain Roll, the Spear, a throw, a bomb) is refused with `refusal_text`, the
##   clink, at most every REFUSAL_EVERY_MS.
##
## Owner: dungeons (Fatty's Lair).

const Services := preload("res://game/shared/services.gd")
const HeavyCheck := preload("res://game/fattys_lair/heavy_check.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")

const GROUP := &"plank_barricade"
const RULE := {"priority": 0, "damageMultiplier": 1}
## No `resource` tag: the Roll's bonk (AbilityWorld.strike_area) skips resources.
const TAGS: Array[String] = []
const FRAME_WHOLE := 0
const FRAME_SMASHED := 1
const CUE_REFUSED := &"HitBlocked"
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
@export var smash_text: String = "Smashed!"
@export var smash_cue: StringName = &"BreakWood"
## Where the splinters fly from, above the root (world units).
@export var splinter_rise: float = 40.0
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
		feel.audio_cue(smash_cue)
		feel.shake(shake_ms, shake_intensity)
		feel.particles(DUST, global_position + Vector2(-30.0, -10.0))
		feel.particles(DUST, global_position + Vector2(30.0, -10.0))
		feel.particles(SPLINTERS, global_position - Vector2(0.0, splinter_rise))
		feel.floating_text(global_position - Vector2(0.0, splinter_rise + 80.0), smash_text, &"yellow", true)
	var world := Services.world()
	SkinState.show(world.player if world != null else null, SkinState.HEAVY)
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
