extends Node2D
## What a throw's effect looks like on the enemy it stunned (throw-combat experiment,
## docs/godot/THROW_COMBAT.md): drawn on the enemy's body while the stun lasts, then gone.
## Presentation only: the stun itself is the reaction's (a long daze or stagger from the effect's hit
## class, game-constants.json `combat.weights.<weight>.classes.thrown-<effect>`).
##
## - **freeze**: an icy crust round the feet and frost shards at the sides;
## - **sleep**: z's rising over the head;
## - **stick**: an amber puddle under it with drips.
## One look per body: a new one replaces the old. It counts on the gameplay clock, so it waits with
## a hit-stop or a pause.
##
## Owner: throw combat (experiment).

const Services := preload("res://game/shared/services.gd")

const SELF_PATH := "res://game/throw/throw_status_look.gd"
const NODE_NAME := "ThrowStatusLook"
const FREEZE := "freeze"
const SLEEP := "sleep"
const STICK := "stick"
const ICE := Color(0.72, 0.9, 1.0, 0.55)
const ICE_EDGE := Color(0.9, 0.97, 1.0, 0.9)
const AMBER := Color(0.95, 0.68, 0.18, 0.6)
const AMBER_EDGE := Color(1.0, 0.82, 0.35, 0.9)
const Z_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const Z_OUTLINE := Color(0.1, 0.12, 0.25, 0.9)
const PUDDLE_SIZE := Vector2(26.0, 9.0)
const Z_FONT_SIZE := 15
const Z_RISE_PX := 26.0
const Z_CYCLE_MS := 1200.0
const Z_COUNT := 3
## The last share of the look fades out.
const FADE_SHARE := 0.2

var effect: String = ""
var _from_ms: float = 0.0
var _until_ms: float = 0.0
## The top of the enemy's art over its feet (px, negative).
var _head_y: float = -40.0


## Puts `effect`'s look on `receiver` (an enemy: its `get_body()` or itself) for `ms` of gameplay
## time. Nothing for an effect with no look or a receiver with no body.
static func attach(receiver: Object, look_effect: String, ms: float) -> void:
	if not [FREEZE, SLEEP, STICK].has(look_effect) or ms <= 0.0:
		return
	if receiver == null or not is_instance_valid(receiver):
		return
	var host: Node2D = null
	if receiver.has_method(&"get_body"):
		host = receiver.call(&"get_body") as Node2D
	if host == null and receiver is Node2D:
		host = receiver as Node2D
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	var old := host.get_node_or_null(NODE_NAME)
	if old != null:
		old.free()
	var look := (load(SELF_PATH) as GDScript).new() as Node2D
	look.name = NODE_NAME
	look.z_index = 3
	var now := Services.now_ms()
	var head := -40.0
	if receiver.has_method(&"get_centre"):
		var centre: Variant = receiver.call(&"get_centre")
		if centre is Vector2:
			head = minf(-24.0, ((centre as Vector2) - host.global_position).y * 2.0 - 6.0)
	look.call(&"setup", look_effect, now, now + ms, head)
	host.add_child(look)


func setup(look_effect: String, from_ms: float, until_ms: float, head_y: float) -> void:
	effect = look_effect
	_from_ms = from_ms
	_until_ms = until_ms
	_head_y = head_y


func _process(_delta: float) -> void:
	if Services.now_ms() >= _until_ms:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var now := Services.now_ms()
	var span := maxf(1.0, _until_ms - _from_ms)
	var left := (_until_ms - now) / span
	var alpha := clampf(left / FADE_SHARE, 0.0, 1.0)
	match effect:
		FREEZE:
			_draw_puddle(Color(ICE, ICE.a * alpha), Color(ICE_EDGE, ICE_EDGE.a * alpha))
			for side: float in [-1.0, 1.0]:
				var base := Vector2(side * PUDDLE_SIZE.x * 0.8, -4.0)
				var shard := PackedVector2Array([base + Vector2(-4.0, 0.0), base + Vector2(4.0, 0.0),
					base + Vector2(side * 3.0, -18.0)])
				draw_colored_polygon(shard, Color(ICE_EDGE, 0.8 * alpha))
		STICK:
			_draw_puddle(Color(AMBER, AMBER.a * alpha), Color(AMBER_EDGE, AMBER_EDGE.a * alpha))
			for i in 3:
				var x := (float(i) - 1.0) * 9.0
				var drip := fmod((now - _from_ms) / 600.0 + float(i) * 0.33, 1.0)
				draw_circle(Vector2(x, _head_y * 0.4 + drip * 10.0), 2.5, Color(AMBER_EDGE, alpha * (1.0 - drip)))
		SLEEP:
			var font := ThemeDB.fallback_font
			for i in Z_COUNT:
				var phase := fmod((now - _from_ms) / Z_CYCLE_MS + float(i) / Z_COUNT, 1.0)
				var at := Vector2(6.0 + phase * 10.0, _head_y - phase * Z_RISE_PX)
				var a := alpha * sin(phase * PI)
				var size := int(Z_FONT_SIZE * (0.7 + phase * 0.5))
				draw_string_outline(font, at, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(Z_OUTLINE, a))
				draw_string(font, at, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(Z_COLOR, a))


func _draw_puddle(fill: Color, edge: Color) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * i / 20.0
		points.append(Vector2(cos(angle) * PUDDLE_SIZE.x, sin(angle) * PUDDLE_SIZE.y))
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, edge, 1.5, true)
