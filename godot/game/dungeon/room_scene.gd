@tool
extends Node2D
## F6 opens this authored room in the game with the dungeon's normal direct-run powers.
@export var world_id: String = ""
@export var room_id: String = ""
func _ready() -> void:
	if Engine.is_editor_hint() or get_tree().current_scene != self:
		return
	_run.call_deferred()
func _run() -> void:
	var main := (load("res://game/main.tscn") as PackedScene).instantiate()
	main.set(&"map_id", world_id)
	main.set(&"direct_world_run", true)
	main.set(&"direct_room_run", room_id)
	get_tree().change_scene_to_node(main)
