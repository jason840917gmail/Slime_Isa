extends "res://game/enemy/patterned_enemy.gd"
class_name CrystalColossusScript
## Scene script `game.crystal-colossus` (`character.crystal-colossus`; roadmap 12.4; Chapter 3's
## boss, docs/godot/DUNGEONS.md "The Crystal Mine (built)"; decisions archive questions 59, 69 and
## 94): a hulking golem of icy blue crystal grown round Pearl 3, part beast. His arena
## (game/crystal_mine/colossus_arena.gd) rings him with four braziers.
##
## - **Walk:** he plods at the slime (`walkSpeed`); touching him hurts (`contactDamage`).
## - **Stomp:** within `stompRangePx` of the slime, or every `stompEveryMs` anyway, he lifts a crystal
##   foot (the tell, `raiseMs`) while a dark ring grows round his feet, then stomps: the slime's feet
##   in the ring (`stompRx` x `stompRy`) take `stompDamage`; the screen shakes; and the stomp puts out
##   the lit brazier nearest to him, one at a time (candle.gd `put_out_near`, the braziers'
##   `stomp_puts_out`: the Shardback's Den rehearsed it).
## - **The weak spot:** only while all four braziers burn (the arena calls `set_exposed`), a plate of
##   his armour cracks open at a random place: his front, his back, his left or his right side (a
##   hot glow there). He reels for `reelMs` (an opening), then fights on. Only the Spear hurts him,
##   only there: a Spear hit from the slime standing on that side of him lands; every other hit, and
##   every hit while the braziers do not all burn, clinks off his crystal.
## - **The climb:** after `stompsPerClimb` stomps he leaps onto the north wall of his arena at the
##   climb spot nearest the slime (the arena's `climb_spots`) and clings there (not solid; his pose up
##   the face), throwing a Crystal Mite down every `throwEveryMs` (`character.crystal-mite`: it drops
##   in near the slime behind its shadow, and on a slime climbing above its spot; `mitesPerClimb`, at
##   most `maxMites` alive). After `climbMs` he leaps down where the slime stands (kept inside his
##   arena), a ring marking the spot before he lands: the landing is a stomp and puts out
##   `landPutsOut` braziers.
## - **His claws: the Feral skin's exam** (the Pearl mid-dungeon plan, 2026-10-17): roots run up the
##   wall beside each climb spot, and a slime climbing them strikes his gripping claws with the
##   Spear (the strike while clinging, player.gd `_climb_strike`): while he clings his hurtbox rides
##   up the face with his pose, and only a Spear hit from a climbing slime reaches it. `clawHits`
##   such hits and he loses his grip: he crashes down `fallDropPx` from the wall over `fallMs` with
##   no landing stomp (no brazier goes out) and lies stunned `fallStunMs`, his back cracked open: any
##   Spear hit lands while he lies there. Then he gets up and fights on (his stomps counted afresh).
## - **His second phase** (below `phaseTwoShare` of his health; not the Pearl's rage, EnragedLook):
##   faster stomps, more mites, two braziers a landing.
##
## Numbers: `crystal-colossus` in game/data/enemy-types.json.
##
## Owner: dungeons (the Crystal Mine).

const CandleScript := preload("res://game/world/fire/candle.gd")
const FireFx := preload("res://game/world/fire/fire_fx.gd")

const PHASE_WAIT := "wait"
const PHASE_WALK := "walk"
const PHASE_RAISE := "raise"
const PHASE_STOMP := "stomp"
const PHASE_RECOVER := "recover"
const PHASE_REEL := "reel"
const PHASE_LEAP_UP := "leap-up"
const PHASE_CLING := "cling"
const PHASE_LEAP_DOWN := "leap-down"
## His claws struck loose: the crash down from the wall, then the stun.
const PHASE_FALL := "fall"
const PHASE_STUNNED := "stunned"
const FRAME_STAND := 0
const FRAME_RAISE := 1
const FRAME_STOMP := 2
const FRAME_CRACKED := 3
const FRAME_CLIMB := 4
const FRAME_THROW := 5
const FRAME_LAND := 6
const FRAME_DEFEATED := 7
## Sprawled face down after his fall from the wall, his back cracked open (the sheet's ninth pose;
## FRAME_DEFEATED's heap on an older sheet of eight).
const FRAME_STUNNED := 8
## Where his claws' crack shows on his clinging pose, and his open back on the stunned one (art
## units are world units here).
const CLAW_GLOW_AT := Vector2(0, -170)
const STUN_GLOW_AT := Vector2(0, -88)
const CUE_GRIP_LOST := &"StomperSlam"
const MITE_SCENE := "character.crystal-mite"
## Its own wind-up sound (Sound Picker round 13, 2026-11-21; it played the slime's SlamWindup before).
const CUE_RAISE := &"ColossusRaise"
const CUE_STOMP := &"StomperSlam"
const CUE_CLINK := &"HitBlocked"
const CUE_CRACK := &"BreakGlass"
const CUE_ROAR := &"SlamImpact"
const SHARDS := &"stone-chip"
const DUST := &"dodge-dust"
const ZONE_NAME := "StompZone"
const ZONE_TINT := Color(0.32, 0.05, 0.02, 0.5)
const LAND_TINT := Color(0.12, 0.08, 0.2, 0.55)
## The weak spot's sides (from his centre toward where the slime must stand), and where its glow
## shows on his pose (art units are world units here).
const SIDES := {
	"front": [Vector2(0, 1), Vector2(0, -78)],
	"back": [Vector2(0, -1), Vector2(0, -150)],
	"left": [Vector2(-1, 0), Vector2(-58, -108)],
	"right": [Vector2(1, 0), Vector2(58, -108)],
}
const SIDE_ORDER: Array[String] = ["front", "back", "left", "right"]
const WEAK_TINT := Color(1.0, 0.55, 0.18, 0.9)
const STEP_MS := 300.0
const STEP_BOB := 0.02

## The arena (game/crystal_mine/colossus_arena.gd sets it): the spots on the north wall's foot he
## climbs from (old centres).
var climb_spots: Array[Vector2] = []

var _exposed := false
var _weak_side := "front"
var _weak_glow: Sprite2D
var _stomp_ready_at := 0.0
var _stomps := 0
var _zone: GroundShadowLook
var _air_from := Vector2.ZERO
var _air_to := Vector2.ZERO
var _cling_at := Vector2.ZERO
var _next_throw_at := 0.0
var _thrown := 0
var _mites: Array[Node] = []
var _mask := 0
var _rng := RandomNumberGenerator.new()
## His claws: Spear hits from a climbing slime this climb, and the last hit's activation (one count a
## strike).
var _claw_hits := 0
var _claw_activation: Variant = null
## His hurtbox's authored position (it rides up the face with his pose while he clings).
var _area_home := Vector2.ZERO


func _ready() -> void:
	super()
	_rng.seed = 7311
	if damage_area != null:
		_area_home = damage_area.position
	_transition(PHASE_WAIT, Services.now_ms())
	set_frame(FRAME_STAND)
	if pose != null:
		_weak_glow = Sprite2D.new()
		_weak_glow.name = "WeakSpot"
		_weak_glow.texture = FireFx.glow_texture()
		_weak_glow.material = FireFx.additive()
		_weak_glow.modulate = WEAK_TINT
		_weak_glow.scale = Vector2.ONE * 0.7
		_weak_glow.visible = false
		pose.add_child(_weak_glow)


func _exit_tree() -> void:
	_clear_zone()
	super()


# --- the arena's hooks -------------------------------------------------------------------------------

## The weak spot opens (all four braziers burn) or shuts.
func set_exposed(on: bool) -> void:
	if on == _exposed or is_defeated():
		return
	_exposed = on
	if on:
		_weak_side = SIDE_ORDER[_rng.randi_range(0, SIDE_ORDER.size() - 1)]
		_cue(CUE_CRACK)
		_puff(SHARDS, get_centre())
		if _phase in [PHASE_WALK, PHASE_RECOVER]:
			_transition(PHASE_REEL, Services.now_ms())
			set_frame(FRAME_CRACKED)
	_show_weak_spot()


func is_exposed() -> bool:
	return _exposed


## Where the weak spot is ("front", "back", "left", "right").
func weak_side() -> String:
	return _weak_side


## True while he clings to the wall (out of reach).
func is_on_wall() -> bool:
	return _phase in [PHASE_LEAP_UP, PHASE_CLING]


## Wakes him (the arena, when the slime is in).
func wake() -> void:
	if _phase == PHASE_WAIT:
		_transition(PHASE_WALK, Services.now_ms())
		_cue(CUE_ROAR)
		var feel := Services.feel()
		if feel != null:
			feel.shake(500.0, 0.012)
		_stomp_ready_at = Services.now_ms() + pattern("firstStompMs", 1800.0)


## Takes away every mite he threw (the fight is reset).
func clear_mites() -> void:
	for mite in _mites:
		if is_instance_valid(mite) and is_instance_valid(mite.get_parent()):
			(mite.get_parent() as Node).queue_free()
	_mites.clear()


func live_mites() -> int:
	_mites = _mites.filter(func(m: Node) -> bool: return is_instance_valid(m) and not m.is_queued_for_deletion() and not bool(m.call(&"is_defeated")))
	return _mites.size()


# --- the pattern -----------------------------------------------------------------------------------

func _step_pattern(now: float, delta: float, target: Dictionary, engaged: bool) -> void:
	var elapsed := _elapsed(now)
	var centre := get_centre()
	var slime: Vector2 = target.get("centre", centre)
	match _phase:
		PHASE_WAIT:
			body.velocity = Vector2.ZERO
			set_look(0.0)
		PHASE_WALK:
			if engaged:
				body.velocity = _velocity_toward(slime, pattern("walkSpeed", 34.0) * _rage(1.25), delta)
				face_x(slime.x - centre.x)
				_contact(target, pattern("contactDamage", 14.0), pattern("contactKnockback", 260.0), pattern("contactReachPx", 70.0))
				if now >= _stomp_ready_at and (centre.distance_to(slime) <= pattern("stompRangePx", 120.0) or elapsed >= pattern("stompEveryMs", 2600.0) / _rage(1.4)):
					_raise(now)
			else:
				body.velocity = Vector2.ZERO
			var bob := sin(now / STEP_MS * PI) * STEP_BOB if body.velocity.length() > WALK_SPEED_THRESHOLD else 0.0
			set_look(0.0, Vector2(1.0 + bob, 1.0 - bob))
		PHASE_RAISE:
			body.velocity = Vector2.ZERO
			var t := clampf(elapsed / maxf(1.0, pattern("raiseMs", 650.0)), 0.0, 1.0)
			set_look(6.0 * t, Vector2(1.0 - 0.03 * t, 1.0 + 0.05 * t))
			if _zone != null:
				_zone.strength = lerpf(0.2, 1.0, t)
			if t >= 1.0:
				_stomp(now, target, engaged, int(pattern("stompPutsOut", 1.0)))
		PHASE_STOMP:
			body.velocity = Vector2.ZERO
			set_look(0.0, Vector2(1.06, 0.94))
			if elapsed >= pattern("stompPoseMs", 420.0):
				_transition(PHASE_RECOVER, now)
				set_frame(FRAME_CRACKED if _exposed else FRAME_STAND)
		PHASE_RECOVER:
			body.velocity = Vector2.ZERO
			set_look(0.0)
			if elapsed >= pattern("recoverMs", 600.0):
				if _stomps >= int(pattern("stompsPerClimb", 3.0)) and not climb_spots.is_empty():
					_leap_up(now, slime)
				else:
					_transition(PHASE_WALK, now)
					set_frame(FRAME_CRACKED if _exposed else FRAME_STAND)
		PHASE_REEL:
			body.velocity = Vector2.ZERO
			set_look(0.0, Vector2(1.0, 1.0), sin(elapsed / 90.0) * 0.03)
			if elapsed >= pattern("reelMs", 1800.0):
				_transition(PHASE_WALK, now)
				set_frame(FRAME_CRACKED if _exposed else FRAME_STAND)
				_stomp_ready_at = now + pattern("afterReelStompMs", 900.0)
		PHASE_LEAP_UP:
			_fly(elapsed, pattern("leapUpMs", 700.0), 0.0, pattern("wallLiftPx", 120.0))
			if elapsed >= pattern("leapUpMs", 700.0):
				_transition(PHASE_CLING, now)
				set_frame(FRAME_CLIMB)
				_next_throw_at = now + pattern("firstThrowMs", 900.0)
				_thrown = 0
				_grip(true)
		PHASE_CLING:
			body.velocity = Vector2.ZERO
			var sway := sin(elapsed / 260.0) * 3.0
			set_look(pattern("wallLiftPx", 120.0) + sway)
			if now >= _next_throw_at and _thrown < int(pattern("mitesPerClimb", 2.0) * _rage(1.5)) and live_mites() < int(pattern("maxMites", 4.0)):
				_throw_mite(now, target)
			elif now >= _next_throw_at - pattern("throwEveryMs", 1300.0) + pattern("throwPoseMs", 380.0):
				set_frame(FRAME_CLIMB)
			if elapsed >= pattern("climbMs", 5200.0):
				_leap_down(now, slime)
		PHASE_LEAP_DOWN:
			var air := pattern("leapDownMs", 900.0)
			_fly(elapsed, air, pattern("wallLiftPx", 120.0), 0.0)
			if _zone != null:
				_zone.strength = clampf(elapsed / air, 0.2, 1.0)
			if elapsed >= air:
				_land(now, target, engaged)
		PHASE_FALL:
			# Off the wall, away from it, falling fast (no arc): no ring, no stomp.
			var fall := maxf(1.0, pattern("fallMs", 450.0))
			var t := clampf(elapsed / fall, 0.0, 1.0)
			body.velocity = Vector2.ZERO
			body.global_position = _air_from.lerp(_air_to, t)
			set_look(lerpf(pattern("wallLiftPx", 120.0), 0.0, t * t), Vector2.ONE, t * 0.25)
			if t >= 1.0:
				_crash(now)
		PHASE_STUNNED:
			body.velocity = Vector2.ZERO
			var wobble := sin(elapsed / 70.0) * 0.02 * (1.0 - clampf(elapsed / maxf(1.0, pattern("fallStunMs", 2500.0)), 0.0, 1.0))
			set_look(0.0, Vector2(1.0 + wobble, 1.0 - wobble))
			if elapsed >= pattern("fallStunMs", 2500.0):
				_get_up(now)


## His second phase: below `phaseTwoShare` of his health he stomps and throws faster (`factor`).
func _rage(factor: float) -> float:
	var state := get_damage_state()
	var share := float(state.get("hp", 1.0)) / maxf(1.0, float(state.get("max_hp", 1.0)))
	return factor if share <= pattern("phaseTwoShare", 0.5) else 1.0


## True in his second phase (below `phaseTwoShare` of his health).
func is_phase_two() -> bool:
	return _rage(2.0) > 1.0


## True while he lies stunned after his claws lost their grip (his back open to the Spear).
func is_stunned() -> bool:
	return _phase == PHASE_STUNNED


## Spear hits on his claws so far this climb.
func claw_hits() -> int:
	return _claw_hits


## His grip on the wall (`on`: he clings; his hurtbox rides up the face with his pose, so a slime
## climbing beside him reaches his claws) or not (his hurtbox back at his body, as authored).
func _grip(on: bool) -> void:
	if damage_area == null:
		return
	if on:
		_claw_hits = 0
		_claw_activation = null
		damage_area.position = _area_home - Vector2(0.0, pattern("wallLiftPx", 120.0))
		set_hurtbox(true)
	else:
		damage_area.position = _area_home


## A Spear hit from a climbing slime on his gripping claws: a crack; `clawHits` of them and he lets go.
func _claw_hit(request: Dictionary) -> void:
	var activation: Variant = request.get("activation_id")
	if activation != null and activation == _claw_activation:
		return
	_claw_activation = activation
	_claw_hits += 1
	var claws := get_centre() + CLAW_GLOW_AT + Vector2(0.0, 120.0 - pattern("wallLiftPx", 120.0))
	_cue(CUE_CRACK)
	_puff(SHARDS, claws)
	var feel := Services.feel()
	if feel != null:
		feel.shake(160.0, 0.006)
	if _claw_hits >= int(pattern("clawHits", 3.0)):
		_lose_grip(Services.now_ms())


## His claws lose their grip: he crashes down off the wall, `fallDropPx` out from it.
func _lose_grip(now: float) -> void:
	_grip(false)
	_clear_zone()
	var landing := _inside_arena(feet() + Vector2(0.0, pattern("fallDropPx", 70.0)))
	_begin_air(landing)
	_transition(PHASE_FALL, now)
	set_frame(FRAME_LAND)
	_cue(CUE_ROAR)


## The crash at the wall's foot: a hard shake and dust, no stomp ring and no brazier out; then the stun.
func _crash(now: float) -> void:
	_end_air()
	_stomps = 0
	_cue(CUE_GRIP_LOST)
	_puff(DUST, feet())
	_puff(SHARDS, get_centre())
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("crashShakeMs", 420.0), pattern("crashShake", 0.016))
	_transition(PHASE_STUNNED, now)
	set_frame(_stunned_frame())
	_show_weak_spot()


## Up again after the stun: he fights on, his stomps counted afresh.
func _get_up(now: float) -> void:
	_transition(PHASE_WALK, now)
	set_frame(FRAME_CRACKED if _exposed else FRAME_STAND)
	_stomp_ready_at = now + pattern("afterReelStompMs", 900.0)
	_show_weak_spot()


func _stunned_frame() -> int:
	var visual_sprite := visual as Sprite2D
	return FRAME_STUNNED if visual_sprite != null and visual_sprite.hframes > FRAME_STUNNED else FRAME_DEFEATED


## `point` (feet) kept `arenaInsetPx` inside his arena (the point itself without one).
func _inside_arena(point: Vector2) -> Vector2:
	if _arena.is_empty():
		return point
	var inset := pattern("arenaInsetPx", 48.0)
	var x := float(_arena.get("x", point.x))
	var y := float(_arena.get("y", point.y))
	var w := float(_arena.get("w", 0.0))
	var h := float(_arena.get("h", 0.0))
	return Vector2(clampf(point.x, x + inset, x + w - inset), clampf(point.y, y + inset, y + h - inset))


func _raise(now: float) -> void:
	_transition(PHASE_RAISE, now)
	set_frame(FRAME_RAISE)
	_cue(CUE_RAISE)
	_show_zone(feet(), Vector2(pattern("stompRx", 116.0), pattern("stompRy", 78.0)), ZONE_TINT)


func _stomp(now: float, target: Dictionary, engaged: bool, put_out: int) -> void:
	_transition(PHASE_STOMP, now)
	set_frame(FRAME_STOMP)
	_clear_zone()
	_stomps += 1
	_stomp_ready_at = now + pattern("stompPoseMs", 420.0) + pattern("recoverMs", 600.0) + pattern("stompCooldownMs", 1400.0) / _rage(1.4)
	_cue(CUE_STOMP)
	_puff(SHARDS, feet())
	_puff(DUST, feet())
	var feel := Services.feel()
	if feel != null:
		feel.shake(pattern("stompShakeMs", 320.0), pattern("stompShake", 0.012))
	for i in maxi(0, put_out):
		CandleScript.put_out_near(get_tree(), feet(), Vector2(4000, 4000), true)
	var slime_body := target.get("body") as Node2D
	if not engaged or slime_body == null:
		return
	var offset := slime_body.global_position - feet()
	var rx := maxf(1.0, pattern("stompRx", 116.0))
	var ry := maxf(1.0, pattern("stompRy", 78.0))
	if (offset.x / rx) * (offset.x / rx) + (offset.y / ry) * (offset.y / ry) <= 1.0:
		_route_hit_from(get_centre(), target, pattern("stompDamage", 24.0), pattern("stompKnockback", 340.0))


## Onto the wall at the climb spot nearest the slime (`slime`, its old centre).
func _leap_up(now: float, slime: Vector2) -> void:
	_stomps = 0
	_clear_zone()
	var best := climb_spots[0]
	for spot in climb_spots:
		if absf(spot.x - slime.x) < absf(best.x - slime.x):
			best = spot
	_cling_at = best
	_begin_air(_feet_for(_cling_at))
	_transition(PHASE_LEAP_UP, now)
	set_frame(FRAME_LAND)
	_cue(CUE_RAISE)


func _leap_down(now: float, slime: Vector2) -> void:
	# Where the slime stands, kept on his arena's floor (a slime up the wall is not under him).
	var landing := _inside_arena(_feet_for(slime))
	_begin_air(landing)
	_transition(PHASE_LEAP_DOWN, now)
	set_frame(FRAME_LAND)
	_show_zone(landing, Vector2(pattern("stompRx", 116.0), pattern("stompRy", 78.0)), LAND_TINT)


func _land(now: float, target: Dictionary, engaged: bool) -> void:
	_end_air()
	set_look(0.0)
	_stomp(now, target, engaged, int(pattern("landPutsOut", 1.0) * _rage(2.0)))
	set_frame(FRAME_LAND)


## Airborne: not solid, no hurtbox, nothing collides; the body is moved straight there.
func _begin_air(to_feet: Vector2) -> void:
	_grip(false)
	_air_from = body.global_position
	_air_to = to_feet
	set_solid(false)
	set_hurtbox(false)
	# From the wall (leap down, a fall) the mask is already off: keep the one he walks with.
	if body.collision_mask != 0:
		_mask = body.collision_mask
	body.collision_mask = 0


func _end_air() -> void:
	body.collision_mask = _mask if _mask != 0 else body.collision_mask
	set_solid(true)
	set_hurtbox(true)


## Through the air from `_air_from` to `_air_to` (feet), the pose lifted from `from_lift` to
## `to_lift` with an arc over the way.
func _fly(elapsed: float, air_ms: float, from_lift: float, to_lift: float) -> void:
	var t := clampf(elapsed / maxf(1.0, air_ms), 0.0, 1.0)
	body.velocity = Vector2.ZERO
	body.global_position = _air_from.lerp(_air_to, t)
	set_look(lerpf(from_lift, to_lift, t) + sin(t * PI) * pattern("leapArcPx", 110.0))


func _throw_mite(now: float, target: Dictionary) -> void:
	set_frame(FRAME_THROW)
	_next_throw_at = now + pattern("throwEveryMs", 1300.0)
	_thrown += 1
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	var root := world.instantiate_scene(MITE_SCENE) as Node2D if world != null else null
	if root == null or parent == null:
		return
	var mite: Node = null
	for child: Node in root.get_children():
		if child.has_method(&"configure_arena"):
			mite = child
			break
	if mite == null:
		root.free()
		return
	parent.add_child(root)
	var slime: Vector2 = target.get("centre", get_centre())
	FeetAnchor.place_at_phaser_position(root, slime)
	var no_zones: Array[Dictionary] = []
	mite.call(&"configure_navigation", {}, no_zones)
	mite.call(&"configure_arena", get_arena())
	_mites.append(mite)


func _feet_for(centre: Vector2) -> Vector2:
	return centre - (get_centre() - feet())


func _show_zone(at: Vector2, size: Vector2, tint: Color) -> void:
	_clear_zone()
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return
	_zone = GroundShadowLook.new()
	_zone.name = ZONE_NAME
	_zone.size = size
	_zone.tint = tint
	_zone.strength = 0.2
	parent.add_child(_zone)
	_zone.global_position = at


func _clear_zone() -> void:
	if _zone != null and is_instance_valid(_zone):
		_zone.queue_free()
	_zone = null


func _show_weak_spot() -> void:
	if _weak_glow == null:
		return
	if _phase == PHASE_STUNNED and not is_defeated():
		# His back cracked open as he lies there.
		_weak_glow.visible = true
		_weak_glow.position = STUN_GLOW_AT
		return
	_weak_glow.visible = _exposed and not is_defeated()
	var side: Array = SIDES.get(_weak_side, SIDES["front"])
	_weak_glow.position = side[1]


func _process(delta: float) -> void:
	if _weak_glow != null and _weak_glow.visible:
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 110.0)
		_weak_glow.scale = Vector2.ONE * lerpf(0.55, 0.85, pulse)


# --- hits ------------------------------------------------------------------------------------------

## Every hit clinks off his crystal but the Spear's on the open weak spot from its side, the Spear's
## on his back while he lies stunned, and (counted, not hurting him) the Spear's from a climbing
## slime on his claws while he clings.
func _shields(request: Dictionary) -> bool:
	if _phase == PHASE_CLING:
		if has_tag(request, SPEAR_TAG) and _from_climber(request):
			_claw_hit(request)
		return true
	if _phase == PHASE_STUNNED:
		return not has_tag(request, SPEAR_TAG)
	if not _exposed or is_on_wall() or _phase in [PHASE_LEAP_DOWN, PHASE_FALL]:
		return true
	if not has_tag(request, SPEAR_TAG):
		return true
	return not _from_weak_side(request)


## True when the hit's source is the slime climbing a wall (the Feral skin).
static func _from_climber(request: Dictionary) -> bool:
	var source: Variant = request.get("source")
	return is_instance_valid(source) and source is Node and (source as Node).has_method(&"is_climbing") \
		and bool((source as Node).call(&"is_climbing"))


func _from_weak_side(request: Dictionary) -> bool:
	var source: Variant = request.get("source")
	var from := Vector2.INF
	if is_instance_valid(source) and source is Node and (source as Node).has_method(&"get_centre"):
		from = (source as Node).call(&"get_centre")
	else:
		var impact: Dictionary = request.get("impact", {})
		var knock: Vector2 = impact.get("knock", Vector2.ZERO)
		if knock != Vector2.ZERO:
			from = get_centre() - knock * 60.0
	if from == Vector2.INF:
		return false
	var side: Array = SIDES.get(_weak_side, SIDES["front"])
	var toward := (from - get_centre()).normalized()
	return toward.dot(side[0]) >= pattern("weakSideDot", 0.45)


func commit_damage(commit: Dictionary) -> void:
	super(commit)
	if is_defeated():
		return
	var result: Dictionary = commit.get("result", {})
	if int(result.get("actual_damage", 0)) > 0:
		_cue(CUE_CRACK)
		_puff(SHARDS, get_centre())


func _defeat() -> void:
	if is_defeated():
		return
	_clear_zone()
	_exposed = false
	_grip(false)
	if _weak_glow != null:
		_weak_glow.visible = false
	_end_air()
	clear_mites()
	_cue(CUE_CRACK)
	_puff(SHARDS, get_centre())
	var feel := Services.feel()
	if feel != null:
		feel.shake(700.0, 0.016)
	super()
