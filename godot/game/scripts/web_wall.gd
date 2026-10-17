@tool
extends Node2D
class_name WebWallScript
## Scene script of `object.web-wall` (docs/godot/WEBS.md; owner, 2026-10-16, question 131; roadmap
## 7.9): thick silk filling a doorway or a nook's mouth, the Silk skin's lock.
##
## - **Without the Silk skin** (`player.crosses_webs()`, today the Silk Gulp form) it is solid: a
##   walk and a Roll stop against it (a StaticBody2D on the `world` layer, which every walker
##   masks, so enemies never pass either). Every hit clinks with `refusal_text` ("Thick silk. It
##   will not give."), at most every 1.5 s for all barriers (BlastBarrier.refuse).
## - **With it** the slime passes through (its body gets a collision exception with the wall) at
##   `webs.wallPassMultiplier` (half) of its walk (FloorWebs, the group `web_slows`), and a shape's
##   hit (request tags in CUT_TAGS: the Spear, and the old weapons) cuts it open for good: the
##   solid and the hurtbox go, the cut picture shows (tatters at the jambs), the story flag
##   `save_key()` is set, and it says "The web tears open!" with the secret jingle `SecretFound`
##   when `hides_secret` (a nook behind it), else the web tear cue. Other hits (throws, blasts)
##   clink without a line. A blast never cuts it.
##
## Place it in the editor: `orientation` "across" for a door in a north or south wall (the web
## faces the camera; put the root on the doorway's floor line, in the middle), "side" for a door in
## an east or west wall (a narrow band of silk seen from above; put the root in the middle of the
## opening). `span` is the opening's width (128: a two-tile door), `thickness` the solid band's
## depth across it; the solid is drawn as a red box in the editor, the hurtbox as an orange one.
## `art_scale` shrinks or grows the picture, `height` sets its height alone (match the wall's, so
## the web does not stand over it). `preview_cut` shows the cut look. Set
## `flag_id` to name its story flag (default: `web-wall.<world scene>:<node path>`), e.g. to
## show a nook's prize with a story variant once it is cut.
##
## Owner: webs (the Weaver Hollow).

const Services := preload("res://game/shared/services.gd")
const FloorWebs := preload("res://game/world/webs/floor_webs.gd")
const BlastBarrier := preload("res://game/scripts/blast_barrier.gd")
const SpiderWebPort := preload("res://game/enemy/spider_web_port.gd")

const ACROSS_ART := "res://asset/MAPS/webs/web-wall-across-2x1.webp"
const SIDE_ART := "res://asset/MAPS/webs/web-wall-side-2x1.webp"
## The art is painted at 2 px a unit for a 128-unit opening.
const ART_SCALE := 0.5
const BASE_SPAN := 128.0
## The across picture's foot is this far below the root (the silk columns stand on the floor).
const ACROSS_FOOT := 3.0
## The side band's foot is this far below the opening's south end.
const SIDE_FOOT := 2.0
## The hurtbox: the solid band grown by this much on every side, and for "across" this much up the
## web's face.
const HURT_MARGIN := 12.0
const HURT_RISE := 64.0
## The Silk slime walks at half speed while its feet are within the solid grown by this much.
const PASS_MARGIN := 16.0
## Hits of these tags cut the web (with the Silk skin): the shapes and the old weapons.
const CUT_TAGS: Array[String] = ["weapon", "spear"]
const RULE := {"priority": 0, "damageMultiplier": 0}
const TAGS: Array[String] = ["barrier", "web"]
const FLAG_PREFIX := "web-wall."
const CUE_SECRET := &"SecretFound"
const SECRET_FALLBACK_CUE := &"GateOpen"
## The refusal line sits this far above the root (BlastBarrier.refuse raises it 70 more).
const LINE_RISE := 32.0
## A refused hit makes the silk shiver: amplitude (units), rate (rad/s), length (real ms).
const SHIVER_PX := 2.0
const SHIVER_RATE := 46.0
const SHIVER_MS := 260.0
const SOLID_PREVIEW := Color(1.0, 0.3, 0.3, 0.7)
const HURT_PREVIEW := Color(1.0, 0.65, 0.2, 0.6)

## The web was cut open. Payload: {"flagId", "x", "y"}.
signal cut(payload: Dictionary)
## A hit was refused (the clink). Payload: {"crosses": bool}.
signal refused(payload: Dictionary)

@export_enum("across", "side") var orientation: String = "across":
	set(value):
		orientation = value
		queue_redraw()
## The opening's width (world units): two tiles.
@export var span: float = 128.0:
	set(value):
		span = maxf(16.0, value)
		queue_redraw()
## The solid band's depth across the opening (world units).
@export var thickness: float = 24.0:
	set(value):
		thickness = maxf(4.0, value)
		queue_redraw()
## The picture's size against the opening's (1: as painted).
@export var art_scale: float = 1.0:
	set(value):
		art_scale = maxf(0.1, value)
		queue_redraw()
## The picture's height on screen, world units (0: its own proportion, about as tall as the opening
## is wide for "across"); set it to the wall's height so the web does not stand over the wall.
@export var height: float = 0.0:
	set(value):
		height = maxf(0.0, value)
		queue_redraw()
## Said when a hit cannot cut it (no Silk skin).
@export var refusal_text: String = "Thick silk. It will not give."
## A nook or a secret is behind it: cutting it plays the secret jingle.
@export var hides_secret: bool = false
## The story flag set when it is cut (empty: `web-wall.<world scene>:<node path>`).
@export var flag_id: String = ""
## Editor only: show the cut look.
@export var preview_cut: bool = false:
	set(value):
		preview_cut = value
		queue_redraw()

var _cut: bool = false
var _body: StaticBody2D
var _area: Area2D
var _excepted: PhysicsBody2D
var _shiver_until_ms: float = 0.0
static var _textures: Dictionary = {}


func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		set_physics_process(false)
		set_process(false)
		return
	var run := Services.run()
	_cut = run != null and run.has_flag(save_key())
	set_process(false)
	if _cut:
		set_physics_process(false)
		return
	add_to_group(FloorWebs.GROUP)
	_build_body()
	_build_hurtbox()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	_drop_exception()
	_unregister()


## True once it is cut (now or earlier in the run).
func is_cut() -> bool:
	return _cut


## The story flag it sets when cut.
func save_key() -> String:
	if not flag_id.is_empty():
		return flag_id
	return FLAG_PREFIX + _placement_key(self)


## `<world scene>:<path from the scene root>` for a node placed in a scene, else its tree path.
static func _placement_key(node: Node) -> String:
	var scene_root := node.owner
	if scene_root != null and not scene_root.scene_file_path.is_empty():
		return "%s:%s" % [scene_root.scene_file_path.get_file().get_basename(), str(scene_root.get_path_to(node))]
	return str(node.get_path())


## The solid band (local to the root).
func solid_rect() -> Rect2:
	if orientation == "side":
		return Rect2(-thickness / 2.0, -span / 2.0, thickness, span)
	return Rect2(-span / 2.0, -thickness / 2.0, span, thickness)


## The hurtbox (local to the root): the band grown, and up the web's face for "across".
func hurt_rect() -> Rect2:
	var rect := solid_rect().grow(HURT_MARGIN)
	if orientation == "across":
		rect = rect.expand(Vector2(rect.position.x, -HURT_RISE))
	return rect


## True when `point` (a world position) is in the wall's passage (the solid grown by PASS_MARGIN).
func in_passage(point: Vector2) -> bool:
	return point.is_finite() and solid_rect().grow(PASS_MARGIN).has_point(to_local(point))


# --- the Silk skin's pass ---------------------------------------------------------------------------

## FloorWebs: the Silk slime walks at `webs.wallPassMultiplier` through the wall.
func web_walk_multiplier(player: Node, crosses: bool) -> float:
	if _cut or not crosses or not in_passage(FloorWebs.feet(player)):
		return 1.0
	return FloorWebs.setting("wallPassMultiplier")


## Keeps the slime's body excepted from the solid while it crosses webs (and while it is still
## inside after it stopped crossing, so it is never shut in).
func _physics_process(_delta: float) -> void:
	if _cut or _body == null:
		return
	var player := FloorWebs.player()
	var body: PhysicsBody2D = player.get(&"body") as PhysicsBody2D if player != null else null
	if body == null:
		_drop_exception()
		return
	if _excepted != null and _excepted != body:
		_drop_exception()
	if bool(player.call(&"crosses_webs")):
		if _excepted == null:
			body.add_collision_exception_with(_body)
			_excepted = body
	elif _excepted != null and not in_passage(body.global_position):
		_drop_exception()


func _drop_exception() -> void:
	if _excepted != null and is_instance_valid(_excepted) and _body != null and is_instance_valid(_body):
		_excepted.remove_collision_exception_with(_body)
	_excepted = null


# --- the damage contract -----------------------------------------------------------------------------

func get_damage_state() -> Dictionary:
	return {"hp": 1.0, "max_hp": 1.0, "dead": _cut}


## A shape's hit with the Silk skin cuts it; anything else clinks (with the line without the skin).
func can_receive_damage(input: Dictionary) -> Dictionary:
	if _cut:
		return {"accepted": false, "reason": "dead"}
	var request: Dictionary = input.get("request", {})
	var crosses := _player_crosses_webs()
	if crosses and _is_cut_hit(request):
		return {"accepted": true}
	_shiver()
	refused.emit({"crosses": crosses})
	if crosses:
		return {"accepted": false, "reason": BlastBarrier.REASON_IMMUNE}
	return BlastBarrier.refuse(global_position - Vector2(0.0, LINE_RISE), refusal_text)


func commit_damage(_commit: Dictionary) -> void:
	if not _cut:
		cut_open()


func publish_damage_feedback(_commit: Dictionary) -> void:
	pass


## Cuts the web open for good (the shape's cut; tests and scripts may call it).
func cut_open() -> void:
	if _cut:
		return
	_cut = true
	var run := Services.run()
	if run != null:
		run.set_flag(save_key())
	remove_from_group(FloorWebs.GROUP)
	_drop_exception()
	_unregister()
	if _body != null:
		_body.queue_free()
		_body = null
	if _area != null:
		_area.queue_free()
		_area = null
	set_physics_process(false)
	queue_redraw()
	var middle := global_position + (Vector2(0.0, -40.0) if orientation == "across" else Vector2.ZERO)
	var zone := {"x": middle.x, "y": middle.y, "halfWidth": span / 2.0, "halfHeight": thickness / 2.0}
	var feel := Services.feel()
	if feel != null:
		if hides_secret:
			var audio: Node = feel.global_audio()
			var has_secret := audio != null and audio.find_child(String(CUE_SECRET), true, false) != null
			feel.audio_cue(CUE_SECRET if has_secret else SECRET_FALLBACK_CUE)
			feel.particles(SpiderWebPort.TORN_PARTICLES, middle)
			feel.floating_text(middle - Vector2(0.0, SpiderWebPort.TORN_MESSAGE_RISE_PX), SpiderWebPort.TORN_MESSAGE,
				&"cyan", true, SpiderWebPort.TORN_MESSAGE_MS)
		else:
			SpiderWebPort.web_torn(zone)
	cut.emit({"flagId": save_key(), "x": global_position.x, "y": global_position.y})


static func _is_cut_hit(request: Dictionary) -> bool:
	var tags: Variant = request.get("weapon_tags", [])
	if not (tags is Array):
		return false
	for tag: Variant in tags:
		if str(tag) in CUT_TAGS:
			return true
	return false


static func _player_crosses_webs() -> bool:
	var player := FloorWebs.player()
	return player != null and bool(player.call(&"crosses_webs"))


# --- bodies --------------------------------------------------------------------------------------------

func _build_body() -> void:
	_body = StaticBody2D.new()
	_body.name = "Solid"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.add_child(_rect_shape(solid_rect()))
	add_child(_body)


func _build_hurtbox() -> void:
	_area = Area2D.new()
	_area.name = "DamageArea"
	_area.collision_layer = 8
	_area.collision_mask = 0
	_area.monitoring = false
	_area.add_child(_rect_shape(hurt_rect()))
	add_child(_area)
	var router := Services.router()
	if router != null:
		router.register_area(_area, self, RULE, TAGS)


func _unregister() -> void:
	var router := Services.router()
	if router != null and _area != null and is_instance_valid(_area):
		router.unregister_area(_area)


static func _rect_shape(rect: Rect2) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	return shape


# --- the look ------------------------------------------------------------------------------------------

func _shiver() -> void:
	_shiver_until_ms = float(Time.get_ticks_msec()) + SHIVER_MS
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()
	if float(Time.get_ticks_msec()) >= _shiver_until_ms:
		set_process(false)


func _draw() -> void:
	var cut_look := _cut or (Engine.is_editor_hint() and preview_cut)
	var path := SIDE_ART if orientation == "side" else ACROSS_ART
	var texture := _texture(path)
	if texture != null:
		var frame := Vector2(texture.get_width() / 2.0, texture.get_height())
		var drawn := frame * ART_SCALE * (span / BASE_SPAN) * art_scale
		if height > 0.0:
			drawn.y = height
		var foot := Vector2(0.0, ACROSS_FOOT) if orientation == "across" else Vector2(0.0, span / 2.0 + SIDE_FOOT)
		var now := float(Time.get_ticks_msec())
		var shake := 0.0
		if not Engine.is_editor_hint() and now < _shiver_until_ms:
			shake = sin(now * SHIVER_RATE / 1000.0) * SHIVER_PX * (_shiver_until_ms - now) / SHIVER_MS
		var rect := Rect2(foot + Vector2(-drawn.x / 2.0 + shake, -drawn.y), drawn)
		draw_texture_rect_region(texture, rect, Rect2(Vector2(frame.x if cut_look else 0.0, 0.0), frame))
	if Engine.is_editor_hint():
		draw_rect(solid_rect(), SOLID_PREVIEW, false, 2.0)
		draw_rect(hurt_rect(), HURT_PREVIEW, false, 1.0)


static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]
