@tool
extends Node2D
## Draws the exact stored collision polygons above the tiles for painting alignment.


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var lab := get_parent() as Node2D
	if lab == null or not bool(lab.get("show_collision")):
		return
	for child: Node in lab.get_children():
		if child is TileMapLayer:
			_draw_layer(child as TileMapLayer)


func _draw_layer(layer: TileMapLayer) -> void:
	for cell: Vector2i in layer.get_used_cells():
		var tile := layer.get_cell_tile_data(cell)
		if tile == null:
			continue
		for i: int in tile.get_collision_polygons_count(0):
			var points := tile.get_collision_polygon_points(0, i)
			for j: int in points.size():
				points[j] = layer.position + (Vector2(layer.map_to_local(cell)) + points[j]) * layer.scale
			draw_colored_polygon(points, Color(1, 0.2, 0.2, 0.38))

