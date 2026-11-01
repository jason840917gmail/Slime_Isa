@tool
class_name InteriorTrimLayer
extends TileMapLayer
## Floor trim along interior walls (docs/godot/INTERIOR_WALLS.md "Floor trim"): Add Node >
## InteriorTrimLayer in a room scene beside its `interior-walls` layer (same grid, position (0, 0)),
## name it `floor-trim`, and paint floor cells along the walls from its palette
## (game/world/interior/interior_trim_tileset.tres): a column per shape, a row per colour. A painted
## floor cell draws its trim's band on every side where a wall's face meets it (doors and openings
## too: the paint decides), or the foot of a level's face (a pit's or a raised floor's walls,
## room_faces.gd, the band laid past the part of the cell the face covers), and a corner block where
## two bands meet: at the floor's outer corners, and round a wall or a raised floor jutting into the
## room (with the bands carried on to it). Painting the whole floor is fine: only the cells along the
## walls and faces draw.
##
## The pieces come from scripts/art/pack-floor-trims.py, a shape's in grey, which its trim's ramp
## colours (interior_trim.gdshader); this draws them on the floor, under every body (z -1, as the
## walls; over the level faces and the stairs, z -2, so a band never reaches into a face and is cut
## where a flight's drawing reaches over the floor below it), and keeps only its cells. The palette
## squares show in the editor only.
##
## Owner: world (interior walls).

const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")
const NodeFind := preload("res://game/shared/node_find.gd")
const RoomFaces := preload("res://game/world/elevation/room_faces.gd")
const Elevation := preload("res://game/world/elevation/elevation.gd")
const SHADER := preload("res://game/world/interior/interior_trim.gdshader")

const TILESET := "res://game/world/interior/interior_trim_tileset.tres"
const TABLE := "res://asset/MAPS/walls/interior/floor-trims.json"
const TRIM_DATA := "floor_trim"
## The `elevation` layer's level data layer (Elevation.LEVEL_DATA_LAYER).
const ELEVATION_DATA := "elevation_level"
const HOLDER := "Trim"
## The texels of a trim's ramp (its gradient map, sampled by the grey).
const RAMP_WIDTH := 256
## The sides of a cell, in the order of a band's key (`bands`), and their names in RoomFaces.feet.
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const SIDE_NAMES: Array[String] = ["n", "s", "w", "e"]
const N := 0
const S := 1
const W := 2
const E := 3
## The corners of a cell: its horizontal side, its vertical side.
const CORNERS := {Vector2i(-1, -1): [N, W], Vector2i(1, -1): [N, E], Vector2i(-1, 1): [S, W], Vector2i(1, 1): [S, E]}
## A band's part shorter than this (units) is left out where a flight cuts it.
const MIN_RUN := 2.0

## How strongly the painted squares show over the floor in the editor (0 hides them).
@export_range(0.0, 1.0) var paint_opacity: float = 0.2:
	set(value):
		paint_opacity = value
		_apply_opacity()

var _queued := false
var _walls: InteriorWallLayer
var _elevation: TileMapLayer
var _ground: TileMapLayer
## Where the level faces stand on the floor (RoomFaces.feet), read at each build.
var _feet := {}
## The stairs' drawing in this layer's space (`_stairs_cover`), read at each build.
var _cover: Array[PackedVector2Array] = []
static var _table := {}
## trim -> the material that colours its shape's pieces
static var _materials := {}


func _ready() -> void:
	if tile_set == null:
		tile_set = load(TILESET)
	_apply_opacity()
	if not changed.is_connected(_queue_rebuild):
		changed.connect(_queue_rebuild)
	_walls = NodeFind.child_of(get_parent(), InteriorWalls) as InteriorWallLayer
	# the walls build their floor and faces first: the trim follows each build
	if _walls != null and not _walls.rebuilt.is_connected(_queue_rebuild):
		_walls.rebuilt.connect(_queue_rebuild)
	# and each repaint of the levels, whose faces it follows too
	_elevation = NodeFind.layer_with_data(get_parent(), ELEVATION_DATA)
	if _elevation != null and not _elevation.changed.is_connected(_queue_rebuild):
		_elevation.changed.connect(_queue_rebuild)
	# and each build of the elevation's drawing (its stairs), mounted on the ground layer after this
	_ground = NodeFind.layer_with_tile_set(get_parent(), Elevation.TERRAIN_TILESET_PATH)
	if _ground != null:
		if not _ground.child_entered_tree.is_connected(_watch):
			_ground.child_entered_tree.connect(_watch)
		_watch(Elevation.find_in(_ground))
	_rebuild()


func _watch(node: Node) -> void:
	var elevation := node as Elevation
	if elevation != null and not elevation.built.is_connected(_queue_rebuild):
		elevation.built.connect(_queue_rebuild)


## The palette squares show in the editor only (the layer is enabled there whatever the scene says).
func _apply_opacity() -> void:
	self_modulate.a = paint_opacity if Engine.is_editor_hint() else 0.0
	enabled = Engine.is_editor_hint()


func _queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()


## The trims' table (floor-trims.json); the editor reads it again once it is packed again.
static func table() -> Dictionary:
	if _table.is_empty() or (Engine.is_editor_hint() and int(_table.get("_read", 0)) != FileAccess.get_modified_time(TABLE)):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
		_table = parsed if parsed is Dictionary else {}
		_table["_read"] = FileAccess.get_modified_time(TABLE)
		_materials.clear()
	return _table


## The material that paints a trim's grey pieces in its colour on a floor of `level`: its ramp through
## interior_trim.gdshader (darker below level 0, as the floor), one per trim and level, shared by
## every layer.
static func material_of(trim_name: String, level: int = 0) -> ShaderMaterial:
	var trims: Dictionary = table().get("trims", {})
	var key := "%s@%d" % [trim_name, level]
	if not _materials.has(key):
		var offsets := PackedFloat32Array()
		var colors := PackedColorArray()
		for stop: Array in (trims.get(trim_name, {}) as Dictionary).get("ramp", []):
			offsets.append(float(stop[0]))
			colors.append(Color.html(str(stop[1])))
		var gradient := Gradient.new()
		gradient.offsets = offsets
		gradient.colors = colors
		var ramp := GradientTexture1D.new()
		ramp.gradient = gradient
		ramp.width = RAMP_WIDTH
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("ramp", ramp)
		material.set_shader_parameter("level", float(level))
		_materials[key] = material
	return _materials[key]


## The trim painted on `cell` ("<shape>-<colour>"), or "".
func trim_of(cell: Vector2i) -> String:
	var data := get_cell_tile_data(cell)
	if data == null or tile_set == null or not tile_set.has_custom_data_layer_by_name(TRIM_DATA):
		return ""
	return str(data.get_custom_data(TRIM_DATA))


## The bands to draw: (cell x, cell y, side: N S W E) -> trim, for every painted floor cell's side
## that meets a wall's face (an opening's too) or a level face's foot. A cell a face covers whole (a
## front, a stair) draws none.
func bands() -> Dictionary:
	var out := {}
	if _walls == null:
		return out
	_feet = {}
	if _elevation != null:
		_feet = RoomFaces.feet(_elevation, _walls.get_used_rect(), _elevation.get(&"room_back_faces") == true)
	for cell in get_used_cells():
		var trim := trim_of(cell)
		var foot: Dictionary = _feet.get(cell, {})
		if trim.is_empty() or not _walls.is_floor(cell) or bool(foot.get("full", false)):
			continue
		var faced: Dictionary = foot.get("sides", {})
		for side in SIDES.size():
			if _walls.faces(cell + SIDES[side], cell) or faced.has(SIDE_NAMES[side]):
				out[_key(cell, side)] = trim
	return out


static func _key(cell: Vector2i, side: int) -> Vector3i:
	return Vector3i(cell.x, cell.y, side)


## The level painted on `cell` on the `elevation` layer (0 where none is).
func _level_of(cell: Vector2i) -> int:
	var data := _elevation.get_cell_tile_data(cell) if _elevation != null else null
	return int(data.get_custom_data(ELEVATION_DATA)) if data != null else 0


## How far into `cell` (units) a level face reaches from `side`: where the band along it starts.
func _inset(cell: Vector2i, side: int) -> float:
	var faced: Dictionary = (_feet.get(cell, {}) as Dictionary).get("sides", {})
	return float(faced.get(SIDE_NAMES[side], 0.0))


## Where in `cell` (units, along its side) the band on `side` lies: [its offset across the cell,
## the start and the end of its run along it, clear of the faces on the other two sides].
func _band_at(cell: Vector2i, side: int, depth: float, size: float) -> Array:
	match side:
		N:
			return [_inset(cell, N), _inset(cell, W), size - _inset(cell, E)]
		S:
			return [size - _inset(cell, S) - depth, _inset(cell, W), size - _inset(cell, E)]
		W:
			return [_inset(cell, W), _inset(cell, N), size - _inset(cell, S)]
		_:
			return [size - _inset(cell, E) - depth, _inset(cell, N), size - _inset(cell, S)]


func _rebuild() -> void:
	_queued = false
	if not is_inside_tree() or tile_set == null:
		return
	var old := get_node_or_null(HOLDER)
	if old != null:
		old.free()
	var holder := Node2D.new()
	holder.name = HOLDER
	# on the floor, under every body, as the walls
	holder.z_index = -1
	holder.z_as_relative = false
	add_child(holder)
	var found := bands()
	if found.is_empty():
		return
	_cover = _stairs_cover()
	var size := float(tile_set.tile_size.x)
	var texture := str(table().get("texture", ""))
	var density := float(table().get("cell", 128)) / size
	for key: Vector3i in found:
		var cell := Vector2i(key.x, key.y)
		var shape := _shape_of(found[key])
		if shape.is_empty():
			continue
		var depth := float(shape["depth"]) / density
		var place := _band_at(cell, key.z, depth, size)
		var horizontal := key.z == N or key.z == S
		_run(holder, texture, found[key], shape, cell, horizontal, float(place[0]), float(place[1]), float(place[2]), density)
	# the corner blocks over the bands' meeting: two bands of one cell (the floor's outer corner), or
	# the bands of the two cells beside a floor cell round a wall cell or a raised floor jutting into
	# the room, carried on through this cell to the block when the faces stand back from the edge
	var cells := {}
	for key: Vector3i in found:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				cells[Vector2i(key.x + dx, key.y + dy)] = true
	for cell: Vector2i in cells:
		if not _walls.is_floor(cell) or bool((_feet.get(cell, {}) as Dictionary).get("full", false)):
			continue
		for d: Vector2i in CORNERS:
			var h: int = CORNERS[d][0]
			var v: int = CORNERS[d][1]
			# the cells whose bands meet here: across (the horizontal band) and up/down (the vertical one)
			var across := cell
			var upright := cell
			if not (found.has(_key(cell, h)) and found.has(_key(cell, v))):
				across = cell + Vector2i(d.x, 0)
				upright = cell + Vector2i(0, d.y)
				if not (found.has(_key(across, h)) and found.has(_key(upright, v))):
					continue
			var trim_name: String = found[_key(across, h)]
			var shape := _shape_of(trim_name)
			if shape.is_empty():
				continue
			var depth := float(shape["depth"]) / density
			var corner := Vector2(float(_band_at(upright, v, depth, size)[0]), float(_band_at(across, h, depth, size)[0]))
			var origin := Vector2(cell) * size
			var block := Rect2(origin + corner, Vector2(depth, depth))
			var clear := _uncovered(block, true)
			if clear.size() == 1 and is_equal_approx(clear[0].y - clear[0].x, depth):
				_add(holder, texture, trim_name, shape, "c", block.position, density)
			if across == cell:
				continue
			# the run from the block to the edge it shares with each band's cell
			var h_from := corner.x + depth if d.x > 0 else 0.0
			var h_to := size if d.x > 0 else corner.x
			if h_to > h_from:
				_run(holder, texture, trim_name, shape, cell, true, corner.y, h_from, h_to, density)
			var v_trim: String = found[_key(upright, v)]
			var v_shape := _shape_of(v_trim)
			var v_from := corner.y + depth if d.y > 0 else 0.0
			var v_to := size if d.y > 0 else corner.y
			if not v_shape.is_empty() and v_to > v_from:
				_run(holder, texture, v_trim, v_shape, cell, false, corner.x, v_from, v_to, density)


## The shape a trim is cut in (its depth, variants and pieces on the sheet), or {}.
static func _shape_of(trim_name: String) -> Dictionary:
	var trim: Dictionary = (table().get("trims", {}) as Dictionary).get(trim_name, {})
	return (table().get("shapes", {}) as Dictionary).get(str(trim.get("shape", "")), {})


## A band in `cell`: `across` units from its top (horizontal) or left (vertical) side, running from
## `from` to `to` units along it, cut from the cell's own piece (each starts and ends on a joint, so a
## cut joins the piece beside it).
func _run(holder: Node2D, texture: String, trim_name: String, shape: Dictionary, cell: Vector2i, horizontal: bool,
		across: float, from: float, to: float, density: float) -> void:
	var along := cell.x if horizontal else cell.y
	var piece := "%s%d" % ["h" if horizontal else "v", posmod(along, int(shape["variants"]))]
	var size := float(tile_set.tile_size.x)
	var depth := float(shape["depth"]) / density
	var origin := Vector2(cell) * size
	var rect := Rect2(origin + Vector2(from, across), Vector2(to - from, depth)) if horizontal \
		else Rect2(origin + Vector2(across, from), Vector2(depth, to - from))
	# the parts no flight's drawing lies on
	for part: Vector2 in _uncovered(rect, horizontal):
		if part.y - part.x < MIN_RUN:
			continue
		var at := rect.position + (Vector2(part.x, 0.0) if horizontal else Vector2(0.0, part.x))
		_add(holder, texture, trim_name, shape, piece, at, density, from + part.x, from + part.y, horizontal)


## Each flight's drawing (Elevation's `stairs`, their silhouettes) in this layer's space: a side or
## back flight running down into a pit reaches over the floor below its cells, and no band lies there.
func _stairs_cover() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var elevation := Elevation.find_in(_ground) if _ground != null else null
	if elevation == null:
		return out
	var to_here := get_global_transform().affine_inverse() * elevation.get_global_transform()
	for flight: Object in elevation.stairs:
		for outline: PackedVector2Array in flight.get(&"silhouette"):
			out.append(to_here * outline)
	return out


## The parts of `rect` (a band along x when `horizontal`, else along y) no flight covers: [from, to]
## along it, measured from its start.
func _uncovered(rect: Rect2, horizontal: bool) -> Array[Vector2]:
	var runs: Array[Vector2] = [Vector2(0.0, rect.size.x if horizontal else rect.size.y)]
	if _cover.is_empty():
		return runs
	var box := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)])
	for outline in _cover:
		for part: PackedVector2Array in Geometry2D.intersect_polygons(outline, box):
			var low := INF
			var high := -INF
			for point in part:
				var t := (point.x - rect.position.x) if horizontal else (point.y - rect.position.y)
				low = minf(low, t)
				high = maxf(high, t)
			if high - low < 0.5:
				continue
			var kept: Array[Vector2] = []
			for run in runs:
				if high <= run.x or low >= run.y:
					kept.append(run)
					continue
				if low > run.x:
					kept.append(Vector2(run.x, low))
				if high < run.y:
					kept.append(Vector2(high, run.y))
			runs = kept
	return runs


## Adds a piece at `at` (in the cell it lies in, whose level's light it takes); with `to` past `from`,
## only its part from `from` to `to` units along it.
func _add(holder: Node2D, texture: String, trim_name: String, shape: Dictionary, piece: String, at: Vector2, density: float,
		from: float = 0.0, to: float = -1.0, horizontal: bool = true) -> void:
	var rect: Array = (shape["pieces"] as Dictionary).get(piece, [])
	if rect.is_empty():
		return
	var region := Rect2(rect[0], rect[1], rect[2], rect[3])
	if to > from:
		if horizontal:
			region = Rect2(region.position.x + from * density, region.position.y, (to - from) * density, region.size.y)
		else:
			region = Rect2(region.position.x, region.position.y + from * density, region.size.x, (to - from) * density)
	var sprite := Sprite2D.new()
	sprite.texture = InteriorWalls.picture(texture)
	sprite.material = material_of(trim_name, _level_of(Vector2i((at / float(tile_set.tile_size.x)).floor())))
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.centered = false
	sprite.scale = Vector2.ONE / density
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.position = at
	holder.add_child(sprite)
