@tool
extends Node2D
## One region of the world atlas (world_atlas.gd, docs/godot/WORLD_ATLAS.md): a slot saved in
## game/dev/world_atlas.tscn at the north-west corner of its region's block of chunks. Click
## anywhere on the block to select it (metadata `_edit_group_` and the transparent `Hit` rect) and
## drag it to move the region: it snaps to whole chunks and stays on the map, and the atlas shows
## the move as pending until its "Save layout" writes it to the world map. Regions that are not a
## rectangle of whole chunks are locked (metadata `_edit_lock_`).
##
## When `live`, the slot shows its region's world scene as it is saved: an instance with no owner,
## so it is never saved with the atlas and nothing in it can be selected. Edit the world in its
## own scene ("Open world"), save it, then "Refresh worlds" on the atlas. The atlas also makes
## slots without an owner for the interiors on its shelf (locked groups, like the shelf itself).
##
## Owner: world (atlas).

## Dragged by hand onto another chunk (sent on every snap: the atlas only notes it and plans once
## per frame, from where the slot ends up).
signal dragged(slot: Node2D)
## `live` was switched.
signal live_changed(slot: Node2D)

const WORLD_NODE := "World"
const HIT_NODE := "Hit"
const WORLD_GROUND := "res://game/world/world_ground.gd"

## The region's key in the world map (one character).
@export var region_key: String = ""
## Show the region's world scene; off leaves the outline and the sketch (lighter for the editor).
@export var live: bool = true:
	set(value):
		live = value
		if is_node_ready():
			live_changed.emit(self)
@export_tool_button("Open world", "PackedScene") var open_button: Callable = open_world

## Problems the atlas found with this region (shown on the slot in the Scene dock).
var warnings := PackedStringArray()
## The world (map id) this slot shows and its scene ("" when it has none yet).
var map_id := ""
var scene_path := ""
## A slot on the interior shelf (no owner, never dragged).
var interior := false
var chunk_units := Vector2(2048.0, 2048.0)
## The region's block and the whole grid, in chunks (a drag keeps the block on the grid).
var block_size := Vector2i.ONE
var grid_size := Vector2i(8, 8)
## Where the shown world was instanced: its drawing bakes that position, so a slot that moved
## since must be instanced again.
var built_at := Vector2.INF

var _placing := false
var _chunk := Vector2i.ZERO


func _ready() -> void:
	_chunk = chunk_at(position)
	set_notify_local_transform(not interior)


func _notification(what: int) -> void:
	if what != NOTIFICATION_LOCAL_TRANSFORM_CHANGED or _placing or interior:
		return
	var at_chunk := chunk_at(position)
	var corner := Vector2(at_chunk) * chunk_units
	if position != corner:
		_placing = true
		position = corner
		_placing = false
	if at_chunk != _chunk:
		_chunk = at_chunk
		dragged.emit(self)


func _get_configuration_warnings() -> PackedStringArray:
	return warnings


## The chunk under `at` (rounded), kept so the block stays on the grid.
func chunk_at(at: Vector2) -> Vector2i:
	var rounded := Vector2i((at / chunk_units).round())
	return rounded.clamp(Vector2i.ZERO, (grid_size - block_size).max(Vector2i.ZERO))


## The chunk of the slot's corner.
func chunk() -> Vector2i:
	return _chunk


## Moves the slot without counting it as a drag.
func place(at: Vector2) -> void:
	_placing = true
	position = at
	_placing = false
	_chunk = chunk_at(position)


## The transparent rect over the block that makes the whole block clickable; `scene_owner` owns it
## (the atlas root, so it is saved with the slot).
func ensure_hit(scene_owner: Node) -> void:
	var hit := get_node_or_null(HIT_NODE) as ColorRect
	if hit == null:
		hit = ColorRect.new()
		hit.name = HIT_NODE
		hit.color = Color(0, 0, 0, 0)
		hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hit)
		move_child(hit, 0)
		hit.owner = scene_owner
	hit.size = Vector2(block_size) * chunk_units


func world() -> Node2D:
	return get_node_or_null(WORLD_NODE) as Node2D


## Shows an instance of `packed` (built here, so its drawing lines up), replacing the last one;
## `prepare` (when valid) gets the instance before it enters the tree.
func show_world(packed: PackedScene, prepare: Callable = Callable()) -> void:
	clear_world()
	var instance := packed.instantiate() as Node2D
	if instance == null:
		return
	# Not linked to any scene file, so saving the world (or a prop scene in it) in the editor never
	# reloads this copy into the atlas.
	_unlink(instance)
	instance.name = WORLD_NODE
	if prepare.is_valid():
		prepare.call(instance)
	built_at = position
	add_child(instance)
	hide_painting_aids(instance)


func clear_world() -> void:
	var old := world()
	built_at = Vector2.INF
	if old != null:
		remove_child(old)
		old.queue_free()


static func _unlink(node: Node) -> void:
	node.scene_file_path = ""
	for child: Node in node.get_children():
		_unlink(child)


## The squares of a world's painting layers (elevation, cliffs, fences, forest) are aids for
## painting; the game hides them, so the atlas does too (their drawing stays).
static func hide_painting_aids(instance: Node) -> void:
	for child: Node in instance.get_children():
		var layer := child as TileMapLayer
		var script := layer.get_script() as Script if layer != null else null
		if script != null and script.resource_path != WORLD_GROUND:
			layer.self_modulate.a = 0.0


func open_world() -> void:
	if scene_path == "":
		push_warning("World atlas: %s has no scene yet." % (map_id if map_id != "" else region_key))
		return
	var editor := Engine.get_singleton(&"EditorInterface") if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface") else null
	if editor != null:
		editor.call(&"open_scene_from_path", scene_path)
