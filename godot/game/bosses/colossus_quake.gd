extends Node2D
## The Crystal Colossus's quake on his floor (game/scripts/crystal_colossus.gd, the crystal fight;
## docs/godot/DUNGEONS.md "The crystal fight"): presentation only, made when his warning starts, at his
## feet, under the actors (z -1). While he warns (`warn_ms`) painted fissures
## (`colossus-quake-fissures-1x4.webp`) run out from his feet across his whole floor (`floor_rect`),
## piece after piece along wandering rays, each growing from its near end, and the climb walls by his
## wall (`roots`) light up as the safe place; while the floor shakes (`quake_ms`) the fissures glow and
## pulse, the floor is tinted and painted craters (`colossus-quake-craters-4x1.webp`) pop where he
## breaks it (`add_crater`). Nothing is drawn past his floor's edge (a clip by world position). It
## watches his phase and fades out once he is out of the quake (its end, a cart's blow, his fall),
## then frees itself. The art's sources and packer: asset/Originals/dungeon-kit/bosses/colossus/quake/,
## scripts/art/pack-quake-art.py.
##
## Owner: dungeons (the Crystal Mine).

const Services := preload("res://game/shared/services.gd")
const GlowMoss := preload("res://game/world/darkness/glow_moss.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const WARN_PHASE := "quake-warn"
const QUAKE_PHASE := "quake"
const FISSURES_ART := "res://asset/MAPS/effects/colossus-quake-fissures-1x4.webp"
const CRATERS_ART := "res://asset/MAPS/effects/colossus-quake-craters-4x1.webp"
## The fissure sheet's cells (one fissure a row, its crack along the cell's middle line) and how many;
## a piece's scale in the world (a cell of 640 px: 288 units long), how much of it the next one
## overlaps.
const FISSURE_CELL := Vector2(640.0, 120.0)
const FISSURE_KINDS := 4
const FISSURE_SCALE := 0.45
const PIECE_OVERLAP := 0.1
## The rays: how many run out from his feet, how far from his feet they start, how much a piece may
## turn from the last and how strongly each keeps to its way out, at most how many pieces a ray.
const RAYS := 9
const START_PX := 40.0
const BEND := 0.3
const KEEP_WAY := 0.35
const MAX_PIECES := 6
const SEED := 4417
## The fissures spread over this share of the warning (then they wait, glowing, for the first pound).
const SPREAD_SHARE := 0.8
## The craters' sheet cells and scale (a cell of 256 px: about 118 units), their pop, how long they
## lie, their fade.
const CRATER_CELL := 256.0
const CRATER_KINDS := 4
const CRATER_SCALE := 0.46
const CRATER_POP_S := 0.12
const CRATER_LIE_S := 1.2
const CRATER_FADE_S := 0.5
## Colours: the floor's tint while it shakes, the fissures' glow (added light), the roots' light.
const FLOOR_TINT := Color(1.0, 0.42, 0.12)
const GLOW := Color(1.0, 0.62, 0.3)
const ROOT_LIGHT := Color(0.72, 1.0, 0.62, 0.95)
## The roots' light: its radius, how much it swells with the pulse, the pulse's period, how high up a
## climb wall its middle is (a share of the wall's `top`).
const ROOT_RADIUS := 96.0
const ROOT_SWELL := 18.0
const PULSE_MS := 260.0
const ROOT_MIDDLE := 0.55
const FADE_MS := 700.0
## The clip: a canvas item's pixels past the floor's rectangle (world) are not drawn; `ADD` the glow's.
const CLIP_SHADER := """
shader_type canvas_item;
render_mode %s;
uniform vec4 floor_rect;
varying vec2 world_at;
void vertex() {
	world_at = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	vec4 colour = texture(TEXTURE, UV) * COLOR;
	if (world_at.x < floor_rect.x || world_at.y < floor_rect.y || world_at.x > floor_rect.x + floor_rect.z || world_at.y > floor_rect.y + floor_rect.w) {
		colour.a = 0.0;
	}
	COLOR = colour;
}
"""

## Set before it enters the tree: the boss whose phase it watches, his feet (global: it stands there),
## his floor (global), the warning's and the quake's length, the climb walls to light.
var boss: Node
var origin := Vector2.ZERO
var floor_rect := Rect2()
var warn_ms := 2500.0
var quake_ms := 5000.0
var roots: Array[Node2D] = []

var _started_at := 0.0
var _fade_from := -1.0
var _clip: ShaderMaterial
var _clip_glow: ShaderMaterial
var _craters_art: Texture2D
var _rng := RandomNumberGenerator.new()
## The fissure pieces: each {"sprite", "glow" (its glowing twin), "from" (its near end's distance from
## his feet along its ray), "length"}.
var _pieces: Array[Dictionary] = []
var _farthest := 1.0
var _lights: Array[Node2D] = []


func _ready() -> void:
	z_index = -1
	global_position = origin
	_started_at = Services.now_ms()
	_rng.seed = SEED
	var rect := Vector4(floor_rect.position.x, floor_rect.position.y, floor_rect.size.x, floor_rect.size.y)
	_clip = _clip_material("blend_mix", rect)
	_clip_glow = _clip_material("blend_add", rect)
	_craters_art = SheetSprite.load_picture(CRATERS_ART)
	_lay_fissures(SheetSprite.load_picture(FISSURES_ART))
	for root: Node2D in roots:
		if not is_instance_valid(root):
			continue
		var light := Node2D.new()
		light.set_script(GlowMoss)
		light.name = "QuakeRootLight"
		light.set(&"color", ROOT_LIGHT)
		light.set(&"radius", 0.0)
		add_child(light)
		var top: Variant = root.get(&"top")
		light.global_position = root.global_position + (top as Vector2 if top is Vector2 else Vector2(0, -192)) * ROOT_MIDDLE
		_lights.append(light)


func _process(_delta: float) -> void:
	var now := Services.now_ms()
	var phase := str(boss.call(&"get_phase")) if is_instance_valid(boss) and boss.has_method(&"get_phase") else ""
	if _fade_from < 0.0 and phase != WARN_PHASE and phase != QUAKE_PHASE:
		_fade_from = now
	var fade := _fade(now)
	if fade <= 0.0:
		queue_free()
		return
	var age := now - _started_at
	var shaking := age >= warn_ms
	var pulse := _pulse(now)
	var spread := _farthest * clampf(age / maxf(1.0, warn_ms * SPREAD_SHARE), 0.0, 1.0)
	var glow := (lerpf(0.15, 0.4, clampf(age / maxf(1.0, warn_ms), 0.0, 1.0)) if not shaking else 0.45 + 0.4 * pulse) * fade
	for piece: Dictionary in _pieces:
		var shown := clampf((spread - float(piece["from"])) / float(piece["length"]), 0.0, 1.0)
		for sprite: Sprite2D in [piece["sprite"], piece["glow"]]:
			sprite.visible = shown > 0.0
			var region := sprite.region_rect
			region.size.x = FISSURE_CELL.x * shown
			sprite.region_rect = region
		(piece["sprite"] as Sprite2D).modulate.a = fade
		(piece["glow"] as Sprite2D).modulate = Color(GLOW, glow)
	for light: Node2D in _lights:
		light.set(&"radius", (ROOT_RADIUS + ROOT_SWELL * pulse) * fade * clampf(age / 300.0, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	var now := Services.now_ms()
	if now - _started_at < warn_ms:
		return
	draw_rect(Rect2(floor_rect.position - global_position, floor_rect.size),
		Color(FLOOR_TINT, (0.05 + 0.07 * _pulse(now)) * _fade(now)))


## A crater where he breaks the floor (global `at`): it pops in, lies a moment and fades.
func add_crater(at: Vector2) -> void:
	if _craters_art == null:
		return
	var crater := Sprite2D.new()
	crater.texture = _craters_art
	crater.hframes = CRATER_KINDS
	crater.frame = _rng.randi_range(0, CRATER_KINDS - 1)
	crater.flip_h = _rng.randf() < 0.5
	crater.rotation = _rng.randf_range(-0.3, 0.3)
	crater.material = _clip
	crater.position = at - global_position
	crater.scale = Vector2.ONE * CRATER_SCALE * 0.55
	add_child(crater)
	var tween := crater.create_tween()
	tween.tween_property(crater, "scale", Vector2.ONE * CRATER_SCALE, CRATER_POP_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(CRATER_LIE_S)
	tween.tween_property(crater, "modulate:a", 0.0, CRATER_FADE_S)
	tween.tween_callback(crater.queue_free)


## The fissures: along each ray out from his feet, pieces end to end (each a random kind, some
## mirrored across their line), until the ray leaves his floor.
func _lay_fissures(art: Texture2D) -> void:
	if art == null:
		return
	var rect := Rect2(floor_rect.position - global_position, floor_rect.size)
	var length := FISSURE_CELL.x * FISSURE_SCALE
	for i in RAYS:
		var way := TAU * (float(i) + _rng.randf_range(-0.3, 0.3)) / float(RAYS)
		var at := Vector2.from_angle(way) * START_PX
		var heading := way
		var gone := START_PX
		for k in MAX_PIECES:
			if not rect.has_point(at):
				break
			heading = lerp_angle(heading + _rng.randf_range(-BEND, BEND), way, KEEP_WAY)
			var kind := _rng.randi_range(0, FISSURE_KINDS - 1)
			var mirrored := _rng.randf() < 0.5
			var piece := _fissure_sprite(art, kind, mirrored, _clip)
			var glow := _fissure_sprite(art, kind, mirrored, _clip_glow)
			piece.position = at
			piece.rotation = heading
			add_child(piece)
			piece.add_child(glow)
			glow.position = Vector2.ZERO
			glow.scale = Vector2.ONE
			_pieces.append({"sprite": piece, "glow": glow, "from": gone, "length": length})
			_farthest = maxf(_farthest, gone + length)
			var step := length * (1.0 - PIECE_OVERLAP)
			at += Vector2.from_angle(heading) * step
			gone += step


## One fissure piece: its near end on the node, its crack along +x, grown by its region's width.
func _fissure_sprite(art: Texture2D, kind: int, mirrored: bool, clip: ShaderMaterial) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = art
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0.0, FISSURE_CELL.y * float(kind), 0.0, FISSURE_CELL.y)
	sprite.offset = Vector2(0.0, -FISSURE_CELL.y * 0.5)
	sprite.flip_v = mirrored
	sprite.scale = Vector2.ONE * FISSURE_SCALE
	sprite.material = clip
	sprite.visible = false
	return sprite


static func _clip_material(blend: String, rect: Vector4) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = CLIP_SHADER % blend
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"floor_rect", rect)
	return material


func _pulse(now: float) -> float:
	return 0.5 + 0.5 * sin((now - _started_at) / PULSE_MS * TAU)


func _fade(now: float) -> float:
	if _fade_from < 0.0:
		return 1.0
	return clampf(1.0 - (now - _fade_from) / FADE_MS, 0.0, 1.0)
