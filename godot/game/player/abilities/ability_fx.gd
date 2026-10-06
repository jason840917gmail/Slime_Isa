extends Node2D
## One-off ability visuals (Phaser `LegacyPlayerAbilityPresentation.ts`: `spawnFlash`, the slam
## ring, the jump shadow, the landing goo dust, the lash tendril; abilities spec 5.3, 6.1, 7.3,
## 8.2). Each is a node in the world that tweens itself and frees itself; tweens pause with the
## tree (hit-stop), like Phaser's scene tweens.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")

## Drawn over entities ("reveal-effects" band).
const OVER_Z := 50
const KIND_CIRCLE := 0
const KIND_ELLIPSE := 1
const KIND_DOTS := 2

var kind: int = KIND_CIRCLE
var radius: float = 10.0
var ellipse_size: Vector2 = Vector2(40.0, 16.0)
var color: Color = Color.WHITE
## Goo dust: [{"velocity": Vector2, "life": float}] per particle.
var _dots: Array = []
var _dot_age: float = 0.0
var _dot_life: float = 0.32


func _draw() -> void:
	match kind:
		KIND_CIRCLE:
			draw_circle(Vector2.ZERO, radius, color)
		KIND_ELLIPSE:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(ellipse_size.x / ellipse_size.y, 1.0))
			draw_circle(Vector2.ZERO, ellipse_size.y / 2.0, color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		KIND_DOTS:
			var t := clampf(_dot_age / _dot_life, 0.0, 1.0)
			var scale_now := lerpf(0.3, 0.0, t)
			var alpha := lerpf(0.6, 0.0, t)
			for dot: Dictionary in _dots:
				var at: Vector2 = dot["velocity"] * _dot_age
				draw_circle(at, 7.0 * scale_now, Color(Color("#1a3a24"), alpha))
				draw_circle(at, 5.0 * scale_now, Color(Color("#7be08a"), alpha))
				draw_circle(at, 2.0 * scale_now, Color(1, 1, 1, 0.85 * alpha))


func _process(delta: float) -> void:
	if kind == KIND_DOTS:
		_dot_age += delta
		queue_redraw()


## `spawnFlash`: a circle r 10 at `at` that grows to r 60 and fades over 260 ms (Quad.Out).
static func flash(at: Vector2, tint: Color) -> Node2D:
	var node := _spawn(at, KIND_CIRCLE, Color(tint, 0.9))
	if node == null:
		return null
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector2(6.0, 6.0), 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(node, "modulate:a", 0.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(node.queue_free)
	return node


## The slam ring: r 10 #86f0c3 at 0.5 alpha growing to `ring_radius` and fading over 300 ms.
static func ring(at: Vector2, ring_radius: float) -> Node2D:
	var node := _spawn(at, KIND_CIRCLE, Color(Color("#86f0c3"), 0.5))
	if node == null:
		return null
	var grow := ring_radius / 10.0
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector2(grow, grow), 0.3)
	tween.parallel().tween_property(node, "modulate:a", 0.0, 0.3)
	tween.tween_callback(node.queue_free)
	return node


## The jump shadow: a 40 x 16 black ellipse at 0.35 alpha at `at`. The flight that owns it moves
## it along the ground under the slime, shrinks and fades it with height and frees it
## (jump_sequence.gd; Phaser's stayed at the start and tweened itself).
static func jump_shadow(at: Vector2) -> Node2D:
	return _spawn(at, KIND_ELLIPSE, Color(0, 0, 0, 0.35), false)


## The landing's 8 goo dots: speed 20-60 any direction, 320 ms, shrinking and fading.
static func goo_dust(at: Vector2) -> Node2D:
	var node := _spawn(at, KIND_DOTS, Color.WHITE)
	if node == null:
		return null
	for i in 8:
		var angle := randf() * TAU
		node._dots.append({"velocity": Vector2.from_angle(angle) * randf_range(20.0, 60.0)})
	var timer := node.create_tween()
	timer.tween_interval(0.4)
	timer.tween_callback(node.queue_free)
	return node


static func _spawn(at: Vector2, node_kind: int, tint: Color, over: bool = true) -> Node2D:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return null
	var node := preload("res://game/player/abilities/ability_fx.gd").new()
	node.name = "AbilityFx"
	node.kind = node_kind
	node.color = tint
	if over:
		node.z_index = OVER_Z
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	parent.add_child(node)
	node.global_position = at
	return node
