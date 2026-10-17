extends Node2D
## A thing thrown in an arc (the bestiary's Pick Mole's pickaxe, docs/godot/BESTIARY.md "Pick Mole"):
## it flies from the ground point `from` to `to` in `flight_ms` of gameplay time
## (Services.now_ms(): it holds in hit-stop), `arc_px` high at its middle, spinning; a shadow on the
## ground where it will land darkens as it comes (the tell). On landing it calls `on_land(to)`, sticks
## in the ground for `stuck_ms`, then fades and frees itself. It lives under the world's entities,
## so it outlives its thrower; nothing hits it on the way.
##
## The thrower sets the fields, adds it to the tree and calls `start()`.
##
## Owner: enemy builder.

const Services := preload("res://game/shared/services.gd")
const GroundShadowLook := preload("res://game/enemy/ground_shadow.gd")
const SheetSprite := preload("res://game/runtime/sheet_sprite.gd")

const MARK_SIZE := Vector2(16.0, 6.0)
const SHADOW_SIZE := Vector2(9.0, 3.5)
const FADE_MS := 250.0

var from: Vector2 = Vector2.ZERO
var to: Vector2 = Vector2.ZERO
var flight_ms: float = 700.0
var arc_px: float = 80.0
## It leaves from this high over `from` (a hand over a head) and comes down to the ground.
var start_lift_px: float = 0.0
var stuck_ms: float = 500.0
## Turns per second while it flies.
var spin_per_s: float = 2.5
var picture_path: String = ""
var picture_scale: float = 0.5
## How it sticks in the ground (radians).
var stuck_angle: float = 0.7
var on_land: Callable = Callable()

var _started_at: float = -1.0
var _landed_at: float = -1.0
var _sprite: Sprite2D
var _mark: GroundShadowLook
var _shadow: GroundShadowLook


func start() -> void:
	_started_at = Services.now_ms()
	global_position = from
	_shadow = GroundShadowLook.new()
	_shadow.size = SHADOW_SIZE
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.texture = SheetSprite.load_picture(picture_path)
	_sprite.scale = Vector2.ONE * picture_scale
	add_child(_sprite)
	_mark = GroundShadowLook.new()
	_mark.size = MARK_SIZE * 0.5
	_mark.strength = 0.0
	var parent := get_parent()
	if parent != null:
		parent.add_child(_mark)
		_mark.global_position = to


func _exit_tree() -> void:
	if _mark != null and is_instance_valid(_mark):
		_mark.queue_free()
	_mark = null


func _physics_process(_delta: float) -> void:
	if _started_at < 0.0:
		return
	var now := Services.now_ms()
	if _landed_at >= 0.0:
		var since := now - _landed_at
		if since >= stuck_ms:
			modulate.a = clampf(1.0 - (since - stuck_ms) / FADE_MS, 0.0, 1.0)
		if since >= stuck_ms + FADE_MS:
			queue_free()
		return
	var t := clampf((now - _started_at) / maxf(1.0, flight_ms), 0.0, 1.0)
	global_position = from.lerp(to, t)
	var lift := sin(PI * t) * arc_px + (1.0 - t) * start_lift_px
	_sprite.position = Vector2(0.0, -lift - 6.0)
	_sprite.rotation = TAU * spin_per_s * (now - _started_at) / 1000.0
	if _mark != null:
		_mark.strength = t
		_mark.size = MARK_SIZE * lerpf(0.5, 1.0, t)
	if t >= 1.0:
		_land(now)


func _land(now: float) -> void:
	_landed_at = now
	global_position = to
	_sprite.position = Vector2(0.0, -6.0)
	_sprite.rotation = stuck_angle
	if _mark != null and is_instance_valid(_mark):
		_mark.queue_free()
	_mark = null
	if on_land.is_valid():
		on_land.call(to)
