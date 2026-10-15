extends RefCounted
## The stairs walk (docs/godot/ELEVATION.md "Stairs walk"; owner, 2026-10-14: stairs "should feel
## like a transition, similar to Zelda ... it take longer to cross them than normal terrain").
##
## Stepping onto a flight of stairs along it (player.gd `_enter_stairs`) hands the slime to this: it
## is carried to the far end, up or down, and cannot stop, turn back or act on the way. It keeps the
## line across the flight it came in on (the flight's t) and goes up or down in footsteps of
## `elevation.stairsFootstepMs`, each covering `elevation.stairsPerFootstep` stairs (4 a level): a
## footstep eases in (smoothstep) under a small hop of `elevation.stairsStepBob` and lands with the
## StairsStep cue (owner, 2026-10-14, of two paces tried: slower footsteps with one hop and one sound
## each, rather than a hop on every stair with the sound on its own pace). Then it walks
## `elevation.stairsExit` units off the end over `elevation.stairsExitMs`. Its depth follows the
## steps (the stairs' frame: hidden behind what a body there would be), its level stays the one it
## came from until it steps off, where it takes the level of that end.
##
## intent: {id (&"stairs"), flight (ElevationStairs, never a ramp), down (bool)}.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const ElevationStairs := preload("res://game/world/elevation/elevation_stairs.gd")

const ID := &"stairs"
const CLIP_WALK := "walk"
const CUE_STEP := &"StairsStep"
## The height of one step (world units: a level is 64, four steps).
const RISE := ElevationStairs.LEVEL / ElevationStairs.STEPS_PER_LEVEL

var _player: Node
var _body: CharacterBody2D
var _flight: ElevationStairs
var _elevation: Elevation
var _started_ms: float = 0.0
## The flight's frame (s, h above its lower ground) where the steps start, end and the walk off
## ends, and the line across it (t).
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _off := Vector2.ZERO
var _t := 0.0
## The stairs it crosses, and the footsteps it takes over them and their length.
var _steps := 1
var _footsteps := 1
var _footstep_ms := 400.0
var _exit_ms := 160.0
var _bob := 3.0
var _to_level := 0
var _cued := 0
var _done := false


func begin(player: Node, intent: Dictionary, now_ms: float) -> void:
	_player = player
	_started_ms = now_ms
	_body = player.get(&"body") as CharacterBody2D
	_flight = intent["flight"] as ElevationStairs
	var world := Services.world()
	_elevation = world.elevation if world != null else null
	if _body == null or _flight == null or _elevation == null:
		_done = true
		return
	var down := bool(intent.get("down", true))
	_exit_ms = Elevation.setting("stairsExitMs")
	_bob = Elevation.setting("stairsStepBob")
	var exit := Elevation.setting("stairsExit")
	var height := ElevationStairs.LEVEL * (_flight.top - _flight.bottom)
	var local := _body.global_position - _elevation.global_position
	var st := _flight.st_at(local)
	if is_nan(st.x):
		st = Vector2(0.0, 0.0)
	# Keep off the side walls (and a front flight's posts): the body is about 26 units wide.
	_t = clampf(st.y, -maxf(0.0, _flight.half - 14.0), maxf(0.0, _flight.half - 14.0))
	var h := _flight.height_at(local)
	if is_nan(h):
		h = height if down else 0.0
	_from = Vector2(st.x, h)
	if _flight.in_face:
		_to = Vector2(0.0, 0.0) if down else Vector2(0.0, height)
		_off = Vector2(exit, 0.0) if down else Vector2(-exit, height)
	else:
		_to = Vector2(_flight.end, 0.0) if down else Vector2(0.0, height)
		_off = Vector2(_flight.end + exit, 0.0) if down else Vector2(-exit, height)
	_steps = maxi(1, ceili(absf(_to.y - _from.y) / RISE - 0.25))
	_footsteps = maxi(1, ceili(_steps / maxf(Elevation.setting("stairsPerFootstep"), 1.0)))
	_footstep_ms = maxf(Elevation.setting("stairsFootstepMs"), 1.0)
	_to_level = _flight.bottom if down else _flight.top
	# Facing the way it walks on the ground: down the flight, or back up it.
	var facing := _flight.dir if down else -_flight.dir
	_player.call(&"stop_movement")
	_player.call(&"reset_effects")
	_player.call(&"face", facing)
	_player.call(&"play_animation", CLIP_WALK)
	_place(_from, 0.0)


## The walk places the body itself every step.
func owns_body() -> bool:
	return not _done


func advance(now_ms: float) -> bool:
	if _done:
		return true
	var elapsed := now_ms - _started_ms
	var steps_ms := _footsteps * _footstep_ms
	if elapsed < steps_ms:
		# Footstep by footstep: each eases in (smoothstep) under a little hop and lands with the cue.
		var p := elapsed / _footstep_ms
		var k := floori(p)
		var f := p - k
		var eased := (k + f * f * (3.0 - 2.0 * f)) / _footsteps
		_cue_footsteps(k)
		_place(_from.lerp(_to, eased), _bob * sin(PI * f))
		_player.call(&"play_animation", CLIP_WALK)
		return false
	_cue_footsteps(_footsteps)
	var u := clampf((elapsed - steps_ms) / maxf(_exit_ms, 1.0), 0.0, 1.0)
	_place(_to.lerp(_off, u), 0.0)
	if u >= 1.0:
		_finish()
	return _done


## Teardown (a travel, death): the body steps off at the far end, never left on the stairs.
func cancel() -> void:
	if not _done:
		_place(_off, 0.0)
		_finish()


## The StairsStep cue for each footstep landed so far (`landed` footsteps).
func _cue_footsteps(landed: int) -> void:
	while _cued < mini(landed, _footsteps):
		_cued += 1
		_player.call(&"action_cue", CUE_STEP)


## The body at the flight's frame point (s, h) on its line, the art `lift` units over it.
func _place(sh: Vector2, lift: float) -> void:
	if _body == null or not is_instance_valid(_body):
		return
	var p := Vector3(sh.x, _t, sh.y)
	_body.global_position = _flight.screen_of(p) + _elevation.global_position
	_body.velocity = Vector2.ZERO
	_player.call(&"set_effect_offset", Vector2(0.0, -lift))
	# Its depth: the ground under it in the stairs' frame (a front flight's face plane).
	_elevation.set_flight(_body, _flight.world(p).y + _elevation.global_position.y)


func _finish() -> void:
	_done = true
	if _player != null and is_instance_valid(_player):
		_player.call(&"reset_effects")
	if _body == null or not is_instance_valid(_body) or _elevation == null:
		return
	_elevation.end_flight(_body)
	_elevation.track(_body, _to_level)
	_body.reset_physics_interpolation()
