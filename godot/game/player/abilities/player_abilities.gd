extends RefCounted
## The player's ability rules and the running sequence (Phaser `PlayerAbilityService.ts` +
## `PlayerAbilityController.ts` + `PlayerAbilityPresentation.ts`; abilities spec 2). Owned by
## player.gd; a travel builds a new player, so cooldowns reset per world as in Phaser.
##
## A press is refused, in this order: another ability is running ("busy", silent), not learned
## ("Not learned yet"), on cooldown (the dodge silently), action-locked (a swing, the eat clip),
## too little energy ("Low energy"). A sequenced ability (jump, teleport, slam, lash) then spends
## its energy, starts its cooldown from the press, locks actions and runs until its sequence says
## it is done; then actions unlock and the slime idles. Sequence milestones run on the simulation
## clock (`advance`), so hit-stop and menus pause them; Phaser ran them on scene time.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const Definitions := preload("res://game/player/abilities/ability_definitions.gd")
const AbilityTerrain := preload("res://game/player/abilities/ability_terrain.gd")
const JumpSequence := preload("res://game/player/abilities/jump_sequence.gd")
const SlamSequence := preload("res://game/player/abilities/slam_sequence.gd")
const TeleportSequence := preload("res://game/player/abilities/teleport_sequence.gd")
const LashSequence := preload("res://game/player/abilities/lash_sequence.gd")

const CUE_DENIED := &"AbilityDenied"
const TEXT_RISE := 30.0

var _player: Node
var _cooldown_until: Dictionary = {}
var _active_seq: int = 0
var _next_seq: int = 1
var _sequence: RefCounted


func _init(player: Node) -> void:
	_player = player


func is_busy() -> bool:
	return _active_seq != 0


## The running sequence moves the body itself (the lash flight): skip the mover this step.
func owns_body() -> bool:
	return _sequence != null and _sequence.has_method(&"owns_body") and bool(_sequence.call(&"owns_body"))


## `RunState` knows it; the dodge also when player.gd's `dodge_learned` (trial override) is on.
func is_learned(id: StringName) -> bool:
	var run := Services.run()
	if run != null and run.has_learned_ability(String(id)):
		return true
	return id == Definitions.DODGE and bool(_player.get(&"dodge_learned"))


## `PlayerAbilityService.rejection`: "" when the ability may start.
func rejection(id: StringName) -> String:
	if is_busy():
		return "busy"
	if not is_learned(id):
		return "locked"
	if Services.now_ms() < float(_cooldown_until.get(id, 0.0)):
		return "cooldown"
	if bool(_player.call(&"is_action_locked")):
		return "action-locked"
	if float(_player.call(&"get_energy")) < Definitions.energy_cost(id):
		return "energy"
	return ""


## The dodge (`tryInstant`): rules, energy (0), cooldown from now. The roll itself is player.gd's.
func try_instant(id: StringName) -> bool:
	var reason := rejection(id)
	if not reason.is_empty():
		if reason != "cooldown":
			notify_rejected(id, reason)
		return false
	if not _spend(id):
		notify_rejected(id, "energy")
		return false
	_cooldown_until[id] = Services.now_ms() + Definitions.cooldown_ms(id, Services.constants())
	return true


## `tryBegin` for jump, teleport, squash-slam and stretch-lash. `request` = {"position" (old
## centre), "direction" (movement keys for the jump, else the aim or facing), "facing", "reach"?}.
## True when the sequence started.
func try_begin(id: StringName, request: Dictionary) -> bool:
	var reason := rejection(id)
	if not reason.is_empty():
		notify_rejected(id, reason)
		return false
	var position: Vector2 = request["position"]
	var raw: Vector2 = request.get("direction", Vector2.ZERO)
	var facing: Vector2 = request.get("facing", Vector2.ZERO)
	var direction := raw.normalized() if raw != Vector2.ZERO else facing.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT if id == Definitions.STRETCH_LASH else Vector2.UP
	var target := position
	var definition := Definitions.entry(id)
	if id == Definitions.JUMP and raw != Vector2.ZERO:
		target = AbilityTerrain.trace(position, direction, float(definition["distance"]), true)
	elif id == Definitions.TELEPORT:
		var reach := float(definition["distance"])
		var asked: Variant = request.get("reach")
		if (asked is float or asked is int) and is_finite(float(asked)):
			reach = minf(reach, maxf(0.0, float(asked)))
		var landing: Variant = AbilityTerrain.safe_landing(position, direction, reach, _player.call(&"body_rids"))
		if landing == null:
			notify_rejected(id, "blocked")
			return false
		target = landing
	if not _spend(id):
		notify_rejected(id, "energy")
		return false
	var seq := _next_seq
	_next_seq += 1
	var now := Services.now_ms()
	_cooldown_until[id] = now + Definitions.cooldown_ms(id, Services.constants())
	_active_seq = seq
	_player.call(&"set_action_locked", true)
	var intent := {"id": id, "seq": seq, "direction": direction, "start": position, "target": target,
		"definition": definition}
	_sequence = _make_sequence(id)
	if _sequence == null:
		complete(seq)
		return true
	_sequence.call(&"begin", _player, intent, now)
	return true


## Runs the active sequence's milestones; completes it when it is done.
func advance(now_ms: float) -> void:
	if _sequence == null:
		return
	if bool(_sequence.call(&"advance", now_ms)):
		complete(_active_seq)


## The sequence finished: unlock and idle (refused while dead or inside the knockback window).
func complete(seq: int) -> void:
	if seq != _active_seq or _active_seq == 0:
		return
	_active_seq = 0
	_sequence = null
	_player.call(&"set_action_locked", false)
	_player.call(&"play_animation", "idle")


## Stops the running sequence without the idle (teardown), resetting the visual.
func cancel() -> void:
	if _sequence != null:
		_sequence.call(&"cancel")
	_sequence = null
	if _active_seq != 0:
		_active_seq = 0
		_player.call(&"set_action_locked", false)


## `PlayerAbilityController.status` (camelCase keys, for the ability bar).
func status(id: StringName) -> Dictionary:
	var unlocked := is_learned(id)
	var remaining := maxf(0.0, float(_cooldown_until.get(id, 0.0)) - Services.now_ms())
	var busy := is_busy()
	var locked := bool(_player.call(&"is_action_locked"))
	var poor := float(_player.call(&"get_energy")) < Definitions.energy_cost(id)
	return {
		"unlocked": unlocked,
		"earnedBy": str(Definitions.entry(id).get("earned_by", "")),
		"cooldownRemainingMs": remaining,
		"busy": busy,
		"actionLocked": locked,
		"insufficientEnergy": poor,
		"canActivate": unlocked and remaining == 0.0 and not busy and not locked and not poor,
	}


## Cooldown end (simulation ms) of `id`; 0 when it never ran.
func cooldown_until(id: StringName) -> float:
	return float(_cooldown_until.get(id, 0.0))


## Rejection feedback: the AbilityDenied cue for everything but "busy"; texts for locked, energy
## and blocked at the centre - 30.
func notify_rejected(_id: StringName, reason: String) -> void:
	if reason == "busy":
		return
	var feel := Services.feel()
	if feel == null:
		return
	feel.audio_cue(CUE_DENIED)
	if Definitions.REJECTION_TEXT.has(reason):
		var text: Array = Definitions.REJECTION_TEXT[reason]
		var centre: Vector2 = _player.call(&"get_centre")
		feel.floating_text(centre - Vector2(0.0, TEXT_RISE), str(text[0]), text[1], false)


func _spend(id: StringName) -> bool:
	var cost := Definitions.energy_cost(id)
	return cost <= 0.0 or bool(_player.call(&"spend_energy", cost))


func _make_sequence(id: StringName) -> RefCounted:
	match id:
		Definitions.JUMP:
			return JumpSequence.new()
		Definitions.SQUASH_SLAM:
			return SlamSequence.new()
		Definitions.TELEPORT:
			return TeleportSequence.new()
		Definitions.STRETCH_LASH:
			return LashSequence.new()
	return null
