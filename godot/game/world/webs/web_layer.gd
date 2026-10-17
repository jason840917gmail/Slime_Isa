@tool
class_name WebLayer
extends TileMapLayer
## Floor webs painted cell by cell (docs/godot/WEBS.md; the Weaver Hollow's floors): Add Node >
## WebLayer in a world scene, name it `webs`, beside the ground layer (same grid, position (0, 0)),
## and paint from its palette (game/world/webs/web_tileset.tres). Every painted cell is a floor
## web: without the Silk skin a walk through it is slowed by half and a Roll that enters it sticks
## (FloorWebs, floor_webs.gd); with the skin it is crossed at full speed. Enemies are not slowed.
##
## The palette: row 0, the auto tile (light frame): each cell picks one of the six webs and one of
## eight turns from its cell (and `variation`), so a field never shows a repeat. Row 1 (dark frame,
## dots count the web): one web exactly; the TileMap panel's flip and rotate buttons turn it.
## Erase a cell to clear its web.
##
## The webs are drawn by this layer and saved nowhere (the scene stores only the cells): each is a
## flat picture 1.5 cells wide centred on its cell, so painted neighbours overlap into one web,
## drawn under bodies at the layer's z_index (-1, with the ground's details). The slow and the stick
## hold exactly on the painted cells (the slime's feet). The palette squares are drawn at
## `paint_opacity` in the editor and never in the game.
##
## Owner: webs (the Weaver Hollow).

const Services := preload("res://game/shared/services.gd")
const FloorWebs := preload("res://game/world/webs/floor_webs.gd")

const TILESET := "res://game/world/webs/web_tileset.tres"
const ART := "res://asset/MAPS/webs/floor-webs-6x1.webp"
## The art: six 192 px frames in a row, drawn at half size (96 units).
const FRAMES := 6
const FRAME_PX := 192.0
const ART_SCALE := 0.5
## A palette tile's web (-1: picked from the cell).
const VARIANT_DATA := "web_variant"
const HOLDER := "Webs"
## The layer's draw order: with the ground's details, under every body.
const Z_INDEX := -1

## A Roll stuck in this layer's webs. Payload: {"cell": Vector2i}.
signal roll_stuck(payload: Dictionary)

## How strongly the painted squares show over the webs in the editor (0 hides them).
@export_range(0.0, 1.0) var paint_opacity: float = 0.3:
	set(value):
		paint_opacity = value
		_apply_opacity()
## Another number picks other webs and turns for the auto cells.
@export var variation: int = 0:
	set(value):
		variation = value
		_queue_rebuild()
## The webs' opacity (1 as painted).
@export_range(0.1, 1.0) var web_opacity: float = 1.0:
	set(value):
		web_opacity = value
		var holder := get_node_or_null(HOLDER) as Node2D
		if holder != null:
			holder.modulate.a = web_opacity

var _queued := false
static var _texture: Texture2D


func _init() -> void:
	z_index = Z_INDEX


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		add_to_group(FloorWebs.GROUP)


func _ready() -> void:
	if tile_set == null:
		tile_set = load(TILESET)
	y_sort_enabled = false
	_apply_opacity()
	if not changed.is_connected(_queue_rebuild):
		changed.connect(_queue_rebuild)
	set_physics_process(not Engine.is_editor_hint())
	_rebuild()


func _apply_opacity() -> void:
	self_modulate.a = paint_opacity if Engine.is_editor_hint() else 0.0
	if not Engine.is_editor_hint():
		# The game never draws the palette squares; the cells stay readable.
		enabled = false


func _queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()


# --- the rule --------------------------------------------------------------------------------------

## The cell under `point` (a world position).
func cell_at(point: Vector2) -> Vector2i:
	return local_to_map(to_local(point))


## True when a web is painted under `point` (a world position) and the layer is shown.
func has_web_at(point: Vector2) -> bool:
	if not point.is_finite() or not is_visible_in_tree():
		return false
	return get_cell_source_id(cell_at(point)) != -1


## FloorWebs: the walk's scale for `player` (its feet in a web and it does not cross webs).
func web_walk_multiplier(player: Node, crosses: bool) -> float:
	if crosses or not has_web_at(FloorWebs.feet(player)):
		return 1.0
	return FloorWebs.setting("floorSlowMultiplier")


## A Roll that enters a painted web sticks there.
func _physics_process(_delta: float) -> void:
	var player := FloorWebs.player()
	if player == null or not bool(player.call(&"is_rolling")):
		return
	var feet := FloorWebs.feet(player)
	if has_web_at(feet) and FloorWebs.stick_roll(player):
		roll_stuck.emit({"cell": cell_at(feet)})


# --- the look --------------------------------------------------------------------------------------

## The web picked for `cell`: [frame, flip_h, flip_v, transpose].
func pick(cell: Vector2i) -> Array:
	var data := get_cell_tile_data(cell)
	var fixed := -1
	if data != null and tile_set != null and tile_set.has_custom_data_layer_by_name(VARIANT_DATA):
		fixed = int(data.get_custom_data(VARIANT_DATA))
	if fixed >= 0:
		return [fixed % FRAMES, is_cell_flipped_h(cell), is_cell_flipped_v(cell), is_cell_transposed(cell)]
	var roll := absi(hash(Vector3i(cell.x, cell.y, variation)))
	var turn := (roll / FRAMES) % 8
	return [roll % FRAMES, (turn & 1) != 0, (turn & 2) != 0, (turn & 4) != 0]


## A sprite of web `frame` (turned) centred at `at` in the layer.
static func web_sprite(frame: int, flip_h: bool, flip_v: bool, transpose: bool, at: Vector2) -> Sprite2D:
	if _texture == null:
		_texture = load(ART) as Texture2D
	var sprite := Sprite2D.new()
	sprite.texture = _texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(frame * FRAME_PX, 0.0, FRAME_PX, FRAME_PX)
	sprite.centered = true
	sprite.position = at
	sprite.scale = Vector2.ONE * ART_SCALE
	# A transposed cell turns its web a quarter (the webs are flat, any turn reads).
	sprite.rotation = PI / 2.0 if transpose else 0.0
	sprite.flip_h = flip_h
	sprite.flip_v = flip_v
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return sprite


func _rebuild() -> void:
	_queued = false
	if not is_inside_tree() or tile_set == null:
		return
	var holder := get_node_or_null(HOLDER) as Node2D
	if holder == null:
		holder = Node2D.new()
		holder.name = HOLDER
		add_child(holder)
	holder.modulate.a = web_opacity
	for child in holder.get_children():
		child.free()
	if not ResourceLoader.exists(ART):
		return
	var size := Vector2(tile_set.tile_size)
	for cell in get_used_cells():
		var picked := pick(cell)
		holder.add_child(web_sprite(int(picked[0]), bool(picked[1]), bool(picked[2]), bool(picked[3]),
			Vector2(cell) * size + size / 2.0))
