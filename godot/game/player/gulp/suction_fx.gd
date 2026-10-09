extends Node2D
## The suck's placeholder effect (owner, 2026-10-08; roadmap 7.5 assets): pale streaks rushing
## from a cone in front of the slime into its mouth while Q is held. Drawn in code on the slime's
## body; `direction` is where the slime sucks from, `reach` how far.
##
## Owner: abilities.

const STREAKS := 7
const SPEED := 2.4
const COLOR := Color(0.92, 1.0, 0.96, 0.75)
const WIDTH := 2.0
const MOUTH_RISE := 22.0

var direction: Vector2 = Vector2.DOWN
var reach: float = 120.0
var cone_deg: float = 60.0
var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var mouth := Vector2(0.0, -MOUTH_RISE)
	var half := deg_to_rad(cone_deg) * 0.5
	for i in STREAKS:
		var phase := fposmod(_time * SPEED + float(i) / STREAKS, 1.0)
		var angle := lerpf(-half, half, (float(i) + 0.5) / STREAKS)
		var ray := direction.rotated(angle)
		var far := mouth + ray * reach * (1.0 - phase)
		var near := mouth + ray * reach * maxf(0.0, 1.0 - phase - 0.22)
		var fade := Color(COLOR, COLOR.a * phase)
		draw_line(far, near, fade, WIDTH)
