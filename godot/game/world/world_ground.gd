@tool
extends TileMapLayer
## A world's ground layer (docs/godot/TERRAIN_LAB.md): every world scene's `ground` TileMapLayer
## carries this script so the editor shows the world as the game draws it. In the editor it mounts
## the 128 px ground, the animated water and the hand-made terrain edges on itself, as
## `WorldService.register_world` does in the game, and painting the ground rebuilds them. The mounted nodes have no owner, so they are never
## saved with the scene. In the game WorldService mounts them; this script only takes the cells
## under bridge decks (bridge_deck.gd, docs/godot/specs/water.md §10) and drops their collision,
## through the layer's runtime tile data, so their tiles still draw.
##
## Owner: world.

const WaterSurface := preload("res://game/world/water_surface.gd")
const TerrainEdges := preload("res://game/world/terrain_edges/terrain_edges.gd")
const GroundSurface := preload("res://game/world/ground_surface.gd")

var _queued := false
## Cells under a bridge deck: they keep their tile and lose its collision.
var _bridged: Dictionary[Vector2i, bool] = {}


## The cells under every bridge deck of the world (BridgeDeck.lay); replaces the previous set.
func set_bridged_cells(cells: Array[Vector2i]) -> void:
	_bridged.clear()
	for cell: Vector2i in cells:
		_bridged[cell] = true
	notify_runtime_tile_data_update()


## True when `cell` is under a bridge deck.
func is_bridged(cell: Vector2i) -> bool:
	return _bridged.has(cell)


## Never in the editor: bridges open their cells only in the game, and a layer the editor already
## held when this script was reloaded has no `_bridged` yet.
func _use_tile_data_runtime_update(coords: Vector2i) -> bool:
	return not Engine.is_editor_hint() and _bridged.has(coords)


func _tile_data_runtime_update(_coords: Vector2i, tile_data: TileData) -> void:
	for layer: int in tile_set.get_physics_layers_count():
		tile_data.set_collision_polygons_count(layer, 0)


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	refresh()
	changed.connect(_queue_refresh)


## The 128 px ground first, then the water (the edges copy its mask) and the edges right after it,
## so the cliffs an `elevation` layer mounts on this ground stay on top.
func refresh() -> void:
	_queued = false
	var surface := GroundSurface.mount(self)
	var water := get_node_or_null(^"WaterSurface") as WaterSurface
	if water != null:
		water.build(self)
	else:
		water = WaterSurface.mount(self)
	var edges := TerrainEdges.mount(self)
	var index := 0
	for node: Node in [surface, water, edges]:
		if node != null:
			move_child(node, index)
			index += 1


func _queue_refresh() -> void:
	if _queued:
		return
	_queued = true
	refresh.call_deferred()
