@tool
extends Node2D
## Light by height for the hand-painted cliffs (docs/godot/CLIFFS.md "Light"): the ground that is
## not on a raised top is drawn darker, so the eye tells low from high at a glance. The raised
## cells are the painted cells of the cliff tops terrain on the world's cliff layers (siblings of
## the ground using cliff_tileset.tres); nothing is painted twice.
##
## `GroundShade.mount(ground)` adds it as the child "GroundShade" of the ground layer, after the
## water surface and the terrain edges, so it shades the ground, the water and the edges but not
## the cliff art, the props or the bodies (all drawn above the ground layer). One rectangle with a
## multiply shader (ground_shade.gdshader) over a one-texel-per-cell height map sampled with linear
## filtering, so the light turns over half a cell each side of a cliff line, under its border art.
## No node (and an old one removed) when the world has no cliff tops.
##
## Owner: world.

const SHADER := preload("res://game/world/ground_shade.gdshader")
const Self := preload("res://game/world/ground_shade.gd")
const NODE_NAME := "GroundShade"
const CLIFF_TILESET := "res://game/world/cliffs/cliff_tileset.tres"
## The cliff tile set's terrain set, and its terrain of the raised tops (walls and feet are low).
const CLIFF_SET := 0
const TOP_TERRAIN := 0

var columns: int = 0
var rows: int = 0
var raised: int = 0


## Mounts (or rebuilds) the shade on `ground`. Null when the world has no painted cliff top.
static func mount(ground: TileMapLayer) -> Self:
	if ground == null or ground.tile_set == null:
		return null
	var shade := ground.get_node_or_null(NodePath(NODE_NAME)) as Self
	var fresh := shade == null
	if fresh:
		shade = Self.new()
		shade.name = NODE_NAME
	if not shade.build(ground):
		if fresh:
			shade.free()
		else:
			shade.queue_free()
		return null
	if fresh:
		ground.add_child(shade)
	ground.move_child(shade, -1)
	return shade


## The world's cliff layers: siblings of `ground` drawn with the cliff tile set.
static func cliff_layers(ground: TileMapLayer) -> Array[TileMapLayer]:
	var found: Array[TileMapLayer] = []
	var parent := ground.get_parent() if ground != null else null
	if parent == null:
		return found
	for child: Node in parent.get_children():
		var layer := child as TileMapLayer
		if layer != null and layer.tile_set != null and layer.tile_set.resource_path == CLIFF_TILESET:
			found.append(layer)
	return found


func build(ground: TileMapLayer) -> bool:
	var used := ground.get_used_rect()
	columns = int(ground.get_meta("columns", used.end.x))
	rows = int(ground.get_meta("rows", used.end.y))
	raised = 0
	if columns <= 0 or rows <= 0:
		return false
	var map := Image.create_empty(columns, rows, false, Image.FORMAT_R8)
	map.fill(Color(0, 0, 0))
	for layer in cliff_layers(ground):
		for cell: Vector2i in layer.get_used_cells():
			if cell.x < 0 or cell.y < 0 or cell.x >= columns or cell.y >= rows:
				continue
			var data := layer.get_cell_tile_data(cell)
			if data != null and data.terrain_set == CLIFF_SET and data.terrain == TOP_TERRAIN:
				map.set_pixelv(cell, Color(1, 1, 1))
				raised += 1
	if raised == 0:
		return false
	var shader_material := ShaderMaterial.new()
	shader_material.shader = SHADER
	shader_material.set_shader_parameter(&"height_map", ImageTexture.create_from_image(map))
	shader_material.set_shader_parameter(&"grid_size", Vector2(columns, rows))
	shader_material.set_shader_parameter(&"tile_size", float(ground.tile_set.tile_size.x))
	material = shader_material
	queue_redraw()
	return true


func _draw() -> void:
	if raised > 0 and material != null:
		var tile := float((material as ShaderMaterial).get_shader_parameter(&"tile_size"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(columns, rows) * tile), Color.WHITE)
