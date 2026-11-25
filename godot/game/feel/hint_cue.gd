extends Node2D
## A hint's pointer at the thing it is about (2026-11-24; the owner: "whenever possible hints need to
## flash the item or object involved", "an arrow ... many games do that"; docs/GAME_GUIDELINES.md
## "Hints"). Put it at the thing (global position: its middle, or a flame's place) and add it to the
## world: it flashes `flashes` times (a warm glow swelling and fading over the thing), then keeps a
## soft pulse, while an arrow bobs `arrow_rise` px above it pointing down at it; after `life_ms` it
## fades and frees itself. Drawn over a dark room's darkness (dark_room.gd's OVERLAY_Z is 45), so it
## shows in the dark. Presentation only, on real time.
##
## Owner: feel (hints).

const FireFx := preload("res://game/world/fire/fire_fx.gd")

const OVER_THE_DARK_Z := 46
## The flashes: each this long (rise, then fall), the glow's peak and resting strength, its size.
const FLASH_S := 0.42
const FLASH_RISE_SHARE := 0.35
const FLASH_PEAK := 0.95
const REST_GLOW := 0.3
const GLOW_SCALE := 1.1
## The arrow: its size (shaft width and length, head width and length), the bob's height and period,
## its colours (warm gold with the style guide's dark warm brown outline).
const SHAFT := Vector2(12.0, 16.0)
const HEAD := Vector2(30.0, 18.0)
const BOB_PX := 7.0
const BOB_S := 0.8
const ARROW_FILL := Color("#ffd277")
const ARROW_OUTLINE := Color("#3b2416")
const OUTLINE_PX := 3.0
const FADE_S := 0.4

## How many flashes, the glow's colour, how high over the thing the arrow's tip stands, how long it
## all lasts (ms).
var flashes := 3
var color := Color(1.0, 0.86, 0.55)
var arrow_rise := 70.0
var life_ms := 6000.0

var _age := 0.0
var _glow: Sprite2D


func _ready() -> void:
	z_index = OVER_THE_DARK_Z
	z_as_relative = false
	_glow = Sprite2D.new()
	_glow.texture = FireFx.glow_texture()
	_glow.material = FireFx.additive()
	_glow.modulate = Color(color, 0.0)
	_glow.scale = Vector2.ONE * GLOW_SCALE
	add_child(_glow)


func _process(delta: float) -> void:
	_age += delta
	var life_s := life_ms / 1000.0
	if _age >= life_s + FADE_S:
		queue_free()
		return
	var fade := clampf((life_s + FADE_S - _age) / FADE_S, 0.0, 1.0)
	var strength := REST_GLOW * (0.75 + 0.25 * sin(_age * TAU / BOB_S))
	var flashing := _age < FLASH_S * float(flashes)
	if flashing:
		var t := fmod(_age, FLASH_S) / FLASH_S
		strength = t / FLASH_RISE_SHARE if t < FLASH_RISE_SHARE else 1.0 - (t - FLASH_RISE_SHARE) / (1.0 - FLASH_RISE_SHARE)
		strength = lerpf(0.1, FLASH_PEAK, strength)
	_glow.modulate = Color(color, strength * fade)
	_glow.scale = Vector2.ONE * GLOW_SCALE * (1.0 + 0.25 * strength)
	modulate.a = fade
	queue_redraw()


func _draw() -> void:
	var tip := Vector2(0.0, -arrow_rise + BOB_PX * sin(_age * TAU / BOB_S))
	var points := PackedVector2Array([
		tip,
		tip + Vector2(HEAD.x * 0.5, -HEAD.y),
		tip + Vector2(SHAFT.x * 0.5, -HEAD.y),
		tip + Vector2(SHAFT.x * 0.5, -HEAD.y - SHAFT.y),
		tip + Vector2(-SHAFT.x * 0.5, -HEAD.y - SHAFT.y),
		tip + Vector2(-SHAFT.x * 0.5, -HEAD.y),
		tip + Vector2(-HEAD.x * 0.5, -HEAD.y),
	])
	draw_colored_polygon(points, ARROW_FILL)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, ARROW_OUTLINE, OUTLINE_PX, true)
