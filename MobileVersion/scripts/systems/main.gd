extends Node2D

@export var default_level_scene: PackedScene
@export var player_scene: PackedScene

@onready var level_root: Node2D = $GameRoot/LevelRoot
@onready var player_root: Node2D = $GameRoot/PlayerRoot

var level: Node2D
var player: CharacterBody2D

func _ready() -> void:
	SceneLoader.current_scene_path = scene_file_path
	SaveSystem.load_game()
	_load_level()
	_spawn_player()
	_configure_camera()
	GameState.show_message("Explore the meadow. Collect coins and berries, then interact with the house.")


func _process(_delta: float) -> void:
	if InputManager.consume_action_just_pressed(&"pause"):
		SaveSystem.save_game()
		AudioManager.play_sfx(&"click")
		GameState.show_message("Pause requested. Pause menu can attach here next.")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		SaveSystem.save_game()
		InputManager.clear_virtual_state()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		GameState.show_message("Welcome back to the meadow.")


func _load_level() -> void:
	if default_level_scene == null:
		push_error("Main.gd is missing default_level_scene.")
		return

	level = default_level_scene.instantiate() as Node2D
	level_root.add_child(level)


func _spawn_player() -> void:
	if player_scene == null:
		push_error("Main.gd is missing player_scene.")
		return

	player = player_scene.instantiate() as CharacterBody2D
	player_root.add_child(player)

	var spawn_position := Vector2.ZERO
	if level != null and level.has_method("get_player_spawn_position"):
		spawn_position = level.call("get_player_spawn_position") as Vector2

	var saved_position_valid := GameState.player_position != Vector2.ZERO
	if saved_position_valid and level != null and level.has_method("is_position_in_bounds"):
		saved_position_valid = bool(level.call("is_position_in_bounds", GameState.player_position))

	player.global_position = GameState.player_position if saved_position_valid else spawn_position
	player.connect("interaction_requested", Callable(self, "_on_player_interaction_requested"))


func _configure_camera() -> void:
	if player == null:
		return

	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return

	if level != null and level.has_method("get_camera_bounds"):
		var bounds := level.call("get_camera_bounds") as Rect2
		camera.limit_left = int(bounds.position.x)
		camera.limit_top = int(bounds.position.y)
		camera.limit_right = int(bounds.position.x + bounds.size.x)
		camera.limit_bottom = int(bounds.position.y + bounds.size.y)

	if level != null and level.has_method("get_camera_zoom"):
		camera.zoom = level.call("get_camera_zoom") as Vector2

	if level != null and level.has_method("get_camera_smoothing_speed"):
		camera.position_smoothing_speed = float(level.call("get_camera_smoothing_speed"))


func _on_player_interaction_requested(player_position: Vector2) -> void:
	if level != null and level.has_method("request_interaction"):
		level.call("request_interaction", player_position)
