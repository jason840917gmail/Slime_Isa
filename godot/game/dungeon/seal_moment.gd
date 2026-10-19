extends Node
class_name SealMoment
## The Pearl's take, after its card (docs/godot/DUNGEONS.md "The seal"; the plan
## docs/design/2026-10-17-pearl-mid-dungeon.md "The roar", "The glimpse"). Made by
## `Dungeon.seal_now` (the seal itself is DungeonState's, set at the take); presentation only, on
## real time. It waits until the world runs again (the Pearl's card closed), then:
##
## 1. **The roar:** the boss's roar (the Dungeon's `roar_sound`), a hard shake, dust falling over
##    the screen in the Dungeon's `dust_color`, and one line over the slime:
##    "<boss> roars! The way out slams shut." (`Dungeon.roar_text`).
##    In a dungeon of one world per room (Fatty's Lair) the entrance's seal is in another world: the
##    glimpse is then the Dungeon's `glimpse_pictures`, made in advance (the doorway open, then the
##    seal up), shown full screen over the paused world for `glimpseMs`, the second from
##    `glimpseSlamMs` with the boom (owner, 2026-10-18).
## 2. **The glimpse**, `dungeon.seal.glimpseDelayMs` after the roar: the world pauses and the view
##    cuts to the entrance's seal (`target`: Dungeon.glimpse_seal) for `glimpseMs` (1.5 s); the seal
##    slams up out of its doorway `glimpseSlamMs` in, with a boom, and glows; then the view cuts back
##    to the slime and the world goes on. With no seal in this world (the entrance on another floor:
##    the line and the minimap's red mark tell it) or with the seal in view already, there is no cut
##    (the seal slams where it stands).
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

const PAUSE_REASON := &"seal-glimpse"
## AbilityCeremony.NODE_NAME.
const CEREMONY_NODE := "AbilityCeremony"
## Above the skin's own ceremony lines (SkinState.ceremony_line: 64 and 36 over the slime).
const TEXT_RISE := 112.0
const TEXT_MS := 2800.0
## The dust draws over the world (a dark room's darkness is z 45).
const DUST_Z := 50
const DUST_LIFETIME_S := 1.9
const DUST_TEXTURE_PX := 24

enum Step { WAIT, ROAR, GLIMPSE, PICTURE }

## Over the world, the HUD and the dust (the arrival fade is 5, the HUD 10).
const PICTURE_LAYER := 20
const CUE_SLAM := &"SlamImpact"

## The Dungeon node that sealed (dungeon.gd).
var dungeon: Node2D
## The seal the glimpse shows (dungeon_seal.gd), or null.
var target: Node2D

var _step := Step.WAIT
var _at_ms := 0.0
var _slammed := false
var _cut := false
var _follow: Node2D
## The picture glimpse's layer and its picture (null when none shows).
var _picture_layer: CanvasLayer
var _picture: TextureRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	_end_cut()
	_end_picture()


## True while the view shows the entrance's seal.
func is_glimpsing() -> bool:
	return _cut


func _process(_delta: float) -> void:
	var now := float(Time.get_ticks_msec())
	match _step:
		Step.WAIT:
			# The Pearl's card first (queued this frame, it pauses the world once it starts), or any
			# other pause.
			if get_tree().paused or _ceremony_busy():
				return
			_roar()
			_step = Step.ROAR
			_at_ms = now
		Step.ROAR:
			if now - _at_ms < DungeonState.number("seal.glimpseDelayMs", 600.0):
				return
			if target == null or not is_instance_valid(target) or not target.is_inside_tree():
				if _start_picture():
					_step = Step.PICTURE
					_at_ms = now
					return
				queue_free()
				return
			_cut = _start_cut()
			if not _cut:
				target.call(&"slam")
				queue_free()
				return
			_step = Step.GLIMPSE
			_at_ms = now
		Step.GLIMPSE:
			if not _slammed and now - _at_ms >= DungeonState.number("seal.glimpseSlamMs", 350.0):
				_slammed = true
				if is_instance_valid(target):
					target.call(&"slam")
			if now - _at_ms >= DungeonState.number("seal.glimpseMs", 1500.0):
				_end_cut()
				queue_free()
		Step.PICTURE:
			var pictures: Array = dungeon.get(&"glimpse_pictures") if is_instance_valid(dungeon) else []
			if not _slammed and now - _at_ms >= DungeonState.number("seal.glimpseSlamMs", 350.0):
				_slammed = true
				if pictures.size() > 1 and _picture != null:
					_picture.texture = pictures[1]
				var feel := Services.feel()
				if feel != null:
					feel.audio_cue(CUE_SLAM)
					feel.shake(DungeonState.number("seal.slamShakeMs", 420.0), DungeonState.number("seal.slamShakeIntensity", 0.01))
			if now - _at_ms >= DungeonState.number("seal.glimpseMs", 1500.0):
				_end_picture()
				queue_free()


## True while the picture glimpse shows.
func is_showing_picture() -> bool:
	return _picture_layer != null and is_instance_valid(_picture_layer)


## The picture glimpse (the entrance's seal in another world): false without pictures.
func _start_picture() -> bool:
	if dungeon == null or not is_instance_valid(dungeon) or not &"glimpse_pictures" in dungeon:
		return false
	var pictures: Array = dungeon.get(&"glimpse_pictures")
	if pictures.is_empty() or not pictures[0] is Texture2D:
		return false
	_picture_layer = CanvasLayer.new()
	_picture_layer.name = "SealGlimpse"
	_picture_layer.layer = PICTURE_LAYER
	_picture_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture_layer.add_child(back)
	_picture = TextureRect.new()
	_picture.texture = pictures[0]
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture_layer.add_child(_picture)
	add_child(_picture_layer)
	var world := Services.world()
	if world != null:
		world.set_pause_reason(PAUSE_REASON, true)
	return true


func _end_picture() -> void:
	if _picture_layer == null:
		return
	if is_instance_valid(_picture_layer):
		_picture_layer.queue_free()
	_picture_layer = null
	_picture = null
	var world := Services.world()
	if world != null:
		world.set_pause_reason(PAUSE_REASON, false)


## True while the ceremony (game/ui/ceremony/ability_ceremony.gd, under the tree's root) plays a
## card or has one waiting.
func _ceremony_busy() -> bool:
	var ceremony := get_tree().root.get_node_or_null(CEREMONY_NODE)
	if ceremony == null:
		return false
	return bool(ceremony.call(&"is_playing")) or int(ceremony.call(&"waiting")) > 0


func _roar() -> void:
	if dungeon == null or not is_instance_valid(dungeon):
		return
	dungeon.call(&"play_roar")
	var feel := Services.feel()
	var world := Services.world()
	if feel != null:
		feel.shake(DungeonState.number("seal.roarShakeMs", 700.0), DungeonState.number("seal.roarShakeIntensity", 0.012))
		if world != null and world.player != null and is_instance_valid(world.player):
			feel.floating_text(world.player.get_centre() - Vector2(0.0, TEXT_RISE), str(dungeon.call(&"roar_text")),
				&"red", true, TEXT_MS)
	dust(dungeon, dungeon.get(&"dust_color"), int(DungeonState.number("seal.roarDust", 90.0)))


## The cut to the target's room: false (no cut) without a camera or with the target in view.
func _start_cut() -> bool:
	var world := Services.world()
	var camera: Camera2D = world.camera if world != null else null
	if camera == null or not is_instance_valid(camera) or not camera.has_method(&"release_room"):
		return false
	var view: Rect2 = camera.call(&"view_rect")
	if view.grow(-32.0).has_point(target.global_position):
		return false
	_follow = camera.get(&"follow_target")
	world.set_pause_reason(PAUSE_REASON, true)
	target.process_mode = Node.PROCESS_MODE_ALWAYS
	camera.call(&"release_room")
	camera.call(&"pan_to", _view_point(camera, view.size), 0.0, false)
	return true


## Where the view centres to show the target: inside its camera room (the room's middle on an axis
## where the room is no bigger than the view).
func _view_point(camera: Camera2D, view: Vector2) -> Vector2:
	var at := target.global_position
	var room: Rect2 = camera.call(&"room_at", at)
	if not room.has_area() or not room.has_point(at):
		return at
	var half := view * 0.5
	var point := at
	point.x = room.get_center().x if room.size.x <= view.x else clampf(at.x, room.position.x + half.x, room.end.x - half.x)
	point.y = room.get_center().y if room.size.y <= view.y else clampf(at.y, room.position.y + half.y, room.end.y - half.y)
	return point


func _end_cut() -> void:
	if not _cut:
		return
	_cut = false
	var world := Services.world()
	if world != null:
		world.set_pause_reason(PAUSE_REASON, false)
		var camera: Camera2D = world.camera
		if camera != null and is_instance_valid(camera) and _follow != null and is_instance_valid(_follow):
			camera.call(&"start_follow", _follow, true)
	if target != null and is_instance_valid(target):
		target.process_mode = Node.PROCESS_MODE_INHERIT


## Dust falling over the view (the roar's, and a little with a distant one): `count` soft motes of
## `color` over the camera's view, under `owner`'s world. Presentation only.
static func dust(owner: Node, color: Color, count: int) -> void:
	if owner == null or not owner.is_inside_tree() or count <= 0:
		return
	var world := Services.world()
	var camera: Camera2D = world.camera if world != null else null
	var view := Rect2((owner as Node2D).global_position - Vector2(512.0, 448.0), Vector2(1024.0, 896.0)) if owner is Node2D else Rect2()
	if camera != null and is_instance_valid(camera) and camera.has_method(&"view_rect"):
		view = camera.call(&"view_rect")
	var parent: Node = world.world_root if world != null and world.world_root != null else owner
	var particles := CPUParticles2D.new()
	particles.name = "SealDust"
	particles.process_mode = Node.PROCESS_MODE_ALWAYS
	particles.z_as_relative = false
	particles.z_index = DUST_Z
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = DUST_LIFETIME_S
	particles.explosiveness = 0.25
	particles.randomness = 0.6
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = view.size * Vector2(0.5, 0.45)
	particles.direction = Vector2.DOWN
	particles.spread = 18.0
	particles.gravity = Vector2(0.0, 160.0)
	particles.initial_velocity_min = 20.0
	particles.initial_velocity_max = 70.0
	particles.angular_velocity_min = -90.0
	particles.angular_velocity_max = 90.0
	particles.scale_amount_min = 0.45
	particles.scale_amount_max = 1.4
	particles.texture = _mote_texture()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color, 0.0))
	ramp.set_color(1, Color(color, 0.0))
	ramp.add_point(0.12, Color(color, 1.0))
	ramp.add_point(0.75, Color(color, 0.85))
	particles.color_ramp = ramp
	parent.add_child(particles)
	particles.global_position = view.get_center()
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


static func _mote_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.45, Color(1, 1, 1, 0.85))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = DUST_TEXTURE_PX
	texture.height = DUST_TEXTURE_PX
	return texture
