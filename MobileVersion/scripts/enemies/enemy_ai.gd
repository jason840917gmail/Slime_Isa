extends CharacterBody2D

@export var speed := 70.0
@export var wander_radius := 80.0

var _spawn_position := Vector2.ZERO
var _target_position := Vector2.ZERO

func _ready() -> void:
	_spawn_position = global_position
	_pick_target()


func _physics_process(_delta: float) -> void:
	var direction := global_position.direction_to(_target_position)
	velocity = direction * speed
	move_and_slide()

	if global_position.distance_to(_target_position) < 8.0:
		_pick_target()


func _pick_target() -> void:
	_target_position = _spawn_position + Vector2(randf_range(-wander_radius, wander_radius), randf_range(-wander_radius, wander_radius))
