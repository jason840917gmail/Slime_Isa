@tool
extends TileMapLayer
## Dual-grid edge overlay for hand-made terrain transitions (docs/godot/TERRAIN_LAB.md).
##
## The layer sits half a cell up and left of `ground`, so each of its cells covers the corner
## shared by four ground cells. It shows the edge tile for which of those four cells are the
## upper ground (e.g. snow): index = TL + 2*TR + 4*BL + 8*BR (1 = that cell is upper), at
## atlas (index % 4, index / 4) of `edge_source`. Corners with no upper cell, or only upper
## cells, get no tile (the ground shows). The tiles are art; this script only picks them,
## the way Godot's terrain brush would if its corner mode matched cells instead of corners.
## It rebuilds whenever `ground` changes, in the editor too: paint the ground, edges follow.
## The layer's material (terrain_edges.gdshader) names the upper and lower grounds' sheets.

const TL := 1
const TR := 2
const BL := 4
const BR := 8

## The ground layer, painted by hand (same parent, same scale, not rotated).
@export var ground: TileMapLayer:
	set(value):
		if ground != null and ground.changed.is_connected(_queue_rebuild):
			ground.changed.disconnect(_queue_rebuild)
		ground = value
		if ground != null and is_inside_tree():
			ground.changed.connect(_queue_rebuild)
		_queue_rebuild()
## Ground atlas sources that count as the upper ground.
@export var upper_sources: PackedInt32Array = PackedInt32Array()
## The atlas source of the 16 edge tiles in this layer's tile set.
@export var edge_source: int = 0

var _queued := false


func _enter_tree() -> void:
	if ground != null and not ground.changed.is_connected(_queue_rebuild):
		ground.changed.connect(_queue_rebuild)


func _exit_tree() -> void:
	if ground != null and ground.changed.is_connected(_queue_rebuild):
		ground.changed.disconnect(_queue_rebuild)


func _ready() -> void:
	rebuild()


## Recomputes every edge tile from `ground`. Returns the number of edge tiles placed.
func rebuild() -> int:
	_queued = false
	clear()
	if ground == null or ground.tile_set == null:
		return 0
	scale = ground.scale
	position = ground.position - Vector2(ground.tile_set.tile_size) * 0.5 * ground.scale
	var upper := {}
	for cell: Vector2i in ground.get_used_cells():
		if ground.get_cell_source_id(cell) in upper_sources:
			upper[cell] = true
	var corners := {}
	for cell: Vector2i in upper:
		for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			corners[cell + offset] = true
	var placed := 0
	for corner: Vector2i in corners:
		var index := 0
		if upper.has(corner + Vector2i(-1, -1)):
			index |= TL
		if upper.has(corner + Vector2i(0, -1)):
			index |= TR
		if upper.has(corner + Vector2i(-1, 0)):
			index |= BL
		if upper.has(corner):
			index |= BR
		if index != TL | TR | BL | BR:
			set_cell(corner, edge_source, Vector2i(index % 4, index / 4))
			placed += 1
	return placed


func _queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	rebuild.call_deferred()
