extends CharacterBody2D

const SPEED := 48.0
const COLOR_VARIANTS := [
	Color(1.0, 0.78, 0.42),
	Color(0.55, 0.82, 1.0),
	Color(1.0, 0.71, 0.71),
	Color(0.60, 1.0, 0.60),
	Color(0.85, 0.66, 1.0),
]

@export var wander_bounds := Rect2(0.0, 0.0, 3456.0, 3456.0)

@onready var face: Polygon2D = $Face
@onready var left_eye: Polygon2D = $LeftEye
@onready var right_eye: Polygon2D = $RightEye
@onready var mouth: Polygon2D = $Mouth
@onready var ears: Polygon2D = $Ears

var home: Node2D
var _wander_target := Vector2.ZERO
var _next_wander_at := 0.0
var _next_face_change_at := 0.0
var _next_color_change_at := 0.0
var _next_ear_change_at := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_pick_new_target()
	_apply_random_face()
	_apply_random_color()
	_apply_random_ears()
	_next_face_change_at = _now() + _rng.randf_range(0.8, 3.2)
	_next_color_change_at = _now() + _rng.randf_range(4.0, 10.0)
	_next_ear_change_at = _now() + _rng.randf_range(5.0, 15.0)


func _physics_process(_delta: float) -> void:
	var time := _now()

	if time >= _next_face_change_at:
		_apply_random_face()
		_next_face_change_at = time + _rng.randf_range(0.8, 4.2)

	if time >= _next_color_change_at:
		_apply_random_color()
		_next_color_change_at = time + _rng.randf_range(4.0, 10.0)

	if time >= _next_ear_change_at:
		_apply_random_ears()
		_next_ear_change_at = time + _rng.randf_range(5.0, 15.0)

	if time >= _next_wander_at or global_position.distance_squared_to(_wander_target) < 100.0:
		_pick_new_target()

	var direction := global_position.direction_to(_wander_target)
	velocity = direction * SPEED
	move_and_slide()


func _pick_new_target() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var radius := _rng.randf_range(24.0, 120.0)
	_wander_target = global_position + Vector2(cos(angle), sin(angle)) * radius
	_wander_target.x = clampf(_wander_target.x, wander_bounds.position.x, wander_bounds.position.x + wander_bounds.size.x)
	_wander_target.y = clampf(_wander_target.y, wander_bounds.position.y, wander_bounds.position.y + wander_bounds.size.y)
	_next_wander_at = _now() + _rng.randf_range(1.2, 4.2)


func _apply_random_color() -> void:
	var color := COLOR_VARIANTS[_rng.randi_range(0, COLOR_VARIANTS.size() - 1)] as Color
	face.color = color
	ears.color = color


func _apply_random_face() -> void:
	var variant := _rng.randi_range(0, 3)
	left_eye.visible = true
	right_eye.visible = true
	mouth.visible = true
	mouth.color = Color(0.17, 0.17, 0.17)
	mouth.polygon = _rect_points(Vector2(-2.0, 5.0), Vector2(4.0, 1.5))

	if variant == 0:
		pass
	elif variant == 1:
		mouth.polygon = _rect_points(Vector2(-4.0, 5.0), Vector2(8.0, 2.5))
	elif variant == 2:
		left_eye.visible = false
		mouth.polygon = _rect_points(Vector2(-3.0, 5.0), Vector2(6.0, 1.5))
	else:
		mouth.color = Color(1.0, 0.42, 0.42)
		mouth.polygon = _circle_points(Vector2(0.0, 5.0), 2.5, 10)


func _apply_random_ears() -> void:
	var variant := _rng.randi_range(0, 3)
	if variant == 0:
		ears.polygon = PackedVector2Array([Vector2(-10, -7), Vector2(-5, -20), Vector2(0, -7), Vector2(0, -7), Vector2(5, -20), Vector2(10, -7)])
	elif variant == 1:
		ears.polygon = PackedVector2Array([Vector2(-8, -8), Vector2(-8, -28), Vector2(-3, -28), Vector2(-3, -8), Vector2(3, -8), Vector2(3, -28), Vector2(8, -28), Vector2(8, -8)])
	elif variant == 2:
		ears.polygon = PackedVector2Array([Vector2(-11, -8), Vector2(-15, -18), Vector2(-8, -20), Vector2(-3, -8), Vector2(3, -8), Vector2(8, -20), Vector2(15, -18), Vector2(11, -8)])
	else:
		ears.polygon = PackedVector2Array([Vector2(-10, -7), Vector2(-4, -22), Vector2(0, -7), Vector2(0, -7), Vector2(4, -22), Vector2(10, -7)])


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _circle_points(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _rect_points(position: Vector2, size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		position,
		position + Vector2(size.x, 0.0),
		position + size,
		position + Vector2(0.0, size.y),
	])
