extends Node

signal coins_changed(total: int)
signal berries_changed(total: int)
signal player_health_changed(value: int)
signal friends_changed(total: int)
signal level_changed(level_id: StringName)
signal ability_used(ability_id: StringName)
signal message_changed(text: String)

const SAVE_VERSION := 1

var coins := 50
var berries := 0
var player_health := 3
var friends := 0
var current_level: StringName = &"test_level"
var player_position := Vector2.ZERO
var player_facing_direction := Vector2.DOWN
var unlocked_abilities: Array[StringName] = [&"jump", &"roll", &"interact"]
var collected_items: Array[StringName] = []

func add_coins(amount: int) -> void:
	coins = max(0, coins + amount)
	coins_changed.emit(coins)


func add_berries(amount: int) -> void:
	berries = max(0, berries + amount)
	berries_changed.emit(berries)


func set_friends(total: int) -> void:
	friends = max(0, total)
	friends_changed.emit(friends)


func set_player_health(value: int) -> void:
	player_health = max(0, value)
	player_health_changed.emit(player_health)


func set_player_facing_direction(direction: Vector2) -> void:
	if direction.length_squared() == 0.0:
		return

	player_facing_direction = direction.normalized()


func set_current_level(level_id: StringName) -> void:
	current_level = level_id
	level_changed.emit(current_level)


func use_ability(ability_id: StringName) -> void:
	if unlocked_abilities.has(ability_id):
		ability_used.emit(ability_id)


func show_message(text: String) -> void:
	message_changed.emit(text)


func has_collected(item_id: StringName) -> bool:
	return item_id != &"" and collected_items.has(item_id)


func mark_collected(item_id: StringName) -> void:
	if item_id == &"" or collected_items.has(item_id):
		return

	collected_items.append(item_id)


func get_save_data() -> Dictionary:
	var abilities: Array[String] = []
	for ability_id in unlocked_abilities:
		abilities.append(String(ability_id))

	return {
		"version": SAVE_VERSION,
		"coins": coins,
		"berries": berries,
		"friends": friends,
		"current_level": String(current_level),
		"player": {
			"position": [player_position.x, player_position.y],
			"facing_direction": [player_facing_direction.x, player_facing_direction.y],
			"health": player_health,
			"unlocked_abilities": abilities,
		},
		"collected_items": _stringify_names(collected_items),
		"settings": {
			"music_volume": AudioManager.music_volume,
			"sfx_volume": AudioManager.sfx_volume,
		},
	}


func apply_save_data(data: Dictionary) -> void:
	coins = int(data.get("coins", 50))
	berries = int(data.get("berries", 0))
	friends = int(data.get("friends", 0))
	current_level = StringName(data.get("current_level", "test_level"))

	var player := data.get("player", {}) as Dictionary
	player_health = int(player.get("health", 3))

	var saved_position := player.get("position", [0.0, 0.0]) as Array
	if saved_position.size() >= 2:
		player_position = Vector2(float(saved_position[0]), float(saved_position[1]))

	var saved_facing_direction := player.get("facing_direction", [0.0, 1.0]) as Array
	if saved_facing_direction.size() >= 2:
		set_player_facing_direction(Vector2(float(saved_facing_direction[0]), float(saved_facing_direction[1])))

	unlocked_abilities.clear()
	for ability_id in player.get("unlocked_abilities", ["jump", "roll", "interact"]):
		unlocked_abilities.append(StringName(ability_id))

	collected_items.clear()
	for item_id in data.get("collected_items", []):
		collected_items.append(StringName(item_id))

	var settings := data.get("settings", {}) as Dictionary
	AudioManager.set_music_volume(float(settings.get("music_volume", AudioManager.music_volume)))
	AudioManager.set_sfx_volume(float(settings.get("sfx_volume", AudioManager.sfx_volume)))

	coins_changed.emit(coins)
	berries_changed.emit(berries)
	friends_changed.emit(friends)
	player_health_changed.emit(player_health)
	level_changed.emit(current_level)


func _stringify_names(names: Array[StringName]) -> Array[String]:
	var strings: Array[String] = []
	for value in names:
		strings.append(String(value))
	return strings
