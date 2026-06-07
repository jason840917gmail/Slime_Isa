extends Node2D

@export var interactable_id: StringName = &"house"
@export var prompt_text := "A cozy slime house. Shop and NPC systems can attach here later."

func _ready() -> void:
	add_to_group("interactable")
	if interactable_id == &"house":
		add_to_group("houses")


func interact() -> void:
	AudioManager.play_sfx(&"interact")
	GameState.show_message(prompt_text)
