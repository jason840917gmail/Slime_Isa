@tool
class_name PropLayer
extends TileMapLayer
## Props painted from a palette (docs/godot/PROPS.md): a world's `props` layer (64-unit cells,
## `props_cell_tileset.tres`) and `details` layer (32-unit cells, `props_detail_tileset.tres`).
## Pick a prop in the TileMap panel and paint; erase its cell to remove it. Each painted cell shows
## exactly the prop painted there:
## the palette tile's scene, standing at the tile's anchor in the cell, at the tile's size, mirrored
## when painted flipped (the TileMap panel's flip button). Nothing random. On those palettes a prop
## takes a block of whole cells, the painted cell its bottom-left one, and mirrors about the painted
## cell's middle, as Godot mirrors the tile. The older layers (`old-props`, 8-unit cells, and
## `large-props`, 64) keep what was painted on them before the cell layers (2026-10-13); there a prop mirrors in place.
##
## The props are real instances of their scenes (collision, idle animation), made by this layer and
## saved nowhere: the world scene stores only the painted cells, so its tree stays small. They are
## unowned, so the editor neither lists nor selects them. A prop that needs its own logic (a secret,
## a resource, a gate) is still placed as a normal instance. The palette squares are drawn at
## `paint_opacity` in the editor (0 hides them) and never in the game.
##
## The tile sets are built by tools/build_prop_palettes.gd; tools/absorb_props.gd turns props
## already placed in a world into paint.
##
## Owner: world (props).

const HOLDER := "Props"
const SCENE_DATA := "prop_scene"
const ANCHOR_DATA := "prop_anchor"
const SIZE_DATA := "prop_size"
## True on a tile whose prop mirrors about its cell's middle (the newer palettes).
const MIRROR_DATA := "prop_mirror"
const FLIP_FLAGS := TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V \
		| TileSetAtlasSource.TRANSFORM_TRANSPOSE

## How strongly the palette squares show over the props in the editor (0 hides them).
@export_range(0.0, 1.0) var paint_opacity: float = 0.3:
	set(value):
		paint_opacity = value
		_apply_opacity()

var _queued := false
## Per painted cell: [what it shows, the prop node].
var _placed := {}
static var _scenes := {}


func _ready() -> void:
	y_sort_enabled = true
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


## What painted `cell` shows: {scene, at (the prop's origin, layer space), size, flip, and
## mirror_x (the line it mirrors about) when it mirrors about its cell's middle}, or {}.
func prop_at(cell: Vector2i) -> Dictionary:
	var source_id := get_cell_source_id(cell)
	if source_id < 0 or tile_set == null or not tile_set.has_source(source_id):
		return {}
	var source := tile_set.get_source(source_id) as TileSetAtlasSource
	var coords := get_cell_atlas_coords(cell)
	var alternative := get_cell_alternative_tile(cell)
	var base := alternative & ~FLIP_FLAGS
	if source == null or not source.has_tile(coords) or not source.has_alternative_tile(coords, base):
		return {}
	var data := source.get_tile_data(coords, base)
	var scene := str(data.get_custom_data(SCENE_DATA))
	if scene.is_empty():
		return {}
	var anchor: Vector2 = data.get_custom_data(ANCHOR_DATA)
	var size := float(data.get_custom_data(SIZE_DATA))
	var prop := {
		"scene": scene,
		"at": Vector2(cell) * Vector2(tile_set.tile_size) + anchor,
		"size": size if size > 0.0 else 1.0,
		"flip": (alternative & TileSetAtlasSource.TRANSFORM_FLIP_H) != 0,
	}
	if tile_set.has_custom_data_layer_by_name(MIRROR_DATA) and bool(data.get_custom_data(MIRROR_DATA)):
		prop["mirror_x"] = (cell.x + 0.5) * tile_set.tile_size.x
	return prop


## Makes the props match the paint: new and changed cells get their prop, erased cells lose it,
## unchanged cells keep theirs.
func _rebuild() -> void:
	_queued = false
	if not is_inside_tree() or tile_set == null:
		return
	var holder := get_node_or_null(HOLDER) as Node2D
	if holder == null:
		holder = Node2D.new()
		holder.name = HOLDER
		holder.y_sort_enabled = true
		add_child(holder)
	if _placed.is_empty():
		for child in holder.get_children():
			child.free()
	var seen := {}
	for cell in get_used_cells():
		var prop := prop_at(cell)
		if prop.is_empty():
			continue
		seen[cell] = true
		var key := [prop["scene"], prop["at"], prop["size"], prop["flip"], prop.get("mirror_x")]
		var old: Variant = _placed.get(cell)
		if old != null and old[0] == key and is_instance_valid(old[1]):
			continue
		if old != null and is_instance_valid(old[1]):
			(old[1] as Node).free()
		_placed.erase(cell)
		var node := make_prop(prop)
		if node == null:
			continue
		node.name = "%s@%d_%d" % [str(prop["scene"]).get_file().get_basename(), cell.x, cell.y]
		holder.add_child(node)
		_placed[cell] = [key, node]
	for cell: Vector2i in _placed.keys():
		if not seen.has(cell):
			var node: Variant = _placed[cell][1]
			if is_instance_valid(node):
				(node as Node).free()
			_placed.erase(cell)


## The box a sprite draws, in its own space.
static func picture_rect(item: Node2D) -> Rect2:
	if item is Sprite2D:
		return (item as Sprite2D).get_rect()
	var animated := item as AnimatedSprite2D
	if animated.sprite_frames == null or not animated.sprite_frames.has_animation(animated.animation):
		return Rect2()
	var texture := animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
	if texture == null:
		return Rect2()
	var size := texture.get_size()
	return Rect2((-size / 2.0 if animated.centered else Vector2.ZERO) + animated.offset, size)


## An instance of `prop`'s scene at its place, sized and mirrored on its `Visual` (as worlds used to
## override placed props). With `mirror_x` a mirrored prop is also moved so that its picture is
## mirrored about that line instead of about its Visual's middle. `edit_state` instances it as the
## editor does, so a scene saved with it keeps the Visual's size and mirror (tools/paint_to_nodes.gd).
static func make_prop(prop: Dictionary, edit_state := false) -> Node2D:
	var path := str(prop["scene"])
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	var packed := _scenes[path] as PackedScene
	if packed == null:
		push_warning("PropLayer: no scene %s" % path)
		return null
	var node := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE if edit_state else PackedScene.GEN_EDIT_STATE_DISABLED) as Node2D
	if node == null:
		return null
	node.position = prop["at"]
	var visual := node.get_node_or_null(^"Visual") as Node2D
	if visual != null:
		visual.scale *= float(prop["size"])
		if bool(prop["flip"]) and &"flip_h" in visual:
			visual.set(&"flip_h", not bool(visual.get(&"flip_h")))
			if prop.has("mirror_x") and (visual is Sprite2D or visual is AnimatedSprite2D):
				# flip_h mirrors the picture about the Visual's middle; move it so the mirror line is mirror_x
				var middle := node.position.x + (visual.transform * picture_rect(visual)).get_center().x
				node.position.x += 2.0 * (float(prop["mirror_x"]) - middle)
	return node
