extends Node2D
## The electrocution look (the owner, 2026-11-22: "we need an electrocution animation that shows your
## bones"; the Jelly Bouncer's zap, docs/godot/BESTIARY.md "39. Jelly Bouncer"). For `ms` of gameplay
## time the body flickers, every FLICKER_MS, between:
## - the **X-ray**: its art darkened to a deep blue silhouette (`self_modulate`, so the hurt flash and
##   the fades, which use `modulate`, are untouched) with the cartoon skeleton glowing over it (one
##   picture for every body: `128x128-shock-skeleton.webp`, packed by
##   scripts/characters/pack-bestiary-enemies.py; a slime has no bones, the gag says otherwise);
## - its own look **lit** pale yellow.
## Little lightning sparks crackle round it the whole time. At the end the art's own tint comes back,
## a grey puff of smoke rises and `on_end` is called (the slime's kick away from what shocked it).
##
## One per body: a second shock on a body still shocked only makes it last longer. It is a child of
## the body, so it follows it; presentation only (the freeze itself is the caller's: the slime's
## `suppress_movement`, an enemy's daze).
##
## Owner: feel.

const Services := preload("res://game/shared/services.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
## Loaded through SheetSprite.load_picture (the imported texture, else the file: a picture packed
## while an editor holds the project shows before it is imported).
const SKELETON_PATH := "res://asset/MAPS/enemies/128x128-shock-skeleton.webp"
const NODE_NAME := "ShockLook"
## The skeleton's drawn size in its 128 px picture (the packer's fit: 88 x 124).
const SKELETON_ART := Vector2(88.0, 124.0)
## The skeleton's share of the body's box (it sits inside the body, not over its edge).
const SKELETON_FILL := 1.25
const FLICKER_MS := 70.0
const XRAY_TINT := Color(0.13, 0.2, 0.42)
const LIT_TINT := Color(1.45, 1.45, 1.05)
const SPARK_CORE := Color(1.0, 0.96, 0.55, 0.95)
const SPARK_GLOW := Color(0.55, 0.95, 1.0, 0.45)
const SPARKS := 3
const SPARK_SEGMENTS := 4
const SPARK_JAG := 0.35
const SPARK_WIDTH := 1.6
const SPARK_GLOW_WIDTH := 4.0
const SMOKE := &"dodge-dust"
const SMOKE_TINT := Color(0.42, 0.42, 0.46)
const SMOKE_SCALE := 0.8

var _art: CanvasItem
var _art_tint: Color = Color.WHITE
var _box: Rect2 = Rect2()
var _ends_at: float = 0.0
var _on_end: Callable = Callable()
var _skeleton: Sprite2D
var _rng := RandomNumberGenerator.new()
var _xray: bool = false


## Shocks the body `holder` (its root: the look follows it) for `ms`: `art` flickers, the skeleton fills
## `box` (in `holder`'s space: the body's middle and size). `on_end` is called when it is over (not when
## the body is gone first). Returns the look (an existing one on `holder`, made to last longer).
static func play(holder: Node2D, art: CanvasItem, box: Rect2, ms: float, on_end: Callable = Callable()) -> Node2D:
	if holder == null or not is_instance_valid(holder) or ms <= 0.0:
		return null
	var ends_at := Services.now_ms() + ms
	var existing := holder.get_node_or_null(NodePath(NODE_NAME))
	if existing != null and existing.has_method(&"extend"):
		existing.call(&"extend", ends_at, on_end)
		return existing as Node2D
	var look := new()
	look.name = NODE_NAME
	look._art = art
	look._art_tint = art.self_modulate if art != null else Color.WHITE
	look._box = box
	look._ends_at = ends_at
	look._on_end = on_end
	look.z_index = 2
	look._rng.randomize()
	holder.add_child(look)
	return look


## The box (in `holder`'s space) of `area`'s first shape: a body's hurtbox, its middle and size.
static func box_of(holder: Node2D, area: Area2D, fallback: Rect2) -> Rect2:
	if holder == null or area == null:
		return fallback
	for child in area.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.shape == null:
			continue
		var size := Vector2.ZERO
		var shape := shape_node.shape
		if shape is RectangleShape2D:
			size = (shape as RectangleShape2D).size
		elif shape is CircleShape2D:
			size = Vector2.ONE * (shape as CircleShape2D).radius * 2.0
		elif shape is CapsuleShape2D:
			size = Vector2((shape as CapsuleShape2D).radius * 2.0, (shape as CapsuleShape2D).height)
		if size == Vector2.ZERO:
			continue
		size *= shape_node.global_transform.get_scale().abs()
		var middle := holder.to_local(shape_node.global_position)
		return Rect2(middle - size * 0.5, size)
	return fallback


## A second shock while this one runs: it lasts until `ends_at` (the later), and the newer `on_end`.
func extend(ends_at: float, on_end: Callable) -> void:
	_ends_at = maxf(_ends_at, ends_at)
	if on_end.is_valid():
		_on_end = on_end


func _ready() -> void:
	_skeleton = Sprite2D.new()
	_skeleton.texture = SheetSprite.load_picture(SKELETON_PATH)
	var fit := minf(_box.size.x / SKELETON_ART.x, _box.size.y / SKELETON_ART.y) * SKELETON_FILL
	_skeleton.scale = Vector2.ONE * maxf(0.05, fit)
	_skeleton.position = _box.get_center()
	_skeleton.visible = false
	add_child(_skeleton)
	_flicker(Services.now_ms())


func _exit_tree() -> void:
	_restore()


func _physics_process(_delta: float) -> void:
	var now := Services.now_ms()
	if _art != null and not is_instance_valid(_art):
		_art = null
	if now >= _ends_at:
		_finish()
		return
	_flicker(now)
	queue_redraw()


func _flicker(now: float) -> void:
	_xray = int(now / FLICKER_MS) % 2 == 0
	_skeleton.visible = _xray
	if _art != null:
		_art.self_modulate = XRAY_TINT if _xray else LIT_TINT


## A few jagged sparks round the body, new ones every frame.
func _draw() -> void:
	var middle := _box.get_center()
	var reach := maxf(_box.size.x, _box.size.y) * 0.62
	for i in SPARKS:
		var angle := _rng.randf() * TAU
		var from := middle + Vector2.from_angle(angle) * reach * _rng.randf_range(0.35, 0.6)
		var to := middle + Vector2.from_angle(angle + _rng.randf_range(-0.5, 0.5)) * reach * _rng.randf_range(0.95, 1.25)
		var points := PackedVector2Array([from])
		for k in range(1, SPARK_SEGMENTS):
			var along := from.lerp(to, float(k) / float(SPARK_SEGMENTS))
			var side := (to - from).orthogonal().normalized() * (to - from).length() * SPARK_JAG * _rng.randf_range(-0.5, 0.5)
			points.append(along + side)
		points.append(to)
		draw_polyline(points, SPARK_GLOW, SPARK_GLOW_WIDTH, true)
		draw_polyline(points, SPARK_CORE, SPARK_WIDTH, true)


func _finish() -> void:
	_restore()
	var feel := Services.feel()
	var holder := get_parent() as Node2D
	if feel != null and holder != null:
		feel.burst(SMOKE, holder.to_global(_box.get_center()), Vector2.UP, SMOKE_TINT, SMOKE_SCALE)
	var callback := _on_end
	_on_end = Callable()
	queue_free()
	if callback.is_valid():
		callback.call()


func _restore() -> void:
	if _art != null and is_instance_valid(_art):
		_art.self_modulate = _art_tint
	_art = null
