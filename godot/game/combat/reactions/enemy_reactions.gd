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
##   - a sleep (a sleep throw; owner, 2026-11-01) lasts until a hit that deals damage wakes it
##     (`wake_if_hurt` here, enemy.gd `_react_to_damage` for old hits, `_bowl_into`): the enemy's
##     step renews its stun every step (`keep_asleep`), it sways without stars, and it lands through
##     immunities and a patterned enemy's shield on the ground (`sleeps_through`), never on a boss;
##   - hold, bounce, stagger, knockdown, daze and sleep stop the body where it is, unless the hit dealt
##     damage and carries a `knock_px` (a thrown thing's, `gulp.throwHit.knockbackPx`; owner,
##     2026-11-01: a throw that hurts knocks back): then the body slides `knock_px` x
##     `knockbackScale` along the knock while the stun holds it, `knock_speed_scale` times as fast as
##     a stun slide (`_knock_slide`, `slide_decay_of`); knockback and
##     launch set its velocity along the knock at `launch_speed` x `knockbackScale`, capped at
##     `combat.verbs.launch.maxSpeed` (the enemy's own stun step then slides it with
##     `combat.verbs.slideDecay`); a kill launches x `combat.rules.killLaunchScale` and the corpse
##     slides to where it dies (a kill that would not fly slides its `knock_px` instead); a tiny
##     enemy's kill pops (the pop streak raises the pitch);
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
## - A throw's new feel (owner, 2026-11-16: "a strong hit and the monster got pushed back with nice
##   effects and sounds"; the sender, thrown_object.gd `rework_hit`, sets these on the hit only while
##   `gulp.throwFeel.enabled` is on, and a hit without them reacts as before):
##   - `big`, on a hit that dealt damage (no damage, no hard hit): the hard flash (`_flash`, `combat.verbs.knock.flash`: white, then the tint and the white
##     in turns while it flies, then the fade) and the victim's shake through the freeze, side to side
##     and shrinking (`_shake_in_freeze`: `shakePx`, `shakeMs`);
##   - `knock_motion`: a stun whose knock slide moves the body (a daze, a knockdown, a stagger) plays
##     the knock first (`_play_stun`, EnemyHitMotion.KNOCK, `combat.verbs.knock`), then its own motion;
##     the daze's stars are `starScale` times as big;
##   - `chains`: that knock slide is a launch while it is fast (`_open_chain`), so the body splats on
##     walls (a knockdown stays down against the wall, the daze sway follows the squash) and bowls;
##     a bowling contact deals the hit's `bowl_damage` to both, plays `bowling.chainFeel`, and the
##     bowled body carries the chain on, `bowling.chainPasses` deep; a body the splat or the contact
##     kills is sent off (`_chain_hurt`);
##   - `kill_sendoff`: a kill flies the corpse back along the throw whatever the verb and the weight
##     and pops it (`_send_off`, `pop_corpse` from enemy.gd's `begin_sendoff`; `combat.rules.killSendoff`):
##     never a boss or a dummy; an enemy whose `knockbackScale` is 0 pops where it stands.
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
const HitFlash := preload("res://game/feel/hit_flash.gd")
const ArcadeMover := preload("res://game/shared/arcade_mover.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const EnergyShard := preload("res://game/combat/reactions/energy_shard.gd")
## What the ground does to a body a blow moves: ledges, holes, deep water, danger zones.
const EnemyHazards := preload("res://game/combat/reactions/enemy_hazards.gd")

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
## A sleeper's daze sway lasts until `wake` stops it.
const SLEEP_SWAY_MS := 1.0e9
## Long enough for any stun slide to stop (ms): a slide's whole reach is what it covers in it.
const SLIDE_WHOLE_MS := 10000.0
## The stuns that leave an enemy helpless on the ground (`is_helpless`: the enemy-ammo prototype),
## and the hit tag that marks a throw's.
const HELPLESS_VERBS: Array[String] = [HitReaction.VERB_DAZE, HitReaction.VERB_KNOCKDOWN, HitReaction.VERB_STAGGER,
	HitReaction.VERB_SLEEP]
const THROWN_TAG := "thrown"
## A blown body counts as blown this long past the moment it slows under the hazards' `minSpeed`
## (the step it is stopped on comes a step after the speed that stopped it).
const BLOWN_GRACE_MS := 50.0
## A cue payload's pitch (GameFeel.CUE_PITCH_KEY).
const CUE_PITCH_KEY := "pitch"
## The juice switch the hit flash obeys (HitJuice.LAYER_FLASH).
const FLASH_LAYER := &"flash"

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
	wake_if_hurt(enemy, commit)
	var answer := HitReaction.decide(profile, hit, state, now)
	_annotate(answer, profile)
	var knock := _knock_of(enemy, hit, request)
	# No damage, no hard hit (owner: a throw that does not hurt does not push): a sleep throw or a shut
	# part's daze flashes as any hit does, without the hard flash or the shake.
	_flash(enemy, hit, is_dead and _sends_off(enemy, hit, profile), damage > 0.0)
	if is_dead:
		_apply_kill(enemy, profile, state, hit, answer, knock, damage, now)
	else:
		_apply(enemy, profile, state, hit, answer, knock, _origin_of(enemy, request), damage, now)
		_note_helpless(enemy, state, hit, answer, now)
	if damage > 0.0:
		_shake_in_freeze(enemy, hit)
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
	var launched := now < state.launch_until_ms
	# A body a blow moves meets the ground's hazards (enemy_hazards.gd), launch or plain knock slide.
	var blown := now < state.blown_until_ms and EnemyHazards.is_on()
	if not launched and not blown:
		return
	var body := _body_of(enemy)
	if body == null or not body.is_inside_tree():
		return
	if launched:
		_bowl(enemy, body, state, now)
	var info: Variant = body.get_meta(ArcadeMover.COLLISION_META) if body.has_meta(ArcadeMover.COLLISION_META) else null
	var stopped := info is Dictionary and int((info as Dictionary).get("frame", -1)) == Engine.get_physics_frames() \
		and _is_obstacle((info as Dictionary).get("collider"))
	if blown:
		# A rim that drops takes it over, a hole or deep water takes it for good; else, on its own
		# level, a void or a danger zone under it.
		if stopped and EnemyHazards.at_obstacle(enemy, body, state, info, now):
			return
		if EnemyHazards.over(enemy, body, state, now):
			return
	if _defeated(enemy):
		return
	if launched and stopped:
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
	# A send-off's puff is its pop, where the corpse ends (`pop_corpse`).
	if not (enemy.has_meta(STATE_META) and state_of(enemy).sendoff):
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


## True while `enemy` sleeps (a sleep throw's `HitReaction.VERB_SLEEP`, until a damaging hit).
static func is_asleep(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy) or not enemy.has_meta(STATE_META):
		return false
	var state := state_of(enemy)
	return state.verb == HitReaction.VERB_SLEEP and state.in_stun(Services.now_ms())


## Every stunned step of a sleeping enemy (enemy.gd, patterned_enemy.gd, the training dummy): its
## stun is renewed (`combat.verbs.sleep.stunMs` from now), so it sleeps until `wake`.
static func keep_asleep(enemy: Node) -> void:
	if not is_asleep(enemy):
		return
	var until := Services.now_ms() + _number("combat.verbs.sleep.stunMs")
	var state := state_of(enemy)
	state.stun_until_ms = maxf(state.stun_until_ms, until)
	_stun(enemy, until)


## Wakes `enemy` from a sleep (owner, 2026-11-01: it sleeps until new damage wakes it): the stun ends
## now and the sway stops (the z's go with the sleep: throw_status_look.gd). Nothing when it is
## awake.
static func wake(enemy: Node) -> void:
	if not is_asleep(enemy):
		return
	var state := state_of(enemy)
	var now := Services.now_ms()
	state.verb = ""
	state.stun_until_ms = now
	_stun(enemy, now, true)
	var motion := enemy.get_node_or_null(NodePath(MOTION_NODE)) as EnemyHitMotion
	if motion != null and motion.current() == EnemyHitMotion.DAZE:
		motion.stop()


## `wake` when the committed hit in `commit` dealt damage (rework hits here in `react`, old ones in
## enemy.gd `_react_to_damage`; bowling in `_bowl_into`).
static func wake_if_hurt(enemy: Node, commit: Dictionary) -> void:
	var result: Variant = commit.get("result")
	if result is Dictionary and float((result as Dictionary).get("actual_damage", 0)) > 0.0:
		wake(enemy)


## True when the rework hit in `request` puts `enemy` to sleep through its shield
## (`HitReaction.sleeps_through`): patterned_enemy.gd lets it past `_shields`.
static func sleeps_through(enemy: Node, request: Dictionary) -> bool:
	var hit := HitReaction.hit_of(request)
	if enemy == null or hit.is_empty():
		return false
	var profile := ReactionProfile.for_enemy(enemy)
	return HitReaction.sleeps_through(profile, hit, _prepare(enemy, request, profile).phase)


## True while `enemy` lies helpless from a throw and can be gulped as ammo (the enemy-ammo prototype,
## game/throw/gulpable_enemy.gd): the stun in force is a throw's daze, knockdown, stagger or sleep
## (a freeze is a daze; a chain's wall splat and bowl count), its knock's flight is over, no launch
## flies, no wake guard runs, and its phase is on the ground (not one marked `noSleep`: in the air,
## burrowed, hidden). Never a corpse.
static func is_helpless(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy) or not enemy.has_meta(STATE_META) or _defeated(enemy):
		return false
	var state := state_of(enemy)
	var now := Services.now_ms()
	if not state.throw_helpless or not state.in_stun(now) or not HELPLESS_VERBS.has(state.verb):
		return false
	if now < state.helpless_from_ms or now < state.wake_until_ms or now < state.launch_until_ms:
		return false
	var phase := str(enemy.call(&"reaction_phase")) if enemy.has_method(&"reaction_phase") else ""
	return not bool(HitReaction.phase_entry(ReactionProfile.for_enemy(enemy), phase).get("noSleep", false))


## The enemy-ammo prototype: `enemy` is gulped (gulpable_enemy.gd `take`). Its stun, its sleep, its
## chain and its hit motion end here (the stars go); it comes back with `put_down` or a landing hit.
static func prepare_carry(enemy: Node) -> void:
	if enemy == null:
		return
	var state := state_of(enemy)
	var now := Services.now_ms()
	state.verb = ""
	state.stun_until_ms = now
	state.launch_until_ms = now
	state.slide_decay_until_ms = 0.0
	state.damage_taken = 1.0
	state.hold_count = 0
	state.throw_helpless = false
	_stun(enemy, now, true)
	var motion := enemy.get_node_or_null(NodePath(MOTION_NODE)) as EnemyHitMotion
	if motion != null:
		motion.stop()


## The enemy-ammo prototype: `enemy` is back on the ground unhurt (it burst out of the mouth, it was
## dropped, it landed immune): dazed `daze_ms` so it does not strike at once, and not helpless (it
## cannot be gulped again from this daze).
static func put_down(enemy: Node, daze_ms: float) -> void:
	if enemy == null or daze_ms <= 0.0:
		return
	var state := state_of(enemy)
	var now := Services.now_ms()
	state.verb = HitReaction.VERB_DAZE
	state.stun_until_ms = maxf(state.stun_until_ms, now + daze_ms)
	state.throw_helpless = false
	_call(enemy, &"cancel_attack")
	_stun(enemy, now + daze_ms)
	var motion := motion_of(enemy)
	if motion != null:
		motion.play(EnemyHitMotion.DAZE, Vector2.ZERO, {"ms": daze_ms})
		motion.show_stars(state.stun_until_ms)


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


## The per-step slide decay of `enemy`'s stunned body (or corpse) now: a throw's knock slide's own
## while it runs (`_knock_slide`), else `slide_decay`. enemy.gd, patterned_enemy.gd and the
## training dummy slow their slides by it.
static func slide_decay_of(enemy: Node) -> float:
	if enemy != null and enemy.has_meta(STATE_META):
		var state := state_of(enemy)
		if Services.now_ms() < state.slide_decay_until_ms:
			return state.slide_decay
	return slide_decay()


## The start speed (px/s) that makes a stunned body's slide (`decay` per 60 Hz step; `slide_decay`
## when < 0) cover `px` in `ms`.
static func speed_for_distance(px: float, ms: float, decay: float = -1.0) -> float:
	if px <= 0.0:
		return 0.0
	var ticks := float(maxi(1, Engine.physics_ticks_per_second))
	var step_decay := pow(clampf(decay if decay >= 0.0 else slide_decay(), 0.0, 1.0), 60.0 / ticks)
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
	if not is_instance_valid(area) or not area is Area2D:
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
	var knocked := false
	if body != null:
		state.slide_decay_until_ms = 0.0
		match verb:
			HitReaction.VERB_KNOCKBACK, HitReaction.VERB_BONK:
				body.velocity = knock * _launch_speed(hit, profile, 1.0)
			HitReaction.VERB_LAUNCH:
				body.velocity = knock * _launch_speed(hit, profile, 1.0)
				_remember_launch(state, body, damage)
				_carry_chain(state, hit)
			HitReaction.VERB_BOWL:
				var side := knock.orthogonal()
				if side.dot(_centre_of(enemy) - origin) < 0.0:
					side = -side
				body.velocity = side * _launch_speed(hit, profile, 1.0)
				_remember_launch(state, body, damage)
				_carry_chain(state, hit)
			HitReaction.VERB_RESIST:
				body.velocity = knock * speed_for_distance(float(answer.get("slide_px", 0.0)), _number("combat.verbs.knockback.stunMs"))
			_:
				if HitReaction.STUN_VERBS.has(verb):
					var slide := _knock_slide(state, hit, profile, damage, stun, now)
					body.velocity = knock * slide
					knocked = slide > 0.0 and knock != Vector2.ZERO
					if knocked:
						_open_chain(state, hit, body, damage, slide, now)
		_mark_blown(state, body.velocity.length(), slide_decay_of(enemy), now)
	if bool(answer.get("poise_broken", false)):
		_puff(enemy, profile)
	_play_motion(enemy, profile, state, hit, answer, knock, knocked and _flag(hit, "knock_motion"))


## Remembers whether the stun this hit put in force leaves the enemy helpless from a throw
## (`is_helpless`): a daze, a knockdown, a stagger or a sleep by a hit tagged `thrown`, from the end
## of its knock's flight when it slides. Armor, a clink and a shorter stun under a longer one change
## nothing; any other stun that takes over ends it.
static func _note_helpless(enemy: Node, state: ReactionState, hit: Dictionary, answer: Dictionary, now: float) -> void:
	var verb := str(answer.get("verb", ""))
	if not HitReaction.STUN_VERBS.has(verb) or state.verb != verb:
		return
	var tags: Variant = hit.get("tags", [])
	state.throw_helpless = HELPLESS_VERBS.has(verb) and tags is Array and (tags as Array).has(THROWN_TAG)
	var body := _body_of(enemy)
	var slides := body != null and body.velocity != Vector2.ZERO
	state.helpless_from_ms = now + (_knock_number("flightMs", EnemyHitMotion.KNOCK_MS) + EnemyHitMotion.LANDING_MS if slides else 0.0)


## The killing blow: a tiny enemy pops (the pop streak's pitch goes to the sender's feel); a
## knockback or launch flies the corpse x `combat.rules.killLaunchScale` (it dies where it lands);
## anything else squashes, in place or, with a `knock_px` (a throw), sliding that far. A hit that
## carries `kill_sendoff` (a throw with the new feel) sends the corpse off instead, whatever the verb
## and the weight (`_send_off`; the answer says `sendoff`).
static func _apply_kill(enemy: Node, profile: Dictionary, state: ReactionState, hit: Dictionary, answer: Dictionary,
		knock: Vector2, damage: float, now: float) -> void:
	answer["killed"] = true
	var motion := motion_of(enemy)
	if motion != null:
		motion.hide_stars()
	state.sendoff = false
	var tiny := str(profile.get("weight", "")) == HitReaction.WEIGHT_TINY
	var sends := _sends_off(enemy, hit, profile)
	# The pop streak: one step per kill that pops (a tiny enemy's, a send-off's).
	var pitch := _pop_pitch(now) if tiny or sends else 1.0
	if tiny:
		answer["verb"] = HitReaction.VERB_POP
		answer["feel"] = {"pitch": pitch}
	if sends:
		state.sendoff_pitch = pitch
		if _send_off(enemy, profile, state, hit, knock, damage, now) and not tiny:
			answer["verb"] = HitReaction.VERB_LAUNCH
		answer["sendoff"] = true
		return
	if tiny:
		if motion != null:
			motion.play(EnemyHitMotion.SQUASH, knock, {"along": EnemyHitMotion.SPLAT_ALONG,
				"across": EnemyHitMotion.SPLAT_ACROSS, "amplitude": LIGHT_AMPLITUDE, "elastic": true})
		return
	var verb := str(answer.get("verb", ""))
	var body := _body_of(enemy)
	state.slide_decay_until_ms = 0.0
	var flies := verb == HitReaction.VERB_LAUNCH or verb == HitReaction.VERB_KNOCKBACK or verb == HitReaction.VERB_BOWL
	var speed := _launch_speed(hit, profile, _number("combat.rules.killLaunchScale")) if flies else 0.0
	if speed > 0.0 and knock != Vector2.ZERO and body != null and enemy.has_method(&"set_death_slide"):
		answer["verb"] = HitReaction.VERB_LAUNCH
		enemy.call(&"set_death_slide", knock * speed)
		_mark_blown(state, speed, slide_decay(), now)
		_remember_launch(state, body, damage)
		_carry_chain(state, hit)
		state.launch_until_ms = now + _number("combat.verbs.launch.stunMs") * _stun_scale(profile)
		if motion != null:
			motion.play(EnemyHitMotion.TUMBLE, knock, _tumble_params(hit))
		return
	var slide := _knock_slide(state, hit, profile, damage, _number("combat.verbs.knockback.stunMs"), now)
	if slide > 0.0 and knock != Vector2.ZERO and body != null and enemy.has_method(&"set_death_slide"):
		enemy.call(&"set_death_slide", knock * slide)
		_mark_blown(state, slide, slide_decay_of(enemy), now)
	if motion != null:
		motion.play(EnemyHitMotion.SQUASH, knock, _squash_params(profile, hit))


## Whether a kill by `hit` is a send-off (the hit's `kill_sendoff`, a throw's; `_can_send_off`).
static func _sends_off(enemy: Node, hit: Dictionary, _profile: Dictionary) -> bool:
	return _flag(hit, "kill_sendoff") and _can_send_off(enemy)


## A send-off (`combat.rules.killSendoff`): whatever the verb, the corpse flies back along the throw
## at the kill launch's speed (`launch_speed` x `combat.rules.killLaunchScale` x its `knockbackScale`,
## at least `minScale`; an enemy that never moves, scale 0, stays where it is), tumbling and blinking
## white (`_flash`), bowling whoever is in its way, and pops (`pop_corpse`, from enemy.gd) after
## `maxMs`, or from `minMs` on once it has stopped (a wall); a corpse that stays pops after `stillMs`.
## The death puff waits for the pop (`on_defeated`). True when the corpse flies.
static func _send_off(enemy: Node, profile: Dictionary, state: ReactionState, hit: Dictionary, knock: Vector2,
		damage: float, now: float) -> bool:
	var rule := _dictionary("combat.rules.killSendoff")
	var motion := motion_of(enemy)
	var body := _body_of(enemy)
	state.sendoff = true
	state.slide_decay_until_ms = 0.0
	var resist := _hit_number(profile, "knockbackScale", 1.0)
	var speed := 0.0
	if resist > 0.0 and knock != Vector2.ZERO and body != null and enemy.has_method(&"set_death_slide"):
		speed = clampf(_hit_number(hit, "launch_speed", 0.0) * maxf(resist, float(rule.get("minScale", 0.0)))
			* _number("combat.rules.killLaunchScale"), 0.0, _number("combat.verbs.launch.maxSpeed"))
	if speed <= 0.0:
		if motion != null:
			motion.play(EnemyHitMotion.SQUASH, knock, _squash_params(profile, hit))
		var still_at := now + float(rule.get("stillMs", 0.0))
		enemy.call(&"begin_sendoff", still_at, still_at)
		return false
	var fly_ms := float(rule.get("maxMs", 0.0))
	# The corpse covers that launch's whole slide `pace` times as fast (a blow, not a drift): a faster
	# start, slowing `pace` times as fast, as a throw's knock slide does.
	var pace := maxf(float(rule.get("pace", 1.0)), 0.01)
	if not is_equal_approx(pace, 1.0):
		var reach := _slide_px(speed, slide_decay())
		state.slide_decay = pow(clampf(slide_decay(), 0.0, 1.0), pace)
		state.slide_decay_until_ms = now + fly_ms
		speed = speed_for_distance(reach, SLIDE_WHOLE_MS, state.slide_decay)
	enemy.call(&"set_death_slide", knock * speed)
	_mark_blown(state, speed, slide_decay_of(enemy), now)
	_remember_launch(state, body, damage)
	_carry_chain(state, hit)
	state.launched_at_ms = now
	state.launch_until_ms = now + fly_ms
	if motion != null:
		var params := _tumble_params(hit)
		params["ms"] = fly_ms
		params["ghost_white"] = true
		motion.play(EnemyHitMotion.TUMBLE, knock, params)
	enemy.call(&"begin_sendoff", now + float(rule.get("minMs", 0.0)), now + fly_ms)
	return true


## The send-off's pop, where the corpse is now (enemy.gd calls it as the corpse goes): the
## material's own burst (`killSendoff.puffs`), the common puff (`puff`) and the ring (`ring`), each
## `popScale` times a normal burst, and the cue (`cue`, when the sounds have one).
static func pop_corpse(enemy: Node) -> void:
	var feel := Services.feel()
	if enemy == null or feel == null:
		return
	var rule := _dictionary("combat.rules.killSendoff")
	var at := _centre_of(enemy)
	var scale := float(rule.get("popScale", 1.0))
	var puffs: Variant = rule.get("puffs", {})
	var own := str((puffs as Dictionary).get(str(ReactionProfile.for_enemy(enemy).get("material", "")), "")) if puffs is Dictionary else ""
	for preset: String in [own, str(rule.get("puff", "")), str(rule.get("ring", ""))]:
		if not preset.is_empty():
			feel.burst(StringName(preset), at, Vector2.ZERO, Color.WHITE, scale)
	var cue := str(rule.get("cue", ""))
	if not cue.is_empty() and feel.has_method(&"audio_cue"):
		var pitch := state_of(enemy).sendoff_pitch if enemy.has_meta(STATE_META) else 1.0
		feel.call(&"audio_cue", StringName(cue), {CUE_PITCH_KEY: pitch})


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
	state.slide_decay_until_ms = 0.0
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
		knock: Vector2, knocked: bool = false) -> void:
	var motion := motion_of(enemy)
	if motion == null:
		return
	var verb := str(answer.get("verb", ""))
	# A shorter hit keeps the longer stun's motion (the fall, the daze sway, the tumble, the stagger):
	# a jab on a downed enemy does not pop it upright. The flash and the sender's number still show.
	var running := motion.current()
	if verb != state.verb and state.in_stun(Services.now_ms()) and not HitReaction.MOVING_VERBS.has(verb) \
			and running in [EnemyHitMotion.FALL, EnemyHitMotion.DAZE, EnemyHitMotion.TUMBLE, EnemyHitMotion.WOBBLE,
				EnemyHitMotion.KNOCK]:
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
			_play_stun(motion, knocked, profile, knock, EnemyHitMotion.WOBBLE,
				{"rad": EnemyHitMotion.WOBBLE_RAD, "jiggle": STAGGER_JIGGLE})
		HitReaction.VERB_KNOCKDOWN:
			_play_stun(motion, knocked, profile, knock, EnemyHitMotion.FALL, {"ms": stun})
		HitReaction.VERB_DAZE:
			_play_stun(motion, knocked, profile, knock, EnemyHitMotion.DAZE, {"ms": stun})
			motion.show_stars(state.stun_until_ms, _knock_number("starScale", 1.0) if knocked else 1.0)
		HitReaction.VERB_SLEEP:
			# The sway runs until `wake` stops it; the z's are the sleep's look (no stars).
			motion.hide_stars()
			motion.play(EnemyHitMotion.DAZE, knock, {"ms": SLEEP_SWAY_MS})
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


## A stun's motion (the daze sway, the knockdown fall, the stagger wobble), or, `knocked` (a throw's
## `knock_motion` on a body its knock slide moves), the knock first (`combat.verbs.knock`: squashed
## along the throw on the hit frame, stretched as it flies back in a hop of `hopPx`, both x its
## `knockbackScale` (at least `hopFloor` of them), for `flightMs`, `afterimages`, dust every
## `dustEveryPx` and where it lands, leaning `tiltRad` with the push) and then that motion for the
## rest of its time; a knockdown turns over in the air and lands on its back.
static func _play_stun(motion: EnemyHitMotion, knocked: bool, profile: Dictionary, knock: Vector2,
		then: StringName, then_params: Dictionary) -> void:
	if not knocked:
		motion.play(then, knock, then_params)
		return
	var flight := _knock_number("flightMs", EnemyHitMotion.KNOCK_MS)
	var falls := then == EnemyHitMotion.FALL
	var follow := then_params.duplicate()
	if follow.has("ms"):
		follow["ms"] = maxf(0.0, float(follow["ms"]) - flight - EnemyHitMotion.LANDING_MS)
	if falls:
		follow["down"] = true
	# A body that gives way less hops lower and bends less (a heavy one is no rubber ball).
	var resist := clampf(_hit_number(profile, "knockbackScale", 1.0), _knock_number("hopFloor", 0.0), 1.0)
	motion.play(EnemyHitMotion.KNOCK, knock, {
		"ms": flight,
		"hop_px": _knock_number("hopPx", EnemyHitMotion.KNOCK_HOP_PX) * resist,
		"squash_along": lerpf(1.0, _knock_number("squashAlong", EnemyHitMotion.KNOCK_SQUASH_ALONG), resist),
		"squash_across": lerpf(1.0, _knock_number("squashAcross", EnemyHitMotion.KNOCK_SQUASH_ACROSS), resist),
		"stretch_along": lerpf(1.0, _knock_number("stretchAlong", EnemyHitMotion.STRETCH_ALONG), resist),
		"stretch_across": lerpf(1.0, _knock_number("stretchAcross", EnemyHitMotion.STRETCH_ACROSS), resist),
		"tilt": EnemyHitMotion.FALL_RAD if falls else _knock_number("tiltRad", 0.0),
		"tilt_hold": falls,
		"ghosts": _knock_number("afterimages", 0.0),
		"dust_px": _knock_number("dustEveryPx", 0.0),
		"then": then,
		"then_params": follow,
	})


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
	state.chains = false
	state.chain_depth = 0
	state.bowl_damage = -1.0


## A throw's chain on a launch just remembered: the hit's `chains` and `bowl_damage` (what its
## bowling deals instead of `combat.rules.bowling.damage`), read in `_bowl` and `_bowl_into`.
static func _carry_chain(state: ReactionState, hit: Dictionary) -> void:
	state.chains = _flag(hit, "chains")
	state.bowl_damage = _hit_number(hit, "bowl_damage", -1.0)


## A `chains` hit's knock slide (a stun that slides at `speed`) is a launch for as long as it is fast
## enough to splat or bowl (over the lower of `wallSplat.minSpeed` and `bowling.minSpeed`), so
## `after_move` runs the wall splat and bowling for it.
static func _open_chain(state: ReactionState, hit: Dictionary, body: CharacterBody2D, damage: float, speed: float,
		now: float) -> void:
	if not _flag(hit, "chains"):
		return
	_remember_launch(state, body, damage)
	_carry_chain(state, hit)
	var slowest := minf(float(_dictionary("combat.rules.wallSplat").get("minSpeed", INF)),
		float(_dictionary("combat.rules.bowling").get("minSpeed", INF)))
	state.launched_at_ms = now
	state.launch_until_ms = now + _fast_ms(speed, state.slide_decay, slowest)


## How far (px) a slide that starts at `speed` and slows by `decay` per 60 Hz step goes before it
## stops (`speed_for_distance` the other way round, over SLIDE_WHOLE_MS).
static func _slide_px(speed: float, decay: float) -> float:
	var one := speed_for_distance(1.0, SLIDE_WHOLE_MS, decay)
	return speed / one if one > 0.0 else 0.0


## How long (ms) a slide that starts at `speed` and slows by `decay` per 60 Hz step stays over
## `slowest`.
static func _fast_ms(speed: float, decay: float, slowest: float) -> float:
	if slowest <= 0.0 or speed <= slowest or decay <= 0.0 or decay >= 1.0:
		return 0.0
	return log(slowest / speed) / log(decay) * 1000.0 / 60.0


## A launched body hit a wall (the mover's collider, not an enemy or the slime) faster than
## `wallSplat.minSpeed` into it: squash, the share of the launch's damage, the freeze and trauma,
## bounce back, daze; once per chain.
## True when `collider` (the mover's) is the world's: not the slime's body, not an enemy's.
static func _is_obstacle(collider: Variant) -> bool:
	return is_instance_valid(collider) and collider is Object and not _is_player_body(collider as Object) \
		and _enemy_of(collider as Object) == null


## The blow moves the body from `now` for as long as it is faster than `combat.rules.hazards.minSpeed`
## (starting at `speed`, slowing by `decay` per 60 Hz step): the ground's hazards take it meanwhile
## (`after_move`, enemy_hazards.gd).
static func _mark_blown(state: ReactionState, speed: float, decay: float, now: float) -> void:
	if speed <= _number("combat.rules.hazards.minSpeed"):
		return
	state.blown_until_ms = maxf(state.blown_until_ms, now + _fast_ms(speed, decay, _number("combat.rules.hazards.minSpeed")) + BLOWN_GRACE_MS)


## The pop streak's pitch for a kill at `now` (enemy_hazards.gd: a death by a hole or deep water).
static func kill_pitch(now: float) -> float:
	return _pop_pitch(now)


## The blink of a body that falls into a hole or sinks (enemy_hazards.gd): a send-off's.
static func flash_fate(enemy: Node) -> void:
	_flash(enemy, {}, true)


## Damage the ground deals (enemy_hazards.gd: a fall, a danger zone): reaction damage, and a death
## by it is a send-off's pop where the enemy lies. Returns what it dealt.
static func hurt_by_ground(enemy: Node, state: ReactionState, amount: int, now: float) -> int:
	return _chain_hurt(enemy, state, true, amount, Vector2.ZERO, now)


static func _try_splat(enemy: Node, body: CharacterBody2D, state: ReactionState, info: Dictionary, now: float) -> void:
	var splat := _dictionary("combat.rules.wallSplat")
	if state.splats_this_chain >= int(splat.get("perChain", 0)):
		return
	var collider: Variant = info.get("collider")
	if not is_instance_valid(collider) or not collider is Object or _is_player_body(collider as Object) \
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
	# A throw's knocked body (a chain slide) keeps the stun it flew with when that is a knockdown: it
	# stays down against the wall, for at least the splat's daze.
	var stays_down := state.chains and state.in_stun(now, HitReaction.VERB_KNOCKDOWN)
	if not stays_down:
		state.verb = HitReaction.VERB_DAZE
		state.damage_taken = 1.0
	state.stun_until_ms = maxf(state.stun_until_ms, now + daze_ms)
	state.hold_count = 0
	# The daze is the splat's opening: no wake guard over it.
	state.wake_until_ms = now
	# A throw's chain leaves it helpless against the wall (`is_helpless`), once the squash is over.
	state.throw_helpless = state.chains
	state.helpless_from_ms = now + float(splat.get("squashMs", EnemyHitMotion.SPLAT_MS))
	_call(enemy, &"cancel_attack")
	_stun(enemy, now + daze_ms)
	state.slide_decay_until_ms = 0.0
	body.velocity = normal * speed_for_distance(float(splat.get("bouncePx", 0.0)), daze_ms)
	var motion := motion_of(enemy)
	if motion != null:
		var params := {"along": float(splat.get("squashX", EnemyHitMotion.SPLAT_ALONG)),
			"across": float(splat.get("squashY", EnemyHitMotion.SPLAT_ACROSS)), "ms": float(splat.get("squashMs", EnemyHitMotion.SPLAT_MS))}
		if state.chains:
			# The stun's own motion follows the squash: down on its back, or the daze sway.
			var rest := maxf(0.0, state.stun_until_ms - now - float(params["ms"]) - EnemyHitMotion.ELASTIC_MS)
			params["then"] = EnemyHitMotion.FALL if stays_down else EnemyHitMotion.DAZE
			params["then_params"] = {"ms": rest, "down": true} if stays_down else {"ms": rest}
		motion.play(EnemyHitMotion.SPLAT, normal, params)
		motion.show_stars(state.stun_until_ms, _knock_number("starScale", 1.0) if state.chains else 1.0)
	_puff_at(enemy, PUFF_DUST)
	var dealt := _chain_hurt(enemy, state, state.chains, roundi(state.launch_damage * float(splat.get("damageShare", 0.0))),
		Vector2.ZERO, now)
	_play_feel({"hit_stop_ms": float(splat.get("hitStopMs", 0.0)), "trauma": float(splat.get("trauma", 0.0)),
		"number": dealt, "number_big": false}, _centre_of(enemy), normal)


## A launched body (alive or a sliding corpse) runs into other enemies' bodies: each, once per launch,
## takes `bowling.speedShare` of its speed as its own launch (heavy enemies and bosses only shake)
## and both take `bowling.damage`; the launcher keeps the rest of its speed.
## A throw's chain (`state.chains`): both take the throw's `bowl_damage` instead, the bowled body
## carries the chain on one deeper, and a body deeper than `bowling.chainPasses` bowls no one (the
## struck enemy bowls its friend, who can pass it on once); a body the contact kills is sent off
## (`_chain_hurt`).
static func _bowl(enemy: Node, body: CharacterBody2D, state: ReactionState, now: float) -> void:
	if state.launch_layer == 0:
		return
	if state.chains and state.chain_depth > int(_dictionary("combat.rules.bowling").get("chainPasses", 0)):
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
		_bowl_into(enemy, body, state, other, other_body, now)


static func _bowl_into(enemy: Node, body: CharacterBody2D, state: ReactionState, other: Node, other_body: CharacterBody2D,
		now: float) -> void:
	var bowling := _dictionary("combat.rules.bowling")
	var share := float(bowling.get("speedShare", 0.0))
	var damage := roundi(state.bowl_damage if state.chains and state.bowl_damage >= 0.0 else float(bowling.get("damage", 0.0)))
	# Bowled into, a sleeper wakes (its bowling damage), and its launch then runs as on anyone.
	if damage > 0:
		wake(other)
	var direction := _centre_of(other) - _centre_of(enemy)
	direction = direction.normalized() if direction != Vector2.ZERO else body.velocity.normalized()
	var passed := body.velocity.length() * share
	body.velocity *= maxf(0.0, 1.0 - share)
	var profile := ReactionProfile.for_enemy(other)
	var other_state := state_of(other)
	var motion := motion_of(other)
	var speed := minf(_number("combat.verbs.launch.maxSpeed"), passed * float(profile.get("knockbackScale", 1.0)))
	var shoved := Vector2.ZERO
	if HEAVY_WEIGHTS.has(str(profile.get("weight", ""))) or speed <= 0.0:
		if motion != null:
			_play_heavy(motion, str(profile.get("weight", "")), direction)
	else:
		shoved = direction * speed
		var stun := _number("combat.verbs.launch.stunMs") * _stun_scale(profile)
		# In a throw's chain the bowled body ends its tumble dazed (`bowling.chainDazeMs`, stars), with
		# no wake guard over that daze, as after a wall splat: it lies helpless (`is_helpless`).
		var daze := float(bowling.get("chainDazeMs", 0.0)) * _stun_scale(profile) if state.chains else 0.0
		other_state.verb = HitReaction.VERB_DAZE if daze > 0.0 else HitReaction.VERB_LAUNCH
		other_state.stun_until_ms = maxf(other_state.stun_until_ms, now + stun + daze)
		other_state.launched_at_ms = now
		other_state.launch_until_ms = now + stun
		other_state.hold_count = 0
		if daze > 0.0:
			other_state.wake_until_ms = now
		else:
			other_state.wake_until_ms = maxf(other_state.wake_until_ms, now + stun + _number("combat.rules.wakeGuardMs"))
		other_state.throw_helpless = daze > 0.0
		other_state.helpless_from_ms = now + stun
		_remember_launch(other_state, other_body, 0.0)
		if state.chains:
			other_state.chains = true
			other_state.chain_depth = state.chain_depth + 1
			other_state.bowl_damage = state.bowl_damage
		other_state.bowled[enemy.get_instance_id()] = true
		_call(other, &"cancel_attack")
		_stun(other, now + stun + daze)
		_call(other, &"play_hurt", [HURT_ACTION])
		other_state.slide_decay_until_ms = 0.0
		other_body.velocity = direction * speed
		_mark_blown(other_state, speed, slide_decay(), now)
		if motion != null:
			var params := {"deg": _number("combat.verbs.launch.spinDeg"), "hop_px": _number("combat.verbs.launch.hopPx"), "ms": stun}
			if daze > 0.0:
				params["then"] = EnemyHitMotion.DAZE
				params["then_params"] = {"ms": maxf(0.0, daze - EnemyHitMotion.LANDING_MS)}
				motion.show_stars(other_state.stun_until_ms, _knock_number("starScale", 1.0))
			motion.play(EnemyHitMotion.TUMBLE, direction, params)
	# In a throw's chain the contact is a blow of its own: the hard flash on the bowled body, and a
	# short freeze, a little trauma, sparks, a ring and dust between the two (`bowling.chainFeel`).
	_flash(other, {"big": true} if state.chains else {})
	var between := (_centre_of(enemy) + _centre_of(other)) * 0.5
	# A boss bowled into takes the plain `bowling.damage`, chain or not (its fight's rules stay its own).
	var boss := str(profile.get("weight", "")) == WEIGHT_BOSS
	var dealt_other := _chain_hurt(other, other_state, state.chains, roundi(float(bowling.get("damage", 0.0))) if boss else damage,
		shoved, now)
	var dealt_self := _chain_hurt(enemy, state, state.chains, damage, body.velocity, now)
	var chain_feel: Variant = bowling.get("chainFeel") if state.chains else null
	if chain_feel is Dictionary:
		_play_feel({"hit_stop_ms": float((chain_feel as Dictionary).get("hitStopMs", 0.0)),
			"trauma": float((chain_feel as Dictionary).get("trauma", 0.0)), "sparks": int((chain_feel as Dictionary).get("sparks", 0)),
			"impact_ring": bool((chain_feel as Dictionary).get("ring", false)), "dust": bool((chain_feel as Dictionary).get("dust", false))},
			between, direction)
	_play_feel({"hit_stop_ms": 0.0, "number": dealt_other, "number_big": false}, _centre_of(other), direction)
	if dealt_self > 0:
		_play_feel({"hit_stop_ms": 0.0, "number": dealt_self, "number_big": false}, _centre_of(enemy), -direction)


# --- helpers ------------------------------------------------------------------------------------

## `launch_speed` x `knockbackScale` x `scale`, capped at `combat.verbs.launch.maxSpeed`.
static func _launch_speed(hit: Dictionary, profile: Dictionary, scale: float) -> float:
	var speed := float(hit.get("launch_speed", 0.0)) if (hit.get("launch_speed") is float or hit.get("launch_speed") is int) else 0.0
	var resist := float(profile.get("knockbackScale", 1.0)) if (profile.get("knockbackScale") is float or profile.get("knockbackScale") is int) else 1.0
	return clampf(speed * resist * scale, 0.0, _number("combat.verbs.launch.maxSpeed"))


## A damaging hit's knock slide: the start speed that covers the hit's `knock_px` x the profile's
## `knockbackScale` in `ms` (the stun that holds the body while it slides), slowing
## `knock_speed_scale` times as fast as a stun slide (`slideDecay` ^ scale, kept in the memory for
## `ms`: `slide_decay_of`), so 2 covers it in half the time; 0, and no slide, when the hit dealt no
## damage (immune, a shut gate, a sleep throw), has no `knock_px` or no time to slide.
static func _knock_slide(state: ReactionState, hit: Dictionary, profile: Dictionary, damage: float, ms: float,
		now: float) -> float:
	var px := float(hit.get("knock_px", 0.0)) if (hit.get("knock_px") is float or hit.get("knock_px") is int) else 0.0
	var resist := float(profile.get("knockbackScale", 1.0)) if (profile.get("knockbackScale") is float or profile.get("knockbackScale") is int) else 1.0
	var pace := float(hit.get("knock_speed_scale", 1.0)) if (hit.get("knock_speed_scale") is float or hit.get("knock_speed_scale") is int) else 1.0
	if damage <= 0.0 or ms <= 0.0 or px * resist <= 0.0:
		return 0.0
	state.slide_decay = pow(clampf(slide_decay(), 0.0, 1.0), maxf(pace, 0.01))
	state.slide_decay_until_ms = now + ms
	return speed_for_distance(px * resist, ms, state.slide_decay)


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
## the motion's white fill (a dummy). A throw's hard hit (the hit's `big`) and a kill's send-off
## (`sendoff`) flash their own curve (`combat.verbs.knock.flash`, `combat.rules.killSendoff.flash`:
## white for `whiteMs`, the tint and the white in turns for `blinkMs`, a pair every `blinkPeriodMs`,
## then the tint fading over `tintMs`), under the same flash switch; a `big` hit that dealt no damage
## (`hurt` false: a sleep throw, a shut part) flashes as any hit.
static func _flash(enemy: Node, hit: Dictionary, sendoff: bool = false, hurt: bool = true) -> void:
	var feel := Services.feel()
	var visual: Variant = enemy.call(&"get_visual") if enemy.has_method(&"get_visual") else null
	if feel != null and feel.has_method(&"flash_hit") and is_instance_valid(visual) and visual is CanvasItem:
		var hard := _dictionary("combat.rules.killSendoff.flash") if sendoff \
			else (_dictionary("combat.verbs.knock.flash") if hurt and _flag(hit, "big") else {})
		if hard.is_empty():
			feel.call(&"flash_hit", visual, _big_hit(hit))
		elif not feel.has_method(&"juice_layer_on") or bool(feel.call(&"juice_layer_on", FLASH_LAYER)):
			HitFlash.flash_curve(visual, HitFlash.HURT_TINT, true, float(hard.get("whiteMs", -1.0)),
				float(hard.get("tintMs", -1.0)), Color.WHITE, float(hard.get("blinkMs", 0.0)),
				float(hard.get("blinkPeriodMs", 0.0)))
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


## `_hurt`, and in a throw's chain (`chains`) a body this damage kills is sent off like the throw's
## own kill: its corpse keeps `slide` (ZERO: it stays) and pops (`combat.rules.killSendoff`).
static func _chain_hurt(enemy: Node, state: ReactionState, chains: bool, amount: int, slide: Vector2, now: float) -> int:
	var sends := chains and amount > 0 and not _defeated(enemy) and _can_send_off(enemy) and _health(enemy) <= float(amount)
	if not sends:
		return _hurt(enemy, amount)
	var flies := slide != Vector2.ZERO and enemy.has_method(&"set_death_slide")
	state.sendoff = true
	if flies:
		enemy.call(&"set_death_slide", slide)
		_mark_blown(state, slide.length(), slide_decay_of(enemy), now)
	var dealt := _hurt(enemy, amount)
	if not _defeated(enemy):
		state.sendoff = false
		if flies:
			enemy.call(&"set_death_slide", Vector2.ZERO)
		return dealt
	var rule := _dictionary("combat.rules.killSendoff")
	var last := now + float(rule.get("maxMs" if flies else "stillMs", 0.0))
	enemy.call(&"begin_sendoff", now + float(rule.get("minMs", 0.0)) if flies else last, last)
	if flies:
		state.launch_until_ms = maxf(state.launch_until_ms, last)
	state.sendoff_pitch = _pop_pitch(now)
	_flash(enemy, {}, true)
	return dealt


## Whether `enemy`'s corpse can be sent off (a throw's kill): never a boss's (by weight, or by rank:
## `can_send_off`) or a dummy's.
static func _can_send_off(enemy: Node) -> bool:
	if _is_dummy(enemy) or not enemy.has_method(&"begin_sendoff") or not enemy.has_method(&"can_send_off"):
		return false
	return str(ReactionProfile.for_enemy(enemy).get("weight", "")) != WEIGHT_BOSS and bool(enemy.call(&"can_send_off"))


## The enemy's health now (INF when it does not say).
static func _health(enemy: Node) -> float:
	if not enemy.has_method(&"get_damage_state"):
		return INF
	var found: Variant = enemy.call(&"get_damage_state")
	return float((found as Dictionary).get("hp", INF)) if found is Dictionary else INF


## A hard hit (the hit's `big`, a throw's) shakes the victim through the freeze that follows:
## `combat.verbs.knock.shakePx` side to side, shrinking over `shakeMs`.
static func _shake_in_freeze(enemy: Node, hit: Dictionary) -> void:
	if not _flag(hit, "big"):
		return
	var motion := enemy.get_node_or_null(NodePath(MOTION_NODE)) as EnemyHitMotion
	if motion != null:
		motion.shake_in_freeze(_knock_number("shakePx", 0.0), _knock_number("shakeMs", EnemyHitMotion.FREEZE_SHAKE_MS))


## True when `hit` carries the flag `key` (the throw's new feel: big, chains, knock_motion,
## kill_sendoff).
static func _flag(hit: Dictionary, key: String) -> bool:
	return hit.get(key) is bool and bool(hit[key])


## The number at `key` of `row` (a hit or a profile), `fallback` when it has none.
static func _hit_number(row: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = row.get(key)
	return float(value) if (value is float or value is int) and is_finite(float(value)) else fallback


## `combat.verbs.knock.<key>` (the knock's look), `fallback` when the data has none.
static func _knock_number(key: String, fallback: float) -> float:
	var value: Variant = _dictionary("combat.verbs.knock").get(key)
	return float(value) if (value is float or value is int) else fallback


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
	return body as CharacterBody2D if is_instance_valid(body) and body is CharacterBody2D else null


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
