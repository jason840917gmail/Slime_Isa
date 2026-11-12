@tool
extends "res://game/dungeon/drawbridge.gd"
class_name RopeBridge
## A rope bridge across the sky (docs/godot/SKY_FLOOR.md "Rope bridges"): the dungeon kit's drawbridge
## (drawbridge.gd) always down, so its deck is safe ground over the sky's void hazard and opens its
## passage over the elevation hole at its `level`, as a lowered drawbridge does. The slime cannot fall
## from it (owner, 2026-11-01):
##
## - its `railings` are solid: a wall on the world layer along each side of the lane, so nothing walks
##   or rolls off its sides;
## - its deck (`deck_rects`) reaches a unit past the lane each side, so the passage it opens (whole
##   cells: hazard_watch.gd) takes the row beside the lane too: a ledge push against a railing probes
##   ground there (Elevation.ledge_below) and never starts a drop;
## - a cap closes each of those side rows at both ends, on the rim's line, so nothing walks into them
##   from the islands.
##
## Place it as a drawbridge: the node at the hinge,
## the middle of the deck's end on the rim it leaves, `toward` the way it runs, `length` cells long
## (the sky cells it crosses), `width` the lane (one row: 64). Keep it after the SkyFloor in the tree.
##
## It draws the rope bridge along its deck, `overhang` past each end so the anchor posts stand on the
## rims: the art's two ends with its middle stretch repeated between them
## (asset/MAPS/sky/rope-bridge-<ew|ns>-*.webp, scripts/art/build-sky-art.py), upright whichever way it
## runs (east and west use the east-west art, north and south the north-south art).
##
## Owner: world (sky).

const ART := "res://asset/MAPS/sky/rope-bridge-%s.webp"
const PIECES := {true: ["ew-west", "ew-mid", "ew-east"], false: ["ns-north", "ns-mid", "ns-south"]}
const DIRECTIONS := {"south": Vector2.DOWN, "north": Vector2.UP, "east": Vector2.RIGHT, "west": Vector2.LEFT}
## The art is 128 px a cell: two pixels a unit.
const PX_PER_UNIT := 2.0
const PLANK := Color("#a8743e")
## The physics layer of walls (`world`, as wall_layer.gd and fences.gd use), and the railings' body.
const WORLD_LAYER := 1
const RAILINGS := "Railings"
const ROPE := Color("#d8b77a")

## How far past each end of the deck the bridge is drawn, onto the rims (world units).
@export_range(0.0, 96.0, 1.0) var overhang: float = 28.0:
	set(value):
		overhang = value
		queue_redraw()

## Solid railings along both sides of the lane (and the side rows' caps): nothing walks or drops off
## the bridge. Off: the lane's sides are rims, and a push drops off them into the sky.
@export var railings: bool = true
## How thick each railing's wall and cap is (world units), just outside the lane.
@export_range(2.0, 32.0, 1.0) var railing_width: float = 8.0

static var _pictures: Dictionary = {}


func _init() -> void:
	super()
	starts_lowered = true
	width = 64.0


func _ready() -> void:
	super()
	if railings and not Engine.is_editor_hint():
		_build_railings()


## Its deck: with railings, a unit wider than the lane each side, so the passage takes the rows beside
## the lane (see the class notes).
func deck_rects() -> Array[Rect2]:
	var rect: Rect2 = super()[0]
	if not railings:
		return [rect]
	if toward == "north" or toward == "south":
		return [rect.grow_individual(1.0, 0.0, 1.0, 0.0)]
	return [rect.grow_individual(0.0, 1.0, 0.0, 1.0)]


## A static body on the world layer (as a wall: every walker collides with it, and a ledge drop never
## crosses it): a railing along each side of the lane, the deck's whole length, and a cap across each
## side row at both ends, on the rims' lines; made at run time.
func _build_railings() -> void:
	var body := StaticBody2D.new()
	body.name = RAILINGS
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var run := float(length) * CELL
	# the deck runs down this node's +y from the hinge, `width` across (drawbridge.gd)
	for side: float in [-1.0, 1.0]:
		_add_box(body, Vector2(side * (width + railing_width) * 0.5, run * 0.5), Vector2(railing_width, run))
		for end: float in [0.0, run]:
			_add_box(body, Vector2(side * (width + CELL) * 0.5, end), Vector2(CELL, railing_width))
	add_child(body)


static func _add_box(body: StaticBody2D, centre: Vector2, size: Vector2) -> void:
	var box := RectangleShape2D.new()
	box.size = size
	var shape := CollisionShape2D.new()
	shape.shape = box
	shape.position = centre
	body.add_child(shape)


func _draw() -> void:
	var way: Vector2 = DIRECTIONS.get(toward, Vector2.DOWN)
	var horizontal := absf(way.x) > 0.5
	# drawn upright from the hinge, whatever way the node is turned
	draw_set_transform(Vector2.ZERO, -rotation)
	var ends := [-way * overhang, way * (float(length) * CELL + overhang)]
	var lo := minf(ends[0].x, ends[1].x) if horizontal else minf(ends[0].y, ends[1].y)
	var hi := maxf(ends[0].x, ends[1].x) if horizontal else maxf(ends[0].y, ends[1].y)
	var pieces: Array[Texture2D] = []
	for name: String in PIECES[horizontal]:
		pieces.append(_picture(ART % name))
	if pieces.has(null):
		_draw_plain(lo, hi, horizontal)
	else:
		_draw_pieces(pieces, lo, hi, horizontal)
	if Engine.is_editor_hint():
		var lane: Rect2 = deck_rects()[0]
		draw_rect(Rect2(lane.position - global_position, lane.size), EDITOR_EDGE, false, 2.0)
	draw_set_transform(Vector2.ZERO)


## The two ends at `lo` and `hi` (along the bridge, units from the hinge) and the middle stretch
## repeated between them, stretched a little to fit; squeezed ends on a bridge shorter than they are.
func _draw_pieces(pieces: Array[Texture2D], lo: float, hi: float, horizontal: bool) -> void:
	var across := _along(pieces[0], not horizontal) / PX_PER_UNIT
	var start := _along(pieces[0], horizontal) / PX_PER_UNIT
	var stretch_len := _along(pieces[1], horizontal) / PX_PER_UNIT
	var finish := _along(pieces[2], horizontal) / PX_PER_UNIT
	var span := hi - lo
	var squeeze := minf(1.0, span / maxf(1.0, start + finish))
	start *= squeeze
	finish *= squeeze
	var middle := span - start - finish
	var count := maxi(1, roundi(middle / stretch_len)) if middle > 1.0 else 0
	var each := middle / float(count) if count > 0 else 0.0
	_piece(pieces[0], lo, start, across, horizontal)
	var at := lo + start
	for i in count:
		_piece(pieces[1], at, each, across, horizontal)
		at += each
	_piece(pieces[2], hi - finish, finish, across, horizontal)


func _piece(picture: Texture2D, at: float, along: float, across: float, horizontal: bool) -> void:
	var rect := Rect2(at, -across * 0.5, along, across) if horizontal else Rect2(-across * 0.5, at, across, along)
	draw_texture_rect(picture, rect, false)


## Without the art: planks and two ropes.
func _draw_plain(lo: float, hi: float, horizontal: bool) -> void:
	var half := width * 0.5
	var deck := Rect2(lo, -half, hi - lo, width) if horizontal else Rect2(-half, lo, width, hi - lo)
	draw_rect(deck, PLANK)
	for side: float in [-half - 4.0, half + 4.0]:
		if horizontal:
			draw_line(Vector2(lo, side), Vector2(hi, side), ROPE, 3.0)
		else:
			draw_line(Vector2(side, lo), Vector2(side, hi), ROPE, 3.0)


static func _along(picture: Texture2D, horizontal: bool) -> float:
	return float(picture.get_width()) if horizontal else float(picture.get_height())


static func _picture(path: String) -> Texture2D:
	if not _pictures.has(path):
		_pictures[path] = SheetSprite.load_picture(path)
	return _pictures[path]
