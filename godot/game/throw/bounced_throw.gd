extends Node2D
## A thrown thing bouncing off a Jelly Bouncer (docs/godot/BESTIARY.md "39. Jelly Bouncer",
## docs/godot/THROW_COMBAT.md "Off a jelly"; the owner, 2026-11-22: "throw objects bounce off him back
## to the thrower, so it is better to avoid them", and "if the slime sucks it can catch the object").
## game/player/gulp/thrown_object.gd makes one instead of striking when the thing touches a bouncer (an
## enemy in the group BOUNCERS_GROUP whose `bounces_throw()` says yes): the same thing flies back from
## where it touched him toward where the slime stood at that moment (it does not home in), in a low
## bouncy arc, at the bouncer's `bounceSpeed`, for at most its `bounceRangePx`:
## - it meets the slime (the slime's middle within HIT_PX of the thing, on the thrower's height level):
##   the bouncer hurts it (its `bounced_hit`: `bounceDamage<Weight>`, knocked along the flight), and
##   the thing breaks there as a thrown thing breaks on a hit (a sturdy thing falls whole instead);
## - a wall, or the end of its flight: it breaks as a missed throw does, or a sturdy thing (stone,
##   metal, bone) lies where it came down, as the same thing again;
## - **the catch**: it is in the rebounds' group (game/throw/throw_rebound.gd GROUP, the same
##   `can_catch`, `take` and `air_point`), so a Q press with an empty mouth while it is within
##   `catchRangePx` of the slime's feet, `catchFromMs` after the bounce, takes it straight into the
##   mouth (Mouth.snap_catch: "Catch!", and its next throw is hot).
##
## The node sits on the ground point under the flying thing (its shadow is there); the look rides
## above it. Gameplay time (the physics step).
##
## Owner: throw combat (the sender).

const Services := preload("res://game/shared/services.gd")
const AbilityWorld := preload("res://game/player/abilities/ability_world.gd")
const HeldLook := preload("res://game/player/gulp/held_look.gd")
const BreakBurst := preload("res://game/player/gulp/break_burst.gd")
const LiftableScript := preload("res://game/scripts/liftable.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const ThrowFeel := preload("res://game/throw/throw_feel.gd")
const ThrowRebound := preload("res://game/throw/throw_rebound.gd")
const DungBall := preload("res://game/enemy/dung_ball.gd")

## The enemies a thrown thing bounces off (the Jelly Bouncer): `bounces_throw() -> bool`,
## `bounce_numbers() -> Dictionary` ({"speed", "rangePx", "arcPx"}), `on_throw_bounced(at, away)` and
## `bounced_hit(at, direction, weight) -> bool`, with their `damage_area`.
const BOUNCERS_GROUP := &"throw_bouncers"
## It meets the slime when the slime's middle is this close to the thing (px).
const HIT_PX := 20.0
const SPIN_PER_S := 9.0
const SHADOW := Color(0.0, 0.0, 0.0, 0.28)
const SHADOW_SIZE := Vector2(12.0, 5.0)
const SHADOW_LOOK_PX := 30.0
const DUST_PRESET := &"dodge-dust"

var _held: Dictionary = {}
var _direction: Vector2 = Vector2.DOWN
var _speed: float = 1.0
var _range_px: float = 1.0
var _travelled: float = 0.0
var _from_height: float = 0.0
var _arc_px: float = 0.0
var _look_px: float = 30.0
var _level: int = AbilityWorld.ANY_LEVEL
var _feet: Vector2 = Vector2.ZERO
var _age_ms: float = 0.0
var _bouncer: Node
var _player: Node
var _cue: StringName = &""
var _particles: Array = []
var _weight: String = ""
var _look: Node2D
var _done: bool = false


## The thing `held` bouncing off `bouncer` under `parent`: from the ground point `from` (the thing
## `from_height` over it) toward the ground point `aim` (where the slime stands), its look `look_px`
## across; `player` the thrower (its feet and level are where the thing may lie); `cue` and
## `particles` its material's break cue and particles (thrown_object.gd's); `weight` its throw
## weight ("light", "medium", "heavy"), which picks the bouncer's hit.
static func launch(parent: Node, held: Dictionary, from: Vector2, from_height: float, aim: Vector2, look_px: float,
		bouncer: Node, player: Node, cue: StringName, particles: Array, weight: String) -> Node2D:
	if parent == null:
		return null
	var node := new()
	node.name = "BouncedThrow"
	node._held = held.duplicate()
	node._held.erase("hot")
	var away := aim - from
	node._direction = away.normalized() if away.length() > 1.0 else Vector2.DOWN
	var numbers: Dictionary = bouncer.call(&"bounce_numbers") if bouncer != null and bouncer.has_method(&"bounce_numbers") else {}
	node._speed = maxf(1.0, float(numbers.get("speed", 380.0)))
	node._range_px = maxf(1.0, float(numbers.get("rangePx", 360.0)))
	node._arc_px = float(numbers.get("arcPx", 20.0))
	node._from_height = from_height
	node._look_px = look_px
	node._bouncer = bouncer
	node._player = player
	node._cue = cue
	node._particles = particles
	node._weight = weight
	var body := player.get(&"body") as Node2D if player != null and is_instance_valid(player) else null
	node._feet = body.global_position if body != null else aim
	node._level = AbilityWorld.body_level(body) if body != null else AbilityWorld.ANY_LEVEL
	node.z_index = 5
	parent.add_child(node)
	node.global_position = from
	node._look = HeldLook.make(node._held, look_px)
	node._look.modulate = ThrowFeel.wear_tint(node._held, HeldLook.material_of(node._held))
	node.add_child(node._look)
	node._place()
	node.reset_physics_interpolation()
	return node


func _enter_tree() -> void:
	add_to_group(ThrowRebound.GROUP)


# --- the rebounds' catch contract (game/throw/throw_rebound.gd, mouth.gd `snap_catch`) -------------

## True while the mouth may catch it: `catchFromMs` into its flight, until it ends.
func can_catch() -> bool:
	return not _done and _age_ms >= ThrowFeel.rebound_number("catchFromMs", 0.0)


## Caught: it leaves the air; returns what the mouth now holds ({} when it was already gone).
func take() -> Dictionary:
	if _done:
		return {}
	_done = true
	queue_free()
	return _held.duplicate()


## Where the thing itself is now (over its ground point).
func air_point() -> Vector2:
	return global_position - Vector2(0.0, _height(_travelled / _range_px))


# --- the flight ----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _done:
		return
	_age_ms += delta * 1000.0
	var step := minf(_speed * delta, _range_px - _travelled)
	var from := air_point()
	var next_ground := global_position + _direction * step
	var next_air := next_ground - Vector2(0.0, _height(minf(1.0, (_travelled + step) / _range_px)))
	var reach := AbilityWorld.line_reach(from, next_air, _player_rids())
	if reach.distance_to(next_air) > AbilityWorld.CLEAR_LINE_SLACK_PX:
		_end(reach, false)
		return
	global_position = next_ground
	_travelled += step
	_place()
	if _meets_slime(next_air):
		_hit_slime(next_air)
		return
	if _travelled >= _range_px - 0.01:
		_end(global_position, false)


func _draw() -> void:
	var t := clampf(_travelled / _range_px, 0.0, 1.0)
	var size := SHADOW_SIZE * (_look_px / SHADOW_LOOK_PX) * lerpf(1.0, 0.6, 4.0 * t * (1.0 - t))
	var points := PackedVector2Array()
	for i in 16:
		var angle := TAU * i / 16.0
		points.append(Vector2(cos(angle) * size.x, sin(angle) * size.y))
	draw_colored_polygon(points, SHADOW)


func _place() -> void:
	if _look != null:
		_look.position = Vector2(0.0, -_height(_travelled / _range_px))
		_look.rotation = -SPIN_PER_S * _age_ms / 1000.0 * signf(_direction.x if _direction.x != 0.0 else 1.0)
	queue_redraw()


## Height over the ground at flight share `t`: from where it touched the jelly down to the ground,
## with the bounce's rise.
func _height(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return _from_height * (1.0 - t) + 4.0 * _arc_px * t * (1.0 - t)


## The slime is alive, on the thrower's level, and its middle is within HIT_PX of the thing.
func _meets_slime(air: Vector2) -> bool:
	if _player == null or not is_instance_valid(_player) or bool(_player.call(&"is_dead")):
		return false
	var body := _player.get(&"body") as Node2D
	if body == null or (_level != AbilityWorld.ANY_LEVEL and AbilityWorld.body_level(body) != _level):
		return false
	return (_player.call(&"get_centre") as Vector2).distance_to(air) <= HIT_PX


## It struck the slime: the bouncer's hit, then it breaks there (a sturdy thing drops whole at the
## slime's feet).
func _hit_slime(at: Vector2) -> void:
	if _bouncer != null and is_instance_valid(_bouncer) and _bouncer.has_method(&"bounced_hit"):
		_bouncer.call(&"bounced_hit", at, _direction, _weight)
	_end(at, true)


## The flight ends at `at` (over the ground point it is on): on the slime (`struck`), at a wall or
## where it came down. A sturdy thing (or the Dung Roller's ball) lies there whole where a liftable
## fits; anything else breaks into its own picture with its material's particles and cue.
func _end(at: Vector2, struck: bool) -> void:
	_done = true
	var material := HeldLook.material_of(_held)
	var spot := global_position
	var feel := Services.feel()
	if DungBall.is_ball(_held):
		if struck or DungBall.lay(get_parent(), spot, _held) == null:
			DungBall.broke(_held)
			_shatter(at, material)
		queue_free()
		return
	var kind := str(_held.get("kind", ""))
	var sturdy := ThrowFeel.uses_of(material) > 0 and not LiftableScript.entry(kind).is_empty()
	if sturdy and ThrowAmmo.fits(spot, _feet, _level):
		ThrowAmmo.spawn_liftable(kind, spot, {"variant": int(_held.get("variant", 0)), "weight": str(_held.get("weight", "")),
			"uses": ThrowFeel.uses_left(_held, material), "tint": ThrowFeel.wear_tint(_held, material), "pop": false})
		if feel != null:
			feel.burst(DUST_PRESET, spot)
			feel.audio_cue(_cue, {"pitch": ThrowFeel.rebound_number("landPitch", 1.0),
				"volume_db": ThrowFeel.rebound_number("landVolumeDb", 0.0)})
		queue_free()
		return
	_shatter(at, material)
	queue_free()


func _shatter(at: Vector2, _material: String) -> void:
	if _look is Sprite2D:
		BreakBurst.burst(get_parent(), at, _look as Sprite2D)
	var feel := Services.feel()
	if feel == null:
		return
	for preset: Variant in _particles:
		feel.particles(preset as StringName, at)
	if _cue != &"":
		feel.audio_cue(_cue)


## The slime's bodies (walls are looked for past them).
func _player_rids() -> Array[RID]:
	var rids: Array[RID] = []
	if _player != null and is_instance_valid(_player):
		rids = _player.call(&"body_rids")
	return rids
