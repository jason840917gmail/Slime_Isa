extends Node2D
## The enemy-ammo prototype (owner, 2026-11-16: Kirby, Klonoa, Super Mario Bros. 2: the enemy you
## just stunned is your next projectile; docs/godot/THROW_COMBAT.md). One of these sits on every
## enemy's body that is no boss (enemy.gd `_ready`, `attach`) and makes the enemy a suckable while it
## lies helpless from a throw. Behind its own switch, `gulp.throwFeel.enemyAmmo.enabled`, and only
## while the new throw feel is on (`is_on`; the throw yard flips it for the session: `toggle`). With
## the switch off it does nothing: `can_take` is false and nothing is drawn.
##
## - **Who** (`_gulpable`): not a boss, not rooted (`knockbackScale` 0), not defeated, not carried,
##   and helpless on the ground from a throw (EnemyReactions `is_helpless`: dazed, knocked down,
##   staggered, frozen or asleep by a thrown hit, or dazed by a chain's wall splat or bowl; its
##   knock's flight over, no wake guard, not in a `noSleep` phase). The Gulp's level must lift its
##   weight as it lifts a liftable's (ThrowMode `can_lift`: a tiny or light enemy is light, medium
##   needs level 2, heavy level 3); one it cannot lift answers `is_too_heavy` (the mouth says so).
## - **Readable** (`_step_hint`, `_draw`): a gulpable enemy within `hintRangePx` of the slime shows a
##   pulsing goo-green ring at its feet and a pulsing outline of the same green round its picture
##   (`hint`: color, pulseMs, ringPx, outlineAlpha), whether the Gulp can lift it or not.
## - **The gulp** (the mouth's suckable contract: `origin`, `can_take`, `suck_info`, `take`): `take`
##   does not kill it. It is carried: out of play (enemy.gd `begin_carry`: hidden, no collision, no
##   hurtbox, its step stopped, out of the "enemy" group), alive and valid, so rooms, the population
##   and quests still count it standing and nothing reports its death. Its stun, sleep and status
##   look end. The held Dictionary: {"kind": "enemy", "enemy": its script's instance id,
##   "enemy_type", "weight", "material", "struggle_until_ms", and its picture (gulped_enemy_look.gd
##   `frame_of`: "enemy_texture", "enemy_region", "flip_h", "art_px")}.
## - **Carrying** (`_step_held`): each step it asks the mouth whether it still holds it. After
##   `holdMs` it bursts out beside the slime (`_come_out`: "Ptoo!", a goo puff, dazed `outDazeMs`,
##   unhurt, not gulpable from that daze). The same happens whenever the mouth no longer holds it and
##   it was not thrown (a hit made the slime drop it, the mouth was cleared, the slime died: then it
##   is put back where it was taken), so it is never lost and never doubled, whatever the mouth does.
## - **The throw** (`thrown`, from thrown_object.gd `launch`): it flies as the thrown thing's look;
##   the thrown thing tells where it ends (`land`): the enemy reappears there (on the nearest spot
##   back along the throw where a body fits: ThrowAmmo.fits; else where it was taken) and takes the
##   throw's base damage x `damageScale` when it struck an enemy, x `missDamageScale` when it struck
##   nothing, as a routed hit of class `landing` (`combat.hits.landing`: every weight answers it with
##   a knockdown), so its damage, its death (rewards, the quest event, the death sound, the send-off
##   pop) and its immunities are its own: an enemy immune now takes nothing and lands dazed instead.
##   One that comes down over an endless hole or deep water meets that fate instead (enemy_hazards.gd
##   `landing_fate`: it dies on the nearest ground back along the throw and falls or sinks where it
##   came down); thrown off a ledge it lands on the lower ground and lives there; thrown into spikes
##   or lava it lands and the zone hurts it.
##   Down from the landing it can be gulped again. A throw that never tells (`flightSafetyMs`) puts
##   it back too.
##
## Not a farm: an enemy dies once and pays once; every throw of it hurts it.
##
## Owner: throw combat (the enemy-ammo prototype).

const Services := preload("res://game/shared/services.gd")
const ThrowFeel := preload("res://game/throw/throw_feel.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const EnemyReactions := preload("res://game/combat/reactions/enemy_reactions.gd")
const HitReaction := preload("res://game/combat/reactions/hit_reaction.gd")
const ReactionProfile := preload("res://game/combat/reactions/reaction_profile.gd")
const GulpedEnemyLook := preload("res://game/throw/gulped_enemy_look.gd")
## What the ground does to a thrown enemy that comes down over a hole, deep water or a danger zone.
const EnemyHazards := preload("res://game/combat/reactions/enemy_hazards.gd")

## The held kind of a carried enemy.
const KIND := "enemy"
const NODE_NAME := "GulpableEnemy"
const SUCKABLE_GROUP := &"suckable"
## Its numbers: `gulp.throwFeel.<BLOCK>`.
const BLOCK := "enemyAmmo"
## The hit a landing enemy takes (`combat.hits.landing`, `combat.weights.<weight>.classes.landing`).
const LANDING_CLASS := "landing"
const LANDING_TAGS: Array[String] = ["thrown", "landing"]
const DAMAGE_TYPES: Array[String] = ["physical"]
## A reaction weight as a thrown thing's weight (a boss is never carried).
const THROW_WEIGHTS := {"tiny": "light", "light": "light", "medium": "medium", "heavy": "heavy"}
## The status look a throw's effect put on the enemy (throw_status_look.gd NODE_NAME).
const STATUS_LOOK_NODE := "ThrowStatusLook"
## The ring at the feet: this share of the picture's width across (within these px), this flat, and
## how much the pulse swells it and fills it.
const RING_WIDTH_SHARE := 0.42
const RING_MIN_PX := 14.0
const RING_MAX_PX := 46.0
const RING_FLAT := 0.42
const RING_SWELL := 0.14
const RING_POINTS := 32
const RING_ALPHA := Vector2(0.4, 0.95)
const FILL_ALPHA := Vector2(0.08, 0.24)
## Where the burst-out's word shows over the slime's feet, and its cue (the mouth's spit).
const WORD_RISE := 44.0
const WORD := "Ptoo!"
const CUE_OUT := &"GulpSpit"
const PUFF := &"slime-splash"
const DUST := &"dodge-dust"

enum Carry { NONE, HELD, FLYING }

## The session's dev switch: -1 = the constants', 0 off, 1 on.
static var _session: int = -1

## The enemy's script (enemy.gd).
var enemy: Node

var _carry: int = Carry.NONE
## When and where it was taken (simulation ms; its feet and its height level).
var _taken_at_ms: float = 0.0
var _taken_from: Vector2 = Vector2.ZERO
var _taken_level: int = AbilityWorld.ANY_LEVEL
## The thrown thing that carries it in flight, and when the flight is given up.
var _carrier: WeakRef = null
var _fly_until_ms: float = 0.0
## The hint: shown now, its pulse's clock (ms) and when the outline last pulsed.
var _hinting: bool = false
var _pulse_ms: float = 0.0
var _outlined_at_ms: float = -INF


# --- the switch and the numbers --------------------------------------------------------------------

## True while enemies can be gulped: the new throw feel on, and the constants' switch
## (`gulp.throwFeel.enemyAmmo.enabled`) or the session's.
static func is_on() -> bool:
	if not ThrowFeel.is_on() or _session == 0:
		return false
	return _session == 1 or bool(ThrowFeel.block(BLOCK).get("enabled", false))


## Flips it for the session (the throw yard's dev key); returns whether it is on now.
static func toggle() -> bool:
	_session = 0 if is_on() else 1
	return is_on()


## Back to the constants' switch.
static func clear_session() -> void:
	_session = -1


## `gulp.throwFeel.enemyAmmo.<key>`.
static func number(key: String, fallback: float = 0.0) -> float:
	return ThrowFeel.number("%s.%s" % [BLOCK, key], fallback)


# --- what the mouth and the thrown thing call ------------------------------------------------------

## Puts a helper on `enemy`'s body (enemy.gd `_ready`); once.
static func attach(enemy_script: Node) -> void:
	if enemy_script == null or not enemy_script.has_method(&"get_body"):
		return
	var body := enemy_script.call(&"get_body") as Node
	if body == null or body.has_node(NODE_NAME):
		return
	var helper: Node2D = new()
	helper.name = NODE_NAME
	helper.set(&"enemy", enemy_script)
	helper.show_behind_parent = true
	body.add_child.call_deferred(helper)


## True when `held` is a carried enemy.
static func is_enemy(held: Dictionary) -> bool:
	return str(held.get("kind", "")) == KIND


## The helper of the enemy `held` names, or null when that enemy is gone (its world was left).
static func of(held: Dictionary) -> Node:
	var id: Variant = held.get("enemy")
	if not (id is int or id is float) or not is_instance_id_valid(int(id)):
		return null
	var script := instance_from_id(int(id)) as Node
	if script == null or not script.has_method(&"get_body"):
		return null
	var body := script.call(&"get_body") as Node
	return body.get_node_or_null(NODE_NAME) if body != null else null


## The look of `held` (the enemy's own picture, wriggling), about `size_px` across: for
## held_look.gd `make`.
static func make_look(held: Dictionary, size_px: float) -> Node2D:
	return GulpedEnemyLook.make(held, size_px)


## The damage a thrown enemy deals to what it strikes: the throw's base damage x `damageScale`.
static func throw_damage() -> float:
	return ThrowFeel.base_damage() * number("damageScale", 1.0)


## The class of the hit a thrown enemy deals (`hitClass`: thrown-medium).
static func throw_hit_class() -> String:
	return str(ThrowFeel.block(BLOCK).get("hitClass", "thrown-medium"))


## `held`'s enemy was thrown: `carrier` (the thrown thing) carries it until it calls `land`.
static func thrown(held: Dictionary, carrier: Node2D) -> void:
	var helper := of(held)
	if helper != null:
		helper.call(&"_fly", carrier)


## The throw of `held`'s enemy ended with its ground point at `at`, flying along `direction`, thrown
## from `feet` on height level `level`; `struck` when it hit an enemy. The enemy reappears and takes
## its landing (see the file comment). {} when there is no enemy to land; else {"at": where it
## stands, "result": the landing hit's route() result}.
static func land(held: Dictionary, at: Vector2, direction: Vector2, feet: Vector2, level: int, struck: bool) -> Dictionary:
	var helper := of(held)
	if helper == null:
		return {}
	return helper.call(&"_land", at, direction, feet, level, struck)


## The mouth lets `held`'s enemy go (a hit made the slime drop it): it comes out beside the slime.
## The helper would notice by itself a step later; this is at once.
static func release(held: Dictionary) -> void:
	var helper := of(held)
	if helper != null:
		helper.call(&"_release")


# --- the mouth's suckable contract (game/player/gulp/mouth.gd) -------------------------------------

func _enter_tree() -> void:
	add_to_group(SUCKABLE_GROUP)


## Its feet (the body's place).
func origin() -> Vector2:
	var body := get_parent() as Node2D
	return body.global_position if body != null else global_position


func can_take() -> bool:
	return is_on() and is_inside_tree() and _gulpable() and ThrowMode.can_lift(_weight())


## It lies there helpless but the Gulp's level is too low for its weight.
func is_too_heavy() -> bool:
	return is_on() and is_inside_tree() and _gulpable() and not ThrowMode.can_lift(_weight())


## Its weight as a thrown thing (the mouth names the level it needs: mouth_hold.gd).
func weight() -> String:
	return _weight()


func suck_info() -> Dictionary:
	var profile := ReactionProfile.for_enemy(enemy)
	var info := {
		"kind": KIND, "essence": "", "variant": 0,
		"enemy": enemy.get_instance_id(),
		"enemy_type": ReactionProfile.type_of(enemy),
		"weight": _weight(),
		"material": str(profile.get("material", "")),
		"struggle_until_ms": Services.now_ms() + number("holdMs", 0.0),
	}
	info.merge(GulpedEnemyLook.frame_of(enemy.call(&"get_visual") as Sprite2D if enemy.has_method(&"get_visual") else null))
	return info


## Sucked in: the enemy is carried (taken out of play, alive).
func take() -> void:
	if not can_take():
		return
	var body := get_parent() as Node2D
	_taken_from = body.global_position
	_taken_level = AbilityWorld.body_level(body)
	_taken_at_ms = Services.now_ms()
	var look := body.get_node_or_null(STATUS_LOOK_NODE)
	if look != null:
		look.queue_free()
	EnemyReactions.prepare_carry(enemy)
	if not bool(enemy.call(&"begin_carry")):
		return
	_carry = Carry.HELD
	_carrier = null
	_show_hint(false)


# --- carrying ---------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	match _carry:
		Carry.HELD:
			_step_held()
		Carry.FLYING:
			_step_flying()
		_:
			_step_hint(delta)


## In the mouth (or flying into it): out after `holdMs`, or as soon as the mouth no longer has it.
func _step_held() -> void:
	var mouth := _mouth()
	var holding := _mouth_holds(mouth)
	var pulling := mouth != null and bool(mouth.call(&"is_pulling"))
	if not holding and not pulling:
		_come_out(_slime_down())
		return
	if Services.now_ms() >= _taken_at_ms + number("holdMs", 0.0):
		if holding:
			mouth.call(&"clear_held")
		_come_out(false)


## In flight: the thrown thing lands it; one that is gone or takes too long puts it back.
func _step_flying() -> void:
	var carrier: Variant = _carrier.get_ref() if _carrier != null else null
	if carrier is Node2D and is_instance_valid(carrier) and not (carrier as Node).is_queued_for_deletion() \
			and Services.now_ms() < _fly_until_ms:
		return
	if carrier is Node2D and is_instance_valid(carrier):
		_land((carrier as Node2D).global_position, Vector2.ZERO, _taken_from, _taken_level, false)
	else:
		_come_out(true)


func _fly(carrier: Node2D) -> void:
	if _carry != Carry.HELD:
		return
	_carry = Carry.FLYING
	_carrier = weakref(carrier) if carrier != null else null
	_fly_until_ms = Services.now_ms() + number("flightSafetyMs", 0.0)


func _release() -> void:
	if _carry == Carry.HELD:
		_come_out(false)


## It comes out of the mouth unhurt: beside the slime (the first spot around it where a body fits),
## or, `home`, where it was taken; dazed `outDazeMs`.
func _come_out(home: bool) -> void:
	if _carry == Carry.NONE:
		return
	_carry = Carry.NONE
	var world := Services.world()
	var slime := world.player_body if world != null else null
	var spot := _taken_from
	var level := _taken_level
	var beside := false
	if not home and slime != null and is_instance_valid(slime):
		var feet := slime.global_position
		var facing: Vector2 = world.player.call(&"get_facing") if world.player != null and world.player.has_method(&"get_facing") else Vector2.DOWN
		if facing == Vector2.ZERO:
			facing = Vector2.DOWN
		var on := AbilityWorld.body_level(slime)
		# Beside it on screen first (a body above or below it is drawn over or under the slime), the
		# side it faces away from first.
		var behind := Vector2.LEFT if facing.x >= 0.0 else Vector2.RIGHT
		for way: Vector2 in [behind, -behind, Vector2.DOWN, Vector2.UP]:
			var candidate := feet + way.normalized() * number("outPx", 0.0)
			if ThrowAmmo.fits(candidate, feet, on):
				spot = candidate
				level = on
				beside = true
				break
	enemy.call(&"end_carry", spot, level if level != AbilityWorld.ANY_LEVEL else null)
	EnemyReactions.put_down(enemy, number("outDazeMs", 0.0))
	var feel := Services.feel()
	if feel == null:
		return
	feel.burst(PUFF, spot)
	if beside:
		feel.floating_text(slime.global_position - Vector2(0.0, WORD_RISE), WORD, &"white", false)
		feel.audio_cue(CUE_OUT)


## The throw ended (`land`): the enemy stands where a body fits and takes its landing hit.
func _land(at: Vector2, direction: Vector2, feet: Vector2, level: int, struck: bool) -> Dictionary:
	if _carry == Carry.NONE:
		return {}
	_carry = Carry.NONE
	_carrier = null
	var unit := direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO
	var spot := _taken_from
	var on := _taken_level
	var step := number("landTryPx", 0.0)
	# Over an endless hole or deep water it meets that fate (enemy_hazards.gd), dying on the nearest
	# ground back along the throw (the rim, the bank: its rewards fall where the slime reaches them).
	var fate := EnemyHazards.landing_fate(enemy, at, level)
	# Thrown off a ledge it comes down on the lower ground there, and lives on that level.
	var world := Services.world()
	var lower := level
	if fate.is_empty() and not struck and level != AbilityWorld.ANY_LEVEL and world != null and world.elevation != null:
		lower = mini(level, world.elevation.walkable_level_at(at))
	# Against an enemy it lands a step short of the contact; on the ground where it came down. Over a
	# hole or water the search runs all the way back to where it was thrown from (the rim, the bank).
	var tries := maxi(1, int(number("landTries", 1.0)))
	if not fate.is_empty() and step > 0.0:
		tries = maxi(tries, ceili(at.distance_to(feet) / step))
	for i in range(1 if struck else 0, tries + 1):
		var candidate := at - unit * step * float(i)
		if ThrowAmmo.fits(candidate, feet, level):
			spot = candidate
			on = level
			break
		if i == 0 and lower < level and ThrowAmmo.fits(candidate, feet, lower):
			spot = candidate
			on = lower
			break
	# Dying over a hole or water, it stands `fateBackPx` further onto the ground, so its rewards (an
	# essence hops a little below where it dies) fall on the ground, not into the water or the void.
	if not fate.is_empty() and spot != _taken_from:
		var back := spot - unit * number("fateBackPx", 0.0)
		if ThrowAmmo.fits(back, feet, on):
			spot = back
	enemy.call(&"end_carry", spot, on if on != AbilityWorld.ANY_LEVEL else null)
	if not fate.is_empty():
		EnemyHazards.landing_death(enemy, fate, at)
		return {"at": at, "fate": fate}
	if on != _taken_level and enemy.has_method(&"settle_at"):
		enemy.call(&"settle_at", enemy.call(&"get_centre"))
	var feel := Services.feel()
	if feel != null:
		feel.burst(DUST, spot)
	var result := _route_landing(ThrowFeel.base_damage() * number("damageScale" if struck else "missDamageScale", 1.0), unit)
	var dealt := int(result.get("actual_damage", 0))
	if str(result.get("status", "")) != "accepted":
		# Immune now (or no hit could be sent): it lands unhurt and only dazed.
		EnemyReactions.put_down(enemy, number("outDazeMs", 0.0))
	elif dealt > 0 and feel != null:
		feel.play_hit({"hit_stop_ms": 0.0, "number": dealt, "number_big": false}, enemy.call(&"get_centre"), unit)
	# Thrown into spikes or lava: the zone hurts it from now on, as it does the slime.
	EnemyHazards.landed_at(enemy)
	return {"at": spot, "result": result}


## The landing's hit, routed from the slime to this enemy's hurtbox like any thrown hit: class
## `landing` (a knockdown for every weight), tagged `thrown`, with the hard flash and, when it
## kills, the send-off along the throw. {} when it cannot be sent.
func _route_landing(damage: float, direction: Vector2) -> Dictionary:
	var router := Services.router()
	var world := Services.world()
	var slime: Node = world.player if world != null else null
	var attack_area := slime.call(&"get_slam_area") as Area2D if slime != null and slime.has_method(&"get_slam_area") else null
	var target := enemy.get(&"damage_area") as Area2D
	if router == null or attack_area == null or target == null:
		return {}
	var hit := HitReaction.build_hit(LANDING_CLASS, {
		"step": 0, "last": true, "tags": LANDING_TAGS.duplicate(),
		"knock": direction,
		"launch_speed": float(ThrowFeel.hit_block(_weight()).get("launchSpeed", 0.0)),
		"big": true, "kill_sendoff": true,
	})
	var activation := router.begin_activation(slime, [attack_area])
	var request := {
		"activation_id": activation,
		"source": slime,
		"attack_area": attack_area,
		"target_area": target,
		"weapon_id": "thrown-" + KIND,
		"weapon_tags": ["thrown", KIND],
		"damage_types": DAMAGE_TYPES.duplicate(),
		"base_damage": damage,
		"effects": [],
		"impact": {"position": target.global_position, "knock": direction},
	}
	var result: Dictionary = router.route(HitReaction.attach(request, hit))
	router.end_activation(activation)
	return result


# --- who can be gulped, and the hint ----------------------------------------------------------------

## True while this enemy could be gulped, whatever the Gulp's level (see the file comment).
func _gulpable() -> bool:
	if _carry != Carry.NONE or enemy == null or not is_instance_valid(enemy):
		return false
	if not EnemyReactions.is_helpless(enemy):
		return false
	var profile := ReactionProfile.for_enemy(enemy)
	if not THROW_WEIGHTS.has(str(profile.get("weight", ""))):
		return false
	var scale: Variant = profile.get("knockbackScale", 1.0)
	return (scale is float or scale is int) and float(scale) > 0.0


## Its weight as a thrown thing ("light", "medium" or "heavy").
func _weight() -> String:
	return str(THROW_WEIGHTS.get(str(ReactionProfile.for_enemy(enemy).get("weight", "")), ThrowMode.LIGHT))


## The ring and the outline show while it can be gulped and the slime is within `hintRangePx`.
func _step_hint(delta: float) -> void:
	var show := is_on() and _gulpable() and _slime_within(number("hintRangePx", 0.0))
	if show != _hinting:
		_show_hint(show)
	if not _hinting:
		return
	_pulse_ms += delta * 1000.0
	var hint := ThrowFeel.block(BLOCK + ".hint")
	var period := maxf(1.0, float(hint.get("pulseMs", 700.0)))
	if _pulse_ms - _outlined_at_ms >= period:
		_outlined_at_ms = _pulse_ms
		var motion := EnemyReactions.motion_of(enemy)
		if motion != null:
			motion.outline(period, Color(_hint_color(hint), float(hint.get("outlineAlpha", 1.0))))
	queue_redraw()


func _show_hint(on: bool) -> void:
	_hinting = on
	_pulse_ms = 0.0
	_outlined_at_ms = -INF
	queue_redraw()


func _draw() -> void:
	if not _hinting:
		return
	var hint := ThrowFeel.block(BLOCK + ".hint")
	var color := _hint_color(hint)
	var wave := 0.5 + 0.5 * sin(TAU * _pulse_ms / maxf(1.0, float(hint.get("pulseMs", 700.0))))
	var across := _ring_radius() * (1.0 + RING_SWELL * wave)
	var points := PackedVector2Array()
	for i in RING_POINTS:
		var angle := TAU * float(i) / float(RING_POINTS)
		points.append(Vector2(cos(angle) * across, sin(angle) * across * RING_FLAT))
	draw_colored_polygon(points, Color(color, lerpf(FILL_ALPHA.x, FILL_ALPHA.y, wave)))
	points.append(points[0])
	draw_polyline(points, Color(color, lerpf(RING_ALPHA.x, RING_ALPHA.y, wave)), float(hint.get("ringPx", 2.0)), true)


static func _hint_color(hint: Dictionary) -> Color:
	var text := str(hint.get("color", ""))
	return Color.html(text) if Color.html_is_valid(text) else Color(0.48, 0.88, 0.54)


## Half the ring's width: a share of the picture's.
func _ring_radius() -> float:
	var visual := enemy.call(&"get_visual") as Sprite2D if enemy.has_method(&"get_visual") else null
	if visual == null or not is_instance_valid(visual):
		return RING_MIN_PX
	return clampf(visual.get_rect().size.x * absf(visual.scale.x) * RING_WIDTH_SHARE, RING_MIN_PX, RING_MAX_PX)


func _slime_within(reach: float) -> bool:
	var world := Services.world()
	var slime := world.player_body if world != null else null
	var body := get_parent() as Node2D
	return slime != null and is_instance_valid(slime) and body != null \
		and slime.global_position.distance_to(body.global_position) <= reach


## The slime's mouth (mouth.gd), or null.
func _mouth() -> RefCounted:
	var world := Services.world()
	var slime: Node = world.player if world != null else null
	if slime == null or not is_instance_valid(slime) or not slime.has_method(&"get_mouth"):
		return null
	return slime.call(&"get_mouth") as RefCounted


## True while `mouth` holds this very enemy.
func _mouth_holds(mouth: RefCounted) -> bool:
	if mouth == null:
		return false
	var held: Variant = mouth.get(&"held")
	if not held is Dictionary or not is_enemy(held as Dictionary):
		return false
	var id: Variant = (held as Dictionary).get("enemy")
	return (id is int or id is float) and int(id) == enemy.get_instance_id()


## True when the slime is dead or gone (a carried enemy then goes back where it was taken).
func _slime_down() -> bool:
	var world := Services.world()
	var slime: Node = world.player if world != null else null
	if slime == null or not is_instance_valid(slime):
		return true
	return slime.has_method(&"is_dead") and bool(slime.call(&"is_dead"))
