@tool
extends Node2D
## A dungeon room scene (docs/godot/DUNGEON_ROOMS.md). F6 on it plays it:
## - a room that is its own world (Fatty's Lair since 2026-10-18: it has a `world-definition`) runs
##   as any world does (game/scripts/world_definition.gd), with the dungeon's direct-run powers;
## - a room of a shell (the Weaver Hollow, the Crystal Mine) opens its dungeon's world at this room.
@export var world_id: String = ""
@export var room_id: String = ""


func _ready() -> void:
	if Engine.is_editor_hint() or get_tree().current_scene != self:
		return
	if get_node_or_null(^"world-definition") != null:
		return
	_run.call_deferred()


func _run() -> void:
	var main := (load("res://game/main.tscn") as PackedScene).instantiate()
	main.set(&"map_id", world_id)
	main.set(&"direct_world_run", true)
	main.set(&"direct_room_run", room_id)
	get_tree().change_scene_to_node(main)
