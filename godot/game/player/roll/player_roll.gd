extends RefCounted
## The Roll (owner, 2026-10-08/09; roadmap 7.7), the Dodge's successor on key 2. The ability keeps
## the id and the input action `dodge`, so saves, quests and the HUD slot stay as they were; the
## player sees "Roll". Owned by player.gd. It feels like Zelda's Pegasus Boots dash (owner,
## 2026-10-09): it goes straight, nothing steers it, and running into something is a bonk.
##
## - **Spin-up:** the slime curls into the ball (the `ball` clip, page 4 of the slime sheet) and
##   spins in place for `rollSpinUpMs`, its clip SPIN_UP_CLIP_SPEED times too fast, laying skid
##   streaks and kicking dust back like screeching tires (roll_fx.gd; cue `RollRev`). It does not
##   move.
## - **Launch:** it shoots off at `rollLaunchSpeed` along one of eight directions (the pointer aim,
##   else the held movement keys, else the facing), easing to `rollSpeed` over `rollMinMs`, and is
##   safe from hits for `rollInvulnerabilityMs` from the launch (cue `RollLaunch`). The movement keys
##   do nothing while it rolls: it cannot turn or slide sideways.
## - **Rolling on:** after `rollMinMs` it keeps rolling while the key is held, draining
##   `rollEnergyPerSecond` (energy does not refill while it rolls); letting go or running out of
##   energy stops it. Everything about the Roll comes with the lesson (owner, 2026-10-09).
## - **Bonk:** a wall, a rock or an enemy that stops the ball on either axis is a bonk (cue
##   `RollBonk`): the screen shakes (`rollBonkShakeMs`, `rollBonkShakeIntensity`, a short hit-stop),
##   the things standing around the impact wobble (`rollBonkWobbleRadiusPx`), an enemy there is hit
##   (`rollBonkDamage`, `rollBonkKnockback` within `rollBonkHitRadiusPx`), and the slime bounces back
##   off it in a little hop (`rollBounceSpeed` easing out over `rollBounceMs`, `rollBounceHopPx`) and
##   only then is free again.
## - **Heavy** (the Heavy skin, Pearl 1's: SkinState, always on once won; docs/godot/SKINS.md
##   "Heavy"): the Heavy Roll. Its bonk's hit also carries the tag `heavy`, which breaks the old,
##   grey, dead or built things lying or leaning in the way (plank barricades, rotten timbers,
##   rubble heaps, loose rocks, old trunks and fences: game/scripts/plank_barricade.gd) and a Thorn
##   Guard Statue; its screen shake is strong (`skins.heavy.rollBonkShake*`, a plain bonk shakes
##   much less: owner, 2026-10-16), and it shakes loose what hangs or sits loose round the impact
##   (game/scripts/loose_prize.gd hears the heavy ground shake). The ground shakes
##   (game/enemy/ground_shake.gd): every bonk shakes `rollBonkShakeRadiusPx` round the impact (heavy
##   or not, the listeners decide), and a Heavy ball rumbles `rollHeavyRumbleRadiusPx` round its feet
##   every step it rolls (a Popworm's mound there throws it out, dazed; docs/godot/BESTIARY.md). It
##   pushes no enemy away (a later upgrade, owner 2026-10-16), and the slime shows the skin while it
##   rolls (player.gd `show_skin`). It **crushes tiny enemies** (reaction weight `tiny`: the Matron's
##   Broodlings, the Colossus's Crystal Mites; owner, 2026-11-24, "crush them"): a tiny one's hurtbox
##   within `rollHeavyCrushRadiusPx` of the ball's front (`rollHeavyCrushAheadPx` ahead of the bonk's
##   point) takes a killing hit (`rollHeavyCrushDamage`, tags roll and heavy) before the ball touches
##   it, pops flat, and the ball rolls on through, no bonk (`_crush_ahead`). It **breaks light things
##   to throw** in its way the same way (a pot, a rock, a web ball: weight `light`; owner, 2026-11-24):
##   each bursts into its picture's shards with its material's particles and sound, as a thrown one
##   breaks, and goes as if sucked up, leaving what it hid (`_break_ahead`); heavier ones still bonk.
## - **Webs:** a Roll sticks in a web (owner, 2026-10-16, question 131): a floor web or a web
##   barrier catches the rolling slime as it does a walking one (game/enemy/spider_web_port.gd),
##   which ends the roll there (`cancel` through player.gd `stop_movement`; no bonk) and roots the
##   slime. With the Silk skin (player.gd `crosses_webs`) webs no longer catch it, and it tears
##   through them.
## - The next roll can start `rollCooldownMs` after this one ends. A knockback, a death, a door or
##   a web ends it at once (`cancel`).
## All values are in `character.player.movement` (game-constants.json).
##
## Body-shapes rework (docs/godot/BODY_SHAPES.md; owner, 2026-10-12), only while the mode is on: the
## Roll fires on the release. player.gd arms it on the press (`_due_roll`); a tap (released
## within `character.player.rework.rollTapMs`), and any release without the `roll-charge` upgrade
## (CHARGE_UPGRADE_ID), rolls the **quick roll** (`begin_quick`): no spin-up, straight off at once,
## `quickRollDistancePx` over `quickRollMs`, slowing to `quickRollEndSpeedShare` of its launch speed,
## safe for `quickRollInvulnerabilityMs`, and it bonks as any roll. A hold past the tap with the
## upgrade learned is the **charged roll** (`begin` with `launch_on_release`): the spin-up while held,
## the launch at the release or at the spin-up's end, rolling on while held as above. The classic
## game keeps the Roll above exactly.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const RollFx := preload("res://game/player/roll/roll_fx.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const GroundShake := preload("res://game/enemy/ground_shake.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const ReactionProfile := preload("res://game/combat/reactions/reaction_profile.gd")
const BreakBurst := preload("res://game/player/gulp/break_burst.gd")
const ThrownObject := preload("res://game/player/gulp/thrown_object.gd")

const CLIP_BALL := "ball"
const CLIP_BOUNCE := "knockback"
## The ball's spin during the spin-up, as a multiple of its clip's speed; after the launch the
## spin follows the roll's speed (the clip at `rollSpeed` = 1).
const SPIN_UP_CLIP_SPEED := 3.0
const CUE_REV := &"RollRev"
const CUE_LAUNCH := &"RollLaunch"
const CUE_BONK := &"RollBonk"
const PARTICLES_LAUNCH := &"dodge-dust"
const PARTICLES_BONK := &"hit-spark"
## Dust kicked back every this many ms of the spin-up, this many puffs, this fast.
const DUST_EVERY_MS := 50.0
const DUST_PUFFS := 2
const DUST_SPEED := 120.0
const LAUNCH_PUFFS := 6
const BONK_PUFFS := 8
## A blocked axis: the mover left less than this share of the speed asked of it on that axis.
const BLOCKED_SHARE := 0.5
## Things around a bonk wobble this much (radians), dying away over WOBBLE_S.
const WOBBLE_RAD := 0.14
const WOBBLE_S := 0.55
const WOBBLE_TURNS := 4.0
const FX_NAME := "RollFx"
const BALL_REACH_PX := 18.0
## The bonk's hit tags; HEAVY_TAG joins them with the Heavy skin.
const BONK_TAG := "roll"
const HEAVY_TAG := "heavy"
## The Heavy Roll's crush: the squish's sound, its weapon id, the reaction weight it crushes, and how
## long after a crush a cut step is the crushed one's body, not a bonk (ms).
const CUE_CRUSH := &"BreakSoft"
const CRUSH_WEAPON := "roll-crush"
const CRUSH_WEIGHT := "tiny"
const CRUSH_GRACE_MS := 80.0
## The things to throw a Heavy ball breaks in its way: light ones (a pot, a rock, a web ball).
const BREAK_WEIGHT := "light"
## Rework mode: the upgrade that lets a held Roll key charge (the spin-up); without it every roll is
## the quick roll. The playground's testbed lends it for the session (shapes_testbed.gd).
const CHARGE_UPGRADE_ID := &"roll-charge"
const REWORK_CONSTANTS := "character.player.rework."

enum Phase { NONE, SPIN, ROLL, BOUNCE }

## The slime (player.gd): body, animation, face, play_animation, set_effect_offset, spend_energy,
## get_centre.
var _player: Node
var _phase: Phase = Phase.NONE
var _direction: Vector2 = Vector2.RIGHT
var _started_ms: float = 0.0
var _launched_ms: float = 0.0
var _bounce_started_ms: float = 0.0
var _invulnerable_until_ms: float = 0.0
var _ready_at_ms: float = 0.0
var _next_dust_ms: float = 0.0
## The velocity set last step (ZERO during the spin-up), to tell a blocked axis.
var _asked: Vector2 = Vector2.ZERO
## Rework mode: this roll is the quick roll (`begin_quick`), or a charged roll whose spin-up ends at
## the key's release (`begin` with `launch_on_release`).
var _quick: bool = false
var _launch_on_release: bool = false
## When the Heavy Roll last crushed a tiny enemy (a cut step just after is its body, not a bonk).
var _crushed_ms: float = -INF


func _init(player: Node) -> void:
	_player = player


## True from the press to the end of the roll, spin-up and bounce included.
func is_active() -> bool:
	return _phase != Phase.NONE


func is_spinning_up() -> bool:
	return _phase == Phase.SPIN


func is_bouncing() -> bool:
	return _phase == Phase.BOUNCE


## The launch's i-frames.
func is_invulnerable(now_ms: float) -> bool:
	return now_ms < _invulnerable_until_ms


## No roll on and the last one's cooldown over.
func can_begin(now_ms: float) -> bool:
	return _phase == Phase.NONE and now_ms >= _ready_at_ms


## True while the Heavy skin is on: every Roll is a Heavy Roll.
func is_heavy() -> bool:
	return SkinState.is_on(_player, SkinState.HEAVY)


## The way the ball rolls (unit, one of eight directions).
func direction() -> Vector2:
	return _direction


## The speed the ball rolls at (0 during the spin-up and the bounce).
func speed() -> float:
	return _asked.length() if _phase == Phase.ROLL else 0.0


## Starts the spin-up toward `toward` (snapped to eight directions). False when a roll is on, its
## cooldown runs or there is no body. Rework mode: `launch_on_release` (the charged roll) launches
## the ball as soon as the key is let go during the spin-up.
func begin(toward: Vector2, now_ms: float, launch_on_release: bool = false) -> bool:
	var body := _body()
	if not can_begin(now_ms) or body == null:
		return false
	_aim_at(toward)
	_quick = false
	_launch_on_release = launch_on_release
	_phase = Phase.SPIN
	_started_ms = now_ms
	_next_dust_ms = now_ms
	_asked = Vector2.ZERO
	body.velocity = Vector2.ZERO
	_player.call(&"face", _direction)
	_player.call(&"play_animation", CLIP_BALL, true)
	_set_clip_speed(SPIN_UP_CLIP_SPEED)
	_cue(CUE_REV)
	return true


## Rework mode: the quick roll toward `toward` (snapped to eight directions): no spin-up, the ball
## shoots off at once and rolls `quickRollDistancePx` in `quickRollMs`, slowing to
## `quickRollEndSpeedShare` of its launch speed, whether the key is held or not; it bonks as any
## roll. False when a roll is on, its cooldown runs or there is no body.
func begin_quick(toward: Vector2, now_ms: float) -> bool:
	var body := _body()
	if not can_begin(now_ms) or body == null:
		return false
	_aim_at(toward)
	_quick = true
	_launch_on_release = false
	_started_ms = now_ms
	_player.call(&"face", _direction)
	_player.call(&"play_animation", CLIP_BALL, true)
	_launch(now_ms, body)
	return true


## Every physics step while a roll is on: `held` is whether the roll key is still down. The
## movement keys are not asked: the ball goes straight.
func update(now_ms: float, delta: float, held: bool) -> void:
	var body := _body()
	if body == null:
		cancel()
		return
	match _phase:
		Phase.SPIN:
			_spin(now_ms, body, held)
		Phase.ROLL:
			_roll(now_ms, delta, held, body)
		Phase.BOUNCE:
			_bounce(now_ms, body)


## The roll is over: the ball stops and the next roll waits `rollCooldownMs`. player.gd's next
## walk step brings back idle or walk.
func end(now_ms: float) -> void:
	if _phase == Phase.NONE:
		return
	_finish(now_ms)
	var body := _body()
	if body != null:
		body.velocity = Vector2.ZERO


## A knockback, a death or a door: the roll stops where it is, leaving the body's velocity alone.
func cancel() -> void:
	if _phase == Phase.NONE:
		return
	_invulnerable_until_ms = 0.0
	_finish(Services.now_ms())


func _spin(now_ms: float, body: CharacterBody2D, held: bool) -> void:
	body.velocity = Vector2.ZERO
	var spin_up := maxf(1.0, _constant("rollSpinUpMs"))
	var fx := _fx()
	if fx != null:
		fx.skid(_feet(), _direction, (now_ms - _started_ms) / spin_up)
		if now_ms >= _next_dust_ms:
			_next_dust_ms = now_ms + DUST_EVERY_MS
			fx.kick(_feet(), _direction, DUST_PUFFS, DUST_SPEED)
	if now_ms - _started_ms >= spin_up or (_launch_on_release and not held):
		_launch(now_ms, body)


func _launch(now_ms: float, body: CharacterBody2D) -> void:
	_phase = Phase.ROLL
	_launched_ms = now_ms
	var safe_ms := _rework_constant("quickRollInvulnerabilityMs") if _quick else _constant("rollInvulnerabilityMs")
	_invulnerable_until_ms = now_ms + safe_ms
	_asked = _direction * (_quick_launch_speed() if _quick else _constant("rollLaunchSpeed"))
	body.velocity = _asked
	_set_clip_speed(_asked.length() / maxf(1.0, _constant("rollSpeed")))
	_cue(CUE_LAUNCH)
	var feel := Services.feel()
	if feel != null:
		feel.particles(PARTICLES_LAUNCH, _feet())
	var fx := _fx()
	if fx != null:
		fx.kick(_feet(), _direction, LAUNCH_PUFFS, DUST_SPEED * 1.5)


func _roll(now_ms: float, delta: float, held: bool, body: CharacterBody2D) -> void:
	# A Heavy ball crushes the tiny enemies just ahead of it before it touches them.
	if _crush_ahead():
		_crushed_ms = now_ms
	# The mover cut an axis on the last step: a wall, a rock or an enemy is in the way (not a tiny
	# one just crushed: its body clears at the end of the step).
	if _blocked(body.velocity) and now_ms - _crushed_ms > CRUSH_GRACE_MS:
		_bonk(now_ms, body)
		return
	if is_heavy():
		GroundShake.shake(_feet(), _constant("rollHeavyRumbleRadiusPx"), true)
		SkinState.show(_player, SkinState.HEAVY)
	var rolled := now_ms - _launched_ms
	if _quick:
		_roll_quick(now_ms, rolled, body)
		return
	var min_ms := maxf(1.0, _constant("rollMinMs"))
	if rolled >= min_ms:
		if not held or not bool(_player.call(&"spend_energy", _constant("rollEnergyPerSecond") * delta)):
			end(now_ms)
			return
	var cruise := _constant("rollSpeed")
	var speed_now := lerpf(_constant("rollLaunchSpeed"), cruise, clampf(rolled / min_ms, 0.0, 1.0))
	_asked = _direction * speed_now
	body.velocity = _asked
	_set_clip_speed(speed_now / maxf(1.0, cruise))


## Rework mode: the quick roll's straight run, its launch speed easing linearly down to
## `quickRollEndSpeedShare` of it, over `quickRollMs`; then it ends.
func _roll_quick(now_ms: float, rolled: float, body: CharacterBody2D) -> void:
	var length := maxf(1.0, _rework_constant("quickRollMs"))
	if rolled >= length:
		end(now_ms)
		return
	var launch := _quick_launch_speed()
	var speed_now := lerpf(launch, launch * _quick_end_share(), rolled / length)
	_asked = _direction * speed_now
	body.velocity = _asked
	_set_clip_speed(speed_now / maxf(1.0, _constant("rollSpeed")))


## The quick roll's launch speed: the one that covers `quickRollDistancePx` in `quickRollMs` while
## easing linearly to `quickRollEndSpeedShare` of it (distance = the mean speed x the time).
func _quick_launch_speed() -> float:
	var seconds := maxf(1.0, _rework_constant("quickRollMs")) / 1000.0
	return 2.0 * _rework_constant("quickRollDistancePx") / (seconds * (1.0 + _quick_end_share()))


func _quick_end_share() -> float:
	return clampf(_rework_constant("quickRollEndSpeedShare"), 0.0, 1.0)


## Faces the ball toward `toward`, snapped to eight directions (RIGHT when ZERO).
func _aim_at(toward: Vector2) -> void:
	var aim := toward if toward != Vector2.ZERO else Vector2.RIGHT
	_direction = Vector2.RIGHT.rotated(snappedf(aim.angle(), PI / 4.0))


func _blocked(velocity: Vector2) -> bool:
	if _asked == Vector2.ZERO:
		return false
	var cut_x := absf(_asked.x) > 1.0 and absf(velocity.x) < absf(_asked.x) * BLOCKED_SHARE
	var cut_y := absf(_asked.y) > 1.0 and absf(velocity.y) < absf(_asked.y) * BLOCKED_SHARE
	return cut_x or cut_y


## The Heavy Roll crushes the tiny enemies in its way (see the head): a killing hit on each tiny
## one's hurtbox within reach of the ball's front, a squish, a short hit-stop. True when one was hit.
func _crush_ahead() -> bool:
	if not is_heavy():
		return false
	var broke := _break_ahead()
	var router := Services.router()
	if router == null:
		return broke
	var front := _centre() + _direction * (BALL_REACH_PX + _constant("rollHeavyCrushAheadPx"))
	var tiny: Array[Area2D] = []
	for area: Area2D in AbilityWorld.hurtboxes_at(_player, front, _constant("rollHeavyCrushRadiusPx")):
		var receiver: Variant = router.receiver_for_area(area)
		if not receiver is Node or not (receiver as Node).has_method(&"is_defeated") or bool((receiver as Node).call(&"is_defeated")):
			continue
		if str(ReactionProfile.for_enemy(receiver as Node).get("weight", "")) == CRUSH_WEIGHT:
			tiny.append(area)
	if tiny.is_empty():
		return broke
	var tags: Array[String] = [BONK_TAG, HEAVY_TAG]
	AbilityWorld.strike_targets(_player, front, tiny, _constant("rollHeavyCrushDamage"), 0.0, tags, CRUSH_WEAPON)
	_cue(CUE_CRUSH)
	var feel := Services.feel()
	if feel != null:
		feel.hit_stop(_constant("rollHeavyCrushHitStopMs"))
		feel.particles(PARTICLES_LAUNCH, front)
	return true


## The Heavy Roll breaks the light things to throw in its way (the owner, 2026-11-24: "it make no sence
## that light throwables make you bounce back on roll, you should be able to breake them with heavy
## roll, so they break with the same animation as when throw"): each light liftable whose feet lie
## within `rollHeavyBreakRadiusPx` of the ball's front bursts into its own picture's shards with its
## material's particles and sound (a thrown thing's break: break_burst.gd, thrown_object.gd) and goes
## as if sucked up (what it hid is left where it stood: pot_loot.gd). True when one broke.
func _break_ahead() -> bool:
	var tree := _player.get_tree() if _player != null else null
	if tree == null:
		return false
	var front := _feet() + _direction * (BALL_REACH_PX + _constant("rollHeavyCrushAheadPx"))
	var radius := _constant("rollHeavyBreakRadiusPx")
	var broke := false
	for node: Node in tree.get_nodes_in_group(LiftableScript.GROUP):
		var root := node.get_parent() as Node2D
		if root == null or root.is_queued_for_deletion() or root.global_position.distance_to(front) > radius:
			continue
		if not node.has_method(&"weight") or str(node.call(&"weight")) != BREAK_WEIGHT:
			continue
		var visual := root.get_node_or_null(^"Visual") as Sprite2D
		if visual != null:
			BreakBurst.burst(root.get_parent(), root.global_position, visual)
		var material := LiftableScript.material_of(str(node.get(&"kind")))
		var feel := Services.feel()
		if feel != null:
			for preset: StringName in ThrownObject.BREAK_PARTICLES.get(material, [PARTICLES_LAUNCH]):
				feel.particles(preset, root.global_position)
			feel.audio_cue(ThrownObject.break_cue(material))
		node.call(&"take")
		broke = true
	return broke


func _bonk(now_ms: float, body: CharacterBody2D) -> void:
	_phase = Phase.BOUNCE
	_bounce_started_ms = now_ms
	_asked = Vector2.ZERO
	_invulnerable_until_ms = 0.0
	_set_clip_speed(1.0)
	var impact := _centre() + _direction * BALL_REACH_PX
	var heavy := is_heavy()
	_cue(CUE_BONK)
	var feel := Services.feel()
	if feel != null:
		if heavy:
			feel.shake(SkinState.setting("heavy.rollBonkShakeMs", 420.0), SkinState.setting("heavy.rollBonkShakeIntensity", 0.02))
			feel.hit_stop(SkinState.setting("heavy.rollBonkHitStopMs", 90.0))
		else:
			feel.shake(_constant("rollBonkShakeMs"), _constant("rollBonkShakeIntensity"))
			feel.hit_stop(_constant("rollBonkHitStopMs"))
		feel.particles(PARTICLES_BONK, impact)
		feel.particles(PARTICLES_LAUNCH, _feet() + _direction * BALL_REACH_PX)
	var fx := _fx()
	if fx != null:
		fx.kick(_feet() + _direction * BALL_REACH_PX, -_direction, BONK_PUFFS, DUST_SPEED)
	var damage := _constant("rollBonkDamage")
	if damage > 0.0:
		var tags: Array[String] = [BONK_TAG]
		if heavy:
			tags.append(HEAVY_TAG)
		AbilityWorld.strike_area(_player, impact, _constant("rollBonkHitRadiusPx"), damage,
			_constant("rollBonkKnockback"), tags, "roll-bonk")
	# A Heavy Roll's shake reaches further: it shakes loose what hangs or sits loose round the impact
	# (loose_prize.gd).
	var shake_radius := _constant("rollBonkShakeRadiusPx")
	if heavy:
		shake_radius = maxf(shake_radius, SkinState.setting("heavy.looseRadiusPx", 200.0))
		SkinState.show(_player, SkinState.HEAVY)
	GroundShake.shake(_feet() + _direction * BALL_REACH_PX, shake_radius, heavy)
	_wobble_around(impact, _constant("rollBonkWobbleRadiusPx"))
	_player.call(&"face", _direction)
	_player.call(&"play_animation", CLIP_BOUNCE, true)
	body.velocity = -_direction * _constant("rollBounceSpeed")


func _bounce(now_ms: float, body: CharacterBody2D) -> void:
	var length := maxf(1.0, _constant("rollBounceMs"))
	var t := clampf((now_ms - _bounce_started_ms) / length, 0.0, 1.0)
	body.velocity = -_direction * _constant("rollBounceSpeed") * (1.0 - t)
	# The hop rides the player's ability effects channel (player.gd `set_effect_offset`).
	_player.call(&"set_effect_offset", Vector2(0.0, -sin(PI * t) * _constant("rollBounceHopPx")))
	if t >= 1.0:
		end(now_ms)


func _finish(now_ms: float) -> void:
	if _phase == Phase.BOUNCE:
		_player.call(&"set_effect_offset", Vector2.ZERO)
	_phase = Phase.NONE
	_asked = Vector2.ZERO
	_quick = false
	_launch_on_release = false
	_ready_at_ms = now_ms + _constant("rollCooldownMs")
	_set_clip_speed(1.0)


## Every world thing standing within `radius` of `at` (a Node2D under the entities root with a
## Visual) wobbles, its art rocking and settling back (presentation only, real time).
func _wobble_around(at: Vector2, radius: float) -> void:
	var world := Services.world()
	var root: Node = world.entities_root() if world != null else null
	var body := _body()
	if root == null or radius <= 0.0:
		return
	for child: Node in root.get_children():
		var thing := child as Node2D
		if thing == null or thing == body or thing.global_position.distance_to(at) > radius:
			continue
		var art := thing.get_node_or_null(^"Visual") as Node2D
		if art == null:
			continue
		var side := -1.0 if thing.global_position.x < at.x else 1.0
		var rest := art.rotation
		var tween := art.create_tween()
		tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
		tween.tween_method(func(t: float) -> void:
			if is_instance_valid(art):
				art.rotation = rest + side * WOBBLE_RAD * (1.0 - t) * sin(t * TAU * WOBBLE_TURNS), 0.0, 1.0, WOBBLE_S)
		tween.tween_callback(func() -> void:
			if is_instance_valid(art):
				art.rotation = rest)


func _set_clip_speed(clip_speed: float) -> void:
	var animation := _player.get(&"animation") as AnimationPlayer
	if animation != null:
		animation.speed_scale = clip_speed


func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)


func _body() -> CharacterBody2D:
	return _player.get(&"body") as CharacterBody2D if _player != null else null


func _centre() -> Vector2:
	return _player.call(&"get_centre")


## The ground point under the ball's centre.
func _feet() -> Vector2:
	var body := _body()
	var centre := _centre()
	return Vector2(centre.x, body.global_position.y) if body != null else centre


## The world's RollFx, made on first use under the entities root (freed with the world).
func _fx() -> RollFx:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return null
	var fx := parent.get_node_or_null(FX_NAME) as RollFx
	if fx == null:
		fx = RollFx.new()
		fx.name = FX_NAME
		parent.add_child(fx)
	return fx


static func _constant(name: String) -> float:
	var constants := Services.constants()
	return constants.number("character.player.movement." + name) if constants != null else 0.0


## The rework mode's Roll numbers (`character.player.rework`).
static func _rework_constant(name: String) -> float:
	var constants := Services.constants()
	return constants.number(REWORK_CONSTANTS + name) if constants != null else 0.0
