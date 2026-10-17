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
@export_group("Phase two (Fatty's Lair)")
## Phase two's settings (used once `configure_phase_two` turns it on; its `config` overrides them):
## the share of his health under which it starts, the second leap's time in the air, the clods a
## landing asks for, the dizzy's length, the mud ripple's hit, shove, speed, crest width and reach.
@export var phase_two_health_share: float = 0.5
@export var phase_two_second_air_time_ms: float = 700.0
@export var phase_two_clods_per_landing: int = 2
@export var phase_two_dizzy_ms: float = 1600.0
@export var phase_two_ripple_damage: float = 18.0
@export var phase_two_ripple_knockback: float = 220.0
@export var phase_two_ripple_speed: float = 300.0
@export var phase_two_ripple_width: float = 30.0
@export var phase_two_ripple_max_radius: float = 560.0
@export_group("")

## Payload {"phase": String, "time": float (Services.now_ms())}.
signal phase_changed(payload: Dictionary)
## Phase two began (Fatty's Lair). Payload {"time"}.
signal phase_two_started(payload: Dictionary)
## A phase-two landing: the lair drops `count` light mud clods (game/fattys_lair/lair_director.gd).
## Payload {"count": int, "at": Vector2 (old Phaser position of the landing), "last": bool}.
signal clods_requested(payload: Dictionary)
## A thrown thing made him dizzy, his eye wide open. Payload {"until": float}.
signal dizzied(payload: Dictionary)

## Phase two (Fatty's Lair; docs/godot/DUNGEONS.md "Fatty's Lair (built)"; the 2026-10-11 dungeons
## plan's second phase and the Lair design's open point 4). Off unless `configure_phase_two` turns
## it on, so the open-world camp's fight stays as specs/boss.md has it. Below `health_share` of his
## health: two leaps in a row (the second with `second_air_time_ms` in the air); his eye squints shut
## (every hit clinks, the Spear's too) except while he is dizzy; each landing asks the lair for
## `clods_per_landing` light mud clods (`clods_requested`); a thrown thing makes him dizzy for
## `dizzy_ms` with his eye wide open (the Spear lands then); and the second landing sends a mud ripple
## over the floor (game/fattys_lair/mud_ripple.gd) that hits for `ripple_damage` where its crest meets
## the slime, unless the Roll's i-frames carry it through.
const PHASE_DIZZY := "dizzy"
const THROWN_TAG := "thrown"
const MudRipple := preload("res://game/fattys_lair/mud_ripple.gd")
## The ripple is a ground ellipse (mud_ripple.gd SQUASH_Y): its crest is measured the same way.
const RIPPLE_SQUASH_Y := 0.5
const DIZZY_TEXT := "Dizzy!"
const DIZZY_TEXT_RISE := 110.0

var _phase: String = PHASE_CHASE
var _phase_started_at: float = 0.0
var _next_contact_hop_at: float = 0.0
var _next_leap_at: float = 0.0
var _leap_from: Vector2 = Vector2.ZERO
var _leap_target: Vector2 = Vector2.ZERO
## The body's authored collision layer and mask, restored when collision comes back on.
var _body_layer: int = 0
var _body_mask: int = 0
## Phase two's settings (the `phase_two_*` exports merged with `configure_phase_two`); {} = off.
var _two: Dictionary = {}
## The authored spear-only rule, kept when the hurtbox also lets thrown things through (classic hits;
## see `_receiver_rule`). Empty when the router keeps no `acceptedSources` (rework mode's gate).
var _spear_rule: Dictionary = {}
var _two_on: bool = false
## Leaps still to come in this leap cycle (phase two leaps twice).
var _leaps_left: int = 0
## The current leap's time in the air.
var _air_ms: float = 1000.0
var _dizzy_until: float = 0.0
var _ripple: Node2D = null
var _ripple_from: Vector2 = Vector2.ZERO
var _ripple_started: float = 0.0
var _ripple_done_with_target: bool = false


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


## Turns phase two on for this fight (`config` overrides the `phase_two_*` exports; see the notes there).
func configure_phase_two(config: Dictionary = {}) -> void:
	_two = {"health_share": phase_two_health_share, "second_air_time_ms": phase_two_second_air_time_ms,
		"clods_per_landing": phase_two_clods_per_landing, "dizzy_ms": phase_two_dizzy_ms,
		"ripple_damage": phase_two_ripple_damage, "ripple_knockback": phase_two_ripple_knockback,
		"ripple_speed": phase_two_ripple_speed, "ripple_width": phase_two_ripple_width,
		"ripple_max_radius": phase_two_ripple_max_radius}
	_two.merge(config, true)


## True once his health fell under phase two's share (with phase two configured).
func is_in_phase_two() -> bool:
	return _two_on


## True while a thrown thing keeps him dizzy (his eye wide open).
func is_dizzy() -> bool:
	return _phase == PHASE_DIZZY


## The mud ripple's crest radius now (0 when none spreads).
func ripple_radius() -> float:
	if _ripple == null or not is_instance_valid(_ripple):
		return 0.0
	return float(_ripple.get(&"radius"))


## Hits the slime when its feet are within `radius` of the ground point `point`: a clod landing on
## it (game/fattys_lair/lair_director.gd). True when it hurt.
func strike_at(point: Vector2, radius: float, damage: float, knockback: float) -> bool:
	var target := _primary_target()
	if target.is_empty() or not bool(target.get("active", false)):
		return false
	var target_body := target.get("body") as Node2D
	if target_body == null or target_body.global_position.distance_to(point) > radius:
		return false
	return _route_immediate_attack(target, damage, knockback, -1.0, false)


## Boss spec 3.2 (FattyScript.ts:52-115), after the base step and before the body moves.
func _after_enemy_step(_delta: float) -> void:
	if is_defeated() or _phase == PHASE_DEAD or body == null:
		return
	var now := Services.now_ms()
	_check_phase_two(now)
	_step_ripple(now)
	if _phase == PHASE_DIZZY:
		body.velocity = Vector2.ZERO
		if now >= _dizzy_until:
			_resume_chase(now)
		return
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
			_leaps_left = 1 if _two_on else 0
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
			var progress := minf(1.0, _elapsed(now) / maxf(1.0, _air_ms))
			FeetAnchor.place_at_phaser_position(body, _leap_from + (_leap_target - _leap_from) * progress)
			if progress >= 1.0:
				_land(now)
		PHASE_LANDING:
			if _elapsed(now) >= LANDING_PHASE_MS:
				if _two_on and _leaps_left > 0:
					# Phase two: the second leap of the pair, its small hops first.
					_leaps_left -= 1
					_transition_to(PHASE_SMALL_HOP, now)
					_play_animation(CLIP_SMALL_HOP, false)
				else:
					_begin_recovery(now)
		PHASE_RECOVERY:
			if _elapsed(now) >= maxf(1.0, recovery_ms):
				_next_leap_at = now + maxf(1.0, leap_cadence_ms)
				_resume_chase(now)


# --- damage receiver (FattyScript.ts:19-43, 203-210) -----------------------------------------------

## Airborne and contact-hop phases reject hits as "state-blocked" (retryable); else the base rule.
## Phase two: a thrown thing makes him dizzy (no damage); his squinting eye refuses every other hit
## (the clink) unless he is dizzy.
func can_receive_damage(input: Dictionary) -> Dictionary:
	if _phase == PHASE_AIRBORNE or _phase == PHASE_CONTACT_HOP:
		return {"accepted": false, "reason": STATE_BLOCKED_REASON}
	var request: Dictionary = input.get("request", {})
	if _two_on:
		var tags: Variant = request.get("weapon_tags", [])
		if tags is Array and (tags as Array).has(THROWN_TAG):
			if _phase != PHASE_DIZZY:
				_get_dizzy(Services.now_ms())
			return {"accepted": false, "reason": "pass"}
		if _phase != PHASE_DIZZY:
			return {"accepted": false, "reason": "immune"}
	# A thrown thing passed the hurtbox for phase two; anything else still needs the spear.
	if not _spear_rule.is_empty() and not DamageResolverScript.source_matches(_spear_rule, request):
		return {"accepted": false, "reason": DamageResolverScript.REASON_SOURCE_BLOCKED}
	return super(input)


## The hurtbox's rule: the authored one (the Spear only), plus thrown things, which must reach
## `can_receive_damage` so phase two's throw can dizzy him (it refuses them otherwise, as the
## authored rule did). In rework mode the router keeps no `acceptedSources` and the gate decides.
func _receiver_rule() -> Dictionary:
	var rule := super()
	var sources: Variant = rule.get("acceptedSources", null)
	_spear_rule = {}
	if sources is Array and not (sources as Array).is_empty():
		_spear_rule = {"acceptedSources": (sources as Array).duplicate(true)}
		(sources as Array).append({"allWeaponTags": [THROWN_TAG]})
	return rule


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
	_end_ripple()
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


## Godot deviation (boss spec 4.4, owner decision 2026-10-05): the dead body stays 2 s (its
## `death` clip, then the last frame) and fades out at the end; Phaser removes it the step it dies.
func _dispose_delay_ms() -> float:
	return maxf(BOSS_CORPSE_MS, _clip_length_ms(CLIP_DEATH))


func _corpse_fade_ms() -> float:
	return BOSS_CORPSE_FADE_MS


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
	_air_ms = air_time_ms
	if _two_on and _leaps_left == 0:
		_air_ms = float(_two.get("second_air_time_ms", air_time_ms))
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
	if _two_on:
		var last := _leaps_left == 0
		clods_requested.emit({"count": int(_two.get("clods_per_landing", 2)), "at": get_centre(), "last": last})
		if last:
			_start_ripple(now)
	return true


func _begin_recovery(now: float) -> bool:
	if _phase != PHASE_LANDING:
		return false
	_transition_to(PHASE_RECOVERY, now)
	_play_animation(CLIP_RECOVERY, false)
	return true


func _resume_chase(now: float) -> bool:
	if _phase != PHASE_CONTACT_HOP and _phase != PHASE_RECOVERY and _phase != PHASE_RETURN and _phase != PHASE_DIZZY:
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


# --- phase two (Fatty's Lair) --------------------------------------------------------------------

## Phase two starts once (configured) when his health falls under its share.
func _check_phase_two(now: float) -> void:
	if _two_on or _two.is_empty():
		return
	var state := get_damage_state()
	var max_hp := float(state.get("max_hp", max_health))
	if max_hp <= 0.0 or float(state.get("hp", max_hp)) > max_hp * float(_two.get("health_share", 0.5)):
		return
	_two_on = true
	_shake_camera(260.0, 0.008)
	phase_two_started.emit({"time": now})


## A thrown thing hit him: dizzy, his eye wide open, for `dizzy_ms`; no leap right after.
func _get_dizzy(now: float) -> void:
	if body == null or is_defeated():
		return
	AttackTelegraph.clear_for(self)
	_set_body_collision(true, true)
	_dizzy_until = now + float(_two.get("dizzy_ms", 1600.0))
	_next_leap_at = maxf(_next_leap_at, _dizzy_until + maxf(1.0, recovery_ms))
	_transition_to(PHASE_DIZZY, now)
	_play_animation(CLIP_RECOVERY, false)
	_shake_camera(120.0, 0.004)
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(get_centre() - Vector2(0.0, DIZZY_TEXT_RISE), DIZZY_TEXT, &"yellow", true)
	dizzied.emit({"until": _dizzy_until})


func _start_ripple(now: float) -> void:
	_end_ripple()
	var parent := body.get_parent() if body != null else null
	if parent == null:
		return
	# The ripple spreads on the ground from his feet; the slime is measured at its feet too.
	_ripple_from = body.global_position
	_ripple_started = now
	_ripple_done_with_target = false
	_ripple = MudRipple.new()
	_ripple.name = "MudRipple"
	_ripple.set(&"width", float(_two.get("ripple_width", 30.0)))
	_ripple.set(&"max_radius", float(_two.get("ripple_max_radius", 560.0)))
	_ripple.global_position = _ripple_from
	parent.add_child(_ripple)


## Spreads the ripple; the crest hits the slime once, where it meets it (its i-frames pass it).
func _step_ripple(now: float) -> void:
	if _ripple == null or not is_instance_valid(_ripple):
		return
	var radius := (now - _ripple_started) / 1000.0 * float(_two.get("ripple_speed", 300.0))
	if radius > float(_two.get("ripple_max_radius", 560.0)):
		_end_ripple()
		return
	_ripple.call(&"set_radius", radius)
	if _ripple_done_with_target:
		return
	var target := _primary_target()
	if target.is_empty() or not bool(target.get("active", false)):
		return
	var target_body := target.get("body") as Node2D
	if target_body == null:
		return
	var offset: Vector2 = target_body.global_position - _ripple_from
	var reach := Vector2(offset.x, offset.y / RIPPLE_SQUASH_Y).length()
	if absf(reach - radius) > float(_two.get("ripple_width", 30.0)) * 0.5:
		return
	_ripple_done_with_target = true
	_route_immediate_attack(target, float(_two.get("ripple_damage", 18.0)), float(_two.get("ripple_knockback", 220.0)), -1.0, false)


func _end_ripple() -> void:
	if _ripple != null and is_instance_valid(_ripple):
		_ripple.queue_free()
	_ripple = null


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
