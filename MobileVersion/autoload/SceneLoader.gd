extends Node

signal loading_status_changed(message: String)

const LOADING_SCREEN_SCENE := "res://scenes/ui/LoadingScreen.tscn"

var current_scene_path := "res://scenes/Main.tscn"
var _loading_screen: CanvasLayer

func change_scene(scene_path: String) -> void:
	_show_loading_screen()
	loading_status_changed.emit("Loading %s" % scene_path.get_file())
	current_scene_path = scene_path
	call_deferred("_change_scene_deferred", scene_path)


func reload_current_scene() -> void:
	change_scene(current_scene_path)


func _change_scene_deferred(scene_path: String) -> void:
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		loading_status_changed.emit("Scene load failed: %s" % error)
		push_error("Could not change scene to %s: %s" % [scene_path, error])
		_hide_loading_screen()
		return

	loading_status_changed.emit("Loaded %s" % scene_path.get_file())
	_hide_loading_screen()


func _show_loading_screen() -> void:
	if _loading_screen != null:
		return

	var scene := load(LOADING_SCREEN_SCENE) as PackedScene
	if scene == null:
		return

	_loading_screen = scene.instantiate() as CanvasLayer
	get_tree().root.add_child(_loading_screen)


func _hide_loading_screen() -> void:
	if _loading_screen == null:
		return

	_loading_screen.queue_free()
	_loading_screen = null
