extends Node

signal save_status_changed(message: String)

const SAVE_PATH := "user://savegame.json"

func save_game() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		var message := "Could not open save file for writing: %s" % FileAccess.get_open_error()
		save_status_changed.emit(message)
		push_error(message)
		return false

	file.store_string(JSON.stringify(GameState.get_save_data(), "\t"))
	save_status_changed.emit("Saved to %s" % SAVE_PATH)
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		save_status_changed.emit("No save found at %s" % SAVE_PATH)
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		var message := "Could not open save file for reading: %s" % FileAccess.get_open_error()
		save_status_changed.emit(message)
		push_error(message)
		return false

	var parsed_data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed_data) != TYPE_DICTIONARY:
		save_status_changed.emit("Save file is not valid JSON object data.")
		push_error("Save file is not valid JSON object data.")
		return false

	var data: Dictionary = parsed_data as Dictionary
	GameState.apply_save_data(data)
	save_status_changed.emit("Loaded %s" % SAVE_PATH)
	return true


func reset_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	save_status_changed.emit("Reset %s" % SAVE_PATH)
