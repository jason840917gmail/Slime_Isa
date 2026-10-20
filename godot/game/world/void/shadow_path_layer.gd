@tool
extends TileMapLayer
## The painted shadow path of a world (docs/godot/DUNGEONS.md "Dark-room extras"): glow-moss on a
## hidden ledge over a void, painted cell by cell from its one-tile palette (shadow_path_tileset.tres)
## on a `shadow-path` TileMapLayer beside the `ground` layer, at position (0, 0). The layer keeps one
## ShadowPath (game/dungeon/shadow_path.gd: the deck that holds the slime, the moss drawn only in
## light) over its painted cells, rebuilt as you paint; it is never saved with the scene. The layer's
## own squares are a painting aid (`paint_opacity` in the editor), never drawn in the game.
##
## Owner: dungeon kit.

const ShadowPathScript := preload("res://game/dungeon/shadow_path.gd")
const TILESET := "res://game/world/void/shadow_path_tileset.tres"
const HOLDER := "ShadowPath"

## How strongly the painted squares show over the moss in the editor (0 hides them).
@export_range(0.0, 1.0) var paint_opacity: float = 0.35:
	set(value):
		paint_opacity = value
		_apply_opacity()

var _queued := false


func _ready() -> void:
	if tile_set == null:
		tile_set = load(TILESET)
	_apply_opacity()
	if not changed.is_connected(_queue_rebuild):
		changed.connect(_queue_rebuild)
	_rebuild()


func _apply_opacity() -> void:
	self_modulate.a = paint_opacity if Engine.is_editor_hint() else 0.0


func _queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	var path := get_node_or_null(HOLDER) as Node2D
	if path == null:
		path = ShadowPathScript.new()
		path.name = HOLDER
		add_child(path)
	path.position = Vector2.ZERO
	var cells: Array[Vector2i] = []
	for cell: Vector2i in get_used_cells():
		cells.append(cell)
	path.set(&"cells", cells)
