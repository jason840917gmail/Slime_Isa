@tool
class_name WallLayer
extends TileMapLayer
## Built walls painted cell by cell (docs/godot/WALLS.md): Add Node > WallLayer in a world scene
## (beside the ground layer, same grid) and paint from its palette
## (game/world/walls/wall_tileset.tres). A cell painted with a style's auto tile (top row) takes its
## shape from its four neighbours (16 shapes: post, ends, straights, corners, T junctions, cross),
## so a wall runs seamlessly in any direction you paint; erase a cell to open a gap. The rows below
## pick a shape yourself: the first row keeps the stone pattern following the cell (seamless), the
## four under it are every exact piece. A neighbour of fixed shape is joined only where its shape
## has an arm. Nothing is random: the stone pattern repeats every two cells along a run.
##
## The pieces come from each style's three-part kit (scripts/art/build-wall-kit.py): a cell draws
## the half-runs toward its neighbours and, unless it is a straight run, a pillar where they meet,
## all drawn by this layer and saved nowhere (the scene stores only the cells). Each piece sorts
## with bodies at its cell's bottom, where the wall stands. In the game each shape's footprint is
## solid. The palette squares are drawn at `paint_opacity` in the editor and never in the game.
##
## Owner: world (walls).

const TILESET := "res://game/world/walls/wall_tileset.tres"
const TABLE := "res://asset/MAPS/walls/sets/walls.json"
const STYLE_DATA := "wall_style"
## A palette tile's fixed shape (-1: from the neighbours).
const SHAPE_DATA := "wall_shape"
## A palette tile's fixed stretch of the stone pattern (-1: from the cell, so runs stay seamless).
const PARITY_DATA := "wall_parity"
## The neighbours, by shape bit: north 1, east 2, south 4, west 8.
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const HOLDER := "Walls"
const COLLISION := "Collision"
## The palette's cell (the tile set's tile size), units.
const CELL := 64.0
## Where a wall stands in its cell (its foot): the cell's bottom middle.
const FOOT := Vector2(32.0, 64.0)

## How strongly the painted squares show over the walls in the editor (0 hides them).
@export_range(0.0, 1.0) var paint_opacity: float = 0.3:
	set(value):
		paint_opacity = value
		_apply_opacity()

## The cells drawn and solid; outside it a painted cell only shapes its neighbours, so a chunk cut
## from a bigger world can keep a one-cell margin of the wall past its edge and the pieces at the
## edge still join. Empty (the default): every painted cell.
@export var shown_cells := Rect2i():
	set(value):
		shown_cells = value
		_queue_rebuild()

var _queued := false
static var _table := {}
static var _textures := {}


func _ready() -> void:
	if tile_set == null:
		tile_set = load(TILESET)
	y_sort_enabled = true
	_apply_opacity()
	if not changed.is_connected(_queue_rebuild):
		changed.connect(_queue_rebuild)
	_rebuild()


func _apply_opacity() -> void:
	self_modulate.a = paint_opacity if Engine.is_editor_hint() else 0.0
	if not Engine.is_editor_hint():
		# the game never draws the palette squares (an exported game has no palette pictures);
		# the cells stay readable
		enabled = false


func _queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()


## The styles' table (walls.json): {style: {texture, frame, foot, scale, collision}}.
static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
		_table = parsed if parsed is Dictionary else {}
	return _table


## The wall style painted on `cell`, or "".
func style_of(cell: Vector2i) -> String:
	var data := get_cell_tile_data(cell)
	if data == null or not tile_set.has_custom_data_layer_by_name(STYLE_DATA):
		return ""
	return str(data.get_custom_data(STYLE_DATA))


## The shape of a wall in `cell`: the one its tile fixes, else a bit per neighbour it joins
## (north 1, east 2, south 4, west 8).
func shape_of(cell: Vector2i) -> int:
	var fixed := _fixed(cell, SHAPE_DATA)
	if fixed >= 0:
		return fixed
	var mask := 0
	for i in 4:
		if _reaches(cell + SIDES[i], (i + 2) % 4):
			mask |= 1 << i
	return mask


## True when a wall stands in `cell` with an arm toward side `side` (any side for a cell whose shape
## follows its neighbours).
func _reaches(cell: Vector2i, side: int) -> bool:
	if style_of(cell).is_empty():
		return false
	var fixed := _fixed(cell, SHAPE_DATA)
	return fixed < 0 or (fixed & (1 << side)) != 0


## The palette tile's value `data_name` on `cell` (shape or parity), or -1 when it fixes none.
func _fixed(cell: Vector2i, data_name: String) -> int:
	var data := get_cell_tile_data(cell)
	if data == null or not tile_set.has_custom_data_layer_by_name(data_name):
		return -1
	return int(data.get_custom_data(data_name))


## A sprite showing `style`'s piece of `shape` for a cell at `cell` (its parity, or `parity` when
## given, picks the stretch of the repeating pattern), standing on the cell's foot; null when the
## style is unknown.
static func piece(style: String, shape: int, cell: Vector2i, parity: int = -1) -> Sprite2D:
	var entry: Dictionary = table().get(style, {})
	if entry.is_empty():
		return null
	var path := str(entry["texture"])
	if not _textures.has(path):
		_textures[path] = load(path)
	var foot: Array = entry["foot"]
	var sprite := Sprite2D.new()
	sprite.texture = _textures[path]
	sprite.region_enabled = true
	sprite.region_rect = region(style, shape, cell, parity)
	sprite.centered = false
	sprite.offset = -Vector2(float(foot[0]), float(foot[1]))
	sprite.scale = Vector2.ONE * float(entry.get("scale", 0.5))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return sprite


## Where `style`'s piece of `shape` for a cell at `cell` is in the style's sheet (a column per shape,
## a row per pattern stretch: the cell's parity, or `parity` when given); empty when the style is
## unknown.
static func region(style: String, shape: int, cell: Vector2i, parity: int = -1) -> Rect2:
	var entry: Dictionary = table().get(style, {})
	if entry.is_empty():
		return Rect2()
	var frame: Array = entry["frame"]
	var row := parity if parity >= 0 else posmod(cell.x, 2) + 2 * posmod(cell.y, 2)
	return Rect2(shape * float(frame[0]), row * float(frame[1]), float(frame[0]), float(frame[1]))


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
	for child in holder.get_children():
		child.free()
	var size := Vector2(tile_set.tile_size)
	var shapes := {}
	for cell in get_used_cells():
		var style := style_of(cell)
		if style.is_empty() or (shown_cells.has_area() and not shown_cells.has_point(cell)):
			continue
		var shape := shape_of(cell)
		var sprite := piece(style, shape, cell, _fixed(cell, PARITY_DATA))
		if sprite == null:
			continue
		sprite.position = Vector2(cell) * size + FOOT
		holder.add_child(sprite)
		shapes[cell] = [style, shape]
	if not Engine.is_editor_hint():
		_build_collision(shapes, size)


## Each wall's footprint (the style's rectangles for its shape) is solid.
func _build_collision(shapes: Dictionary, size: Vector2) -> void:
	var old := get_node_or_null(COLLISION)
	if old != null:
		old.free()
	var body := StaticBody2D.new()
	body.name = COLLISION
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for cell: Vector2i in shapes:
		var entry: Dictionary = table().get(shapes[cell][0], {})
		for rect: Array in (entry.get("collision", {}) as Dictionary).get(str(shapes[cell][1]), []):
			var shape := CollisionShape2D.new()
			var box := RectangleShape2D.new()
			box.size = Vector2(rect[2], rect[3])
			shape.shape = box
			shape.position = Vector2(cell) * size + Vector2(rect[0], rect[1]) + box.size / 2.0
			body.add_child(shape)
