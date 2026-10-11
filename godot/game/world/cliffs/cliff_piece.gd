@tool
extends Node2D
## One whole painted cliff (docs/godot/CLIFFS.md "Cliff pieces"): an approved painting, scaled so a
## stone course is one cell and cut out of its surrounding ground (scripts/art/build-cliff-kit.py,
## godot/asset/MAPS/cliffs/kit-<name>.png and .json). Pick the shape in `piece`, put the node on the
## 64-unit grid. Several pieces stack into levels: a later sibling draws over an earlier one.
##
## In the game the piece is solid where its painting has wall (physics layer 1, world) and along a
## 12-unit strip inside its top's open sides; on the top's north side the strip sits `behind_depth`
## units in and an overlay above the bodies draws that band again, so bodies walking along it go
## behind the cliff. Pieces without labels (the dip) are only drawn.
##
## Owner: world (cliffs).

const KIT_DIR := "res://asset/MAPS/cliffs/"
const SHADER := preload("res://game/world/cliffs/cliff_piece.gdshader")
const CELL := 64.0
const TILE := 128.0
const RIM := 12.0
const WALL := ["W", "M", "V"]
## The pieces: the approved paintings (asset/Originals/elevation/cliff-concepts/).
const PIECES := {
	"octagon": "plateau",
	"h-shape 1 level": "h1",
	"h-shape 2 levels": "h2",
	"h-shape 3 levels": "h3",
	"octagon dip": "dip",
}

@export_enum("octagon", "h-shape 1 level", "h-shape 2 levels", "h-shape 3 levels", "octagon dip")
var piece: String = "octagon":
	set(value):
		piece = value
		_rebuild()
## How far (world units) a body walks into the top from its north side, hidden behind it.
@export_range(0.0, 48.0) var behind_depth: float = 32.0:
	set(value):
		behind_depth = value
		_rebuild()

var labels: Array = []
var _texture: Texture2D
var _cells := Vector2i.ZERO


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var kit: String = PIECES.get(piece, "plateau")
	_texture = load(KIT_DIR + "kit-%s.png" % kit) as Texture2D
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT_DIR + "kit-%s.json" % kit))
	labels = (parsed as Dictionary).get("labels", []) if parsed is Dictionary else []
	_cells = Vector2i(int(parsed["cells"][0]), int(parsed["cells"][1])) if parsed is Dictionary else Vector2i.ZERO
	_overlay()
	queue_redraw()
	if not Engine.is_editor_hint():
		_build_collision()


func _draw() -> void:
	if _texture != null:
		draw_texture_rect(_texture, Rect2(Vector2.ZERO, Vector2(_cells) * CELL), false)


func label_at(c: Vector2i) -> String:
	if c.y < 0 or c.y >= labels.size() or c.x < 0 or c.x >= String(labels[c.y]).length():
		return "L"
	var ch := String(labels[c.y])[c.x]
	return "T" if ch == "X" else ch


## The behind overlay: the painting again above the bodies, only on the north band of the top's
## north-side cells.
func _overlay() -> void:
	var overlay := get_node_or_null(^"Behind") as Node2D
	if labels.is_empty() or _texture == null:
		if overlay != null:
			overlay.queue_free()
		return
	if overlay == null:
		overlay = BehindDrawer.new()
		overlay.name = "Behind"
		add_child(overlay)
	overlay.z_index = 2
	var map := Image.create_empty(_cells.x, _cells.y, false, Image.FORMAT_R8)
	for y in _cells.y:
		for x in _cells.x:
			var c := Vector2i(x, y)
			if label_at(c) == "T" and label_at(c + Vector2i.UP) != "T":
				map.set_pixel(x, y, Color(1, 1, 1))
	var shader_material := ShaderMaterial.new()
	shader_material.shader = SHADER
	shader_material.set_shader_parameter(&"behind_map", ImageTexture.create_from_image(map))
	shader_material.set_shader_parameter(&"cells", Vector2(_cells))
	shader_material.set_shader_parameter(&"behind_frac", behind_depth / CELL)
	overlay.material = shader_material
	(overlay as BehindDrawer).texture = _texture
	(overlay as BehindDrawer).size = Vector2(_cells) * CELL
	overlay.queue_redraw()


func _build_collision() -> void:
	var old := get_node_or_null(^"Collision")
	if old != null:
		old.free()
	if labels.is_empty():
		return
	var body := StaticBody2D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for rect in collision_rects():
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.get_center()
		body.add_child(shape)


## Solid rectangles (world units, this node's space): wall cells, and the top's rims (the north rim
## `behind_depth` in), inner corners included.
func collision_rects() -> Array[Rect2]:
	return rects_for(label_at, _cells, behind_depth)


## The solid rectangles of a cliff whose cell labels `label_at` gives (Callable(Vector2i) -> String:
## T top, W / M / V wall, anything else open), `cells` in size. Shared with cliff_builder.gd.
static func rects_for(label_at: Callable, cells: Vector2i, behind: float) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var north := clampf(behind, 0.0, CELL - RIM)
	var is_top := func(c: Vector2i) -> bool: return label_at.call(c) == "T"
	var open := func(c: Vector2i) -> bool: return label_at.call(c) != "T" and not WALL.has(label_at.call(c))
	for y in cells.y:
		for x in cells.x:
			var c := Vector2i(x, y)
			var p := Vector2(c) * CELL
			if WALL.has(label_at.call(c)):
				rects.append(Rect2(p, Vector2(CELL, CELL)))
				continue
			if not is_top.call(c):
				continue
			var top_open: bool = open.call(c + Vector2i.UP)
			var start := north if top_open else 0.0
			if top_open:
				rects.append(Rect2(p + Vector2(0, north), Vector2(CELL, RIM)))
			if open.call(c + Vector2i.DOWN):
				rects.append(Rect2(p + Vector2(0, CELL - RIM), Vector2(CELL, RIM)))
			if open.call(c + Vector2i.LEFT):
				rects.append(Rect2(p + Vector2(0, start), Vector2(RIM, CELL - start)))
			if open.call(c + Vector2i.RIGHT):
				rects.append(Rect2(p + Vector2(CELL - RIM, start), Vector2(RIM, CELL - start)))
			for d: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
				if is_top.call(c + Vector2i(d.x, 0)) and is_top.call(c + Vector2i(0, d.y)) and open.call(c + d):
					rects.append(Rect2(p + Vector2(0.0 if d.x < 0 else CELL - RIM, 0.0 if d.y < 0 else CELL - RIM), Vector2(RIM, RIM)))
	return rects


class BehindDrawer:
	extends Node2D
	var texture: Texture2D
	var size := Vector2.ZERO

	func _draw() -> void:
		if texture != null:
			draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
