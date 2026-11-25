extends "res://game/enemy/patterned_enemy.gd"
class_name ShardbackScript
## Scene script `game.shardback` (the bestiary's row 28, an armoured mini-boss; docs/godot/
## BESTIARY.md "Shardback"): an old tortoise under a shell of crystal that turns brittle in fire
## light.
##
## - **Walk:** it plods toward the slime at `walkSpeed` (home at `homeSpeed` while the slime is out
##   of its pen).
## - **Rear** (the tell, `rearMs`): within `slamRangePx` of the slime (at most every
##   `slamCooldownMs`) it rears up on its hind legs, its crystals glowing, and the ground it will
##   slam darkens (an ellipse `slamRx` x `slamRy` round its feet).
## - **Slam** (`slamPoseMs`): it comes down: the slime's feet in the ellipse take `slamDamage` with
##   `slamKnockback`; crystal shards fly and the ground shakes.
## - **Recover** (`recoverMs`): it stands, then walks again.
## - **The shell:** unlit, every hit is armor (the reaction profile: heavy, poise 4) and only
##   `shellDamageTaken` of it hurts (a clink, so it can still be worn down with patience: about 40
##   jabs). **Brittle** in fire light: inside a burning candle's or brazier's light (any light
##   source but the slime's own ember, game/enemy/light_sense.gd), and for `brittleLingerMs` after
##   it leaves it, or for `brittleMs` after a Lantern flame (a hit tagged `fire`) hits it, its shell
##   glows hot and cracks: hits take `brittleDamageTaken` (140 health: a Spear chain or two there).
## A stun (its poise broken) in the rear cancels the slam. The slam puts out a brazier marked
## `stomp_puts_out` within `slamPutOutScale` times its ellipse (candle.gd `put_out_near`).
## - **The runaway cart** (the rebuilt Crystal Mine's Den, 2026-11-25; game/crystal_mine/ram_cart.gd,
##   its hook `on_mechanism_hit(&"cart", cart)`, as the Brood Warden answers the ram): stopped against
##   it while its shell is brittle, the cart **shatters the shell** in one blow: `cartShatterDamage`
##   (more than it has: it falls, its defeat frame the shell burst into shards), a burst of crystal, a
##   hard shake. Against a cold shell it clangs off: `cartColdDamage`, a stagger of `cartStaggerMs`.
##   The Spear still works (brittle, `brittleDamageTaken`).
## - **Ammo from its slam:** each slam knocks a crystal chunk off the Den (a light liftable of
##   `slam_chunk_kind`, thrown like a pot) beside the slam ring, `slamChunkOffsetPx` from it, never on a
##   cart's rails or the lane from their end to its target (`slamChunkRailClearPx`); at most `slamChunksMax` lie at once (the oldest crumbles):
##   the knock target's throws never run out while the fight lasts.
##
## Owner: enemy builder.

const LightSense := preload("res://game/enemy/light_sense.gd")
const CandleScript := preload("res://game/world/fire/candle.gd")

const PHASE_WALK := "walk"
const PHASE_REAR := "rear"
const PHASE_SLAM := "slam"
const PHASE_RECOVER := "recover"
## Staggered by a cart that clanged off its cold shell.
const PHASE_STAGGER := "stagger"
const CART_KIND := &"cart"
const FRAME_WALK := 0
const FRAME_REAR := 1
const FRAME_SLAM := 2
const FIRE_TAG := "fire"
## Its own wind-up sound (Sound Picker round 13, 2026-11-21; it played the slime's SlamWindup before).
const CUE_REAR := &"ShardbackRear"
const CUE_SLAM := &"StomperSlam"
const CUE_CLINK := &"HitBlocked"
const CUE_CRACK := &"BreakGlass"
const CUE_BRITTLE := &"StatusBurn"
const SHARDS := &"stone-chip"
const DUST := &"dodge-dust"
const ZONE_NAME := "SlamZone"
## The slam's zone on the ground: a dark red, stronger than a shadow.
const ZONE_TINT := Color(0.32, 0.05, 0.02, 0.5)
## Presentation: the plod's bob, the brittle glow (a warm pulse on the shell's art).
const STEP_MS := 260.0
const STEP_BOB := 0.025
const BRITTLE_TINT := Color(1.35, 0.92, 0.72)
const BRITTLE_PULSE_MS := 140.0

var _brittle_until: float = 0.0
var _slam_ready_at: float = 0.0
var _slam_at: Vector2 = Vector2.ZERO
var _zone: GroundShadowLook
var _was_brittle: bool = false
## The liftable its slams knock loose (ThrowAmmo kinds: a crystal chunk).
@export var slam_chunk_kind: String = "crystal-cluster"
## The crystal chunks its slams knocked loose (liftables), oldest first.
var _chunks: Array[Node2D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	super()
	_transition(PHASE_WALK, Services.now_ms())
	set_frame(FRAME_WALK)


func _exit_tree() -> void:
	_clear_zone()
	super()


## True while fire light has its shell brittle.
func is_brittle() -> bool:
	return Services.now_ms() < _brittle_until


func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	_sense_light(now)
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	match _phase:
		PHASE_WALK:
			if engaged:
				body.velocity = _velocity_toward(slime, pattern("walkSpeed", 38.0), delta)
				face_x(slime.x - centre.x)
				if centre.distance_to(slime) <= pattern("slamRangePx", 96.0) and now >= _slam_ready_at:
					_rear(now)
			else:
				body.velocity = _velocity_home(pattern("homeSpeed", 50.0), delta)
				face_x(body.velocity.x)
			if show_walk(delta, FRAME_WALK):
				set_look(0.0)
			else:
				var bob := sin(now / STEP_MS * PI) * STEP_BOB if body.velocity.length() > WALK_SPEED_THRESHOLD else 0.0
				set_look(0.0, Vector2(1.0 + bob, 1.0 - bob))
		PHASE_REAR:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("rearMs", 800.0)), 0.0, 1.0)
			set_look(0.0, Vector2(1.0 - 0.04 * t, 1.0 + 0.06 * t))
			if _zone != null:
				_zone.strength = lerpf(0.2, 1.0, t)
			if t >= 1.0:
				_slam(now, target, engaged)
		PHASE_SLAM:
			body.velocity = Vector2.ZERO
			set_look(0.0, Vector2(1.08, 0.92))
			if elapsed >= pattern("slamPoseMs", 450.0):
				_transition(PHASE_RECOVER, now)
				set_frame(FRAME_WALK)
		PHASE_RECOVER:
			body.velocity = Vector2.ZERO
			set_look(0.0)
			if elapsed >= pattern("recoverMs", 900.0):
				_transition(PHASE_WALK, now)
		PHASE_STAGGER:
			body.velocity = Vector2.ZERO
			# rocked back on its legs, shaking off the clang
			var shake := sin(elapsed / 38.0) * (1.0 - clampf(elapsed / maxf(1.0, pattern("cartStaggerMs", 1100.0)), 0.0, 1.0))
			set_look(0.06 * shake, Vector2(1.0 - 0.03 * absf(shake), 1.0 + 0.03 * absf(shake)))
			if elapsed >= pattern("cartStaggerMs", 1100.0):
				_transition(PHASE_WALK, now)
				_slam_ready_at = now + pattern("slamCooldownMs", 1200.0)
	_brittle_look(now)


## Fire light on it keeps its shell brittle a little longer.
func _sense_light(now: float) -> void:
	if LightSense.light_at(get_tree(), get_centre(), pattern("lightPadPx", 26.0), true) > 0.0:
		_brittle_until = maxf(_brittle_until, now + pattern("brittleLingerMs", 1200.0))


func _rear(now: float) -> void:
	_transition(PHASE_REAR, now)
	set_frame(FRAME_REAR)
	_cue(CUE_REAR)
	_slam_at = feet()
	_clear_zone()
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent != null:
		_zone = GroundShadowLook.new()
		_zone.name = ZONE_NAME
		_zone.size = Vector2(pattern("slamRx", 88.0), pattern("slamRy", 60.0))
		_zone.tint = ZONE_TINT
		_zone.strength = 0.2
		parent.add_child(_zone)
		_zone.global_position = _slam_at


func _slam(now: float, target: Dictionary, engaged: bool) -> void:
	_transition(PHASE_SLAM, now)
	set_frame(FRAME_SLAM)
	_clear_zone()
	_slam_ready_at = now + pattern("slamPoseMs", 450.0) + pattern("recoverMs", 900.0) + pattern("slamCooldownMs", 1200.0)
	_cue(CUE_SLAM)
	_puff(SHARDS, _slam_at)
	_puff(DUST, _slam_at)
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("slamShakeMs", 200.0), pattern("slamShake", 0.006))
	# The slam puts out a brazier near it (`stomp_puts_out`), as the Crystal Colossus's stomps will
	# (the Crystal Mine's Shardback's Den rehearses his fight).
	var reach := pattern("slamPutOutScale", 1.8)
	CandleScript.put_out_near(get_tree(), _slam_at, Vector2(pattern("slamRx", 88.0), pattern("slamRy", 60.0)) * reach)
	_knock_chunk_loose()
	var slime_body := target.get("body") as Node2D
	if not engaged or slime_body == null:
		return
	var offset := slime_body.global_position - _slam_at
	var rx := maxf(1.0, pattern("slamRx", 88.0))
	var ry := maxf(1.0, pattern("slamRy", 60.0))
	if (offset.x / rx) * (offset.x / rx) + (offset.y / ry) * (offset.y / ry) <= 1.0:
		_route_hit_from(get_centre(), target, pattern("slamDamage", 40.0), pattern("slamKnockback", 320.0))


## The cart's blow (ram_cart.gd's hook, instead of damage): brittle, the shell shatters and it falls;
## cold, a clang and a stagger.
func on_mechanism_hit(kind: StringName, _source: Node) -> void:
	if kind != CART_KIND or is_defeated() or body == null:
		return
	var now := Services.now_ms()
	_clear_zone()
	var feel := Services.feel()
	if is_brittle():
		_cue(CUE_CRACK)
		_puff(SHARDS, get_centre())
		_puff(SHARDS, feet())
		_puff(DUST, feet())
		if feel != null:
			feel.shake(pattern("cartShatterShakeMs", 320.0), pattern("cartShatterShake", 0.012))
		var dealt := take_reaction_damage(pattern("cartShatterDamage", 9999.0))
		if feel != null and dealt > 0:
			feel.play_hit({"hit_stop_ms": 120.0, "trauma": 0.7, "kick_px": 0.0, "sparks": 18, "number": dealt,
				"number_big": true}, get_centre(), Vector2.UP)
		return
	_cue(CUE_CLINK)
	_puff(SHARDS, get_centre())
	if feel != null:
		feel.shake(pattern("cartClangShakeMs", 160.0), pattern("cartClangShake", 0.005))
	var cold := take_reaction_damage(pattern("cartColdDamage", 10.0))
	if feel != null and cold > 0:
		feel.play_hit({"hit_stop_ms": 60.0, "trauma": 0.3, "kick_px": 0.0, "sparks": 8, "number": cold}, get_centre(), Vector2.UP)
	if not is_defeated():
		_transition(PHASE_STAGGER, now)
		set_frame(FRAME_WALK)


## True while the cart's clang has it staggered.
func is_staggered() -> bool:
	return _phase == PHASE_STAGGER


## A slam knocks a crystal chunk loose beside its ring (a light liftable to throw), off every cart's
## rails; the oldest crumbles once `slamChunksMax` lie.
func _knock_chunk_loose() -> void:
	_chunks = _chunks.filter(func(c: Node2D) -> bool: return is_instance_valid(c) and c.is_inside_tree())
	var most := int(pattern("slamChunksMax", 3.0))
	if most <= 0:
		return
	var world := Services.world()
	if world == null:
		return
	_rng.seed = hash(Services.now_ms())
	var spot := Vector2.ZERO
	var found := false
	for i in 8:
		var angle := _rng.randf_range(0.0, TAU)
		spot = _slam_at + Vector2(cos(angle), sin(angle) * 0.7) * pattern("slamChunkOffsetPx", 110.0)
		if not _on_rails(spot) and world.elevation != null and int(world.elevation.call(&"walkable_level_at", spot)) == 0:
			found = true
			break
	if not found:
		return
	var chunk := ThrowAmmo.spawn_liftable(slam_chunk_kind, spot, {"pop": true, "weight": "light"})
	if chunk == null:
		return
	_chunks.append(chunk)
	while _chunks.size() > most:
		var old: Node2D = _chunks.pop_front()
		if is_instance_valid(old):
			_puff(DUST, old.global_position)
			old.queue_free()


## True within `slamChunkRailClearPx` of a runaway cart's line or of its run on to its knock target (the
## rails stay clear for the cart, the lane clear for the throw).
func _on_rails(at: Vector2) -> bool:
	var clear := pattern("slamChunkRailClearPx", 72.0)
	for cart: Node in get_tree().get_nodes_in_group(&"knock_mechanisms"):
		if not (cart is Node2D) or not (&"points" in cart):
			continue
		var points: PackedVector2Array = cart.get(&"points")
		var line: Array[Vector2] = []
		for p: Vector2 in points:
			line.append((cart as Node2D).to_global(p))
		# and on from the line's end to its knock target: the throw's lane
		var target: Node = cart.call(&"get_knock_target") if cart.has_method(&"get_knock_target") else null
		if target is Node2D and is_instance_valid(target) and not line.is_empty():
			line.append((target as Node2D).global_position)
		for i in range(line.size() - 1):
			if Geometry2D.get_closest_point_to_segment(at, line[i], line[i + 1]).distance_to(at) < clear:
				return true
	return false


func _brittle_look(now: float) -> void:
	var brittle := now < _brittle_until
	if brittle and not _was_brittle:
		_cue(CUE_BRITTLE)
	_was_brittle = brittle
	if pose == null:
		return
	if brittle:
		var pulse := 0.5 + 0.5 * sin(now / BRITTLE_PULSE_MS)
		pose.modulate = Color.WHITE.lerp(BRITTLE_TINT, 0.7 + 0.3 * pulse)
	else:
		pose.modulate = Color.WHITE


func _clear_zone() -> void:
	if _zone != null and is_instance_valid(_zone):
		_zone.queue_free()
	_zone = null


## Its shell: a share of each hit unlit, more than the hit brittle.
func mitigate_damage(input: Dictionary) -> float:
	var share := pattern("brittleDamageTaken", 1.6) if is_brittle() else pattern("shellDamageTaken", 0.3)
	return super(input) * share


## A flame on its shell makes it brittle; a hit clinks on hard crystal and cracks brittle crystal.
func commit_damage(commit: Dictionary) -> void:
	var request: Dictionary = commit.get("request", {})
	var brittle := is_brittle()
	if has_tag(request, FIRE_TAG):
		_brittle_until = maxf(_brittle_until, Services.now_ms() + pattern("brittleMs", 4000.0))
	super(commit)
	if is_defeated():
		return
	var result: Dictionary = commit.get("result", {})
	if int(result.get("actual_damage", 0)) > 0 or brittle:
		_cue(CUE_CRACK if brittle else CUE_CLINK)
		if brittle:
			_puff(SHARDS, get_centre())


## A stun (its poise broken) in the rear cancels the slam.
func _on_stunned(now: float, _delta: float) -> void:
	if _phase == PHASE_REAR:
		_clear_zone()
		_transition(PHASE_RECOVER, now)
		set_frame(FRAME_WALK)
		_slam_ready_at = now + pattern("slamCooldownMs", 1200.0)
	_brittle_look(now)


func _defeat() -> void:
	if is_defeated():
		return
	_clear_zone()
	_cue(CUE_CRACK)
	_puff(SHARDS, get_centre())
	if pose != null:
		pose.modulate = Color.WHITE
	super()
