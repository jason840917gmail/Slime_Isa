extends Node
## An enemy's hit motion (combat-feel plan section 6 "Victim body" and "By weight class", section 8
## `feel/enemy_hit_motion.gd`; BODY_SHAPES.md "Reactions"). PROCESS_MODE_ALWAYS: it owns the
## sprite's offset, scale, rotation and skew for the reactions - the hold's nudge and squash, the
## launch tumble (stretch, spin, hop and bounce, afterimages, landing squash), the Hammer's flatten,
## the ring's bounce hop, the wall splat, the knockback lean, the knockdown fall, the daze sway, the
## heavy shake and the belly wobble - plus the overlays: the jitter of a frozen victim, the
## break-free outline flash, the daze stars and a real-time flash for receivers without one of their
## own (the training dummy). The body never moves here: EnemyReactions moves it through the enemy's
## own ArcadeMover step. EnemyReactions makes one per enemy (`EnemyReactions.motion_of`), a child of
## the enemy's script node, and calls `setup` with its sprite.
##
## Time: real time (presentation), but a motion's clock stops while a hit-stop freezes the tree
## (the squash is "held in the freeze") and while any other pause holds the tree; only the jitter
## runs during the freeze. Reduce motion keeps 35 % of every deformation and drops the jitter; the
## juice dev switches (F9) act here too: GameFeel.squash_scale() scales every deformation (0 with the
## squash switch off, 0.35 under reduce motion) and GameFeel.jitter_allowed() gates the jitter.
##
## It writes on top of whatever else animates the sprite (the Clod Stomper's clips key its scale and
## rotation): each frame a property someone else changed since the last write becomes the new base,
## and the motion is added to (scale: multiplied by) that base; `process_priority` runs it after the
## AnimationPlayers. When nothing plays it writes nothing and stops processing.
##
## Owner: reactions.

const Services := preload("res://game/shared/services.gd")
const HitFlash := preload("res://game/feel/hit_flash.gd")
const DazeStars := preload("res://game/feel/daze_stars.gd")

## Motions `play` knows (params in brackets, all optional; times in real ms, presentation only).
## Nudge along the hit and spring back [px, ms].
const NUDGE := &"nudge"
## Squash along the hit, stretch across it, spring back [along, across, ms, amplitude, elastic,
## nudge_px, nudge_ms, skew].
const SQUASH := &"squash"
## The launch: stretch, spin, hop and bounce, afterimages, landing squash [deg, hop_px, ms].
const TUMBLE := &"tumble"
## The Thud's flatten, held, then back [x, y, ms, return_ms].
const FLATTEN := &"flatten"
## A hold with a small art hop (the ring's bounce) [hop_px, ms, nudge_px].
const BOUNCE := &"bounce"
## A short shake (armor on a heavy enemy, a clink) [px, ms].
const JITTER := &"jitter"
## A launched body hitting a wall: squashed along the wall's normal [along, across, ms].
const SPLAT := &"splat"
## The damped wobble (the dummy's lean; a boss's belly jiggle) [rad, jiggle].
const WOBBLE := &"wobble"
## A knockback: leans with the push, then back [rad, ms].
const LEAN := &"lean"
## A knockdown: falls over, stays down, gets up [rad, ms].
const FALL := &"fall"
## A daze: sways in place [rad, ms].
const DAZE := &"daze"

## Presentation numbers (combat-feel plan section 6); the data ones (`combat.verbs`) come in the
## params from EnemyReactions.
const SQUASH_ALONG := 0.86
const SQUASH_ACROSS := 1.12
const SQUASH_MS := 150.0
## Light enemies' elastic return (and their 1.5x amplitude comes in `amplitude`).
const ELASTIC_MS := 260.0
const ELASTIC_TURNS := 1.5
const ELASTIC_DECAY := 5.0
const STRETCH_ALONG := 1.25
const STRETCH_ACROSS := 0.82
const STRETCH_MS := 120.0
const LANDING_SQUASH := Vector2(1.3, 0.75)
const LANDING_MS := 140.0
const TUMBLE_DEG := 360.0
const TUMBLE_MS := 460.0
const TUMBLE_HOP_PX := 12.0
## The tumble's first hop takes this share of its time; the bounce after it is this high.
const TUMBLE_FIRST_HOP_SHARE := 0.7
const TUMBLE_BOUNCE_SHARE := 0.3
const FLATTEN_X := 1.3
const FLATTEN_Y := 0.6
const FLATTEN_MS := 400.0
const RETURN_MS := 150.0
const BOUNCE_HOP_PX := 10.0
const BOUNCE_MS := 220.0
const SPLAT_ALONG := 0.6
const SPLAT_ACROSS := 1.3
const SPLAT_MS := 100.0
const NUDGE_PX := 4.0
const NUDGE_MS := 120.0
## The springs' overshoot (half-turns over the motion).
const NUDGE_TURNS := 1.5
const JITTER_PX := 2.0
const SHAKE_MS := 120.0
## The dummy's wobble: 0.22 rad decaying by e^(-4.5 t), cos(6 pi t); it ends under 0.004 rad.
const WOBBLE_RAD := 0.22
const WOBBLE_DECAY := 4.5
const WOBBLE_RATE := 9.0 * TAU / 3.0
const WOBBLE_END := 0.004
const LEAN_RAD := 0.22
const LEAN_MS := 380.0
const LEAN_IN_SHARE := 0.15
const LEAN_OUT_SHARE := 0.4
const FALL_RAD := 1.35
const FALL_MS := 1200.0
const FALL_TURN_MS := 150.0
const DAZE_RAD := 0.09
const DAZE_MS := 1200.0
const DAZE_SWAY_HZ := 1.4
## The Axe's twist: a skew along the sweep.
const AXE_SKEW_RAD := 0.3
const AFTERIMAGE_COUNT := 3
const AFTERIMAGE_GAP_MS := 45.0
const AFTERIMAGE_FADE_S := 0.22
const AFTERIMAGE_ALPHA := 0.45
## The break-free tell: a yellow-white outline flash.
const OUTLINE_COLOR := Color(1.0, 0.96, 0.62, 1.0)
const OUTLINE_PX := 2.0
const OUTLINE_MS := 350.0
const FLASH_COLOR := Color.WHITE
const REDUCED_MOTION := 0.35
## Runs after the enemy's AnimationPlayer (priority 0), so its write is the frame's last.
const PROCESS_PRIORITY := 100
## The outline's solid silhouette.
const SILHOUETTE_CODE := "shader_type canvas_item;\nuniform vec4 tint : source_color = vec4(1.0);\nvoid fragment() {\n\tCOLOR = vec4(tint.rgb, texture(TEXTURE, UV).a * tint.a);\n}\n"
const OUTLINE_DIRECTIONS: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]

static var _silhouette: Shader

## The sprite it moves (the enemy's `visual`).
var visual: Sprite2D

var _motion: StringName = &""
var _direction: Vector2 = Vector2.ZERO
var _params: Dictionary = {}
var _age_ms: float = 0.0
var _length_ms: float = 0.0
var _side: float = 1.0
var _ghosts_made: int = 0
## The base the motion is applied on (the sprite's own values) and what it last wrote.
var _writing: bool = false
var _base_offset: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ONE
var _base_rotation: float = 0.0
var _base_skew: float = 0.0
var _written_offset: Vector2 = Vector2.ZERO
var _written_scale: Vector2 = Vector2.ONE
var _written_rotation: float = 0.0
var _written_skew: float = 0.0
## Overlays.
var _outline: Node2D
var _outline_left_ms: float = 0.0
var _outline_total_ms: float = 0.0
var _outline_color: Color = OUTLINE_COLOR
var _flash_left_ms: float = 0.0
var _stars: Node2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = PROCESS_PRIORITY
	set_process(false)


func _exit_tree() -> void:
	stop()


## Takes `target_visual` (its current pose is the base the motions start from).
func setup(target_visual: Sprite2D) -> void:
	visual = target_visual
	if visual == null:
		return
	_base_offset = visual.offset
	_base_scale = visual.scale
	_base_rotation = visual.rotation
	_base_skew = visual.skew


## Plays `motion` (one of the constants above) along `direction` (a unit vector; ZERO plays it in
## place) with `params`. A new motion replaces the running one (the overlays stay).
func play(motion: StringName, direction: Vector2 = Vector2.ZERO, params: Dictionary = {}) -> void:
	if not _has_visual():
		return
	_motion = motion
	_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO
	_params = params
	_age_ms = 0.0
	_ghosts_made = 0
	_side = -1.0 if _direction.x < 0.0 else 1.0
	_length_ms = _length_of(motion)
	set_process(true)


## True while a motion plays.
func is_playing() -> bool:
	return _motion != &""


## The motion playing (&"" when none).
func current() -> StringName:
	return _motion


## Back to the rest pose at once, overlays gone (death, a reset).
func stop() -> void:
	_motion = &""
	_release()
	_clear_outline()
	_clear_flash()
	if _stars != null and is_instance_valid(_stars):
		_stars.queue_free()
	_stars = null
	set_process(false)


## The break-free tell: the sprite's silhouette, `color`, flashes around it for `duration_ms`.
func outline(duration_ms: float = OUTLINE_MS, color: Color = OUTLINE_COLOR) -> void:
	if not _has_visual():
		return
	if _outline == null or not is_instance_valid(_outline):
		_outline = _make_outline()
	_outline_total_ms = maxf(1.0, duration_ms)
	_outline_left_ms = _outline_total_ms
	_outline_color = color
	set_process(true)


## A white fill for `duration_ms` (real time), for receivers without a hit flash of their own.
func flash(duration_ms: float) -> void:
	if not _has_visual() or duration_ms <= 0.0:
		return
	HitFlash.flash(visual, FLASH_COLOR)
	_flash_left_ms = duration_ms
	set_process(true)


## Stars orbit the head until `until_ms` (simulation ms); a later call moves the end.
func show_stars(until_ms: float) -> void:
	if not _has_visual():
		return
	if _stars != null and is_instance_valid(_stars) and not _stars.is_queued_for_deletion():
		_stars.set(&"until_ms", maxf(float(_stars.get(&"until_ms")), until_ms))
		return
	var root := visual.get_parent() as Node2D
	if root == null:
		return
	var stars := DazeStars.new()
	stars.name = "DazeStars"
	var rect := visual.get_rect()
	stars.head = visual.transform * Vector2(rect.get_center().x, rect.position.y)
	stars.until_ms = until_ms
	root.add_child(stars)
	_stars = stars


## Takes the stars away at once (the daze ended early, the enemy died).
func hide_stars() -> void:
	if _stars != null and is_instance_valid(_stars):
		_stars.queue_free()
	_stars = null


func _process(delta: float) -> void:
	if not _has_visual():
		set_process(false)
		return
	var real_ms := delta * 1000.0
	var tree := get_tree()
	var frozen := _frozen()
	var held := tree != null and tree.paused
	_step_overlays(real_ms, held and not frozen)
	if _motion == &"":
		if not _overlays_running():
			set_process(false)
		return
	var jitter := Vector2.ZERO
	if _motion == JITTER:
		_age_ms += real_ms
		jitter = _random_jitter(float(_params.get("px", JITTER_PX)))
	elif frozen:
		if bool(_params.get("jitter", true)):
			jitter = _random_jitter(JITTER_PX)
	elif not held:
		_age_ms += real_ms
	if _age_ms >= _length_ms:
		_motion = &""
		_release()
		return
	_apply_pose(_age_ms, jitter)


# --- poses ------------------------------------------------------------------------------------

func _length_of(motion: StringName) -> float:
	match motion:
		NUDGE:
			return _param("ms", NUDGE_MS)
		SQUASH:
			var squash_ms := _param("ms", ELASTIC_MS if bool(_params.get("elastic", false)) else SQUASH_MS)
			return maxf(squash_ms, _param("nudge_ms", 0.0))
		TUMBLE:
			return _param("ms", TUMBLE_MS) + LANDING_MS
		FLATTEN:
			return _param("ms", FLATTEN_MS) + _param("return_ms", RETURN_MS)
		BOUNCE:
			return _param("ms", BOUNCE_MS) + LANDING_MS
		JITTER:
			return _param("ms", SHAKE_MS)
		SPLAT:
			return _param("ms", SPLAT_MS) + ELASTIC_MS
		WOBBLE:
			# Until the decaying lean is under WOBBLE_END.
			return 1000.0 * log(maxf(1.0, _param("rad", WOBBLE_RAD) / WOBBLE_END)) / WOBBLE_DECAY
		LEAN:
			return _param("ms", LEAN_MS)
		FALL:
			return maxf(2.0 * FALL_TURN_MS, _param("ms", FALL_MS))
		DAZE:
			return _param("ms", DAZE_MS)
	return 0.0


## Writes the pose of the running motion at `t` ms (offset in world px along `_direction`, scale
## factors, rotation and skew in radians), softened under reduce motion, plus `jitter` (world px).
func _apply_pose(t: float, jitter: Vector2) -> void:
	var offset := Vector2.ZERO
	var factor := Vector2.ONE
	var rotation := 0.0
	var skew := 0.0
	match _motion:
		NUDGE:
			offset = _direction * _param("px", NUDGE_PX) * _spring(t / maxf(1.0, _length_ms))
		SQUASH:
			var elastic := bool(_params.get("elastic", false))
			var squash_ms := _param("ms", ELASTIC_MS if elastic else SQUASH_MS)
			var u := clampf(t / maxf(1.0, squash_ms), 0.0, 1.0)
			var k := (_elastic(u) if elastic else _ease_back(u)) * _param("amplitude", 1.0)
			factor = _directional(1.0 + (_param("along", SQUASH_ALONG) - 1.0) * k,
				1.0 + (_param("across", SQUASH_ACROSS) - 1.0) * k)
			skew = _param("skew", 0.0) * k
			var nudge_ms := _param("nudge_ms", 0.0)
			if nudge_ms > 0.0:
				offset = _direction * _param("nudge_px", 0.0) * _spring(clampf(t / nudge_ms, 0.0, 1.0))
		TUMBLE:
			var spin_ms := maxf(1.0, _param("ms", TUMBLE_MS))
			if t < STRETCH_MS:
				var s := 1.0 - t / STRETCH_MS
				factor = _directional(1.0 + (STRETCH_ALONG - 1.0) * s, 1.0 + (STRETCH_ACROSS - 1.0) * s)
			if t < spin_ms:
				var u := t / spin_ms
				rotation = _side * deg_to_rad(_param("deg", TUMBLE_DEG)) * (1.0 - pow(1.0 - u, 2.0))
				offset = Vector2(0.0, -_hop_height(u, _param("hop_px", TUMBLE_HOP_PX)))
				_make_afterimages(t)
			else:
				var land := clampf((t - spin_ms) / LANDING_MS, 0.0, 1.0)
				factor = Vector2.ONE + (LANDING_SQUASH - Vector2.ONE) * _ease_back(land)
		FLATTEN:
			var hold_ms := _param("ms", FLATTEN_MS)
			var k := 1.0 if t < hold_ms else _elastic(clampf((t - hold_ms) / maxf(1.0, _param("return_ms", RETURN_MS)), 0.0, 1.0))
			factor = Vector2(1.0 + (_param("x", FLATTEN_X) - 1.0) * k, 1.0 + (_param("y", FLATTEN_Y) - 1.0) * k)
		BOUNCE:
			var hop_ms := maxf(1.0, _param("ms", BOUNCE_MS))
			if t < hop_ms:
				offset = Vector2(0.0, -_param("hop_px", BOUNCE_HOP_PX) * sin(PI * t / hop_ms))
				offset += _direction * _param("nudge_px", 0.0) * _spring(t / hop_ms)
			else:
				var land := clampf((t - hop_ms) / LANDING_MS, 0.0, 1.0)
				factor = Vector2.ONE + (LANDING_SQUASH - Vector2.ONE) * 0.5 * _ease_back(land)
		JITTER:
			pass
		SPLAT:
			var flat_ms := _param("ms", SPLAT_MS)
			var k := 1.0 if t < flat_ms else _elastic(clampf((t - flat_ms) / ELASTIC_MS, 0.0, 1.0))
			factor = _directional(1.0 + (_param("along", SPLAT_ALONG) - 1.0) * k, 1.0 + (_param("across", SPLAT_ACROSS) - 1.0) * k)
		WOBBLE:
			var seconds := t / 1000.0
			var amplitude := _param("rad", WOBBLE_RAD) * exp(-WOBBLE_DECAY * seconds)
			rotation = _side * amplitude * cos(seconds * WOBBLE_RATE)
			var jiggle := _param("jiggle", 0.0) * exp(-WOBBLE_DECAY * seconds) * sin(seconds * WOBBLE_RATE)
			factor = Vector2(1.0 + jiggle, 1.0 - jiggle)
		LEAN:
			var u := t / maxf(1.0, _length_ms)
			var k := 1.0
			if u < LEAN_IN_SHARE:
				k = u / LEAN_IN_SHARE
			elif u > 1.0 - LEAN_OUT_SHARE:
				k = (1.0 - u) / LEAN_OUT_SHARE
			rotation = _side * _param("rad", LEAN_RAD) * k
		FALL:
			var down_ms := _length_ms
			var k := minf(1.0, t / FALL_TURN_MS)
			if t > down_ms - FALL_TURN_MS:
				k = maxf(0.0, (down_ms - t) / FALL_TURN_MS)
			rotation = _side * _param("rad", FALL_RAD) * k
		DAZE:
			rotation = _param("rad", DAZE_RAD) * sin(TAU * DAZE_SWAY_HZ * t / 1000.0)
	var soft := _motion_scale()
	if soft < 1.0:
		offset *= soft
		factor = Vector2.ONE + (factor - Vector2.ONE) * soft
		rotation *= soft
		skew *= soft
	if not _jitter_allowed():
		jitter = Vector2.ZERO
	_write(offset + jitter, factor, rotation, skew)


## Along/across factors as x/y scale factors for the motion's direction (a squash with no direction
## flattens: across on x, along on y).
func _directional(along: float, across: float) -> Vector2:
	if _direction == Vector2.ZERO:
		return Vector2(across, along)
	var wx := _direction.x * _direction.x
	var wy := _direction.y * _direction.y
	return Vector2(along * wx + across * wy, along * wy + across * wx)


## 1 -> 0 with one small overshoot (the nudge's spring back).
static func _spring(u: float) -> float:
	var v := clampf(u, 0.0, 1.0)
	return (1.0 - v) * cos(v * PI * NUDGE_TURNS)


## 1 -> 0, easing out.
static func _ease_back(u: float) -> float:
	var v := clampf(u, 0.0, 1.0)
	return (1.0 - v) * (1.0 - v)


## 1 -> 0, overshooting a few times (the elastic return).
static func _elastic(u: float) -> float:
	var v := clampf(u, 0.0, 1.0)
	return exp(-ELASTIC_DECAY * v) * cos(v * PI * 2.0 * ELASTIC_TURNS) * (1.0 - v)


## The tumble's hop (px) at `u` of its spin: one hop, then a lower bounce.
static func _hop_height(u: float, hop_px: float) -> float:
	if u < TUMBLE_FIRST_HOP_SHARE:
		return hop_px * sin(PI * u / TUMBLE_FIRST_HOP_SHARE)
	return hop_px * TUMBLE_BOUNCE_SHARE * sin(PI * (u - TUMBLE_FIRST_HOP_SHARE) / (1.0 - TUMBLE_FIRST_HOP_SHARE))


func _random_jitter(px: float) -> Vector2:
	return Vector2(randf_range(-px, px), randf_range(-px, px))


# --- writing on top of the sprite's own values -----------------------------------------------

func _write(offset_px: Vector2, factor: Vector2, rotation: float, skew: float) -> void:
	_read_base()
	var scale_abs := Vector2(maxf(absf(_base_scale.x), 0.001), maxf(absf(_base_scale.y), 0.001))
	# The offset is in the sprite's turned frame: undo the rotation so a hop is screen-up.
	var turned := _base_rotation + rotation
	var shift := offset_px.rotated(-turned) / scale_abs
	if _motion == TUMBLE:
		# Spin about the art's centre, not the node origin (the dummy's origin is its feet).
		var centre := visual.get_rect().get_center() - visual.offset + _base_offset
		shift += centre.rotated(-rotation) - centre
	visual.offset = _base_offset + shift
	visual.scale = _base_scale * factor
	visual.rotation = _base_rotation + rotation
	visual.skew = _base_skew + skew
	# Read back what the sprite stored (its 32-bit floats), so the next frame's comparison is exact.
	_written_offset = visual.offset
	_written_scale = visual.scale
	_written_rotation = visual.rotation
	_written_skew = visual.skew
	_writing = true


## A property someone else changed since the last write is the new base.
func _read_base() -> void:
	if not _writing:
		_base_offset = visual.offset
		_base_scale = visual.scale
		_base_rotation = visual.rotation
		_base_skew = visual.skew
		return
	if visual.offset != _written_offset:
		_base_offset = visual.offset
	if visual.scale != _written_scale:
		_base_scale = visual.scale
	if visual.rotation != _written_rotation:
		_base_rotation = visual.rotation
	if visual.skew != _written_skew:
		_base_skew = visual.skew


## Puts the base back where the motion wrote last (nothing someone else wrote since is undone).
func _release() -> void:
	if not _writing or not _has_visual():
		_writing = false
		return
	_read_base()
	visual.offset = _base_offset
	visual.scale = _base_scale
	visual.rotation = _base_rotation
	visual.skew = _base_skew
	_writing = false


# --- overlays ---------------------------------------------------------------------------------

func _step_overlays(real_ms: float, held: bool) -> void:
	if _flash_left_ms > 0.0 and not held:
		_flash_left_ms -= real_ms
		if _flash_left_ms <= 0.0:
			_clear_flash()
	if _outline == null or not is_instance_valid(_outline):
		return
	if not held:
		_outline_left_ms -= real_ms
	if _outline_left_ms <= 0.0:
		_clear_outline()
		return
	var alpha := _outline_color.a * clampf(_outline_left_ms / _outline_total_ms, 0.0, 1.0)
	var scale_abs := Vector2(maxf(absf(visual.scale.x), 0.001), maxf(absf(visual.scale.y), 0.001))
	var index := 0
	for child: Node in _outline.get_children():
		var copy := child as Sprite2D
		if copy == null:
			continue
		_copy_frame(copy)
		copy.offset = visual.offset + OUTLINE_DIRECTIONS[index % OUTLINE_DIRECTIONS.size()] * OUTLINE_PX / scale_abs
		(copy.material as ShaderMaterial).set_shader_parameter(&"tint", Color(_outline_color, alpha))
		index += 1


func _overlays_running() -> bool:
	return _flash_left_ms > 0.0 or (_outline != null and is_instance_valid(_outline))


func _make_outline() -> Node2D:
	if _silhouette == null:
		_silhouette = Shader.new()
		_silhouette.code = SILHOUETTE_CODE
	var holder := Node2D.new()
	holder.name = "HitOutline"
	holder.show_behind_parent = true
	for direction: Vector2 in OUTLINE_DIRECTIONS:
		var copy := Sprite2D.new()
		var material := ShaderMaterial.new()
		material.shader = _silhouette
		copy.material = material
		_copy_frame(copy)
		holder.add_child(copy)
	visual.add_child(holder)
	return holder


func _clear_outline() -> void:
	if _outline != null and is_instance_valid(_outline):
		_outline.queue_free()
	_outline = null
	_outline_left_ms = 0.0


func _clear_flash() -> void:
	if _flash_left_ms != 0.0 and _has_visual():
		HitFlash.clear(visual)
	_flash_left_ms = 0.0


## Copies the sprite's frame (texture, sheet, region, flips, centring) onto `copy`.
func _copy_frame(copy: Sprite2D) -> void:
	copy.texture = visual.texture
	copy.hframes = visual.hframes
	copy.vframes = visual.vframes
	copy.frame = visual.frame
	copy.centered = visual.centered
	copy.flip_h = visual.flip_h
	copy.flip_v = visual.flip_v
	copy.region_enabled = visual.region_enabled
	copy.region_rect = visual.region_rect
	copy.offset = visual.offset


## The tumble's afterimages: a fading copy of the sprite every AFTERIMAGE_GAP_MS, left where the body
## was (on the world's entity layer, so they sort with it).
func _make_afterimages(t: float) -> void:
	while _ghosts_made < AFTERIMAGE_COUNT and t >= float(_ghosts_made) * AFTERIMAGE_GAP_MS:
		_ghosts_made += 1
		var world := Services.world()
		var parent: Node = world.entities_root() if world != null else null
		if parent == null:
			parent = visual.get_parent()
		if parent == null:
			return
		var ghost := Sprite2D.new()
		_copy_frame(ghost)
		ghost.modulate = Color(1.0, 1.0, 1.0, AFTERIMAGE_ALPHA)
		ghost.self_modulate = visual.self_modulate
		parent.add_child(ghost)
		ghost.global_transform = visual.global_transform
		var fade := ghost.create_tween()
		fade.tween_property(ghost, ^"modulate:a", 0.0, AFTERIMAGE_FADE_S)
		fade.tween_callback(ghost.queue_free)


# --- helpers ----------------------------------------------------------------------------------

func _param(key: String, fallback: float) -> float:
	var value: Variant = _params.get(key, fallback)
	return float(value) if (value is float or value is int) and is_finite(float(value)) else fallback


func _has_visual() -> bool:
	return visual != null and is_instance_valid(visual) and visual.is_inside_tree()


func _frozen() -> bool:
	var feel := Services.feel()
	return feel != null and feel.is_frozen()


func _reduce_motion() -> bool:
	var feel := Services.feel()
	return feel != null and feel.reduce_motion


## How much of a deformation shows: GameFeel.squash_scale() (the squash switch, then reduce motion),
## else REDUCED_MOTION under reduce motion.
func _motion_scale() -> float:
	var feel := Services.feel()
	if feel != null and feel.has_method(&"squash_scale"):
		return clampf(float(feel.call(&"squash_scale")), 0.0, 1.0)
	return REDUCED_MOTION if _reduce_motion() else 1.0


## Whether the jitter shows: GameFeel.jitter_allowed() (the jitter switch, no reduce motion).
func _jitter_allowed() -> bool:
	var feel := Services.feel()
	if feel != null and feel.has_method(&"jitter_allowed"):
		return bool(feel.call(&"jitter_allowed"))
	return not _reduce_motion()
