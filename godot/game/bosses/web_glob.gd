extends Node2D
## A glob of web the Orb-Weaver Matron spits at a knock target to let its ram go at the slime (her
## ram call, game/bosses/matron_ram.gd; docs/godot/specs/matron.md section 9). It flies in an arc from
## `from` to the target's disc over `flight_ms` of gameplay time, trailing a thread, then knocks the
## target (`strike()`: an armed target spins and lets its ram go) with a splat of silk. Not a hit: the
## slime cannot block it, only step off the lane.
##
## Owner: boss port (the Matron).

const Services := preload("res://game/shared/services.gd")

const GLOB_COLOR := Color(0.97, 0.94, 0.82)
const OUTLINE := Color(0.32, 0.22, 0.18, 0.9)
const THREAD := Color(0.97, 0.93, 0.82, 0.7)
const RADIUS := 7.0
const SPLAT := &"dodge-dust"
## The target's disc sits this far above its foot (knock_target.gd: the disc on its post).
const DISC_ABOVE_FOOT := Vector2(0.0, -44.0)

var from: Vector2 = Vector2.ZERO
var target: Node2D
var flight_ms: float = 450.0
var arc_px: float = 70.0
## Its size (1: a glob RADIUS wide), set to her size by matron_ram.gd.
var size: float = 1.0

var _start_ms: float = 0.0
var _to: Vector2 = Vector2.ZERO
var _done: bool = false


func _ready() -> void:
	_start_ms = Services.now_ms()
	_to = target.global_position + DISC_ABOVE_FOOT if target != null else from
	global_position = from
	z_index = 20


func _physics_process(_delta: float) -> void:
	if _done:
		return
	var t := clampf((Services.now_ms() - _start_ms) / maxf(1.0, flight_ms), 0.0, 1.0)
	global_position = from.lerp(_to, t) - Vector2(0.0, arc_px * sin(t * PI))
	queue_redraw()
	if t >= 1.0:
		_arrive()


func _arrive() -> void:
	_done = true
	if target != null and is_instance_valid(target) and target.has_method(&"strike"):
		target.call(&"strike")
	var feel := Services.feel()
	if feel != null:
		feel.particles(SPLAT, _to)
	queue_free()


func _draw() -> void:
	# the thread back toward her mouth, then the glob
	var r := RADIUS * size
	draw_line(Vector2.ZERO, (from - global_position) * 0.25, THREAD, 2.0 * size, true)
	draw_circle(Vector2.ZERO, r + 1.5 * size, OUTLINE)
	draw_circle(Vector2.ZERO, r, GLOB_COLOR)
	draw_circle(Vector2(-0.3, -0.3) * r, r * 0.35, Color(1.0, 1.0, 1.0, 0.8))
