@tool
extends Node2D
## The dark beyond an InteriorWallLayer's faces (docs/godot/INTERIOR_WALLS.md): a flat colour over
## the wall cells no piece covers (deep rock, a carved pocket's surroundings).
##
## Owner: world (interior walls).

const COLOUR := Color("#0d0a0f")

var cells: Array[Vector2i] = []
var cell_size := Vector2(64, 64)


func _draw() -> void:
	for cell in cells:
		draw_rect(Rect2(Vector2(cell) * cell_size, cell_size), COLOUR)
