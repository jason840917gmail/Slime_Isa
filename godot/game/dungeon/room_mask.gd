extends CanvasLayer
## Covers everything outside the current room, under fades and the HUD, on every aspect and zoom.
const Services := preload("res://game/shared/services.gd")
const CameraRoom := preload("res://game/world/camera_room.gd")
const MASK_SHADER := preload("res://game/dungeon/room_mask.gdshader")
const MAX_POINTS := 64
var _cover: ColorRect
var _material: ShaderMaterial

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
