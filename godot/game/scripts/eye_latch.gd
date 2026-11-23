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
##   good too once it is shut; `open_ms` matters with a group. In its last WARN_MS a timed latch's
##   eye flickers.
## - **In order** (`order` > 0, 2026-10-19, R5's north maze): the latches of a group are struck in
##   their order (1, 2, 3 ...). Struck while a latch of the group with a lower order is still
##   open, it clinks (`order_text`) and every latch of the group already shut opens again: the run
##   starts over. When a latch opens again (its time ran out), every later one of its group opens
##   too, so the first latch's `open_ms` is the whole run's time. Solved, each latch opens its own
##   `gate_id` (and its `more_gate_ids`): the gates sink together. The run is the group's latches
##   standing in the world now, however many the scene holds: R5's maze has two since 2026-11-21
##   (owner: eye III taken out; eye II also opens the inner door, `more_gate_ids`).
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
## A timed latch's eye flickers this long before it opens again, this fast.
const WARN_MS := 1500.0
const WARN_FLICKER_MS := 90.0
const WARN_ALPHA := 0.35

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
## More gates it opens with `gate_id` (their own ids kept: a gate whose eye was taken out, R5's inner
## door).
@export var more_gate_ids: PackedStringArray = PackedStringArray()
## Latches that must all be shut at once ("" = alone).
@export var group_id: String = ""
## How long a thrust keeps it shut (ms, gameplay time); 0 = for good.
@export var open_ms: float = 0.0
## Its place in its group's order (1 first); 0 = any time.
@export var order: int = 0
@export var refusal_text: String = "It stares on. Only a sharp point would reach the pupil."
## Said when it is struck out of its group's order.
@export var order_text: String = "The eye snaps open again. Another eye comes first."
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
	var held := Services.now_ms() - _shut_at_ms
	if held < open_ms:
		# the last WARN_MS: the eye flickers (presentation, on real time)
		if visual != null:
			var flicker := open_ms - held < WARN_MS and int(Time.get_ticks_msec() / WARN_FLICKER_MS) % 2 == 0
			visual.modulate.a = WARN_ALPHA if flicker else 1.0
		return
	reopen()


## Its eye opens again (its time ran out, or its group's run broke); in an ordered group every later
## latch of the group opens with it (quietly: one sound for the run).
func reopen(sound: bool = true) -> void:
	if not _shut or _solved:
		return
	_shut = false
	_show()
	var feel := Services.feel()
	if feel != null and sound:
		feel.audio_cue(CUE_REOPEN)
	reopened.emit({"latchId": latch_id})
	if order > 0 and not group_id.is_empty():
		for latch: Node in _group():
			if latch != self and int(latch.get(&"order")) > order:
				latch.call(&"reopen", false)


## True when a latch of its ordered group comes before it and is still open.
func _out_of_order() -> bool:
	if order <= 0 or group_id.is_empty():
		return false
	for latch: Node in _group():
		var before := int(latch.get(&"order"))
		if latch != self and before > 0 and before < order and not bool(latch.call(&"is_shut")):
			return true
	return false


## Struck out of order: it stays open, every latch of its group already shut opens again.
func _break_run() -> void:
	for latch: Node in _group():
		if latch != self:
			latch.call(&"reopen", false)
	_say(order_text)


## A thrust landed: it shuts; alone (or with its whole group shut) its gate opens for good. Out of
## its group's order it clinks and the group's run starts over (`_break_run`).
func strike() -> void:
	if _solved:
		return
	if _out_of_order():
		_break_run()
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
	var opens := PackedStringArray(more_gate_ids)
	if not gate_id.is_empty():
		opens.append(gate_id)
	for gate: Node in get_tree().get_nodes_in_group(GATE_GROUP):
		var id := str(gate.get(&"gate_id"))
		if not id.is_empty() and opens.has(id) and not bool(gate.call(&"is_open")):
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
		visual.modulate.a = 1.0


func refuse(weapon_id: String) -> void:
	refused.emit({"latchId": latch_id, "weaponId": weapon_id})
	_say(refusal_text)


## The clink and `text` over it (at most every REFUSAL_EVERY_MS).
func _say(text: String) -> void:
	var now := Time.get_ticks_msec()
	if now < _next_refusal_ms:
		return
	_next_refusal_ms = now + REFUSAL_EVERY_MS
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(CUE_REFUSED)
		feel.floating_text(global_position - Vector2(0.0, REFUSAL_RISE), text, &"white", false, 2200.0)


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
