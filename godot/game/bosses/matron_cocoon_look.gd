@tool
extends Node2D
## The Orb-Weaver Matron's cocoon (docs/godot/specs/matron.md "The cocoon"; the Weaver Hollow's
## boss): presentation only. A child of her body at her feet, which are the cocoon's shadow on the
## floor; matron.gd sets `state`, `progress`, `hang_px` and `breath` every step, and this node draws:
##
## - **the shadow**, an ellipse on the floor that shrinks and pales as the cocoon hangs higher;
## - **the thread**, a silk line from the cocoon's top up to `thread_top_px` above the shadow (her
##   web); the packed art already has its first stretch;
## - **the cocoon** (`sheet_path` frame 0: her purple shape and six red eyes through the silk),
##   hanging with its bottom `hang_px` over the shadow, swelling and sinking with `breath` (the
##   Cocoon Mimic's tell: a cocoon that breathes wants a blast), and a red glow over the eyes that
##   brightens as it swells;
## - **torn** (frame 1): the empty husk on its thread while she is down on the floor;
## - **respin**: threads whirl round the husk and the cocoon closes again (`progress` 0..1);
## - **gone**: her defeat, the cocoon unravels and the thread draws up into the web.
##
## The pictures come from scripts/art/pack-matron-art.py (256 x 416 cells, the thread's top at each
## cell's top middle); `art_bottom_px` and `eyes_px` are where the cocoon's bottom and eyes are in the
## cell. In the editor `preview_state` shows a state, so the hang, the thread and the glow can be tuned
## on the scene.
##
## Owner: boss port (the Matron).

const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")
const GroundShadowLook := preload("res://game/enemy/ground_shadow.gd")

const STATE_OFF := "off"
const STATE_COCOONED := "cocooned"
const STATE_TORN := "torn"
const STATE_RESPIN := "respin"
const STATE_GONE := "gone"
const FRAME_COCOON := 0
const FRAME_TORN := 1
const THREAD_COLOR := Color(0.97, 0.93, 0.82, 0.85)
const WHIRL_COLOR := Color(0.98, 0.95, 0.86, 0.9)
const WHIRLS := 4
const WHIRL_SPEED := 7.0
const WHIRL_ARC := 1.7
const WHIRL_POINTS := 14
## The glow's texture is GLOW_TEXTURE_PX wide.
const GLOW_TEXTURE_PX := 64.0
## How much of the breath's swell goes sideways (it swells downward more than sideways).
const BREATH_WIDTH_SHARE := 0.6

## The cocoon strip (frame 0 whole, frame 1 torn).
@export_file("*.webp", "*.png") var sheet_path: String = "res://asset/MAPS/enemies/256x416-tile_2x1-matron-cocoon.webp":
	set(value):
		sheet_path = value
		_build()
@export var cell_size: Vector2 = Vector2(256.0, 416.0)
## The art's size in the world (0.5: the project's 2 art pixels per world unit).
@export var art_scale: float = 0.5:
	set(value):
		art_scale = value
		_apply()
## The whole cocoon's bottom and its eyes in its cell (art pixels; the packer prints them).
@export var art_bottom_px: float = 383.0
@export var eyes_px: Vector2 = Vector2(127.0, 127.0)
## The cocoon's bottom above the shadow (world units). matron.gd sets it per round.
@export var hang_px: float = 60.0:
	set(value):
		hang_px = value
		_apply()
## Where the thread ends above the shadow (her web).
@export var thread_top_px: float = 420.0:
	set(value):
		thread_top_px = value
		queue_redraw()
## The shadow's half axes when the cocoon hangs at `hang_px` 0, and the hang at which it is gone.
@export var shadow_size: Vector2 = Vector2(62.0, 19.0)
@export var shadow_fade_px: float = 360.0
## The breath's swell at its fullest (share of the size).
@export var breath_swell: float = 0.06
@export var eye_glow_color: Color = Color(1.0, 0.25, 0.12, 0.42)
## The eyes' glow radius (art pixels) and how much brighter a full breath makes it.
@export var eye_glow_px: float = 22.0
@export var eye_glow_pulse: float = 0.5
@export_enum("cocooned", "torn", "respin", "gone", "off") var preview_state: String = "cocooned":
	set(value):
		preview_state = value
		if Engine.is_editor_hint():
			state = value

## What it shows (STATE_*), set by matron.gd.
var state: String = STATE_COCOONED:
	set(value):
		state = value
		_apply()
## 0..1 through `respin` and `gone`.
var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		_apply()
## 0..1: how full the breath is.
var breath: float = 0.0:
	set(value):
		breath = clampf(value, 0.0, 1.0)
		_apply()

var _cocoon: Sprite2D
var _torn: Sprite2D
var _glow: Sprite2D
var _shadow: GroundShadowLook
var _clock: float = 0.0


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	_clock += delta
	if Engine.is_editor_hint():
		breath = (sin(_clock / 2.6 * TAU) + 1.0) * 0.5
	if state == STATE_RESPIN or state == STATE_GONE:
		queue_redraw()


## The cocoon's top (where the art's thread starts), relative to the shadow.
func cocoon_top() -> Vector2:
	return Vector2(0.0, -hang_px - art_bottom_px * art_scale)


## The middle of the cocoon, relative to the shadow (the clink line and the tear burst rise from it).
func cocoon_middle() -> Vector2:
	return Vector2(0.0, -hang_px - art_bottom_px * art_scale * 0.5)


func _build() -> void:
	if not is_inside_tree():
		return
	var picture := SheetSprite.load_picture(sheet_path)
	if _cocoon == null:
		_shadow = GroundShadowLook.new()
		_shadow.name = "Shadow"
		add_child(_shadow, false, Node.INTERNAL_MODE_FRONT)
		_cocoon = _make_sprite("Cocoon", FRAME_COCOON)
		_torn = _make_sprite("Torn", FRAME_TORN)
		_glow = Sprite2D.new()
		_glow.name = "EyeGlow"
		_glow.texture = _glow_texture()
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow.material = add
		_cocoon.add_child(_glow, false, Node.INTERNAL_MODE_FRONT)
	for sprite: Sprite2D in [_cocoon, _torn]:
		sprite.texture = picture
	_apply()


func _make_sprite(sprite_name: String, frame: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.centered = false
	sprite.hframes = 2
	sprite.frame = frame
	sprite.offset = Vector2(-cell_size.x * 0.5, 0.0)
	add_child(sprite, false, Node.INTERNAL_MODE_FRONT)
	return sprite


func _apply() -> void:
	if _cocoon == null:
		return
	var top := cocoon_top()
	var swell := breath_swell * breath
	var base := Vector2.ONE * art_scale
	var shown := state != STATE_OFF
	visible = shown
	# Whole while it fights from inside and while the respin closes it; torn while she is down.
	var whole_alpha := 1.0
	var torn_alpha := 0.0
	var squash := Vector2.ONE
	match state:
		STATE_TORN:
			whole_alpha = 0.0
			torn_alpha = 1.0
		STATE_RESPIN:
			# The husk fades as the new silk closes over it from a pinched, narrow shape.
			var closing := clampf((progress - 0.35) / 0.65, 0.0, 1.0)
			whole_alpha = closing
			torn_alpha = 1.0 - closing
			squash = Vector2(0.55 + 0.45 * closing, 0.8 + 0.2 * closing)
		STATE_GONE:
			whole_alpha = 1.0 - progress
			squash = Vector2(1.0 - 0.4 * progress, 1.0 + 0.15 * progress)
	_cocoon.position = top
	_cocoon.scale = base * squash * Vector2(1.0 + swell * BREATH_WIDTH_SHARE, 1.0 + swell)
	_cocoon.modulate.a = whole_alpha
	_cocoon.visible = whole_alpha > 0.0
	_torn.position = top
	_torn.scale = base
	_torn.modulate.a = torn_alpha
	_torn.visible = torn_alpha > 0.0
	# The eyes: glow brighter as it swells; dark while the respin has not closed it yet.
	_glow.position = eyes_px - Vector2(cell_size.x * 0.5, 0.0)
	_glow.scale = Vector2.ONE * (eye_glow_px * 2.0 / GLOW_TEXTURE_PX)
	var glow := eye_glow_color
	glow.a = eye_glow_color.a * (1.0 - eye_glow_pulse + eye_glow_pulse * breath)
	_glow.modulate = glow
	var shadow_share := clampf(1.0 - hang_px / maxf(1.0, shadow_fade_px), 0.25, 1.0)
	_shadow.size = shadow_size * (0.7 + 0.3 * shadow_share)
	_shadow.strength = shadow_share * (1.0 - (progress if state == STATE_GONE else 0.0))
	queue_redraw()


func _draw() -> void:
	if state == STATE_OFF:
		return
	var top := cocoon_top()
	var thread_alpha := 1.0
	var thread_end := -thread_top_px
	if state == STATE_GONE:
		# The thread draws up into the web.
		thread_alpha = 1.0 - progress
		top.y = lerpf(top.y, thread_end, progress)
	if thread_alpha > 0.0 and top.y > thread_end:
		draw_line(Vector2(0.0, top.y + 2.0), Vector2(0.0, thread_end), Color(THREAD_COLOR, THREAD_COLOR.a * thread_alpha), 2.0, true)
	if state == STATE_RESPIN:
		_draw_whirl()


## The respin's tell: silk threads whirling round the cocoon, tightening as it closes.
func _draw_whirl() -> void:
	var middle := cocoon_middle()
	var size := Vector2(cell_size.x * 0.32, art_bottom_px * 0.36) * art_scale * (1.25 - 0.35 * progress)
	var alpha := sin(progress * PI) * WHIRL_COLOR.a
	for i in WHIRLS:
		var start := _clock * WHIRL_SPEED + TAU * float(i) / float(WHIRLS)
		var points := PackedVector2Array()
		for p in WHIRL_POINTS:
			var angle := start + WHIRL_ARC * float(p) / float(WHIRL_POINTS - 1)
			points.append(middle + Vector2(cos(angle) * size.x, sin(angle) * size.y))
		draw_polyline(points, Color(WHIRL_COLOR, alpha), 2.0, true)


## A soft round glow (white in the middle, clear at the rim), tinted by `eye_glow_color`.
static func _glow_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = int(GLOW_TEXTURE_PX)
	texture.height = int(GLOW_TEXTURE_PX)
	return texture
