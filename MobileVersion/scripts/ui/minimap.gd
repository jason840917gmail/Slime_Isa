extends Control

const MAP_PADDING := 8.0

var _player_color := Color8(107, 224, 255)
var _friend_color := Color8(255, 179, 71)
var _house_color := Color8(132, 190, 255)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var bounds := _get_world_bounds()
	if bounds.size == Vector2.ZERO:
		return

	var map_rect := Rect2(Vector2(MAP_PADDING, MAP_PADDING), size - Vector2.ONE * MAP_PADDING * 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.12, 0.08, 0.92), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color8(68, 204, 136), false, 3.0)
	draw_rect(map_rect, Color(0.07, 0.16, 0.12, 0.85), true)

	for house in get_tree().get_nodes_in_group("houses"):
		if house is Node2D:
			var house_node := house as Node2D
			_draw_dot(house_node.global_position, bounds, map_rect, _house_color, 3.5)

	for friend in get_tree().get_nodes_in_group("friends"):
		if friend is Node2D:
			var friend_node := friend as Node2D
			_draw_dot(friend_node.global_position, bounds, map_rect, _friend_color, 2.5)

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		_draw_dot(player.global_position, bounds, map_rect, _player_color, 4.0)

	_draw_camera_rect(bounds, map_rect)


func _draw_dot(world_position: Vector2, bounds: Rect2, map_rect: Rect2, color: Color, radius: float) -> void:
	var point := _to_minimap(world_position, bounds, map_rect)
	draw_circle(point, radius, color)


func _draw_camera_rect(bounds: Rect2, map_rect: Rect2) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return

	var viewport_size := get_viewport_rect().size / camera.zoom
	var top_left := camera.get_screen_center_position() - viewport_size / 2.0
	var bottom_right := top_left + viewport_size
	var minimap_top_left := _to_minimap(top_left, bounds, map_rect)
	var minimap_bottom_right := _to_minimap(bottom_right, bounds, map_rect)
	draw_rect(Rect2(minimap_top_left, minimap_bottom_right - minimap_top_left), Color8(136, 200, 153), false, 1.5)


func _to_minimap(world_position: Vector2, bounds: Rect2, map_rect: Rect2) -> Vector2:
	var x := inverse_lerp(bounds.position.x, bounds.position.x + bounds.size.x, world_position.x)
	var y := inverse_lerp(bounds.position.y, bounds.position.y + bounds.size.y, world_position.y)
	return map_rect.position + Vector2(clampf(x, 0.0, 1.0), clampf(y, 0.0, 1.0)) * map_rect.size


func _get_world_bounds() -> Rect2:
	var level := get_tree().get_first_node_in_group("level")
	if level != null and level.has_method("get_camera_bounds"):
		return level.call("get_camera_bounds") as Rect2

	return Rect2(Vector2.ZERO, Vector2(3456.0, 3456.0))
