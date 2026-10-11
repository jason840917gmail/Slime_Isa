extends CharacterBody2D
## Standalone collision probe; same mover as gameplay, no saves or world registration.
const ArcadeMover := preload("res://game/shared/arcade_mover.gd")
@export var speed: float = 190.0


func _physics_process(delta: float) -> void:
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	velocity = direction.normalized() * speed
	ArcadeMover.move(self, delta)

