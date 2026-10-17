extends StaticBody2D
## Scene script of `object.rubble-heap` and `object.loose-rock` (game/scenes/objects/rubble-heap.tscn,
## loose-rock.tscn; docs/godot/SKINS.md "Heavy"): old rocks lying across the way, the Heavy Roll's
## lock (the look book: big, grey and old, lying across the way, never the Gulp's small loose light
## things; owner, 2026-10-16, questions 77 and 128: rubble heaps break under a Heavy Roll instead of
## a Goo Bomb). A heap (asset/abilities/goo-bomb/rubble-2x1.webp: heap | scatter, 224 x 160 each,
## drawn at half size) or one big loose rock (asset/MAPS/props/heavy-skin/loose-rock-2x1.webp:
## rock | rubble). It blocks as a wall, so a Roll into it bonks.
##
## - **A Heavy Roll's bonk** (the Heavy skin on: game/fattys_lair/heavy_check.gd) scatters it: the
##   rubble left on the ground no longer collides, the screen shakes hard, the story flag `flag_id`
##   keeps it broken (read at load: gone for good; a story variant on the same flag can show a
##   prize), and the slime shows its Heavy skin.
## - Anything else (a plain Roll, the Spear, a throw, a blast) clinks off with `refusal_text`.
## - `breaks_by_blast` (the playground Bomb corner's islet heap only, until question 72's cracked
##   rock face is built there): the old Goo Bomb heap instead, broken only by a blast whose ellipse
##   holds its root (`receive_blast`; group `blast_targets`).
##
## Owner: skins (the Heavy Roll); the islet's blast heap: abilities.

const Services := preload("res://game/shared/services.gd")
const BlastBarrier := preload("res://game/scripts/blast_barrier.gd")
const HeavyCheck := preload("res://game/fattys_lair/heavy_check.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")

const FRAME_HEAP := 0
const FRAME_SCATTER := 1
## The scatter lies flat under the bodies.
const SCATTER_Z := -1
## The Heavy Roll's hurtbox rule (the Roll's bonk is accepted: `commit_damage` breaks it).
const ROLL_RULE := {"priority": 0, "damageMultiplier": 1}
const TAGS: Array[String] = ["barrier"]
const CUE_BREAK := &"BreakStone"

## Broken. Payload: {"flagId", "by": "roll" | "blast"}.
signal broken(payload: Dictionary)

## Story flag set when it breaks.
@export var flag_id: String = ""
@export var refusal_text: String = "Old rocks piled across the way. A heavier roll would scatter them."
@export var break_text: String = "The rocks fly apart!"
## The pebbles' and the dust's colour as it breaks.
@export var rock_tint: Color = Color("#8f8a80")
## The old Goo Bomb heap: only a blast breaks it (the Bomb corner's islet).
@export var breaks_by_blast: bool = false
## The hard shake of the break (ms, intensity).
@export var shake_ms: float = 380.0
@export var shake_intensity: float = 0.016

var _broken: bool = false
var _registered: Area2D


func _enter_tree() -> void:
	if breaks_by_blast:
		add_to_group(BlastBarrier.GROUP)
	var run := Services.run()
	_broken = not flag_id.is_empty() and run != null and run.has_flag(flag_id)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if _broken:
		_scatter()
		return
	var area := get_node_or_null(^"DamageArea") as Area2D
	if breaks_by_blast:
		BlastBarrier.register(area, self)
	else:
		var router := Services.router()
		if router != null and area != null:
			router.register_area(area, self, ROLL_RULE, TAGS)
	_registered = area


func _exit_tree() -> void:
	BlastBarrier.unregister(_registered)
	_registered = null


func is_broken() -> bool:
	return _broken


func blast_point() -> Vector2:
	return global_position


## A Goo Bomb blast (group `blast_targets`): only the blast heap gives way.
func receive_blast(_hit: Dictionary) -> bool:
	if _broken or not breaks_by_blast:
		return false
	_break("blast")
	return true


func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": _broken}


func can_receive_damage(input: Dictionary) -> Dictionary:
	if _broken:
		return {"accepted": false, "reason": "pass"}
	var request: Dictionary = input.get("request", {})
	if not breaks_by_blast and HeavyCheck.is_heavy_roll(request):
		return {"accepted": true, "reason": ""}
	return BlastBarrier.refuse(global_position - Vector2(0.0, 30.0), refusal_text)


func mitigate_damage(_input: Dictionary) -> float:
	return 1.0


func commit_damage(_commit: Dictionary) -> void:
	if not _broken:
		_break("roll")


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


func _break(by: String) -> void:
	_broken = true
	var run := Services.run()
	if run != null and not flag_id.is_empty():
		run.set_flag(flag_id)
	_scatter()
	BlastBarrier.give_way(global_position - Vector2(0.0, 10.0), break_text, rock_tint, 18, 10)
	if by == "roll":
		var feel := Services.feel()
		if feel != null:
			feel.audio_cue(CUE_BREAK)
			feel.shake(shake_ms, shake_intensity)
		var world := Services.world()
		SkinState.show(world.player if world != null else null, SkinState.HEAVY)
	broken.emit({"flagId": flag_id, "by": by})


## The rubble left on the ground: no collision, no hurtbox.
func _scatter() -> void:
	var visual := get_node_or_null(^"Visual") as Sprite2D
	if visual != null:
		visual.frame = FRAME_SCATTER
		visual.z_as_relative = false
		visual.z_index = SCATTER_Z
	set_deferred(&"collision_layer", 0)
	var shape := get_node_or_null(^"BodyShape") as CollisionShape2D
	if shape != null:
		shape.set_deferred(&"disabled", true)
	BlastBarrier.unregister(_registered)
	_registered = null
	var area := get_node_or_null(^"DamageArea") as Area2D
	if area != null:
		area.queue_free()
