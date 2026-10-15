extends Node
class_name ChunkScroll
## The screen scroll between two chunk worlds of a region, as in Zelda (owner, 2026-10-14): instead
## of a fade to black, the view slides from the old chunk into the next one in the way the player
## walks, and the slime walks in across the edge.
##
## main.gd (`travel_to` for a whole-edge exit inside a region) first takes a picture of the old
## view (`capture`: the world only, without the slime, cut to the old chunk), builds the next chunk,
## lays the picture beside it where the old chunk would lie (`old_offset`) and starts this node.
## Each frame it moves the camera (its bounds off) from the old view, shifted beside the new chunk,
## to the new view, and the slime's body from where it left the old chunk to where it arrives;
## then it frees the picture, gives the camera its bounds back and calls `done`. Real time, like the
## camera: the old world is gone, so nothing in the picture moves.
##
## Owner: world builder.

const WorldCamera := preload("res://game/world/world_camera.gd")

var _camera: WorldCamera
var _body: Node2D
var _picture: Node2D
var _from_centre := Vector2.ZERO
var _to_centre := Vector2.ZERO
var _from_feet := Vector2.ZERO
var _to_feet := Vector2.ZERO
var _ms := 0.0
var _start_ms := -1.0
var _done: Callable


func _init() -> void:
	name = "ChunkScroll"
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Before the camera (process_priority 100), which then keeps the centre set here.
	process_priority = 90


## Starts the scroll: the camera from `from_centre` to `to_centre` (play-area centres, world units),
## `body` from `from_feet` to `to_feet`, over `ms`; `picture` is freed at the end, then `done`
## is called. The clock starts on the first frame this node processes (the frame that built the
## new chunk is long, and must not count).
func start(camera: WorldCamera, body: Node2D, picture: Node2D, from_centre: Vector2, to_centre: Vector2,
		from_feet: Vector2, to_feet: Vector2, ms: float, done: Callable = Callable()) -> void:
	_camera = camera
	_body = body
	_picture = picture
	_from_centre = from_centre
	_to_centre = to_centre
	_from_feet = from_feet
	_to_feet = to_feet
	_ms = maxf(ms, 1.0)
	_done = done
	_camera.stop_follow()
	_camera.use_bounds = false
	_camera.center_on(_from_centre)
	if is_instance_valid(_body):
		_body.global_position = _from_feet
		_body.reset_physics_interpolation()


func _process(_delta: float) -> void:
	var now := float(Time.get_ticks_msec())
	if _start_ms < 0.0:
		_start_ms = now
	var t := clampf((now - _start_ms) / _ms, 0.0, 1.0)
	if is_instance_valid(_camera):
		_camera.center_on(_from_centre.lerp(_to_centre, t))
	if is_instance_valid(_body):
		_body.global_position = _from_feet.lerp(_to_feet, t)
	if t >= 1.0:
		_finish()


func _finish() -> void:
	set_process(false)
	if is_instance_valid(_picture):
		_picture.queue_free()
	if is_instance_valid(_body):
		_body.reset_physics_interpolation()
	if is_instance_valid(_camera):
		_camera.use_bounds = _camera.bounds.size.x > 0.0 and _camera.bounds.size.y > 0.0
		if is_instance_valid(_body):
			_camera.start_follow(_body, false)
	if _done.is_valid():
		_done.call()
	queue_free()


## Renders the world's canvas of `viewport` (its CanvasLayers, the HUD, left out) over `rect` (world
## units) at `zoom`, at the window's pixel density, through a SubViewport under `parent` sharing
## the viewport's World2D; returns the picture two frames later (null when none was drawn). A
## coroutine.
static func capture(parent: Node, viewport: Viewport, rect: Rect2, zoom: float) -> Texture2D:
	var density := viewport.get_final_transform().get_scale().x
	if not is_finite(density) or density <= 0.0:
		density = 1.0
	var scale := zoom * density
	var pixels := Vector2i((rect.size * scale).ceil()).clamp(Vector2i.ONE, Vector2i(8192, 8192))
	var sub := SubViewport.new()
	sub.name = "ChunkScrollCapture"
	sub.world_2d = viewport.world_2d
	sub.size = pixels
	sub.transparent_bg = false
	sub.disable_3d = true
	sub.snap_2d_transforms_to_pixel = viewport.snap_2d_transforms_to_pixel
	sub.snap_2d_vertices_to_pixel = viewport.snap_2d_vertices_to_pixel
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	parent.add_child(sub)
	# After entering the tree: the world's canvas is attached to the SubViewport then.
	sub.canvas_transform = Transform2D(0.0, Vector2(scale, scale), 0.0, -rect.position * scale)
	# Two frames: the SubViewport draws with the next frame; a frame that is not drawn (a hidden
	# window) leaves the picture empty rather than waiting for ever.
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var image := sub.get_texture().get_image()
	sub.queue_free()
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null


## A Sprite2D showing `texture` over `rect` (world units), above everything in the world.
static func picture(texture: Texture2D, rect: Rect2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = "ChunkScrollPicture"
	sprite.texture = texture
	sprite.centered = false
	sprite.position = rect.position
	if texture != null:
		sprite.scale = rect.size / Vector2(texture.get_size())
	sprite.z_as_relative = false
	sprite.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	return sprite


## Where the old chunk's origin lies in the new chunk's coordinates when the player arrives at the
## new chunk's `entry` edge: beside the new chunk on that side (the chunks of a region share their
## grid, so the other axis does not move).
static func old_offset(entry: String, old_rect: Rect2, new_rect: Rect2) -> Vector2:
	match entry:
		"south":
			return Vector2(new_rect.position.x - old_rect.position.x, new_rect.end.y - old_rect.position.y)
		"north":
			return Vector2(new_rect.position.x - old_rect.position.x, new_rect.position.y - old_rect.end.y)
		"west":
			return Vector2(new_rect.position.x - old_rect.end.x, new_rect.position.y - old_rect.position.y)
		_:
			return Vector2(new_rect.end.x - old_rect.position.x, new_rect.position.y - old_rect.position.y)


## The way the player walks when it arrives at the `entry` edge (into the chunk).
static func walk_direction(entry: String) -> Vector2:
	match entry:
		"south":
			return Vector2.UP
		"north":
			return Vector2.DOWN
		"west":
			return Vector2.RIGHT
		_:
			return Vector2.LEFT
