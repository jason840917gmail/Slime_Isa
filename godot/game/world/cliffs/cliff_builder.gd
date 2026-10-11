@tool
class_name CliffBuilder
extends Node2D
## A cliff of any size from one approved painting (docs/godot/CLIFFS.md "Cliff builder"). Add it with
## Add Node > CliffBuilder (or duplicate one), put it on the 64-unit grid (its origin is the cliff's
## top-left corner), then set kind, width_cells, height_cells and variation in the Inspector: it
## redraws at once, in the editor too.
##
## How: each painting (scripts/art/build-cliff-kit.py, godot/asset/MAPS/cliffs/kit-<name>.png) is
## split into a head, a straight middle and a tail, across and down. The cliff keeps the head and the
## tail and fills the extra length with runs of the middle in a random order (`variation` picks
## another), crossfaded where two runs meet (cliff_builder.gdshader). A rectangle is an H painting
## stretched: its left leg, the leg's middle, its right leg.
##
## In the game the cliff is solid where its painting has wall (physics layer 1, world) and along a
## strip inside its top's open sides; on the north side the strip sits `behind_depth` units in and an
## overlay above the bodies draws that band again, so bodies walking along it go behind the cliff.
## Cliffs stack: a smaller one placed on a bigger one's top (a later sibling) draws over it.
##
## Owner: world (cliffs).

const CliffPiece := preload("res://game/world/cliffs/cliff_piece.gd")
const SHADER := preload("res://game/world/cliffs/cliff_builder.gdshader")
const KIT_DIR := "res://asset/MAPS/cliffs/"
const CELL := 64.0
const MAX_CELLS := 64
## kind -> kit painting
const KINDS := {
	"octagon": "plateau",
	"rectangle 1 level": "h1",
	"rectangle 2 levels": "h2",
	"rectangle 3 levels": "h3",
	"octagon dip": "dip",
}

@export_enum("octagon", "rectangle 1 level", "rectangle 2 levels", "rectangle 3 levels", "octagon dip")
var kind: String = "octagon":
	set(value):
		kind = value
		_data = {}
		_rebuild()
## Width and height in cells (64 units). The smallest size is the painting's head and tail alone.
@export_range(1, 64) var width_cells: int = 20:
	set(value):
		width_cells = value
		_rebuild()
@export_range(1, 64) var height_cells: int = 16:
	set(value):
		height_cells = value
		_rebuild()
## Another number gives another arrangement of the middle runs.
@export var variation: int = 0:
	set(value):
		variation = value
		_rebuild()
## How far (world units) a body walks into the top from its north side, hidden behind it.
@export_range(0.0, 48.0) var behind_depth: float = 32.0:
	set(value):
		behind_depth = value
		_rebuild()

var _data: Dictionary = {}
var _size := Vector2i.ZERO
var _columns := PackedInt32Array()
var _rows := PackedInt32Array()


func _ready() -> void:
	_rebuild()


## The kit: {"cells": [cols, rows], "columns": [a, b], "rows": [a, b], "tails"?: [c, r], "labels"?}.
func kit_data() -> Dictionary:
	if _data.is_empty():
		var kit: String = KINDS.get(kind, "plateau")
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT_DIR + "kit-%s.json" % kit))
		_data = parsed if parsed is Dictionary else {}
	return _data


## The kit across (axis 0) or down (axis 1): [start, a, b, tail, end]: the head is [start, a), the
## middle [a, b), the tail [tail, end). The painting's empty margin is trimmed to one cell (kept for
## the ferns and stones that spill past the cliff).
func slices(axis: int) -> Array[int]:
	var data := kit_data()
	var key := "columns" if axis == 0 else "rows"
	var a := int(data[key][0])
	var b := int(data[key][1])
	var tail := int(data["tails"][axis]) if data.has("tails") else b
	var total := int(data["cells"][axis])
	var start := 0
	var end := total
	var labels: Array = data.get("labels", [])
	if not labels.is_empty():
		var used: Array[int] = []
		for y in labels.size():
			var row := String(labels[y])
			for x in row.length():
				if row[x] != "L":
					used.append(x if axis == 0 else y)
		used.sort()
		start = maxi(used[0] - 1, 0)
		end = mini(used[-1] + 2, total)
	return [start, a, b, tail, end]


## The smallest size in cells: the head and the tail alone.
func min_size() -> Vector2i:
	if kit_data().is_empty():
		return Vector2i.ONE
	var x := slices(0)
	var y := slices(1)
	return Vector2i(x[1] - x[0] + x[4] - x[3], y[1] - y[0] + y[4] - y[3])


## Which kit column (or row) each cell shows: the head, the middle filled with runs of two to four
## consecutive kit cells from a random start (the first and last middle cells are the ones that meet
## the head and the tail in the painting), then the tail.
static func layout(count: int, s: Array[int], rng: RandomNumberGenerator) -> PackedInt32Array:
	var first := s[1]
	var last := s[2]
	var tail := s[3]
	var total := s[4]
	var out := PackedInt32Array()
	for i in range(s[0], first):
		out.append(i)
	var middle := count - (first - s[0]) - (total - tail)
	var span := last - first
	var fill := PackedInt32Array()
	while fill.size() < middle:
		var start := rng.randi_range(0, span - 1)
		for k in rng.randi_range(2, 4):
			fill.append(first + (start + k) % span)
	fill.resize(maxi(middle, 0))
	if middle > 0:
		fill[0] = first
	if middle > 1:
		fill[middle - 1] = last - 1
	out.append_array(fill)
	for i in range(tail, total):
		out.append(i)
	return out


## The label of a cliff cell (T top, W / M / V wall, else open), from the kit cell it shows.
func label_at(c: Vector2i) -> String:
	var labels: Array = kit_data().get("labels", [])
	if labels.is_empty() or c.x < 0 or c.y < 0 or c.x >= _size.x or c.y >= _size.y:
		return "L"
	var ch := String(labels[_rows[c.y]])[_columns[c.x]]
	return "T" if ch == "X" else ch


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var texture := load(KIT_DIR + "kit-%s.png" % KINDS.get(kind, "plateau")) as Texture2D
	if kit_data().is_empty() or texture == null:
		push_warning("CliffBuilder: kit for '%s' not found in %s (run scripts/art/build-cliff-kit.py)" % [kind, KIT_DIR])
		return
	var least := min_size()
	_size = Vector2i(clampi(width_cells, least.x, MAX_CELLS), clampi(height_cells, least.y, MAX_CELLS))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([kind, variation])
	_columns = layout(_size.x, slices(0), rng)
	_rows = layout(_size.y, slices(1), rng)
	var behind := Image.create_empty(_size.x, _size.y, false, Image.FORMAT_R8)
	for y in _size.y:
		for x in _size.x:
			if label_at(Vector2i(x, y)) == "T" and label_at(Vector2i(x, y - 1)) != "T":
				behind.set_pixel(x, y, Color(1, 1, 1))
	material = _material(texture, behind, false)
	var overlay := get_node_or_null(^"Behind") as Drawer
	if kit_data().has("labels"):
		if overlay == null:
			overlay = Drawer.new()
			overlay.name = "Behind"
			add_child(overlay)
		overlay.z_index = 2
		overlay.material = _material(texture, behind, true)
		overlay.size = Vector2(_size) * CELL
		overlay.queue_redraw()
	elif overlay != null:
		overlay.queue_free()
	queue_redraw()
	if not Engine.is_editor_hint():
		_build_collision()


func _material(texture: Texture2D, behind: Image, behind_only: bool) -> ShaderMaterial:
	var columns := _columns.duplicate()
	var rows := _rows.duplicate()
	columns.resize(MAX_CELLS)
	rows.resize(MAX_CELLS)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"kit", texture)
	m.set_shader_parameter(&"kit_cells", Vector2(int(kit_data()["cells"][0]), int(kit_data()["cells"][1])))
	m.set_shader_parameter(&"size", Vector2(_size))
	m.set_shader_parameter(&"cell", CELL)
	m.set_shader_parameter(&"col_map", columns)
	m.set_shader_parameter(&"row_map", rows)
	m.set_shader_parameter(&"behind_map", ImageTexture.create_from_image(behind))
	m.set_shader_parameter(&"behind_only", behind_only)
	m.set_shader_parameter(&"behind_frac", behind_depth / CELL)
	return m


func _build_collision() -> void:
	var old := get_node_or_null(^"Collision")
	if old != null:
		old.free()
	if not kit_data().has("labels"):
		return
	var body := StaticBody2D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for rect in CliffPiece.rects_for(label_at, _size, behind_depth):
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.get_center()
		body.add_child(shape)


func _draw() -> void:
	if _size != Vector2i.ZERO:
		draw_rect(Rect2(Vector2.ZERO, Vector2(_size) * CELL), Color.WHITE)


## Draws the cliff's rectangle again with the behind overlay's material.
class Drawer:
	extends Node2D
	var size := Vector2.ZERO

	func _draw() -> void:
		if size != Vector2.ZERO:
			draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
