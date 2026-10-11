@tool
extends Node2D
## A cliff of any right-angled shape and several levels (docs/godot/CLIFFS.md "Cliff shapes"): paint
## the raised cells on the child TileMapLayer "paint" with the cliff paint tiles (levels 1 to 8,
## res://game/world/cliffs/cliff_paint_tileset.tres; any tile without a level counts as level 1)
## and the cliff is drawn from the kit paintings, in the editor too. The level is the ground's
## height in stone courses: under a south edge hangs a wall as many courses tall as the level drops
## (times `courses_per_level`), then its foot. Each wall takes its pieces from the painting of its
## height (h1, h2, h3 and taller), so stones and feet line up.
##
## How: per level, every cell gets a label (T top, W wall's top course, M middle courses, V bottom
## course, F foot, L low ground) and shows the kit cell whose 3 x 3 neighbourhood has the same
## labels (a middle course of a tall wall matches the kits' one middle course), preferring the one
## that continues its left or upper neighbour in the painting, so edges stay continuous.
## cliff_shape.gdshader draws each level and crossfades where neighbouring cells do not follow each
## other in the painting.
##
## Right angles only: the pieces come from the H paintings (square outer corners, inner corners on
## rims and walls). Rectangles painted on one layer join into one outline. Spots too tight for the
## paintings (a gap narrower than MIN_GAP cells, a top too close below a wall, a higher level too
## close to the lower level's edge) are listed as configuration warnings (the yellow sign in the
## Scene dock); a top right below a wall's foot keeps its border and the foot gives way.
##
## In the game: wall cells are solid (physics layer 1, world), and so is a RIM-thick strip inside a
## top's sides that face nothing (a top is not walked onto or off, as in Zelda). On a top's north
## side the strip sits `behind_depth` units in, and an overlay above the bodies draws that band of
## the top again, so a body walking along the north side of a cliff goes behind it.
##
## Owner: world (cliffs).

const SHADER := preload("res://game/world/cliffs/cliff_shape.gdshader")
const KIT_DIR := "res://asset/MAPS/cliffs/"
const CELL := 64.0
const PAINT := "paint"
const LEVEL_DATA := "elevation_level"
## Thickness of a top's solid border, in world units.
const RIM := 12.0
## z of the behind overlay relative to this node (the node sits at -1: the overlay at 1, above the
## y-sorted bodies at 0).
const OVERLAY_Z := 2
const DIRS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
		Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
## The wall height each kit is painted with (a wall prefers the kit of its height; 3 and taller use h3).
const KIT_HEIGHTS := {"h1": 1, "h2": 2, "h3": 3}
## Signature positions of DIRS (the centre is 4).
const SIG_INDEX: Array[int] = [0, 1, 2, 3, 5, 6, 7, 8]
const WALL := ["W", "M", "V"]
## Narrowest gap (cells) between two parts of one level, across or down, that the paintings show.
const MIN_GAP := 3
## Narrowest strip (cells) of a lower level beside a higher level's north, east or west edge.
const MIN_STEP := 2

## The kit paintings the pieces come from (godot/asset/MAPS/cliffs/kit-<name>.png, at most four):
## the H plateau painted with a two-course (h2), one-course (h1) and three-course (h3) wall; taller
## walls repeat h3's middle course. Each cell takes whichever painting has its neighbourhood.
@export var kits: PackedStringArray = ["h2", "h1", "h3"]:
	set(value):
		kits = value
		_kit = {}
		_queue()
## Stone courses (cells) per painted level: 1 means level 3 is a three-course wall.
@export_range(1, 4) var courses_per_level: int = 1:
	set(value):
		courses_per_level = value
		_queue()
## Another number picks other pieces of the painting where several fit.
@export var variation: int = 0:
	set(value):
		variation = value
		_queue()
## How far (world units) a body walks into a top from its north side, hidden behind it.
@export_range(0.0, 48.0) var behind_depth: float = 32.0:
	set(value):
		behind_depth = value
		_queue()

var _kit: Dictionary = {}
var _queued := false
## Per level, bottom first: {"labels": {cell: label}, "origin", "size", "map", "behind"}.
var levels: Array[Dictionary] = []
## The tight spots of the last build: {kind: [count, first cell]}.
var tight: Dictionary = {}


func _ready() -> void:
	var paint := get_node_or_null(PAINT) as TileMapLayer
	if paint != null:
		if Engine.is_editor_hint():
			paint.modulate = Color(1, 1, 1, 0.35)
			if not paint.changed.is_connected(_queue):
				paint.changed.connect(_queue)
		else:
			paint.visible = false
	_rebuild()


func _queue() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()


# --- the kits -------------------------------------------------------------------------------------

## The kits: per 3 x 3 signature (and per centre label) the kit cells that have it, as
## Vector3i(x, y, kit index); and each kit's label lookup, texture and size in cells.
func kit_data() -> Dictionary:
	if not _kit.is_empty():
		return _kit
	var by_signature := {}
	var by_center := {}
	var lookups: Array[Callable] = []
	var textures: Array[Texture2D] = []
	var sizes := PackedVector2Array()
	var heights := PackedInt32Array()
	for i in kits.size():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT_DIR + "kit-%s.json" % kits[i]))
		var texture := load(KIT_DIR + "kit-%s.png" % kits[i]) as Texture2D
		if not (parsed is Dictionary) or not (parsed as Dictionary).has("labels") or texture == null:
			push_warning("CliffShape: kit '%s' has no labels or picture" % kits[i])
			continue
		if textures.size() >= 4:
			push_warning("CliffShape: only four kits are drawn; '%s' is skipped" % kits[i])
			continue
		var labels: Array = parsed["labels"]
		var cells := Vector2i(labels[0].length(), labels.size())
		# 'X' marks a busy top cell (scripts/art/build-cliff-kit.py): never used as a piece, but a
		# top to its neighbours.
		var raw := func(c: Vector2i) -> String:
			return "L" if c.x < 0 or c.y < 0 or c.x >= cells.x or c.y >= cells.y else String(labels[c.y][c.x])
		var at := func(c: Vector2i) -> String:
			var ch: String = raw.call(c)
			return "T" if ch == "X" else ch
		var index := textures.size()
		lookups.append(at)
		textures.append(texture)
		sizes.append(Vector2(cells))
		heights.append(int(KIT_HEIGHTS.get(kits[i], 0)))
		for y in cells.y:
			for x in cells.x:
				if raw.call(Vector2i(x, y)) == "X":
					continue
				var sig := _signature(Vector2i(x, y), at)
				if sig == "LLLLLLLLL":
					continue
				var k := Vector3i(x, y, index)
				(by_signature.get_or_add(sig, []) as Array).append(k)
				(by_center.get_or_add(sig[4], []) as Array).append(k)
	if textures.is_empty():
		return {}
	_kit = {"heights": heights, "sizes": sizes, "lookups": lookups, "textures": textures, "by_signature": by_signature, "by_center": by_center}
	return _kit


static func _signature(c: Vector2i, at: Callable) -> String:
	var s := ""
	for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i.ZERO,
			Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
		s += at.call(c + d)
	return s


## The signature a shape cell is matched by: as painted, except that a middle course of a wall
## taller than three sees the course above it as the top course and the one below as the bottom
## course, as the kits' single middle course does (so tall walls keep their end stones).
static func _match_signature(c: Vector2i, at: Callable) -> String:
	var s := _signature(c, at)
	if s[4] != "M":
		return s
	var chars := s.split("")
	for i in 3:
		if chars[i] == "M":
			chars[i] = "W"
		if chars[6 + i] == "M":
			chars[6 + i] = "V"
	return "".join(chars)


# --- the shape -------------------------------------------------------------------------------------

## The painted level of every cell ({cell: level}, levels 1 and up).
func painted_levels() -> Dictionary:
	var out := {}
	var paint := get_node_or_null(PAINT) as TileMapLayer
	if paint == null or paint.tile_set == null:
		return out
	var has_levels := paint.tile_set.has_custom_data_layer_by_name(LEVEL_DATA)
	for c: Vector2i in paint.get_used_cells():
		var level := 1
		var data := paint.get_cell_tile_data(c)
		if has_levels and data != null:
			level = int(data.get_custom_data(LEVEL_DATA))
		if level >= 1:
			out[c] = level
	return out


## The labels of the ground at or above `level` ({cell: label}) and, for every wall and foot cell
## and the top cell above a wall, the wall's height in courses ({cell: height}). Under every south
## edge hangs a wall as tall as the ground drops there, then the foot.
func shape_labels(painted: Dictionary, level: int) -> Array[Dictionary]:
	var labels := {}
	var heights := {}
	for c: Vector2i in painted:
		if int(painted[c]) >= level:
			labels[c] = "T"
	for c: Vector2i in labels.keys():
		var below_level := int(painted.get(c + Vector2i.DOWN, 0))
		if below_level >= level:
			continue
		var rows := (level - below_level) * courses_per_level
		heights[c] = rows
		for k in rows + 1:
			var below := c + Vector2i(0, k + 1)
			if int(painted.get(below, 0)) >= level:
				break
			labels[below] = "F" if k == rows else ("W" if k == 0 else ("V" if k == rows - 1 else "M"))
			heights[below] = rows
	# A foot right above another top of this level: no painting has that, so the top keeps its
	# border (painted in the row above it) and the foot gives way.
	for c: Vector2i in labels.keys():
		if labels[c] == "F" and labels.get(c + Vector2i.DOWN, "L") == "T":
			labels.erase(c)
			heights.erase(c)
	return [labels, heights]


## The spots of the painting tighter than the paintings show ({kind: [count, first cell]}).
func tight_spots(painted: Dictionary) -> Dictionary:
	var found := {}
	var note := func(kind: String, c: Vector2i) -> void:
		var entry: Array = found.get_or_add(kind, [0, c])
		entry[0] = int(entry[0]) + 1
	var level_of := func(c: Vector2i) -> int: return int(painted.get(c, 0))
	for c: Vector2i in painted:
		var level: int = painted[c]
		# Gaps across: from this cell's east edge to the next cell of its level in the row.
		if level_of.call(c + Vector2i.RIGHT) < level:
			for k in range(2, MIN_GAP + 1):
				if level_of.call(c + Vector2i(k, 0)) >= level:
					note.call("gap narrower than %d cells across" % MIN_GAP, c + Vector2i.RIGHT)
					break
		# Gaps down: below a south edge the wall, its foot and a row for the next top's border.
		var below: int = level_of.call(c + Vector2i.DOWN)
		if below < level:
			var need := (level - below) * courses_per_level + 2
			for k in range(2, need + 1):
				if level_of.call(c + Vector2i(0, k)) >= level:
					note.call("top closer than %d rows below a wall" % need, c + Vector2i.DOWN)
					break
		# Gaps up: from a north edge to the cell of its level above (a notch from the north).
		if level_of.call(c + Vector2i.UP) < level:
			for k in range(2, MIN_GAP + 1):
				if level_of.call(c + Vector2i(0, -k)) >= level:
					note.call("gap narrower than %d cells down" % MIN_GAP, c + Vector2i.UP)
					break
		# A higher level's north, east or west edge needs MIN_STEP cells of the lower level beside it.
		if level >= 2:
			for d: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
				var lower: int = level_of.call(c + d)
				if lower >= 1 and lower < level:
					for k in range(2, MIN_STEP + 1):
						if level_of.call(c + d * k) < lower:
							note.call("lower level narrower than %d cells beside a higher level" % MIN_STEP, c + d)
							break
	return found


func _get_configuration_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	for kind: String in tight:
		var entry: Array = tight[kind]
		out.append("%s: %d cells, the first at %s. The paintings have no piece for it, so it will show a seam." % [kind, entry[0], entry[1]])
	return out


## Picks the kit cell of every cell of one level: {"origin", "size", "map": Image (r, g = kit cell,
## b = kit index), "behind": Image (r = 1 on a top cell whose north neighbour is not top)}.
func match_level(labels: Dictionary, heights: Dictionary, data: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var lo := Vector2i(1000000, 1000000)
	var hi := -lo
	for c: Vector2i in labels:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var origin := lo - Vector2i(2, 2)
	var size := hi - lo + Vector2i(5, 5)
	var at := func(c: Vector2i) -> String:
		return String(labels.get(c, "L"))
	var map := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	map.fill(Color(0, 0, 0, 0))
	var behind := Image.create_empty(size.x, size.y, false, Image.FORMAT_R8)
	behind.fill(Color(0, 0, 0))
	var chosen := {}
	var by_signature: Dictionary = data["by_signature"]
	var by_center: Dictionary = data["by_center"]
	var lookups: Array = data["lookups"]
	var kit_heights: PackedInt32Array = data["heights"]
	var none := Vector3i(-9, -9, -9)
	for y in size.y:
		for x in size.x:
			var c := origin + Vector2i(x, y)
			if at.call(c) == "T" and at.call(c + Vector2i.UP) != "T":
				behind.set_pixel(x, y, Color(1, 1, 1))
			var sig := _match_signature(c, at)
			if sig == "LLLLLLLLL":
				continue
			var candidates: Array = by_signature.get(sig, [])
			var exact := not candidates.is_empty()
			if not exact:
				candidates = by_center.get(sig[4], [])
			if candidates.is_empty():
				continue
			# A wall (its foot, the top above it) keeps to the painting of its height.
			if heights.has(c):
				var want := mini(int(heights[c]), 3)
				var own: Array = candidates.filter(func(k: Vector3i) -> bool: return kit_heights[k.z] == want)
				if not own.is_empty():
					candidates = own
			var best: Array[Vector3i] = []
			var best_score := -1000000
			for k: Vector3i in candidates:
				var score := 0
				if not exact:
					var kit_at: Callable = lookups[k.z]
					for i in DIRS.size():
						if kit_at.call(Vector2i(k.x, k.y) + DIRS[i]) == sig[SIG_INDEX[i]]:
							score += 2 if DIRS[i].x == 0 or DIRS[i].y == 0 else 1
				if chosen.get(c + Vector2i.LEFT, none) + Vector3i(1, 0, 0) == k:
					score += 3
				if chosen.get(c + Vector2i.UP, none) + Vector3i(0, 1, 0) == k:
					score += 3
				if score > best_score:
					best_score = score
					best = [k]
				elif score == best_score:
					best.append(k)
			var pick: Vector3i = best[rng.randi_range(0, best.size() - 1)]
			chosen[c] = pick
			map.set_pixel(x, y, Color8(pick.x, pick.y, pick.z, 255))
	return {"origin": origin, "size": size, "map": map, "behind": behind}


func _rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	var data := kit_data()
	var painted := painted_levels()
	levels.clear()
	tight = {}
	var top_level := 0
	for c: Vector2i in painted:
		top_level = maxi(top_level, int(painted[c]))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([kits, variation])
	var drawers: Array[Node] = []
	if not data.is_empty():
		var values := {}
		for c: Vector2i in painted:
			values[int(painted[c])] = true
		var sorted_levels: Array = values.keys()
		sorted_levels.sort()
		tight = tight_spots(painted)
		for level: int in sorted_levels:
			var shape := shape_labels(painted, level)
			var labels: Dictionary = shape[0]
			var built := match_level(labels, shape[1], data, rng)
			built["labels"] = labels
			levels.append(built)
			drawers.append(_drawer("Level%d" % level, built, data, false, 0))
			drawers.append(_drawer("Behind%d" % level, built, data, true, OVERLAY_Z))
	for child in get_children():
		if child.has_meta(&"cliff_drawer") and not drawers.has(child):
			child.queue_free()
	if Engine.is_editor_hint():
		update_configuration_warnings()
	else:
		_build_collision()


## The drawing node of one level (made at run time, never saved: no owner). Higher levels are
## added later, so they draw over the lower ones.
func _drawer(drawer_name: String, built: Dictionary, data: Dictionary, behind_only: bool, z: int) -> Node:
	var node := get_node_or_null(NodePath(drawer_name)) as CliffDrawer
	if node == null:
		node = CliffDrawer.new()
		node.name = drawer_name
		node.set_meta(&"cliff_drawer", true)
		add_child(node)
	node.z_index = z
	var shader_material := node.material as ShaderMaterial
	if shader_material == null:
		shader_material = ShaderMaterial.new()
		shader_material.shader = SHADER
		node.material = shader_material
	var textures: Array = data["textures"]
	for i in 4:
		shader_material.set_shader_parameter(StringName("kit%d" % i), textures[mini(i, textures.size() - 1)])
	var sizes: PackedVector2Array = (data["sizes"] as PackedVector2Array).duplicate()
	while sizes.size() < 4:
		sizes.append(sizes[0])
	shader_material.set_shader_parameter(&"kit_cells", sizes)
	shader_material.set_shader_parameter(&"cell_map", ImageTexture.create_from_image(built["map"]))
	shader_material.set_shader_parameter(&"behind_map", ImageTexture.create_from_image(built["behind"]))
	shader_material.set_shader_parameter(&"behind_only", behind_only)
	shader_material.set_shader_parameter(&"behind_frac", behind_depth / CELL)
	shader_material.set_shader_parameter(&"size", Vector2(built["size"]))
	shader_material.set_shader_parameter(&"cell", CELL)
	shader_material.set_shader_parameter(&"origin", Vector2(built["origin"]))
	node.rect = Rect2(Vector2(built["origin"]) * CELL, Vector2(built["size"]) * CELL)
	node.queue_redraw()
	return node


# --- collision -------------------------------------------------------------------------------------

## Solid wall cells and top rims of every level, on physics layer 1 (world). Made in the game only.
func _build_collision() -> void:
	var old := get_node_or_null(^"Collision")
	if old != null:
		old.free()
	var body := StaticBody2D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for built: Dictionary in levels:
		for rect in collision_rects(built["labels"]):
			var shape := CollisionShape2D.new()
			var box := RectangleShape2D.new()
			box.size = rect.size
			shape.shape = box
			shape.position = rect.get_center()
			body.add_child(shape)


## The solid rectangles of one level (world units, in this node's space).
func collision_rects(labels: Dictionary) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var is_top := func(c: Vector2i) -> bool: return labels.get(c, "L") == "T"
	var is_wall := func(c: Vector2i) -> bool: return WALL.has(labels.get(c, "L"))
	var open := func(c: Vector2i) -> bool: return not is_top.call(c) and not is_wall.call(c)
	var north := clampf(behind_depth, 0.0, CELL - RIM)
	for c: Vector2i in labels:
		var p := Vector2(c) * CELL
		if is_wall.call(c):
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
		# Inner corners: both sides top, the diagonal open.
		for d: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			if is_top.call(c + Vector2i(d.x, 0)) and is_top.call(c + Vector2i(0, d.y)) and open.call(c + d):
				var x := 0.0 if d.x < 0 else CELL - RIM
				var y := 0.0 if d.y < 0 else CELL - RIM
				rects.append(Rect2(p + Vector2(x, y), Vector2(RIM, RIM)))
	return rects


## Draws one level's rectangle with the shader.
class CliffDrawer:
	extends Node2D
	var rect := Rect2()

	func _draw() -> void:
		if rect.has_area():
			draw_rect(rect, Color.WHITE)
