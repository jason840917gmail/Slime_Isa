extends Node2D
class_name EyeLatchScript
## Scene script `game.eye-latch` (`object.eye-latch`, game/scenes/objects/eye-latch.tscn; Fatty's
## Lair, docs/godot/DUNGEONS.md "Fatty's Lair (built)"): a stone eye latch, the Spear's lock (the
## secrets table: "a thrust to the stone pupil opens the door"; an eye is always the Spear's or an
## enemy's, question 127). A carved stone eye on a plaque set in a wall over a door, its pupil
## glowing amber while it watches (frame 0); a Spear thrust to it shuts it (frame 1) and opens its
## gate.
##
## - **The node** stands at the wall's foot under the plaque: the hurtbox (`area`) is there, where a
##   thrust from the floor reaches, and the picture hangs `plaque_rise` higher on the wall.
## - **Only the Spear** (a hit tagged `spear`, the Spear shape's tags) shuts it; anything else (a
##   thrown pot, the Roll, a bomb) clinks off with `refusal_text`. Tagged `resource`, so a throw's
##   blast never reaches it and it plays no enemy feel. A screen (a pillar in front of it, part of
##   the room) is what makes a latch "screened": only a diagonal thrust gets past it.
## - **Alone, for good** (`open_ms` 0, no `group_id`): shut, it opens every gate with `gate_id`
##   for good (`open_for_good`) and stays shut: the story flag SOLVED_FLAG_PREFIX + `latch_id`.
## - **Timed** (`open_ms` > 0): it stays shut that long, then opens its eye again. Latches sharing a
##   `group_id` solve their gate only while all of them are shut at once: then all stay shut for
##   good and the gate opens for good (each latch's flag set). A timed latch alone opens its gate for
##   good too once it is shut; `open_ms` matters with a group.
##
## Owner: dungeons (Fatty's Lair).

const Services := preload("res://game/shared/services.gd")

const GROUP := &"eye_latch"
const GATE_GROUP := &"gate"
const SPEAR_TAG := "spear"
const RULE := {"priority": 0, "damageMultiplier": 1}
const TAGS: Array[String] = ["resource"]
const SOLVED_FLAG_PREFIX := "eye-latch."
const FRAME_WATCHING := 0
const FRAME_SHUT := 1
const CUE_SHUT := &"GateUnlock"
const CUE_SOLVED := &"SecretFound"
const CUE_REOPEN := &"HitBlocked"
const CUE_REFUSED := &"HitBlocked"
const SPARKLE := &"loot-sparkle"
const REFUSAL_EVERY_MS := 1500
const REFUSAL_RISE := 40.0

## Shut by a thrust. Payload: {"latchId", "groupId"}.
signal shut(payload: Dictionary)
## Its eye opened again (a timed latch ran out). Payload: {"latchId"}.
signal reopened(payload: Dictionary)
## Its gate opened for good. Payload: {"latchId", "gateId", "groupId"}.
signal solved(payload: Dictionary)
## A wrong tool clinked off it. Payload: {"latchId", "weaponId"}.
signal refused(payload: Dictionary)

## Its id (its flag: SOLVED_FLAG_PREFIX + latch_id; ids are unique across the game).
@export var latch_id: String = ""
## The gates it opens (game/scripts/gate.gd `gate_id`).
@export var gate_id: String = ""
## Latches that must all be shut at once ("" = alone).
@export var group_id: String = ""
## How long a thrust keeps it shut (ms, gameplay time); 0 = for good.
@export var open_ms: float = 0.0
@export var refusal_text: String = "It stares on. Only a sharp point would reach the pupil."
## The hurtbox a thrust must reach.
@export var area: Area2D
## The plaque's picture (2 frames: watching, shut).
@export var visual: Sprite2D

var _shut := false
var _solved := false
var _shut_at_ms := 0.0
var _registered: Area2D
var _next_refusal_ms := 0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var router := Services.router()
	if router != null and area != null:
		router.register_area(area, self, RULE, TAGS)
		_registered = area
	var run := Services.run()
	if run != null and not latch_id.is_empty() and run.has_flag(SOLVED_FLAG_PREFIX + latch_id):
		_solved = true
		_shut = true
	_show()


func _exit_tree() -> void:
	var router := Services.router()
	if _registered != null and router != null:
		router.unregister_area(_registered)
	_registered = null


func is_shut() -> bool:
	return _shut


func is_solved() -> bool:
	return _solved


func _physics_process(_delta: float) -> void:
	if not _shut or _solved or open_ms <= 0.0:
		return
	if Services.now_ms() - _shut_at_ms < open_ms:
		return
	_shut = false
	_show()
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_REOPEN)
	reopened.emit({"latchId": latch_id})


## A thrust landed: it shuts; alone (or with its whole group shut) its gate opens for good.
func strike() -> void:
	if _solved:
		return
	_shut = true
	_shut_at_ms = Services.now_ms()
	_show()
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_SHUT)
		feel.particles(SPARKLE, global_position - Vector2(0.0, 30.0))
	shut.emit({"latchId": latch_id, "groupId": group_id})
	if group_id.is_empty():
		_solve()
		return
	var members := _group()
	for latch: Node in members:
		if not bool(latch.call(&"is_shut")):
			return
	for latch: Node in members:
		latch.call(&"_solve")


## Shut for good; its gates open for good. Called on every latch of a solved group.
func _solve() -> void:
	if _solved:
		return
	_solved = true
	_shut = true
	_show()
	var run := Services.run()
	if run != null and not latch_id.is_empty():
		run.set_flag(SOLVED_FLAG_PREFIX + latch_id)
	if not gate_id.is_empty():
		for gate: Node in get_tree().get_nodes_in_group(GATE_GROUP):
			if str(gate.get(&"gate_id")) == gate_id and not bool(gate.call(&"is_open")):
				gate.call(&"open_for_good" if gate.has_method(&"open_for_good") else &"open")
	var feel := Services.feel()
	if feel != null and _is_group_leader():
		feel.audio_cue(CUE_SOLVED)
	solved.emit({"latchId": latch_id, "gateId": gate_id, "groupId": group_id})


func _is_group_leader() -> bool:
	if group_id.is_empty():
		return true
	var members := _group()
	return members.is_empty() or members[0] == self


func _group() -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if str(node.get(&"group_id")) == group_id:
			out.append(node)
	return out


func _show() -> void:
	if visual != null:
		visual.frame = FRAME_SHUT if _shut else FRAME_WATCHING


func refuse(weapon_id: String) -> void:
	refused.emit({"latchId": latch_id, "weaponId": weapon_id})
	var now := Time.get_ticks_msec()
	if now < _next_refusal_ms:
		return
	_next_refusal_ms = now + REFUSAL_EVERY_MS
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_REFUSED)
		feel.floating_text(global_position - Vector2(0.0, REFUSAL_RISE), refusal_text, &"white", false, 2200.0)


# --- damage receiver (DamageRouter) -----------------------------------------------------------------

func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": _shut}


func can_receive_damage(input: Dictionary) -> Dictionary:
	var request: Dictionary = input.get("request", {})
	if _shut:
		return {"accepted": false, "reason": "pass"}
	if is_spear(request):
		return {"accepted": true, "reason": ""}
	refuse(str(request.get("weapon_id", "")))
	return {"accepted": false, "reason": "immune"}


## A thrust always lands (a `resource` would otherwise take nothing from a weapon).
func mitigate_damage(_input: Dictionary) -> float:
	return 1.0


func commit_damage(_commit: Dictionary) -> void:
	strike()


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


static func is_spear(request: Dictionary) -> bool:
	var tags: Variant = request.get("weapon_tags", [])
	return tags is Array and (tags as Array).has(SPEAR_TAG)
