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
## Owner: world builder.

const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

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
## At integer zoom (roundPixels) Phaser `Camera.preRender` (Camera.js:557-571) floors the scroll
## (`centre - vp / 2`, screen px) BEFORE clamping and stores it back, so the next follow update
## starts from the floored value (sub-pixel catch-up steps truncate: the camera settles up to a
## few px short of the deadzone edge moving right/down). Same here: `center` keeps the floored,
## clamped value and the view's top-left lands on a whole pixel.
func center_on(point: Vector2) -> void:
	var p := point
	if _round_pixels:
		var half_vp := _viewport_size() * 0.5
		p = (p - half_vp).floor() + half_vp
	if use_bounds and bounds.size.x > 0.0 and bounds.size.y > 0.0:
		var view := _viewport_size() / maxf(target_zoom, ZOOM_EPSILON)
		var min_c := bounds.position + view * 0.5
		var max_c := Vector2(maxf(min_c.x, bounds.end.x - view.x * 0.5), maxf(min_c.y, bounds.end.y - view.y * 0.5))
		p = Vector2(clampf(p.x, min_c.x, max_c.x), clampf(p.y, min_c.y, max_c.y))
	center = p
	global_position = p


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
## `zoom = min(1, vp.x / W, vp.y / H)`, centre on the world centre.
func hold_fixed() -> void:
	following = false
	_pan_duration_ms = 0.0
	use_bounds = false
	var vp := _viewport_size()
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


func _advance_shake(now: float) -> void:
	if now < _shake_until_ms:
		var vp := _viewport_size()
		var z := maxf(target_zoom, ZOOM_EPSILON)
		var shake_offset := Vector2(randf_range(-1.0, 1.0) * _shake_intensity * vp.x,
			randf_range(-1.0, 1.0) * _shake_intensity * vp.y) * z
		offset = shake_offset.round() if _round_pixels else shake_offset
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO
		_shake_intensity = 0.0


func _update_deadzone() -> void:
	var vp := _viewport_size()
	_deadzone = Vector2(
		clampf(vp.x * DEADZONE_WIDTH_RATIO, DEADZONE_WIDTH_MIN, DEADZONE_WIDTH_MAX),
		clampf(vp.y * DEADZONE_HEIGHT_RATIO, DEADZONE_HEIGHT_MIN, DEADZONE_HEIGHT_MAX))


## `exponentialDampingFactor` (CameraMotion.ts:43-50).
static func _damping_factor(delta_ms: float) -> float:
	if not is_finite(delta_ms) or delta_ms <= 0.0:
		return 0.0
	return 1.0 - exp(-DAMPING_RATE * minf(delta_ms, MAX_DAMPING_DELTA_MS) / 1000.0)


## Visible viewport size in canvas units (CSS px once main.gd set content_scale_size).
func _viewport_size() -> Vector2:
	if not is_inside_tree():
		return Vector2(1280.0, 720.0)
	return get_viewport().get_visible_rect().size
