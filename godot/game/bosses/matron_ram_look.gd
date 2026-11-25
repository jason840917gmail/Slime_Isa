extends Node2D
## The Orb-Weaver Matron's look in her ram fight (game/bosses/matron_ram.gd; docs/godot/specs/matron.md
## section 9): presentation only, a child of her body at her feet (her shadow's place on the floor).
## matron_ram.gd sets it every step:
##
## - **her pose** (`show_pose`): a frame of her packed animations (BossSheetSprite: hanging, the
##   spit, the dive, rammed, on her back, climbing, spinning, dazed), its picture's bottom `bottom_px`
##   above the floor: hanging high, falling in a dive, lying on the floor at 0;
## - **a prop** (`show_prop`): the cocoon knocked down onto the floor, straining, then torn open;
## - **her thread** from her top up to `thread_top_px` over the shadow (her web), while she hangs,
##   climbs or spins;
## - **her shadow**, which shrinks and pales the higher she is: as she dives it grows (the tell).
##
## While she hangs in a whole cocoon the cocoon's own look (matron_cocoon_look.gd) draws it, and this
## node hides its pose and shadow (`hide_all`).
##
## Owner: boss port (the Matron).

const BossSheetSprite := preload("res://game/bosses/boss_sheet_sprite.gd")
const GroundShadowLook := preload("res://game/enemy/ground_shadow.gd")

const FOLDER := "res://asset/MAPS/enemies/bosses/matron"
const THREAD_COLOR := Color(0.97, 0.93, 0.82, 0.85)
const THREAD_WIDTH := 2.5

## Where the thread ends above the shadow (her web).
@export var thread_top_px: float = 460.0
## The shadow's half axes on the floor, the height at which it is faintest, and that faintest share.
@export var shadow_size: Vector2 = Vector2(70.0, 21.0)
@export var shadow_fade_px: float = 320.0
@export var shadow_least: float = 0.25

var _pose: BossSheetSprite
var _prop: BossSheetSprite
var _shadow: GroundShadowLook
## The thread's lower end (local y), or NAN when none shows.
var _thread_from: float = NAN


func _ready() -> void:
	_shadow = GroundShadowLook.new()
	_shadow.name = "Shadow"
	add_child(_shadow, false, Node.INTERNAL_MODE_FRONT)
	_prop = _make_sprite("Prop")
	_pose = _make_sprite("Pose")
	hide_all()


func _make_sprite(sprite_name: String) -> BossSheetSprite:
	var sprite := BossSheetSprite.new()
	sprite.name = sprite_name
	sprite.folder = FOLDER
	sprite.visible = false
	add_child(sprite, false, Node.INTERNAL_MODE_FRONT)
	return sprite


## Her pose sprite: the hit flash goes on it (matron_ram.gd makes it her `visual`).
func pose_sprite() -> BossSheetSprite:
	return _pose


## Frame `index` of `key`, its picture's bottom `bottom_px` above the floor, mirrored when `flip`;
## with `thread` her thread runs from her top up into the web.
func show_pose(key: String, index: int, bottom_px: float, flip: bool = false, thread: bool = false) -> void:
	if _pose == null:
		return
	_pose.show_frame(key, index, flip)
	_pose.visible = true
	_pose.position = Vector2(0.0, -bottom_px - _pose.below_anchor(key))
	var top := _pose.position.y + _pose.box_of(key).position.y
	_thread_from = top + 6.0 if thread else NAN
	queue_redraw()


func hide_pose() -> void:
	if _pose != null:
		_pose.visible = false
	_thread_from = NAN
	queue_redraw()


## The fallen cocoon (`cocoon`: knocked down whole, straining, torn), its bottom `bottom_px` above the
## floor, `alpha` see-through.
func show_prop(key: String, index: int, bottom_px: float, alpha: float = 1.0) -> void:
	if _prop == null:
		return
	_prop.show_frame(key, index)
	_prop.visible = alpha > 0.0
	_prop.modulate.a = clampf(alpha, 0.0, 1.0)
	_prop.position = Vector2(0.0, -bottom_px - _prop.below_anchor(key))


func hide_prop() -> void:
	if _prop != null:
		_prop.visible = false


## The shadow under something `height_px` above the floor (hidden when `on` is false).
func set_shadow(height_px: float, on: bool = true) -> void:
	if _shadow == null:
		return
	_shadow.visible = on
	var share := clampf(1.0 - height_px / maxf(1.0, shadow_fade_px), shadow_least, 1.0)
	_shadow.size = shadow_size * (0.6 + 0.4 * share)
	_shadow.strength = share


## The top of her pose above the floor (world units, negative up), or her feet when hidden.
func pose_top() -> float:
	if _pose == null or not _pose.visible:
		return 0.0
	return _pose.position.y + _pose.box_of(_pose.current_key()).position.y


## The middle of her pose (a line or a burst rises from it).
func pose_middle() -> Vector2:
	if _pose == null or not _pose.visible:
		return Vector2.ZERO
	var rect := _pose.box_of(_pose.current_key())
	return _pose.position + rect.get_center()


func hide_all() -> void:
	hide_pose()
	hide_prop()
	if _shadow != null:
		_shadow.visible = false


func _draw() -> void:
	if is_nan(_thread_from) or _thread_from <= -thread_top_px:
		return
	draw_line(Vector2(0.0, _thread_from), Vector2(0.0, -thread_top_px), THREAD_COLOR, THREAD_WIDTH, true)
