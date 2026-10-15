extends Camera2D
class_name WorldCamera
## The world camera (Phaser `presentation/ResponsiveCameraController.ts`, `CameraMotion.ts`,
## `CameraZoom.ts`, `WorldScene.createCamera / bindHotkeys`). World spec section 4.
##
## Node setup in `_ready` (world spec 4.1): ANCHOR_MODE_DRAG_CENTER, no position smoothing, no
## drag margins, Godot limits left at defaults (clamping is done here), ignore_rotation,
## process_callback IDLE, physics_interpolation_mode OFF, PROCESS_MODE_ALWAYS (keeps following
## and shaking through hit-stop and pause), process_priority 100 (after gameplay `_process`).
## The script keeps its own `center` and writes `global_position = center`, `zoom = (z, z)`.
## Presentation literals stay here as consts (not balance values).
##
## The play area (HUD console, docs/design/2026-10-07-hud-console-mockup.md): `bottom_inset` screen
## units at the bottom of the view belong to the HUD console (main.gd sets it). Everything the
## camera decides (follow, deadzone, bounds, the fixed hold, pixel rounding) works on the play area
## above it, and `center` is the play area's centre; the Camera2D itself sits half the inset lower,
## so the console covers only what lies under it and a map's south edge stops at its top.
##
## Body-shapes rework (combat-feel plan section 6 "Camera", section 8 `world/world_camera.gd`;
## docs/godot/BODY_SHAPES.md "Juice"): a trauma shake and a kick, both on real time, ADDED to the
## old shake's offset (the old `shake` is unchanged and still runs on its own):
## - `add_trauma(amount, direction)`: trauma += amount (capped at 1); every frame the shake is
##   trauma^`exponent` x `maxOffsetPx` screen px of smooth FastNoiseLite noise sampled at
##   `noiseHz`, `directionalShare` of it along the last hit's axis and the rest in any direction;
##   trauma decays by `decayPerS` per second (`combat.trauma` in game-constants.json).
## - `kick(px, direction)`: the picture jolts `px` screen px along `direction` and eases back
##   (KICK_OUT_MS, KICK_RETURN_MS); a new kick replaces the running one.
## GameFeel calls both (it applies reduce motion and the screen-shake slider).
##
## Owner: world builder (trauma and kick: juice).

const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const Services := preload("res://game/shared/services.gd")

## Kick (presentation): the jolt reaches its full size in KICK_OUT_MS and eases back in
## KICK_RETURN_MS (real ms).
const KICK_OUT_MS := 30.0
const KICK_RETURN_MS := 120.0
## Trauma noise channels: the free shake's x and y and the directional one sample the same noise
## this far apart.
const TRAUMA_CHANNEL_SPACING := 97.0

const ZOOM_LEVELS: Array[float] = [0.5, 0.625, 0.75, 0.875, 1.0, 1.125, 1.25]
const DEFAULT_ZOOM := 1.0
const DAMPING_RATE := 12.0
const ZOOM_EPSILON := 0.000001
## Deadzone (screen px): width clamp(vp.x * 0.18, 128, 224), height clamp(vp.y * 0.14, 96, 160).
const DEADZONE_WIDTH_RATIO := 0.18
const DEADZONE_WIDTH_MIN := 128.0
const DEADZONE_WIDTH_MAX := 224.0
const DEADZONE_HEIGHT_RATIO := 0.14
const DEADZONE_HEIGHT_MIN := 96.0
const DEADZONE_HEIGHT_MAX := 160.0
## Damping delta cap (ms).
const MAX_DAMPING_DELTA_MS := 100.0
## Phaser `roundPixels` at integer zoom (world spec 4.4): snap 2D transforms/vertices to pixels
## and round the rendered camera position. Set false if it jitters with physics interpolation.
const ROUND_PIXELS_AT_INTEGER_ZOOM := true

## A followed-root jump longer than this between two physics ticks is a teleport (respawn) and
## is not interpolated.
const TELEPORT_DISTANCE := 256.0

const MODE_FOLLOW := "follow"
const MODE_FIXED := "fixed"

## Camera centre in world units (the clamped value of the last frame).
var center: Vector2 = Vector2.ZERO
## Requested zoom (one of ZOOM_LEVELS in follow mode).
var target_zoom: float = DEFAULT_ZOOM
## "follow" or "fixed" (world definition camera_mode).
var camera_mode: String = "follow"
## True while following `follow_target`.
var following: bool = false
## The followed root (the player body). The aim point is its old Phaser position
## (feet - depth_anchor) as drawn this frame (see get_target_draw_position()).
var follow_target: Node2D
## Camera bounds (world rect). Removed in fixed mode.
var bounds: Rect2 = Rect2()
var use_bounds: bool = true
## Screen units at the bottom of the view kept for the HUD console (0 = the whole view).
var bottom_inset: float = 0.0:
	set(value):
		bottom_inset = maxf(0.0, value)
		if is_inside_tree():
			_update_deadzone()
			center_on(center)

var _deadzone: Vector2 = Vector2.ZERO
var _round_pixels: bool = false
## Shake state (real time, ms).
var _shake_until_ms: float = -1.0
var _shake_intensity: float = 0.0
## Pan state (real time, ms); `_pan_duration_ms <= 0` = no pan running.
var _pan_from: Vector2 = Vector2.ZERO
var _pan_to: Vector2 = Vector2.ZERO
var _pan_start_ms: float = 0.0
var _pan_duration_ms: float = 0.0
var _pan_resume_follow: bool = false
## Physics-tick positions of the followed root (see get_target_draw_position()).
var _target_prev: Vector2 = Vector2.ZERO
var _target_curr: Vector2 = Vector2.ZERO
var _has_snapshot: bool = false
## Rework trauma shake (0..1), its axis (unit; ZERO = none), the real ms of its last decay step and
## the noise it samples (made on the first trauma).
var _trauma: float = 0.0
var _trauma_axis: Vector2 = Vector2.ZERO
var _trauma_last_ms: float = 0.0
var _trauma_noise: FastNoiseLite
## Rework kick: its full offset (screen px, along the hit) and the real ms it started (< 0 = none).
var _kick: Vector2 = Vector2.ZERO
var _kick_start_ms: float = -1.0


## Interpolation OFF before the node enters the tree: Camera2D checks it on tree entry and
## would otherwise warn "overridden to physics process mode" (main.tscn sets it too).
func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Node setup as described above.
func _ready() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	position_smoothing_enabled = false
	rotation_smoothing_enabled = false
	drag_horizontal_enabled = false
	drag_vertical_enabled = false
	ignore_rotation = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	process_physics_priority = 100
	enabled = true
	make_current()
	_update_deadzone()
	apply_zoom(target_zoom)


## Stores the world rect and camera mode; follow mode: bounds on, `reset_zoom()`; fixed mode:
## `hold_fixed()` (OUT for level-1, world spec 4.6).
func setup(world_rect: Rect2, mode: String) -> void:
	bounds = world_rect
	camera_mode = MODE_FIXED if mode == MODE_FIXED else MODE_FOLLOW
	if camera_mode == MODE_FIXED:
		hold_fixed()
	else:
		use_bounds = bounds.size.x > 0.0 and bounds.size.y > 0.0
		reset_zoom()


## Starts following `target`; `snap` centres immediately on the target's old Phaser position
## (world spec 1.2 step 8). No-op in fixed mode.
func start_follow(target: Node2D, snap: bool = true) -> void:
	if camera_mode == MODE_FIXED:
		return
	if target != follow_target:
		_has_snapshot = false
	follow_target = target
	following = target != null
	_pan_duration_ms = 0.0
	if following and snap:
		center_on(_target_point())
		reset_smoothing()
		force_update_scroll()


## Stops following (camera stays where it is).
func stop_follow() -> void:
	following = false


## Follow update every rendered frame (world spec 4.3): deadzone per axis, exponential damping
## `1 - exp(-12 * min(delta_ms, 100) / 1000)`, then `center_on()`; also advances shake/pan.
func _process(delta: float) -> void:
	var now := float(Time.get_ticks_msec())
	_update_deadzone()
	if _pan_duration_ms > 0.0:
		_advance_pan(now)
	elif following and is_instance_valid(follow_target):
		var target := _target_point()
		var z := maxf(target_zoom, ZOOM_EPSILON)
		var half := _deadzone / (2.0 * z)
		var current := center
		var desired := current
		if target.x < current.x - half.x:
			desired.x = target.x + half.x
		elif target.x > current.x + half.x:
			desired.x = target.x - half.x
		if target.y < current.y - half.y:
			desired.y = target.y + half.y
		elif target.y > current.y + half.y:
			desired.y = target.y - half.y
		var damping := _damping_factor(delta * 1000.0)
		center_on(current.lerp(desired, damping))
	elif camera_mode == MODE_FOLLOW:
		# Re-clamp after a resize even while idle (Phaser clamps before every render).
		center_on(center)
	_advance_shake(now)


## `zoom_in` -> step_zoom(-1), `zoom_out` -> step_zoom(+1); key repeat ignored (world spec 4.4).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"zoom_in", false):
		step_zoom(-1.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"zoom_out", false):
		step_zoom(1.0)
		get_viewport().set_input_as_handled()


## Phaser `centerOn` + bounds clamp (world spec 4.5): when the view is larger than the world the
## view's left/top edge is pinned to the bounds (no centring). Sets `center` and `global_position`.
## "The view" is the play area above `bottom_inset`; `global_position` is `center` lowered by half
## the inset (in world units).
## At integer zoom (roundPixels) Phaser `Camera.preRender` (Camera.js:557-571) floors the scroll
## (`centre - vp / 2`, screen px) BEFORE clamping and stores it back, so the next follow update
## starts from the floored value (sub-pixel catch-up steps truncate: the camera settles up to a
## few px short of the deadzone edge moving right/down). Same here: `center` keeps the floored,
## clamped value and the view's top-left lands on a whole pixel.
func center_on(point: Vector2) -> void:
	var p := point
	var z := maxf(target_zoom, ZOOM_EPSILON)
	if _round_pixels:
		var half_vp := _play_size() * 0.5
		p = (p - half_vp).floor() + half_vp
	if use_bounds and bounds.size.x > 0.0 and bounds.size.y > 0.0:
		var view := _play_size() / z
		var min_c := bounds.position + view * 0.5
		var max_c := Vector2(maxf(min_c.x, bounds.end.x - view.x * 0.5), maxf(min_c.y, bounds.end.y - view.y * 0.5))
		p = Vector2(clampf(p.x, min_c.x, max_c.x), clampf(p.y, min_c.y, max_c.y))
	center = p
	global_position = p + Vector2(0.0, bottom_inset * 0.5 / z)


## Phaser `setZoom` (world spec 4.4): ignore non-finite or <= 0; set target and `zoom`;
## `snap_2d_transforms_to_pixel` / `snap_2d_vertices_to_pixel` on iff integer zoom.
## (Named apply_zoom because Camera2D.set_zoom is native.)
func apply_zoom(z: float) -> void:
	if not is_finite(z) or z <= 0.0:
		return
	target_zoom = z
	zoom = Vector2(z, z)
	_round_pixels = ROUND_PIXELS_AT_INTEGER_ZOOM and is_integer_zoom(z)
	if is_inside_tree():
		var viewport := get_viewport()
		viewport.snap_2d_transforms_to_pixel = _round_pixels
		viewport.snap_2d_vertices_to_pixel = _round_pixels


## `nextCameraZoom` + `stepZoom` (world spec 4.4): move one level (delta_y < 0 zooms in); false at
## the ends of the list or when delta_y == 0; on change re-centre on the target immediately.
func step_zoom(delta_y: float) -> bool:
	if delta_y == 0.0 or not is_finite(delta_y):
		return false
	var next := next_zoom(target_zoom, delta_y)
	if absf(next - target_zoom) < ZOOM_EPSILON:
		return false
	apply_zoom(next)
	if camera_mode == MODE_FIXED:
		center_on(bounds.get_center())
	elif following and is_instance_valid(follow_target):
		center_on(_target_point())
	else:
		center_on(center)
	return true


## `resetZoom()`: apply DEFAULT_ZOOM (fixed mode re-holds).
func reset_zoom() -> void:
	if camera_mode == MODE_FIXED:
		hold_fixed()
		return
	apply_zoom(DEFAULT_ZOOM)
	center_on(center)


## Closest ZOOM_LEVELS index (ties -> lower index), stepped by `dir = +1 if delta_y < 0 else -1`,
## clamped to the list (CameraZoom.ts:42-52).
static func next_zoom(current: float, delta_y: float) -> float:
	var closest := 0
	for i: int in range(1, ZOOM_LEVELS.size()):
		if absf(ZOOM_LEVELS[i] - current) < absf(ZOOM_LEVELS[closest] - current):
			closest = i
	var dir := 1 if delta_y < 0.0 else -1
	var next_index := clampi(closest + dir, 0, ZOOM_LEVELS.size() - 1)
	return ZOOM_LEVELS[next_index]


## True when `z` is (within 1e-6 of) an integer (`isIntegerCameraZoom`).
static func is_integer_zoom(z: float) -> bool:
	return absf(z - roundf(z)) < ZOOM_EPSILON


## Fixed camera for interiors (OUT for level-1): stop following, no bounds,
## `zoom = min(1, vp.x / W, vp.y / H)` on the play area, centre on the world centre.
func hold_fixed() -> void:
	following = false
	_pan_duration_ms = 0.0
	use_bounds = false
	var vp := _play_size()
	var z := 1.0
	if bounds.size.x > 0.0 and bounds.size.y > 0.0:
		z = minf(1.0, minf(vp.x / bounds.size.x, vp.y / bounds.size.y))
	apply_zoom(z)
	center_on(bounds.get_center())


## Phaser `camera.shake(ms, intensity)` (world spec 4.9, player spec 8): ignored while a shake
## runs (Phaser force = false); each frame `offset = (randf_range(-1,1) * i * vp.x,
## randf_range(-1,1) * i * vp.y) * zoom` in world units, rounded at integer zoom, reset to zero
## at the end. Phaser (Shake.js:242-250) computes the same `* zoom` value and translates the
## already zoom-scaled camera matrix by it, so the on-screen shift is `i * vp * zoom^2`
## (Camera2D.offset is world units, scaled once more by zoom on screen). Runs on real time.
## Called by GameFeel.shake().
func shake(duration_ms: float, intensity: float) -> void:
	if duration_ms <= 0.0 or intensity <= 0.0 or not is_finite(duration_ms) or not is_finite(intensity):
		return
	var now := float(Time.get_ticks_msec())
	if now < _shake_until_ms:
		return
	_shake_until_ms = now + duration_ms
	_shake_intensity = intensity


## True while a shake runs.
func is_shaking() -> bool:
	return float(Time.get_ticks_msec()) < _shake_until_ms


## Rework trauma (see the header): adds `amount` (capped at 1) and, with a `direction`, turns the
## directional share of the shake to the axis of the stronger contribution so far. Real time.
func add_trauma(amount: float, direction: Vector2 = Vector2.ZERO) -> void:
	if amount <= 0.0 or not is_finite(amount):
		return
	var now := float(Time.get_ticks_msec())
	if _trauma <= 0.0:
		_trauma_last_ms = now
	if _trauma_noise == null:
		_trauma_noise = FastNoiseLite.new()
		_trauma_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_trauma_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		_trauma_noise.frequency = 1.0
		_trauma_noise.seed = randi()
	if direction != Vector2.ZERO and direction.is_finite() and (amount >= _trauma or _trauma_axis == Vector2.ZERO):
		_trauma_axis = direction.normalized()
	_trauma = minf(1.0, _trauma + amount)


## The current trauma (0..1).
func get_trauma() -> float:
	return _trauma


## Rework kick (see the header): the picture jolts `px` screen px along `direction`, then eases back.
func kick(px: float, direction: Vector2) -> void:
	if px <= 0.0 or not is_finite(px) or direction == Vector2.ZERO or not direction.is_finite():
		return
	_kick = direction.normalized() * px
	_kick_start_ms = float(Time.get_ticks_msec())


## Respawn pan (player spec 6.7): stop following, tween `center` to `point` over `duration_ms`
## with Phaser 'Power2' = TRANS_CUBIC / EASE_OUT, then resume following the target.
## Runs on real time in `_process`.
func pan_to(point: Vector2, duration_ms: float) -> void:
	if camera_mode == MODE_FIXED:
		return
	_pan_resume_follow = is_instance_valid(follow_target)
	following = false
	if duration_ms <= 0.0:
		center_on(point)
		_finish_pan()
		return
	_pan_from = center
	_pan_to = point
	_pan_start_ms = float(Time.get_ticks_msec())
	_pan_duration_ms = duration_ms


## Current deadzone size in screen px (for the FPS panel).
func get_deadzone_size() -> Vector2:
	return _deadzone


## "gameplay" at integer zoom, else "overview" (CameraZoom.ts:18-24).
func get_zoom_mode() -> String:
	return "gameplay" if is_integer_zoom(target_zoom) else "overview"


## Screen position (canvas-layer px) of a world point using this frame's camera state. Lets
## screen-space UI (the floating health bar) track world points without waiting for the
## viewport canvas transform, which Godot updates after every `_process`.
func world_to_screen(world_point: Vector2) -> Vector2:
	var z := maxf(target_zoom, ZOOM_EPSILON)
	return (world_point - (global_position + offset)) * z + _viewport_size() * 0.5


## The followed root's global position as drawn this frame (feet). Godot 4.7 has no 2D
## `get_global_transform_interpolated()`, so with physics interpolation on this lerps the last
## two physics-tick positions by `Engine.get_physics_interpolation_fraction()`, exactly what the
## renderer does; otherwise the plain global position.
func get_target_draw_position() -> Vector2:
	if not is_instance_valid(follow_target):
		return center
	if not _has_snapshot or not _interpolating():
		return follow_target.global_position
	return _target_prev.lerp(_target_curr, Engine.get_physics_interpolation_fraction())


## Physics-tick snapshot of the followed root (runs while paused too, like the renderer's tick,
## so a frozen body is drawn at its current position). A jump over TELEPORT_DISTANCE (respawn)
## is not interpolated.
func _physics_process(_delta: float) -> void:
	if not is_instance_valid(follow_target):
		_has_snapshot = false
		return
	var position_now := follow_target.global_position
	if not _has_snapshot or position_now.distance_to(_target_curr) > TELEPORT_DISTANCE:
		_target_prev = position_now
	else:
		_target_prev = _target_curr
	_target_curr = position_now
	_has_snapshot = true


func _interpolating() -> bool:
	return is_inside_tree() and get_tree().physics_interpolation \
		and follow_target.is_physics_interpolated_and_enabled()


## The aim point: the followed root's old Phaser position, as drawn this frame.
func _target_point() -> Vector2:
	if not is_instance_valid(follow_target):
		return center
	return get_target_draw_position() - FeetAnchor.depth_anchor(follow_target) * follow_target.global_scale


func _advance_pan(now: float) -> void:
	var t := clampf((now - _pan_start_ms) / _pan_duration_ms, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 3.0)
	center_on(_pan_from.lerp(_pan_to, eased))
	if t >= 1.0:
		_finish_pan()


func _finish_pan() -> void:
	_pan_duration_ms = 0.0
	if _pan_resume_follow and is_instance_valid(follow_target):
		following = true
	_pan_resume_follow = false


## The old shake's offset, plus the rework's trauma shake and kick (ZERO while neither runs, so the
## old shake is exactly as before).
func _advance_shake(now: float) -> void:
	var shake_offset := Vector2.ZERO
	var shaking := now < _shake_until_ms
	if shaking:
		var vp := _viewport_size()
		var z := maxf(target_zoom, ZOOM_EPSILON)
		shake_offset = Vector2(randf_range(-1.0, 1.0) * _shake_intensity * vp.x,
			randf_range(-1.0, 1.0) * _shake_intensity * vp.y) * z
	var extra := _advance_trauma(now) + _advance_kick(now)
	if shaking or extra != Vector2.ZERO:
		var total := shake_offset + extra
		offset = total.round() if _round_pixels else total
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO
		_shake_intensity = 0.0


## This frame's trauma shake in world units (ZERO without trauma); decays the trauma on real time.
func _advance_trauma(now: float) -> Vector2:
	if _trauma <= 0.0:
		return Vector2.ZERO
	var elapsed_s := maxf(0.0, now - _trauma_last_ms) / 1000.0
	_trauma_last_ms = now
	var settings := _trauma_settings()
	var decay := float(settings["decay"])
	# Without a decay (no constants) the trauma would never end: drop it.
	_trauma = maxf(0.0, _trauma - decay * elapsed_s) if decay > 0.0 else 0.0
	if _trauma <= 0.0 or _trauma_noise == null:
		_trauma_axis = Vector2.ZERO
		return Vector2.ZERO
	var shake := pow(_trauma, float(settings["exponent"]))
	var t := now / 1000.0 * float(settings["hz"])
	var free := Vector2(_trauma_noise.get_noise_2d(t, 0.0), _trauma_noise.get_noise_2d(t, TRAUMA_CHANNEL_SPACING))
	var share := float(settings["share"]) if _trauma_axis != Vector2.ZERO else 0.0
	var along := _trauma_axis * _trauma_noise.get_noise_2d(t, TRAUMA_CHANNEL_SPACING * 2.0)
	var screen_px := (free * (1.0 - share) + along * share) * float(settings["max_px"]) * shake
	return screen_px / maxf(target_zoom, ZOOM_EPSILON)


## This frame's kick in world units (ZERO without one): the picture moves along the kick, so the
## camera moves against it.
func _advance_kick(now: float) -> Vector2:
	if _kick_start_ms < 0.0:
		return Vector2.ZERO
	var elapsed := now - _kick_start_ms
	var reach := 0.0
	if elapsed < KICK_OUT_MS:
		var t := elapsed / KICK_OUT_MS
		reach = 1.0 - (1.0 - t) * (1.0 - t)
	elif elapsed < KICK_OUT_MS + KICK_RETURN_MS:
		var t := (elapsed - KICK_OUT_MS) / KICK_RETURN_MS
		reach = 1.0 - t * t * (3.0 - 2.0 * t)
	else:
		_kick_start_ms = -1.0
		_kick = Vector2.ZERO
		return Vector2.ZERO
	return -_kick * reach / maxf(target_zoom, ZOOM_EPSILON)


## `combat.trauma` (game-constants.json) as {"max_px", "exponent", "decay", "share", "hz"}; all 0
## without the constants (no shake).
func _trauma_settings() -> Dictionary:
	var constants := Services.constants()
	var block: Dictionary = {}
	if constants != null:
		var raw: Variant = constants.value("combat.trauma", {})
		if raw is Dictionary:
			block = raw
	return {
		"max_px": float(block.get("maxOffsetPx", 0.0)),
		"exponent": float(block.get("exponent", 1.0)),
		"decay": float(block.get("decayPerS", 0.0)),
		"share": clampf(float(block.get("directionalShare", 0.0)), 0.0, 1.0),
		"hz": float(block.get("noiseHz", 0.0)),
	}


func _update_deadzone() -> void:
	var vp := _play_size()
	_deadzone = Vector2(
		clampf(vp.x * DEADZONE_WIDTH_RATIO, DEADZONE_WIDTH_MIN, DEADZONE_WIDTH_MAX),
		clampf(vp.y * DEADZONE_HEIGHT_RATIO, DEADZONE_HEIGHT_MIN, DEADZONE_HEIGHT_MAX))


## `exponentialDampingFactor` (CameraMotion.ts:43-50).
static func _damping_factor(delta_ms: float) -> float:
	if not is_finite(delta_ms) or delta_ms <= 0.0:
		return 0.0
	return 1.0 - exp(-DAMPING_RATE * minf(delta_ms, MAX_DAMPING_DELTA_MS) / 1000.0)


## Visible viewport size in canvas units (the 1024 x 1024 base, wider on wide windows; main.gd).
func _viewport_size() -> Vector2:
	if not is_inside_tree():
		return Vector2(1280.0, 720.0)
	return get_viewport().get_visible_rect().size


## The play area: the visible viewport above the HUD console's `bottom_inset` (1024 x 896 at the
## base size).
func _play_size() -> Vector2:
	var vp := _viewport_size()
	return Vector2(vp.x, maxf(1.0, vp.y - bottom_inset))
