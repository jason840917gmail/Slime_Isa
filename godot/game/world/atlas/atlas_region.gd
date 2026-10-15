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
## own scene ("Open world"), save it, then "Refresh worlds" on the atlas. A region cut into chunk
## worlds (WorldChunks) shows its chunk scenes, each in its place on the block, and "Open world"
## opens the chunk picked in `open_chunk`. The atlas also makes
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
## For a region cut into chunk worlds: the chunk "Open world" opens (a list of its chunks; not saved).
@export var open_chunk: String = ""
@export_tool_button("Open world", "PackedScene") var open_button: Callable = open_world

## Problems the atlas found with this region (shown on the slot in the Scene dock).
var warnings := PackedStringArray()
## The world (map id) this slot shows and its scene ("" when it has none yet, or is cut into chunk
## worlds: `chunk_scenes`, chunk name ("C6") -> its scene).
var map_id := ""
var scene_path := ""
var chunk_scenes: Dictionary = {}:
	set(value):
		chunk_scenes = value
		notify_property_list_changed()
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


func _validate_property(property: Dictionary) -> void:
	if property["name"] != "open_chunk":
		return
	if chunk_scenes.is_empty():
		property["usage"] = PROPERTY_USAGE_NO_EDITOR
		return
	property["usage"] = PROPERTY_USAGE_EDITOR
	property["hint"] = PROPERTY_HINT_ENUM
	property["hint_string"] = ",".join(chunk_names())


## The chunks of a region cut into chunk worlds, in reading order (rows, then columns).
func chunk_names() -> PackedStringArray:
	var names := PackedStringArray(chunk_scenes.keys())
	var order := func(a: String, b: String) -> bool:
		return int(a.substr(1)) < int(b.substr(1)) or (int(a.substr(1)) == int(b.substr(1)) and a < b)
	var sorted := Array(names)
	sorted.sort_custom(order)
	return PackedStringArray(sorted)


## True when the slot has something to show: its world's scene or its chunk worlds.
func has_scene() -> bool:
	return scene_path != "" or not chunk_scenes.is_empty()


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


## Shows the chunk worlds of a cut region, replacing the last world: `parts` = [{"packed":
## PackedScene, "offset": Vector2 (its place on the block, world units)}]; `prepare` (when valid)
## gets each instance and its offset before it enters the tree.
func show_chunks(parts: Array, prepare: Callable = Callable()) -> void:
	clear_world()
	var holder := Node2D.new()
	holder.name = WORLD_NODE
	holder.y_sort_enabled = true
	for part: Dictionary in parts:
		var instance := (part["packed"] as PackedScene).instantiate() as Node2D
		if instance == null:
			continue
		_unlink(instance)
		instance.position = part["offset"]
		if prepare.is_valid():
			prepare.call(instance, part["offset"])
		holder.add_child(instance)
	built_at = position
	add_child(holder)
	for instance: Node in holder.get_children():
		hide_painting_aids(instance)


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
	var path := scene_path
	if not chunk_scenes.is_empty():
		path = str(chunk_scenes.get(open_chunk, chunk_scenes[chunk_names()[0]]))
	if path == "":
		push_warning("World atlas: %s has no scene yet." % (map_id if map_id != "" else region_key))
		return
	var editor := Engine.get_singleton(&"EditorInterface") if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface") else null
	if editor != null:
		editor.call(&"open_scene_from_path", path)
