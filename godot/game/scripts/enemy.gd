extends Node
class_name EnemyScript
## Scene script `game.enemy` (Phaser `features/scripts/EnemyScript.ts`, base enemy only).
## Implements the enemy spec: per-step behaviour (4.2), camp territory (4.3), AI loop (4.4),
## facing/clips (4.5), timer-driven melee (5), hit reaction (6), death and despawn (7).
##
## Used by every scene with script id `game.enemy` (worm swordsman, worm archer, worm brawler,
## slime spider, orb weaver). Part 2 of the enemy spec (2026-10-05) adds the ranged attack (the
## common attack fires `projectile.<id>` through res://game/enemy/enemy_projectiles.gd, §12), the
## keep-distance `fleeRange` rules (§13), the slime-spider AI (`attributes.behavior`,
## res://game/enemy/slime_spider_ai.gd, §14), `apply_slow` (§15) and the `impactEffect` (§16). A
## honey throw's `apply_tempo` slows its walk and its attack's timings (throw combat).
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
## Bosses (`game.fatty` -> res://game/scripts/fatty.gd, `game.matron` -> matron.gd) extend this
## script as Phaser's FattyScript / MatronScript extend EnemyScript. For them it also carries the
## arena leash (`configure_arena`, boss spec 3.3), `_route_immediate_attack`, the EnemyScript
## helpers `_spawn_effect_at`, `_shake_camera`, `_target_overlaps`, and the overridable hooks
## `_after_enemy_step`, `_attack_area_reach`, `_can_run_common_attack`, `_mirrors_side_facing`,
## `_receiver_tags`, `_damage_number_top`, `_dispose_delay_ms`, `_react_to_damage` and
## `can_receive_damage`. Their defaults keep the worm's behaviour.
##
## Body-shapes rework (docs/godot/BODY_SHAPES.md "The reaction"): a request with a top-level `hit`
## (only rework attacks send one) goes to game/combat/reactions/enemy_reactions.gd: `can_receive`
## from `can_receive_damage` (a clink answers "immune"), `damage_scale` from `mitigate_damage`,
## `react` from `_react_to_damage` (a subclass that overrides it without reaching `react`, as Fatty
## and the Matron do, gets `react_override` after it, so its own reaction stays and the hit still
## answers `result.reaction`); its flash shows without the old number (the sender's `play_hit` shows
## it), and a 0-damage hit plays no hurt sound. In the rework mode `after_move` runs after each
## step's move (wall splats, bowling), `on_defeated` on defeat (the energy shard), a kill launch
## slides the corpse (`set_death_slide`), a throw's kill sends it off (`begin_sendoff`: it flies and
## pops instead of lying 0.8 s), the stun slide decays by `EnemyReactions.slide_decay_of`
## (`combat.verbs.slideDecay`; a throw's knock slide faster), and a hurtbox the reaction profile
## gates as a part (Fatty's eye) registers without its
## `acceptedSources`: the gate decides for rework hits, and old hits still meet the old rule in
## `can_receive_damage`. Old requests and the mode off keep every old path. `enemy_type` and
## `reaction_overrides` pick the reaction profile; the public wrappers below (`get_body`,
## `set_hit_stun_until`, `play_hurt`, `flash_hit`, `react_classic`, `reaction_phase`,
## `take_reaction_damage`, `begin_counter_attack`, ...) are what the reaction helper uses instead of
## the private fields.
##
## Owner: enemy builder.

const Services := preload("res://game/shared/services.gd")
## The throw-combat experiment: ammo the enemies make (game/throw/throw_ammo.gd).
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const HitFlash := preload("res://game/feel/hit_flash.gd")
const EnemyAI := preload("res://game/enemy/enemy_ai.gd")
const CampTerritory := preload("res://game/enemy/camp_territory.gd")
const EnemyAttackLifecycle := preload("res://game/enemy/attack_lifecycle.gd")
const ArcadeMover := preload("res://game/shared/arcade_mover.gd")
const BossArena := preload("res://game/bosses/boss_arena.gd")
const AreaShapes := preload("res://game/bosses/area_shapes.gd")
const SlimeSpiderAI := preload("res://game/enemy/slime_spider_ai.gd")
const EnemyProjectiles := preload("res://game/enemy/enemy_projectiles.gd")
const GameFeelType := preload("res://game/feel/game_feel.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const EnemyReactions := preload("res://game/combat/reactions/enemy_reactions.gd")
const DamageResolverScript := preload("res://game/combat/damage_resolver.gd")
const LineUpAI := preload("res://game/enemy/line_up_ai.gd")
## The enemy-ammo prototype: a helpless enemy can be gulped and thrown (game/throw/gulpable_enemy.gd).
const GulpableEnemy := preload("res://game/throw/gulpable_enemy.gd")
## What the ground does to a body a blow moves: ledges, holes, deep water, danger zones.
const EnemyHazards := preload("res://game/combat/reactions/enemy_hazards.gd")
## How a walk to a spot gets round what stands in its way (the walk home, the walk to where the
## slime was last seen).
const WayAround := preload("res://game/enemy/way_around.gd")

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
## Owner decision 2026-10-05: a defeated boss stays this long (its death clip, then its last
## frame) and fades out over the last BOSS_CORPSE_FADE_MS. Phaser removed it the step it died.
const BOSS_CORPSE_MS := 2000.0
const BOSS_CORPSE_FADE_MS := 300.0
## UniversalSceneWorldController.ts:2043 - damage numbers above this are yellow and big.
const IMPORTANT_DAMAGE := 15.0
const DAMAGE_NUMBER_RISE_PX := 8.0
## Router target tags of an ordinary enemy hurtbox (UniversalSceneWorldController.ts:2195-2206).
const RECEIVER_TAGS: Array[String] = ["enemy"]
## EnemyScript.ts:762: projectile speed when `attributes.projectileSpeed` is missing.
const DEFAULT_PROJECTILE_SPEED := 200.0
## `shakeCamera` plays this feel preset with the caller's shake (UniversalSceneWorldController.ts:586).
const BOSS_LANDING_FEEL := &"boss-landing"
## `rank` of bosses: never slowed (EnemyScript.ts:935).
const RANK_BOSS := "boss"
## A fall: one level of height in units (the flight's depth); a fate: the share of its time the
## corpse glides out over the hole or the water in.
const FALL_LEVEL_UNITS := 64.0
const FATE_GLIDE_SHARE := 0.35
## A corpse a Carnivore Plant took (`begin_fate`, game/scripts/carnivore_plant.gd): it slides into
## her jaws in the first FATE_GLIDE_SHARE of the time, stays all but whole (its alpha 1 - t^EATEN_FADE_POW)
## and is gone with no pop and no sound (the plant's own swallow is the end).
const FATE_EATEN := "eaten"
const EATEN_FADE_POW := 4.0
## Why a carried enemy (the enemy-ammo prototype) refuses a hit.
const REASON_CARRIED := "carried"
## Four-way shooters (enemy spec 20): the Worm Archer's behaviour, and the spiders' when their type
## has an `alignSpeed`. The numbers are the `ai` keys below, from `attributes` or else the type's
## `ai` block in enemy-types.json (`_ai_value`).
const BEHAVIOR_LINER_UP := "liner-up"
const BEHAVIOR_SLIME_SPIDER := "slime-spider"
const AI_TYPES_FILE := "enemy-types.json"
const TYPE_AI_KEY := "ai"
## Only for a line-up type that misses a key (every built one sets them all, the Worm Archer's
## numbers).
const LINE_UP_DEFAULTS := {"alignTolerancePx": 8.0, "alignMarginPx": 16.0, "alignReplanMs": 250.0,
	"alignSwitchPx": 24.0}

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
## JSON `projectile` (ranged enemies: {projectileId, assetId, damage, stickMs?}; enemy spec 12.1).
@export var projectile: Dictionary = {}
## JSON `impactEffect` (worm brawler: {effectId, distance}; enemy spec 16).
@export var impact_effect: Dictionary = {}
## JSON `arenaRecoveryMs` (bosses with an arena: heal to full once the player has stayed outside
## the arena this long; 0 = never).
@export var arena_recovery_ms: float = 0.0
## Rework: the `enemy-types.json` type whose `reactions` block this enemy uses ("" = its scene's
## file name; ReactionProfile.type_of).
@export var enemy_type: String = ""
## Rework: reaction profile keys this scene changes, on top of the type's (combat-feel plan
## section 5, "Layers merge in this order").
@export var reaction_overrides: Dictionary = {}

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
## Slow (the slime's goo trail, enemy spec 15): movement x `_slow_multiplier` until `_slowed_until`;
## `_applied_slow` is the factor the last written velocity carries.
var _slowed_until: float = 0.0
var _slow_multiplier: float = 1.0
var _applied_slow: float = 1.0
## Tempo (a honey throw, owner 2026-11-01; `apply_tempo`): everything it does at `_tempo` of its pace
## until `_tempo_until`.
var _tempo: float = 1.0
var _tempo_until: float = 0.0
## Rework: the corpse's slide after a kill launch (ZERO = none; only EnemyReactions sets it), and
## whether it has started (from then on the body's own velocity, which walls cut, carries it).
var _death_slide: Vector2 = Vector2.ZERO
## Rework: a throw's kill send-off (`begin_sendoff`): the corpse pops at `_sendoff_at_ms`, or from
## `_sendoff_from_ms` on once it no longer slides; -1 = no send-off (the corpse lies and goes).
var _sendoff_from_ms: float = -1.0
var _sendoff_at_ms: float = -1.0
## The enemy-ammo prototype: the slime carries it (`begin_carry`), and what `end_carry` puts back
## (the body's and the hurtbox's layers and masks, the body's `visible`).
## Rework: the ground's fates for a body a blow moves (enemy_hazards.gd): the fall that carries it
## over a ledge (`begin_fall`: {from, to, level_from, level_to, started, ms}; {} = none) and its
## corpse's fate in an endless hole or deep water (`begin_fate`: {fate, from, to, started, ms}).
var _fall: Dictionary = {}
var _fate: Dictionary = {}
var _ammo_carried: bool = false
var _ammo_kept: Dictionary = {}
var _death_sliding: bool = false
## Rework: the authored rule a gated hurtbox registered without ({} = registered as authored);
## old-style hits still meet its `acceptedSources` in `can_receive_damage`.
var _authored_rule: Dictionary = {}
## Four-way shooters: the line-up AI (null for every other enemy; made on the first step, after
## the spawner's overrides), the type's `ai` block (read once), the line-up numbers and the bodies
## a probe ignores.
var _line_up: LineUpAI = null
var _line_up_checked: bool = false
var _type_ai: Variant = null
var _align: Dictionary = {}
var _probe_exclude: Array[RID] = []
## The territory's walks (home, to where the slime was last seen): the steering round obstacles
## (made on first use) and the spot it steers to now.
var _way: WayAround = null
var _way_goal: Vector2 = Vector2.INF


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
	_warm_attack_scenes()
	# The enemy-ammo prototype: a helpless enemy can be gulped and thrown (never a boss).
	if rank != RANK_BOSS:
		GulpableEnemy.attach(self)


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
## after the scripts, enemy spec 4.2). In the rework mode EnemyReactions.after_move follows the move
## (wall splats, bowling).
func _physics_process(delta: float) -> void:
	if body == null or _ammo_carried:
		return
	# Rework: a blow sent it over a ledge: the fall owns its body until it lands (`begin_fall`).
	if not _fall.is_empty():
		_step_fall()
		return
	# Rework: the danger zone a blow put it in hurts it on the slime's rhythm (enemy_hazards.gd).
	if ReworkMode.is_on():
		EnemyHazards.step(self)
	var moves := _step_enemy(delta)
	_after_enemy_step(delta)
	if moves and is_instance_valid(body) and not body.is_queued_for_deletion():
		ArcadeMover.move(body, delta)
		if ReworkMode.is_on():
			EnemyReactions.after_move(self, delta)


## Enemy spec 4.2 step order exactly (flash update, defeated, stun slide, no target, arena leash
## (bosses), territory, attack in flight, AI loop, alerted, facing/clip). Returns false only on
## the defeated path (the body does not move). When defeated: velocity 0 and `body.queue_free()`
## once `now >= dispose_at` (enemy spec 7, self-dispose replaces the world-side cleanup).
func _step_enemy(delta: float) -> bool:
	var now := Services.now_ms()
	# Only the territory walk and the AI path write a slowed velocity (enemy spec 15).
	var slow_written := _applied_slow
	_applied_slow = 1.0
	_update_hit_flash(now)
	if _defeated:
		# Rework: a corpse that went into an endless hole or deep water falls or sinks away (`begin_fate`).
		if not _fate.is_empty():
			_step_fate(now)
			_runtime_state = EnemyAI.STATE_DEAD
			return false
		# Rework: a kill launch slides the corpse to where it dies (only it sets a death slide).
		var sliding := _death_slide != Vector2.ZERO and _step_death_slide(delta)
		if not sliding:
			body.velocity = Vector2.ZERO
		_runtime_state = EnemyAI.STATE_DEAD
		# Rework: a throw's kill send-off pops the corpse where it ends (`begin_sendoff`).
		if _sendoff_at_ms >= 0.0 and (now >= _sendoff_at_ms or (not sliding and now >= _sendoff_from_ms)):
			_sendoff_at_ms = -1.0
			EnemyReactions.pop_corpse(self)
			_dispose_at_ms = now
		var fade_ms := _corpse_fade_ms()
		if fade_ms > 0.0 and _dispose_at_ms >= 0.0:
			body.modulate.a = clampf((_dispose_at_ms - now) / fade_ms, 0.0, 1.0)
		if _dispose_at_ms >= 0.0 and now >= _dispose_at_ms and not body.is_queued_for_deletion():
			body.queue_free()
		return sliding

	# Knockback / hit-stun: slide with decay; no AI, no territory, no attack, no clip change. A sleep
	# throw's sleep renews the stun until a damaging hit wakes it.
	if now < _hit_stun_until:
		if ReworkMode.is_on():
			EnemyReactions.keep_asleep(self)
		var decay := EnemyReactions.slide_decay_of(self) if ReworkMode.is_on() else HIT_STUN_VELOCITY_DECAY
		body.velocity *= pow(decay, delta * 60.0)
		return true

	# Rework: on its legs in the danger zone a blow put it in, it walks out the shortest way first.
	if ReworkMode.is_on() and _walk_out_of_zone():
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
				# Round what stands in the way (way_around.gd), never a straight line into a wall.
				walk = _walk_around(territory["move_to"], to_spot, now) * speed
			# It cannot get home: it lives where it stands (a ledge it was knocked off, a gate shut
			# behind it), wandering and fighting there as at home.
			if territory["mode"] == CampTerritory.MODE_RETURNING and _way != null and _way.is_lost(now):
				_territory.settle(origin, _way_number("settleRadiusPx"))
				_way.reset()
				walk = Vector2.ZERO
		else:
			_way_goal = Vector2.INF
		_applied_slow = _current_slow(now)
		body.velocity = walk * _applied_slow
		_update_facing(walk)
		_play_facing("walk" if walk.length() > WALK_SPEED_THRESHOLD else "idle")
		return true
	_way_goal = Vector2.INF
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
		"behavior": _behavior(),
		"preferred_distance": SlimeSpiderAI.preferred_distance(_optional_attribute("fleeRange"), attack_range),
	}
	# Four-way shooters line up on the slime's row or column (enemy spec 20).
	if _line_up_ai() != null:
		_add_line_up_context(context, now, delta, origin, target, distance, territory.is_empty())
	# Authored attack-area reach replaces the attack_range distance rules (EnemyScript.ts:464).
	var reach: Variant = _attack_area_reach(target)
	if reach is bool:
		context["in_attack_reach"] = reach
	# The AI reads back its own unslowed velocity (EnemyScript.ts:449).
	var outcome := EnemyAI.run(_ai_state, body.velocity / slow_written, context)
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
	_applied_slow = _current_slow(now)
	body.velocity = velocity if _applied_slow == 1.0 else velocity * _applied_slow
	if _active_sequence_id == NO_ID:
		# The line-up AI may look along its line while it holds, or at the slime as it scuttles.
		var face: Vector2 = outcome.get("face_dir", Vector2.ZERO)
		_update_facing(face if face != Vector2.ZERO else velocity)
		_play_facing("walk" if velocity.length() > WALK_SPEED_THRESHOLD else "idle")
	return true


# --- API for the spawner / world ---------------------------------------------------------------

## Called by EnemyPopulation right after instancing, before the first physics step: the
## enemy-spawn area record it came from (WorldService.areas("enemy-spawn") entry), or a placed
## enemy's wander record (an "enemy-wander" area, or its own circle: PlacedEnemy.wander_record);
## {} = no camp, then `may_engage = distance <= aggro`; and the safe-zone perimeters. Builds the
## CampTerritory from `spawn_area.stay_perimeter`.
func configure_navigation(spawn_area: Dictionary, safe_zones: Array[Dictionary]) -> void:
	_spawn_area = spawn_area
	_safe_zones = safe_zones
	_territory = null
	var stay: Variant = spawn_area.get("stay_perimeter", {})
	if stay is Dictionary and not (stay as Dictionary).is_empty():
		_territory = CampTerritory.new()
		_territory.setup(stay, targeting_radius, attack_range, _optional_attribute("leashRange"))
		_territory.reengage_margin = _way_number("reengageMarginPx")
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


## True while a common attack sequence runs (Phaser `attacking`).
func is_attacking() -> bool:
	return _active_sequence_id != NO_ID


## `applySlow` (EnemyScript.ts:934-939, enemy spec 15): movement x `multiplier` for `duration_ms`
## (the slime's goo trail). Bosses, defeated enemies, a multiplier outside (0, 1) and a duration
## <= 0 are ignored; a fresh slow replaces a weaker or expired one and never shortens it.
func apply_slow(multiplier: float, duration_ms: float) -> void:
	if rank == RANK_BOSS or _defeated or not (multiplier > 0.0 and multiplier < 1.0) or not (duration_ms > 0.0):
		return
	var now := Services.now_ms()
	if now >= _slowed_until or multiplier <= _slow_multiplier:
		_slow_multiplier = multiplier
	_slowed_until = maxf(_slowed_until, now + duration_ms)


## True while a slow holds this enemy back.
func is_slowed() -> bool:
	return Services.now_ms() < _slowed_until


## Everything it does at `scale` of its pace for `duration_ms` (a honey throw: 0.5, half speed;
## docs/godot/THROW_COMBAT.md): its walk and chase (`_current_slow`, with the goo trail's slow), its
## attack's wind-up, recovery and cooldown (`_begin_attack`), and a patterned enemy's every `pattern`
## time and speed (patterned_enemy.gd). Bosses, defeated enemies, a scale outside (0, 1) and a
## duration <= 0 are ignored; a fresh one replaces a weaker or expired one and never shortens it.
## True when it took.
func apply_tempo(scale: float, duration_ms: float) -> bool:
	if rank == RANK_BOSS or _defeated or not (scale > 0.0 and scale < 1.0) or not (duration_ms > 0.0):
		return false
	var now := Services.now_ms()
	if now >= _tempo_until or scale <= _tempo:
		_tempo = scale
	_tempo_until = maxf(_tempo_until, now + duration_ms)
	return true


## Its pace now (1 = normal; `apply_tempo`).
func tempo() -> float:
	return _tempo if Services.now_ms() < _tempo_until else 1.0


## Lifecycle cancel + end_attack (enemy spec 5.4): called on non-lethal hit, death, target lost,
## territory move/hold and `_exit_tree`.
func cancel_attack() -> void:
	_lifecycle.cancel()
	_end_attack()


# --- rework reaction API (game/combat/reactions/enemy_reactions.gd; docs/godot/BODY_SHAPES.md) ----

## The CharacterBody2D root (`body`).
func get_body() -> CharacterBody2D:
	return body


## The Sprite2D (`visual`; the hit motion moves its offset, scale, rotation and skew).
func get_visual() -> Sprite2D:
	return visual


## Sets the hit-stun end (simulation ms) as given; while `now < it` the enemy slides with the stun
## decay (`combat.verbs.slideDecay` in the rework mode) and does nothing else (no AI, territory,
## attack or clip change). The caller decides how stuns combine (the combat-feel plan: the longer
## wins).
func set_hit_stun_until(until_ms: float) -> void:
	_hit_stun_until = until_ms


## The hit-stun end (simulation ms); in stun while `Services.now_ms()` is below it.
func get_hit_stun_until() -> float:
	return _hit_stun_until


## Restarts `<action>-<facing>` (e.g. the "knockback" hurt pose until reaction poses exist).
func play_hurt(action: String = "knockback") -> void:
	_play_facing(action, true)


## The old hit feedback: the flash and the damage number (`_show_hit_feedback`).
func show_hit_feedback(commit: Dictionary) -> void:
	_show_hit_feedback(commit)


## "up" | "down" | "side", and whether a side clip is mirrored (facing left).
func get_facing_name() -> String:
	return _facing


func is_facing_flipped() -> bool:
	return _facing_flipped


## `attributes[key]` as a finite float, else `fallback` (knockbackResist, attackWindupMs, ...).
func get_attribute(key: String, fallback: float = 0.0) -> float:
	return _attribute(key, fallback)


## Pushes a running attack's impact and end `ms` later (armor: a light hit slips the wind-up; the
## caller caps the total). Nothing without an attack in flight or after its impact.
func delay_attack(ms: float) -> void:
	if _active_sequence_id == NO_ID or _attack_resolved or ms <= 0.0:
		return
	_attack_impact_at += ms
	_attack_finish_at += ms


## The phase the reaction profile's `states` are keyed by ("" = the normal phase). The base enemy
## reports "windup" between an attack's start and its impact; bosses and special enemies override it
## (combat-feel plan section 8: `_reaction_phase()`).
func reaction_phase() -> String:
	# Scripts with a phase machine of their own (Fatty, the Matron, the Clod Stomper) report its
	# phase, which their `reactions.states` are keyed by, until they override this.
	if has_method(&"get_phase"):
		return str(call(&"get_phase"))
	if _active_sequence_id != NO_ID and not _attack_resolved:
		return "windup"
	return ""


## The hit flash alone (`_show_hit_feedback` without the number): the rework's damage number is the
## sender's (`GameFeel.play_hit`).
func flash_hit() -> void:
	_hit_flash_until = Services.now_ms() + HIT_FLASH_MS
	if visual != null:
		HitFlash.flash(visual, HIT_FLASH_COLOR)


## The running attack's sequence id (-1 when none): armor counts its wind-up push per attack.
func attack_sequence() -> int:
	return _active_sequence_id


## The break-free counter (the worm swordsman's counter-slash, the orb weaver's spit): ends the
## stun and starts its common attack toward the target at once, whatever its cooldown. False when it
## cannot (no target, defeated, no attack area).
func begin_counter_attack() -> bool:
	if _defeated or body == null:
		return false
	if _active_sequence_id != NO_ID:
		return true
	var target := _primary_target()
	if target.is_empty() or not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
		return false
	var origin := get_centre()
	var toward: Vector2 = target.get("centre", origin) - origin
	_hit_stun_until = 0.0
	_lifecycle.ready_at = minf(_lifecycle.ready_at, Services.now_ms())
	_begin_attack(toward if toward != Vector2.ZERO else _attack_direction)
	if _active_sequence_id != NO_ID:
		_ai_state = EnemyAI.STATE_CHASE
	return _active_sequence_id != NO_ID


## Damage a reaction deals outside a routed hit (a wall splat's share, a bowling knock): hp, the
## health signal, the hurt sound, the flash, and defeat at 0. Returns the damage dealt (0 once
## defeated).
func take_reaction_damage(amount: float) -> int:
	if _defeated or not (amount > 0.0):
		return 0
	var actual := int(minf(_hp, float(maxi(0, roundi(amount)))))
	if actual <= 0:
		return 0
	_hp = maxf(0.0, _hp - float(actual))
	health_changed.emit(_health_payload())
	var dead := _hp <= 0.0
	var commit := {"request": {"reaction_damage": true}, "result": {"status": "accepted", "reason": "",
		"actual_damage": actual, "defeated": dead, "applied_effects": [], "rejected_effects": []},
		"simulation_time": Services.now_ms(), "receiver": self}
	damaged.emit(commit)
	_hurt_since_territory_step = true
	flash_hit()
	if dead:
		_defeat()
	return actual


## The corpse's slide after a kill launch (`velocity`, decaying as a stun slide): the body keeps its
## collision mask until it stops, so it does not slide through walls.
func set_death_slide(velocity: Vector2) -> void:
	_death_slide = velocity
	_death_sliding = false


## Whether a throw's kill may send this corpse off (EnemyReactions `_can_send_off`): never a boss's
## (its death is its own scene).
func can_send_off() -> bool:
	return body != null and rank != RANK_BOSS


## A throw's kill send-off (EnemyReactions `_send_off`, `combat.rules.killSendoff`): the corpse pops
## (`EnemyReactions.pop_corpse`) and goes at `latest_ms`, or from `earliest_ms` on once it no longer
## slides (it stopped, a wall stopped it), instead of lying DISPOSE_AFTER_DEFEAT_MS and vanishing.
## Called before or just after the defeat; the rewards, the death clip and the death sound are the
## defeat's, as ever.
func begin_sendoff(earliest_ms: float, latest_ms: float) -> void:
	_sendoff_from_ms = minf(earliest_ms, latest_ms)
	_sendoff_at_ms = latest_ms


## A blow sent it over a ledge (enemy_hazards.gd `_fall`): its body flies in a straight line from
## where it stands to `to_feet` on height level `to_level` over `ms` of simulation time, as the
## slime's ledge drop does (jump_sequence.gd): nothing collides on the way, the elevation hides it
## by the depth of the flight (`set_flight`), and on landing it is tracked on `to_level` and
## `EnemyHazards.landed` deals with the rest. The art's arc is the hit motion's (EnemyHitMotion.DROP).
func begin_fall(to_feet: Vector2, to_level: int, ms: float) -> void:
	if body == null or _defeated:
		return
	cancel_attack()
	var world := Services.world()
	var from_level := to_level
	if world != null and world.elevation != null:
		from_level = world.elevation.level_of(body)
	_fall = {"from": body.global_position, "to": to_feet, "level_from": from_level, "level_to": to_level,
		"started": Services.now_ms(), "ms": maxf(1.0, ms)}
	body.velocity = Vector2.ZERO


## True while a fall carries it (`begin_fall`).
func is_falling() -> bool:
	return not _fall.is_empty()


## A corpse's fate (enemy_hazards.gd `_die_into`: "hole" or "water"): instead of lying, sliding or
## popping, the defeated body is taken `over` there (gliding over the first FATE_GLIDE_SHARE of `ms`
## when `glides`, else at once), fades (a hole: late, as it shrinks; water: evenly, as it sinks) and
## is freed after `ms`; `EnemyHazards.fate_done` is told as it goes. Its shrinking, spinning and
## sinking are the hit motion's. FATE_EATEN: a Carnivore Plant's catch (see the constant). Only for a
## defeated enemy.
func begin_fate(fate: String, over: Vector2, ms: float, glides: bool) -> void:
	if body == null or not _defeated:
		return
	_death_slide = Vector2.ZERO
	_death_sliding = false
	_sendoff_at_ms = -1.0
	_dispose_at_ms = -1.0
	body.velocity = Vector2.ZERO
	body.set_deferred(&"collision_mask", 0)
	if not glides:
		body.global_position = over
		body.reset_physics_interpolation()
	_fate = {"fate": fate, "from": body.global_position, "to": over, "started": Services.now_ms(), "ms": maxf(1.0, ms)}


## The enemy lives at `centre` from now on (a fall took it to another level: enemy_hazards.gd): its
## camp territory and its arena leash are let go, so it fights where it is and never walks at the
## cliff to get back (a patterned enemy moves its home there: patterned_enemy.gd).
func settle_at(_centre: Vector2) -> void:
	_territory = null
	_arena = {}
	_returning_to_arena = false


## True while the slime carries it as ammo (`begin_carry` to `end_carry`).
func is_carried() -> bool:
	return _ammo_carried


## The enemy-ammo prototype (game/throw/gulpable_enemy.gd): the slime gulps this enemy. It is taken
## out of play, not killed: its attack is cancelled, its body and its hurtbox leave the physics
## (their layers and masks are kept for `end_carry`), it is hidden, it leaves the "enemy" group (the
## aim help, the hints and the reactions' bowling no longer see it) and its step stops
## (`_physics_process`). It stays alive and valid: `is_defeated` is false, so a room fight, the
## population and a placed enemy still count it standing, and nothing reports its death. False when
## it cannot be carried (defeated, carried already, no body).
func begin_carry() -> bool:
	if _defeated or _ammo_carried or body == null:
		return false
	cancel_attack()
	_ammo_carried = true
	_ammo_kept = {"layer": body.collision_layer, "mask": body.collision_mask, "visible": body.visible}
	body.velocity = Vector2.ZERO
	body.collision_layer = 0
	body.collision_mask = 0
	if damage_area != null:
		_ammo_kept["area_layer"] = damage_area.collision_layer
		_ammo_kept["area_mask"] = damage_area.collision_mask
		damage_area.collision_layer = 0
		damage_area.collision_mask = 0
	body.visible = false
	_hit_stun_until = 0.0
	if is_in_group(ENEMY_GROUP):
		remove_from_group(ENEMY_GROUP)
	return true


## The carried enemy is back in play with its feet at `feet` (world), as it was taken: seen, its
## body and hurtbox in the physics again, in the "enemy" group, its step running. `level` (an int;
## null = as the elevation finds it) is the height level it stands on there (the elevation tracks
## its body on it). What happens to it next (a daze, a landing's damage) is the caller's.
func end_carry(feet: Vector2, level: Variant = null) -> void:
	if not _ammo_carried or body == null:
		return
	_ammo_carried = false
	body.global_position = feet
	body.velocity = Vector2.ZERO
	body.collision_layer = int(_ammo_kept.get("layer", body.collision_layer))
	body.collision_mask = int(_ammo_kept.get("mask", body.collision_mask))
	if damage_area != null:
		damage_area.collision_layer = int(_ammo_kept.get("area_layer", damage_area.collision_layer))
		damage_area.collision_mask = int(_ammo_kept.get("area_mask", damage_area.collision_mask))
	body.visible = bool(_ammo_kept.get("visible", true))
	_ammo_kept = {}
	body.reset_physics_interpolation()
	var world := Services.world()
	if level is int and world != null and world.elevation != null and world.elevation.bodies.has(body):
		world.elevation.track(body, int(level))
	if not is_in_group(ENEMY_GROUP):
		add_to_group(ENEMY_GROUP)


# --- damage receiver API (combat spec 7.2) --------------------------------------------------------

## {"hp": float, "max_hp": float, "dead": bool}.
func get_damage_state() -> Dictionary:
	return {"hp": _hp, "max_hp": max_health, "dead": _defeated}


## {"accepted": false, "reason": "dead"} once defeated, else {"accepted": true, "reason": ""}.
## A rework hit (the request has `hit`) asks EnemyReactions.can_receive instead (a clink answers
## "immune"). On a hurtbox registered without its authored `acceptedSources` (rework mode, a gated
## part), an old-style hit still has to match them ("source-blocked").
func can_receive_damage(input: Dictionary) -> Dictionary:
	if _defeated:
		return {"accepted": false, "reason": "dead"}
	# Carried as ammo: it is in the slime's mouth, nothing reaches it.
	if _ammo_carried:
		return {"accepted": false, "reason": REASON_CARRIED}
	var request: Dictionary = input.get("request", {})
	if ReworkMode.is_rework_request(request):
		return EnemyReactions.can_receive(self, input)
	if not _authored_rule.is_empty() and not DamageResolverScript.source_matches(_authored_rule, request):
		return {"accepted": false, "reason": DamageResolverScript.REASON_SOURCE_BLOCKED}
	return {"accepted": true, "reason": ""}


## The scaled damage as it is (enemies take raw scaled damage); a rework hit x
## EnemyReactions.damage_scale (a shut gate's 0, the part's, the phase's and a knockdown's
## `damageTaken`).
func mitigate_damage(input: Dictionary) -> float:
	var scaled := float(input.get("scaled_damage", 0.0))
	var request: Dictionary = input.get("request", {})
	if ReworkMode.is_rework_request(request):
		return scaled * EnemyReactions.damage_scale(self, input)
	return scaled


## Enemy spec 6.1: hp -= actual; emit health_changed and damaged(commit); mark hurt for the
## territory; react_to_damage (flash, number, cancel attack, knockback (P + 120) * (1 - resist),
## stun 320 + min(280, strength * 0.35), "knockback-<facing>" restart); defeat() when dead.
## A rework hit with no damage plays no hurt sound (`damaged` is not emitted); one whose
## `_react_to_damage` override did not answer `result.reaction` gets EnemyReactions.react_override.
func commit_damage(commit: Dictionary) -> void:
	if _defeated:
		return
	var result: Dictionary = commit.get("result", {})
	var request: Dictionary = commit.get("request", {})
	var rework := ReworkMode.is_rework_request(request)
	_hp = maxf(0.0, _hp - float(result.get("actual_damage", 0)))
	health_changed.emit(_health_payload())
	if not rework or int(result.get("actual_damage", 0)) > 0:
		damaged.emit(commit)
	var is_dead := bool(result.get("defeated", false)) or _hp <= 0.0
	_hurt_since_territory_step = true
	_react_to_damage(commit, is_dead)
	if rework and not result.has("reaction"):
		EnemyReactions.react_override(self, commit, is_dead)
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
	# A honey throw's tempo stretches the cooldown, the wind-up and the recovery (`apply_tempo`).
	var pace := tempo()
	var sequence := _lifecycle.try_begin(now, attack_cooldown_ms / pace)
	if sequence == NO_ID:
		return
	var router := Services.router()
	if attack_area == null or router == null:
		return
	# Four-way shooters shoot only straight up, down, left or right (enemy spec 20), whoever asks
	# (a break-free counter spit too).
	if _line_up_ai() != null:
		direction = LineUpAI.snap_shot(direction)
	if direction.length() > 0.0:
		_attack_direction = direction.normalized()
	_active_sequence_id = sequence
	var areas: Array[Area2D] = [attack_area]
	_active_activation_id = router.begin_activation(self, areas)
	var windup_ms := maxf(0.0, _attribute("attackWindupMs")) / pace
	var recovery_ms := maxf(0.0, _attribute("attackRecoveryMs")) / pace
	_update_facing(_attack_direction)
	var clip_ms := _clip_length_ms("attack-" + _facing)
	_attack_impact_at = now + windup_ms
	_attack_finish_at = now + minf(ATTACK_SEQUENCE_MAX_MS,
		maxf(windup_ms + recovery_ms, clip_ms) + ATTACK_SEQUENCE_PADDING_MS)
	_attack_resolved = false
	_set_attack_area_active(true)
	_play_facing("attack", true)
	attack_started.emit({"ranged": not _projectile_config().is_empty(), "windupMs": windup_ms})


## Enemy spec 5.3: one impact check per swing; centre distance <= attack_range * 1.35 routes a
## request to the player hurtbox (weapon_id "enemy-contact", tags ["contact", "enemy"], base
## damage attributes.contactDamage, knockback potency attributes.knockbackStrength, impact at the
## enemy centre, knock = normalized(player centre - enemy centre)); an accepted hit with damage
## spawns the impact effect (spec 16). Ranged enemies fire their projectile instead, from the
## centre along the attack direction, whatever the distance (spec 12.2).
func _resolve_attack(target: Dictionary, origin: Vector2) -> void:
	_attack_resolved = true
	var router := Services.router()
	if _active_activation_id <= 0 or attack_area == null or router == null:
		return
	if not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
		return
	var ranged := _projectile_config()
	if not ranged.is_empty():
		_fire_projectile(origin, ranged)
		return
	# Throw combat (docs/godot/THROW_COMBAT.md): a Worm Brawler's blow may knock a rock loose, ahead of
	# its feet (the body's ground point) on the ground's level there.
	ThrowAmmo.knock_loose(enemy_type if not enemy_type.is_empty() or body == null \
		else body.scene_file_path.get_file().get_basename(), body.global_position if body != null else origin,
		_attack_direction)
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
	var result := router.route(request)
	if str(result.get("status", "")) == "accepted" and int(result.get("actual_damage", 0)) > 0:
		_spawn_impact_effect(origin)


## `fireProjectile` (EnemyScript.ts:758-768): the world's `spawnEnemyProjectile` (enemy spec 12.3).
func _fire_projectile(origin: Vector2, config: Dictionary) -> void:
	EnemyProjectiles.fire({
		"source": self,
		"position": origin,
		"direction": _attack_direction,
		"speed": _attribute("projectileSpeed", DEFAULT_PROJECTILE_SPEED),
		"damage": float(config["damage"]),
		"knockback_strength": _attribute("knockbackStrength"),
		"projectile_id": str(config["projectile_id"]),
		"asset_id": str(config["asset_id"]),
		"stick_ms": float(config["stick_ms"]),
	})


## `projectileConfiguration` (EnemyScript.ts:900-908, enemy spec 12.1): {} unless `projectile`
## has a numeric `damage` and a `projectileId` or `assetId`; else {"projectile_id", "asset_id",
## "damage", "stick_ms" (0 unless > 0)}.
func _projectile_config() -> Dictionary:
	var damage: Variant = projectile.get("damage")
	if not (damage is float or damage is int):
		return {}
	var projectile_id: Variant = projectile.get("projectileId")
	var asset_id: Variant = projectile.get("assetId")
	var id_text := str(projectile_id) if projectile_id is String else ""
	var asset_text := str(asset_id) if asset_id is String else ""
	if id_text.is_empty() and asset_text.is_empty():
		return {}
	var stick: Variant = projectile.get("stickMs")
	var stick_ms := float(stick) if (stick is float or stick is int) and float(stick) > 0.0 else 0.0
	return {"projectile_id": id_text, "asset_id": asset_text, "damage": float(damage), "stick_ms": stick_ms}


## `spawnImpactEffect` (EnemyScript.ts:797-806, enemy spec 16): `effect.<effectId>` at the centre
## pushed `distance` along the attack direction; nothing without a string `effectId`.
func _spawn_impact_effect(origin: Vector2) -> void:
	var effect_id: Variant = impact_effect.get("effectId")
	if not effect_id is String:
		return
	var distance_value: Variant = impact_effect.get("distance")
	var distance := float(distance_value) if (distance_value is float or distance_value is int) \
		and is_finite(float(distance_value)) else 0.0
	_spawn_effect_at(effect_id, origin + _attack_direction * distance)


## Loads the projectile scene and the impact effect this enemy spawns, so the first shot or hit
## does not read them from disk mid-fight (enemy spec 19).
func _warm_attack_scenes() -> void:
	var world := Services.world()
	if world == null:
		return
	var ranged := _projectile_config()
	if not ranged.is_empty() and not str(ranged["projectile_id"]).is_empty():
		world.packed_scene("projectile." + str(ranged["projectile_id"]))
	var effect_id: Variant = impact_effect.get("effectId")
	if effect_id is String and not (effect_id as String).is_empty():
		world.packed_scene("effect." + effect_id)


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
		# stays registered (later hits are rejected "dead"). A rework kill launch keeps the mask
		# while the corpse slides (`_step_death_slide` clears it).
		body.set_deferred(&"collision_layer", 0)
		if _death_slide == Vector2.ZERO:
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
	# Rework: the kill feel and the energy shard roll.
	if ReworkMode.is_on():
		EnemyReactions.on_defeated(self)


## Enemy spec 6.2 reaction (ordinary enemies): `react_classic`. A rework hit (the request has `hit`)
## gets the shared reaction instead (EnemyReactions.react, which writes `result.reaction`).
func _react_to_damage(commit: Dictionary, is_dead: bool) -> void:
	var request: Dictionary = commit.get("request", {})
	if ReworkMode.is_rework_request(request):
		EnemyReactions.react(self, commit, is_dead)
		return
	# An old hit that hurts wakes a sleeper too (the rework's are woken in `react`).
	if ReworkMode.is_on():
		EnemyReactions.wake_if_hurt(self, commit)
	react_classic(commit, is_dead)


## The old reaction (enemy spec 6.2, ordinary enemies): feedback always; on a non-lethal hit cancel
## the attack, knock back and stun. Public for EnemyReactions' fallback.
func react_classic(commit: Dictionary, is_dead: bool) -> void:
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
## (`Services.feel().floating_text`). A rework hit gets the flash only (its number is the
## sender's `GameFeel.play_hit`, which follows the Damage numbers setting).
func _show_hit_feedback(commit: Dictionary) -> void:
	_hit_flash_until = Services.now_ms() + HIT_FLASH_MS
	if visual != null:
		HitFlash.flash(visual, HIT_FLASH_COLOR)
	if ReworkMode.is_rework_request(commit.get("request", {})):
		return
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


## The unit heading of a territory walk to `spot` (`to_spot` away), round what stands in the way
## (way_around.gd); a new spot starts a new walk.
func _walk_around(spot: Vector2, to_spot: Vector2, now: float) -> Vector2:
	if _way == null:
		_way = WayAround.new()
	if _way_goal == Vector2.INF or _way_goal.distance_to(spot) > 1.0:
		_way.reset()
		_way_goal = spot
	return _way.heading(body, to_spot, now)


## `combat.wayAround.<key>` (0 when missing).
static func _way_number(key: String) -> float:
	var constants := Services.constants()
	var value: Variant = constants.value(WayAround.BLOCK + "." + key) if constants != null else null
	return float(value) if value is float or value is int else 0.0


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


## `attributes[key]` when it is a String, else "".
func _attribute_string(key: String) -> String:
	var value: Variant = attributes.get(key)
	return value if value is String else ""


# --- four-way shooters (enemy spec 20) -------------------------------------------------------------

## The behaviour: `attributes.behavior`, else the type's `ai.behavior` in enemy-types.json (the
## Worm Archer's "liner-up"); "" for none.
func _behavior() -> String:
	var value: Variant = _ai_value("behavior")
	return value if value is String else ""


## `attributes[key]` when the scene (or a placed enemy's overrides) sets it, else the type's
## `ai[key]` in enemy-types.json, else null.
func _ai_value(key: String) -> Variant:
	if attributes.has(key):
		return attributes[key]
	if _type_ai == null:
		_type_ai = _type_ai_block()
	return (_type_ai as Dictionary).get(key)


## `_ai_value(key)` as a finite float, else `fallback`.
func _ai_number(key: String, fallback: float) -> float:
	var value: Variant = _ai_value(key)
	if value is float or value is int:
		var number := float(value)
		if is_finite(number):
			return number
	return fallback


## The `ai` block of this enemy's type in enemy-types.json (`enemy_type`, else its scene's file
## name; {} when none).
func _type_ai_block() -> Dictionary:
	var type_id := enemy_type
	if type_id.is_empty() and body != null:
		type_id = body.scene_file_path.get_file().get_basename()
	var constants := Services.constants()
	var data: Variant = constants.data_file(AI_TYPES_FILE) if constants != null else null
	var types: Variant = (data as Dictionary).get("types", {}) if data is Dictionary else {}
	var entry: Variant = (types as Dictionary).get(type_id, {}) if types is Dictionary else {}
	var block: Variant = (entry as Dictionary).get(TYPE_AI_KEY, {}) if entry is Dictionary else {}
	return block if block is Dictionary else {}


## The line-up AI of a four-way shooter (made on first use), else null: the "liner-up" behaviour
## (the Worm Archer), or the spiders' "slime-spider" when the type has an `alignSpeed` (the Slime
## Spider, the Orb-weaver; the Orb-Weaver Matron has none and keeps its orbit). The numbers: the
## `ai` keys `alignSpeed`, `backOffSpeed`, `alignTolerancePx`, `alignMarginPx`, `alignReplanMs`
## and `alignSwitchPx` (a missing one falls back to LINE_UP_DEFAULTS, the speeds to
## `movement_speed`).
func _line_up_ai() -> LineUpAI:
	if _line_up_checked:
		return _line_up
	_line_up_checked = true
	var behavior := _behavior()
	if behavior != BEHAVIOR_LINER_UP and not (behavior == BEHAVIOR_SLIME_SPIDER and _ai_number("alignSpeed", 0.0) > 0.0):
		return null
	_line_up = LineUpAI.new()
	_align = {
		"speed": _ai_number("alignSpeed", movement_speed),
		"back_off_speed": _ai_number("backOffSpeed", movement_speed),
		"tolerance": _ai_number("alignTolerancePx", LINE_UP_DEFAULTS["alignTolerancePx"]),
		"margin": _ai_number("alignMarginPx", LINE_UP_DEFAULTS["alignMarginPx"]),
		"replan_ms": _ai_number("alignReplanMs", LINE_UP_DEFAULTS["alignReplanMs"]),
		"switch_px": _ai_number("alignSwitchPx", LINE_UP_DEFAULTS["alignSwitchPx"]),
	}
	return _line_up


## The line-up AI's context keys (line_up_ai.gd). Without a camp it still has to see the slime to
## notice it (a camp's territory checks the sight itself).
func _add_line_up_context(context: Dictionary, now: float, delta: float, origin: Vector2,
		target: Dictionary, distance: float, no_territory: bool) -> void:
	context["line_up"] = _line_up
	context["align"] = _align
	context["aim_point"] = _aim_point(target)
	context["now"] = now
	context["step_s"] = delta
	context["attacking"] = _active_sequence_id != NO_ID
	context["faces_target"] = _behavior() == BEHAVIOR_SLIME_SPIDER
	context["route_clear"] = _route_clear
	context["shot_clear"] = _shot_clear
	_probe_exclude.clear()
	_probe_exclude.append(body.get_rid())
	var player_body := target.get("body") as CharacterBody2D
	if player_body != null:
		_probe_exclude.append(player_body.get_rid())
	if no_territory:
		context["may_engage"] = distance <= targeting_radius and _sees_target(now, origin, target, distance)


## Where a shot has to pass to hit the slime: the middle of its hurtbox's shape (14.56 px below
## the slime's old centre); the centre when it has none.
func _aim_point(target: Dictionary) -> Vector2:
	var centre: Vector2 = target.get("centre", get_centre())
	var hurtbox := target.get("hurtbox") as Area2D
	if hurtbox == null:
		return centre
	for child: Node in hurtbox.get_children():
		if child is CollisionShape2D and not (child as CollisionShape2D).disabled:
			return (child as CollisionShape2D).global_position
	return centre


## The line-up AI's way probe: the body's own shape moved by `to - from` meets nothing it collides
## with (walls, water, a fence, the slime).
func _route_clear(from: Vector2, to: Vector2) -> bool:
	if body == null or not body.is_inside_tree():
		return true
	return not body.test_move(body.global_transform, to - from)


## The line-up AI's shot probe: nothing on the world layer (what stops an arrow or a web) between
## `from` and `to` (WorldService.line_of_sight).
func _shot_clear(from: Vector2, to: Vector2) -> bool:
	var world := Services.world()
	return world == null or world.line_of_sight(from, to, _probe_exclude)


## The movement factor of a slow at `now` (1 when not slowed).
func _current_slow(now: float) -> float:
	return (_slow_multiplier if now < _slowed_until else 1.0) * (_tempo if now < _tempo_until else 1.0)


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
## Rework mode: a hurtbox the reaction profile gates as a part drops `acceptedSources` (the gate
## decides for rework hits; `_authored_rule` keeps them for old hits, see `can_receive_damage`).
func _receiver_rule() -> Dictionary:
	var rule := damage_rule.duplicate(true)
	if not rule.has("priority"):
		rule["priority"] = 0
	if not rule.has("damageMultiplier"):
		rule["damageMultiplier"] = 1
	if ReworkMode.is_on() and rule.has("acceptedSources") and EnemyReactions.is_gated(self, damage_area):
		_authored_rule = rule.duplicate(true)
		rule.erase("acceptedSources")
	return rule


## Rework: one step of a fall (`begin_fall`): the body on the straight line to its landing, hidden by
## the flight's depth; landed, it is tracked on its new level and EnemyHazards deals with the rest.
func _step_fall() -> void:
	var t := clampf((Services.now_ms() - float(_fall["started"])) / float(_fall["ms"]), 0.0, 1.0)
	var from: Vector2 = _fall["from"]
	var to: Vector2 = _fall["to"]
	var level_from := int(_fall["level_from"])
	var level_to := int(_fall["level_to"])
	var world := Services.world()
	var elevation: Node = world.elevation if world != null and world.elevation != null and is_instance_valid(world.elevation) else null
	body.global_position = from.lerp(to, t)
	body.velocity = Vector2.ZERO
	if elevation != null:
		elevation.call(&"set_flight", body, lerpf(from.y + float(level_from) * FALL_LEVEL_UNITS, to.y + float(level_to) * FALL_LEVEL_UNITS, t))
	if t < 1.0:
		return
	_fall = {}
	if elevation != null:
		elevation.call(&"end_flight", body)
		elevation.call(&"track", body, level_to)
	body.reset_physics_interpolation()
	EnemyHazards.landed(self, level_from - level_to)


## Rework: one step of a corpse's fate (`begin_fate`): it glides out, fades and is gone.
func _step_fate(now: float) -> void:
	var t := clampf((now - float(_fate["started"])) / float(_fate["ms"]), 0.0, 1.0)
	var glide := clampf(t / FATE_GLIDE_SHARE, 0.0, 1.0)
	body.global_position = (_fate["from"] as Vector2).lerp(_fate["to"], 1.0 - (1.0 - glide) * (1.0 - glide))
	body.velocity = Vector2.ZERO
	var eaten := str(_fate["fate"]) == FATE_EATEN
	if eaten:
		body.modulate.a = 1.0 - pow(t, EATEN_FADE_POW)
	else:
		body.modulate.a = 1.0 - t * t if str(_fate["fate"]) == EnemyHazards.FATE_HOLE else 1.0 - t
	if t < 1.0 or body.is_queued_for_deletion():
		return
	if not eaten:
		EnemyHazards.fate_done(self)
	body.queue_free()


## Rework: an enemy on its legs in the danger zone a blow put it in walks out the shortest way
## (EnemyHazards.walk_out) before anything else; true while it does.
func _walk_out_of_zone() -> bool:
	var way := EnemyHazards.walk_out(self)
	if way == Vector2.ZERO:
		return false
	cancel_attack()
	body.velocity = way * EnemyHazards.walk_out_speed()
	return true


## Rework: one step of the corpse's slide after a kill launch (the stun slide's decay); under
## WALK_SPEED_THRESHOLD it ends and the body stops colliding, as every corpse does. Returns true while
## the body still moves.
func _step_death_slide(delta: float) -> bool:
	var slide := body.velocity if _death_sliding else _death_slide
	_death_sliding = true
	slide *= pow(EnemyReactions.slide_decay_of(self), delta * 60.0)
	if slide.length() < WALK_SPEED_THRESHOLD:
		_death_slide = Vector2.ZERO
		_death_sliding = false
		body.set_deferred(&"collision_mask", 0)
		return false
	_death_slide = slide
	body.velocity = slide
	return true


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


## The defeated body fades out over this many ms before it frees itself; 0 = it just goes
## (ordinary enemies, as in Phaser). Bosses return BOSS_CORPSE_FADE_MS.
func _corpse_fade_ms() -> float:
	return 0.0


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
## was accepted with damage > 0; then the impact effect plays unless `impact_effect` is false
## (Fatty's landing and the Matron's volley pass false, as in Phaser).
func _route_immediate_attack(target: Dictionary, base_damage: float, knockback_strength: float,
		max_range: float = -1.0, impact_effect_on_hit: bool = true) -> bool:
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
	var hit := str(result.get("status", "")) == "accepted" and int(result.get("actual_damage", 0)) > 0
	if hit and impact_effect_on_hit:
		_spawn_impact_effect(origin)
	router.end_activation(activation_id)
	return hit


## `spawnEffectAt` (EnemyScript.ts:702-704): `effect.<id>` (direction "right") with its root at an
## old Phaser point; nothing for "".
func _spawn_effect_at(effect_id: String, point: Vector2) -> void:
	if effect_id.is_empty():
		return
	var world := Services.world()
	if world != null:
		world.spawn_at_phaser_position("effect." + effect_id, point)


## `shakeCamera` (EnemyScript.ts:714-716): nothing unless both values are > 0, else the
## "boss-landing" feel with this shake (its hit-stop, 0, from the preset).
func _shake_camera(duration_ms: float, intensity: float) -> void:
	if duration_ms <= 0.0 or intensity <= 0.0:
		return
	var feel := Services.feel()
	if feel == null:
		return
	feel.shake(duration_ms, intensity)
	feel.hit_stop(float((GameFeelType.PRESETS[BOSS_LANDING_FEEL] as Dictionary)["hit_stop_ms"]))


## `targetOverlapsShapes` (EnemyScript.ts:635-639) against the player's hurtbox (its centre when it
## has no shapes).
func _target_overlaps(shapes: Array[Dictionary], target: Dictionary) -> bool:
	if target.is_empty():
		return false
	var hurtbox := target.get("hurtbox") as Area2D
	return AreaShapes.overlaps_area(shapes, hurtbox, target.get("centre", Vector2.INF))
