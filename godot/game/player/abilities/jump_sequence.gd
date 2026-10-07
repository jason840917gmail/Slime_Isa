extends RefCounted
## The jump and the ledge drop: one flight from the start to the landing (abilities spec 5.3;
## docs/godot/ELEVATION.md "Moving between levels").
##
## The flight is worked out in 3D, as the camera sees it: a point on the ground plane (screen feet
## + 64 · level, the depth the occlusion uses) moves evenly from where the slime took off to where
## it lands, and its height (64 · level) falls from the start level to the landing level under
## gravity, over an apex `arc` above the start (`elevation.hopArcHeight` for a hop, which stays below
## one level so it never reaches a higher top; DROP_ARC for a ledge drop's small hop off the edge).
##
## The body itself travels (`owns_body`) on the straight line between the two screen positions, so
## the camera, the hurtbox and the depth follow it evenly; the art rides above it by what gravity
## adds (up first, then down faster: a fall). The shadow lies on the ground under the slime: on the
## start level while it is over it, then on the landing level (at the foot of the wall it falls
## down, or hidden when that ground is behind a hill), shrinking and fading with height. On
## landing: the Land cue, the forced `land` squash, goo dust, a Heavy slime's landing record and,
## with elevation, the body's new level.
##
## intent: {id (&"jump" or &"drop"), start, target (old centres), level_from?, level_to?}.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const AbilityFx := preload("res://game/player/abilities/ability_fx.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")

const DROP := &"drop"
## A jump on one level (Phaser's 420 ms); a drop's base time and time per level of drop come from
## game-constants.json `elevation` (with these fallbacks without elevation).
const JUMP_MS := 420.0
const DROP_ARC := 14.0
const FALLBACK_ARC := 36.0
const STRETCH := Vector2(0.82, 1.35)
const SQUASH := Vector2(1.18, 0.70)
const LEVEL_UNITS := 64.0
## The shadow is drawn over the ground, under the bodies; it shrinks to SHADOW_HIGH_SCALE and fades
## to SHADOW_HIGH_ALPHA (of its own 0.35) at SHADOW_HIGH units above its ground.
const SHADOW_Z := -1
const SHADOW_HIGH := 96.0
const SHADOW_HIGH_SCALE := 0.55
const SHADOW_HIGH_ALPHA := 0.65
const NO_LEVEL := -100

var _player: Node
var _body: CharacterBody2D
var _intent: Dictionary
var _started_ms: float = 0.0
var _duration_ms: float = JUMP_MS
var _start_feet := Vector2.ZERO
var _landing_feet := Vector2.ZERO
var _to_centre := Vector2.ZERO
var _from_level := 0
var _to_level := 0
## Gravity's share of the height: height(t) = lerp(start, landing, t) + _lift · t · (1 − t), the
## parabola that rises `arc` over the start and ends at the landing.
var _lift: float = 4.0 * FALLBACK_ARC
var _landed: bool = false
var _shadow: Node2D


func begin(player: Node, intent: Dictionary, now_ms: float) -> void:
	_player = player
	_intent = intent
	_started_ms = now_ms
	_body = player.get(&"body") as CharacterBody2D
	var start: Vector2 = intent["start"]
	var target: Vector2 = intent["target"]
	_to_centre = start - _body.global_position if _body != null else Vector2.ZERO
	_start_feet = start - _to_centre
	_landing_feet = target - _to_centre
	_from_level = int(intent.get("level_from", 0))
	_to_level = int(intent.get("level_to", _from_level))
	var drop := maxi(0, _from_level - _to_level)
	var dropping := StringName(intent.get("id", &"")) == DROP
	var arc := FALLBACK_ARC
	_duration_ms = JUMP_MS
	if _elevation() != null:
		arc = DROP_ARC if dropping else Elevation.setting("hopArcHeight")
		var base: float = Elevation.setting("dropBaseMs") if dropping else JUMP_MS
		_duration_ms = base + Elevation.setting("dropMsPerLevel") * float(drop)
	_lift = lift(arc, float(drop) * LEVEL_UNITS)
	if not dropping:
		_player.call(&"action_cue", &"Jump")
	_player.call(&"play_animation", "hop")
	_player.call(&"stop_movement")
	_player.call(&"reset_effects")
	_shadow = AbilityFx.jump_shadow(_start_feet)
	if _shadow != null:
		_shadow.z_index = SHADOW_Z
	_place(0.0)


## The lift of a flight that rises `arc` over its start and ends `fall` lower: with gravity g and
## take-off speed v (time 0..1), v² = 2g · arc and v − g/2 = −fall; the lift is g/2 = v + fall.
static func lift(arc: float, fall: float) -> float:
	var speed := 2.0 * arc + 2.0 * sqrt(arc * arc + arc * fall)
	return speed + fall


## The flight places the body itself every step.
func owns_body() -> bool:
	return not _landed


func advance(now_ms: float) -> bool:
	if _landed:
		return true
	var t := clampf((now_ms - _started_ms) / _duration_ms, 0.0, 1.0)
	_place(t)
	if t >= 1.0:
		_land()
	return _landed


## Teardown: put the body down where it was going (never left halfway over a ledge).
func cancel() -> void:
	if not _landed:
		_place(1.0)
		_finish_level()
		if _body != null and is_instance_valid(_body):
			_body.reset_physics_interpolation()
	_landed = true
	_free_shadow()
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")


func _place(t: float) -> void:
	if _body == null or not is_instance_valid(_body):
		return
	var feet := _start_feet.lerp(_landing_feet, t)
	_body.global_position = feet
	_body.velocity = Vector2.ZERO
	# The art: gravity's share of the height over the body, stretched rising, squashed falling.
	var above := _lift * t * (1.0 - t)
	_player.call(&"set_effect_offset", Vector2(0.0, -above))
	var stretch := Vector2.ONE.lerp(STRETCH, t * 2.0) if t < 0.5 else STRETCH.lerp(SQUASH, (t - 0.5) * 2.0)
	_player.call(&"set_effect_scale", stretch)
	var elevation := _elevation()
	var depth := lerpf(_start_feet.y + float(_from_level) * LEVEL_UNITS, _landing_feet.y + float(_to_level) * LEVEL_UNITS, t)
	if elevation != null:
		elevation.set_flight(_body, depth)
	_place_shadow(feet, depth, lerpf(float(_from_level), float(_to_level), t) * LEVEL_UNITS + above, elevation)


## The shadow on the ground under the slime: the ground point at `depth` on the start level while
## that level is seen there, else on the landing level; hidden when neither is (behind a hill).
func _place_shadow(feet: Vector2, depth: float, height: float, elevation: Elevation) -> void:
	if _shadow == null or not is_instance_valid(_shadow):
		return
	var at := feet
	var ground_level := _from_level
	if elevation != null:
		ground_level = NO_LEVEL
		for level: int in [_from_level, _to_level]:
			var point := Vector2(feet.x, depth - float(level) * LEVEL_UNITS)
			if elevation.level_at(point, NO_LEVEL) == level:
				at = point
				ground_level = level
				break
	_shadow.visible = ground_level != NO_LEVEL
	_shadow.global_position = at
	var high := clampf((height - float(ground_level) * LEVEL_UNITS) / SHADOW_HIGH, 0.0, 1.0)
	_shadow.scale = Vector2.ONE * lerpf(1.0, SHADOW_HIGH_SCALE, high)
	_shadow.modulate.a = lerpf(1.0, SHADOW_HIGH_ALPHA, high)


func _land() -> void:
	_landed = true
	_place(1.0)
	_finish_level()
	_free_shadow()
	var target := _landing_feet + _to_centre
	_player.call(&"reset_effects")
	_player.call(&"action_cue", &"Land")
	_player.call(&"squash", &"land", true)
	_player.call(&"record_landing", target)
	AbilityFx.goo_dust(target)


func _finish_level() -> void:
	var elevation := _elevation()
	if elevation == null or _body == null or not is_instance_valid(_body):
		return
	elevation.end_flight(_body)
	elevation.track(_body, _to_level)


func _free_shadow() -> void:
	if _shadow != null and is_instance_valid(_shadow):
		_shadow.queue_free()
	_shadow = null


func _elevation() -> Elevation:
	var world := Services.world()
	return world.elevation if world != null else null
