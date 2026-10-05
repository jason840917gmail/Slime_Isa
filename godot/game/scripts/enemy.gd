extends Node
class_name EnemyScript
## Scene script `game.enemy` (Phaser `features/scripts/EnemyScript.ts`, base enemy only).
## Implements the enemy spec: per-step behaviour (4.2), camp territory (4.3), AI loop (4.4),
## facing/clips (4.5), timer-driven melee (5), hit reaction (6), death and despawn (7).
##
## Used by every scene with script id `game.enemy` (worm swordsman, worm archer, worm brawler,
## slime spider, orb weaver). The trial only spawns the worm swordsman; ranged attacks, fleeRange,
## slime-spider AI, slow, impactEffect and effect immunities are OUT (enemy spec 0).
##
## Node: `EnemyScript` (plain Node child of the CharacterBody2D root, re-anchored to the feet;
## worm `metadata/depth_anchor = (0, 22)`). ALL AI maths use old Phaser centres
## (`get_centre()`, `primary_target().centre`; enemy spec 9).
## This script is the only mover of its body: `ArcadeMover.move(body, delta)` (every path except
## the defeated one) stands in for Phaser Arcade - a wall hit zeroes the blocked velocity component
## and keeps the tangential one, and that cut velocity is read back next step (enemy spec 4.2).
## Timers use `Services.now_ms()` (SimClock), which freezes in hit-stop.
## The attack-side `animation_event` hitbox events are deliberately ignored (enemy spec 2.1).
##
## Bosses (`game.fatty` -> res://game/scripts/fatty.gd) extend this script as Phaser's FattyScript
## extends EnemyScript. For them it also carries the arena leash (`configure_arena`, boss spec
## 3.3), `_route_immediate_attack` and the overridable hooks `_after_enemy_step`,
## `_attack_area_reach`, `_can_run_common_attack`, `_mirrors_side_facing`, `_receiver_tags`,
## `_damage_number_top`, `_dispose_delay_ms`, `_react_to_damage` and `can_receive_damage`. Their
## defaults keep the worm's behaviour.
##
## Owner: enemy builder.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const HitFlash := preload("res://game/feel/hit_flash.gd")
const EnemyAI := preload("res://game/enemy/enemy_ai.gd")
const CampTerritory := preload("res://game/enemy/camp_territory.gd")
const EnemyAttackLifecycle := preload("res://game/enemy/attack_lifecycle.gd")
const ArcadeMover := preload("res://game/shared/arcade_mover.gd")
const BossArena := preload("res://game/bosses/boss_arena.gd")

## EnemyScript.ts literals (enemy spec 1.2).
const SIGHT_CHECK_MS := 150.0
const HIT_KNOCKBACK_BASE := 120.0
const HIT_STUN_BASE_MS := 320.0
const HIT_STUN_MAX_BONUS_MS := 280.0
const HIT_STUN_PER_STRENGTH_MS := 0.35
const HIT_STUN_VELOCITY_DECAY := 0.94
const HIT_FLASH_MS := 120.0
const HIT_FLASH_COLOR := Color("#ff6f88")
const ATTACK_SEQUENCE_PADDING_MS := 250.0
const ATTACK_SEQUENCE_MAX_MS := 2000.0
const MELEE_REACH_MULTIPLIER := 1.35
const WALK_SPEED_THRESHOLD := 2.0
## UniversalSceneWorldController.ts:2052 - the enemy frees itself this long after defeat.
const DISPOSE_AFTER_DEFEAT_MS := 800.0
## UniversalSceneWorldController.ts:2043 - damage numbers above this are yellow and big.
const IMPORTANT_DAMAGE := 15.0
const DAMAGE_NUMBER_RISE_PX := 8.0
## Router target tags of an ordinary enemy hurtbox (UniversalSceneWorldController.ts:2195-2206).
const RECEIVER_TAGS: Array[String] = ["enemy"]

## JSON `body`: the CharacterBody2D root.
@export var body: CharacterBody2D
## JSON `visual`: the Sprite2D (side clips mirrored with flip_h when facing left).
@export var visual: Sprite2D
## JSON `animation`: the AnimationPlayer (idle-*, walk-*, attack-*, knockback-*, die-*).
@export var animation: AnimationPlayer
## JSON `damageArea`: the hurtbox Area2D registered with the router.
@export var damage_area: Area2D
## JSON `attackArea`: the hitbox Area2D (toggled for parity; damage uses the distance rule).
@export var attack_area: Area2D
## JSON `faction` ("hostile").
@export var faction: String = "hostile"
## JSON `rank` ("ordinary"; bosses use other scripts).
@export var rank: String = "ordinary"
## JSON `displayName` (absent on the worm).
@export var display_name: String = ""
## JSON `maxHealth` (worm 90), clamped to max(1, v).
@export var max_health: float = 1.0
## JSON `targetingRadius` = aggro range (worm 220).
@export var targeting_radius: float = 0.0
## JSON `attackRange` (worm 38).
@export var attack_range: float = 0.0
## JSON `movementSpeed` = chase speed (worm 75).
@export var movement_speed: float = 0.0
## JSON `attackCooldownMs` (worm 1500).
@export var attack_cooldown_ms: float = 0.0
## JSON `attributes` (camelCase keys: wanderSpeed, attackWindupMs, attackRecoveryMs,
## contactDamage, knockbackStrength, knockbackResist; optional fleeRange, leashRange,
## projectileSpeed, behavior). Missing/non-finite numbers read as 0 unless stated.
@export var attributes: Dictionary = {}
## JSON `damageRule` ({priority, damageMultiplier}); passed to the router as the receiver rule.
@export var damage_rule: Dictionary = {}
## JSON `rewards` ({coins, items[{itemId, chance}]}); emitted with reward_requested (OUT).
@export var rewards: Dictionary = {}
## JSON `projectile` (ranged enemies, OUT).
@export var projectile: Dictionary = {}
## JSON `impactEffect` (worm brawler, OUT).
@export var impact_effect: Dictionary = {}
## JSON `arenaRecoveryMs` (bosses with an arena: heal to full once the player has stayed outside
## the arena this long; 0 = never).
@export var arena_recovery_ms: float = 0.0

## Payload {"hp": float, "maxHp": float}.
signal health_changed(payload: Dictionary)
## -> HurtSfx.play_cue. Payload: the router commit.
signal damaged(commit: Dictionary)
## -> DeathSfx.play_cue (detached). Payload {"receiverNodeId": String}.
signal defeated(payload: Dictionary)
## -> AlertSfx.play_cue. Payload {"state": "chase"|"flee"}.
signal alerted(payload: Dictionary)
## -> WindupSfx.play_cue. Payload {"ranged": bool, "windupMs": float}.
signal attack_started(payload: Dictionary)
## Emitted once on defeat; nobody listens in the trial (loot OUT). Payload {"receiverNodeId", "rewards"}.
signal reward_requested(payload: Dictionary)
## Emitted after each commit; no scene listener. Payload: the commit.
signal damage_feedback(commit: Dictionary)


## Melee request shape (EnemyScript.ts:774-790; weapon tags sorted as the resolver normalises them).
const CONTACT_WEAPON_ID := "enemy-contact"
const CONTACT_WEAPON_TAGS: Array[String] = ["contact", "enemy"]
const CONTACT_DAMAGE_TYPES: Array[String] = ["physical"]
const KNOCKBACK_EFFECT_ID := "knockback"
const IMMUNE_REASON := "immune"
## EnemyScript.ts:826-829: shorter vectors keep the old facing.
const FACING_EPSILON := 0.000001
const ENEMY_GROUP := &"enemy"
const NO_ID := -1

var _hp: float = 0.0
var _defeated: bool = false
var _dispose_at_ms: float = -1.0
var _lifecycle: EnemyAttackLifecycle = EnemyAttackLifecycle.new()
var _territory: CampTerritory
var _spawn_area: Dictionary = {}
var _safe_zones: Array[Dictionary] = []
var _ai_state: String = "idle"
var _runtime_state: String = "idle"
var _facing: String = "down"
var _facing_flipped: bool = false
var _active_sequence_id: int = -1
var _active_activation_id: int = -1
var _attack_impact_at: float = 0.0
var _attack_finish_at: float = 0.0
var _attack_resolved: bool = false
var _attack_direction: Vector2 = Vector2(0.0, 1.0)
var _hit_stun_until: float = 0.0
var _hit_flash_until: float = 0.0
var _hurt_since_territory_step: bool = false
var _sight_checked_at: float = -INF
var _sight_cached: bool = false
var _reward_published: bool = false
## Last value written to the attack area (scene default: monitoring off, shapes disabled).
var _attack_area_active: bool = false
var _registered_area: Area2D
## Boss arena perimeter (BossArena shape, {} = no arena) and its leash state (boss spec 3.3).
var _arena: Dictionary = {}
var _returning_to_arena: bool = false
var _arena_left: bool = false
var _arena_left_at_ms: float = 0.0


## Clamps max_health, sets hp; push_error when damage_area / attack_area are missing; registers
## the hurtbox: `Services.router().register_area(damage_area, self, damage_rule, RECEIVER_TAGS)`;
## installs HitFlash on `visual`; `body.motion_mode = MOTION_MODE_FLOATING`; joins group "enemy".
func _ready() -> void:
	max_health = maxf(1.0, max_health)
	_hp = max_health
	add_to_group(ENEMY_GROUP)
	if body == null:
		push_error("EnemyScript '%s' requires a CharacterBody2D body reference." % get_path())
		set_physics_process(false)
		return
	if damage_area == null:
		push_error("EnemyScript '%s' requires a damageArea reference." % get_path())
	if attack_area == null:
		push_error("EnemyScript '%s' requires an attackArea reference." % get_path())
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if visual != null:
		HitFlash.install(visual)
	var router := Services.router()
	if router != null and damage_area != null:
		router.register_area(damage_area, self, _receiver_rule(), _receiver_tags())
		_registered_area = damage_area


## `cancel_attack()` and unregister the hurtbox.
func _exit_tree() -> void:
	cancel_attack()
	if _registered_area != null:
		var router := Services.router()
		if router != null:
			router.unregister_area(_registered_area)
		_registered_area = null


## One physics step: the base enemy step (`_step_enemy`), then the subclass hook
## `_after_enemy_step` (Phaser: FattyScript._physics_process after `super`), then the body moves
## once with `ArcadeMover.move(body, delta)` on every path except defeated (Arcade integrates
## after the scripts, enemy spec 4.2).
func _physics_process(delta: float) -> void:
	if body == null:
		return
	var moves := _step_enemy(delta)
	_after_enemy_step(delta)
	if moves and is_instance_valid(body) and not body.is_queued_for_deletion():
		ArcadeMover.move(body, delta)


## Enemy spec 4.2 step order exactly (flash update, defeated, stun slide, no target, arena leash
## (bosses), territory, attack in flight, AI loop, alerted, facing/clip). Returns false only on
## the defeated path (the body does not move). When defeated: velocity 0 and `body.queue_free()`
## once `now >= dispose_at` (enemy spec 7, self-dispose replaces the world-side cleanup).
func _step_enemy(delta: float) -> bool:
	var now := Services.now_ms()
	_update_hit_flash(now)
	if _defeated:
		body.velocity = Vector2.ZERO
		_runtime_state = EnemyAI.STATE_DEAD
		if _dispose_at_ms >= 0.0 and now >= _dispose_at_ms and not body.is_queued_for_deletion():
			body.queue_free()
		return false

	# Knockback / hit-stun: slide with decay; no AI, no territory, no attack, no clip change.
	if now < _hit_stun_until:
		body.velocity *= pow(HIT_STUN_VELOCITY_DECAY, delta * 60.0)
		return true

	var target := _primary_target()
	if target.is_empty() or not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
		cancel_attack()
		_ai_state = EnemyAI.STATE_IDLE
		_runtime_state = EnemyAI.STATE_IDLE
		body.velocity = Vector2.ZERO
		_play_facing("idle")
		return true

	var origin := get_centre()
	var player_centre: Vector2 = target.get("centre", origin)
	# Arena leash (boss camps, EnemyScript.ts:392-409): outside the arena the enemy drops the fight
	# and walks home; left alone `arena_recovery_ms`, it heals to full.
	if not _arena.is_empty() and not BossArena.contains(_arena, player_centre):
		if not _arena_left:
			_arena_left = true
			_arena_left_at_ms = now
		if arena_recovery_ms > 0.0 and now - _arena_left_at_ms >= arena_recovery_ms:
			_restore_health(max_health)
		cancel_attack()
		_returning_to_arena = true
		_ai_state = EnemyAI.STATE_IDLE
		_runtime_state = EnemyAI.STATE_IDLE
		var home := _velocity_toward_arena_centre(origin, delta)
		body.velocity = home
		_update_facing(home)
		_play_facing("walk" if home.length() > WALK_SPEED_THRESHOLD else "idle")
		return true
	_returning_to_arena = false
	_arena_left = false
	var to_player := player_centre - origin
	var distance := to_player.length()
	var direction := to_player / distance if distance > 0.0 else _attack_direction

	# Camp enemies follow their territory (Territory.ts): chase within the leash, search where the
	# player was last seen, then walk home healing.
	var territory: Dictionary = {}
	if _territory != null:
		territory = _step_camp_territory(now, delta, origin, target, player_centre, distance)
	if not territory.is_empty() and (territory["move_to"] != null or bool(territory["hold"])):
		cancel_attack()
		_ai_state = EnemyAI.STATE_IDLE if bool(territory["hold"]) else EnemyAI.STATE_WANDER
		_runtime_state = _ai_state
		var speed := CampTerritory.return_speed(movement_speed)
		var walk := Vector2.ZERO
		if territory["move_to"] is Vector2:
			var to_spot: Vector2 = (territory["move_to"] as Vector2) - origin
			if to_spot.length() > 0.0 and speed > 0.0:
				walk = to_spot.normalized() * speed
		body.velocity = walk
		_update_facing(walk)
		_play_facing("walk" if walk.length() > WALK_SPEED_THRESHOLD else "idle")
		return true
	if not territory.is_empty() and territory["mode"] == CampTerritory.MODE_ENGAGED \
			and (_ai_state == EnemyAI.STATE_IDLE or _ai_state == EnemyAI.STATE_WANDER):
		# Noticed by sight or a hit: the combat AI starts chasing even beyond its aggro range.
		alerted.emit({"state": EnemyAI.STATE_CHASE})
		_ai_state = EnemyAI.STATE_CHASE

	# Attack in flight (timer driven, enemy spec 5).
	if _active_sequence_id != NO_ID:
		if not _attack_resolved and now >= _attack_impact_at:
			_resolve_attack(target, origin)
		if _active_sequence_id != NO_ID and now >= _attack_finish_at:
			_finish_attack(_active_sequence_id)
			var flee_range := _optional_attribute("fleeRange")
			_ai_state = EnemyAI.STATE_FLEE if flee_range > 0.0 and distance < flee_range else EnemyAI.STATE_CHASE

	# The AI keeps running during an attack: the attack state holds position, and a target that
	# escapes beyond reach is chased while the committed swing plays out.
	var context := {
		"centre": origin,
		"distance": distance,
		"dir": direction,
		"aggro": targeting_radius,
		"attack_range": attack_range,
		"wander_speed": _attribute("wanderSpeed"),
		"chase_speed": movement_speed,
		"flee_range": maxf(0.0, _optional_attribute("fleeRange")),
		"may_engage": bool(territory["may_engage"]) if not territory.is_empty() else distance <= targeting_radius,
		"safe_zones": _safe_zones,
	}
	# Authored attack-area reach replaces the attack_range distance rules (EnemyScript.ts:464).
	var reach: Variant = _attack_area_reach(target)
	if reach is bool:
		context["in_attack_reach"] = reach
	var outcome := EnemyAI.run(_ai_state, body.velocity, context)
	var velocity: Vector2 = outcome["velocity"]
	if bool(outcome["attack_requested"]) and _can_run_common_attack():
		_begin_attack(outcome["attack_dir"])
	var next_state: String = outcome["state"]
	# Presentation hook (alert chirp): idle or wandering enemies that start pursuing or fleeing.
	if (_ai_state == EnemyAI.STATE_IDLE or _ai_state == EnemyAI.STATE_WANDER) \
			and (next_state == EnemyAI.STATE_CHASE or next_state == EnemyAI.STATE_FLEE):
		alerted.emit({"state": next_state})
	_ai_state = next_state
	_runtime_state = EnemyAI.STATE_ATTACK if _active_sequence_id != NO_ID else next_state
	body.velocity = velocity
	if _active_sequence_id == NO_ID:
		_update_facing(velocity)
		_play_facing("walk" if velocity.length() > WALK_SPEED_THRESHOLD else "idle")
	return true


# --- API for the spawner / world ---------------------------------------------------------------

## Called by EnemyPopulation right after instancing, before the first physics step: the
## enemy-spawn area record it came from (WorldService.areas("enemy-spawn") entry; {} = no camp,
## then `may_engage = distance <= aggro`) and the safe-zone perimeters. Builds the
## CampTerritory from `spawn_area.stay_perimeter`.
func configure_navigation(spawn_area: Dictionary, safe_zones: Array[Dictionary]) -> void:
	_spawn_area = spawn_area
	_safe_zones = safe_zones
	_territory = null
	var stay: Variant = spawn_area.get("stay_perimeter", {})
	if stay is Dictionary and not (stay as Dictionary).is_empty():
		_territory = CampTerritory.new()
		_territory.setup(stay, targeting_radius, attack_range, _optional_attribute("leashRange"))
	elif not spawn_area.is_empty():
		push_error("EnemyScript '%s': spawn area '%s' has no stay perimeter; no territory." % [get_path(), spawn_area.get("id", "")])


## Called by a boss camp right after spawning its boss (Phaser navigation `{arena}`,
## UniversalSceneWorldController.ts:2073-2079): the arena perimeter (BossArena shape) the enemy
## does not pursue beyond (boss spec 3.3). {} removes the leash.
func configure_arena(perimeter: Dictionary) -> void:
	_arena = perimeter
	_returning_to_arena = false
	_arena_left = false


## The arena perimeter given by configure_arena ({} when none).
func get_arena() -> Dictionary:
	return _arena


## True while an arena-leashed enemy walks home because its target left the arena.
func is_returning_to_arena() -> bool:
	return _returning_to_arena


## Old Phaser body centre: FeetAnchor.phaser_position(body).
func get_centre() -> Vector2:
	return FeetAnchor.phaser_position(body)


## True from the killing blow on (the body stays until disposed).
func is_defeated() -> bool:
	return _defeated


## "idle" | "wander" | "chase" | "attack" | "flee" | "dead".
func get_runtime_state() -> String:
	return _runtime_state


## The spawn area record given by configure_navigation ({} when none).
func get_spawn_area() -> Dictionary:
	return _spawn_area


## Lifecycle cancel + end_attack (enemy spec 5.4): called on non-lethal hit, death, target lost,
## territory move/hold and `_exit_tree`.
func cancel_attack() -> void:
	_lifecycle.cancel()
	_end_attack()


# --- damage receiver API (combat spec 7.2) --------------------------------------------------------

## {"hp": float, "max_hp": float, "dead": bool}.
func get_damage_state() -> Dictionary:
	return {"hp": _hp, "max_hp": max_health, "dead": _defeated}


## {"accepted": false, "reason": "dead"} once defeated, else {"accepted": true, "reason": ""}.
## Enemies have no mitigate_damage (raw scaled damage).
func can_receive_damage(_input: Dictionary) -> Dictionary:
	if _defeated:
		return {"accepted": false, "reason": "dead"}
	return {"accepted": true, "reason": ""}


## Enemy spec 6.1: hp -= actual; emit health_changed and damaged(commit); mark hurt for the
## territory; react_to_damage (flash, number, cancel attack, knockback (P + 120) * (1 - resist),
## stun 320 + min(280, strength * 0.35), "knockback-<facing>" restart); defeat() when dead.
func commit_damage(commit: Dictionary) -> void:
	if _defeated:
		return
	var result: Dictionary = commit.get("result", {})
	_hp = maxf(0.0, _hp - float(result.get("actual_damage", 0)))
	health_changed.emit(_health_payload())
	damaged.emit(commit)
	var is_dead := bool(result.get("defeated", false)) or _hp <= 0.0
	_hurt_since_territory_step = true
	_react_to_damage(commit, is_dead)
	if is_dead:
		_defeat()


## Emits damage_feedback(commit).
func publish_damage_feedback(commit: Dictionary) -> void:
	damage_feedback.emit(commit)


# --- private steps ------------------------------------------------------------------------------

## Enemy spec 5.2: lifecycle try_begin, activation `Services.router().begin_activation(self,
## [attack_area])`, facing, impact at +windup, finish at +min(2000, max(windup + recovery,
## clip_ms) + 250), attack area on, "attack-<facing>" restart, emit attack_started.
func _begin_attack(direction: Vector2) -> void:
	var now := Services.now_ms()
	var sequence := _lifecycle.try_begin(now, attack_cooldown_ms)
	if sequence == NO_ID:
		return
	var router := Services.router()
	if attack_area == null or router == null:
		return
	if direction.length() > 0.0:
		_attack_direction = direction.normalized()
	_active_sequence_id = sequence
	var areas: Array[Area2D] = [attack_area]
	_active_activation_id = router.begin_activation(self, areas)
	var windup_ms := maxf(0.0, _attribute("attackWindupMs"))
	var recovery_ms := maxf(0.0, _attribute("attackRecoveryMs"))
	_update_facing(_attack_direction)
	var clip_ms := _clip_length_ms("attack-" + _facing)
	_attack_impact_at = now + windup_ms
	_attack_finish_at = now + minf(ATTACK_SEQUENCE_MAX_MS,
		maxf(windup_ms + recovery_ms, clip_ms) + ATTACK_SEQUENCE_PADDING_MS)
	_attack_resolved = false
	_set_attack_area_active(true)
	_play_facing("attack", true)
	attack_started.emit({"ranged": not projectile.is_empty(), "windupMs": windup_ms})


## Enemy spec 5.3: one impact check per swing; centre distance <= attack_range * 1.35 routes a
## request to the player hurtbox (weapon_id "enemy-contact", tags ["contact", "enemy"], base
## damage attributes.contactDamage, knockback potency attributes.knockbackStrength, impact at the
## enemy centre, knock = normalized(player centre - enemy centre)).
## Ranged enemies (`projectile` set) are OUT of the trial: their swing resolves to nothing.
func _resolve_attack(target: Dictionary, origin: Vector2) -> void:
	_attack_resolved = true
	var router := Services.router()
	if _active_activation_id <= 0 or attack_area == null or router == null:
		return
	if not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
		return
	if not projectile.is_empty():
		push_warning("EnemyScript '%s': ranged attacks are not ported (projectile ignored)." % get_path())
		return
	var target_area := target.get("hurtbox") as Area2D
	if target_area == null:
		return
	var player_centre: Vector2 = target.get("centre", origin)
	var to_player := player_centre - origin
	# An authored attack-area reach replaces the distance rule (EnemyScript.ts:771-773).
	var reach: Variant = _attack_area_reach(target)
	if reach is bool:
		if not reach:
			return
	elif to_player.length() > attack_range * MELEE_REACH_MULTIPLIER:
		return
	var knock := to_player.normalized() if to_player.length() > 0.0 else _attack_direction
	var effects: Array[Dictionary] = []
	var knockback_strength := _attribute("knockbackStrength")
	if knockback_strength > 0.0:
		effects.append({"effect_id": KNOCKBACK_EFFECT_ID, "potency": knockback_strength})
	var request := {
		"activation_id": _active_activation_id,
		"source": self,
		"attack_area": attack_area,
		"target_area": target_area,
		"weapon_id": CONTACT_WEAPON_ID,
		"weapon_tags": CONTACT_WEAPON_TAGS.duplicate(),
		"damage_types": CONTACT_DAMAGE_TYPES.duplicate(),
		"base_damage": _attribute("contactDamage"),
		"effects": effects,
		"impact": {"position": origin, "knock": knock},
	}
	router.route(request)
	# An accepted hit would spawn `impact_effect` here (worm brawler only; OUT of the trial).


## Phaser `finishAttack(seq)`: lifecycle finish, then end the runtime attack when it is current.
func _finish_attack(sequence: int) -> void:
	_lifecycle.finish(sequence)
	if _active_sequence_id == sequence:
		_end_attack()


## Enemy spec 5.4: end the activation, clear the sequence, attack area off.
func _end_attack() -> void:
	if _active_activation_id > 0:
		var router := Services.router()
		if router != null:
			router.end_activation(_active_activation_id)
	_active_activation_id = NO_ID
	_active_sequence_id = NO_ID
	_attack_resolved = false
	_set_attack_area_active(false)


## Enemy spec 7: defeated, hp 0, cancel attack, velocity 0, body collision off (set_deferred),
## attack area off, "die-<facing>" restart, health_changed, defeated, reward_requested once,
## dispose_at = now + `_dispose_delay_ms()` (DISPOSE_AFTER_DEFEAT_MS).
func _defeat() -> void:
	if _defeated:
		return
	_defeated = true
	_hp = 0.0
	cancel_attack()
	_runtime_state = EnemyAI.STATE_DEAD
	if body != null:
		body.velocity = Vector2.ZERO
		# Phaser `collisionEnabled = false`: the player walks through the corpse. The hurtbox
		# stays registered (later hits are rejected "dead").
		body.set_deferred(&"collision_layer", 0)
		body.set_deferred(&"collision_mask", 0)
	_set_attack_area_active(false)
	_play_facing("die", true)
	health_changed.emit({"hp": 0.0, "maxHp": max_health})
	var receiver_node_id := _receiver_node_id()
	defeated.emit({"receiverNodeId": receiver_node_id})
	if not _reward_published:
		_reward_published = true
		reward_requested.emit({"receiverNodeId": receiver_node_id, "rewards": rewards})
	_dispose_at_ms = Services.now_ms() + _dispose_delay_ms()


## Enemy spec 6.2 reaction (ordinary enemies): feedback always; on a non-lethal hit cancel the
## attack, knock back and stun.
func _react_to_damage(commit: Dictionary, is_dead: bool) -> void:
	_show_hit_feedback(commit)
	if is_dead:
		return
	cancel_attack()
	var result: Dictionary = commit.get("result", {})
	var immune := false
	for effect: Variant in result.get("rejected_effects", []):
		if effect is Dictionary and effect.get("effect_id", "") == KNOCKBACK_EFFECT_ID \
				and effect.get("reason", "") == IMMUNE_REASON:
			immune = true
	var potency := 0.0
	for effect: Variant in result.get("applied_effects", []):
		if effect is Dictionary and effect.get("effect_id", "") == KNOCKBACK_EFFECT_ID:
			potency += float(effect.get("potency", 0.0))
	var resist := clampf(_attribute("knockbackResist"), 0.0, 1.0)
	var strength := 0.0 if immune else (potency + HIT_KNOCKBACK_BASE) * (1.0 - resist)
	var request: Dictionary = commit.get("request", {})
	var impact: Dictionary = request.get("impact", {})
	var knock: Vector2 = impact.get("knock", Vector2.ZERO)
	if strength > 0.0 and knock.length() > 0.0 and body != null:
		body.velocity = knock.normalized() * strength
	var stun_ms := HIT_STUN_BASE_MS + minf(HIT_STUN_MAX_BONUS_MS, strength * HIT_STUN_PER_STRENGTH_MS)
	_hit_stun_until = maxf(_hit_stun_until, Services.now_ms() + stun_ms)
	_play_facing("knockback", true)


## Enemy spec 6.2 feedback: flash until now + 120 (HitFlash fill), damage number "-N" at
## (centre.x, `_damage_number_top()` - 8), yellow big when N > 15 else white small
## (`Services.feel().floating_text`).
func _show_hit_feedback(commit: Dictionary) -> void:
	_hit_flash_until = Services.now_ms() + HIT_FLASH_MS
	if visual != null:
		HitFlash.flash(visual, HIT_FLASH_COLOR)
	var result: Dictionary = commit.get("result", {})
	var amount := int(result.get("actual_damage", 0))
	var feel := Services.feel()
	if feel == null or body == null:
		return
	var centre := get_centre()
	var top := _damage_number_top()
	var important := float(amount) > IMPORTANT_DAMAGE
	feel.floating_text(Vector2(centre.x, top - DAMAGE_NUMBER_RISE_PX), "-%d" % amount,
		&"yellow" if important else &"white", important)


## Enemy spec 4.3 sight: beyond aggro * 1.5 -> false; throttled to SIGHT_CHECK_MS; else
## `Services.world().line_of_sight(centre, player centre, [body RID, player body RID])`.
func _sees_target(now: float, origin: Vector2, target: Dictionary, distance: float) -> bool:
	if distance > targeting_radius * CampTerritory.LOSE_SIGHT_MULTIPLIER:
		return false
	if now - _sight_checked_at < SIGHT_CHECK_MS:
		return _sight_cached
	_sight_checked_at = now
	var world := Services.world()
	if world == null:
		_sight_cached = true
		return _sight_cached
	var exclude: Array[RID] = [body.get_rid()]
	var player_body := target.get("body") as CharacterBody2D
	if player_body != null:
		exclude.append(player_body.get_rid())
	_sight_cached = world.line_of_sight(origin, target.get("centre", origin), exclude)
	return _sight_cached


## One territory step with the throttled sight check and regeneration (EnemyScript.ts:548-571).
func _step_camp_territory(now: float, delta: float, origin: Vector2, target: Dictionary,
		player_centre: Vector2, distance: float) -> Dictionary:
	var hurt := _hurt_since_territory_step
	_hurt_since_territory_step = false
	var sees := _sees_target(now, origin, target, distance)
	var decision := _territory.step(now, origin, true, player_centre, sees, distance, hurt)
	if bool(decision["restore_health"]):
		_restore_health(max_health)
	elif bool(decision["regenerate"]):
		_restore_health(_hp + max_health * CampTerritory.REGEN_PER_SECOND_RATIO * delta)
	return decision


## `restoreHealth(hp)`: raise hp (never lower it) up to max; emit health_changed on a change.
func _restore_health(value: float) -> void:
	var next := minf(max_health, maxf(_hp, value))
	if next == _hp or _defeated:
		return
	_hp = next
	health_changed.emit(_health_payload())


## `attributes[key]` as a finite float, else `fallback`.
func _attribute(key: String, fallback: float = 0.0) -> float:
	var value: Variant = attributes.get(key)
	if value is float or value is int:
		var number := float(value)
		if is_finite(number):
			return number
	return fallback


## Optional attribute (fleeRange, leashRange, projectileSpeed): -1 when absent.
func _optional_attribute(key: String) -> float:
	return _attribute(key, -1.0)


## Enemy spec 4.5: ignore |v| < 1e-6; |x| > |y| -> "side", flipped = x < 0; else up/down.
func _update_facing(velocity: Vector2) -> void:
	if velocity.length() < FACING_EPSILON:
		return
	if absf(velocity.x) > absf(velocity.y):
		_facing = "side"
		_facing_flipped = velocity.x < 0.0
	else:
		_facing = "up" if velocity.y < 0.0 else "down"
		_facing_flipped = false
	if _mirrors_side_facing() and visual != null and visual.flip_h != _facing_flipped:
		visual.flip_h = _facing_flipped


## `play_animation(action + "-" + facing, restart)`: play when (restart or different) and the
## clip exists.
func _play_facing(action: String, restart: bool = false) -> void:
	_play_animation(action + "-" + _facing, restart)


## Phaser `playAnimation(name, restart)`: plays only when restarting or when the clip differs
## (a finished non-looping clip leaves `current_animation` empty, as in Phaser). A restart
## rewinds to the first key at once.
func _play_animation(clip: String, restart: bool) -> void:
	if animation == null or not animation.has_animation(clip):
		return
	if not restart and animation.current_animation == clip:
		return
	animation.play(clip)
	if restart:
		animation.seek(0.0, true)


func _clip_length_ms(clip: String) -> float:
	if animation == null or not animation.has_animation(clip):
		return 0.0
	return animation.get_animation(clip).length * 1000.0


func _update_hit_flash(now: float) -> void:
	if _hit_flash_until <= 0.0 or now < _hit_flash_until:
		return
	_hit_flash_until = 0.0
	if visual != null:
		HitFlash.clear(visual)


## `set_attack_area_active(on)` (EnemyScript.ts:816-823): monitoring and every CollisionShape2D
## child, deferred (safe inside physics callbacks). Cosmetic for the worm: damage uses the
## distance rule, not the overlap.
func _set_attack_area_active(active: bool) -> void:
	if attack_area == null or active == _attack_area_active:
		return
	_attack_area_active = active
	if attack_area.is_queued_for_deletion():
		return
	attack_area.set_deferred(&"monitoring", active)
	for child in attack_area.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred(&"disabled", not active)


func _primary_target() -> Dictionary:
	var world := Services.world()
	return world.primary_target() if world != null else {}


## The receiver rule: the authored `damageRule` with Phaser's defaults (priority 0, multiplier 1).
func _receiver_rule() -> Dictionary:
	var rule := damage_rule.duplicate(true)
	if not rule.has("priority"):
		rule["priority"] = 0
	if not rule.has("damageMultiplier"):
		rule["damageMultiplier"] = 1
	return rule


func _receiver_node_id() -> String:
	return str(body.get_path()) if body != null and body.is_inside_tree() else str(get_path())


func _health_payload() -> Dictionary:
	return {"hp": _hp, "maxHp": max_health}


# --- hooks for scripts that extend this one (bosses); the defaults are the base enemy ----------

## Runs after the base step, before the body moves (Phaser: the subclass `_physics_process` body
## after `super`). No-op here.
func _after_enemy_step(_delta: float) -> void:
	pass


## Authored attack-area reach (EnemyScript.ts:614-619): null keeps the `attack_range` distance
## rules; a bool replaces them for the AI and the impact (boss spec 3.3).
func _attack_area_reach(_target: Dictionary) -> Variant:
	return null


## Whether the AI's attack request may start the common melee (EnemyScript.ts:612).
func _can_run_common_attack() -> bool:
	return true


## Directional enemies mirror their side clips when facing left (EnemyScript.ts:663).
func _mirrors_side_facing() -> bool:
	return true


## Target tags the router hands to weapons for this hurtbox (UniversalSceneWorldController.ts:2195-2206).
func _receiver_tags() -> Array[String]:
	return RECEIVER_TAGS


## World y the damage number rises from (minus 8): the top of the Visual's bounds
## (UniversalSceneWorldController.ts:2039-2045), the centre when there is no visual.
func _damage_number_top() -> float:
	if visual == null:
		return get_centre().y
	var rect := visual.get_global_transform() * visual.get_rect()
	return rect.position.y


## How long the defeated body stays before it frees itself (enemy spec 7).
func _dispose_delay_ms() -> float:
	return DISPOSE_AFTER_DEFEAT_MS


## Toward the arena centre at movement speed, snapping onto it on the last step
## (EnemyScript.ts:598-610). `origin` is the old centre.
func _velocity_toward_arena_centre(origin: Vector2, delta: float) -> Vector2:
	var centre := BossArena.centre(_arena)
	var offset := centre - origin
	var remaining := offset.length()
	if remaining <= maxf(1.0, movement_speed * maxf(0.0, delta)):
		FeetAnchor.place_at_phaser_position(body, centre)
		return Vector2.ZERO
	return offset / remaining * movement_speed


## `routeImmediateAttack` (EnemyScript.ts:675-699, boss spec 3.4): one hit on the player's hurtbox
## outside the timed melee, in its own activation. Knock = unit(player centre - centre) (zero when
## they coincide); `max_range >= 0` skips a target further than that. Returns true when the hit
## was accepted with damage > 0. (Phaser's optional impact effect is OUT, as for the melee.)
func _route_immediate_attack(target: Dictionary, base_damage: float, knockback_strength: float,
		max_range: float = -1.0) -> bool:
	var router := Services.router()
	if attack_area == null or router == null or body == null:
		return false
	var origin := get_centre()
	var to_player: Vector2 = target.get("centre", origin) - origin
	var knock := to_player.normalized() if to_player.length() > 0.0 else Vector2.ZERO
	if not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
		return false
	if max_range >= 0.0 and to_player.length() > max_range:
		return false
	var target_area := target.get("hurtbox") as Area2D
	if target_area == null:
		return false
	var areas: Array[Area2D] = [attack_area]
	var activation_id := router.begin_activation(self, areas)
	var effects: Array[Dictionary] = []
	if knockback_strength > 0.0:
		effects.append({"effect_id": KNOCKBACK_EFFECT_ID, "potency": knockback_strength})
	var result := router.route({
		"activation_id": activation_id,
		"source": self,
		"attack_area": attack_area,
		"target_area": target_area,
		"weapon_id": CONTACT_WEAPON_ID,
		"weapon_tags": CONTACT_WEAPON_TAGS.duplicate(),
		"damage_types": CONTACT_DAMAGE_TYPES.duplicate(),
		"base_damage": base_damage,
		"effects": effects,
		"impact": {"position": origin, "knock": knock},
	})
	router.end_activation(activation_id)
	return str(result.get("status", "")) == "accepted" and int(result.get("actual_damage", 0)) > 0
