extends Node2D
## Two small eyes glinting in the dark (the bestiary's Pipe Worm hiding in its pipe,
## docs/godot/BESTIARY.md): a pair of golden dots `spacing` px apart that blink now and then, so a
## hidden enemy never looks like an empty, harmless hole (the clarity rule). `shown` turns them on
## and off. Presentation only (real time).
##
## Owner: enemy builder.

const COLOR := Color("#ffd257")
const RIM := Color(0.18, 0.08, 0.02, 0.9)
const SIZE := Vector2(2.6, 1.6)
const POINTS := 12
## A blink of BLINK_MS every BLINK_EVERY_MS.
const BLINK_EVERY_MS := 2300
const BLINK_MS := 140

@export var spacing: float = 9.0
@export var shown: bool = true:
	set(value):
		shown = value
		queue_redraw()


func _process(_delta: float) -> void:
	if shown:
		queue_redraw()


func _draw() -> void:
	if not shown or Time.get_ticks_msec() % BLINK_EVERY_MS < BLINK_MS:
		return
	for side: float in [-0.5, 0.5]:
		var centre := Vector2(side * spacing, 0.0)
		draw_colored_polygon(_ellipse(centre, SIZE + Vector2(1.0, 1.0)), RIM)
		draw_colored_polygon(_ellipse(centre, SIZE), COLOR)


func _ellipse(centre: Vector2, half: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in POINTS:
		var angle := TAU * float(i) / float(POINTS)
		points.append(centre + Vector2(cos(angle) * half.x, sin(angle) * half.y))
	return points
