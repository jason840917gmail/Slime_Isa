extends Node2D
## A sturdy thrown thing bouncing off (the rebound prototype, game/throw/throw_feel.gd
## `rebound_on`, `gulp.throwFeel.rebound`; owner's material identities, 2026-11-16: stone, metal and
## bone are sturdy; A Link to the Past's ricochet, Yoshi's catch). thrown_object.gd makes one
## instead of shattering when the thing has a use left: it flies from where it struck to its landing
## spot in an arc (`launch`: over `ms`, rising `arc_px`, spinning, its shadow on the ground under
## it), lands with a puff of dust and a thud (its material's break cue, low and quiet: `landPitch`,
## `landVolumeDb`) and lies there as the same thing again, to be sucked in again:
## - a liftable kind: `ThrowAmmo.spawn_liftable` with its kind, look, weight, the hits it has left
##   (`uses`) and its wear tint;
## - a caught enemy shot with its own picture (a skeleton's bone or skull): a spent shot
##   (game/throw/spent_shot.gd) for `shotLifeMs`, with its hits left.
## Where it lands was picked by the sender (a spot a liftable fits on: ThrowAmmo.fits); the landing
## checks once more and steps `clearPx` off the slime if it stands there; a spot that no longer fits
## shatters it (break_burst.gd).
##
## **The mouth catch**: a rebound off an enemy (`catchable`) can be caught from `catchFromMs` after
## the bounce until it lands: mouth_hold.gd asks `nearest_catchable` on a Q press with an empty
## mouth, and Mouth.snap_catch takes it (`take`: it leaves the air at once).
##
## The node sits on the ground point under the flying thing; the look rides above it. Gameplay time
## (the physics step): it waits through the blow's hit-stop at the enemy, then bounces.
##
## Owner: throw combat (the sender).

const Services := preload("res://game/shared/services.gd")
const HeldLook := preload("res://game/player/gulp/held_look.gd")
const BreakBurst := preload("res://game/player/gulp/break_burst.gd")
const LiftableScript := preload("res://game/scripts/liftable.gd")
const ThrowAmmo := preload("res://game/throw/throw_ammo.gd")
const ThrowFeel := preload("res://game/throw/throw_feel.gd")
const SpentShot := preload("res://game/throw/spent_shot.gd")

const GROUP := &"throw-rebound"
const SHADOW := Color(0.0, 0.0, 0.0, 0.28)
## The shadow of a 30 px look on the ground (thrown_object.gd SHADOW_SIZE), and how much smaller it
## is at the top of the arc.
const SHADOW_SIZE := Vector2(12.0, 5.0)
const SHADOW_LOOK_PX := 30.0
const SHADOW_HIGH_SHARE := 0.6
const DUST_PRESET := &"dodge-dust"
const CUE_PITCH_KEY := "pitch"
const CUE_VOLUME_KEY := "volume_db"
## A spent shot lies flat: turned this much.
const SHOT_ANGLE := 0.5

var _held: Dictionary = {}
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _from_height: float = 0.0
var _arc_px: float = 0.0
var _ms: float = 1.0
var _age_ms: float = 0.0
var _look_px: float = 30.0
var _level: int = 0
var _feet: Vector2 = Vector2.ZERO
var _catchable: bool = false
var _spin: float = 0.0
var _cue: StringName = &""
var _look: Node2D
var _done: bool = false


## A rebound of `held` under `parent`: from the ground point `from` (the thing `from_height` over it)
## to `to` over `ms`, rising `arc_px`, its look `look_px` across; `feet` and `level` are the thrower's
## (the landing's height level); `cue` its material's break cue (the thud); `catchable` when the
## mouth may catch it in the air; `spin` its turn (rad/s, signed).
static func launch(parent: Node, held: Dictionary, from: Vector2, from_height: float, to: Vector2, ms: float,
		arc_px: float, look_px: float, feet: Vector2, level: int, cue: StringName, catchable: bool, spin: float) -> Node2D:
	if parent == null:
		return null
	var node := new()
	node.name = "ThrowRebound"
	node._held = held.duplicate()
	node._from = from
	node._to = to
	node._from_height = from_height
	node._arc_px = arc_px
	node._ms = maxf(1.0, ms)
	node._look_px = look_px
	node._feet = feet
	node._level = level
	node._cue = cue
	node._catchable = catchable
	node._spin = spin
	node.z_index = 5
	parent.add_child(node)
	node.global_position = from
	node._look = HeldLook.make(held, look_px)
	node._look.modulate = ThrowFeel.wear_tint(held, HeldLook.material_of(held))
	node.add_child(node._look)
	node._place()
	node.reset_physics_interpolation()
	return node


## The catchable rebound nearest to `feet` within `range_px` of it (its ground point), or null.
static func nearest_catchable(feet: Vector2, range_px: float) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var best: Node = null
	var best_distance := range_px
	for node: Node in tree.get_nodes_in_group(GROUP):
		if not bool(node.call(&"can_catch")):
			continue
		var distance := (node as Node2D).global_position.distance_to(feet)
		if distance <= best_distance:
			best = node
			best_distance = distance
	return best


func _enter_tree() -> void:
	add_to_group(GROUP)


## True while the mouth may catch it: a rebound off an enemy, `catchFromMs` into its flight.
func can_catch() -> bool:
	return _catchable and not _done and _age_ms >= ThrowFeel.rebound_number("catchFromMs", 0.0)


## Caught: it leaves the air; returns what the mouth now holds ({} when it was already gone).
func take() -> Dictionary:
	if _done:
		return {}
	_done = true
	queue_free()
	return _held.duplicate()


## Where the thing itself is now (over its ground point).
func air_point() -> Vector2:
	return global_position - Vector2(0.0, _height())


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age_ms += delta * 1000.0
	_place()
	if _age_ms >= _ms:
		_land()


func _draw() -> void:
	var t := clampf(_age_ms / _ms, 0.0, 1.0)
	var size := SHADOW_SIZE * (_look_px / SHADOW_LOOK_PX) * lerpf(1.0, SHADOW_HIGH_SHARE, 4.0 * t * (1.0 - t))
	var points := PackedVector2Array()
	for i in 16:
		var angle := TAU * i / 16.0
		points.append(Vector2(cos(angle) * size.x, sin(angle) * size.y))
	draw_colored_polygon(points, SHADOW)


func _place() -> void:
	var t := clampf(_age_ms / _ms, 0.0, 1.0)
	global_position = _from.lerp(_to, t)
	if _look != null:
		_look.position = Vector2(0.0, -_height())
		_look.rotation = _spin * _age_ms / 1000.0
	queue_redraw()


## Height over the ground now: from where it struck down to the ground, with the arc's rise.
func _height() -> float:
	var t := clampf(_age_ms / _ms, 0.0, 1.0)
	return _from_height * (1.0 - t) + 4.0 * _arc_px * t * (1.0 - t)


## It comes down: the thing lies at its spot again (off the slime if it stands there), or shatters
## where no body fits any more.
func _land() -> void:
	_done = true
	var spot := _clear_of_slime(_to)
	var material := HeldLook.material_of(_held)
	var feel := Services.feel()
	if not ThrowAmmo.fits(spot, _feet, _level):
		if _look is Sprite2D:
			BreakBurst.burst(get_parent(), spot, _look as Sprite2D, ThrowFeel.block("shards.miss"))
		if feel != null:
			feel.audio_cue(_cue)
		queue_free()
		return
	_lay(spot, material)
	if feel != null:
		feel.burst(DUST_PRESET, spot, Vector2.ZERO, Color.WHITE, ThrowFeel.rebound_number("landDustScale", 1.0))
		feel.audio_cue(_cue, {CUE_PITCH_KEY: ThrowFeel.rebound_number("landPitch", 1.0),
			CUE_VOLUME_KEY: ThrowFeel.rebound_number("landVolumeDb", 0.0)})
	queue_free()


## The thing lying at `spot` again: a liftable of its kind, or (a caught shot with its own picture) a
## spent shot; both carry the hits it has left.
func _lay(spot: Vector2, material: String) -> void:
	var kind := str(_held.get("kind", ""))
	var uses := ThrowFeel.uses_left(_held, material)
	var path: Variant = _held.get("texture")
	if path is String and not (path as String).is_empty():
		var art_px := maxf(1.0, float(_held.get("art_px", _look_px)))
		var shot := SpentShot.spawn(get_parent(), spot - Vector2(0.0, SpentShot.DROP_PX), str(path), art_px, _look_px / art_px,
			SHOT_ANGLE, kind, material, ThrowFeel.rebound_number("shotLifeMs", 0.0))
		if shot != null:
			shot.set_meta(ThrowAmmo.USES_META, uses)
			shot.modulate = ThrowFeel.wear_tint(_held, material)
		return
	if LiftableScript.entry(kind).is_empty():
		return
	ThrowAmmo.spawn_liftable(kind, spot, {"variant": int(_held.get("variant", 0)), "weight": str(_held.get("weight", "")),
		"uses": uses, "tint": ThrowFeel.wear_tint(_held, material), "pop": false})


## `spot`, or a spot `clearPx` from the slime's feet when it stands closer than that (away from it
## along the line to the spot; back along the flight when it stands right on it).
func _clear_of_slime(spot: Vector2) -> Vector2:
	var world := Services.world()
	var body: Node2D = world.player_body if world != null else null
	var clear_px := ThrowFeel.rebound_number("clearPx", 0.0)
	if body == null or not is_instance_valid(body) or clear_px <= 0.0:
		return spot
	var away := spot - body.global_position
	if away.length() >= clear_px:
		return spot
	var unit := away.normalized() if away.length() > 0.5 else (_from - _to).normalized()
	if unit == Vector2.ZERO:
		unit = Vector2.DOWN
	return body.global_position + unit * clear_px
