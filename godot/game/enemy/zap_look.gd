extends Node2D
## The Jelly Bouncer's zap, drawn in code (docs/godot/BESTIARY.md "39. Jelly Bouncer"): two of these
## sit on his body's feet point.
## - **The ring** (`ring`, drawn behind him): during his charge, the edge of the zap's reach on the
##   ground, flickering brighter as the zap nears (`show_ring(radius, strength)`), so the slime knows
##   how far to step back.
## - **The bolts** (`bolts`, drawn over everything near him): during the zap, jagged lightning from his
##   middle to each body it struck and out to the ring's edge (`show_bolts(middle, ends)`), new every
##   frame.
## Presentation only.
##
## Owner: enemy builder.

const RING_COLOR := Color(1.0, 0.93, 0.45)
const RING_FILL := Color(0.55, 0.95, 1.0)
const RING_POINTS := 48
const RING_WIDTH := 2.0
const BOLT_CORE := Color(1.0, 0.98, 0.75, 1.0)
const BOLT_GLOW := Color(0.5, 0.92, 1.0, 0.5)
const BOLT_SEGMENTS := 6
const BOLT_JAG := 0.22
const BOLT_WIDTH := 2.2
const BOLT_GLOW_WIDTH := 6.0

## Draws the ring (true) or the bolts (false).
var ring: bool = true

var _radius: float = 0.0
var _strength: float = 0.0
var _middle: Vector2 = Vector2.ZERO
var _ends: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## The ring at `radius` (local px round the feet), `strength` 0..1 (0 hides it).
func show_ring(radius: float, strength: float) -> void:
	_radius = radius
	_strength = clampf(strength, 0.0, 1.0)
	queue_redraw()


## Bolts from `middle` to each of `ends` (local points); none hides them.
func show_bolts(middle: Vector2, ends: Array[Vector2]) -> void:
	_middle = middle
	_ends = ends
	queue_redraw()


func clear() -> void:
	_strength = 0.0
	_ends = []
	queue_redraw()


func _draw() -> void:
	if ring:
		_draw_ring()
	else:
		_draw_bolts()


func _draw_ring() -> void:
	if _strength <= 0.0 or _radius <= 0.0:
		return
	var points := PackedVector2Array()
	for i in RING_POINTS + 1:
		points.append(Vector2.from_angle(TAU * float(i) / float(RING_POINTS)) * _radius)
	var fill := PackedVector2Array(points)
	fill.remove_at(fill.size() - 1)
	draw_colored_polygon(fill, Color(RING_FILL, 0.10 * _strength))
	draw_polyline(points, Color(RING_COLOR, 0.25 + 0.6 * _strength), RING_WIDTH, true)


func _draw_bolts() -> void:
	for end: Vector2 in _ends:
		var points := PackedVector2Array([_middle])
		var line := end - _middle
		var side := line.orthogonal().normalized()
		for k in range(1, BOLT_SEGMENTS):
			var along := _middle + line * (float(k) / float(BOLT_SEGMENTS))
			points.append(along + side * line.length() * BOLT_JAG * _rng.randf_range(-0.5, 0.5))
		points.append(end)
		draw_polyline(points, BOLT_GLOW, BOLT_GLOW_WIDTH, true)
		draw_polyline(points, BOLT_CORE, BOLT_WIDTH, true)
