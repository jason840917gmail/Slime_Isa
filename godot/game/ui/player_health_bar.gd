extends Control
class_name PlayerHealthBar
## Floating 56 x 8 player health bar (Phaser `ui.health-bar` + `PlayerHealthSurfacePort.ts:9-57`).
## World spec 6.3. Child of the HUD CanvasLayer; draws itself in screen space.
##
## Visible for SHOW_MS of real time after any `health_changed`; hidden while the player is dead.
## Each frame: anchor = player old Phaser position + (0, -48); screen = canvas transform * anchor;
## rect (round(screen.x - 28), round(screen.y - 4), 56, 8). Fill tone: ratio <= 0.25 danger
## #ff6f88, <= 0.5 warning #ffd277, else accent #86f0c3; background #182b46, border 1 px
## #3b5c78 at 68 % alpha, corner radius 4. mouse_filter IGNORE, PROCESS_MODE_ALWAYS.
## The player position is the one drawn this frame (the camera's interpolated follow point) and
## the screen mapping uses the camera's state of this frame (process_priority after the camera).
##
## Owner: world builder.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")
const PlayerScript := preload("res://game/scripts/player.gd")
const WorldCamera := preload("res://game/world/world_camera.gd")

const SHOW_MS := 1800.0
const SIZE := Vector2(56.0, 8.0)
const RISE_PX := 48.0
const TONE_DANGER := Color("#ff6f88")
const TONE_WARNING := Color("#ffd277")
const TONE_ACCENT := Color("#86f0c3")
const BACKGROUND_COLOR := Color("#182b46")
const BORDER_COLOR := Color(59.0 / 255.0, 92.0 / 255.0, 120.0 / 255.0, 0.68)
const CORNER_RADIUS := 4
const DANGER_RATIO := 0.25
const WARNING_RATIO := 0.5

var _player: PlayerScript
var _visible_until_ms: float = 0.0
var _hp: float = 0.0
var _max_hp: float = 1.0
var _background_box: StyleBoxFlat
var _fill_box: StyleBoxFlat


## mouse_filter IGNORE, PROCESS_MODE_ALWAYS, hidden.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After the WorldCamera (100) so this frame's camera centre is used.
	process_priority = 200
	size = SIZE
	visible = false
	_background_box = StyleBoxFlat.new()
	_background_box.bg_color = BACKGROUND_COLOR
	_background_box.border_color = BORDER_COLOR
	_background_box.set_border_width_all(1)
	_background_box.set_corner_radius_all(CORNER_RADIUS)
	_fill_box = StyleBoxFlat.new()
	_fill_box.bg_color = TONE_ACCENT
	_fill_box.set_corner_radius_all(CORNER_RADIUS - 1)


## Follows `player`; connects `health_changed` to `show_for_a_while()`.
func bind_player(player: PlayerScript) -> void:
	if _player != null and is_instance_valid(_player) and _player.health_changed.is_connected(show_for_a_while):
		_player.health_changed.disconnect(show_for_a_while)
	_player = player
	if player == null:
		visible = false
		return
	_hp = float(player.get_hp())
	_max_hp = float(player.get_max_hp())
	player.health_changed.connect(show_for_a_while)


## Makes the bar visible for SHOW_MS from now (real time, Time.get_ticks_msec()).
func show_for_a_while(payload: Dictionary = {}) -> void:
	if payload.has("hp"):
		_hp = float(payload["hp"])
	if payload.has("maxHp"):
		_max_hp = float(payload["maxHp"])
	_visible_until_ms = float(Time.get_ticks_msec()) + SHOW_MS
	queue_redraw()


## Positions the bar over the player and hides it when the time ran out or the player is dead.
func _process(_delta: float) -> void:
	var now := float(Time.get_ticks_msec())
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree() \
			or _player.is_dead() or now >= _visible_until_ms:
		visible = false
		return
	var screen := _anchor_screen_position()
	position = Vector2(roundf(screen.x - SIZE.x * 0.5), roundf(screen.y - SIZE.y * 0.5))
	if not visible:
		visible = true
		queue_redraw()


## Draws background, fill and border.
func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, SIZE)
	var ratio := clampf(_hp / maxf(1.0, _max_hp), 0.0, 1.0)
	var tone := TONE_ACCENT
	if ratio <= DANGER_RATIO:
		tone = TONE_DANGER
	elif ratio <= WARNING_RATIO:
		tone = TONE_WARNING
	_fill_box.bg_color = tone
	_background_box.draw(get_canvas_item(), rect)
	if ratio > 0.0:
		var inner := rect.grow(-1.0)
		_fill_box.draw(get_canvas_item(), Rect2(inner.position, Vector2(inner.size.x * ratio, inner.size.y)))
	# Border on top of the fill.
	var border := _background_box.duplicate() as StyleBoxFlat
	border.draw_center = false
	border.draw(get_canvas_item(), rect)


## Screen position of (player old Phaser position + (0, -48)).
func _anchor_screen_position() -> Vector2:
	var body := _player.get_parent() as Node2D
	if _player.body != null:
		body = _player.body
	var camera := Services.world().camera if Services.world() != null else null
	var feet: Vector2 = body.global_position if body != null else Vector2.ZERO
	if camera != null and is_instance_valid(camera) and camera.follow_target == body:
		feet = camera.get_target_draw_position()
	var anchor := feet - FeetAnchor.depth_anchor(body) * (body.global_scale if body != null else Vector2.ONE)
	anchor.y -= RISE_PX
	if camera != null and is_instance_valid(camera):
		return camera.world_to_screen(anchor)
	return get_viewport().get_canvas_transform() * anchor
