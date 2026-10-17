extends "res://game/enemy/skeleton_enemy.gd"
class_name BoneThrowerScript
## Scene script `game.bone-thrower` (the bestiary's row 31, a thrower; docs/godot/BESTIARY.md "Bone
## Thrower"): a lanky hooded skeleton with a big bone, found only in the dungeons. It never chases.
##
## - **Eight ways** (owner, 2026-10-16: enemy shots fly along lines, four ways for most, eight for
##   the skeletons; game/enemy/four_way_aim.gd with `eight`): it throws only along the slime's row,
##   column or one of its diagonals.
## - **Its post:** it keeps to where it was placed and turns to the slime. To throw it sidesteps onto
##   one of those lines, `lineUpLeashPx` at most from its post, at `stepSpeed` (the reachable one
##   nearest to it; with none in reach it waits at the leash's edge and does not throw). When the
##   slime comes within `backOffRangePx` it also steps back along that line (`backOffPx`, within the
##   leash); with the slime away it walks back to its post.
## - **Armed** (the bone in its hand): it bats every blow away with its bone (a clink; a thrown thing
##   still hits it). With the slime engaged, lined up (within `lineTolerancePx`), in a clear line and
##   within `throwRangePx`, it throws every `throwEveryMs` (the first `firstThrowMs` after the slime
##   comes).
## - **Wind-up** (the tell, `windupMs`): it leans back with the bone behind its head and rattles, its
##   aim locked along the line at the start (a slime that steps off the line is missed); guarded.
## - **Out:** the bone (`projectile.bone`, game/scripts/bone.gd) spins out `boneRangePx` straight
##   along the line at `boneSpeed` and comes back along the same line to its hand like a boomerang,
##   hurting the slime on both legs (`projectile.damage`), stopped by walls. It stands still where it
##   threw, its hand empty: it is **open**.
## - **Catch** (`catchPoseMs`): the bone is back in its hand; armed again.
## - **Unarmed:** the Gulp stole its bone (`stolenRegrowMs`, 10 s: owner, 2026-10-16, question
##   124), or a wall broke it (`regrowMs`): it only rattles its jaw and shakes its fists (open), until
##   a new bone grows in its hand.
## - **The right tool:** close in while its bone is out (or after it was caught) and hit it (30
##   health); or catch the bone with the Gulp (Q) and throw it back at it.
## A stun in the wind-up cancels the throw. Beaten, it falls into a bone pile (skeleton_enemy.gd);
## a bone in flight then drops.
##
## Owner: enemy builder.

const BoneScript := preload("res://game/scripts/bone.gd")
const FourWayAim := preload("res://game/enemy/four_way_aim.gd")
## The skeletons are the eight-way kind of shooter (four_way_aim.gd `eight`).
const EIGHT_WAY := true

const PHASE_ARMED := "armed"
const PHASE_WINDUP := "windup"
const PHASE_OUT := "out"
const PHASE_CATCH := "catch"
const PHASE_UNARMED := "unarmed"
const FRAME_ARMED := 0
const FRAME_WINDUP := 1
const FRAME_THROWN := 2
const FRAME_UNARMED := 3
const CUE_WINDUP := &"GroundCreak"
const CUE_THROW := &"Dodge"
const CUE_CATCH := &"LashCatch"
const CUE_REGROW := &"DropPop"
const SPARKLE := &"loot-sparkle"
## The bone leaves this far along the aim from its centre.
const HAND_PX := 14.0
## Presentation: the breath, the wind-up's lean and rattle, the throw's lunge, the catch's squash,
## the unarmed jaw rattle.
const BREATH := 0.025
const BREATH_MS := 420.0
const WINDUP_LEAN_RAD := 0.12
const WINDUP_SHAKE_RAD := 0.03
const WINDUP_SHAKE_MS := 30.0
const THROW_SQUASH := Vector2(1.08, 0.94)
const CATCH_SQUASH := Vector2(0.94, 1.06)
const RATTLE_SHAKE_RAD := 0.06
const RATTLE_SHAKE_MS := 24.0
const RATTLE_BURST_MS := 260.0

var _aim: Vector2 = Vector2.RIGHT
var _next_throw_at: float = 0.0
var _unarmed_until: float = 0.0
var _rattle_at: float = 0.0
var _bone: BoneScript
var _sight_at: float = -INF
var _sight_ok: bool = false


func _ready() -> void:
	super()
	_arm(Services.now_ms())


func _step_skeleton(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	if not engaged:
		_next_throw_at = maxf(_next_throw_at, now + pattern("firstThrowMs", 700.0))
	match _phase:
		PHASE_ARMED:
			_keep_post(delta, slime, engaged)
			var breath := sin(now / BREATH_MS) * BREATH
			set_look(0.0, Vector2(1.0 - breath, 1.0 + breath))
			var line := FourWayAim.line_direction(centre, slime, pattern("lineTolerancePx", 10.0), EIGHT_WAY)
			if engaged and now >= _next_throw_at and line != Vector2.ZERO \
					and centre.distance_to(slime) <= pattern("throwRangePx", 220.0) and _sees(now, target):
				_aim = line
				body.velocity = Vector2.ZERO
				face_x(_aim.x)
				_transition(PHASE_WINDUP, now)
				set_frame(FRAME_WINDUP)
				_cue(CUE_WINDUP)
		PHASE_WINDUP:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("windupMs", 550.0)), 0.0, 1.0)
			var back := -WINDUP_LEAN_RAD * t * (1.0 if _aim.x >= 0.0 else -1.0)
			set_look(0.0, Vector2.ONE, back + sin(elapsed / WINDUP_SHAKE_MS) * WINDUP_SHAKE_RAD * t)
			if t >= 1.0:
				_throw(now)
		PHASE_OUT:
			# It waits where it threw, so the bone comes back along its line.
			body.velocity = Vector2.ZERO
			var lunge := clampf(elapsed / maxf(1.0, pattern("throwPoseMs", 220.0)), 0.0, 1.0)
			set_look(0.0, THROW_SQUASH.lerp(Vector2.ONE, lunge))
			if _bone == null or not is_instance_valid(_bone):
				_disarm(now)
		PHASE_CATCH:
			body.velocity = Vector2.ZERO
			set_look(0.0, CATCH_SQUASH)
			if elapsed >= pattern("catchPoseMs", 220.0):
				_arm(now)
				_next_throw_at = now + pattern("throwEveryMs", 1500.0)
		PHASE_UNARMED:
			_keep_post(delta, slime, engaged)
			var since := now - _rattle_at
			var shake := sin(since / RATTLE_SHAKE_MS) * RATTLE_SHAKE_RAD if since < RATTLE_BURST_MS else 0.0
			set_look(0.0, Vector2.ONE, shake)
			if since >= pattern("rattleEveryMs", 520.0):
				_rattle_at = now
				_cue(CUE_RATTLE)
			if now >= _unarmed_until:
				_arm(now)
				_next_throw_at = now + pattern("firstThrowMs", 700.0)
				_cue(CUE_REGROW)
				_puff(SPARKLE, centre)


## Faces the slime and sidesteps into its row or column within the leash round its post (stepping
## back along that line when the slime is close); with the slime away it walks back to its post.
func _keep_post(delta: float, slime: Vector2, engaged: bool) -> void:
	var centre := get_centre()
	var goal := _home
	if engaged:
		face_x(slime.x - centre.x)
		goal = _line_up_spot(centre, slime)
	if centre.distance_to(goal) > pattern("homeSlackPx", 4.0):
		body.velocity = _velocity_toward(goal, pattern("stepSpeed", 60.0), delta)
		if not engaged:
			face_x(body.velocity.x)
	else:
		body.velocity = Vector2.ZERO


## Where it stands to throw at the slime at `slime`: on one of the slime's eight lines (its row, its
## column or a diagonal), at the point of that line nearest its post; of those within
## `lineUpLeashPx` of its post, the one nearest to where it stands; with none in reach, the leash's
## edge toward the nearest line. Close to the slime the spot steps back along the line, `backOffPx`
## (when that stays within the leash).
func _line_up_spot(centre: Vector2, slime: Vector2) -> Vector2:
	var leash := pattern("lineUpLeashPx", 72.0)
	var best := Vector2.INF
	var nearest := Vector2.INF
	for direction: Vector2 in FourWayAim.directions(EIGHT_WAY):
		if direction.x < 0.0 or (direction.x == 0.0 and direction.y < 0.0):
			continue
		var spot := slime + direction * (_home - slime).dot(direction)
		if nearest == Vector2.INF or _home.distance_to(spot) < _home.distance_to(nearest):
			nearest = spot
		if _home.distance_to(spot) <= leash and (best == Vector2.INF or centre.distance_to(spot) < centre.distance_to(best)):
			best = spot
	if best == Vector2.INF:
		return _home + (nearest - _home).limit_length(leash)
	if slime.distance_to(best) < pattern("backOffRangePx", 96.0) and best != slime:
		var back := best + (best - slime).normalized() * pattern("backOffPx", 44.0)
		if _home.distance_to(back) <= leash:
			best = back
	return best


## True when nothing of the world stands between it and the slime (throttled).
func _sees(now: float, target: Dictionary) -> bool:
	if now - _sight_at < SIGHT_CHECK_MS:
		return _sight_ok
	_sight_at = now
	var world := Services.world()
	if world == null:
		_sight_ok = true
		return true
	var exclude: Array[RID] = [body.get_rid()]
	var player_body := target.get("body") as CharacterBody2D
	if player_body != null:
		exclude.append(player_body.get_rid())
	_sight_ok = world.line_of_sight(get_centre(), target.get("centre", get_centre()), exclude)
	return _sight_ok


func _throw(now: float) -> void:
	_transition(PHASE_OUT, now)
	set_frame(FRAME_THROWN)
	_cue(CUE_THROW)
	var config := _projectile_config()
	if config.is_empty():
		_disarm(now)
		return
	var root := EnemyProjectiles.fire({
		"source": self,
		"position": get_centre() + _aim * HAND_PX,
		"direction": _aim,
		"speed": pattern("boneSpeed", 230.0),
		"damage": float(config["damage"]),
		"knockback_strength": _attribute("knockbackStrength"),
		"projectile_id": str(config["projectile_id"]),
		"asset_id": str(config["asset_id"]),
		"stick_ms": 0.0,
	})
	var script := EnemyProjectiles.find_projectile_script(root) as BoneScript if root != null else null
	if script == null:
		_disarm(now)
		return
	script.lifetime_ms = pattern("boneLifeMs", 6000.0)
	script.setup(self, pattern("boneRangePx", 220.0), pattern("boneTurnShare", 0.3), pattern("boneCatchPx", 16.0))
	_bone = script


# --- the bone's calls (game/scripts/bone.gd) --------------------------------------------------------

## Where the bone comes back to (its old centre).
func hand_point() -> Vector2:
	if is_defeated() or is_pile():
		return Vector2.INF
	return get_centre()


## The bone is back in its hand.
func bone_back() -> void:
	_bone = null
	if _phase == PHASE_OUT:
		var now := Services.now_ms()
		_transition(PHASE_CATCH, now)
		set_frame(FRAME_ARMED)
		_cue(CUE_CATCH)


## The bone is gone (the Gulp stole it: `stolen`; a wall broke it): unarmed until a new one grows.
func bone_lost(stolen: bool = false) -> void:
	_bone = null
	if _phase == PHASE_OUT:
		_disarm(Services.now_ms(), stolen)


func is_armed() -> bool:
	return _phase == PHASE_ARMED or _phase == PHASE_WINDUP or _phase == PHASE_CATCH


func _arm(now: float) -> void:
	_transition(PHASE_ARMED, now)
	set_frame(FRAME_ARMED)
	set_look(0.0)


func _disarm(now: float, stolen: bool = false) -> void:
	_bone = null
	_transition(PHASE_UNARMED, now)
	set_frame(FRAME_UNARMED)
	_unarmed_until = now + (pattern("stolenRegrowMs", 10000.0) if stolen else pattern("regrowMs", 3500.0))
	_rattle_at = now


## A stun in the wind-up cancels the throw.
func _on_stunned(now: float, _delta: float) -> void:
	if _phase == PHASE_WINDUP:
		_arm(now)
		_next_throw_at = get_hit_stun_until() + pattern("throwEveryMs", 1500.0) * 0.5


## Armed, it bats blows away with its bone; a thrown thing still hits it.
func _skeleton_shields(request: Dictionary) -> bool:
	return (_phase == PHASE_ARMED or _phase == PHASE_WINDUP) and not has_tag(request, THROWN_TAG)


func _on_collapse(_now: float) -> void:
	if _bone != null and is_instance_valid(_bone):
		_bone.drop()
	_bone = null


func _on_stand_up(now: float) -> void:
	_arm(now)
	_next_throw_at = now + pattern("firstThrowMs", 700.0)


## Gone (respawned, the world left): a bone in flight finds no hand and drops by itself.
func _exit_tree() -> void:
	if _bone != null and is_instance_valid(_bone):
		_bone.detach()
	_bone = null
	super()
