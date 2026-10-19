extends CanvasLayer
## Covers everything outside the current room, under fades and the HUD, on every aspect and zoom.
const Services := preload("res://game/shared/services.gd")
const CameraRoom := preload("res://game/world/camera_room.gd")
const MASK_SHADER := preload("res://game/dungeon/room_mask.gdshader")
const MAX_POINTS := 64
var _cover: ColorRect
var _material: ShaderMaterial
var _wall_frames: Array[Sprite2D] = []

func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 200
	_material = ShaderMaterial.new()
	_material.shader = MASK_SHADER
	_cover = ColorRect.new()
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.material = _material
	add_child(_cover)
	var world := Services.world()
	for node: Node in world.world_root.find_children("WallDoorway", "Sprite2D", true, false):
		var parent := node.get_parent()
		if parent.has_method(&"is_open") or parent.has_method(&"is_shut") or parent.has_method(&"is_smashed") or parent.has_node("GateScript"):
			_wall_frames.append(node as Sprite2D)

func _process(_delta: float) -> void:
	var world := Services.world()
	var camera: Node = world.camera if world != null else null
	if camera == null or not is_instance_valid(camera):
		_cover.visible = false
		return
	var current := _active_room(camera)
	_cover.visible = current != null
	if current == null:
		return
	var size := get_viewport().get_visible_rect().size
	_cover.size = size
	var points := PackedVector2Array()
	for point: Vector2 in current.outline_global():
		points.append((camera.call(&"world_to_screen", point) as Vector2) / size)
	var count := mini(points.size(), MAX_POINTS)
	while points.size() < MAX_POINTS:
		points.append(Vector2.ZERO)
	_material.set_shader_parameter(&"outline", points)
	_material.set_shader_parameter(&"point_count", count)
	var frames := PackedVector4Array()
	# a room with interior walls (wall_bands off, docs/godot/INTERIOR_WALLS.md) shows no frame of
	# its neighbours' old doorways past its edge
	var own_walls: bool = current.get_meta(&"wall_bands", true) == false
	for frame: Sprite2D in ([] as Array[Sprite2D]) if own_walls else _wall_frames:
		if not is_instance_valid(frame) or not _anchor_near_room_edge(current, frame.global_position):
			continue
		var bounds := _frame_bounds(frame)
		var a: Vector2 = camera.call(&"world_to_screen", bounds.position)
		var b: Vector2 = camera.call(&"world_to_screen", bounds.end)
		frames.append(Vector4(a.x / size.x, a.y / size.y, b.x / size.x, b.y / size.y))
	var frame_count := mini(frames.size(), 16)
	frames.resize(16)
	_material.set_shader_parameter(&"wall_frames", frames)
	_material.set_shader_parameter(&"frame_count", frame_count)

func _frame_bounds(frame: Sprite2D) -> Rect2:
	var local := frame.get_rect()
	var bounds := Rect2(frame.to_global(local.position), Vector2.ZERO)
	for corner: Vector2 in [local.position, Vector2(local.end.x, local.position.y), local.end, Vector2(local.position.x, local.end.y)]:
		bounds = bounds.expand(frame.to_global(corner))
	return bounds


func _anchor_near_room_edge(room: CameraRoom, point: Vector2) -> bool:
	var points := room.outline_global()
	for i in points.size():
		var a := points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)) <= 32.0:
			return true
	return false

func _active_room(camera: Node) -> CameraRoom:
	var rect: Rect2 = camera.get(&"room")
	for node: Node in get_tree().get_nodes_in_group(CameraRoom.GROUP):
		if not node is CameraRoom or not Services.world().world_root.is_ancestor_of(node):
			continue
		var room := node as CameraRoom
		if rect.has_area() and room.rect() == rect:
			return room
		if not rect.has_area() and room.contains(camera.get(&"center")):
			return room
	return null

