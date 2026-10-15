extends Node2D
## The energy shard's look (owner, 2026-10-11: enemies may drop an energy shard on death;
## BODY_SHAPES.md "Data" `combat.energyShard`): the painted honey-gold crystal (energy-shard.webp,
## body-shapes art of 2026-10-12; SHARD_HEIGHT_PX tall) that pops out of the corpse, then floats over
## a soft shadow until the slime touches it, with its ambient animation (docs/assets/
## AMBIENT_ANIMATION.md: a thing that glows moves): a gentle bob, and a soft glow behind it that
## swells and brightens with the crystal, both started at a random moment so two shards never move in
## sync. It blinks while it is about to fade (`blink`). Presentation only: the pickup is
## game/combat/reactions/energy_shard.gd. Real time; it pauses with the tree.
##
## Owner: reactions.

## Look (presentation).
const SHARD_TEXTURE := preload("res://asset/MAPS/effects/energy-shard.webp")
## The crystal's height on screen (its width follows the art), drawn with mipmaps where the import
## makes them (linear otherwise).
const SHARD_HEIGHT_PX := 24.0
const TEXTURE_FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
const FLOAT_PX := 12.0
const BOB_PX := 2.5
const BOB_PERIOD_S := 1.4
## The glow: a soft round halo (GLOW_RADIUS_PX, in GLOW over its middle fading to nothing at its
## edge) that swells by GLOW_SWELL and brightens from GLOW_ALPHA_LOW to GLOW_ALPHA_HIGH once per
## PULSE_PERIOD_S, while the crystal itself brightens by BRIGHT_PULSE.
const PULSE_PERIOD_S := 1.6
const GLOW_RADIUS_PX := 17.0
const GLOW_SWELL := 0.18
const GLOW_ALPHA_LOW := 0.35
const GLOW_ALPHA_HIGH := 0.6
const GLOW := Color("#ffcf5a")
const GLOW_SIZE_PX := 64
const BRIGHT_PULSE := 0.12
const SHADOW := Color(0.0, 0.0, 0.0, 0.22)
const SHADOW_SIZE := Vector2(8.0, 3.0)
## The pop out of the corpse: up this high over this long, with a squash on landing.
const POP_PX := 18.0
const POP_S := 0.32
const LAND_SQUASH := Vector2(1.25, 0.8)
const LAND_S := 0.12
const BLINK_PERIOD_S := 0.12

## True while it blinks (about to fade).
var blink: bool = false

var _age_s: float = 0.0
## Where in its bob and its pulse this shard starts (seconds).
var _phase_s: float = 0.0

## The glow's soft round texture (made once).
static var _glow_texture: GradientTexture2D


func _ready() -> void:
	texture_filter = TEXTURE_FILTER
	_phase_s = randf() * maxf(BOB_PERIOD_S, PULSE_PERIOD_S)


func _process(delta: float) -> void:
	_age_s += delta
	queue_redraw()


func _draw() -> void:
	if blink and int(_age_s / BLINK_PERIOD_S) % 2 == 1:
		return
	var idle_s := _age_s + _phase_s
	var lift := FLOAT_PX + BOB_PX * sin(idle_s * TAU / BOB_PERIOD_S)
	var squash := Vector2.ONE
	if _age_s < POP_S:
		lift += POP_PX * sin(PI * _age_s / POP_S)
	elif _age_s < POP_S + LAND_S:
		var k := 1.0 - (_age_s - POP_S) / LAND_S
		squash = Vector2.ONE + (LAND_SQUASH - Vector2.ONE) * k
	draw_set_transform(Vector2.ZERO)
	_draw_ellipse(Vector2.ZERO, SHADOW_SIZE * (1.0 - 0.25 * (lift - FLOAT_PX) / POP_PX), SHADOW)
	var centre := Vector2(0.0, -lift)
	var pulse := 0.5 + 0.5 * sin(idle_s * TAU / PULSE_PERIOD_S)
	var glow_radius := GLOW_RADIUS_PX * (1.0 + GLOW_SWELL * pulse)
	draw_texture_rect(_glow(), Rect2(centre - Vector2.ONE * glow_radius, Vector2.ONE * glow_radius * 2.0), false,
		Color(1.0, 1.0, 1.0, lerpf(GLOW_ALPHA_LOW, GLOW_ALPHA_HIGH, pulse)))
	var art := Vector2(SHARD_TEXTURE.get_size())
	var size := art * (SHARD_HEIGHT_PX / maxf(1.0, art.y)) * squash
	var bright := 1.0 + BRIGHT_PULSE * pulse
	draw_texture_rect(SHARD_TEXTURE, Rect2(centre - size * 0.5, size), false, Color(bright, bright, bright, 1.0))


## The glow's texture: GLOW in the middle, fading to nothing at the edge of a GLOW_SIZE_PX square.
static func _glow() -> GradientTexture2D:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, GLOW)
		gradient.set_color(1, Color(GLOW, 0.0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = GLOW_SIZE_PX
		texture.height = GLOW_SIZE_PX
		_glow_texture = texture
	return _glow_texture


func _draw_ellipse(centre: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in 16:
		var angle := TAU * float(index) / 16.0
		points.append(centre + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
