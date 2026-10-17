extends Node2D
## Eyes that shine in the dark (the bestiary's Gloomling and Glint Bat, docs/godot/BESTIARY.md
## "Light and the Caverns' rows"): two small soft dots drawn over a dark room's darkness (absolute z
## Z, above the overlay's 45, game/world/darkness/dark_room.gd), so in a dark room only the eyes of a
## thing out of the light show. Outside a room that is still dark they hide (the art's own eyes show).
##
## A child of the enemy's Visual (so it follows its frame, flip and hit motion): `eyes` gives, per
## sheet frame, the two eyes' pixels in the 256 px cell; the Visual's own offset and scale place
## them. `strength` (0..1) dims them (a sleeping bat's eyes are slits; a fading Gloomling's go out).
## Presentation only.
##
## Owner: enemy builder.

## The dark rooms' group (game/world/darkness/dark_room.gd).
const DARK_ROOM_GROUP := &"dark_rooms"
## Above the darkness overlay (dark_room.gd OVERLAY_Z 45).
const Z := 46
const POINTS := 12

## Frame -> PackedVector2Array of eye pixels in the sheet cell (a frame not listed shows none).
var eyes: Dictionary = {}
var color: Color = Color(1.0, 0.85, 0.35)
## The eye's radius and its soft halo's, in world px.
var radius_px: float = 1.6
var halo_px: float = 4.0
var strength: float = 1.0:
	set(value):
		strength = clampf(value, 0.0, 1.0)
		queue_redraw()
## Squash of the dot (a slit: y < 1).
var squint: float = 1.0:
	set(value):
		squint = clampf(value, 0.1, 1.0)
		queue_redraw()

var _visual: Sprite2D
var _frame: int = -1
var _flip: bool = false
var _dark: bool = false


func _ready() -> void:
	z_as_relative = false
	z_index = Z
	_visual = get_parent() as Sprite2D


func _process(_delta: float) -> void:
	if _visual == null:
		return
	var dark := _in_dark_room(global_position)
	if dark != _dark or _visual.frame != _frame or _visual.flip_h != _flip:
		_dark = dark
		_frame = _visual.frame
		_flip = _visual.flip_h
		queue_redraw()


func _draw() -> void:
	if not _dark or strength <= 0.01 or _visual == null:
		return
	var points: Variant = eyes.get(_frame)
	if not (points is PackedVector2Array):
		return
	# The Visual's scale shrinks what is drawn here: undo it so the dots keep their world size.
	var back := 1.0 / maxf(0.001, absf(_visual.scale.x))
	var cell := float(_visual.texture.get_width()) / float(maxi(1, _visual.hframes)) if _visual.texture != null else 256.0
	for pixel: Vector2 in points as PackedVector2Array:
		var x := pixel.x if not _flip else cell - pixel.x
		var at := _visual.offset + Vector2(x, pixel.y)
		_dot(at, halo_px * back, Color(color, 0.22 * strength))
		_dot(at, radius_px * back, Color(color.lightened(0.35), 0.95 * strength))


func _dot(at: Vector2, r: float, tint: Color) -> void:
	var polygon := PackedVector2Array()
	for i in POINTS:
		var angle := TAU * float(i) / float(POINTS)
		polygon.append(at + Vector2(cos(angle) * r, sin(angle) * r * squint))
	draw_colored_polygon(polygon, tint)


func _in_dark_room(point: Vector2) -> bool:
	for room: Node in get_tree().get_nodes_in_group(DARK_ROOM_GROUP):
		if room.has_method(&"rect") and bool(room.call(&"is_dark")) and (room.call(&"rect") as Rect2).has_point(point):
			return true
	return false
