@tool
extends Node2D
## The Crystal Mine's rails (docs/godot/DUNGEONS.md "The Crystal Mine (built)"): a track drawn on the
## floor along `points` (from this node, world units), two iron rails on wooden sleepers. Scenery
## only: the slime walks over it and nothing collides. The mine's rails are its leading lines: they
## run the main way from the Mine Mouth through the Lamp Tunnel to the Great Shaft, and from the
## cart's stations.
##
## Drawn under the walkers (z -1, a ground decal), so a dark room's darkness covers it like the floor.
##
## Owner: dungeons (the Crystal Mine).

## The track's middle line, from this node (world units). A corner is drawn as is (sharp).
@export var points: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2(256, 0)]):
	set(value):
		points = value
		queue_redraw()
## Half the gauge: each rail this far from the middle line.
@export var half_gauge: float = 15.0
@export var sleeper_every: float = 22.0
@export var sleeper_half_length: float = 24.0

const RAIL := Color(0.22, 0.2, 0.2, 0.95)
const RAIL_SHINE := Color(0.62, 0.6, 0.58, 0.8)
const SLEEPER := Color(0.36, 0.25, 0.16, 0.92)
const SLEEPER_EDGE := Color(0.2, 0.13, 0.08, 0.9)
const RAIL_WIDTH := 4.0
const SLEEPER_WIDTH := 9.0


func _ready() -> void:
	z_index = -1
	queue_redraw()


func _draw() -> void:
	if points.size() < 2:
		return
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		if length <= 0.0:
			continue
		var along := (b - a) / length
		var across := Vector2(-along.y, along.x)
		var t := sleeper_every * 0.5
		while t < length:
			var at := a + along * t
			draw_line(at - across * (sleeper_half_length + 1.0), at + across * (sleeper_half_length + 1.0), SLEEPER_EDGE, SLEEPER_WIDTH + 2.0)
			draw_line(at - across * sleeper_half_length, at + across * sleeper_half_length, SLEEPER, SLEEPER_WIDTH)
			t += sleeper_every
	for side: float in [-1.0, 1.0]:
		var line := PackedVector2Array()
		for i in points.size():
			var normal := _normal_at(i)
			line.append(points[i] + normal * half_gauge * side)
		draw_polyline(line, RAIL, RAIL_WIDTH)
		var shine := PackedVector2Array()
		for p in line:
			shine.append(p + Vector2(0, -1.5))
		draw_polyline(shine, RAIL_SHINE, 1.5)


## The track's sideways normal at point `i` (the mean of its two legs' at a corner).
func _normal_at(i: int) -> Vector2:
	var sum := Vector2.ZERO
	if i > 0:
		var d := (points[i] - points[i - 1]).normalized()
		sum += Vector2(-d.y, d.x)
	if i < points.size() - 1:
		var d := (points[i + 1] - points[i]).normalized()
		sum += Vector2(-d.y, d.x)
	if sum == Vector2.ZERO:
		return Vector2.UP
	var n := sum.normalized()
	# Keep the gauge at a corner: divide by the cosine of the half turn.
	var leg := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
	var cos_half := absf(n.dot(Vector2(-leg.y, leg.x)))
	return n / maxf(cos_half, 0.5)
