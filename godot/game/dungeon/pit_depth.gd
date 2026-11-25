@tool
extends Node2D
class_name PitDepth
## The depth of a hole in a dungeon room (the rebuilt Crystal Mine's voids and shaft,
## docs/godot/DUNGEONS.md "The Crystal Mine rebuilt"): presentation only, drawn over the hole's
## floor and under the room's faces round it, in place of the void hazard's flat abyss (its
## `draw_look` off). Lay it over the hole's cells, `size` the hole's.
##
## - **Walls that go down into the dark:** the room's own faces (a cell round the hole) show whole;
##   from their foot the dark grows inward over `fade_px` to black, the far (north) wall seen a little
##   further down than the near one (`far_extra_px`), so the hole reads deeper than a step.
## - **Something that moves deep down:** dust motes drifting down from the rims and fading as they
##   sink (`dust`), and faint crystal glints twinkling in the dark (`glints`).
## - **Cables** (`cables`: x offsets from the node): ropes hanging from the far rim, swaying a little,
##   fading into the dark (a lift's or a bucket's).
## - **A painted hole** (`picture`, optional): a picture of the hole's inside (M4's shaft: timbered
##   walls going down into the dark) drawn inside the faces first (from the faces' inner edge,
##   `picture_margins`, cropped about its middle to fill it), the dark laid over it lighter
##   (`picture_dark`), the dust and glints over both, so a painted hole still has something moving.
##   Packed by tools/pack_pit_picture.gd (a texture resource: no import).
## Real time drives the motion (presentation only). Nothing here collides or catches: the hazard does.
##
## Owner: dungeon kit.

const DARK := Color(0.0, 0.0, 0.0)
## The dark's falloff: from the faces' foot (clear) to this share of the way in, this opaque; then on
## to black.
const MID_SHARE := 0.45
const MID_ALPHA := 0.78
const ROPE := Color("#3b2a1c")
const ROPE_SHINE := Color("#8a6a48")

## The hole's size (world units, from the node).
@export var size: Vector2 = Vector2(256.0, 256.0):
	set(value):
		size = value
		queue_redraw()
## The room's faces round the hole: how far in from its edge they show before the dark begins.
@export var wall_px: float = 64.0:
	set(value):
		wall_px = value
		queue_redraw()
## Over how much the dark grows from the faces' foot to black.
@export var fade_px: float = 150.0:
	set(value):
		fade_px = value
		queue_redraw()
## The far wall is seen this much further down than the others.
@export var far_extra_px: float = 36.0:
	set(value):
		far_extra_px = value
		queue_redraw()
## Dust motes drifting down.
@export var dust: int = 14
## Crystal glints twinkling deep down.
@export var glints: int = 7
@export var glint_color: Color = Color(0.62, 0.86, 1.0)
## Ropes hanging from the far rim: their x from the node.
@export var cables: PackedFloat32Array = PackedFloat32Array():
	set(value):
		cables = value
		queue_redraw()
## A painted picture of the hole's inside, drawn over the whole hole under the dark (optional).
@export var picture: Texture2D:
	set(value):
		picture = value
		queue_redraw()
## Where the picture begins inside the hole's edges (left, top, right, bottom): the faces' drawn width
## (a room's far face is a whole cell, its side and near faces about a third of one).
@export var picture_margins: Vector4 = Vector4(24.0, 60.0, 24.0, 24.0):
	set(value):
		picture_margins = value
		queue_redraw()
## Over a picture, the dark reaches only this opacity at its deepest (the picture has its own depth).
@export_range(0.0, 1.0) var picture_dark: float = 0.55:
	set(value):
		picture_dark = value
		queue_redraw()
## Where the motes and glints fall (the same every time for a hole).
@export var pattern_seed: int = 1

var _motes: Array[Vector4] = []
var _sparks: Array[Vector3] = []


func _ready() -> void:
	_scatter()
	set_process(not Engine.is_editor_hint())


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = pattern_seed
	_motes.clear()
	for i in dust:
		# x share, phase, period (s), size
		_motes.append(Vector4(rng.randf(), rng.randf(), rng.randf_range(5.0, 9.0), rng.randf_range(1.8, 3.2)))
	_sparks.clear()
	for i in glints:
		# x share, y share (deep: the middle), phase
		_sparks.append(Vector3(rng.randf_range(0.2, 0.8), rng.randf_range(0.4, 0.85), rng.randf()))


## The rect where the dark begins (the faces' foot), from the node.
func _inner() -> Rect2:
	return Rect2(Vector2(wall_px, wall_px + far_extra_px),
		Vector2(maxf(0.0, size.x - wall_px * 2.0), maxf(0.0, size.y - wall_px * 2.0 - far_extra_px)))


func _draw() -> void:
	var inner := _inner()
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var t := 0.0 if Engine.is_editor_hint() else float(Time.get_ticks_msec()) / 1000.0
	# the painted hole under everything; the dark over it only deepens it
	var deepest := 1.0
	if picture != null:
		_draw_picture(Rect2(Vector2(picture_margins.x, picture_margins.y),
			size - Vector2(picture_margins.x + picture_margins.z, picture_margins.y + picture_margins.w)))
		deepest = picture_dark
	# the ropes first: they hang from the far rim and sink into the dark drawn over them
	for x: float in cables:
		_draw_rope(x, t)
	# the dark, a smooth falloff inward from the faces' foot, then black
	var fade := minf(fade_px, minf(inner.size.x, inner.size.y) * 0.5 - 1.0)
	var mid := inner.grow(-fade * MID_SHARE)
	var core := inner.grow(-fade)
	_ring(inner, mid, 0.0, MID_ALPHA * deepest)
	_ring(mid, core, MID_ALPHA * deepest, deepest)
	if core.size.x > 0.0 and core.size.y > 0.0:
		draw_rect(core, Color(DARK, deepest))
	# dust drifting down, fading as it sinks
	for mote: Vector4 in _motes:
		var fall := fposmod(t / mote.z + mote.y, 1.0)
		var at := Vector2(inner.position.x + inner.size.x * mote.x + 6.0 * sin(t * 0.7 + mote.y * 9.0),
			inner.position.y + inner.size.y * fall * 0.9)
		draw_circle(at, mote.w, Color(0.82, 0.88, 0.97, 0.45 * (1.0 - fall)))
	# glints deep down
	for spark: Vector3 in _sparks:
		var phase := fposmod(t / 3.4 + spark.z, 1.0)
		var glow := clampf(1.0 - absf(phase - 0.5) * 6.0, 0.0, 1.0)
		if glow <= 0.0:
			continue
		var at := inner.position + inner.size * Vector2(spark.x, spark.y)
		var arm := 2.5 + 6.0 * glow
		var colour := Color(glint_color, 0.8 * glow)
		draw_line(at - Vector2(arm, 0.0), at + Vector2(arm, 0.0), colour, 1.6, true)
		draw_line(at - Vector2(0.0, arm), at + Vector2(0.0, arm), colour, 1.6, true)
		draw_circle(at, 1.2 + 1.4 * glow, colour)


## The picture over `rect`, cropped about its middle to `rect`'s shape (no stretching).
func _draw_picture(rect: Rect2) -> void:
	var tex := picture.get_size()
	var want := rect.size.x / rect.size.y
	var source := Rect2(Vector2.ZERO, tex)
	if tex.x / tex.y > want:
		source.size.x = tex.y * want
		source.position.x = (tex.x - source.size.x) * 0.5
	else:
		source.size.y = tex.x / want
		source.position.y = (tex.y - source.size.y) * 0.5
	draw_texture_rect_region(picture, rect, source)


## Between `outer` and `inner` (inside it) a band whose dark goes from `from_alpha` at its outer edge to
## `to_alpha` at its inner one, as four trapezoids.
func _ring(outer: Rect2, inner: Rect2, from_alpha: float, to_alpha: float) -> void:
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var a := Color(DARK, from_alpha)
	var b := Color(DARK, to_alpha)
	var o := [outer.position, Vector2(outer.end.x, outer.position.y), outer.end, Vector2(outer.position.x, outer.end.y)]
	var i := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	for k in 4:
		var n := (k + 1) % 4
		draw_polygon(PackedVector2Array([o[k], o[n], i[n], i[k]]), PackedColorArray([a, a, b, b]))


## A rope from the far rim straight down, swaying a little more the deeper it goes.
func _draw_rope(x: float, t: float) -> void:
	var length := size.y * 0.92
	var steps := 18
	var prev := Vector2(x, 0.0)
	for i in range(1, steps + 1):
		var share := float(i) / float(steps)
		var at := Vector2(x + 2.5 * share * sin(t * 0.9 + x * 0.05), length * share)
		draw_line(prev, at, ROPE, 3.0, true)
		draw_line(prev + Vector2(-0.8, 0.0), at + Vector2(-0.8, 0.0), Color(ROPE_SHINE, 0.6), 1.0, true)
		prev = at
