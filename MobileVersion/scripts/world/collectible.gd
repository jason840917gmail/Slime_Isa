extends Area2D

@export_enum("coin", "berry", "purple") var collectible_type := "coin"
@export var amount := 1
@export var collectible_id: StringName

@onready var visual: Polygon2D = $Visual

func _ready() -> void:
	if GameState.has_collected(collectible_id):
		queue_free()
		return

	body_entered.connect(_on_body_entered)
	if collectible_type == "coin":
		visual.color = Color(1.0, 0.82, 0.18)
	elif collectible_type == "purple":
		visual.color = Color(0.56, 0.27, 0.68)
	else:
		visual.color = Color(0.95, 0.24, 0.42)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	if body.has_method("play_pickup_animation"):
		body.call("play_pickup_animation")

	if collectible_type == "coin" or collectible_type == "purple":
		GameState.add_coins(amount)
		GameState.show_message("Collected %d coin." % amount)
	else:
		GameState.add_berries(amount)
		GameState.show_message("Collected %d berry." % amount)

	GameState.mark_collected(collectible_id)
	AudioManager.play_sfx(&"pickup")
	SaveSystem.save_game()
	queue_free()
