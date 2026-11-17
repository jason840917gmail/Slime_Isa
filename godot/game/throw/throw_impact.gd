extends Node2D
## The pictures of a throw's blow, drawn in code (the new throw feel, throw_feel.gd; owner, 2026-11-16:
## "a strong hit ... with nice effects"):
## - **the impact star** (`star`): where a thrown thing strikes an enemy, a bright spiked star about as
##   wide as the enemy for a few frames (white core, cream body, warm edge, its long spike along the
##   throw), then a ring that widens and thins, and short spark streaks shooting on in a cone along
##   the throw. A `dull` one (a throw that struck but did not hurt, a piercing thing passing through)
##   is the ring and a few streaks, no star;
## - **the mouth puff** (`puff`): a small ring leaving the slime's mouth along the throw, seen side on
##   (flattened along the throw);
## - **the snap** (`snap`): a streak from where a rebounding thing was caught in the air to the mouth
##   it went into, its tail catching up at once (the rebound prototype's mouth catch, mouth.gd).
## Presentation only, in real time (`_process`, PROCESS_MODE_ALWAYS): it plays through the hit-stop
## that follows the blow, since it is how the freeze reads (as the camera's shake and the white flash
## do). A child of the entities root at the blow, above the creatures, freed when it has played.
## The lengths and counts come from game-constants.json `gulp.throwFeel.star`; the shapes' proportions
## below are the drawing.
##
## Owner: throw combat (the sender).

const CORE := Color("#ffffff")
const BODY := Color("#ffe89a")
const EDGE := Color("#ff7f1f")
const RING := Color("#fff2b8")
## Above the thrown thing and its shards (z 5), the creatures and GameFeel's particles (z 100): the
## star is the first thing the blow shows.
const Z_INDEX := 110
## The star: its spikes (long and short ones in turn), the short spikes' and the waist's share of the
## long ones, the edge layer's and the core's share of the body, and how much longer it is along the
## throw than across.
const SPIKES := 8
const SHORT_SPIKE_SHARE := 0.6
const WAIST_SHARE := 0.4
const WAIST_END_SHARE := 0.08
const EDGE_SHARE := 1.18
const CORE_SHARE := 0.6
const ALONG_STRETCH := 1.22
const ACROSS_STRETCH := 0.94
## The star pops from this share of its size over the first POP_SHARE of its time, then thins and
## fades from THIN_FROM on, growing a little.
const POP_FROM := 0.75
const POP_SHARE := 0.25
const THIN_FROM := 0.5
const END_GROWTH := 1.15
## The ring: from and to these shares of the star's radius, its line from and to these widths.
const RING_FROM_SHARE := 0.4
const RING_TO_SHARE := 1.3
const RING_WIDTH_FROM := 5.0
const RING_WIDTH_TO := 1.2
const RING_POINTS := 40
## The spark streaks: this share shoots in the cone along the throw (the rest anywhere), each from
## this share of the radius out, this fast (px/s), this long (px) and wide, living this long (ms).
const RAY_FORWARD_SHARE := 0.75
const RAY_CONE_DEG := 62.0
const RAY_START_SHARE := 0.35
const RAY_SPEED := Vector2(240.0, 560.0)
const RAY_LENGTH := Vector2(10.0, 24.0)
const RAY_WIDTH := Vector2(2.0, 3.4)
const RAY_LIFE_MS := Vector2(130.0, 250.0)
## The puff: a ring seen side on, this flat along the throw, drifting this far along it.
const PUFF_FLAT := 0.42
const PUFF_DRIFT_PX := 12.0
const PUFF_ALPHA := 0.9
const PUFF_WIDTH_FROM := 3.0
const PUFF_WIDTH_TO := 1.2
## The puff shows under the thrown thing (z 5), which flies out through it.
const PUFF_Z_INDEX := 4
## The snap: the streak's width at the mouth and at its tail.
const SNAP_WIDTH := Vector2(7.0, 1.5)

var _age_ms: float = 0.0
var _life_ms: float = 0.0
var _direction: Vector2 = Vector2.RIGHT
var _radius: float = 0.0
var _star_ms: float = 0.0
var _ring_from_ms: float = 0.0
var _ring_ms: float = 0.0
var _turn: float = 0.0
var _is_puff: bool = false
## The snap: where the streak's tail starts, from this node (the mouth); ZERO for no snap.
var _snap_from: Vector2 = Vector2.ZERO
## [{"angle", "speed", "length", "width", "life"}].
var _rays: Array[Dictionary] = []


## The impact star at `at` under `parent`, for a blow along `direction`, `width_px` across. `numbers`
## (`gulp.throwFeel.star`): "starMs", "ringFromMs", "ringMs", "rays". `dull`: no star, half the rays.
static func star(parent: Node, at: Vector2, direction: Vector2, width_px: float, numbers: Dictionary,
		dull: bool = false) -> void:
	if parent == null or width_px <= 0.0:
		return
	var node := new()
	node.name = "ThrowImpact"
	node._direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	node._radius = width_px * 0.5
	node._star_ms = 0.0 if dull else float(numbers.get("starMs", 80.0))
	node._ring_from_ms = 0.0 if dull else float(numbers.get("ringFromMs", 30.0))
	node._ring_ms = float(numbers.get("ringMs", 190.0))
	node._turn = randf_range(-0.2, 0.2)
	var rays := int(numbers.get("rays", 10))
	node._make_rays(ceili(rays * 0.5) if dull else rays)
	node._begin(parent, at)


## The mouth puff at `at` under `parent`, along `direction`, growing to `width_px` across over `ms`.
static func puff(parent: Node, at: Vector2, direction: Vector2, width_px: float, ms: float) -> void:
	if parent == null or width_px <= 0.0 or ms <= 0.0:
		return
	var node := new()
	node.name = "ThrowPuff"
	node._is_puff = true
	node._direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	node._radius = width_px * 0.5
	node._ring_ms = ms
	node._begin(parent, at)
	node.z_index = PUFF_Z_INDEX


## The snap under `parent`: a streak from `from` (where the thing was) into `to` (the mouth), over `ms`.
static func snap(parent: Node, from: Vector2, to: Vector2, ms: float) -> void:
	if parent == null or ms <= 0.0 or from.distance_to(to) < 1.0:
		return
	var node := new()
	node.name = "ThrowSnap"
	node._snap_from = from - to
	node._ring_ms = ms
	node._begin(parent, to)


func _begin(parent: Node, at: Vector2) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = Z_INDEX
	_life_ms = maxf(_star_ms, _ring_ms)
	for ray: Dictionary in _rays:
		_life_ms = maxf(_life_ms, float(ray["life"]))
	parent.add_child(self)
	global_position = at
	queue_redraw()


func _make_rays(count: int) -> void:
	var cone := deg_to_rad(RAY_CONE_DEG)
	var along := _direction.angle()
	for i in count:
		var forward := float(i) < float(count) * RAY_FORWARD_SHARE
		var angle := along + randf_range(-cone, cone) if forward else randf() * TAU
		_rays.append({"angle": angle, "speed": randf_range(RAY_SPEED.x, RAY_SPEED.y) * (1.0 if forward else 0.6),
			"length": randf_range(RAY_LENGTH.x, RAY_LENGTH.y), "width": randf_range(RAY_WIDTH.x, RAY_WIDTH.y),
			"life": randf_range(RAY_LIFE_MS.x, RAY_LIFE_MS.y)})


func _process(delta: float) -> void:
	_age_ms += delta * 1000.0
	if _age_ms >= _life_ms:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _snap_from != Vector2.ZERO:
		_draw_snap()
		return
	if _is_puff:
		_draw_puff()
		return
	_draw_ring()
	_draw_rays()
	_draw_star()


func _draw_star() -> void:
	if _star_ms <= 0.0 or _age_ms >= _star_ms:
		return
	var t := _age_ms / _star_ms
	var pop := clampf(t / POP_SHARE, 0.0, 1.0)
	var fade := clampf((t - THIN_FROM) / (1.0 - THIN_FROM), 0.0, 1.0)
	var size := _radius * lerpf(POP_FROM, 1.0, 1.0 - (1.0 - pop) * (1.0 - pop)) * lerpf(1.0, END_GROWTH, fade)
	var waist := lerpf(WAIST_SHARE, WAIST_END_SHARE, fade)
	var alpha := 1.0 - fade * fade
	draw_colored_polygon(_star_points(size * EDGE_SHARE, waist * 1.1), Color(EDGE, alpha * 0.9))
	draw_colored_polygon(_star_points(size, waist), Color(BODY, alpha))
	draw_colored_polygon(_star_points(size * CORE_SHARE, waist), Color(CORE, alpha))


## The star's outline: SPIKES spikes of `radius` (every other one shorter) with a waist of `waist` x
## the radius between them, longer along the throw than across.
func _star_points(radius: float, waist: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var across := Vector2(-_direction.y, _direction.x)
	for i in SPIKES * 2:
		var reach := radius * waist
		if i % 2 == 0:
			reach = radius * (1.0 if i % 4 == 0 else SHORT_SPIKE_SHARE)
		var point := Vector2.from_angle(_turn + PI * float(i) / float(SPIKES)) * reach
		points.append(_direction * point.x * ALONG_STRETCH + across * point.y * ACROSS_STRETCH)
	return points


func _draw_ring() -> void:
	if _ring_ms <= _ring_from_ms or _age_ms < _ring_from_ms or _age_ms >= _ring_ms:
		return
	var t := (_age_ms - _ring_from_ms) / (_ring_ms - _ring_from_ms)
	var eased := 1.0 - (1.0 - t) * (1.0 - t)
	var radius := _radius * lerpf(RING_FROM_SHARE, RING_TO_SHARE, eased)
	var width := lerpf(RING_WIDTH_FROM, RING_WIDTH_TO, t)
	var alpha := 1.0 - t * t
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, RING_POINTS, Color(EDGE, alpha * 0.55), width + 2.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, RING_POINTS, Color(RING, alpha), width, true)


func _draw_rays() -> void:
	for ray: Dictionary in _rays:
		var life := float(ray["life"])
		if _age_ms >= life:
			continue
		var t := _age_ms / life
		var eased := 1.0 - (1.0 - t) * (1.0 - t)
		var unit := Vector2.from_angle(float(ray["angle"]))
		var head := unit * (_radius * RAY_START_SHARE + float(ray["speed"]) * eased * life / 1000.0)
		var tail := head - unit * float(ray["length"]) * (1.0 - t * 0.6)
		var color := CORE.lerp(BODY, clampf(t * 2.0, 0.0, 1.0)).lerp(EDGE, clampf(t * 2.0 - 1.0, 0.0, 1.0))
		draw_line(tail, head, Color(color, 1.0 - t * t), float(ray["width"]) * (1.0 - t * 0.5), true)


## The snap's streak: from its tail (which runs from `_snap_from` into the mouth) to the mouth, wide
## at the mouth, fading.
func _draw_snap() -> void:
	var t := clampf(_age_ms / maxf(1.0, _ring_ms), 0.0, 1.0)
	var tail := _snap_from * (1.0 - t) * (1.0 - t)
	if tail.length() < 1.0:
		return
	var across := tail.normalized().orthogonal()
	var alpha := 1.0 - t * t
	draw_colored_polygon(PackedVector2Array([across * SNAP_WIDTH.x * 0.5, tail + across * SNAP_WIDTH.y * 0.5,
		tail - across * SNAP_WIDTH.y * 0.5, -across * SNAP_WIDTH.x * 0.5]), Color(BODY, alpha * 0.9))
	draw_line(Vector2.ZERO, tail, Color(CORE, alpha), 2.0, true)


func _draw_puff() -> void:
	var t := clampf(_age_ms / maxf(1.0, _ring_ms), 0.0, 1.0)
	var eased := 1.0 - (1.0 - t) * (1.0 - t)
	var radius := _radius * lerpf(0.45, 1.0, eased)
	var width := lerpf(PUFF_WIDTH_FROM, PUFF_WIDTH_TO, t)
	var alpha := PUFF_ALPHA * (1.0 - t * t)
	var across := Vector2(-_direction.y, _direction.x)
	var centre := _direction * PUFF_DRIFT_PX * eased
	var points := PackedVector2Array()
	for i in RING_POINTS + 1:
		var angle := TAU * float(i) / float(RING_POINTS)
		points.append(centre + _direction * cos(angle) * radius * PUFF_FLAT + across * sin(angle) * radius)
	draw_polyline(points, Color(RING, alpha), width, true)
