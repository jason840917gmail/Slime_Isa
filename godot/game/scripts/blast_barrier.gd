extends RefCounted
## What the Goo Bomb's locks share (bomb-lantern-and-secrets design section 3: cracked walls and
## rubble heaps; game/scripts/cracked_wall.gd, rubble_heap.gd): a hurtbox that refuses every hit
## that is not a blast (it clinks: the resolver's "immune") with a line saying what it needs, and
## the feel of giving way.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const AbilityFx := preload("res://game/player/abilities/ability_fx.gd")

const GROUP := &"blast_targets"
## The hurtbox's rule and tags (no weapon is accepted; the refusal is the receiver's).
const RULE := {"priority": 0, "damageMultiplier": 0}
const TAGS: Array[String] = ["barrier"]
const REASON_IMMUNE := "immune"
const REFUSAL_RISE := 70.0
const REFUSAL_MS := 1800.0
## One refusal line every this long for all barriers (real time, as the cracked ground's creak).
const REFUSAL_INTERVAL_MS := 1500.0
const BREAK_RISE := 80.0
const BREAK_MS := 1800.0
const CUE_BREAK := &"BarrierBreak"
const BREAK_FALLBACK_CUE := &"GroundCrack"
## The "secret found" jingle (owner, 2026-10-14) when a barrier opens; GateOpen until its take is in
## the global audio scene.
const CUE_SECRET := &"SecretFound"
const SECRET_FALLBACK_CUE := &"GateOpen"

static var _next_refusal_ms: float = 0.0


## Registers `area` with DamageRouter for `receiver` (a barrier: get_damage_state, can_receive_damage).
static func register(area: Area2D, receiver: Object) -> void:
	var router := Services.router()
	if router != null and area != null:
		router.register_area(area, receiver, RULE, TAGS)


static func unregister(area: Area2D) -> void:
	var router := Services.router()
	if router != null and area != null and is_instance_valid(area):
		router.unregister_area(area)


## The refusal of a weapon, a throw or a slam: the clink's "immune" and, at most every
## REFUSAL_INTERVAL_MS, `text` over `at`.
static func refuse(at: Vector2, text: String) -> Dictionary:
	var now := float(Time.get_ticks_msec())
	if now >= _next_refusal_ms:
		_next_refusal_ms = now + REFUSAL_INTERVAL_MS
		var feel := Services.feel()
		if feel != null and not text.is_empty():
			feel.floating_text(at - Vector2(0.0, REFUSAL_RISE), text, &"orange", false, REFUSAL_MS)
	return {"accepted": false, "reason": REASON_IMMUNE}


## The barrier gives way at `at` (its foot): the line, the break cue and the secret jingle, pebbles
## and dust in `tint`.
static func give_way(at: Vector2, text: String, tint: Color, pebbles: int, puffs: int) -> void:
	AbilityFx.debris(at, tint, pebbles, puffs, 0.6)
	var feel := Services.feel()
	if feel == null:
		return
	var root: Node = feel.global_audio()
	feel.audio_cue(CUE_BREAK if root != null and root.find_child(String(CUE_BREAK), true, false) != null else BREAK_FALLBACK_CUE)
	feel.audio_cue(CUE_SECRET if root != null and root.find_child(String(CUE_SECRET), true, false) != null else SECRET_FALLBACK_CUE)
	if not text.is_empty():
		feel.floating_text(at - Vector2(0.0, BREAK_RISE), text, &"yellow", true, BREAK_MS)
