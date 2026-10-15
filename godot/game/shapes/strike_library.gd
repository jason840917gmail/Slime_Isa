extends RefCounted
## The body shapes' strike files (docs/design/2026-10-12-weapon-strike-frames.md, rounds 4 and 5): one
## StrikeAnimation per strike in `res://game/characters/strikes/<strike>.tres` (strike_animation.gd,
## strike_direction.gd, strike_key.gd). Static helpers, used by the game and by the Inspector's live preview
## (addons/strike_preview; no autoloads, so they run in the editor):
## - `state_at` / `state_at_unit`: what a strike shows at a time (the body frame, the weapon's pose, the hit's
##   numbers): held values from the key at or before, angle, length and head angle sliding to the next key (or
##   snapping there when it jumps);
## - `unit_at`: the strike's 0-3 time for the gameplay's elapsed ms and the step's windup, active and recovery;
## - `socket`, `contact_socket`: where the weapon leaves the body (the art's point plus the file's nudge);
## - `hit_reach`, `hit_center`, `chain_hit`: the chain steps' reach and where it is measured from, which only the
##   strike files hold;
## - `build_library` / `install`: the AnimationLibrary the player's AnimationPlayer plays as `strikes`, one
##   animation per strike and direction (`strikes/<strike>-<direction>`, 3.0 units long: the body frame and the
##   Visual's texture, offset and mirror) and its hold (`strikes/<strike>-<direction>-hold`: the frame it starts
##   on, held while a charge ring fills before a charge that plays the strike; ShapeController.held_pose_clip);
## - `step_data` / `timing_of`: the chain step or charge a strike plays, read from game-constants.json directly.
## The files are read through their properties (not their methods), so they work wherever they are loaded.
##
## Owner: shapes.

const ShapeStrikes := preload("res://game/shapes/shape_strikes.gd")
const AnimationType := preload("res://game/shapes/strike_animation.gd")
const DirectionType := preload("res://game/shapes/strike_direction.gd")
const KeyType := preload("res://game/shapes/strike_key.gd")

const DIRECTORY := "res://game/characters/strikes/"
const CONSTANTS_PATH := "res://game/data/game-constants.json"
## The strike's clock: windup 0 to 1, active 1 to 2, recovery 2 to 3 (the end held).
const UNITS := 3.0
const CONTACT_UNIT := 1.0
const ACTIVE_END_UNIT := 2.0
const MARKER_CONTACT := &"contact"
const MARKER_ACTIVE_END := &"active_end"
const STRIKES: Array[String] = ["spear-jab", "spear-finisher", "axe-sweep", "axe-backswing", "axe-chop", "hammer-thud",
	"hammer-boom"]
const DIRECTIONS: Array[String] = ["side", "down", "up"]
const COLUMNS := 8
## The sampling step of the built animations' editor view (units).
const STEP_UNITS := 0.01
## A query this close (units) to a key counts as on it (float rounding at an exact millisecond).
const UNIT_SLACK := 0.000000001

static var _animations: Dictionary = {}
static var _library: AnimationLibrary = null
static var _constants: Dictionary = {}
## The chain steps already reported without a reach (one error each, not one per hit).
static var _reported: Dictionary = {}


## The strike's resource (`strike` as in STRIKES, e.g. "axe-chop"); null when the file is missing.
static func animation(strike: String) -> AnimationType:
	if not _animations.has(strike):
		var path := "%s%s.tres" % [DIRECTORY, strike]
		_animations[strike] = load(path) as AnimationType if not strike.is_empty() and ResourceLoader.exists(path) else null
	return _animations[strike]


## The direction `name` ("side", "down", "up") of `resource`; null when it has none.
static func direction_of(resource: AnimationType, name: String) -> DirectionType:
	if resource == null or not name in DIRECTIONS:
		return null
	return resource.get(name) as DirectionType


## A key's time on the 0-3 clock (its `phase` plus its `share`).
static func key_unit(key: KeyType) -> float:
	return float(key.phase) + clampf(key.share, 0.0, 1.0)


## The strike a resource plays, from its `shape` and `step` ("axe-chop", "spear-finisher", ...); "" when unknown.
static func strike_of(resource: AnimationType) -> String:
	if resource == null:
		return ""
	return ShapeStrikes.strike_for(resource.shape, {"id": resource.step})


## The chain step or charge a strike plays (game-constants.json: its windupMs, activeMs, recoveryMs); {} when none.
static func step_data(resource: AnimationType) -> Dictionary:
	if resource == null or resource.step.is_empty():
		return {}
	_read_constants()
	var shapes: Variant = _constants.get("shapes", {})
	var block: Variant = (shapes as Dictionary).get(resource.shape, {}) if shapes is Dictionary else {}
	if not block is Dictionary:
		return {}
	for step: Variant in (block as Dictionary).get("chain", []):
		if step is Dictionary and str((step as Dictionary).get("id", "")) == resource.step:
			return step
	var charge: Variant = (block as Dictionary).get("charge", {})
	if charge is Dictionary and str((charge as Dictionary).get("id", "")) == resource.step:
		return charge
	return {}


## The step's (windup, active, recovery) ms as a Vector3 (zero when the step is unknown).
static func timing_of(resource: AnimationType) -> Vector3:
	var data := step_data(resource)
	if data.is_empty():
		return Vector3.ZERO
	return Vector3(float(data.get("windupMs", 0.0)), float(data.get("activeMs", 0.0)), float(data.get("recoveryMs", 0.0)))


## The strike's 0-3 time for `elapsed_ms` of a step with `step_timing` (windup, active, recovery ms): the windup
## onto 0..1, the active window onto 1..2, the recovery onto 2..3 (each linear; the end held).
static func unit_at(elapsed_ms: float, step_timing: Vector3) -> float:
	if elapsed_ms <= 0.0:
		return 0.0
	var windup := maxf(0.0, step_timing.x)
	var active := maxf(0.0, step_timing.y)
	var recovery := maxf(0.0, step_timing.z)
	if elapsed_ms < windup:
		return elapsed_ms / windup
	if elapsed_ms < windup + active:
		return CONTACT_UNIT + (elapsed_ms - windup) / maxf(0.001, active)
	if recovery <= 0.0:
		return UNITS
	return minf(UNITS, ACTIVE_END_UNIT + (elapsed_ms - windup - active) / recovery)


## What `direction` of `resource` shows `elapsed_ms` into a step of `step_timing`: see state_at_unit.
static func state_at(resource: AnimationType, direction: String, elapsed_ms: float, step_timing: Vector3) -> Dictionary:
	return state_at_unit(resource, direction, unit_at(elapsed_ms, step_timing))


## What `direction` of `resource` shows at `unit` (0-3): {"frame" (strip frame 1-6), "angle", "length",
## "layer" (0 behind, 1 front), "view", "view_frame", "head_angle", "arm_px", "hit_reach", "hit_center", "flip_h",
## "spear_inside", "spear_fade", "spear_shaft"}. The keys before `unit` decide: held values from the key at or
## before it; angle, length and head angle slide to the next key, or hold while it jumps; before the first
## key, the first key's values; after the last, the last key's.
static func state_at_unit(resource: AnimationType, direction: String, unit: float) -> Dictionary:
	var spec := direction_of(resource, direction)
	var state := {"frame": 1, "angle": 0.0, "length": 0.0, "layer": 0, "view": "side", "view_frame": 1, "head_angle": 0.0,
		"arm_px": 0.0, "hit_reach": 0.0, "hit_center": Vector2.ZERO, "flip_h": false, "spear_inside": 0.0,
		"spear_fade": 0.0, "spear_shaft": 0.0}
	if spec == null:
		return state
	state["arm_px"] = spec.arm_px
	state["hit_reach"] = spec.hit_reach
	state["hit_center"] = spec.hit_center
	state["flip_h"] = spec.flip_h
	state["spear_inside"] = spec.spear_inside
	state["spear_fade"] = spec.spear_fade
	state["spear_shaft"] = spec.spear_shaft
	var keys: Array[KeyType] = spec.keys
	if keys.is_empty():
		return state
	var index := -1
	for position in keys.size():
		if keys[position] != null and key_unit(keys[position]) <= unit + UNIT_SLACK:
			index = position
	var key: KeyType = keys[maxi(index, 0)]
	if key == null:
		return state
	state["frame"] = key.frame
	state["layer"] = int(key.layer)
	state["view"] = key.view
	state["view_frame"] = key.view_frame
	var angle := key.angle
	var length := key.length
	var head := key.head_angle
	if index >= 0 and index + 1 < keys.size() and keys[index + 1] != null and not keys[index + 1].jump:
		var next: KeyType = keys[index + 1]
		var span := key_unit(next) - key_unit(key)
		if span > 0.0:
			var share := clampf((unit - key_unit(key)) / span, 0.0, 1.0)
			angle = lerpf(key.angle, next.angle, share)
			length = lerpf(key.length, next.length, share)
			head = lerpf(key.head_angle, next.head_angle, share)
	state["angle"] = angle
	state["length"] = length
	state["head_angle"] = head
	return state


## Where the weapon leaves the body on body frame `number` (1-6) of `direction`: the art's socket (game px from the
## slime's centre, unmirrored; ShapeStrikes.socket_game) plus the direction's `socket_nudge` for that frame.
## Vector2.INF when the art has none.
static func socket(resource: AnimationType, direction: String, number: int) -> Vector2:
	var at := ShapeStrikes.socket_game(strike_of(resource), direction, number, false)
	var spec := direction_of(resource, direction)
	if not at.is_finite() or spec == null or number < 1 or number > spec.socket_nudge.size():
		return at
	return at + spec.socket_nudge[number - 1]


## The weapon's socket at the strike's contact (the windup's end): where the Spear's line starts. Vector2.INF
## without one.
static func contact_socket(resource: AnimationType, direction: String) -> Vector2:
	if resource == null:
		return Vector2.INF
	return socket(resource, direction, int(state_at_unit(resource, direction, CONTACT_UNIT)["frame"]))


## The hit's reach of `direction` (game px): the Axe's radius, the Hammer's offset, the Spear's line; 0 without one.
static func hit_reach(resource: AnimationType, direction: String) -> float:
	var spec := direction_of(resource, direction)
	return spec.hit_reach if spec != null else 0.0


## Where the hit of `direction` is measured from (game px from the slime's centre, unmirrored); zero without one.
static func hit_center(resource: AnimationType, direction: String) -> Vector2:
	var spec := direction_of(resource, direction)
	return spec.hit_center if spec != null else Vector2.ZERO


## `hit_center` as the strike shows it: x mirrored while the strip shows flipped (a left side strike, `mirrored`,
## or a mirrored strip; ShapeStrikes.shown_flipped), as the sockets are.
static func shown_hit_center(resource: AnimationType, direction: String, mirrored: bool) -> Vector2:
	var centre := hit_center(resource, direction)
	if ShapeStrikes.shown_flipped(flip_h(resource, direction), mirrored):
		centre.x = -centre.x
	return centre


## A chain step's numbers (`data`, a step of the shape `short`) hitting toward `direction` ("side", "down", "up")
## with its strike file's `hit_reach` (an arc's radius, a circle's offset, a line's reach) measured from its
## `hit_center` (`ShapeStrikes.HIT_CENTER_KEY`, mirrored for a left side strike, `mirrored`, and a mirrored
## strip): game-constants.json holds no reach for the chain steps. Always a copy. A missing strike file or reach
## is an error, once per step and direction, and the copy then has no reach.
static func chain_hit(short: String, data: Dictionary, direction: String, mirrored: bool = false) -> Dictionary:
	var strike := ShapeStrikes.strike_for(short, data)
	var resource := animation(strike)
	var reach := hit_reach(resource, direction)
	if reach > 0.0:
		var out := ShapeStrikes.apply_hit_reach(data, reach).duplicate()
		var centre := shown_hit_center(resource, direction, mirrored)
		if centre != Vector2.ZERO:
			out[ShapeStrikes.HIT_CENTER_KEY] = centre
		return out
	var key := "%s/%s/%s" % [short, str(data.get("id", "")), direction]
	if not _reported.has(key):
		_reported[key] = true
		push_error("StrikeLibrary: the %s step \"%s\" has no hit_reach for %s (%s%s.tres): it hits with no reach" % [
			short, str(data.get("id", "")), direction, DIRECTORY, strike if not strike.is_empty() else "?"])
	return data.duplicate()


## True when `direction` of `resource` shows its strip mirrored (DirectionType.flip_h).
static func flip_h(resource: AnimationType, direction: String) -> bool:
	var spec := direction_of(resource, direction)
	return spec != null and spec.flip_h


## The AnimationLibrary of every strike and direction (built once, cached): `strikes/<strike>-<direction>`, 3.0
## units long, with the body frame (`Visual:frame`, the sheet index: the strip's row * 8 + frame - 1, a key per
## key), `Visual:texture`, `Visual:hframes`, `Visual:vframes`, `Visual:offset` (the sheet's origin) and
## `Visual:flip_h` (the direction's mirror), the markers contact (1.0) and active_end (2.0); and its hold
## `strikes/<strike>-<direction>-hold` (`_hold_of`), except for a mirrored strip (the backswing's down and up).
static func build_library() -> AnimationLibrary:
	if _library != null:
		return _library
	var library := AnimationLibrary.new()
	for strike: String in STRIKES:
		var resource := animation(strike)
		if resource == null:
			push_error("StrikeLibrary: %s%s.tres is missing" % [DIRECTORY, strike])
			continue
		for direction: String in DIRECTIONS:
			var spec := direction_of(resource, direction)
			if spec == null or spec.keys.is_empty():
				continue
			library.add_animation(ShapeStrikes.animation_name(strike, direction), _animation_of(strike, direction, spec))
			# The player's own flip (the facing's) would show a mirrored strip's hold unmirrored; no charge holds one.
			if not spec.flip_h:
				library.add_animation(ShapeStrikes.hold_name(strike, direction), _hold_of(strike, direction, resource))
	_library = library
	return _library


## Installs the built library on `player` as `strikes` (replacing any library of that name).
static func install(player: AnimationPlayer) -> void:
	if player == null:
		return
	if player.has_animation_library(ShapeStrikes.ANIMATION_LIBRARY):
		player.remove_animation_library(ShapeStrikes.ANIMATION_LIBRARY)
	player.add_animation_library(ShapeStrikes.ANIMATION_LIBRARY, build_library())


static func _animation_of(strike: String, direction: String, spec: DirectionType) -> Animation:
	var animation_out := _sheet_animation(strike, UNITS)
	animation_out.add_marker(MARKER_CONTACT, CONTACT_UNIT)
	animation_out.add_marker(MARKER_ACTIVE_END, ACTIVE_END_UNIT)
	animation_out.track_insert_key(_discrete_track(animation_out, "Visual:flip_h"), 0.0, spec.flip_h)
	var frame_track := _discrete_track(animation_out, "Visual:frame")
	var row := ShapeStrikes.row(strike, direction)
	for key: KeyType in spec.keys:
		animation_out.track_insert_key(frame_track, key_unit(key), row * COLUMNS + key.frame - 1)
	return animation_out


## The strike's hold in `direction`: the body frame its animation starts on (`state_at_unit` at 0) on the strike's
## sheet, one step long and played once, so it stays. It keys no mirror: the player flips it for its facing as the
## strike's `-side` (PlayerScript._flip_for), and the release goes on from the same frame.
static func _hold_of(strike: String, direction: String, resource: AnimationType) -> Animation:
	var hold := _sheet_animation(strike, STEP_UNITS)
	var first := int(state_at_unit(resource, direction, 0.0)["frame"])
	var frame := ShapeStrikes.row(strike, direction) * COLUMNS + first - 1
	hold.track_insert_key(_discrete_track(hold, "Visual:frame"), 0.0, frame)
	return hold


## A one-shot animation `length` units long keying the strike's sheet on the Visual at 0: `Visual:texture`, the
## sheet's grid (`Visual:hframes`, `Visual:vframes`) and `Visual:offset` (the sheet's origin).
static func _sheet_animation(strike: String, length: float) -> Animation:
	var animation_out := Animation.new()
	animation_out.length = length
	animation_out.loop_mode = Animation.LOOP_NONE
	animation_out.step = STEP_UNITS
	var fixed := {"Visual:texture": load(ShapeStrikes.texture_path(strike)) as Texture2D, "Visual:hframes": COLUMNS,
		"Visual:vframes": COLUMNS, "Visual:offset": -ShapeStrikes.origin()}
	for path: String in fixed:
		animation_out.track_insert_key(_discrete_track(animation_out, path), 0.0, fixed[path])
	return animation_out


static func _discrete_track(animation_out: Animation, path: String) -> int:
	var track := animation_out.add_track(Animation.TYPE_VALUE)
	animation_out.track_set_path(track, NodePath(path))
	animation_out.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	animation_out.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
	animation_out.track_set_interpolation_loop_wrap(track, false)
	return track


static func _read_constants() -> void:
	if _constants.is_empty() and FileAccess.file_exists(CONSTANTS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONSTANTS_PATH))
		_constants = parsed if parsed is Dictionary else {}
