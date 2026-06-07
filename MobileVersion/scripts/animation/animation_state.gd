extends Node

var current_state: StringName = &"idle"

func set_state(next_state: StringName) -> void:
	if current_state == next_state:
		return

	current_state = next_state
