extends Node2D
## What the ability ceremony draws over the slime (game/ui/ceremony/ability_ceremony.gd sets
## `rise`, `age` and the sparkles each frame): light rays turning behind a glossy goo bubble that
## wells out of the slime, and sparkles drifting off it. Coordinates are relative to the slime's
## centre, in world px (the ceremony scales this node by the camera's zoom).
##
## Owner: ui.

const BUBBLE_RADIUS := 42.0
const BUBBLE_RISE := 92.0
const BUBBLE_COLOR := Color(0.55, 0.95, 0.6, 0.42)
const BUBBLE_RIM := Color(0.9, 1.0, 0.9, 0.9)
const GLOW_COLOR := Color(1.0, 0.95, 0.6, 0.3)
const RAY_COUNT := 14
const RAY_LENGTH := 170.0
const RAY_COLOR := Color(1.0, 0.92, 0.55, 0.5)
const RAY_TURN := 0.6
const SPARKLE_LIFE_S := 0.9
const SPARKLE_COLOR := Color(1.0, 0.97, 0.75)

## 0 (inside the slime) .. 1 (floating above it).
var rise: float = 0.0
## Seconds since the ceremony began (the wobble and the rays turn with it).
var age: float = 0.0
## [{"at": Vector2, "velocity": Vector2, "age": float}], relative to this node.
var sparkles: Array[Dictionary] = []


## The bubble's centre at `at_rise` (0..1): it wells out of the top of the slime and bobs.
func bubble_centre(at_rise: float) -> Vector2:
	var bob := sin(age * 2.0) * 3.0 * at_rise
	return Vector2(0.0, -BUBBLE_RISE * ease(at_rise, 0.4) + bob)


func spawn_sparkle(origin: Vector2, speed: float) -> void:
	var direction := Vector2.RIGHT.rotated(randf() * TAU)
	sparkles.append({"at": origin + direction * BUBBLE_RADIUS * 0.8, "velocity": direction * speed, "age": 0.0})


func age_sparkles(delta: float) -> void:
	for sparkle: Dictionary in sparkles:
		sparkle["age"] = float(sparkle["age"]) + delta
		sparkle["at"] = (sparkle["at"] as Vector2) + (sparkle["velocity"] as Vector2) * delta
		sparkle["velocity"] = (sparkle["velocity"] as Vector2) * 0.94
	sparkles = sparkles.filter(func(sparkle: Dictionary) -> bool: return float(sparkle["age"]) < SPARKLE_LIFE_S)


func _draw() -> void:
	if rise > 0.01:
		var centre := bubble_centre(rise)
		var radius := BUBBLE_RADIUS * (0.25 + 0.75 * rise)
		# Light rays turning behind the bubble, over a soft glow.
		draw_circle(centre, radius * 2.2, Color(GLOW_COLOR, GLOW_COLOR.a * rise))
		var turn := age * RAY_TURN
		for i in RAY_COUNT:
			var angle := turn + TAU * i / RAY_COUNT
			var tip := centre + Vector2.RIGHT.rotated(angle) * RAY_LENGTH * rise
			var side := Vector2.RIGHT.rotated(angle + PI * 0.5) * radius * 0.35
			draw_colored_polygon(PackedVector2Array([centre + side, centre - side, tip]), Color(RAY_COLOR, RAY_COLOR.a * rise))
		# The goo bubble: a wobbling body, a rim and a highlight.
		var wobble := Vector2(1.0 + 0.06 * sin(age * 7.0), 1.0 - 0.06 * sin(age * 7.0))
		var points := PackedVector2Array()
		for i in 32:
			var angle := TAU * i / 32.0
			points.append(centre + Vector2(cos(angle) * wobble.x, sin(angle) * wobble.y) * radius)
		draw_colored_polygon(points, BUBBLE_COLOR)
		points.append(points[0])
		draw_polyline(points, BUBBLE_RIM, 2.0, true)
		draw_circle(centre + Vector2(-0.35, -0.4) * radius, radius * 0.18, Color(1.0, 1.0, 1.0, 0.8))
	for sparkle: Dictionary in sparkles:
		var life := 1.0 - float(sparkle["age"]) / SPARKLE_LIFE_S
		var at: Vector2 = sparkle["at"]
		var size := 3.0 * life + 1.0
		var colour := Color(SPARKLE_COLOR, life)
		draw_line(at - Vector2(size, 0.0), at + Vector2(size, 0.0), colour, 1.5)
		draw_line(at - Vector2(0.0, size), at + Vector2(0.0, size), colour, 1.5)
