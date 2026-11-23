extends "res://game/enemy/patterned_enemy.gd"
class_name JellyBouncerScript
## Scene script `game.jelly-bouncer` (the bestiary's row 39; docs/godot/BESTIARY.md "39. Jelly
## Bouncer"; the owner, 2026-11-22): an electric jelly that never attacks. He wanders slowly in soft
## bounces, and now and then he lets out a zap: whoever is close is electrocuted (game/feel/
## shock_look.gd: frozen, flickering, its bones showing).
##
## - **Wander:** a hop of `hopPx` over `hopMs` every `hopEveryMs`, toward a spot of his wander area
##   (his pen; else his placed enemy's wander area; else `wanderRadiusPx` round where he started),
##   a new spot once he is there or a hop got nowhere.
## - **Charge** (the tell, `chargeMs`), every `zapEveryMinMs` to `zapEveryMaxMs` at random: he stops,
##   swells and blazes, and the ring of his reach flickers on the ground.
## - **Zap** (`zapMs`): everything within `zapRadiusPx` of his feet on his level (x `waterReachScale`
##   while he stands in shallow water) is shocked: the slime (`zapDamage`, frozen for `shockMs` and
##   then kicked `shockKnockPx` away) and other enemies too (`zapEnemyDamage`, dazed `zapEnemyDazeMs`;
##   not another jelly, not a flyer). Bolts reach each of them and the ring's edge. Then he rests
##   (`afterMs`) and wanders on.
## - **Touching him** does nothing (owner: he zaps only in his random zap).
## - **The shapes** (the Spear, the Axe, the Hammer: a hit tagged `weapon`) do him no harm and shock
##   the slime that struck (the same shock as the zap, at most every `weaponShockCooldownMs`).
## - **A thrown thing** bounces off him back at the slime (game/throw/bounced_throw.gd: `bounceSpeed`,
##   `bounceRangePx`, `bounceArcPx`; it hits for `bounceDamage<Weight>`), and the mouth can catch it
##   on the way. A **thrown enemy** is shocked where it lands by him (`catch_thrown`, within
##   `thrownEnemyReachPx`): it bounces off him and lies dazed, its bones flickering.
## - **What kills him:** arrows (`arrowHits` of them, whatever an arrow's damage) and the Goo Bomb's
##   blast (one, in any phase). The Lantern's flame does nothing (he is jelly); the Roll, the Lash,
##   the Slam and the rest clink.
##
## Owner: enemy builder.

const ShockLook := preload("res://game/feel/shock_look.gd")
const ZapLook := preload("res://game/enemy/zap_look.gd")
const BouncedThrow := preload("res://game/throw/bounced_throw.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const WaterWake := preload("res://game/world/water_wake.gd")
const EnemyHitMotion := preload("res://game/feel/enemy_hit_motion.gd")

const PHASE_WANDER := "wander"
const PHASE_CHARGE := "charge"
const PHASE_ZAP := "zap"
const PHASE_AFTER := "after"
## The sheet's frames (scripts/characters/pack-bestiary-enemies.py "jelly-bouncer").
const FRAME_REST := 0
const FRAME_CHARGE := 1
const FRAME_ZAP := 2
const FRAME_DOWN := 3
## The hits that do what to him (the request's `weapon_tags`).
const WEAPON_TAG := "weapon"
const ARROW_TAG := "arrow"
const BLAST_TAG := "blast"
## The refusals: a shape's hit he conducts back (no clink: the shock is the answer) and a thrown thing
## that bounces off (thrown_object.gd sends it back before it strikes; this is for one that struck
## him anyway, as a thrown enemy does).
const REASON_CONDUCTS := "conducts"
const REASON_BOUNCES := "bounces"
## The thrown enemy kind (game/throw/gulpable_enemy.gd): food for the eaters, a shock here.
const EATERS_GROUP := &"enemy_eaters"
## Borrowed cues until a Sound Picker round gives him his own.
const CUE_CHARGE := &"PrismCharge"
const CUE_ZAP := &"SlamImpact"
const CUE_SHOCK := &"StatusBurn"
const CUE_BOUNCE := &"StatusBouncy"
const CUE_POP := &"BubblePop"
const SPARKS := &"hit-spark"
const SPLASH := &"slime-splash"
const SPARK_TINT := Color(1.0, 0.95, 0.5)
const JELLY_TINT := Color(0.55, 0.92, 1.0)
## Presentation: the rest's wobble, a hop's stretch and its landing squash, the charge's swell and
## quiver, a hit's wobble, the zap's flash, bolts out to the ring.
const WOBBLE_MS := 260.0
const WOBBLE := 0.035
const HOP_STRETCH := Vector2(0.9, 1.12)
const LAND_SQUASH := Vector2(1.16, 0.84)
const LAND_MS := 140.0
const SWELL := 0.12
const QUIVER_PX := 1.2
const QUIVER_MS := 30.0
const HIT_WOBBLE_MS := 360.0
const HIT_WOBBLE := 0.14
const ZAP_FLASH := Color(1.6, 1.6, 1.3)
const RING_BOLTS := 7
## Where his middle is over his feet (px, at his drawn size), for the bolts and the sparks.
const MIDDLE_RISE_PX := 18.0
## The zap's line to a body runs this far over the ground (px), so a flat thing on the ground does
## not stop it.
const CLEAR_LINE_RISE_PX := 6.0
## The shock look's box when a body has no hurtbox shape to measure.
const FALLBACK_BOX := Rect2(-14.0, -40.0, 28.0, 30.0)

var _rng := RandomNumberGenerator.new()
var _zap_at: float = 0.0
var _next_hop_at: float = 0.0
var _hop_started: float = -1.0
var _hop_way: Vector2 = Vector2.ZERO
var _landed_at: float = -INF
var _goal: Vector2 = Vector2.INF
var _hit_wobble_until: float = 0.0
var _weapon_shock_ready_at: float = 0.0
## Where the zap struck bodies (world feet points), for the bolts.
var _struck_points: Array[Vector2] = []
var _ring: ZapLook
var _bolts: ZapLook


func _ready() -> void:
	super()
	_rng.randomize()
	add_to_group(BouncedThrow.BOUNCERS_GROUP)
	add_to_group(EATERS_GROUP)
	if body != null:
		_ring = ZapLook.new()
		_ring.name = "ZapRing"
		_ring.ring = true
		_bolts = ZapLook.new()
		_bolts.name = "ZapBolts"
		_bolts.ring = false
		_bolts.z_index = 3
		# The body is still setting up its children while this script readies.
		_mount_looks.call_deferred()
	var now := Services.now_ms()
	_wander(now)
	_zap_at = now + _rng.randf_range(pattern("zapEveryMinMs", 4000.0), pattern("zapEveryMaxMs", 6000.0))


## The ring (behind his art) and the bolts on his body.
func _mount_looks() -> void:
	if body == null or not is_instance_valid(body):
		return
	body.add_child(_ring)
	body.move_child(_ring, 0)
	body.add_child(_bolts)


# --- the pattern -----------------------------------------------------------------------------------

func _step_pattern(now: float, delta: float, target: Dictionary, _engaged: bool) -> void:
	body.velocity = Vector2.ZERO
	var elapsed := _elapsed(now)
	match _phase:
		PHASE_WANDER, PHASE_AFTER:
			if _phase == PHASE_AFTER and elapsed >= pattern("afterMs", 500.0):
				_wander(now)
			if now >= _zap_at and _hop_started < 0.0:
				_charge(now)
				return
			_step_hop(now, delta)
		PHASE_CHARGE:
			var t := clampf(elapsed / maxf(1.0, pattern("chargeMs", 800.0)), 0.0, 1.0)
			set_frame(FRAME_CHARGE)
			var swell := 1.0 + SWELL * t + _hit_wobble(now)
			set_look(0.0, Vector2(swell, swell))
			if pose != null:
				pose.position.x = sin(now / QUIVER_MS) * QUIVER_PX * (0.4 + t)
			if _ring != null:
				var flicker := 0.55 + 0.45 * sin(now / 40.0)
				_ring.show_ring(zap_reach(), t * flicker + 0.15)
			if elapsed >= pattern("chargeMs", 800.0):
				_zap(now, target)
		PHASE_ZAP:
			set_frame(FRAME_ZAP)
			set_look(0.0, Vector2(1.0 + SWELL, 1.0 + SWELL))
			if pose != null:
				pose.position.x = 0.0
			_redraw_bolts()
			if elapsed >= pattern("zapMs", 320.0):
				_after(now)


## The wander: a rest, then a hop toward the goal; a new goal once there or when a hop got nowhere.
func _step_hop(now: float, delta: float) -> void:
	if _hop_started >= 0.0:
		var hop_ms := maxf(1.0, pattern("hopMs", 420.0))
		var t := (now - _hop_started) / hop_ms
		if t >= 1.0:
			_hop_started = -1.0
			_landed_at = now
			_next_hop_at = now + pattern("hopEveryMs", 650.0) * _rng.randf_range(0.8, 1.25)
		else:
			body.velocity = _hop_way * (pattern("hopPx", 24.0) / (hop_ms / 1000.0))
			var lift := sin(t * PI) * pattern("hopLiftPx", 12.0)
			set_frame(FRAME_REST)
			set_look(lift, Vector2.ONE.lerp(HOP_STRETCH, sin(t * PI)))
			ground_shadow()
			return
	set_frame(FRAME_REST)
	var since_land := now - _landed_at
	var shape := Vector2.ONE
	if since_land < LAND_MS:
		shape = LAND_SQUASH.lerp(Vector2.ONE, since_land / LAND_MS)
	var wobble := sin(now / WOBBLE_MS) * WOBBLE + _hit_wobble(now)
	set_look(0.0, shape * Vector2(1.0 + wobble, 1.0 - wobble))
	if now >= _next_hop_at:
		_hop(now, delta)


func _hop(now: float, _delta: float) -> void:
	var here := feet()
	if _goal == Vector2.INF or here.distance_to(_goal) <= pattern("goalReachPx", 14.0):
		_goal = _wander_spot()
	var way := _goal - here
	if way.length() < 1.0:
		_next_hop_at = now + pattern("hopEveryMs", 650.0)
		return
	var hop_px := pattern("hopPx", 24.0)
	# A hop that would meet a wall, a rock or water: another spot next time.
	if _meets_solid(way.normalized() * hop_px, body.collision_mask, false):
		_goal = _wander_spot()
		_next_hop_at = now + pattern("hopEveryMs", 650.0) * 0.5
		return
	_hop_way = way.normalized()
	_hop_started = now
	face_x(_hop_way.x)


## A spot to hop toward: in his pen, his wander area, or `wanderRadiusPx` round where he started.
func _wander_spot() -> Vector2:
	var spot := Vector2.INF
	if not _arena.is_empty():
		spot = BossArena.clamp_point(_arena, get_home() + Vector2.from_angle(_rng.randf() * TAU) * pattern("wanderRadiusPx", 110.0) * sqrt(_rng.randf()))
	else:
		var area: Dictionary = get_spawn_area()
		var perimeter: Variant = area.get("stay_perimeter", area.get("perimeter", {}))
		if perimeter is Dictionary and not (perimeter as Dictionary).is_empty():
			spot = Perimeter.random_point(perimeter as Dictionary)
	if spot == Vector2.INF:
		var home := get_home() if get_home() != Vector2.INF else get_centre()
		spot = home + Vector2.from_angle(_rng.randf() * TAU) * pattern("wanderRadiusPx", 110.0) * sqrt(_rng.randf())
	# Old centre to feet.
	return spot + (feet() - get_centre())


# --- the zap ---------------------------------------------------------------------------------------

func _wander(now: float) -> void:
	_transition(PHASE_WANDER, now)
	set_frame(FRAME_REST)
	_next_hop_at = maxf(_next_hop_at, now + pattern("hopEveryMs", 650.0) * _rng.randf_range(0.3, 1.0))


func _charge(now: float) -> void:
	_transition(PHASE_CHARGE, now)
	body.velocity = Vector2.ZERO
	set_frame(FRAME_CHARGE)
	_cue(CUE_CHARGE)


## The burst: every body in reach is shocked.
func _zap(now: float, target: Dictionary) -> void:
	_transition(PHASE_ZAP, now)
	set_frame(FRAME_ZAP)
	if _ring != null:
		_ring.show_ring(zap_reach(), 1.0)
	_cue(CUE_ZAP)
	if visual != null:
		visual.self_modulate = ZAP_FLASH
	var reach := zap_reach()
	var at := feet()
	_struck_points.clear()
	if _slime_in_reach(target, reach):
		if _shock_slime(target):
			_struck_points.append((target.get("body") as Node2D).global_position)
	for node: Node in get_tree().get_nodes_in_group(ENEMY_GROUP):
		if not _shockable(node):
			continue
		var enemy_body := node.call(&"get_body") as Node2D
		if enemy_body == null or enemy_body.global_position.distance_to(at) > reach or not _same_level(enemy_body) 				or not _clear_to(enemy_body.global_position):
			continue
		_shock_enemy(node)
		_struck_points.append(enemy_body.global_position)
	_puff(SPARKS, at - Vector2(0.0, MIDDLE_RISE_PX))
	_redraw_bolts()



func _redraw_bolts() -> void:
	if _bolts == null:
		return
	var middle := Vector2(0.0, -MIDDLE_RISE_PX)
	var ends: Array[Vector2] = []
	for point: Vector2 in _struck_points:
		ends.append(body.to_local(point) + Vector2(0.0, -MIDDLE_RISE_PX * 0.6))
	var reach := zap_reach()
	for i in RING_BOLTS:
		var angle := TAU * (float(i) + _rng.randf_range(-0.3, 0.3)) / float(RING_BOLTS)
		ends.append(Vector2.from_angle(angle) * reach * _rng.randf_range(0.75, 1.0))
	_bolts.show_bolts(middle, ends)


func _after(now: float) -> void:
	_transition(PHASE_AFTER, now)
	set_frame(FRAME_REST)
	set_look(0.0)
	if visual != null:
		visual.self_modulate = Color.WHITE
	if _ring != null:
		_ring.clear()
	if _bolts != null:
		_bolts.clear()
	_struck_points.clear()
	_zap_at = now + pattern("afterMs", 500.0) + _rng.randf_range(pattern("zapEveryMinMs", 4000.0), pattern("zapEveryMaxMs", 6000.0))


## How far his zap reaches now (px from his feet): `zapRadiusPx`, x `waterReachScale` while he
## stands in shallow water.
func zap_reach() -> float:
	var reach := pattern("zapRadiusPx", 96.0)
	return reach * pattern("waterReachScale", 1.6) if _in_shallow_water() else reach


func _in_shallow_water() -> bool:
	var world := Services.world()
	var layer: TileMapLayer = world.ground_layer if world != null else null
	var wake := WaterWake.find_in(layer) if layer != null else null
	return wake != null and wake.row_of(body) == WaterWake.WADE_ROW


func _slime_in_reach(target: Dictionary, reach: float) -> bool:
	if target.is_empty() or not bool(target.get("active", false)) or not bool(target.get("hostile", false)):
		return false
	var slime_body := target.get("body") as Node2D
	return slime_body != null and slime_body.global_position.distance_to(feet()) <= reach and _same_level(slime_body) 		and _clear_to(slime_body.global_position)


## No wall, rock or fence between his feet and the ground point `point`: the zap does not go through
## walls.
func _clear_to(point: Vector2) -> bool:
	var empty: Array[RID] = []
	return AbilityWorld.clear_line(feet() + Vector2(0.0, -CLEAR_LINE_RISE_PX), point + Vector2(0.0, -CLEAR_LINE_RISE_PX), empty)


func _same_level(other: Node2D) -> bool:
	var mine := AbilityWorld.body_level(body)
	var theirs := AbilityWorld.body_level(other)
	return mine == AbilityWorld.ANY_LEVEL or theirs == AbilityWorld.ANY_LEVEL or mine == theirs


## The slime is shocked: `zapDamage` (no knock), frozen for `shockMs` while its bones flicker, then
## kicked `shockKnockPx` away from him. False when the hit did not land (a Roll's dodge, its hit
## invulnerability).
func _shock_slime(target: Dictionary) -> bool:
	var player: Node = target.get("player")
	var slime_body := target.get("body") as Node2D
	if player == null or slime_body == null or not is_instance_valid(player):
		return false
	if not _route_hit_from(feet(), target, pattern("zapDamage", 20.0), 0.0):
		return false
	var shock_ms := pattern("shockMs", 800.0)
	if slime_body is CharacterBody2D:
		(slime_body as CharacterBody2D).velocity = Vector2.ZERO
	if player.has_method(&"suppress_movement"):
		player.call(&"suppress_movement", shock_ms)
	var away := slime_body.global_position - feet()
	away = away.normalized() if away.length() > 0.5 else Vector2.DOWN
	var kick_ms := maxf(1.0, pattern("shockKnockMs", 220.0))
	var kick := Callable()
	if player.has_method(&"recoil"):
		kick = Callable(player, &"recoil").bind(away, pattern("shockKnockPx", 60.0) / (kick_ms / 1000.0), kick_ms)
	var art := player.call(&"get_visual") as CanvasItem if player.has_method(&"get_visual") else null
	var area := player.call(&"get_damage_area") as Area2D if player.has_method(&"get_damage_area") else null
	ShockLook.play(slime_body, art, ShockLook.box_of(slime_body, area, FALLBACK_BOX), shock_ms, kick)
	_cue(CUE_SHOCK)
	return true


## Another enemy in his reach: alive and in play, on the ground, not a jelly (they are electric).
func _shockable(node: Node) -> bool:
	if node == self or not is_instance_valid(node) or node is JellyBouncerScript:
		return false
	if not node.has_method(&"get_body") or not node.has_method(&"is_defeated") or bool(node.call(&"is_defeated")):
		return false
	if node.has_method(&"is_carried") and bool(node.call(&"is_carried")):
		return false
	if node.has_method(&"is_hurtbox_on") and not bool(node.call(&"is_hurtbox_on")):
		return false
	return not bool(ReactionProfileScript.for_enemy(node).get("flies", false))


## An enemy shocked: `zapEnemyDamage`, dazed `zapEnemyDazeMs`, its bones flickering as long.
func _shock_enemy(enemy: Node) -> void:
	var enemy_body := enemy.call(&"get_body") as Node2D
	if enemy.has_method(&"take_reaction_damage"):
		enemy.call(&"take_reaction_damage", pattern("zapEnemyDamage", 20.0))
	if bool(enemy.call(&"is_defeated")):
		return
	var daze := pattern("zapEnemyDazeMs", 1600.0)
	EnemyReactions.put_down(enemy, daze)
	var art := enemy.call(&"get_visual") as CanvasItem if enemy.has_method(&"get_visual") else null
	var area: Area2D = enemy.get(&"damage_area") as Area2D
	ShockLook.play(enemy_body, art, ShockLook.box_of(enemy_body, area, FALLBACK_BOX), minf(daze, pattern("shockMs", 800.0)))


# --- what bounces off him (game/throw/bounced_throw.gd, game/throw/gulpable_enemy.gd) --------------

## A thrown thing that touches him goes back (while he lives).
func bounces_throw() -> bool:
	return not is_defeated()


## How a thrown thing flies back off him.
func bounce_numbers() -> Dictionary:
	return {"speed": pattern("bounceSpeed", 380.0), "rangePx": pattern("bounceRangePx", 360.0),
		"arcPx": pattern("bounceArcPx", 22.0)}


## A thrown thing just bounced off him at `at`, going `away`: he wobbles, it boings, a few sparks.
func on_throw_bounced(at: Vector2, away: Vector2) -> void:
	_hit_wobble_until = Services.now_ms() + HIT_WOBBLE_MS
	face_x(-away.x)
	_cue(CUE_BOUNCE)
	var feel := Services.feel()
	if feel != null:
		feel.burst(SPARKS, at, away, SPARK_TINT, 0.6)


## The thing that bounced off him struck the slime at `at`, flying `direction`: the hit of its
## weight (`bounceDamageLight`, `-Medium`, `-Heavy`). True when it landed.
func bounced_hit(at: Vector2, direction: Vector2, weight: String) -> bool:
	var key := "bounceDamage" + (weight.capitalize() if not weight.is_empty() else "Light")
	var damage := pattern(key, pattern("bounceDamageLight", 12.0))
	return _route_hit_from(at, _primary_target(), damage, pattern("bounceKnockback", 180.0), direction)


## A thrown enemy (enemies as ammo) landing by him: shocked, it bounces off him and lies dazed, its
## bones flickering. True when he took it (game/throw/gulpable_enemy.gd then skips its landing hit).
func catch_thrown(enemy: Node, spot: Vector2) -> bool:
	if is_defeated() or not _shockable(enemy) or spot.distance_to(feet()) > pattern("thrownEnemyReachPx", 60.0):
		return false
	var away := spot - feet()
	away = away.normalized() if away.length() > 0.5 else Vector2.DOWN
	_shock_enemy(enemy)
	_cue(CUE_SHOCK)
	_hit_wobble_until = Services.now_ms() + HIT_WOBBLE_MS
	var enemy_body := enemy.call(&"get_body") as CharacterBody2D
	var bounce_ms := pattern("thrownEnemyBounceMs", 260.0)
	if enemy_body != null and not bool(enemy.call(&"is_defeated")):
		enemy_body.velocity = away * EnemyReactions.speed_for_distance(pattern("thrownEnemyBouncePx", 26.0), bounce_ms)
		var motion := EnemyReactions.motion_of(enemy)
		if motion != null:
			motion.play(EnemyHitMotion.BOUNCE, away, {"hop_px": 12.0, "ms": bounce_ms})
	return true


# --- hits ------------------------------------------------------------------------------------------

## Arrows and the Goo Bomb's blast reach him; a shape's hit is conducted back into the slime (no
## clink); a thrown thing bounces off (no clink); everything else clinks.
func can_receive_damage(input: Dictionary) -> Dictionary:
	if is_defeated():
		return super(input)
	var request: Dictionary = input.get("request", {})
	if _kill_hit(request) or has_tag(request, ARROW_TAG):
		return super(input)
	if has_tag(request, WEAPON_TAG):
		_conduct.call_deferred()
		return {"accepted": false, "reason": REASON_CONDUCTS}
	if _thrown(request):
		return {"accepted": false, "reason": REASON_BOUNCES}
	return {"accepted": false, "reason": SHIELD_REASON}


## The Goo Bomb's blast kills him at once.
func _kill_hit(request: Dictionary) -> bool:
	return has_tag(request, BLAST_TAG)


## An arrow takes his health over `arrowHits` arrows, whatever its damage.
func mitigate_damage(input: Dictionary) -> float:
	var request: Dictionary = input.get("request", {})
	if not _kill_hit(request) and has_tag(request, ARROW_TAG):
		return ceilf(max_health / maxf(1.0, pattern("arrowHits", 2.0)))
	return super(input)


func commit_damage(commit: Dictionary) -> void:
	super(commit)
	if not is_defeated() and int((commit.get("result", {}) as Dictionary).get("actual_damage", 0)) > 0:
		_hit_wobble_until = Services.now_ms() + HIT_WOBBLE_MS


## A shape's hit went into him: the slime that struck is shocked (at most every
## `weaponShockCooldownMs`).
func _conduct() -> void:
	var now := Services.now_ms()
	if is_defeated() or now < _weapon_shock_ready_at:
		return
	_weapon_shock_ready_at = now + pattern("weaponShockCooldownMs", 600.0)
	var target := _primary_target()
	if _shock_slime(target) and _bolts != null:
		_hit_wobble_until = now + HIT_WOBBLE_MS
		var slime_body := target.get("body") as Node2D
		_puff(SPARKS, slime_body.global_position - Vector2(0.0, MIDDLE_RISE_PX))


## A thrown thing: the throw's hit class (thrown, thrown-medium, ...) or the `thrown` tag.
func _thrown(request: Dictionary) -> bool:
	var hit: Variant = request.get("hit")
	if hit is Dictionary and str((hit as Dictionary).get("class", "")).begins_with(THROWN_TAG):
		return true
	return has_tag(request, THROWN_TAG)


## Jelly: a blow never slides him.
func _slides_when_stunned() -> bool:
	return false


func _hit_wobble(now: float) -> float:
	if now >= _hit_wobble_until:
		return 0.0
	var left := (_hit_wobble_until - now) / HIT_WOBBLE_MS
	return sin(now / 28.0) * HIT_WOBBLE * left


func _defeat() -> void:
	if is_defeated():
		return
	if _ring != null:
		_ring.clear()
	if _bolts != null:
		_bolts.clear()
	if visual != null:
		visual.self_modulate = Color.WHITE
	if pose != null:
		pose.position.x = 0.0
	super()
	_cue(CUE_POP)
	var feel := Services.feel()
	if feel != null:
		feel.burst(SPLASH, feet() - Vector2(0.0, MIDDLE_RISE_PX * 0.5), Vector2.UP, JELLY_TINT, 1.2)
		feel.burst(SPARKS, feet() - Vector2(0.0, MIDDLE_RISE_PX), Vector2.UP, SPARK_TINT, 0.8)


## True while he charges or zaps.
func is_zapping() -> bool:
	return _phase == PHASE_CHARGE or _phase == PHASE_ZAP
