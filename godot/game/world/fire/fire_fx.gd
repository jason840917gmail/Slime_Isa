extends Node2D
## Small code-drawn fire effects (presentation only, real time; docs/godot/DARKNESS.md): a burst of
## embers where a flame lands, a smoke puff where it fizzles, and the soft additive glow texture the
## flame, the slime's ember and lit candles share. A burst frees itself when it is done.
##
## Owner: world (fire and darkness).

const Services := preload("res://game/shared/services.gd")

## What a burst draws.
enum Kind { EMBERS, SMOKE }

const EMBER_COLORS: Array[Color] = [Color(1.0, 0.86, 0.42), Color(1.0, 0.58, 0.16), Color(0.95, 0.33, 0.08)]
const SMOKE_COLOR := Color(0.32, 0.3, 0.3, 0.55)
const EMBER_MS := 420.0
const SMOKE_MS := 620.0
const EMBER_SPEED := Vector2(40.0, 110.0)
const EMBER_RISE := 60.0
const SMOKE_RISE := 26.0
const Z := 50

static var _glow_texture: GradientTexture2D

var _kind: Kind = Kind.EMBERS
var _started: float = 0.0
var _bits: Array[Dictionary] = []


## A burst of `count` embers at the global `at`, pushed along `back` (the way the flame came from).
static func embers(at: Vector2, count: int = 9, back: Vector2 = Vector2.ZERO) -> void:
	_spawn(Kind.EMBERS, at, count, back)


## A small smoke puff at the global `at` (a flame that fizzled).
static func smoke(at: Vector2, count: int = 5) -> void:
	_spawn(Kind.SMOKE, at, count, Vector2.ZERO)


## The soft round glow (white in the middle, nothing at the edge; tint it with modulate and use an
## additive material), 128 px.
static func glow_texture() -> GradientTexture2D:
	if _glow_texture != null:
		return _glow_texture
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	_glow_texture = texture
	return texture


## An additive material for glows.
static func additive() -> CanvasItemMaterial:
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return material


static func _spawn(kind: Kind, at: Vector2, count: int, back: Vector2) -> void:
	var world := Services.world()
	var parent: Node = world.entities_root() if world != null else null
	if parent == null:
		return
	var burst := (load("res://game/world/fire/fire_fx.gd") as GDScript).new() as Node2D
	burst.set(&"_kind", kind)
	parent.add_child(burst)
	burst.global_position = at
	burst.call(&"_setup", count, back)


func _setup(count: int, back: Vector2) -> void:
	z_index = Z
	z_as_relative = false
	_started = float(Time.get_ticks_msec())
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var angle := rng.randf() * TAU
		var away := Vector2(cos(angle), sin(angle))
		if back != Vector2.ZERO:
			away = (away + back.normalized() * 0.8).normalized()
		_bits.append({
			"velocity": away * rng.randf_range(EMBER_SPEED.x, EMBER_SPEED.y),
			"size": rng.randf_range(1.6, 3.4) if _kind == Kind.EMBERS else rng.randf_range(5.0, 9.0),
			"color": EMBER_COLORS[rng.randi() % EMBER_COLORS.size()],
			"offset": away * (2.0 if _kind == Kind.EMBERS else rng.randf_range(2.0, 8.0)),
		})


func _process(_delta: float) -> void:
	if float(Time.get_ticks_msec()) - _started > (EMBER_MS if _kind == Kind.EMBERS else SMOKE_MS):
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var age := float(Time.get_ticks_msec()) - _started
	if _kind == Kind.EMBERS:
		var t := clampf(age / EMBER_MS, 0.0, 1.0)
		var s := age / 1000.0
		for bit: Dictionary in _bits:
			var at: Vector2 = bit["offset"] + (bit["velocity"] as Vector2) * s * (1.0 - t * 0.5) \
				- Vector2(0.0, EMBER_RISE * s * s)
			var color: Color = bit["color"]
			color.a = 1.0 - t
			draw_circle(at, float(bit["size"]) * (1.0 - t * 0.6), color)
	else:
		var t := clampf(age / SMOKE_MS, 0.0, 1.0)
		for bit: Dictionary in _bits:
			var at: Vector2 = (bit["offset"] as Vector2) * (1.0 + t * 2.0) - Vector2(0.0, SMOKE_RISE * t)
			var color := SMOKE_COLOR
			color.a *= (1.0 - t) * minf(1.0, t * 6.0 + 0.3)
			draw_circle(at, float(bit["size"]) * (0.6 + t * 1.2), color)
