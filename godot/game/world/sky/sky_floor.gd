@tool
extends Node2D
class_name SkyFloor
## A sky floor (docs/godot/SKY_FLOOR.md): islands of ground high in the sky. Inside its area (`size`
## from its position, outlined in the editor) the sky is painted as holes on the world's `elevation`
## layer: every cell painted at `sky_level` or lower is sky; the islands are the ground left higher, and
## their cliff walls hang into the sky as any hole's walls do. Holes outside the area stay holes. It
## draws:
##
## - a backdrop far below the islands: up to four pictures that tile, far to near (the far ground,
##   clouds, wisps), each moved with the camera by its own scroll factor (1 sticks to the islands, 0
##   never moves) and drifting on its own, so the sky reads as high above a fixed ground;
## - the cloud bank round every island's foot (owner, 2026-11-01: "not like flying blocks but
##   mountains that go over the clouds"): out over the sky `bank_reach` units from the islands with
##   puffy edges, and up the bottom `bank_cover` units of every front and 45° face the elevation draws
##   into the sky, whatever the wall's height (owner, 2026-11-02: "almost at the bottoms of the wall").
##   A side wall's strip shows its stone all the way, the bank thinning out up it from the front corner
##   (owner, 2026-11-11: "sometimes clouds start from the top edge on lateral walls").
##
## Falls: in the game it lays a SkyFall (sky_fall.gd: the dungeon kit's void hazard pinned to the sky
## cells and to `sky_level`) over its area (`falls`), so a slime that pushes off a rim falls into the
## clouds and is put back where it fell from, losing `dungeon.void.damage`. A SkyFall child of its own
## is used instead (to give it return points). Bridges across the sky are rope bridges (rope_bridge.gd,
## the dungeon kit's drawbridge always down): keep them after it in the tree, so they draw over it.
##
## The walls that hang into the sky stand on no ground: the world's elevation reads the sky floors'
## areas (they are in the group Elevation.SKY_GROUP: `sky_cells_on`) and draws those walls without a
## foot (no plants, no foot strip, no shadow) and lays no ledge dressing there.
##
## Three draws, all with sky_floor.gdshader, made at run time (never saved):
##
## - the backdrop: the Shade's own mesh of the holes' floors drawn again, inside the world elevation's
##   drawing (the last child of its Shade, where a pit's look sits: hazard.gd `_attach_look`), over
##   the darkened floors and under every wall, rim and top. The shader keeps its triangles in the area
##   at `sky_level` or lower (their level is in the mesh), so it fills exactly the floor the elevation
##   leaves in view, and the tops and walls draw over it as they are. It draws the sky's layers and the
##   bank out over the sky;
## - the lip: each of the elevation's wall meshes (its Sides) drawn again right after itself, with the
##   bank up its foot: the mesh's vertex colour holds each point's height in levels (elevation_sides.gd
##   `_add_wall`), so the bank covers exactly the bottom of what is drawn; and the sky in a thin band
##   past each foot line, where the wall's wobbling foot and the floor's straight edge leave a gap;
## - without an elevation drawing to sit in, one draw over the area does both from the field alone.
##
## The field (`_build_field`, a 16-unit texel) holds each sky cell's level, the distance out from the
## islands' silhouettes (their tops with the corners the elevation cuts at 45°, their south walls
## `elevation` levels deep, their side strips), the distance up a side wall's strip from its foot, and
## the distance to the nearest top. It is rebuilt when the paint or the area changes, in the editor
## too, where the layers drift and follow the editor's view.
##
## Owner: world (sky).

const Elevation := preload("res://game/world/elevation/elevation.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const SkyFallScript := preload("res://game/world/sky/sky_fall.gd")
const SHADER := preload("res://game/world/sky/sky_floor.gdshader")

const CELL := 64.0
## Texels of the field per cell (16 units each).
const TEXELS_PER_CELL := 4
## Cells of field round the area (the islands' edges just outside it).
const MARGIN_CELLS := 3
## Units the field's distances reach each way, and the distance to a top.
const FIELD_RANGE := 256.0
const TO_LAND_RANGE := 64.0
const FAR := 1.0e9
## The fallback draw sits over the holes' floors and walls, under every body.
const LOOK_Z := -1
const LOOK_NAME := "SkyLook"
const LIP_PREFIX := "SkyLip-"
## The meta a lip carries: walls are told from lips by it, not by name (a lip made while an old one
## of the same name waited to be freed would be renamed by Godot).
const LIP_META := &"sky_lip"
## The art is 128 px a cell: two pixels a unit.
const PX_PER_UNIT := 2.0
const LAYERS := 4
## A painted cell that is no level (a stair or a ramp: the palette's lower rows).
const NO_LEVEL := -99
const ART := "res://asset/MAPS/sky/"
## The shader's `sky_mode`: the lip on a wall mesh, the backdrop (sky and bank, under the walls), both
## from the field alone (no elevation drawing to sit in).
const SKY_LIP := 0
const SKY_BACKDROP := 1
const SKY_FIELD_ONLY := 2
## In the editor the settings are handed to the shaders this often (seconds), not every frame.
const EDITOR_APPLY_S := 0.25
const EDITOR_EDGE := Color(0.55, 0.8, 1.0, 0.9)

## Cells of the area painted at this level or lower on the `elevation` layer are sky. The islands'
## cliffs are as many courses tall as their tops are levels above it.
@export var sky_level: int = -2:
	set(value):
		sky_level = value
		_queue_build()
## The sky floor's area (world units from this node's position): only cells whose middle lies inside
## it are sky.
@export var size: Vector2 = Vector2(1024, 1024):
	set(value):
		size = value
		_queue_build()
		queue_redraw()

@export_group("Layer 1 (farthest)", "layer1_")
@export_file("*.webp", "*.png") var layer1_picture: String = ART + "far-forest.webp"
## How much it moves with the camera: 1 sticks to the islands, 0 never moves.
@export_range(0.0, 1.0, 0.01) var layer1_scroll: float = 0.2
## Its own drift (world units a second).
@export var layer1_drift: Vector2 = Vector2.ZERO
## 1 draws the picture at 128 px a cell; 2 twice as big.
@export_range(0.05, 8.0, 0.01) var layer1_scale: float = 0.6
@export var layer1_tint: Color = Color.WHITE
## Mixed over it by its alpha: the haze of distance.
@export var layer1_haze: Color = Color(0.27, 0.47, 0.51, 0.22)
@export_range(0.0, 1.0, 0.01) var layer1_opacity: float = 1.0

@export_group("Layer 2", "layer2_")
@export_file("*.webp", "*.png") var layer2_picture: String = ART + "clouds-big-b.webp"
@export_range(0.0, 1.0, 0.01) var layer2_scroll: float = 0.45
@export var layer2_drift: Vector2 = Vector2(6.0, 1.0)
@export_range(0.05, 8.0, 0.01) var layer2_scale: float = 1.4
@export var layer2_tint: Color = Color.WHITE
@export var layer2_haze: Color = Color(0.92, 0.92, 0.97, 0.18)
@export_range(0.0, 1.0, 0.01) var layer2_opacity: float = 1.0

@export_group("Layer 3", "layer3_")
@export_file("*.webp", "*.png") var layer3_picture: String = ART + "clouds-big-a.webp"
@export_range(0.0, 1.0, 0.01) var layer3_scroll: float = 0.62
@export var layer3_drift: Vector2 = Vector2(11.0, 2.0)
@export_range(0.05, 8.0, 0.01) var layer3_scale: float = 1.0
@export var layer3_tint: Color = Color.WHITE
@export var layer3_haze: Color = Color(0.92, 0.92, 0.97, 0.18)
@export_range(0.0, 1.0, 0.01) var layer3_opacity: float = 1.0

@export_group("Layer 4 (nearest)", "layer4_")
@export_file("*.webp", "*.png") var layer4_picture: String = ART + "clouds-wisps.webp"
@export_range(0.0, 1.0, 0.01) var layer4_scroll: float = 0.8
@export var layer4_drift: Vector2 = Vector2(20.0, 3.0)
@export_range(0.05, 8.0, 0.01) var layer4_scale: float = 1.1
@export var layer4_tint: Color = Color.WHITE
@export var layer4_haze: Color = Color(0.93, 0.93, 0.97, 0.1)
@export_range(0.0, 1.0, 0.01) var layer4_opacity: float = 0.75

@export_group("Cloud bank", "bank_")
## The bank's picture (a sea of cloud tops that tiles); empty: no bank.
@export_file("*.webp", "*.png") var bank_picture: String = ART + "cloud-sea.webp"
@export_range(0.05, 8.0, 0.01) var bank_scale: float = 0.8
@export var bank_drift: Vector2 = Vector2(4.0, 1.0)
@export var bank_tint: Color = Color.WHITE
## The islands' shade on the bank near their feet (alpha: how much).
@export var bank_shade: Color = Color(0.62, 0.6, 0.78, 0.3)
## How far up a cliff wall from its foot the bank reaches (world units).
@export_range(0.0, 256.0, 1.0) var bank_cover: float = 20.0
## How far out from the islands it spreads before it thins (world units).
@export_range(0.0, 240.0, 1.0) var bank_reach: float = 40.0
## How soft its edges are (world units).
@export_range(1.0, 128.0, 1.0) var bank_soft: float = 8.0
## How far its puffs push its edges in and out (world units).
@export_range(0.0, 128.0, 1.0) var bank_puff: float = 16.0

@export_group("Edges")
## The width of an island's side wall strip (docs/godot/ELEVATION.md "Side walls"), left clear of the
## open sky.
@export_range(0.0, 64.0, 1.0) var side_strip: float = 24.0:
	set(value):
		side_strip = value
		_queue_build()
## The sky fades in over this much next to a top (world units).
@export_range(0.0, 32.0, 0.5) var rim_soft: float = 4.0
## Under every layer: shows where the first layer is see-through or has no picture.
@export var base_colour: Color = Color(0.42, 0.62, 0.72)

@export_group("")
## Lays a SkyFall (sky_fall.gd) over the area in the game: a slime that drops into the sky falls and
## is put back where it fell from.
@export var falls: bool = true

## Pictures by path, loaded once (imported, else the file itself: SheetSprite.load_picture).
static var _pictures: Dictionary = {}
## The bank picture's luminance (mean, spread) by path.
static var _lums: Dictionary = {}

## The materials: the backdrop's, the lip's (shared by every wall mesh's copy) and the fallback's.
var _sky_material: ShaderMaterial
var _lip_material: ShaderMaterial
var _field_material: ShaderMaterial
## The backdrop (in the elevation's Shade), the elevation's Sides holder the lips were made for, and
## the fallback draw (a child, z LOOK_Z, shown only without an elevation drawing).
var _backdrop: MeshInstance2D
var _sides: Node
var _field_look: Node2D
var _attached := false
var _layer: TileMapLayer
var _ground: TileMapLayer
## The world elevation's depth map holder (elevation_occlusion.gd) and the texture handed on.
var _occlusion: Node
var _depth: Texture2D
## The area's cells (inclusive) on the painted layer, and the sky cells' rectangle (global).
var _first := Vector2i.ZERO
var _last := Vector2i(-1, -1)
var _sky_rect := Rect2()
var _queued := false
var _apply_wait := 0.0
## The area's cells and sky level the world's elevation last built its walls by (editor: it builds them
## again when they change).
var _built_for: Array = []


func _init() -> void:
	# the world's elevation finds the sky floors by it (`sky_cells_on`)
	add_to_group(Elevation.SKY_GROUP)


func _ready() -> void:
	z_index = LOOK_Z
	_build_field()
	if Engine.is_editor_hint():
		return
	if falls:
		_lay_hazard.call_deferred()


## `z_index` is LOOK_Z, set in `_ready`: not stored.
func _validate_property(property: Dictionary) -> void:
	if property["name"] == "z_index":
		property["usage"] = int(property["usage"]) & ~PROPERTY_USAGE_STORAGE


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_rect(Rect2(Vector2.ZERO, size), EDITOR_EDGE, false, 3.0)
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, Vector2(8, 24), "sky floor (cells at %d or lower)" % sky_level, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, EDITOR_EDGE)


func _notification(what: int) -> void:
	# moved in the editor: the area moved with it
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_queue_build()


func _process(delta: float) -> void:
	if _sky_material == null:
		return
	var attached := _attach_backdrop()
	attached = _attach_lips() and attached
	if attached != _attached:
		_attached = attached
		_field_look.visible = not attached
	if Engine.is_editor_hint():
		_apply_wait -= delta
		if _apply_wait <= 0.0:
			_apply_wait = EDITOR_APPLY_S
			_apply()
	_sync_depth()
	var view := get_viewport_rect().size
	var camera := get_canvas_transform().affine_inverse() * (view * 0.5)
	for material: ShaderMaterial in _materials():
		material.set_shader_parameter(&"camera", camera)


## The area's cells (global): the sky's rectangle (SkyFall's own).
func area_rect() -> Rect2:
	return _sky_rect


## The area's cells on `painted` (the world's `elevation` layer) when that is the layer this sky floor
## reads, else an empty rectangle: the world's elevation asks it (elevation.gd `_sky_floors`), so the
## walls that hang into the sky get no foot.
func sky_cells_on(painted: TileMapLayer) -> Rect2i:
	if painted == null or not is_inside_tree() or _painted_layer() != painted:
		return Rect2i()
	var cells := _area_cells(painted)
	return cells if cells.has_area() else Rect2i()


## The cells of `painted` whose middle lies in the area.
func _area_cells(painted: TileMapLayer) -> Rect2i:
	var area := Rect2(global_position, size).abs()
	var half := Vector2(CELL, CELL) * 0.5
	var first := painted.local_to_map(painted.to_local(area.position + half))
	var last := painted.local_to_map(painted.to_local(area.end - half))
	return Rect2i(first, last - first + Vector2i.ONE)


## True when `point` (global) is on a sky cell: inside the area, painted at `sky_level` or lower.
func is_sky_at(point: Vector2) -> bool:
	var painted := _painted_layer()
	if painted == null:
		return false
	var cell := painted.local_to_map(painted.to_local(point))
	if cell.x < _first.x or cell.y < _first.y or cell.x > _last.x or cell.y > _last.y:
		return false
	var at := _level(painted, cell)
	return at != NO_LEVEL and at <= sky_level


func _queue_build() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_build_field.call_deferred()


## The painted `elevation` layer of the world scene it stands in (as hazard.gd finds it), or null.
func _painted_layer() -> TileMapLayer:
	if _layer != null and is_instance_valid(_layer) and _layer.is_inside_tree():
		return _layer
	var at: Node = get_parent()
	while at != null:
		var ground := Elevation.find_ground_in(at)
		if ground != null:
			_ground = ground
			_layer = Elevation.find_layer(ground)
			if _layer != null and Engine.is_editor_hint() and not _layer.changed.is_connected(_queue_build):
				_layer.changed.connect(_queue_build)
			return _layer
		at = at.get_parent()
	return null


## The level painted on `cell` (unpainted 0; a stair or a ramp NO_LEVEL).
static func _level(painted: TileMapLayer, cell: Vector2i) -> int:
	var data := painted.get_cell_tile_data(cell)
	if data == null:
		return 0
	if painted.get_cell_atlas_coords(cell).y > 0:
		return NO_LEVEL
	return int(data.get_custom_data(Elevation.LEVEL_DATA_LAYER))


## Reads the paint inside the area and makes the field the shaders read (see the class notes).
func _build_field() -> void:
	_queued = false
	set_notify_transform(Engine.is_editor_hint())
	_sky_rect = Rect2()
	var painted := _painted_layer()
	if painted == null:
		_drop_look()
		return
	var cells := _area_cells(painted)
	_first = cells.position
	_last = cells.end - Vector2i.ONE
	_rebuild_walls([cells, sky_level])
	if _last.x < _first.x or _last.y < _first.y:
		_drop_look()
		return
	var region := Rect2i(_first, _last - _first + Vector2i.ONE).grow(MARGIN_CELLS)
	var cw := region.size.x
	var ch := region.size.y
	# per cell: sky, level, and under a top: units from the top's edge to the cell's top, the wall's height
	var sky := PackedByteArray()
	var level := PackedInt32Array()
	var wall_top := PackedFloat32Array()
	var wall_h := PackedFloat32Array()
	sky.resize(cw * ch)
	level.resize(cw * ch)
	wall_top.resize(cw * ch)
	wall_h.resize(cw * ch)
	var any := false
	for y in ch:
		for x in cw:
			var cell := region.position + Vector2i(x, y)
			var at := _level(painted, cell)
			var i := y * cw + x
			var inside := cell.x >= _first.x and cell.y >= _first.y and cell.x <= _last.x and cell.y <= _last.y
			sky[i] = 1 if inside and at != NO_LEVEL and at <= sky_level else 0
			level[i] = at if at != NO_LEVEL else sky_level + 1
			any = any or sky[i] == 1
	if not any:
		_drop_look()
		return
	for x in cw:
		var land_row := -1
		var land_level := 0
		var drop := 0
		for y in ch:
			var i := y * cw + x
			wall_top[i] = -1.0
			if sky[i] == 0:
				land_row = y
				land_level = level[i]
				continue
			if land_row < 0:
				continue
			if land_row == y - 1:
				drop = maxi(0, land_level - level[i])
			wall_top[i] = float(y - land_row - 1) * CELL
			wall_h[i] = float(drop) * CELL
	# per cell, once: the corner the elevation cuts at 45° into a sky cell (`_chamfer_of`), and which of
	# its sides is such a cut corner, with no side strip (`_cut_sides`)
	var chamfers := PackedByteArray()
	var cuts := PackedByteArray()
	chamfers.resize(cw * ch)
	cuts.resize(cw * ch)
	for y in ch:
		for x in cw:
			if sky[y * cw + x] == 1:
				chamfers[y * cw + x] = _chamfer_of(sky, cw, ch, x, y)
				cuts[y * cw + x] = _cut_sides(sky, cw, ch, x, y)
	# per texel: what it is (0 open sky, 1 a wall or a side strip, 2 a top), and how far up a wall
	var t := TEXELS_PER_CELL
	var texel := CELL / float(t)
	var w := cw * t
	var h := ch * t
	var kind := PackedByteArray()
	var inside := PackedFloat32Array()
	var strips := PackedFloat32Array()
	kind.resize(w * h)
	inside.resize(w * h)
	strips.resize(w * h)
	strips.fill(FIELD_RANGE)
	for ty in h:
		var cy := ty / t
		var ly := (float(ty % t) + 0.5) * texel
		for tx in w:
			var cx := tx / t
			var lx := (float(tx % t) + 0.5) * texel
			var ci := cy * cw + cx
			var ti := ty * w + tx
			if sky[ci] == 0 or _in_chamfer(chamfers[ci], lx, ly):
				kind[ti] = 2
				inside[ti] = -FIELD_RANGE
				continue
			var f := FAR
			if wall_top[ci] >= 0.0 and wall_top[ci] + ly < wall_h[ci]:
				f = -(wall_h[ci] - wall_top[ci] - ly)
			if side_strip > 0.0:
				for side: int in [-1, 1]:
					var nx := cx + side
					if nx < 0 or nx >= cw:
						continue
					var across := lx if side < 0 else CELL - lx
					# (half a texel past the strip: the texel on its outer edge is the strip's too, so
					# read smoothly the whole strip is a wall, not open sky from its middle on)
					if across >= side_strip + texel * 0.5 or cuts[ci] & (1 if side < 0 else 2):
						continue
					var ni := cy * cw + nx
					# the side strip of a top beside it (its whole height), or of a wall beside it
					# (what is left of that wall down to its foot)
					var height := 0.0
					if sky[ni] == 0:
						height = float(maxi(0, level[ni] - level[ci])) * CELL
					elif wall_top[ni] >= 0.0 and wall_top[ni] + ly < wall_h[ni]:
						height = wall_h[ni] - wall_top[ni] - ly
					if height <= 0.0:
						continue
					var strip := -maxf(side_strip - across, 0.0) / side_strip * height
					f = strip if f == FAR else maxf(f, strip)
					strips[ti] = strip if strips[ti] >= FIELD_RANGE else maxf(strips[ti], strip)
			if f != FAR:
				kind[ti] = 1
				inside[ti] = f
	var out_dist := _chamfer(kind, 1, w, h, texel)
	var to_top := _chamfer(kind, 2, w, h, texel)
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for ti in w * h:
		var ci := (ti / w / t) * cw + (ti % w) / t
		var signed := inside[ti] if kind[ti] != 0 else out_dist[ti]
		data[ti * 4] = _encode_distance(strips[ti])
		data[ti * 4 + 1] = _encode_distance(signed)
		data[ti * 4 + 2] = clampi(roundi((float(level[ci]) + 8.0) / 16.0 * 255.0), 1, 255) if sky[ci] == 1 else 0
		data[ti * 4 + 3] = clampi(roundi(clampf(to_top[ti] / TO_LAND_RANGE, 0.0, 1.0) * 255.0), 0, 255)
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	var origin := painted.to_global(Vector2(region.position) * CELL)
	_sky_rect = Rect2(painted.to_global(Vector2(_first) * CELL), Vector2(_last - _first + Vector2i.ONE) * CELL)
	_ensure_look()
	# the walls the lip copies follow the area: made again on the next frame
	_drop_lips()
	var field := ImageTexture.create_from_image(image)
	for material: ShaderMaterial in _materials():
		material.set_shader_parameter(&"field", field)
		material.set_shader_parameter(&"field_origin", origin)
		material.set_shader_parameter(&"field_size", Vector2(w, h))
		material.set_shader_parameter(&"field_texel", texel)
		material.set_shader_parameter(&"field_range", FIELD_RANGE)
		material.set_shader_parameter(&"to_land_range", TO_LAND_RANGE)
		material.set_shader_parameter(&"area", Vector4(_sky_rect.position.x, _sky_rect.position.y, _sky_rect.size.x, _sky_rect.size.y))
	_apply()
	if _field_look != null:
		_field_look.queue_redraw()


## In the editor the world's elevation builds its walls again when the area's cells or the sky level
## change (`built_for`), so the walls that hang into the sky lose their feet as the area is moved. (In
## the game the area never changes: the elevation reads it when it builds.)
func _rebuild_walls(built_for: Array) -> void:
	if built_for == _built_for:
		return
	var first := _built_for.is_empty()
	_built_for = built_for
	if first or not Engine.is_editor_hint():
		return
	var elevation := _elevation()
	if elevation != null:
		elevation.call(&"queue_rebuild")


## The corner the elevation cuts at 45° into sky cell (`cx`, `cy`): land on one side across and one side
## up or down (an L round the cell; not on both sides of either), as 1 + (east: 1) + (south: 2), 0 for
## none. Its half past the diagonal between those two sides is the top's (`_in_chamfer`).
static func _chamfer_of(sky: PackedByteArray, cw: int, ch: int, cx: int, cy: int) -> int:
	var west := _land(sky, cw, ch, cx - 1, cy)
	var east := _land(sky, cw, ch, cx + 1, cy)
	var north := _land(sky, cw, ch, cx, cy - 1)
	var south := _land(sky, cw, ch, cx, cy + 1)
	if west == east or north == south:
		return 0
	return 1 + (1 if east else 0) + (2 if south else 0)


## Whether point (`lx`, `ly`, units in the cell) lies in the half of a cut corner (`chamfer`, from
## `_chamfer_of`) that the elevation raises.
static func _in_chamfer(chamfer: int, lx: float, ly: float) -> bool:
	if chamfer == 0:
		return false
	var toward_x := lx if (chamfer - 1) & 1 else CELL - lx
	var toward_y := ly if (chamfer - 1) & 2 else CELL - ly
	return toward_x + toward_y > CELL


## The sides (1 west, 2 east) of sky cell (`cx`, `cy`) where it is a cut corner of the land there: land
## on that side and above or below it, open sky past both (an L round it, as a corner cell painted out
## or a step of a 45° edge). The elevation draws a 45° edge across it there, no side wall's strip.
static func _cut_sides(sky: PackedByteArray, cw: int, ch: int, cx: int, cy: int) -> int:
	var sides := 0
	for side: int in [-1, 1]:
		if not _land(sky, cw, ch, cx + side, cy):
			continue
		for up: int in [-1, 1]:
			if _land(sky, cw, ch, cx, cy + up) and not _land(sky, cw, ch, cx + side, cy - up) \
					and not _land(sky, cw, ch, cx - side, cy + up):
				sides |= 1 if side < 0 else 2
	return sides


static func _land(sky: PackedByteArray, cw: int, ch: int, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < cw and y < ch and sky[y * cw + x] == 0


## A distance (units, ±FIELD_RANGE) as a byte, 0.5 at 0.
static func _encode_distance(units: float) -> int:
	return clampi(roundi((clampf(units, -FIELD_RANGE, FIELD_RANGE) / FIELD_RANGE * 0.5 + 0.5) * 255.0), 0, 255)


## Distances (units) from every texel to the nearest texel of `kind` at least `from` (0 on them): two
## chamfer passes.
static func _chamfer(kind: PackedByteArray, from: int, w: int, h: int, step: float) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(w * h)
	var diagonal := step * sqrt(2.0)
	for i in w * h:
		d[i] = 0.0 if kind[i] >= from else FAR
	for y in h:
		for x in w:
			var i := y * w + x
			var v := d[i]
			if x > 0:
				v = minf(v, d[i - 1] + step)
			if y > 0:
				v = minf(v, d[i - w] + step)
				if x > 0:
					v = minf(v, d[i - w - 1] + diagonal)
				if x < w - 1:
					v = minf(v, d[i - w + 1] + diagonal)
			d[i] = v
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			var v := d[i]
			if x < w - 1:
				v = minf(v, d[i + 1] + step)
			if y < h - 1:
				v = minf(v, d[i + w] + step)
				if x < w - 1:
					v = minf(v, d[i + w + 1] + diagonal)
				if x > 0:
					v = minf(v, d[i + w - 1] + diagonal)
			d[i] = v
	return d


func _ensure_look() -> void:
	if _field_look != null and is_instance_valid(_field_look):
		return
	_sky_material = _new_material(SKY_BACKDROP)
	_lip_material = _new_material(SKY_LIP)
	_field_material = _new_material(SKY_FIELD_ONLY)
	_attached = false
	_depth = null
	_field_look = Node2D.new()
	_field_look.name = LOOK_NAME
	_field_look.material = _field_material
	_field_look.draw.connect(_draw_field_look)
	add_child(_field_look)
	set_process(true)


static func _new_material(mode: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"sky_mode", mode)
	return material


func _materials() -> Array[ShaderMaterial]:
	return [_sky_material, _lip_material, _field_material]


func _drop_look() -> void:
	_drop_lips()
	for holder: Node in [_field_look, _backdrop]:
		if holder != null and is_instance_valid(holder):
			holder.queue_free()
	_field_look = null
	_backdrop = null
	_sky_material = null
	_lip_material = null
	_field_material = null
	set_process(false)


func _draw_field_look() -> void:
	if _sky_rect.has_area():
		_field_look.draw_rect(Rect2(_field_look.to_local(_sky_rect.position), _sky_rect.size), Color.WHITE)


## The world's elevation drawing (elevation.gd, under the ground layer), or null.
func _elevation() -> Node:
	return Elevation.find_in(_ground) if _ground != null and is_instance_valid(_ground) else null


## The backdrop inside the elevation's drawing: the Shade's own mesh of the holes' floors (the
## triangles it darkens: no top, no corner patch, no wall's band) drawn again with the sky, as the
## last child of the Shade (over the darkened floors, under every wall, rim and top), so the sky
## fills exactly the floor the elevation leaves in view, whatever shape it draws round the islands
## (45° corners, round ones). Made again after the drawing is rebuilt. False without a drawing.
func _attach_backdrop() -> bool:
	if _backdrop != null and is_instance_valid(_backdrop) and _backdrop.is_inside_tree():
		return true
	_backdrop = null
	var elevation := _elevation()
	var shade := elevation.get_node_or_null(^"Shade") if elevation != null else null
	var holes := shade.get_node_or_null(^"holes") as MeshInstance2D if shade != null else null
	if holes == null or holes.mesh == null:
		return false
	var backdrop := MeshInstance2D.new()
	backdrop.name = "SkyBackdrop-" + str(name)
	backdrop.mesh = holes.mesh
	backdrop.transform = holes.transform
	backdrop.material = _sky_material
	shade.add_child(backdrop)
	_backdrop = backdrop
	return true


## The lip: each wall mesh of the elevation's drawing (its Sides) that reaches the area (its bounds,
## with the field's margin) drawn again right after itself (so the walls' painter's order holds) with
## the bank up its foot. Made again after the drawing is rebuilt and when the area changes. False
## without a drawing.
func _attach_lips() -> bool:
	if _sides != null and is_instance_valid(_sides) and _sides.is_inside_tree():
		return true
	_sides = null
	var elevation := _elevation()
	var sides := elevation.get_node_or_null(^"Sides") if elevation != null else null
	if sides == null:
		return false
	var reach := _sky_rect.grow(float(MARGIN_CELLS) * CELL)
	var walls: Array[MeshInstance2D] = []
	for child: Node in sides.get_children():
		var wall := child as MeshInstance2D
		if wall == null or wall.mesh == null or wall.has_meta(LIP_META):
			continue
		var box := wall.mesh.get_aabb()
		if (wall.global_transform * Rect2(box.position.x, box.position.y, box.size.x, box.size.y)).intersects(reach):
			walls.append(wall)
	for wall: MeshInstance2D in walls:
		var lip := MeshInstance2D.new()
		lip.name = LIP_PREFIX + String(wall.name)
		lip.set_meta(LIP_META, true)
		lip.mesh = wall.mesh
		lip.transform = wall.transform
		lip.material = _lip_material
		wall.add_sibling(lip)
	_sides = sides
	return true


## Takes the lips out of the Sides at once (their names are free for the next ones) and frees them.
func _drop_lips() -> void:
	if _sides != null and is_instance_valid(_sides):
		for child: Node in _sides.get_children():
			if child.has_meta(LIP_META):
				_sides.remove_child(child)
				child.queue_free()
	_sides = null


func _exit_tree() -> void:
	_drop_lips()
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	_backdrop = null


## Hands the backdrop and the lip the elevation's depth map once the world's elevation has drawn it
## (again when it draws anew): under a wall the backdrop shows rock, so a crack between the wall's
## meshes never shows the sky; the lip leaves the tops alone and finds the open sky by it.
func _sync_depth() -> void:
	if _occlusion == null or not is_instance_valid(_occlusion) or not _occlusion.is_inside_tree():
		_occlusion = null
		var elevation := _elevation()
		if elevation != null:
			_occlusion = elevation.get_node_or_null(^"Occlusion")
	var texture: Texture2D = _occlusion.get(&"texture") if _occlusion != null else null
	if texture == _depth:
		return
	_depth = texture
	var rect: Rect2 = _occlusion.get(&"world_rect") if texture != null else Rect2()
	for material: ShaderMaterial in [_sky_material, _lip_material]:
		material.set_shader_parameter(&"depth_map", texture)
		material.set_shader_parameter(&"depth_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))


## Hands the layers and the bank to the shaders.
func _apply() -> void:
	if _sky_material == null:
		return
	var motion := PackedVector4Array()
	var span := PackedVector2Array()
	var tint := PackedVector4Array()
	var haze := PackedVector4Array()
	var opacity := PackedFloat32Array()
	var pictures: Array[Texture2D] = []
	for i in LAYERS:
		var n := i + 1
		var picture := _picture(str(get("layer%d_picture" % n)))
		pictures.append(picture)
		var drift: Vector2 = get("layer%d_drift" % n)
		motion.append(Vector4(drift.x, drift.y, float(get("layer%d_scroll" % n)), 1.0 if picture != null else 0.0))
		var art := Vector2(picture.get_size()) if picture != null else Vector2(CELL, CELL) * PX_PER_UNIT
		span.append(art / PX_PER_UNIT * maxf(0.01, float(get("layer%d_scale" % n))))
		tint.append(_vec4(get("layer%d_tint" % n)))
		haze.append(_vec4(get("layer%d_haze" % n)))
		opacity.append(float(get("layer%d_opacity" % n)))
	var bank := _picture(bank_picture)
	for material: ShaderMaterial in _materials():
		for i in LAYERS:
			material.set_shader_parameter(StringName("layer%d" % (i + 1)), pictures[i])
		material.set_shader_parameter(&"layer_motion", motion)
		material.set_shader_parameter(&"layer_span", span)
		material.set_shader_parameter(&"layer_tint", tint)
		material.set_shader_parameter(&"layer_haze", haze)
		material.set_shader_parameter(&"layer_opacity", opacity)
		material.set_shader_parameter(&"base_colour", Vector3(base_colour.r, base_colour.g, base_colour.b))
		material.set_shader_parameter(&"rim_soft", rim_soft)
		material.set_shader_parameter(&"sky_level", float(sky_level))
		material.set_shader_parameter(&"bank_on", bank != null)
		material.set_shader_parameter(&"bank", bank)
		if bank != null:
			material.set_shader_parameter(&"bank_span", Vector2(bank.get_size()) / PX_PER_UNIT * maxf(0.01, bank_scale))
			material.set_shader_parameter(&"bank_lum", _lum(bank_picture, bank))
		material.set_shader_parameter(&"bank_drift", bank_drift)
		material.set_shader_parameter(&"bank_tint", _vec4(bank_tint))
		material.set_shader_parameter(&"bank_shade", _vec4(bank_shade))
		material.set_shader_parameter(&"bank_cover", bank_cover)
		material.set_shader_parameter(&"bank_reach", bank_reach)
		material.set_shader_parameter(&"bank_soft", bank_soft)
		material.set_shader_parameter(&"bank_puff", bank_puff)


static func _vec4(colour: Color) -> Vector4:
	return Vector4(colour.r, colour.g, colour.b, colour.a)


static func _picture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _pictures.has(path):
		_pictures[path] = SheetSprite.load_picture(path)
	return _pictures[path]


## The mean and spread of a picture's luminance (read once, from a small copy).
static func _lum(path: String, picture: Texture2D) -> Vector2:
	if _lums.has(path):
		return _lums[path]
	var out := Vector2(0.8, 0.08)
	var image := picture.get_image()
	if image != null and not image.is_empty():
		image = image.duplicate() as Image
		if image.is_compressed():
			image.decompress()
		image.resize(64, 64, Image.INTERPOLATE_BILINEAR)
		var sum := 0.0
		var sum_sq := 0.0
		for y in 64:
			for x in 64:
				var c := image.get_pixel(x, y)
				var l := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
				sum += l
				sum_sq += l * l
		var mean := sum / 4096.0
		out = Vector2(mean, sqrt(maxf(0.0, sum_sq / 4096.0 - mean * mean)))
	_lums[path] = out
	return out


## A SkyFall over the area (unless it has one of its own): a drop into the sky is a fall, back to where
## the slime fell from.
func _lay_hazard() -> void:
	if not is_inside_tree() or not _sky_rect.has_area():
		return
	for child: Node in get_children():
		if child is SkyFallScript:
			child.set(&"sky", self)
			return
	var hazard := SkyFallScript.new()
	hazard.name = "SkyFall"
	hazard.set(&"sky", self)
	hazard.set(&"size", _sky_rect.size)
	add_child(hazard)
	hazard.global_position = _sky_rect.position
