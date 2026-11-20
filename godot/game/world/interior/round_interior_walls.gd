@tool
class_name RoundInteriorWalls
extends Node2D
## A round or oval room's walls (docs/godot/INTERIOR_WALLS.md "Round rooms"; owner, 2026-11-19: the
## round houses, the mushrooms, the snail shell): the bevelled frame of an InteriorWallLayer bent
## round an ellipse. The node stands at the room's middle; `radii` is the outer edge's half size and
## `depth` the faces' depth (two cells, as the square rooms'). The faces are the style's north run
## wrapped round the ring, its top (the wall's top) outward, so every part of the wall is the north
## face turned, as every face and opening of the square rooms is; the light follows the style's four
## faces round the ring. Beyond the ring is the dark (`void_extent` out), the floor inside is the
## room's ground layer.
##
## Openings are RoundWallOpening children dragged onto the ring (each two cells along): a doorway, a
## cracked stretch, a blown hole, a closed house door. Their fronts (the frame round the passage)
## draw over the bodies in the passage, as the square rooms' do. In the game the ring is solid but
## for its openings' passages, and an opening with a target is a door to it. A Goo Bomb blowing a
## `cracked-wall` (`frame_drawn_by_wall` on) by a cracked opening turns it into a blown hole
## (`change_opening_at`).
##
## Nothing the ring draws is saved: the scene keeps the node, its settings and its openings.
##
## Owner: world (interior walls).

const Services := preload("res://game/shared/services.gd")
const InteriorWalls := preload("res://game/world/interior/interior_wall_layer.gd")
const DoorScriptType := preload("res://game/scripts/door.gd")
const OpeningType := preload("res://game/world/interior/round_wall_opening.gd")

const GROUP := &"round_interior_walls"
## Sheet pixels per world unit (the styles' sheets are drawn at half size).
const DENSITY := 2.0
const CELL := 64.0
## The pieces' size along the wall and across it (sheet px): a run cell, a two-cell opening.
const RUN_PX := Vector2(128.0, 256.0)
const OPENING_PX := 256.0
## How finely the ring is cut: steps per cell along it, and the samples of the arc-length table.
const STEPS_PER_CELL := 4
const ARC_SAMPLES := 720
## The dark beyond the walls (InteriorWallLayer's fill).
const VOID := Color("#0d0a0f")
## How far (units) from a cracked opening's middle a blast still opens it (InteriorWallLayer's).
const BLAST_REACH := CELL * 3.0
## Where the door to a target stands: this share of the depth in from the outer edge (the square
## rooms' door nodes stand 24 units in from the outer edge of a 128-deep rim).
const DOOR_DEPTH_SHARE := 0.19
## A solid band beyond the outer edge, so nothing walks out through an opening into the dark.
const CAP_UNITS := 48.0

@export var style: String = "cottage":
	set(value):
		style = value
		queue_rebuild()
## The outer edge's half width and half height (world units).
@export var radii: Vector2 = Vector2(448.0, 352.0):
	set(value):
		radii = Vector2(maxf(value.x, depth + CELL), maxf(value.y, depth + CELL))
		queue_rebuild()
## The faces' depth from the outer edge to the floor's (world units).
@export var depth: float = 128.0:
	set(value):
		depth = maxf(value, 16.0)
		queue_rebuild()
## How far the dark reaches past the outer edge (world units): past the room scene's edge.
@export var void_extent: float = 1024.0:
	set(value):
		void_extent = value
		queue_rebuild()

var _queued := false
## Arc-length table of the ellipse half way through the wall: _arc[i] is the length from t = -PI/2
## (the top) to the i-th sample.
var _arc: PackedFloat32Array = PackedFloat32Array()
var _walls: Node2D
var _fronts: Node2D
var _body: StaticBody2D
## The openings as laid out: [{node, kind, t0, t1, t (middle), side}].
var _laid: Array[Dictionary] = []
static var _gains: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	y_sort_enabled = true
	_rebuild()


func queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()


# --- the ring's geometry -------------------------------------------------------------------------

## The point of the wall at ellipse angle `t`, `share` of the depth in from the outer edge (local).
func point(t: float, share: float) -> Vector2:
	var outer := Vector2(radii.x * cos(t), radii.y * sin(t))
	var inner := Vector2((radii.x - depth) * cos(t), (radii.y - depth) * sin(t))
	return outer.lerp(inner, share)


## The outward normal of the ring at `t` (local, unit).
func normal(t: float) -> Vector2:
	return Vector2(cos(t) / radii.x, sin(t) / radii.y).normalized()


func _mid() -> Vector2:
	return radii - Vector2(depth, depth) * 0.5


func _build_arc() -> void:
	_arc = PackedFloat32Array()
	_arc.resize(ARC_SAMPLES + 1)
	var mid := _mid()
	var length := 0.0
	var last := Vector2(mid.x * cos(-PI * 0.5), mid.y * sin(-PI * 0.5))
	_arc[0] = 0.0
	for i in range(1, ARC_SAMPLES + 1):
		var t := -PI * 0.5 + TAU * float(i) / ARC_SAMPLES
		var at := Vector2(mid.x * cos(t), mid.y * sin(t))
		length += at.distance_to(last)
		_arc[i] = length
		last = at


func _length() -> float:
	return _arc[ARC_SAMPLES]


## The ellipse angle at arc length `s` from the top (wrapped round the ring).
func _t_at(s: float) -> float:
	var total := _length()
	var turns := floorf(s / total)
	s -= turns * total
	var lo := 0
	var hi := ARC_SAMPLES
	while hi - lo > 1:
		var m := (lo + hi) / 2
		if _arc[m] <= s:
			lo = m
		else:
			hi = m
	var span := _arc[hi] - _arc[lo]
	var f := (s - _arc[lo]) / span if span > 0.0 else 0.0
	return -PI * 0.5 + TAU * (float(lo) + f) / ARC_SAMPLES + turns * TAU


## The arc length from the top to ellipse angle `t`.
func _s_at(t: float) -> float:
	var u := fposmod(t + PI * 0.5, TAU) / TAU * ARC_SAMPLES
	var i := mini(int(u), ARC_SAMPLES - 1)
	return lerpf(_arc[i], _arc[i + 1], u - float(i))


## The ellipse angle of the wall point nearest the direction of `local`.
func _t_toward(local: Vector2) -> float:
	var mid := _mid()
	return atan2(local.y / mid.y, local.x / mid.x)


static func _side_of(n: Vector2) -> String:
	if absf(n.x) > absf(n.y):
		return "east" if n.x > 0.0 else "west"
	return "south" if n.y > 0.0 else "north"


# --- building ------------------------------------------------------------------------------------

func _rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	_build_arc()
	var entry: Dictionary = InteriorWalls.table().get(style, {})
	for node: Node in [_walls, _fronts, _body]:
		if node != null and is_instance_valid(node):
			node.free()
	_walls = null
	_fronts = null
	_body = null
	_lay_openings(entry)
	if entry.is_empty():
		push_warning("RoundInteriorWalls: no interior wall style %s" % style)
		return
	_walls = Node2D.new()
	_walls.name = "Walls"
	# under every body, as the square rooms' faces: a face's foot is walked over
	_walls.z_index = -1
	_walls.z_as_relative = false
	add_child(_walls)
	_walls.draw.connect(_draw_walls.bind(_walls, entry))
	_fronts = Node2D.new()
	_fronts.name = "Fronts"
	_fronts.y_sort_enabled = true
	add_child(_fronts)
	for opening in _laid:
		if str(opening["kind"]) != "cracked":
			_add_front(opening, entry)
	if not Engine.is_editor_hint():
		_build_collision()
		_make_doors(entry)


## Places each RoundWallOpening on the ring: its middle at the wall point toward it (a door: the
## nearest of the four ends of the ring's axes), two cells along.
func _lay_openings(_entry: Dictionary) -> void:
	_laid.clear()
	for child: Node in get_children():
		var opening := child as OpeningType
		if opening == null:
			continue
		var t := _t_toward(opening.position)
		if opening.kind == "door":
			t = roundf(t / (PI * 0.5)) * PI * 0.5
		var s := _s_at(t)
		_laid.append({"node": opening, "kind": opening.kind, "t": t, "t0": _t_at(s - CELL), "t1": _t_at(s + CELL),
				"side": _side_of(normal(t))})


func _draw_walls(canvas: Node2D, entry: Dictionary) -> void:
	var texture := InteriorWalls.picture(str(entry["texture"]))
	if texture == null:
		return
	var size := texture.get_size()
	var pieces: Dictionary = entry.get("pieces", {})
	var period := int((entry.get("run_period", {}) as Dictionary).get("n", 2))
	var gains := _side_gains(entry, texture)
	# the dark beyond the outer edge
	var far := maxf(radii.x, radii.y) + void_extent
	var steps := 128
	for i in steps:
		var a := TAU * float(i) / steps
		var b := TAU * float(i + 1) / steps
		canvas.draw_colored_polygon(PackedVector2Array([point(a, 0.0), point(b, 0.0),
				Vector2(cos(b), sin(b)) * far * 1.5, Vector2(cos(a), sin(a)) * far * 1.5]), VOID)
	# the faces: the north run round the ring, a whole number of its loops
	var loops := maxi(1, roundi(_length() / (CELL * period)))
	var cells := loops * period
	var cell_length := _length() / cells
	for k in cells:
		var rect: Array = pieces.get("n%d" % (k % period), [])
		if rect.is_empty():
			continue
		var region := Rect2(rect[0], rect[1], rect[2], rect[3])
		var s0 := k * cell_length
		_warp(canvas, texture, size, region, _t_at(s0), _t_at(s0 + cell_length), 0.0, 1.0, STEPS_PER_CELL, gains)
	# the openings over the faces (their ends fade into the run under them)
	for opening in _laid:
		var draw_kind := "doorway" if str(opening["kind"]) == "door" else str(opening["kind"])
		var rect: Array = pieces.get("n_" + draw_kind, [])
		if rect.is_empty():
			continue
		_warp(canvas, texture, size, Rect2(rect[0], rect[1], rect[2], rect[3]), opening["t0"], opening["t1"],
				0.0, 1.0, STEPS_PER_CELL * 2, gains)


## Draws the sheet's `region` bent onto the ring between angles t0 (its left edge) and t1 (its right),
## its top at depth share d0 and its bottom at d1, in `steps` slices, each vertex lit by its side.
func _warp(canvas: Node2D, texture: Texture2D, size: Vector2, region: Rect2, t0: float, t1: float, d0: float,
		d1: float, steps: int, gains: Dictionary) -> void:
	for i in steps:
		var fa := float(i) / steps
		var fb := float(i + 1) / steps
		var ta := lerpf(t0, t1, fa)
		var tb := lerpf(t0, t1, fb)
		var points := PackedVector2Array([point(ta, d0), point(tb, d0), point(tb, d1), point(ta, d1)])
		var x0 := region.position.x + region.size.x * fa
		var x1 := region.position.x + region.size.x * fb
		var uvs := PackedVector2Array([Vector2(x0, region.position.y) / size, Vector2(x1, region.position.y) / size,
				Vector2(x1, region.end.y) / size, Vector2(x0, region.end.y) / size])
		var ca := _light(gains, normal(ta))
		var cb := _light(gains, normal(tb))
		canvas.draw_polygon(points, PackedColorArray([ca, cb, cb, ca]), uvs, texture)


## The light of a face whose outward normal is `n`: the style's four faces' light (their runs' mean
## colour over the north run's), mixed by how much the face looks each way.
static func _light(gains: Dictionary, n: Vector2) -> Color:
	if gains.is_empty():
		return Color.WHITE
	var weights := {"n": maxf(0.0, -n.y), "s": maxf(0.0, n.y), "w": maxf(0.0, -n.x), "e": maxf(0.0, n.x)}
	var sum := Color(0.0, 0.0, 0.0, 0.0)
	var total := 0.0
	for side: String in weights:
		var w: float = weights[side]
		sum += (gains[side] as Color) * w
		total += w
	if total <= 0.0:
		return Color.WHITE
	var c := sum / total
	return Color(c.r, c.g, c.b, 1.0)


## Each side's light relative to the north face's (its first run piece's mean colour), read once per
## style from the sheet; empty when the sheet cannot be read.
func _side_gains(entry: Dictionary, texture: Texture2D) -> Dictionary:
	if _gains.has(style):
		return _gains[style]
	var out := {}
	var image := texture.get_image()
	if image != null:
		if image.is_compressed():
			image.decompress()
		var means := {}
		for side: String in ["n", "s", "w", "e"]:
			var rect: Array = (entry["pieces"] as Dictionary).get(side + "0", [])
			if rect.is_empty():
				means = {}
				break
			means[side] = _mean(image, Rect2i(rect[0], rect[1], rect[2], rect[3]))
		if not means.is_empty():
			var north: Color = means["n"]
			for side: String in means:
				var c: Color = means[side]
				out[side] = Color(c.r / maxf(north.r, 0.01), c.g / maxf(north.g, 0.01), c.b / maxf(north.b, 0.01), 1.0)
	_gains[style] = out
	return out


static func _mean(image: Image, rect: Rect2i) -> Color:
	var sum := Color(0.0, 0.0, 0.0, 0.0)
	var count := 0
	for y in range(rect.position.y, rect.end.y, 8):
		for x in range(rect.position.x, rect.end.x, 8):
			var c := image.get_pixel(x, y)
			if c.a > 0.8:
				sum += c
				count += 1
	return sum / maxf(1.0, float(count))


## An opening's front (the frame without its passage) over the bodies in the passage: a node at the
## opening's lowest point, so a body above it (in the passage) draws under it.
func _add_front(opening: Dictionary, entry: Dictionary) -> void:
	var draw_kind := "doorway" if str(opening["kind"]) == "door" else str(opening["kind"])
	var rect: Array = (entry.get("pieces", {}) as Dictionary).get("n_%s_front" % draw_kind, [])
	if rect.is_empty():
		return
	var lowest := -INF
	for f in [0.0, 1.0]:
		for t in [opening["t0"], opening["t"], opening["t1"]]:
			lowest = maxf(lowest, point(t, f).y)
	var front := Node2D.new()
	front.name = "Front"
	front.position = Vector2(0.0, lowest)
	_fronts.add_child(front)
	var region := Rect2(rect[0], rect[1], rect[2], rect[3])
	front.draw.connect(func() -> void:
		var texture := InteriorWalls.picture(str(entry["texture"]))
		if texture == null:
			return
		front.draw_set_transform(Vector2(0.0, -lowest))
		_warp(front, texture, texture.get_size(), region, opening["t0"], opening["t1"], 0.0, 1.0, STEPS_PER_CELL * 2,
				_side_gains(entry, texture)))
	# a door's closed leaf: the style's leaf for the side it faces, square to it (doors stand at the
	# ends of the ring's axes), its picture the door the game swings open
	if str(opening["kind"]) == "door":
		var leaf := _leaf_sprite(opening, entry)
		if leaf != null:
			_fronts.add_child(leaf)
			opening["leaf"] = leaf


## The closed door's leaf for `opening` (kind "door"): the style's `<side>_door` leaf, centred where
## it sits in the opening, unturned (the sheet's side leaf is already turned); null without one.
func _leaf_sprite(opening: Dictionary, entry: Dictionary) -> Sprite2D:
	var side := str(opening["side"]).left(1)
	var leaf: Dictionary = (entry.get("leaves", {}) as Dictionary).get(side + "_door", {})
	if leaf.is_empty():
		return null
	var region: Array = leaf["region"]
	var inside: Array = leaf["in_opening"]
	var sprite := Sprite2D.new()
	sprite.name = "Leaf"
	sprite.texture = InteriorWalls.picture(str(entry["texture"]))
	sprite.region_enabled = true
	sprite.region_rect = Rect2(region[0], region[1], region[2], region[3])
	sprite.scale = Vector2.ONE / DENSITY
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# the leaf's middle from the opening piece's middle (sheet px, the side piece upright)
	var offset := (Vector2(inside[0], inside[1]) + Vector2(region[2], region[3]) * 0.5 - Vector2.ONE * OPENING_PX * 0.5) / DENSITY
	sprite.position = point(opening["t"], 0.5) + offset
	return sprite


## The opening's passage share along it (the leaf's span in its piece: the style's door leaf, else
## its first leaf), (0.25, 0.75) without one.
static func _passage_share(entry: Dictionary) -> Vector2:
	var leaves: Dictionary = entry.get("leaves", {})
	var leaf: Dictionary = leaves.get("n_door", {})
	if leaf.is_empty():
		for key: String in leaves:
			if key.begins_with("n_"):
				leaf = leaves[key]
				break
	if leaf.is_empty():
		return Vector2(0.25, 0.75)
	var x0 := float((leaf["in_opening"] as Array)[0])
	var w := float((leaf["region"] as Array)[2])
	return Vector2(x0 / OPENING_PX, (x0 + w) / OPENING_PX)


func _build_collision() -> void:
	_body = StaticBody2D.new()
	_body.name = "Collision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	var entry: Dictionary = InteriorWalls.table().get(style, {})
	var share := _passage_share(entry)
	# the open stretches (ellipse angles), unwrapped near each opening's middle
	var open: Array[Vector2] = []
	for opening in _laid:
		if str(opening["kind"]) == "cracked":
			continue
		var t0: float = opening["t0"]
		var t1: float = opening["t1"]
		open.append(Vector2(lerpf(t0, t1, share.x), lerpf(t0, t1, share.y)))
	var steps := maxi(32, roundi(_length() / (CELL * 0.5)))
	for i in steps:
		var a := -PI * 0.5 + TAU * float(i) / steps
		var b := -PI * 0.5 + TAU * float(i + 1) / steps
		var cap := PackedVector2Array([point(a, 0.0), point(b, 0.0),
				point(b, 0.0) + normal(b) * CAP_UNITS, point(a, 0.0) + normal(a) * CAP_UNITS])
		_add_polygon(cap)
		var mid := (a + b) * 0.5
		var is_open := false
		for span in open:
			var d := wrapf(mid - (span.x + span.y) * 0.5, -PI, PI)
			if absf(d) < absf(span.y - span.x) * 0.5:
				is_open = true
				break
		if not is_open:
			_add_polygon(PackedVector2Array([point(a, 0.0), point(b, 0.0), point(b, 1.0), point(a, 1.0)]))


func _add_polygon(points: PackedVector2Array) -> void:
	var shape := CollisionPolygon2D.new()
	shape.polygon = points
	_body.add_child(shape)


## The doors of the openings with a target (game only): a door node at the opening (this share of the
## depth in from the outer edge), its DoorScript a door with the leaf (kind "door") or an opening,
## `side` the way it faces.
func _make_doors(entry: Dictionary) -> void:
	var share := _passage_share(entry)
	for opening in _laid:
		var node := opening["node"] as OpeningType
		if node.target_area_id.is_empty() or str(opening["kind"]) == "cracked":
			continue
		var holder := Node2D.new()
		holder.name = "Door-" + str(node.name)
		holder.position = point(opening["t"], DOOR_DEPTH_SHARE)
		_fronts.add_child(holder)
		var door := DoorScriptType.new()
		door.name = "DoorScript"
		door.door_id = node.door_id
		door.target_area_id = node.target_area_id
		door.target_door_id = node.target_door_id
		door.side = str(opening["side"])
		door.kind = "door" if str(opening["kind"]) == "door" else "opening"
		var t0: float = opening["t0"]
		var t1: float = opening["t1"]
		var width := point(lerpf(t0, t1, share.x), 0.5).distance_to(point(lerpf(t0, t1, share.y), 0.5))
		door.trigger_rect = Rect2(-width * 0.5, -24.0, width, 48.0) if door.side in ["north", "south"] \
				else Rect2(-24.0, -width * 0.5, 48.0, width)
		var leaf := opening.get("leaf") as Sprite2D
		if leaf != null:
			door.house_art = leaf
			var leaf_size := leaf.region_rect.size / DENSITY
			door.door_rect = Rect2(leaf.position - leaf_size * 0.5 - holder.position, leaf_size)
		var world := Services.world()
		if world != null:
			door.map_id = world.map_id()
		holder.add_child(door)


## A Goo Bomb blew a cracked wall at `point` (global): every cracked opening within BLAST_REACH of it
## becomes a blown hole, and the ring is built again. True when one did.
func change_opening_at(at: Vector2, kind: String) -> bool:
	if kind != "blown":
		return false
	var local := to_local(at)
	var changed_any := false
	for opening in _laid:
		if str(opening["kind"]) != "cracked":
			continue
		var middle := point(opening["t"], 0.5)
		if middle.distance_to(local) <= BLAST_REACH:
			(opening["node"] as OpeningType).blow()
			changed_any = true
	if changed_any:
		_rebuild()
	return changed_any
