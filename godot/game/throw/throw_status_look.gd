extends Node2D
## What a throw's effect looks like on the enemy it struck (throw-combat experiment,
## docs/godot/THROW_COMBAT.md), then gone. Presentation only: the stun or the slow itself is the
## reaction's and the enemy's (game-constants.json `combat.weights.<weight>.classes.thrown-<effect>`,
## `gulp.throwCombat.effects.<effect>`).
##
## - **freeze**: an icy crust round the feet and frost shards at the sides, while the stun lasts;
## - **sleep**: z's rising over the head while the enemy sleeps (EnemyReactions `is_asleep`: until a
##   damaging hit wakes it), fading out over SLEEP_FADE_MS once it wakes;
## - **stick** (honey; owner, 2026-11-01: no circle under the enemy): the enemy's own picture coated
##   in honey for the slow's time: a thick glossy amber coat over its top with drips running down its
##   edge, an amber glaze below (a copy of its sprite, frame for frame, with HONEY_SHADER), and honey
##   drops falling from it to the ground.
## One look per body: a new one replaces the old. It counts on the gameplay clock, so it waits with
## a hit-stop or a pause.
##
## Owner: throw combat (experiment).

const Services := preload("res://game/shared/services.gd")
const EnemyReactions := preload("res://game/combat/reactions/enemy_reactions.gd")

const SELF_PATH := "res://game/throw/throw_status_look.gd"
const NODE_NAME := "ThrowStatusLook"
const COAT_NAME := "HoneyCoat"
const FREEZE := "freeze"
const SLEEP := "sleep"
const STICK := "stick"
const ICE := Color(0.72, 0.9, 1.0, 0.55)
const ICE_EDGE := Color(0.9, 0.97, 1.0, 0.9)
const HONEY := Color(0.96, 0.62, 0.08, 1.0)
const HONEY_DEEP := Color(0.72, 0.36, 0.03, 1.0)
const HONEY_SHINE := Color(1.0, 0.94, 0.62, 1.0)
const Z_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const Z_OUTLINE := Color(0.1, 0.12, 0.25, 0.9)
const PUDDLE_SIZE := Vector2(26.0, 9.0)
const Z_FONT_SIZE := 15
const Z_RISE_PX := 26.0
const Z_CYCLE_MS := 1200.0
const Z_COUNT := 3
## The last share of the look fades out.
const FADE_SHARE := 0.2
## A woken sleeper's z's fade out over this.
const SLEEP_FADE_MS := 300.0
## Honey drops falling from the coat: how many at once, one fall's time, its length (px).
const DROPS := 3
const DROP_MS := 700.0
const DROP_FALL_PX := 22.0
const DROP_RADIUS_PX := 2.8
## The coat's look: its edge's share of the art's height from the top, how far its drips run
## further down, their cycle, and how thick it is (its alpha over the art: 1 hides the art under it,
## lower lets the face show through) and the glaze's below it.
const COAT_EDGE := 0.42
const COAT_DRIP := 0.3
const COAT_DRIP_MS := 2400.0
const COAT_THICKNESS := 0.68
const GLAZE_THICKNESS := 0.16
## The honey coat over the silhouette of the sprite it copies: a thick glossy coat over the top of the
## art (`edge` of its height, wavy, with drips that run down and start again), with a dark wet lip
## at its edge and round the outline, light caught on every top surface and a shine on the crown;
## a thin glaze below it. `rect` is the art's own rect in the sprite's local space (x, y, w, h: the
## frame's used pixels, `_art_rect`); `fade` the look's alpha.
const HONEY_SHADER := """
shader_type canvas_item;
uniform vec4 honey : source_color;
uniform vec4 deep : source_color;
uniform vec4 shine : source_color;
uniform vec4 rect = vec4(-16.0, -16.0, 32.0, 32.0);
uniform float edge = 0.42;
uniform float drip = 0.3;
uniform float cycle = 0.0;
uniform float fade = 1.0;
uniform float thickness = 0.68;
uniform float glaze = 0.16;
varying vec2 local;

void vertex() {
	local = VERTEX;
}

float drip_at(float x) {
	float column = floor(x * 9.0);
	float seed = fract(sin(column * 12.9898 + 4.1) * 43758.5453);
	float centre = (column + 0.5) / 9.0;
	float width = 0.035 + 0.025 * seed;
	float shape = 1.0 - smoothstep(width * 0.5, width, abs(x - centre));
	float grow = fract(cycle * (0.7 + 0.6 * seed) + seed);
	return shape * drip * grow * step(0.3, seed);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 p = (local - rect.xy) / max(rect.zw, vec2(1.0));
	float line = edge + 0.04 * sin(p.x * 17.0 + 1.3) + 0.025 * sin(p.x * 37.0) + drip_at(p.x);
	float coat = 1.0 - smoothstep(line - 0.012, line + 0.012, p.y);
	vec2 px = TEXTURE_PIXEL_SIZE * 4.0;
	float up = texture(TEXTURE, UV - vec2(0.0, px.y)).a;
	float down = texture(TEXTURE, UV + vec2(0.0, px.y)).a;
	float sides = min(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	float top_lip = clamp(base.a - up, 0.0, 1.0);
	float outline = clamp(base.a - min(min(up, down), sides), 0.0, 1.0);
	float depth = clamp(p.y / max(line, 0.05), 0.0, 1.0);
	vec3 colour = mix(honey.rgb, deep.rgb, depth * 0.45);
	float wet = smoothstep(line - 0.045, line - 0.008, p.y) * coat;
	colour = mix(colour, deep.rgb * 0.75, max(wet * 0.8, outline * 0.55 * (1.0 - top_lip)));
	float gloss = 1.0 - smoothstep(0.0, 0.09, length((p - vec2(0.34, 0.12)) * vec2(1.0, 1.6)));
	float streak = (1.0 - smoothstep(0.0, 0.025, abs(p.x - 0.62 + p.y * 0.4))) * (1.0 - smoothstep(0.08, 0.2, p.y));
	colour = mix(colour, shine.rgb, clamp(gloss + streak * 0.8 + top_lip * 0.9, 0.0, 1.0) * coat);
	float alpha = mix(glaze, thickness, coat) + wet * 0.2;
	COLOR = vec4(colour, base.a * alpha * fade);
}
"""

static var _honey_shader: Shader = null
## Each texture frame's used rect (`_art_rect`), by texture and frame.
static var _art_rects: Dictionary = {}

var effect: String = ""
var _from_ms: float = 0.0
var _until_ms: float = 0.0
## The top of the enemy's art over its feet (px, negative).
var _head_y: float = -40.0
## The enemy it is on (sleep: is it still asleep?).
var _receiver: WeakRef = null
## The honey coat (a Sprite2D under the enemy's visual) and the visual it copies.
var _coat: Sprite2D = null
var _visual: WeakRef = null


## Puts `effect`'s look on `receiver` (an enemy: its `get_body()` or itself) for `ms` of gameplay
## time (sleep: while it sleeps). Nothing for an effect with no look or a receiver with no body.
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
	var visual: Sprite2D = null
	if receiver.has_method(&"get_visual"):
		visual = receiver.call(&"get_visual") as Sprite2D
	look.call(&"setup", look_effect, now, now + ms, head, receiver, visual)
	host.add_child(look)


func setup(look_effect: String, from_ms: float, until_ms: float, head_y: float, receiver: Object = null,
		visual: Sprite2D = null) -> void:
	effect = look_effect
	_from_ms = from_ms
	_until_ms = until_ms
	_head_y = head_y
	_receiver = weakref(receiver) if receiver != null else null
	if effect == STICK and visual != null and is_instance_valid(visual):
		_visual = weakref(visual)
		_coat = _make_coat(visual)


func _exit_tree() -> void:
	if _coat != null and is_instance_valid(_coat):
		_coat.queue_free()
	_coat = null


func _process(_delta: float) -> void:
	var now := Services.now_ms()
	if effect == SLEEP:
		var receiver: Object = _receiver.get_ref() if _receiver != null else null
		if receiver != null and EnemyReactions.is_asleep(receiver as Node):
			_until_ms = maxf(_until_ms, now + SLEEP_FADE_MS)
	if now >= _until_ms:
		queue_free()
		return
	_update_coat(now)
	queue_redraw()


func _draw() -> void:
	var now := Services.now_ms()
	var alpha := _alpha(now)
	match effect:
		FREEZE:
			_draw_puddle(Color(ICE, ICE.a * alpha), Color(ICE_EDGE, ICE_EDGE.a * alpha))
			for side: float in [-1.0, 1.0]:
				var base := Vector2(side * PUDDLE_SIZE.x * 0.8, -4.0)
				var shard := PackedVector2Array([base + Vector2(-4.0, 0.0), base + Vector2(4.0, 0.0),
					base + Vector2(side * 3.0, -18.0)])
				draw_colored_polygon(shard, Color(ICE_EDGE, 0.8 * alpha))
		STICK:
			_draw_drops(now, alpha)
		SLEEP:
			var font := ThemeDB.fallback_font
			for i in Z_COUNT:
				var phase := fmod((now - _from_ms) / Z_CYCLE_MS + float(i) / Z_COUNT, 1.0)
				var at := Vector2(6.0 + phase * 10.0, _head_y - phase * Z_RISE_PX)
				var a := alpha * sin(phase * PI)
				var size := int(Z_FONT_SIZE * (0.7 + phase * 0.5))
				draw_string_outline(font, at, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(Z_OUTLINE, a))
				draw_string(font, at, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(Z_COLOR, a))


## The look's alpha now: a sleep fades over SLEEP_FADE_MS once it woke, the others over their last
## FADE_SHARE.
func _alpha(now: float) -> float:
	var left := _until_ms - now
	if effect == SLEEP:
		return clampf(left / SLEEP_FADE_MS, 0.0, 1.0)
	return clampf(left / (maxf(1.0, _until_ms - _from_ms) * FADE_SHARE), 0.0, 1.0)


func _draw_puddle(fill: Color, edge: Color) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * i / 20.0
		points.append(Vector2(cos(angle) * PUDDLE_SIZE.x, sin(angle) * PUDDLE_SIZE.y))
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, edge, 1.5, true)


## Honey drops let go of the coat's edge (about the middle of the body) and fall to the feet,
## stretching as they fall, each on its own beat and column.
func _draw_drops(now: float, alpha: float) -> void:
	var top := _head_y * (1.0 - COAT_EDGE)
	for i in DROPS:
		var t := fmod((now - _from_ms) / DROP_MS + float(i) / DROPS * 1.7, 1.0)
		var x := (fmod(float(i) * 7.3, 3.0) - 1.0) * 8.0
		var fall := t * t
		var at := Vector2(x, top + fall * minf(DROP_FALL_PX, -top))
		var stretch := 1.0 + fall * 1.2
		var a := alpha * (1.0 - smoothstep(0.85, 1.0, t))
		var drop := PackedVector2Array()
		for k in 12:
			var angle := TAU * k / 12.0
			var point := Vector2(cos(angle), sin(angle)) * DROP_RADIUS_PX
			if point.y < 0.0:
				point.y *= stretch * 1.6
			drop.append(at + point)
		draw_colored_polygon(drop, Color(HONEY, 0.95 * a))
		drop.append(drop[0])
		draw_polyline(drop, Color(HONEY_DEEP, 0.9 * a), 0.8, true)
		draw_circle(at + Vector2(-0.8, -0.8), DROP_RADIUS_PX * 0.35, Color(HONEY_SHINE, 0.9 * a))


## The coat: a Sprite2D child of `visual` (it moves, squashes and flips with it), drawn with
## HONEY_SHADER over it.
func _make_coat(visual: Sprite2D) -> Sprite2D:
	var old := visual.get_node_or_null(COAT_NAME)
	if old != null:
		old.free()
	if _honey_shader == null:
		_honey_shader = Shader.new()
		_honey_shader.code = HONEY_SHADER
	var material := ShaderMaterial.new()
	material.shader = _honey_shader
	material.set_shader_parameter(&"honey", HONEY)
	material.set_shader_parameter(&"deep", HONEY_DEEP)
	material.set_shader_parameter(&"shine", HONEY_SHINE)
	material.set_shader_parameter(&"edge", COAT_EDGE)
	material.set_shader_parameter(&"drip", COAT_DRIP)
	material.set_shader_parameter(&"thickness", COAT_THICKNESS)
	material.set_shader_parameter(&"glaze", GLAZE_THICKNESS)
	var coat := Sprite2D.new()
	coat.name = COAT_NAME
	coat.material = material
	visual.add_child(coat)
	_copy_frame(visual, coat)
	return coat


## The coat follows the visual's frame and the look's fade.
func _update_coat(now: float) -> void:
	if _coat == null or not is_instance_valid(_coat):
		return
	var visual: Sprite2D = _visual.get_ref() as Sprite2D if _visual != null else null
	if visual == null or not is_instance_valid(visual):
		return
	_copy_frame(visual, _coat)
	var material := _coat.material as ShaderMaterial
	material.set_shader_parameter(&"cycle", fmod((now - _from_ms) / COAT_DRIP_MS, 1.0))
	material.set_shader_parameter(&"fade", _alpha(now))


static func _copy_frame(visual: Sprite2D, coat: Sprite2D) -> void:
	coat.texture = visual.texture
	coat.centered = visual.centered
	coat.offset = visual.offset
	coat.flip_h = visual.flip_h
	coat.flip_v = visual.flip_v
	coat.hframes = visual.hframes
	coat.vframes = visual.vframes
	coat.frame = visual.frame
	coat.region_enabled = visual.region_enabled
	coat.region_rect = visual.region_rect
	var rect := _art_rect(coat)
	(coat.material as ShaderMaterial).set_shader_parameter(&"rect",
		Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))


## The art's own rect in `sprite`'s local space: the used (not see-through) pixels of its current
## frame, so the coat sits on the art and not on the empty frame round it. Read once per texture and
## frame (`_art_rects`); the whole frame when the texture cannot be read.
static func _art_rect(sprite: Sprite2D) -> Rect2:
	var full := sprite.get_rect()
	var texture := sprite.texture
	if texture == null:
		return full
	var source := sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, texture.get_size())
	var cells := Vector2i(maxi(1, sprite.hframes), maxi(1, sprite.vframes))
	var cell := source.size / Vector2(cells)
	var at := source.position + cell * Vector2(sprite.frame % cells.x, sprite.frame / cells.x)
	var key := "%s|%s|%s" % [texture.get_rid(), at, cell]
	var used: Rect2 = _art_rects.get(key, Rect2())
	if not _art_rects.has(key):
		var image := texture.get_image()
		if image == null:
			return full
		if image.is_compressed():
			image.decompress()
		var region := Rect2i(Rect2(at, cell)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		used = Rect2(image.get_region(region).get_used_rect()) if region.has_area() else Rect2(Vector2.ZERO, cell)
		_art_rects[key] = used
	if not used.has_area():
		return full
	if sprite.flip_h:
		used.position.x = cell.x - used.end.x
	if sprite.flip_v:
		used.position.y = cell.y - used.end.y
	return Rect2(full.position + used.position * full.size / cell, used.size * full.size / cell)
