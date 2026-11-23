extends Node2D
## A lookout tree (Gloop Forest's River Roads, 2026-11-21; docs/design/2026-11-21-gloop-river-roads.md
## "The lookout tree"; the ideas board's treehouses and Breath of the Wild's towers): a giant tree
## whose plank stairs wind up its trunk to a railed deck under the crown.
##
## - **Climb:** at the stairs' foot the interact key offers "Climb the lookout" (group `usable`,
##   interaction_controller.gd). The screen fades, and the slime stands on the deck: its body waits,
##   hidden and still, at the stairs' foot while a copy of its picture stands at `deck_offset`.
## - **The view:** the camera pulls back over the forest (to `view_zoom`, never further than the
##   world's bounds fill the screen), centred `view_offset` from the tree, so the glades around it
##   show; every unopened chest in sight twinkles (a prize glint, game/dungeon/prize_glint.gd).
## - **Down:** any move, interact or attack key climbs back down (the fade again), and the camera
##   follows the slime as before at the zoom it had.
##
## Presentation runs on real time; the slime's movement is held through `suppress_movement` while up.
##
## Owner: world (forest).

const Services := preload("res://game/shared/services.gd")
const AreaTravel := preload("res://game/world/area_travel.gd")
const PrizeGlint := preload("res://game/dungeon/prize_glint.gd")

const USABLE_GROUP := &"usable"
const CHEST_GROUP := &"chest"
const FADE_LAYER := 5
const FADE_MS := 240.0
const ZOOM_MS := 900.0
## Held this long while up (renewed every frame); a climb down lets it go.
const HOLD_MS := 400.0
## Keys are read only after this long up, so the press that climbed does not climb down at once.
const GRACE_MS := 450.0
## After climbing down the tree is not offered for this long (the press that climbed down).
const COOLDOWN_MS := 700.0
const DOWN_KEYS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right", &"interact", &"attack"]
const CUE_CLIMB := &"StairsStep"
const UP_TEXT := "What a view! (any key climbs down)"
const TEXT_RISE := 40.0
const TEXT_MS := 2600.0
const GLINT_LIFT := 40.0

## The stairs' foot, from the tree's root: where the climb is offered and the slime waits.
@export var stairs_foot: Vector2 = Vector2(48, 12)
## Where the slime stands on the deck, from the tree's root (its feet).
@export var deck_offset: Vector2 = Vector2(10, -288)
## The camera's centre while up, from the tree's root.
@export var view_offset: Vector2 = Vector2(0, -260)
## The zoom while up (the world's bounds may hold it closer).
@export var view_zoom: float = 0.5
@export var interact_radius: float = 90.0
@export var badge_rise: float = 64.0

var prompt: String = "Climb the lookout"

var _up := false
var _busy := false
var _since_ms := 0.0
var _until_ms := 0.0
var _zoom_before := 1.0
var _zoom_from := 1.0
var _zoom_to := 1.0
var _zoom_from_ms := -1.0
var _stand_in: Sprite2D
var _glints: Array[Node] = []


func _enter_tree() -> void:
	add_to_group(USABLE_GROUP)


func origin() -> Vector2:
	return global_position + stairs_foot


func can_use() -> bool:
	return not _up and not _busy and float(Time.get_ticks_msec()) >= _until_ms


func use() -> bool:
	if not can_use():
		return false
	var player := _player()
	if player == null:
		return false
	_busy = true
	player.call(&"stop_movement")
	player.call(&"suppress_movement", FADE_MS * 2.0 + HOLD_MS)
	_cue(CUE_CLIMB)
	AreaTravel.fade(_fade_parent(), FADE_LAYER, 0.0, 1.0, FADE_MS, func() -> void:
		_go_up(player)
		AreaTravel.fade(_fade_parent(), FADE_LAYER, 1.0, 0.0, FADE_MS)
	)
	return true


func is_up() -> bool:
	return _up


func _go_up(player: Node) -> void:
	_busy = false
	_up = true
	_since_ms = float(Time.get_ticks_msec())
	var body := player.get(&"body") as Node2D
	var visual := player.get(&"visual") as Sprite2D
	if body != null:
		body.visible = false
	_stand_in = _copy_of(visual)
	if _stand_in != null:
		add_child(_stand_in)
		_stand_in.position = deck_offset + (visual.global_position - body.global_position if body != null else Vector2.ZERO)
		_stand_in.z_index = 1
	var camera := _camera()
	if camera != null:
		_zoom_before = float(camera.get(&"target_zoom"))
		camera.call(&"pan_to", global_position + view_offset, 0.0, false)
		_start_zoom(_zoom_before, _view_zoom(camera))
	_glints = _twinkle_chests()
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(global_position + deck_offset - Vector2(0.0, TEXT_RISE), UP_TEXT, &"white", false, TEXT_MS)
	set_process(true)


func _climb_down() -> void:
	if not _up or _busy:
		return
	_busy = true
	_cue(CUE_CLIMB)
	AreaTravel.fade(_fade_parent(), FADE_LAYER, 0.0, 1.0, FADE_MS, func() -> void:
		_go_down()
		AreaTravel.fade(_fade_parent(), FADE_LAYER, 1.0, 0.0, FADE_MS)
	)


func _go_down() -> void:
	_up = false
	_busy = false
	_until_ms = float(Time.get_ticks_msec()) + COOLDOWN_MS
	_zoom_from_ms = -1.0
	if _stand_in != null and is_instance_valid(_stand_in):
		_stand_in.queue_free()
	_stand_in = null
	for glint: Node in _glints:
		if is_instance_valid(glint):
			glint.queue_free()
	_glints.clear()
	var player := _player()
	var body := player.get(&"body") as Node2D if player != null else null
	if body != null:
		body.visible = true
	var camera := _camera()
	if camera != null:
		camera.call(&"apply_zoom", _zoom_before)
		if body != null:
			camera.call(&"start_follow", body, true)


func _process(_delta: float) -> void:
	if not _up:
		if _zoom_from_ms < 0.0:
			set_process(false)
		return
	var now := float(Time.get_ticks_msec())
	var player := _player()
	if player != null:
		player.call(&"suppress_movement", HOLD_MS)
		var visual := player.get(&"visual") as Sprite2D
		if visual != null and _stand_in != null:
			_stand_in.frame = visual.frame
			_stand_in.flip_h = visual.flip_h
	var camera := _camera()
	if camera != null and _zoom_from_ms >= 0.0:
		var t := clampf((now - _zoom_from_ms) / ZOOM_MS, 0.0, 1.0)
		var eased := t * t * (3.0 - 2.0 * t)
		camera.call(&"apply_zoom", lerpf(_zoom_from, _zoom_to, eased))
		camera.call(&"center_on", global_position + view_offset)
		if t >= 1.0:
			_zoom_from_ms = -1.0
	if _busy or now - _since_ms < GRACE_MS:
		return
	for action: StringName in DOWN_KEYS:
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			_climb_down()
			return


func _start_zoom(from: float, to: float) -> void:
	_zoom_from = from
	_zoom_to = to
	_zoom_from_ms = float(Time.get_ticks_msec())


## `view_zoom`, but never so far out that the screen shows past the world's bounds.
func _view_zoom(camera: Node) -> float:
	var bounds: Rect2 = camera.get(&"bounds")
	var screen := get_viewport_rect().size
	var fit := 0.0
	if bounds.size.x > 0.0 and bounds.size.y > 0.0:
		fit = maxf(screen.x / bounds.size.x, screen.y / bounds.size.y)
	return clampf(maxf(view_zoom, fit), 0.1, 1.0)


## A glint over every unopened chest the view holds (removed when the slime climbs down).
func _twinkle_chests() -> Array[Node]:
	var out: Array[Node] = []
	var camera := _camera()
	var screen := get_viewport_rect().size
	var view := Rect2(global_position + view_offset - screen / (2.0 * _zoom_to), screen / _zoom_to)
	for node: Node in get_tree().get_nodes_in_group(CHEST_GROUP):
		var chest := node.get_parent() as Node2D
		if chest == null or not chest.is_visible_in_tree():
			continue
		if node.has_method(&"is_empty") and bool(node.call(&"is_empty")):
			continue
		if camera != null and not view.has_point(chest.global_position):
			continue
		var glint := Node2D.new()
		glint.set_script(PrizeGlint)
		glint.set(&"lit_strength", 1.0)
		glint.set(&"phase", randf() * 3.0)
		glint.position = Vector2(0.0, -GLINT_LIFT)
		chest.add_child(glint)
		out.append(glint)
	return out


static func _copy_of(visual: Sprite2D) -> Sprite2D:
	if visual == null:
		return null
	var copy := Sprite2D.new()
	copy.name = "SlimeOnDeck"
	copy.texture = visual.texture
	copy.hframes = visual.hframes
	copy.vframes = visual.vframes
	copy.frame = visual.frame
	copy.centered = visual.centered
	copy.offset = visual.offset
	copy.flip_h = visual.flip_h
	copy.scale = visual.scale
	copy.material = visual.material
	return copy


func _player() -> Node:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	return player if player != null and is_instance_valid(player) else null


func _camera() -> Node:
	var world := Services.world()
	var camera: Node = world.get(&"camera") if world != null else null
	return camera if camera != null and is_instance_valid(camera) else null


func _fade_parent() -> Node:
	var tree := get_tree()
	return tree.current_scene if tree.current_scene != null else tree.root


func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)
