extends Node2D

const TILE_SIZE := 64
const WORLD_TILES_X := 54
const WORLD_TILES_Y := 54
const WORLD_WIDTH := WORLD_TILES_X * TILE_SIZE
const WORLD_HEIGHT := WORLD_TILES_Y * TILE_SIZE
const FRIEND_COUNT := 84
const HOUSE_COUNT := 4
const FRIEND_SCENE := preload("res://scenes/friends/Friend.tscn")
const COLLECTIBLE_SCENE := preload("res://scenes/collectibles/Collectible.tscn")
const HOUSE_SCENE := preload("res://scenes/world/House.tscn")
const HOUSE_OFFSETS := [Vector2i(0, 0), Vector2i(6, -4), Vector2i(-7, 5), Vector2i(8, 7)]

@export var interaction_radius := 84.0
@export var camera_zoom := Vector2(1.0, 1.0)
@export var camera_smoothing_speed := 8.0

var camera_bounds := Rect2(0.0, 0.0, WORLD_WIDTH, WORLD_HEIGHT)
var _terrain_grid: Array = []
var _textures: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _spawn_position := Vector2(WORLD_WIDTH / 2.0, WORLD_HEIGHT / 2.0)

@onready var tiles_root: Node2D = $World/Tiles
@onready var collision_root: Node2D = $World/Collision
@onready var decoration_root: Node2D = $World/Decorations
@onready var collectible_root: Node2D = $World/Collectibles
@onready var friend_root: Node2D = $World/Friends
@onready var house_root: Node2D = $World/Houses

func _ready() -> void:
	add_to_group("level")
	_rng.seed = 1337
	GameState.set_current_level(&"test_level")
	_create_world_textures()
	_build_world()
	_spawn_position = _spawn_houses(HOUSE_COUNT)
	var spawn := get_node_or_null("SpawnPoints/PlayerSpawn") as Node2D
	if spawn != null:
		spawn.global_position = _spawn_position
	_spawn_friends(FRIEND_COUNT)
	GameState.set_friends(friend_root.get_child_count())


func request_interaction(player_position: Vector2) -> void:
	var closest: Node2D = null
	var closest_distance := interaction_radius

	for node in get_tree().get_nodes_in_group("interactable"):
		if not (node is Node2D):
			continue

		if not node.has_method("interact"):
			continue

		var interactable := node as Node2D
		var distance := player_position.distance_to(interactable.global_position)
		if distance <= closest_distance:
			closest = interactable
			closest_distance = distance

	if closest == null:
		GameState.show_message("Nothing nearby to interact with.")
		return

	closest.call("interact")


func get_player_spawn_position() -> Vector2:
	return _spawn_position


func get_camera_bounds() -> Rect2:
	return camera_bounds


func get_camera_zoom() -> Vector2:
	return camera_zoom


func get_camera_smoothing_speed() -> float:
	return camera_smoothing_speed


func is_position_in_bounds(position: Vector2) -> bool:
	return camera_bounds.has_point(position)


func _build_world() -> void:
	_terrain_grid.clear()

	for tile_y in range(WORLD_TILES_Y):
		var row: Array = []
		for tile_x in range(WORLD_TILES_X):
			var world_position := Vector2(tile_x * TILE_SIZE, tile_y * TILE_SIZE)
			var noise := _sample(tile_x, tile_y)
			var tile_id := _resolve_world_tile(tile_x, tile_y)
			row.append(tile_id)
			_create_world_tile(tile_id, world_position)

			if _allows_decorations(tile_id) and noise > 0.62 and _sample(tile_x + 11, tile_y - 7) > 0.5:
				_create_decoration("flower", world_position + Vector2(42.0, 24.0), _rng.randf_range(0.9, 1.2), 0.0)

			if _allows_decorations(tile_id) and noise > 0.45 and _sample(tile_x + 5, tile_y + 3) > 0.86:
				_spawn_purple(world_position + Vector2(_rng.randi_range(20, 44), _rng.randi_range(20, 44)), tile_x, tile_y)

			if _allows_decorations(tile_id) and noise < 0.18 and _sample(tile_x - 5, tile_y + 9) > 0.62:
				_create_decoration("stone", world_position + Vector2(28.0, 34.0), 1.0, _rng.randf_range(-0.3, 0.3))

		_terrain_grid.append(row)


func _create_world_tile(tile_id: String, world_position: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = _textures[tile_id] as Texture2D
	sprite.centered = false
	sprite.position = world_position
	sprite.z_index = 0
	tiles_root.add_child(sprite)

	if tile_id != "rock-wall":
		return

	var body := StaticBody2D.new()
	body.position = world_position
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE - 8.0, TILE_SIZE - 8.0)
	shape.shape = rect
	shape.position = Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	body.add_child(shape)
	collision_root.add_child(body)


func _create_decoration(texture_id: String, world_position: Vector2, sprite_scale: float, rotation: float) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = _textures[texture_id] as Texture2D
	sprite.position = world_position
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.rotation = rotation
	sprite.z_index = 2
	decoration_root.add_child(sprite)


func _spawn_purple(world_position: Vector2, tile_x: int, tile_y: int) -> void:
	var collectible := COLLECTIBLE_SCENE.instantiate() as Area2D
	collectible.position = world_position
	collectible.set("collectible_type", "purple")
	collectible.set("amount", 5)
	collectible.set("collectible_id", StringName("purple_%d_%d" % [tile_x, tile_y]))
	collectible_root.add_child(collectible)


func _spawn_friends(count: int) -> void:
	for i in range(count):
		var friend := FRIEND_SCENE.instantiate() as CharacterBody2D
		friend.global_position = _find_spawn_point(i + 1)
		friend.set("wander_bounds", camera_bounds)
		friend_root.add_child(friend)


func _spawn_houses(count: int) -> Vector2:
	var first_spawn := _find_spawn_point()
	var center_tile := Vector2i(int(WORLD_TILES_X / 2), int(WORLD_TILES_Y / 2))

	for i in range(count):
		var offset := HOUSE_OFFSETS[i % HOUSE_OFFSETS.size()] as Vector2i
		var tile := _find_house_tile(center_tile.x + offset.x, center_tile.y + offset.y)
		var house := HOUSE_SCENE.instantiate() as Node2D
		house.position = Vector2(tile.x * TILE_SIZE + TILE_SIZE / 2.0, tile.y * TILE_SIZE + TILE_SIZE / 2.0)
		house.z_index = 3
		house_root.add_child(house)

		if i == 0:
			first_spawn = house.global_position + Vector2(0.0, 72.0)

	return first_spawn


func _find_house_tile(start_x: int, start_y: int) -> Vector2i:
	var max_radius := maxi(WORLD_TILES_X, WORLD_TILES_Y)

	for radius in range(max_radius):
		for tile_y in range(start_y - radius, start_y + radius + 1):
			for tile_x in range(start_x - radius, start_x + radius + 1):
				var wrapped_x := posmod(tile_x, WORLD_TILES_X)
				var wrapped_y := posmod(tile_y, WORLD_TILES_Y)
				if _is_house_tile(wrapped_x, wrapped_y):
					return Vector2i(wrapped_x, wrapped_y)

	return Vector2i(int(WORLD_TILES_X / 2), int(WORLD_TILES_Y / 2))


func _find_spawn_point(offset := 0) -> Vector2:
	var start_x := int(WORLD_TILES_X / 2) + offset
	var start_y := int(WORLD_TILES_Y / 2) + offset
	var max_radius := maxi(WORLD_TILES_X, WORLD_TILES_Y)

	for radius in range(max_radius):
		for tile_y in range(start_y - radius, start_y + radius + 1):
			for tile_x in range(start_x - radius, start_x + radius + 1):
				var wrapped_x := posmod(tile_x, WORLD_TILES_X)
				var wrapped_y := posmod(tile_y, WORLD_TILES_Y)
				if not _is_solid_tile(wrapped_x, wrapped_y):
					return Vector2(wrapped_x * TILE_SIZE + TILE_SIZE / 2.0, wrapped_y * TILE_SIZE + TILE_SIZE / 2.0)

	return Vector2(WORLD_WIDTH / 2.0, WORLD_HEIGHT / 2.0)


func _is_solid_tile(tile_x: int, tile_y: int) -> bool:
	var tile_id := _terrain_grid[tile_y][tile_x] as String
	return tile_id == "rock-wall"


func _is_house_tile(tile_x: int, tile_y: int) -> bool:
	var tile_id := _terrain_grid[tile_y][tile_x] as String
	return _allows_decorations(tile_id)


func _resolve_world_tile(tile_x: int, tile_y: int) -> String:
	var noise := _sample(tile_x, tile_y)
	var ridge := _sample(tile_x - 13, tile_y + 17)
	var shelf := _sample(tile_x + 7, tile_y - 19)

	if ridge > 0.82 and shelf > 0.58:
		return "rock-wall"

	if noise > 0.73:
		return "water"

	return "grass-b" if noise > 0.38 else "grass-a"


func _allows_decorations(tile_id: String) -> bool:
	return tile_id == "grass-a" or tile_id == "grass-b"


func _sample(tile_x: int, tile_y: int) -> float:
	var value: float = sin(float(tile_x) * 12.9898 + float(tile_y) * 78.233) * 43758.5453
	var fraction: float = value - floorf(value)
	var wave: float = (sin(float(tile_x) * 0.25) + cos(float(tile_y) * 0.32) + 2.0) / 4.0
	return clampf(fraction * 0.45 + wave * 0.55, 0.0, 1.0)


func _create_world_textures() -> void:
	_textures["grass-a"] = _make_tile_texture(Color8(69, 125, 70), [
		{"type": "circle", "x": 16, "y": 16, "r": 12, "color": Color8(80, 140, 79)},
		{"type": "circle", "x": 44, "y": 22, "r": 10, "color": Color8(80, 140, 79)},
		{"type": "circle", "x": 32, "y": 46, "r": 14, "color": Color8(80, 140, 79)},
	])
	_textures["grass-b"] = _make_tile_texture(Color8(75, 132, 75), [
		{"type": "circle", "x": 20, "y": 20, "r": 9, "color": Color8(94, 164, 95)},
		{"type": "circle", "x": 46, "y": 18, "r": 13, "color": Color8(94, 164, 95)},
		{"type": "circle", "x": 38, "y": 44, "r": 11, "color": Color8(94, 164, 95)},
		{"type": "circle", "x": 10, "y": 48, "r": 8, "color": Color(0.45, 0.73, 0.43, 0.7)},
	])
	_textures["water"] = _make_tile_texture(Color8(43, 79, 87), [
		{"type": "ellipse", "x": 22, "y": 26, "rx": 14, "ry": 9, "color": Color(0.24, 0.45, 0.50, 0.8)},
		{"type": "ellipse", "x": 45, "y": 42, "rx": 12, "ry": 8, "color": Color(0.24, 0.45, 0.50, 0.8)},
	])
	_textures["rock-wall"] = _make_tile_texture(Color8(63, 72, 68), [
		{"type": "round_rect", "x": 4, "y": 6, "w": 56, "h": 52, "color": Color8(87, 100, 94)},
		{"type": "round_rect", "x": 10, "y": 10, "w": 20, "h": 18, "color": Color8(112, 128, 122)},
		{"type": "round_rect", "x": 34, "y": 14, "w": 18, "h": 16, "color": Color8(112, 128, 122)},
		{"type": "round_rect", "x": 18, "y": 32, "w": 28, "h": 18, "color": Color8(112, 128, 122)},
		{"type": "ellipse", "x": 18, "y": 20, "rx": 6, "ry": 4, "color": Color(0.48, 0.70, 0.43, 0.9)},
		{"type": "ellipse", "x": 43, "y": 36, "rx": 7, "ry": 5, "color": Color(0.48, 0.70, 0.43, 0.9)},
	])
	_textures["flower"] = _make_tile_texture(Color(0, 0, 0, 0), [
		{"type": "circle", "x": 8, "y": 8, "r": 6, "color": Color8(149, 214, 106)},
		{"type": "circle", "x": 8, "y": 8, "r": 2, "color": Color8(255, 211, 106)},
	], 16)
	_textures["stone"] = _make_tile_texture(Color(0, 0, 0, 0), [
		{"type": "round_rect", "x": 0, "y": 4, "w": 32, "h": 18, "color": Color8(140, 167, 106)},
		{"type": "round_rect", "x": 4, "y": 8, "w": 24, "h": 10, "color": Color8(111, 132, 82)},
	], 32)


func _make_tile_texture(base_color: Color, shapes: Array, size := TILE_SIZE) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(base_color)
	for shape in shapes:
		var data := shape as Dictionary
		var shape_type := String(data["type"])
		if shape_type == "circle":
			_draw_circle(image, int(data["x"]), int(data["y"]), int(data["r"]), data["color"] as Color)
		elif shape_type == "ellipse":
			_draw_ellipse(image, int(data["x"]), int(data["y"]), int(data["rx"]), int(data["ry"]), data["color"] as Color)
		elif shape_type == "round_rect":
			_draw_rect(image, int(data["x"]), int(data["y"]), int(data["w"]), int(data["h"]), data["color"] as Color)
	return ImageTexture.create_from_image(image)


func _draw_rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	for py in range(maxi(0, y), mini(image.get_height(), y + height)):
		for px in range(maxi(0, x), mini(image.get_width(), x + width)):
			image.set_pixel(px, py, color)


func _draw_circle(image: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	var r2 := radius * radius
	for py in range(maxi(0, cy - radius), mini(image.get_height(), cy + radius + 1)):
		for px in range(maxi(0, cx - radius), mini(image.get_width(), cx + radius + 1)):
			var dx := px - cx
			var dy := py - cy
			if dx * dx + dy * dy <= r2:
				image.set_pixel(px, py, color)


func _draw_ellipse(image: Image, cx: int, cy: int, rx: int, ry: int, color: Color) -> void:
	for py in range(maxi(0, cy - ry), mini(image.get_height(), cy + ry + 1)):
		for px in range(maxi(0, cx - rx), mini(image.get_width(), cx + rx + 1)):
			var dx := float(px - cx) / float(rx)
			var dy := float(py - cy) / float(ry)
			if dx * dx + dy * dy <= 1.0:
				image.set_pixel(px, py, color)
