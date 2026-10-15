extends RefCounted
## Applies rework hits to enemies (combat-feel plan sections 5-7; BODY_SHAPES.md "The reaction").
## game/scripts/enemy.gd calls it only for requests that carry a top-level `hit` (rework attacks)
## and, for the per-step and defeat hooks, only in the rework mode:
##
## - `react(enemy, commit, is_dead)` from `_react_to_damage`: `HitReaction.decide(profile, hit,
##   state, now)`, then applies the verb through the enemy's public wrappers and writes
##   `commit.result.reaction`, the same Dictionary DamageRouter.route() returns to the sender:
##   - every verb but armor, clink and the suck's resist cancels the enemy's attack (its swing, shot
##     or lunge, before its impact) and plays its hurt pose; the stun takes the longer of the old and
##     the new one (`set_hit_stun_until`), and until it ends the enemy's own step does nothing but
##     slide (no chase, territory, new attack or clip change; enemy.gd `_step_enemy`). Light and
##     medium enemies have no wind-up armor: only heavy enemies and bosses absorb hits (armor);
##   - hold, bounce, stagger, knockdown and daze stop the body where it is; knockback and launch set
##     its velocity along the knock at `launch_speed` x `knockbackScale`, capped at
##     `combat.verbs.launch.maxSpeed` (the enemy's own stun step then slides it with
##     `combat.verbs.slideDecay`); a kill launches x `combat.rules.killLaunchScale` and the corpse
##     slides to where it dies; a tiny enemy's kill pops (the pop streak raises the pitch);
##   - armor on a wind-up pushes it `combat.verbs.armor.windupPushMs` later, at most `maxMs` per
##     attack;
##   - the break-free move (`breakFree`): a push away at `pushSpeedScale` x the shape's finisher
##     speed, a hop back `breakFreePx`, a skitter aside (and a spit), or a counter-slash, with the
##     `breakFreeArmorMs` armor and a yellow-white outline flash and a goo puff as its tell;
##   - the hit motion (game/feel/enemy_hit_motion.gd) by verb and weight: the nudge and squash
##     (light enemies 1.5x, elastic), the Hammer's flatten, the bounce hop, the lean, the tumble, the
##     fall, the daze sway and stars, the heavy shake, the boss belly wobble; and the hit flash
##     (GameFeel's white-then-tint `flash_hit` when it has one, else the enemy's own, else the
##     motion's for a dummy). The damage number is the sender's (`GameFeel.play_hit`, which follows
##     the Damage numbers setting).
## - `react_override(enemy, commit, is_dead)` from `commit_damage` for bosses whose own
##   `_react_to_damage` ran (Fatty, the Matron keep their phase flow): the reaction is decided and
##   written, and only its motion plays.
## - `can_receive(enemy, input)` from `can_receive_damage` (after its dead check): a clink (an immune
##   class or a shut hurtbox gate) answers {"accepted": false, "reason": "immune"}.
## - `damage_scale(enemy, input)` from `mitigate_damage`: the gate's 0, the part's, the phase's and a
##   knockdown's `damageTaken`.
## - `after_move(enemy, delta)` from `_physics_process` after the body moved: while a launch flies,
##   the wall splat (the mover's collider is not an enemy or the slime, hit faster than
##   `combat.rules.wallSplat.minSpeed` into the wall: a squash, `damageShare` of the launching hit
##   again, `hitStopMs` and `trauma`, a bounce back `bouncePx`, a daze `dazeMs` that cancels its
##   attack, once per chain) and
##   bowling (another enemy's body in the way, standing (not in flight itself) and moved into at
##   `bowling.minSpeed` or more, takes `bowling.speedShare` of the speed as its own launch, and both
##   take `bowling.damage`; each body once per launch).
## - `on_defeated(enemy)` from `_defeat`: the death puff, and the energy shard roll
##   (`combat.energyShard`: dropChance, amount, pickupRadiusPx, fadeMs?), never for training dummies.
## The training dummy (game/scripts/training_dummy.gd) calls `react` too, with `is_dead` false. A
## scene dummy has no body, stun or attack, so only its motion, flash and memory change; the shapes
## testbed's dummies have a CharacterBody2D (`get_body`) and a stun, so they slide, launch, splat
## and bowl like an enemy (and are found as one: `_enemy_of`), and never attack or fall.
##
## The enemy side it uses (EnemyScript public wrappers): get_body(), get_visual(),
## set_hit_stun_until(ms), get_hit_stun_until(), play_hurt(action), flash_hit(), cancel_attack(),
## react_classic(commit, is_dead), get_centre(), is_defeated(), delay_attack(ms), attack_sequence(),
## reaction_phase(), begin_counter_attack(), take_reaction_damage(amount), set_death_slide(v), and
## the exports enemy_type and reaction_overrides (the dummy: get_visual(), get_centre(),
## is_defeated(), reaction_preset, reaction_overrides, and get_body(), set_hit_stun_until(ms),
## get_hit_stun_until()). Every call is guarded with has_method.
##
## Owner: reactions.

const Services := preload("res://game/shared/services.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const ReactionProfile := preload("res://game/combat/reactions/reaction_profile.gd")
const ReactionState := preload("res://game/combat/reactions/reaction_state.gd")
const EnemyHitMotion := preload("res://game/feel/enemy_hit_motion.gd")
const ArcadeMover := preload("res://game/shared/arcade_mover.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const EnergyShard := preload("res://game/combat/reactions/energy_shard.gd")

## Meta key of an enemy's ReactionState.
const STATE_META := &"reaction_state"
## Node name of an enemy's EnemyHitMotion (a child of its script node).
const MOTION_NODE := "HitMotion"
## A hurtbox's part name: this meta on the Area2D, else its node name in snake_case ("Eye" -> "eye").
const PART_META := &"reaction_part"
const REASON_IMMUNE := "immune"
const HURT_ACTION := "knockback"
const ENEMY_GROUP := &"enemy"
const WINDUP_PHASE := "windup"
## Weights (combat.weights).
const LIGHT_WEIGHTS: Array[String] = ["tiny", "light"]
const HEAVY_WEIGHTS: Array[String] = ["heavy", "boss"]
const WEIGHT_BOSS := "boss"
const MATERIAL_GOO := "goo"
## The shape whose smash holds flatten.
const SHAPE_HAMMER := "hammer"
const SHAPE_AXE := "axe"
## Presentation (combat-feel plan section 6 "By weight class"): light enemies squash 1.5x with an
## elastic return; medium ones 0.9 / 1.1; the heavy shake and the boss belly jiggle.
const LIGHT_AMPLITUDE := 1.5
const MEDIUM_ALONG := 0.9
const MEDIUM_ACROSS := 1.1
const HEAVY_SHAKE_PX := 2.0
const BOSS_WOBBLE_RAD := 0.06
const BOSS_JIGGLE := 0.06
const STAGGER_JIGGLE := 0.04
const CLINK_SHAKE_PX := 1.5
const CLINK_SHAKE_MS := 80.0
const DUMMY_FLASH_MS := 60.0
const PUFF_GOO := &"slime-splash"
## A small puff at the enemy (the big `dust-puff` cloud is a restored building's).
const PUFF_DUST := &"dodge-dust"
## Bowling looks for at most this many bodies in the way per step.
const BOWL_QUERY_MAX := 8

## The pop streak (combat.rules.popStreak): pops so far and when the last one was.
static var _pop_steps: int = 0
static var _pop_at_ms: float = -INF


## A rework hit on `enemy` was committed (`commit` as DamageRouter commits it): decide, apply,
## write `result.reaction`. An old request gets the old reaction (`react_classic`).
static func react(enemy: Node, commit: Dictionary, is_dead: bool) -> void:
	if enemy == null:
		return
	var request: Dictionary = commit.get("request", {})
	var hit := HitReaction.hit_of(request)
	var result: Variant = commit.get("result")
	if hit.is_empty() or not result is Dictionary:
		if enemy.has_method(&"react_classic"):
			enemy.call(&"react_classic", commit, is_dead)
		return
	var now := Services.now_ms()
	var profile := ReactionProfile.for_enemy(enemy)
	var state := _prepare(enemy, request, profile)
	var damage := float((result as Dictionary).get("actual_damage", 0))
	var answer := HitReaction.decide(profile, hit, state, now)
	_annotate(answer, profile)
	var knock := _knock_of(enemy, hit, request)
	_flash(enemy, hit)
	if is_dead:
		_apply_kill(enemy, profile, state, hit, answer, knock, damage, now)
	else:
		_apply(enemy, profile, state, hit, answer, knock, _origin_of(enemy, request), damage, now)
	(result as Dictionary)["reaction"] = answer


## A rework hit on an enemy whose own `_react_to_damage` ran instead of `react` (Fatty and the
## Matron keep their phase flow: no stun, shove or attack cancel from here). The reaction is
## decided (the memory stays right) and written, and only its motion plays.
static func react_override(enemy: Node, commit: Dictionary, is_dead: bool) -> void:
	if enemy == null:
		return
	var request: Dictionary = commit.get("request", {})
	var hit := HitReaction.hit_of(request)
	var result: Variant = commit.get("result")
	if hit.is_empty() or not result is Dictionary:
		return
	var now := Services.now_ms()
	var profile := ReactionProfile.for_enemy(enemy)
	var state := _prepare(enemy, request, profile)
	var answer := HitReaction.decide(profile, hit, state, now)
	_annotate(answer, profile)
	answer["override"] = true
	if not is_dead:
		_play_motion(enemy, profile, state, hit, answer, _knock_of(enemy, hit, request))
	(result as Dictionary)["reaction"] = answer


## Whether `enemy` takes the rework hit in `input` (the receiver input of `can_receive_damage`): a
## clink (an immune class, or a shut gate whose verb is neither daze nor knockdown) is refused as
## "immune" with a small shake; everything else is accepted.
static func can_receive(enemy: Node, input: Dictionary) -> Dictionary:
	var request: Dictionary = input.get("request", {})
	var hit := HitReaction.hit_of(request)
	if enemy == null or hit.is_empty():
		return {"accepted": true, "reason": ""}
	var profile := ReactionProfile.for_enemy(enemy)
	var state := _prepare(enemy, request, profile)
	if HitReaction.gate(profile, hit, state) == HitReaction.GATE_CLINK:
		var motion := motion_of(enemy)
		if motion != null:
			motion.play(EnemyHitMotion.JITTER, Vector2.ZERO, {"px": CLINK_SHAKE_PX, "ms": CLINK_SHAKE_MS})
		return {"accepted": false, "reason": REASON_IMMUNE}
	return {"accepted": true, "reason": ""}


## The damage multiplier of the rework hit in `input` on `enemy` (`mitigate_damage`): 0 through a
## shut gate whose daze or knockdown still lands, x the part's, the phase's and a knockdown's
## `damageTaken`. 1 for an old request.
static func damage_scale(enemy: Node, input: Dictionary) -> float:
	var request: Dictionary = input.get("request", {})
	var hit := HitReaction.hit_of(request)
	if enemy == null or hit.is_empty():
		return 1.0
	var profile := ReactionProfile.for_enemy(enemy)
	var state := _prepare(enemy, request, profile)
	return HitReaction.damage_scale(profile, hit, state, Services.now_ms())


## True when `area` (one of `enemy`'s hurtboxes) is a part its reaction profile gates
## (`parts`): in the rework mode the gate replaces the hurtbox's `acceptedSources` (enemy.gd
## `_receiver_rule`).
static func is_gated(enemy: Node, area: Area2D) -> bool:
	if enemy == null or area == null:
		return false
	return not _part_of(ReactionProfile.for_enemy(enemy), area).is_empty()


## After `enemy`'s body moved this physics step (rework mode only): while a launch flies, bowling
## and the wall splat. Cheap when the enemy was never launched.
static func after_move(enemy: Node, _delta: float) -> void:
	if enemy == null or not enemy.has_meta(STATE_META):
		return
	var state := state_of(enemy)
	var now := Services.now_ms()
	if now >= state.launch_until_ms:
		return
	var body := _body_of(enemy)
	if body == null or not body.is_inside_tree():
		return
	_bowl(enemy, body, state, now)
	if _defeated(enemy):
		return
	var info: Variant = body.get_meta(ArcadeMover.COLLISION_META) if body.has_meta(ArcadeMover.COLLISION_META) else null
	if info is Dictionary and int((info as Dictionary).get("frame", -1)) == Engine.get_physics_frames():
		_try_splat(enemy, body, state, info, now)


## `enemy` was defeated (any hit, rework or not; rework mode only): the stars go, the death puff
## plays and the energy shard rolls (`combat.energyShard.dropChance`; never for a training dummy).
static func on_defeated(enemy: Node) -> void:
	if enemy == null or _is_dummy(enemy):
		return
	var existing := enemy.get_node_or_null(NodePath(MOTION_NODE)) as EnemyHitMotion
	if existing != null:
		existing.hide_stars()
	var profile := ReactionProfile.for_enemy(enemy)
	_puff(enemy, profile)
	var constants := Services.constants()
	var body := _body_of(enemy)
	if constants == null or body == null:
		return
	if randf() >= constants.number("combat.energyShard.dropChance"):
		return
	var fade: Variant = constants.value("combat.energyShard.fadeMs", 0.0)
	EnergyShard.spawn(body.global_position, constants.number("combat.energyShard.amount"),
		constants.number("combat.energyShard.pickupRadiusPx"), float(fade) if (fade is float or fade is int) else 0.0)


## `enemy`'s reaction memory, made on first use.
static func state_of(enemy: Node) -> ReactionState:
	if enemy == null:
		return ReactionState.new()
	var existing: Variant = enemy.get_meta(STATE_META) if enemy.has_meta(STATE_META) else null
	if existing is ReactionState:
		return existing
	var state := ReactionState.new()
	enemy.set_meta(STATE_META, state)
	return state


## `enemy`'s hit motion (a child named MOTION_NODE of its script node), made on first use with its
## `get_visual()` sprite; null without a sprite.
static func motion_of(enemy: Node) -> EnemyHitMotion:
	if enemy == null:
		return null
	var existing := enemy.get_node_or_null(NodePath(MOTION_NODE)) as EnemyHitMotion
	if existing != null:
		return existing
	var sprite: Sprite2D = null
	if enemy.has_method(&"get_visual"):
		sprite = enemy.call(&"get_visual") as Sprite2D
	if sprite == null:
		return null
	var motion := EnemyHitMotion.new()
	motion.name = MOTION_NODE
	enemy.add_child(motion)
	motion.setup(sprite)
	return motion


## The per-step slide decay of a stunned body (`combat.verbs.slideDecay`, per 60 Hz step).
static func slide_decay() -> float:
	return _number("combat.verbs.slideDecay")


## The start speed (px/s) that makes a stunned body's slide (`slide_decay` per 60 Hz step) cover
## `px` in `ms`.
static func speed_for_distance(px: float, ms: float) -> float:
	if px <= 0.0:
		return 0.0
	var ticks := float(maxi(1, Engine.physics_ticks_per_second))
	var step_decay := pow(clampf(slide_decay(), 0.0, 1.0), 60.0 / ticks)
	var steps := maxf(1.0, ms / 1000.0 * ticks)
	var covered := steps / ticks
	if step_decay < 1.0:
		covered = step_decay * (1.0 - pow(step_decay, steps)) / (1.0 - step_decay) / ticks
	return px / covered if covered > 0.0 else 0.0


# --- applying a reaction ------------------------------------------------------------------------

## The memory with this hit's phase (`reaction_phase()`) and hurtbox part set.
static func _prepare(enemy: Node, request: Dictionary, profile: Dictionary) -> ReactionState:
	var state := state_of(enemy)
	state.phase = str(enemy.call(&"reaction_phase")) if enemy.has_method(&"reaction_phase") else ""
	state.part = _part_of(profile, request.get("target_area"))
	return state


## The hurtbox's part when the profile has one by that name ("" otherwise).
static func _part_of(profile: Dictionary, area: Variant) -> String:
	if not area is Area2D or not is_instance_valid(area):
		return ""
	var hurtbox := area as Area2D
	var part := str(hurtbox.get_meta(PART_META)) if hurtbox.has_meta(PART_META) else String(hurtbox.name).to_snake_case()
	return part if not HitReaction.part_entry(profile, part).is_empty() else ""


## Extra keys for the sender's juice: the enemy's weight and material.
static func _annotate(answer: Dictionary, profile: Dictionary) -> void:
	answer["weight"] = str(profile.get("weight", ""))
	answer["material"] = str(profile.get("material", ""))


## The push's unit direction: the request's knock (per target), else the hit's, else from the impact
## point to the enemy.
static func _knock_of(enemy: Node, hit: Dictionary, request: Dictionary) -> Vector2:
	var impact: Variant = request.get("impact", {})
	var knock := Vector2.ZERO
	if impact is Dictionary and (impact as Dictionary).get("knock") is Vector2:
		knock = (impact as Dictionary)["knock"]
	if knock == Vector2.ZERO and hit.get("knock") is Vector2:
		knock = hit["knock"]
	if knock == Vector2.ZERO and impact is Dictionary and (impact as Dictionary).get("position") is Vector2:
		knock = _centre_of(enemy) - ((impact as Dictionary)["position"] as Vector2)
	return knock.normalized() if knock != Vector2.ZERO else Vector2.ZERO


static func _apply(enemy: Node, profile: Dictionary, state: ReactionState, hit: Dictionary, answer: Dictionary,
		knock: Vector2, origin: Vector2, damage: float, now: float) -> void:
	var verb := str(answer.get("verb", ""))
	var stun := float(answer.get("stun_ms", 0.0))
	var body := _body_of(enemy)
	if verb == HitReaction.VERB_BREAK_FREE:
		_break_free(enemy, profile, state, hit, answer, knock, body, now)
		return
	if verb == HitReaction.VERB_ARMOR:
		if not bool(answer.get("guarded", false)):
			_push_windup(enemy, state)
		if bool(answer.get("poise_broken", false)):
			_puff(enemy, profile)
		_play_motion(enemy, profile, state, hit, answer, knock)
		return
	if HitReaction.STUN_VERBS.has(verb):
		_call(enemy, &"cancel_attack")
		_stun(enemy, now + stun)
		_call(enemy, &"play_hurt", [HURT_ACTION])
	if body != null:
		match verb:
			HitReaction.VERB_KNOCKBACK, HitReaction.VERB_BONK:
				body.velocity = knock * _launch_speed(hit, profile, 1.0)
			HitReaction.VERB_LAUNCH:
				body.velocity = knock * _launch_speed(hit, profile, 1.0)
				_remember_launch(state, body, damage)
			HitReaction.VERB_BOWL:
				var side := knock.orthogonal()
				if side.dot(_centre_of(enemy) - origin) < 0.0:
					side = -side
				body.velocity = side * _launch_speed(hit, profile, 1.0)
				_remember_launch(state, body, damage)
			HitReaction.VERB_RESIST:
				body.velocity = knock * speed_for_distance(float(answer.get("slide_px", 0.0)), _number("combat.verbs.knockback.stunMs"))
			_:
				if HitReaction.STUN_VERBS.has(verb):
					body.velocity = Vector2.ZERO
	if bool(answer.get("poise_broken", false)):
		_puff(enemy, profile)
	_play_motion(enemy, profile, state, hit, answer, knock)


## The killing blow: a tiny enemy pops (the pop streak's pitch goes to the sender's feel); a
## knockback or launch flies the corpse x `combat.rules.killLaunchScale` (it dies where it lands);
## anything else squashes in place.
static func _apply_kill(enemy: Node, profile: Dictionary, state: ReactionState, hit: Dictionary, answer: Dictionary,
		knock: Vector2, damage: float, now: float) -> void:
	answer["killed"] = true
	var motion := motion_of(enemy)
	if motion != null:
		motion.hide_stars()
	if str(profile.get("weight", "")) == HitReaction.WEIGHT_TINY:
		answer["verb"] = HitReaction.VERB_POP
		answer["feel"] = {"pitch": _pop_pitch(now)}
		if motion != null:
			motion.play(EnemyHitMotion.SQUASH, knock, {"along": EnemyHitMotion.SPLAT_ALONG,
				"across": EnemyHitMotion.SPLAT_ACROSS, "amplitude": LIGHT_AMPLITUDE, "elastic": true})
		return
	var verb := str(answer.get("verb", ""))
	var body := _body_of(enemy)
	var flies := verb == HitReaction.VERB_LAUNCH or verb == HitReaction.VERB_KNOCKBACK or verb == HitReaction.VERB_BOWL
	var speed := _launch_speed(hit, profile, _number("combat.rules.killLaunchScale")) if flies else 0.0
	if speed > 0.0 and knock != Vector2.ZERO and body != null and enemy.has_method(&"set_death_slide"):
		answer["verb"] = HitReaction.VERB_LAUNCH
		enemy.call(&"set_death_slide", knock * speed)
		_remember_launch(state, body, damage)
		state.launch_until_ms = now + _number("combat.verbs.launch.stunMs") * _stun_scale(profile)
		if motion != null:
			motion.play(EnemyHitMotion.TUMBLE, knock, _tumble_params(hit))
		return
	if motion != null:
		motion.play(EnemyHitMotion.SQUASH, knock, _squash_params(profile, hit))


## The break-free move (the hold cap): the tell (outline flash and a goo puff), then the move.
static func _break_free(enemy: Node, profile: Dictionary, state: ReactionState, hit: Dictionary, answer: Dictionary,
		knock: Vector2, body: CharacterBody2D, now: float) -> void:
	var move := str(answer.get("move", HitReaction.MOVE_PUSH))
	var armor_ms := float(answer.get("stun_ms", 0.0))
	var motion := motion_of(enemy)
	if motion != null:
		motion.outline(_number("combat.rules.breakFreeTellMs"))
	_puff_at(enemy, PUFF_GOO)
	if move == HitReaction.MOVE_COUNTER and enemy.has_method(&"begin_counter_attack"):
		_stun(enemy, now, true)
		if bool(enemy.call(&"begin_counter_attack")):
			if motion != null:
				motion.play(EnemyHitMotion.NUDGE, -knock, {"px": _number("combat.verbs.hold.nudgePx")})
			return
		# No counter now (no target, or none to swing): it pushes free instead.
		move = HitReaction.MOVE_PUSH
		state.verb = HitReaction.VERB_BREAK_FREE
		state.stun_until_ms = maxf(state.stun_until_ms, now + armor_ms)
	var away := knock if knock != Vector2.ZERO else Vector2.RIGHT
	var push_speed := _finisher_speed(hit) * _number("combat.rules.pushSpeedScale")
	var velocity := away * push_speed
	var motion_name := EnemyHitMotion.LEAN
	var params := {"ms": armor_ms}
	match move:
		HitReaction.MOVE_HOP_BACK:
			var hop_px := float(profile.get("breakFreePx", 0.0))
			velocity = away * (speed_for_distance(hop_px, armor_ms) if hop_px > 0.0 else push_speed)
			motion_name = EnemyHitMotion.BOUNCE
			params = {"hop_px": _number("combat.verbs.bounce.hopPx"), "ms": armor_ms}
		HitReaction.MOVE_SKITTER, HitReaction.MOVE_SKITTER_SPIT:
			var side := away.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
			velocity = (side + away * 0.5).normalized() * push_speed
			motion_name = EnemyHitMotion.SQUASH
			params = _squash_params(profile, hit)
	if move == HitReaction.MOVE_SKITTER_SPIT:
		# The spit is its common (ranged) attack: started now, it fires once the skitter's stun ends
		# (a stunned enemy's attack waits).
		_call(enemy, &"cancel_attack")
		_call(enemy, &"begin_counter_attack")
	else:
		_call(enemy, &"cancel_attack")
	_stun(enemy, now + armor_ms)
	if body != null:
		body.velocity = velocity
	if motion != null:
		motion.play(motion_name, away, params)


## Armor on an attack's wind-up pushes the impact `combat.verbs.armor.windupPushMs` later, at most
## `maxMs` per attack.
static func _push_windup(enemy: Node, state: ReactionState) -> void:
	if state.phase != WINDUP_PHASE or not enemy.has_method(&"delay_attack"):
		return
	var sequence := int(enemy.call(&"attack_sequence")) if enemy.has_method(&"attack_sequence") else -1
	if sequence != state.windup_sequence:
		state.windup_sequence = sequence
		state.windup_pushed_ms = 0.0
	var push := minf(_number("combat.verbs.armor.windupPushMs"), _number("combat.verbs.armor.maxMs") - state.windup_pushed_ms)
	if push <= 0.0:
		return
	enemy.call(&"delay_attack", push)
	state.windup_pushed_ms += push


## The verb's hit motion, by weight (combat-feel plan section 6 "Victim body", "By weight class").
static func _play_motion(enemy: Node, profile: Dictionary, state: ReactionState, hit: Dictionary, answer: Dictionary,
		knock: Vector2) -> void:
	var motion := motion_of(enemy)
	if motion == null:
		return
	var verb := str(answer.get("verb", ""))
	# A shorter hit keeps the longer stun's motion (the fall, the daze sway, the tumble, the stagger):
	# a jab on a downed enemy does not pop it upright. The flash and the sender's number still show.
	var running := motion.current()
	if verb != state.verb and state.in_stun(Services.now_ms()) and not HitReaction.MOVING_VERBS.has(verb) \
			and running in [EnemyHitMotion.FALL, EnemyHitMotion.DAZE, EnemyHitMotion.TUMBLE, EnemyHitMotion.WOBBLE]:
		return
	var stun := float(answer.get("stun_ms", 0.0))
	var weight := str(profile.get("weight", ""))
	match verb:
		HitReaction.VERB_HOLD:
			if HEAVY_WEIGHTS.has(weight):
				_play_heavy(motion, weight, knock)
			elif str(hit.get("shape", "")) == SHAPE_HAMMER:
				motion.play(EnemyHitMotion.FLATTEN, knock, _flatten_params(hit, stun))
			else:
				motion.play(EnemyHitMotion.SQUASH, knock, _squash_params(profile, hit))
		HitReaction.VERB_BOUNCE:
			motion.play(EnemyHitMotion.BOUNCE, knock, {"hop_px": _number("combat.verbs.bounce.hopPx"),
				"nudge_px": _number("combat.verbs.hold.nudgePx")})
		HitReaction.VERB_KNOCKBACK, HitReaction.VERB_BONK:
			motion.play(EnemyHitMotion.LEAN, knock, {"ms": stun})
			if verb == HitReaction.VERB_BONK and float(profile.get("rollDazeMs", 0.0)) > 0.0:
				motion.show_stars(state.stun_until_ms)
		HitReaction.VERB_LAUNCH, HitReaction.VERB_BOWL:
			var params := _tumble_params(hit)
			params["ms"] = stun
			motion.play(EnemyHitMotion.TUMBLE, knock, params)
		HitReaction.VERB_STAGGER:
			motion.play(EnemyHitMotion.WOBBLE, knock, {"rad": EnemyHitMotion.WOBBLE_RAD, "jiggle": STAGGER_JIGGLE})
		HitReaction.VERB_KNOCKDOWN:
			motion.play(EnemyHitMotion.FALL, knock, {"ms": stun})
		HitReaction.VERB_DAZE:
			motion.play(EnemyHitMotion.DAZE, knock, {"ms": stun})
			motion.show_stars(state.stun_until_ms)
		HitReaction.VERB_ARMOR, HitReaction.VERB_BREAK:
			if HEAVY_WEIGHTS.has(weight):
				_play_heavy(motion, weight, knock)
			else:
				motion.play(EnemyHitMotion.NUDGE, knock, {"px": _number("combat.verbs.hold.nudgePx") * 0.5,
					"ms": _number("combat.verbs.hold.nudgeMs")})
		HitReaction.VERB_PULLED:
			motion.play(EnemyHitMotion.NUDGE, -knock, {"px": _number("combat.verbs.hold.nudgePx"),
				"ms": _number("combat.verbs.hold.nudgeMs")})
		HitReaction.VERB_RESIST:
			if float(answer.get("slide_px", 0.0)) > 0.0:
				motion.play(EnemyHitMotion.JITTER, knock, {"px": HEAVY_SHAKE_PX})
		HitReaction.VERB_CLINK:
			motion.play(EnemyHitMotion.JITTER, knock, {"px": CLINK_SHAKE_PX, "ms": CLINK_SHAKE_MS})


## Heavy enemies shake 2 px; bosses jiggle their belly (the dummy's damped wobble).
static func _play_heavy(motion: EnemyHitMotion, weight: String, knock: Vector2) -> void:
	if weight == WEIGHT_BOSS:
		motion.play(EnemyHitMotion.WOBBLE, knock, {"rad": BOSS_WOBBLE_RAD, "jiggle": BOSS_JIGGLE})
	else:
		motion.play(EnemyHitMotion.JITTER, knock, {"px": HEAVY_SHAKE_PX})


## The hold's squash: light (and tiny) enemies 1.5x with an elastic return (x the profile's
## `wobbleScale`: the slime-spider's big wobble), medium ones 0.9 / 1.1; the nudge
## (`combat.verbs.hold`) along the hit; the Axe twists along its sweep.
static func _squash_params(profile: Dictionary, hit: Dictionary) -> Dictionary:
	var params := {
		"nudge_px": _number("combat.verbs.hold.nudgePx"),
		"nudge_ms": _number("combat.verbs.hold.nudgeMs"),
	}
	var wobble := float(profile.get("wobbleScale", 1.0)) if (profile.get("wobbleScale") is float or profile.get("wobbleScale") is int) else 1.0
	if LIGHT_WEIGHTS.has(str(profile.get("weight", ""))):
		params["amplitude"] = LIGHT_AMPLITUDE * wobble
		params["elastic"] = true
	else:
		params["along"] = MEDIUM_ALONG
		params["across"] = MEDIUM_ACROSS
		params["amplitude"] = wobble
	if str(hit.get("shape", "")) == SHAPE_AXE:
		params["skew"] = EnemyHitMotion.AXE_SKEW_RAD * (-1.0 if int(hit.get("step", 0)) % 2 == 0 else 1.0)
	return params


## The Thud's flatten (the step's `flattenX` / `flattenY`), held while the hold lasts.
static func _flatten_params(hit: Dictionary, stun: float) -> Dictionary:
	var step := ShapeDefs.step(ShapeDefs.id_for(str(hit.get("shape", ""))), maxi(0, int(hit.get("step", 1)) - 1))
	return {
		"x": float(step.get("flattenX", EnemyHitMotion.FLATTEN_X)),
		"y": float(step.get("flattenY", EnemyHitMotion.FLATTEN_Y)),
		"ms": maxf(0.0, stun - EnemyHitMotion.RETURN_MS),
	}


## The launch tumble: `combat.verbs.launch.spinDeg`, and the hit's hop (else `hopPx`).
static func _tumble_params(hit: Dictionary) -> Dictionary:
	var hop := float(hit.get("hop_px", 0.0)) if (hit.get("hop_px") is float or hit.get("hop_px") is int) else 0.0
	return {
		"deg": _number("combat.verbs.launch.spinDeg"),
		"hop_px": hop if hop > 0.0 else _number("combat.verbs.launch.hopPx"),
		"ms": _number("combat.verbs.launch.stunMs"),
	}


# --- launches: splats and bowling ---------------------------------------------------------------

static func _remember_launch(state: ReactionState, body: CharacterBody2D, damage: float) -> void:
	state.launch_damage = damage
	state.launch_layer = body.collision_layer if body != null else 0
	state.bowled.clear()


## A launched body hit a wall (the mover's collider, not an enemy or the slime) faster than
## `wallSplat.minSpeed` into it: squash, the share of the launch's damage, the freeze and trauma,
## bounce back, daze; once per chain.
static func _try_splat(enemy: Node, body: CharacterBody2D, state: ReactionState, info: Dictionary, now: float) -> void:
	var splat := _dictionary("combat.rules.wallSplat")
	if state.splats_this_chain >= int(splat.get("perChain", 0)):
		return
	var collider: Variant = info.get("collider")
	if not collider is Object or not is_instance_valid(collider) or _is_player_body(collider as Object) \
			or _enemy_of(collider as Object) != null:
		return
	var normal: Vector2 = info.get("normal", Vector2.ZERO)
	var before: Vector2 = info.get("velocity", Vector2.ZERO)
	if normal == Vector2.ZERO or -before.dot(normal) < float(splat.get("minSpeed", INF)):
		return
	state.splats_this_chain += 1
	state.launch_until_ms = now
	var profile := ReactionProfile.for_enemy(enemy)
	var daze_ms := float(splat.get("dazeMs", 0.0)) * _stun_scale(profile)
	state.verb = HitReaction.VERB_DAZE
	state.stun_until_ms = maxf(state.stun_until_ms, now + daze_ms)
	state.damage_taken = 1.0
	state.hold_count = 0
	# The daze is the splat's opening: no wake guard over it.
	state.wake_until_ms = now
	_call(enemy, &"cancel_attack")
	_stun(enemy, now + daze_ms)
	body.velocity = normal * speed_for_distance(float(splat.get("bouncePx", 0.0)), daze_ms)
	var motion := motion_of(enemy)
	if motion != null:
		motion.play(EnemyHitMotion.SPLAT, normal, {"along": float(splat.get("squashX", EnemyHitMotion.SPLAT_ALONG)),
			"across": float(splat.get("squashY", EnemyHitMotion.SPLAT_ACROSS)), "ms": float(splat.get("squashMs", EnemyHitMotion.SPLAT_MS))})
		motion.show_stars(state.stun_until_ms)
	_puff_at(enemy, PUFF_DUST)
	var dealt := _hurt(enemy, roundi(state.launch_damage * float(splat.get("damageShare", 0.0))))
	_play_feel({"hit_stop_ms": float(splat.get("hitStopMs", 0.0)), "trauma": float(splat.get("trauma", 0.0)),
		"number": dealt, "number_big": false}, _centre_of(enemy), normal)


## A launched body (alive or a sliding corpse) runs into other enemies' bodies: each, once per launch,
## takes `bowling.speedShare` of its speed as its own launch (heavy enemies and bosses only shake)
## and both take `bowling.damage`; the launcher keeps the rest of its speed.
static func _bowl(enemy: Node, body: CharacterBody2D, state: ReactionState, now: float) -> void:
	if state.launch_layer == 0:
		return
	var shape := _body_shape(body)
	if shape == null or shape.shape == null:
		return
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	query.collision_mask = state.launch_layer
	query.collide_with_areas = false
	var exclude: Array[RID] = [body.get_rid()]
	query.exclude = exclude
	var hits := body.get_world_2d().direct_space_state.intersect_shape(query, BOWL_QUERY_MAX)
	for entry: Dictionary in hits:
		var other_body := entry.get("collider") as CharacterBody2D
		var other := _enemy_of(other_body)
		if other == null or other == enemy or _defeated(other):
			continue
		var id := other.get_instance_id()
		if state.bowled.has(id):
			continue
		# Only a body moving into a standing enemy bowls it; a body already in flight is never
		# re-bowled (so a crowd cannot bowl itself in a loop), and a drifting body bowls nothing.
		if now < state_of(other).launch_until_ms:
			continue
		var toward := (_centre_of(other) - _centre_of(enemy)).normalized()
		if body.velocity.dot(toward) < float(_dictionary("combat.rules.bowling").get("minSpeed", 0.0)):
			continue
		state.bowled[id] = true
		_bowl_into(enemy, body, other, other_body, now)


static func _bowl_into(enemy: Node, body: CharacterBody2D, other: Node, other_body: CharacterBody2D, now: float) -> void:
	var bowling := _dictionary("combat.rules.bowling")
	var share := float(bowling.get("speedShare", 0.0))
	var direction := _centre_of(other) - _centre_of(enemy)
	direction = direction.normalized() if direction != Vector2.ZERO else body.velocity.normalized()
	var passed := body.velocity.length() * share
	body.velocity *= maxf(0.0, 1.0 - share)
	var profile := ReactionProfile.for_enemy(other)
	var other_state := state_of(other)
	var motion := motion_of(other)
	var speed := minf(_number("combat.verbs.launch.maxSpeed"), passed * float(profile.get("knockbackScale", 1.0)))
	if HEAVY_WEIGHTS.has(str(profile.get("weight", ""))) or speed <= 0.0:
		if motion != null:
			_play_heavy(motion, str(profile.get("weight", "")), direction)
	else:
		var stun := _number("combat.verbs.launch.stunMs") * _stun_scale(profile)
		other_state.verb = HitReaction.VERB_LAUNCH
		other_state.stun_until_ms = maxf(other_state.stun_until_ms, now + stun)
		other_state.launched_at_ms = now
		other_state.launch_until_ms = now + stun
		other_state.hold_count = 0
		other_state.wake_until_ms = maxf(other_state.wake_until_ms, now + stun + _number("combat.rules.wakeGuardMs"))
		_remember_launch(other_state, other_body, 0.0)
		other_state.bowled[enemy.get_instance_id()] = true
		_call(other, &"cancel_attack")
		_stun(other, now + stun)
		_call(other, &"play_hurt", [HURT_ACTION])
		other_body.velocity = direction * speed
		if motion != null:
			var params := {"deg": _number("combat.verbs.launch.spinDeg"), "hop_px": _number("combat.verbs.launch.hopPx"), "ms": stun}
			motion.play(EnemyHitMotion.TUMBLE, direction, params)
	var damage := roundi(float(bowling.get("damage", 0.0)))
	_flash(other, {})
	var dealt_other := _hurt(other, damage)
	var dealt_self := _hurt(enemy, damage)
	_play_feel({"hit_stop_ms": 0.0, "number": dealt_other, "number_big": false}, _centre_of(other), direction)
	if dealt_self > 0:
		_play_feel({"hit_stop_ms": 0.0, "number": dealt_self, "number_big": false}, _centre_of(enemy), -direction)


# --- helpers ------------------------------------------------------------------------------------

## `launch_speed` x `knockbackScale` x `scale`, capped at `combat.verbs.launch.maxSpeed`.
static func _launch_speed(hit: Dictionary, profile: Dictionary, scale: float) -> float:
	var speed := float(hit.get("launch_speed", 0.0)) if (hit.get("launch_speed") is float or hit.get("launch_speed") is int) else 0.0
	var resist := float(profile.get("knockbackScale", 1.0)) if (profile.get("knockbackScale") is float or profile.get("knockbackScale") is int) else 1.0
	return clampf(speed * resist * scale, 0.0, _number("combat.verbs.launch.maxSpeed"))


## The hit's shape's finisher launch speed (the break-free push is a share of it); the hit's own, or
## the launch cap, without a shape.
static func _finisher_speed(hit: Dictionary) -> float:
	var shape := ShapeDefs.id_for(str(hit.get("shape", "")))
	if ShapeDefs.is_shape(shape):
		var last := ShapeDefs.step(shape, ShapeDefs.step_count(shape) - 1)
		var speed := float(last.get("launchSpeed", 0.0))
		if speed > 0.0:
			return speed
	var own := float(hit.get("launch_speed", 0.0)) if (hit.get("launch_speed") is float or hit.get("launch_speed") is int) else 0.0
	return own if own > 0.0 else _number("combat.verbs.launch.maxSpeed")


## Sets the stun end to `until` (the longer of the old and new one, unless `replace`).
static func _stun(enemy: Node, until: float, replace: bool = false) -> void:
	if not enemy.has_method(&"set_hit_stun_until"):
		return
	var old := float(enemy.call(&"get_hit_stun_until")) if enemy.has_method(&"get_hit_stun_until") else 0.0
	enemy.call(&"set_hit_stun_until", until if replace else maxf(old, until))


## The hit flash: GameFeel's white-then-tint curve when it has one (`flash_hit(visual, big)`; big
## for the classes in `combat.damageNumbers.bigClasses`), else the enemy's own flash (SimClock), else
## the motion's white fill (a dummy).
static func _flash(enemy: Node, hit: Dictionary) -> void:
	var feel := Services.feel()
	var visual: Variant = enemy.call(&"get_visual") if enemy.has_method(&"get_visual") else null
	if feel != null and feel.has_method(&"flash_hit") and visual is CanvasItem and is_instance_valid(visual):
		feel.call(&"flash_hit", visual, _big_hit(hit))
		return
	if enemy.has_method(&"flash_hit"):
		enemy.call(&"flash_hit")
		return
	var motion := motion_of(enemy)
	if motion != null:
		motion.flash(DUMMY_FLASH_MS)


## True for a hit whose class is in `combat.damageNumbers.bigClasses` (finishers, charges, the
## Hammer, the Slam).
static func _big_hit(hit: Dictionary) -> bool:
	var constants := Services.constants()
	var big: Variant = constants.value("combat.damageNumbers.bigClasses", []) if constants != null else []
	return big is Array and (big as Array).has(str(hit.get("class", "")))


## Reaction damage (a splat, a bowling knock) through the enemy's own wrapper; what it dealt.
static func _hurt(enemy: Node, amount: int) -> int:
	if amount <= 0 or not enemy.has_method(&"take_reaction_damage"):
		return 0
	return int(enemy.call(&"take_reaction_damage", float(amount)))


static func _play_feel(spec: Dictionary, at: Vector2, direction: Vector2) -> void:
	var feel := Services.feel()
	if feel != null and feel.has_method(&"play_hit"):
		feel.play_hit(spec, at, direction)


## The death and break puff by material: goo splashes, everything else is dust.
static func _puff(enemy: Node, profile: Dictionary) -> void:
	_puff_at(enemy, PUFF_GOO if str(profile.get("material", "")) == MATERIAL_GOO else PUFF_DUST)


static func _puff_at(enemy: Node, preset: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.particles(preset, _centre_of(enemy))


## The pop streak: each pop within `windowMs` of the last plays `semitones` higher, `maxSteps` at
## most; the pitch factor of this pop.
static func _pop_pitch(now: float) -> float:
	var streak := _dictionary("combat.rules.popStreak")
	if now - _pop_at_ms <= float(streak.get("windowMs", 0.0)):
		_pop_steps = mini(int(streak.get("maxSteps", 0)), _pop_steps + 1)
	else:
		_pop_steps = 0
	_pop_at_ms = now
	return pow(2.0, float(streak.get("semitones", 0.0)) * float(_pop_steps) / 12.0)


static func _stun_scale(profile: Dictionary) -> float:
	var scale: Variant = profile.get("hitstunScale", 1.0)
	return float(scale) if (scale is float or scale is int) and float(scale) > 0.0 else 1.0


## Where the hit came from: the request's impact point, else the enemy's centre.
static func _origin_of(enemy: Node, request: Dictionary) -> Vector2:
	var impact: Variant = request.get("impact", {})
	if impact is Dictionary and (impact as Dictionary).get("position") is Vector2:
		return (impact as Dictionary)["position"]
	return _centre_of(enemy)


static func _call(enemy: Node, method: StringName, args: Array = []) -> void:
	if enemy.has_method(method):
		enemy.callv(method, args)


static func _body_of(enemy: Node) -> CharacterBody2D:
	if enemy == null or not enemy.has_method(&"get_body"):
		return null
	var body: Variant = enemy.call(&"get_body")
	return body as CharacterBody2D if body is CharacterBody2D and is_instance_valid(body) else null


static func _centre_of(enemy: Node) -> Vector2:
	if enemy != null and enemy.has_method(&"get_centre"):
		return enemy.call(&"get_centre")
	var root := enemy.get_parent() as Node2D if enemy != null else null
	return root.global_position if root != null else Vector2.ZERO


static func _defeated(enemy: Node) -> bool:
	return enemy.has_method(&"is_defeated") and bool(enemy.call(&"is_defeated"))


static func _is_dummy(enemy: Node) -> bool:
	return enemy.get(&"reaction_preset") is String


## The enemy script node of a body (the child in the "enemy" group that has `get_body`, or a
## testbed training dummy's script whose `get_body()` is that body), or null.
static func _enemy_of(collider: Object) -> Node:
	var node := collider as Node
	if node == null:
		return null
	for child: Node in node.get_children():
		if child.is_in_group(ENEMY_GROUP) and child.has_method(&"get_body"):
			return child
		if _is_dummy(child) and child.has_method(&"get_body") and child.call(&"get_body") == node:
			return child
	return null


static func _is_player_body(collider: Object) -> bool:
	var world := Services.world()
	return world != null and collider == world.player_body


## The body's first collision shape (the one it moves with).
static func _body_shape(body: CharacterBody2D) -> CollisionShape2D:
	for child: Node in body.get_children():
		if child is CollisionShape2D and not (child as CollisionShape2D).disabled:
			return child as CollisionShape2D
	return null


static func _dictionary(path: String) -> Dictionary:
	var constants := Services.constants()
	var found: Variant = constants.value(path, {}) if constants != null else {}
	return found if found is Dictionary else {}


static func _number(path: String) -> float:
	var constants := Services.constants()
	return constants.number(path) if constants != null else 0.0
