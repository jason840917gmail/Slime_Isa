extends "res://game/scripts/enemy.gd"
class_name FattyScript
## Scene script `game.fatty` (Phaser `features/scripts/FattyScript.ts`): Fatty One Eye, the
## level-1 boss. Implements docs/godot/specs/boss.md section 3.
##
## Extends the base enemy as FattyScript extends EnemyScript: every step runs the whole base step
## first (AI, arena leash, the common melee), then the phase machine below in `_after_enemy_step`,
## then the body moves once. Phases: chase, return-to-center, contact-hop, small-hop, airborne,
## landing, recovery, dead; every transition emits `phase_changed({phase, time})`, which the
## scene wires to its hop / leap / fall / land / recover / death sounds.
##
## Node: `FattyScript` under the `FattyOneEye` CharacterBody2D (feet origin, `depth_anchor
## (0, 42)`). All points are old Phaser positions (`get_centre()` = feet - (0, 42)).
## Spawned by `game.boss-camp` (res://game/scripts/boss_camp.gd), which hands it its arena.
##
## Owner: boss port.

const AttackTelegraph := preload("res://game/bosses/attack_telegraph.gd")

const PHASE_CHASE := "chase"
const PHASE_RETURN := "return-to-center"
const PHASE_CONTACT_HOP := "contact-hop"
const PHASE_SMALL_HOP := "small-hop"
const PHASE_AIRBORNE := "airborne"
const PHASE_LANDING := "landing"
const PHASE_RECOVERY := "recovery"
const PHASE_DEAD := "dead"
## Clips (characters/fatty-one-eye.scene.json).
const CLIP_CHASE := "chase"
const CLIP_CONTACT_HOP := "contact-hop"
const CLIP_SMALL_HOP := "small-hop"
const CLIP_AIRBORNE := "airborne"
const CLIP_LANDING := "landing"
const CLIP_RECOVERY := "recovery"
const CLIP_DEATH := "death"
## FattyScript.ts:107: the landing phase lasts 360 ms (the length of the `landing` clip).
const LANDING_PHASE_MS := 360.0
## Bosses are hit as enemies and bosses (UniversalSceneWorldController.ts:2199-2201).
const BOSS_RECEIVER_TAGS: Array[String] = ["enemy", "boss"]
const STATE_BLOCKED_REASON := "state-blocked"

## JSON `contactAttack`: the contact-hop area (its shapes decide reach and the hop telegraph).
@export var contact_attack: Area2D
## JSON `landingZone`: the leap splash area (telegraph while airborne, damage on landing).
@export var landing_zone: Area2D
## JSON `contactHopCooldownMs` (1000).
@export var contact_hop_cooldown_ms: float = 1000.0
## JSON `contactHopDurationMs` (300).
@export var contact_hop_duration_ms: float = 300.0
## JSON `leapCadenceMs` (5000): from spawn, and from the end of each recovery, to the next leap.
@export var leap_cadence_ms: float = 5000.0
## JSON `smallHopCount` (3).
@export var small_hop_count: float = 3.0
## JSON `smallHopDurationMs` (260).
@export var small_hop_duration_ms: float = 260.0
## JSON `betweenHopsMs` (100).
@export var between_hops_ms: float = 100.0
## JSON `airTimeMs` (1000).
@export var air_time_ms: float = 1000.0
## JSON `recoveryMs` (700).
@export var recovery_ms: float = 700.0
## JSON `landingDamage` (32).
@export var landing_damage: float = 32.0
## JSON `landingKnockbackStrength` (280).
@export var landing_knockback_strength: float = 280.0
## JSON `landingEffectId` ("boss-ground-crack"; "" = none): played on landing and after each hop.
@export var landing_effect_id: String = ""
## JSON `landingShakeMs` (100).
@export var landing_shake_ms: float = 100.0
## JSON `landingShakeIntensity` (0.003).
@export var landing_shake_intensity: float = 0.003

## Payload {"phase": String, "time": float (Services.now_ms())}.
signal phase_changed(payload: Dictionary)

var _phase: String = PHASE_CHASE
var _phase_started_at: float = 0.0
var _next_contact_hop_at: float = 0.0
var _next_leap_at: float = 0.0
var _leap_from: Vector2 = Vector2.ZERO
var _leap_target: Vector2 = Vector2.ZERO
## The body's authored collision layer and mask, restored when collision comes back on.
var _body_layer: int = 0
var _body_mask: int = 0


## Base `_ready` (hurtbox registered with tags enemy + boss), then the first leap at
## now + leap_cadence_ms (FattyScript.ts:45-48); warms the landing effect scene.
func _ready() -> void:
	super()
	if body != null:
		_body_layer = body.collision_layer
		_body_mask = body.collision_mask
	_next_leap_at = Services.now_ms() + maxf(1.0, leap_cadence_ms)
	var world := Services.world()
	if world != null and not landing_effect_id.is_empty():
		world.packed_scene("effect." + landing_effect_id)


## Clears the telegraph, then the base exit (FattyScript.ts:198-201).
func _exit_tree() -> void:
	AttackTelegraph.clear_for(self)
	super()


## The current phase ("chase", "return-to-center", "contact-hop", "small-hop", "airborne",
## "landing", "recovery", "dead").
func get_phase() -> String:
	return _phase


## Gameplay time the current phase started.
func get_phase_started_at() -> float:
	return _phase_started_at


## Where the current (or last) leap started and lands (old Phaser positions).
func get_leap_from() -> Vector2:
	return _leap_from


func get_leap_target() -> Vector2:
	return _leap_target


## Gameplay time of the next leap (checked only while chasing and not mid-attack).
func get_next_leap_at() -> float:
	return _next_leap_at


## Boss spec 3.2 (FattyScript.ts:52-115), after the base step and before the body moves.
func _after_enemy_step(_delta: float) -> void:
	if is_defeated() or _phase == PHASE_DEAD or body == null:
		return
	var now := Services.now_ms()
	# The arena leash itself lives in the base step; Fatty only mirrors it as a phase.
	if _phase == PHASE_CHASE:
		if is_returning_to_arena():
			_begin_return(now)
			return
		if get_runtime_state() == EnemyAI.STATE_ATTACK:
			if _request_contact_hop(now):
				_play_animation(CLIP_CONTACT_HOP, false)
			return
		if now >= _next_leap_at:
			cancel_attack()
			_begin_leap_telegraph(now)
			body.velocity = Vector2.ZERO
		return
	if _phase == PHASE_RETURN:
		if not is_returning_to_arena():
			_resume_chase(now)
		return

	body.velocity = Vector2.ZERO
	match _phase:
		PHASE_CONTACT_HOP:
			if _elapsed(now) >= maxf(1.0, contact_hop_duration_ms):
				AttackTelegraph.clear_for(self)
				_spawn_effect_at(landing_effect_id, get_centre())
				_resume_chase(now)
		PHASE_SMALL_HOP:
			var hop_cycle := maxf(1.0, small_hop_duration_ms + between_hops_ms)
			if _elapsed(now) >= hop_cycle * maxf(1.0, small_hop_count):
				_begin_airborne(now)
		PHASE_AIRBORNE:
			var progress := minf(1.0, _elapsed(now) / maxf(1.0, air_time_ms))
			FeetAnchor.place_at_phaser_position(body, _leap_from + (_leap_target - _leap_from) * progress)
			if progress >= 1.0:
				_land(now)
		PHASE_LANDING:
			if _elapsed(now) >= LANDING_PHASE_MS:
				_begin_recovery(now)
		PHASE_RECOVERY:
			if _elapsed(now) >= maxf(1.0, recovery_ms):
				_next_leap_at = now + maxf(1.0, leap_cadence_ms)
				_resume_chase(now)


# --- damage receiver (FattyScript.ts:19-43, 203-210) -----------------------------------------------

## Airborne and contact-hop phases reject hits as "state-blocked" (retryable); else the base rule.
func can_receive_damage(input: Dictionary) -> Dictionary:
	if _phase == PHASE_AIRBORNE or _phase == PHASE_CONTACT_HOP:
		return {"accepted": false, "reason": STATE_BLOCKED_REASON}
	return super(input)


## Bosses keep their phase flow: a hit never cancels a phase or stuns. Only while chasing does a
## non-immune knockback shove the body, with the raw potency and no resistance (legacy boss rule).
func _react_to_damage(commit: Dictionary, is_dead: bool) -> void:
	_show_hit_feedback(commit)
	if is_dead or _phase != PHASE_CHASE or body == null:
		return
	var result: Dictionary = commit.get("result", {})
	var potency := 0.0
	for effect: Variant in result.get("applied_effects", []):
		if effect is Dictionary and str((effect as Dictionary).get("effect_id", "")) == KNOCKBACK_EFFECT_ID:
			potency += float((effect as Dictionary).get("potency", 0.0))
	var request: Dictionary = commit.get("request", {})
	var impact: Dictionary = request.get("impact", {})
	var knock: Vector2 = impact.get("knock", Vector2.ZERO)
	if potency <= 0.0 or knock.length() == 0.0:
		return
	body.velocity = knock.normalized() * potency


## Clears the telegraph, runs the base defeat, collision off, plays "death", phase dead.
func _defeat() -> void:
	if is_defeated():
		return
	AttackTelegraph.clear_for(self)
	super()
	_set_body_collision(false, true)
	_play_animation(CLIP_DEATH, false)
	_transition_to(PHASE_DEAD, Services.now_ms())


# --- base hooks -------------------------------------------------------------------------------

## The common melee runs only while chasing (FattyScript.ts:212).
func _can_run_common_attack() -> bool:
	return _phase == PHASE_CHASE


## The authored ContactAttack shapes decide when the contact hop starts and whether it connects.
func _attack_area_reach(target: Dictionary) -> Variant:
	return _target_overlaps(AreaShapes.of_area(contact_attack), target)


## Fatty's clips are not directional and its sprite never flips (FattyScript.ts:215).
func _mirrors_side_facing() -> bool:
	return false


func _receiver_tags() -> Array[String]:
	return BOSS_RECEIVER_TAGS


## Bosses are not ordinary enemies, so their damage number rises from their position
## (UniversalSceneWorldController.ts:2039-2045).
func _damage_number_top() -> float:
	return get_centre().y


## Godot deviation (boss spec 4.4): the dead body stays until its `death` clip has played; Phaser
## removes it the step it dies.
func _dispose_delay_ms() -> float:
	return _clip_length_ms(CLIP_DEATH)


# --- phases (FattyScript.ts:117-196) ----------------------------------------------------------------

func _request_contact_hop(now: float) -> bool:
	if is_defeated() or _phase != PHASE_CHASE or now < _next_contact_hop_at:
		return false
	var arena := get_arena()
	if not arena.is_empty() and not BossArena.contains(arena, get_centre()):
		return false
	_transition_to(PHASE_CONTACT_HOP, now)
	_next_contact_hop_at = now + maxf(1.0, contact_hop_cooldown_ms)
	_set_body_collision(false)
	AttackTelegraph.show_for(self, AreaShapes.of_area(contact_attack), get_centre())
	return true


func _begin_leap_telegraph(now: float) -> bool:
	if is_defeated() or _phase != PHASE_CHASE:
		return false
	_transition_to(PHASE_SMALL_HOP, now)
	_play_animation(CLIP_SMALL_HOP, false)
	return true


func _begin_airborne(now: float) -> bool:
	if _phase != PHASE_SMALL_HOP:
		return false
	_leap_from = get_centre()
	var target := _primary_target()
	var aim: Vector2 = target.get("centre", _leap_from) if not target.is_empty() else _leap_from
	var arena := get_arena()
	_leap_target = BossArena.clamp_point(arena, aim) if not arena.is_empty() else aim
	# Warn where the splash will land: the landing zone moved from Fatty onto the target.
	var offset := _leap_target - _leap_from
	AttackTelegraph.show_for(self, AreaShapes.translated(AreaShapes.of_area(landing_zone), offset), _leap_target)
	_set_body_collision(false)
	_transition_to(PHASE_AIRBORNE, now)
	_play_animation(CLIP_AIRBORNE, false)
	return true


func _land(now: float) -> bool:
	if _phase != PHASE_AIRBORNE:
		return false
	_set_body_collision(true)
	_transition_to(PHASE_LANDING, now)
	_play_animation(CLIP_LANDING, false)
	AttackTelegraph.clear_for(self)
	var splash := AreaShapes.of_area(landing_zone)
	var target := _primary_target()
	if not target.is_empty() and bool(target.get("active", false)) and _target_overlaps(splash, target):
		_route_immediate_attack(target, landing_damage, landing_knockback_strength, -1.0, false)
	_spawn_effect_at(landing_effect_id, get_centre())
	_shake_camera(landing_shake_ms, landing_shake_intensity)
	return true


func _begin_recovery(now: float) -> bool:
	if _phase != PHASE_LANDING:
		return false
	_transition_to(PHASE_RECOVERY, now)
	_play_animation(CLIP_RECOVERY, false)
	return true


func _resume_chase(now: float) -> bool:
	if _phase != PHASE_CONTACT_HOP and _phase != PHASE_RECOVERY and _phase != PHASE_RETURN:
		return false
	_set_body_collision(true)
	_transition_to(PHASE_CHASE, now)
	_play_animation(CLIP_CHASE, false)
	return true


func _begin_return(now: float) -> bool:
	if is_defeated() or _phase == PHASE_DEAD:
		return false
	_set_body_collision(true)
	_transition_to(PHASE_RETURN, now)
	_play_animation(CLIP_CHASE, false)
	return true


func _elapsed(now: float) -> float:
	return maxf(0.0, now - _phase_started_at)


func _transition_to(phase: String, now: float) -> void:
	_phase = phase
	_phase_started_at = now
	phase_changed.emit({"phase": phase, "time": now})


## Phaser `collisionEnabled` (the Arcade body is disabled: it neither blocks nor is blocked):
## collision layer and mask 0 when off, the authored ones when on. Deferred when called from a
## damage commit (possibly inside a physics callback).
func _set_body_collision(enabled: bool, deferred: bool = false) -> void:
	if body == null:
		return
	var layer := _body_layer if enabled else 0
	var mask := _body_mask if enabled else 0
	if deferred:
		body.set_deferred(&"collision_layer", layer)
		body.set_deferred(&"collision_mask", mask)
	else:
		body.collision_layer = layer
		body.collision_mask = mask
