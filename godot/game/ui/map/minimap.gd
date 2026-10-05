extends Control
class_name Minimap
## The HUD minimap in the lower-left corner (Phaser `features/ui/MinimapSurfacePort.ts` +
## `ui/minimap.scene.json`; docs/godot/specs/map.md 1 and 3.2). Built by `MapUi` under the HUD
## (CanvasLayer 10, PROCESS_MODE_ALWAYS); takes no mouse input.
##
## Box: `size = clamp(short side · 0.24, 128, 180)` at `margin = clamp(short side · 0.025, 12, 16)`
## from the left and bottom edges, both rounded as Phaser does. Drawn bottom to top:
##   this node's `_draw`: the world's ground (MapTerrain: one pixel per tile, scaled once to the map
##     area with cubic filtering into one ImageTexture; `terrain_alpha`), the 16 % `#182b46` tint and
##     the 1 px `#b9efca` 42 % border;
##   Frame: the organic minimap frame, 6 px outside the box (or Phaser's code-drawn fallback);
##   Overlay: the current world's markers (MapMarkers), the camera view rectangle and the player dot.
## The map (terrain, markers, view) fills the box inset by MAP_INSET px.
##
## Per world: the terrain is baked on `WorldService.world_registered` and dropped when that world's
## root leaves the tree; the minimap is hidden while no world is registered. Redrawn in `_process`
## only when the player point, the camera view, the markers or the box changed.
##
## Owner: map (game/ui/map).

const Services := preload("res://game/shared/services.gd")
const MapMarkers := preload("res://game/ui/map/map_markers.gd")
const MapTerrain := preload("res://game/ui/map/map_terrain.gd")
const WorldCamera := preload("res://game/world/world_camera.gd")

## MinimapSurfacePort.ts:26-28 (and Minimap.ts:6-7).
const SIZE_MIN := 128.0
const SIZE_MAX := 180.0
const SIZE_RATIO := 0.24
const MARGIN_MIN := 12.0
const MARGIN_MAX := 16.0
const MARGIN_RATIO := 0.025
## The frame TextureRect reaches 6 px past the box (minimap.scene.json `offsetMin [-6,-6]`).
const FRAME_OUTSET := 6.0
const FRAME_TEXTURE := "res://asset/UI/ui-organic-minimap-frame.webp"
## [DIFF] The map sits this far inside the box so the frame's vines do not hide the world's edges.
const MAP_INSET := 12.0
## `_process` after the WorldCamera's (100): the view rectangle is the frame's own.
const PROCESS_PRIORITY := 200
## Canvas colours (MinimapSurfacePort.ts:64-108).
const TINT_COLOR := Color(24.0 / 255.0, 43.0 / 255.0, 70.0 / 255.0, 0.16)
const BORDER_COLOR := Color(185.0 / 255.0, 239.0 / 255.0, 202.0 / 255.0, 0.42)
const PLAYER_COLOR := Color("#72d8ff")
const PLAYER_RADIUS := 4.0
const PLAYER_RIM_RADIUS := 5.25
const VIEW_COLOR := Color(136.0 / 255.0, 200.0 / 255.0, 153.0 / 255.0, 0.95)
const VIEW_WIDTH := 1.5
const VIEW_MIN_SIZE := 2.0
## Frame fallback when the texture is missing (Minimap.ts:51-61).
const FALLBACK_FRAME_COLOR := Color(0x9be8b8b8)
const FALLBACK_FRAME_WIDTH := 1.5
const FALLBACK_FRAME_RADIUS := 8

## Opacity of the baked ground. 0 (default) = Phaser's see-through interior: the world shows
## through the 16 % tint, the approved artwork-first HUD (docs/GAME_GUIDELINES.md "UI Style",
## 2026-09-04). Above 0 the world's ground is baked and drawn under the tint ([DIFF], an option for
## the owner); turning it on bakes the current world.
@export_range(0.0, 1.0) var terrain_alpha: float = 0.0:
	set(value):
		var was_off := terrain_alpha <= 0.0
		terrain_alpha = value
		if was_off and value > 0.0 and is_inside_tree() and _world_root != null:
			rebuild()
		queue_redraw()

## The shared markers (set by MapUi before the node enters the tree).
var markers: MapMarkers

var _frame: TextureRect
## The frame art, decoded once per run; `_frame` shows it shrunk to the frame's size with Lanczos
## (the 1254 px painting has no mipmaps, so a plain linear shrink would alias).
static var _frame_source: Image
var _overlay: Control
## The current world's ground, one pixel per tile (MapTerrain.bake), and the texture drawn: that
## image scaled to the map area with cubic filtering (smooth shores, crisp enough at ~2.7 px a tile).
var _terrain_image: Image
var _terrain_texture: ImageTexture
var _world_root: Node
var _map_size := Vector2.ZERO
## Last drawn state: {player, view, markers dirty}.
var _drawn_player := Vector2.INF
var _drawn_view := Rect2()
var _markers_dirty: bool = true


func _init() -> void:
	name = "Minimap"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After the WorldCamera (priority 100), so the view is this frame's.
	process_priority = PROCESS_PRIORITY
	visible = false
	if markers == null:
		markers = MapMarkers.new()
	markers.changed.connect(_on_markers_changed)
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	var world := Services.world()
	if world != null:
		world.world_registered.connect(_on_world_registered)
		if is_instance_valid(world.world_root) and world.world_root.is_inside_tree():
			rebuild()


func _exit_tree() -> void:
	var world := Services.world()
	if world != null and world.world_registered.is_connected(_on_world_registered):
		world.world_registered.disconnect(_on_world_registered)
	_forget_world()


# --- public API ---------------------------------------------------------------------------------

## Adds or moves a marker (MapMarkers.set_marker; docs/godot/specs/map.md 3.3).
func set_marker(id: StringName, world_point: Vector2, kind: StringName = MapMarkers.KIND_WAYPOINT, map_id: String = "") -> void:
	markers.set_marker(id, world_point, kind, map_id)


func clear_marker(id: StringName) -> void:
	markers.clear_marker(id)


func clear_markers() -> void:
	markers.clear_markers()


## The box `(size, margin)` for a viewport of `viewport_size` (MinimapSurfacePort.ts:26-28), with
## Phaser's rounding: Rect2 of the box in viewport pixels.
static func box_for(viewport_size: Vector2) -> Rect2:
	var short_side := minf(viewport_size.x, viewport_size.y)
	var box_size := minf(SIZE_MAX, maxf(SIZE_MIN, short_side * SIZE_RATIO))
	var margin := minf(MARGIN_MAX, maxf(MARGIN_MIN, short_side * MARGIN_RATIO))
	var left := roundf(margin)
	var right := roundf(margin + box_size)
	var top := viewport_size.y - roundf(margin + box_size)
	var bottom := viewport_size.y - roundf(margin)
	return Rect2(left, top, right - left, bottom - top)


## The map area inside the box (local coordinates).
func map_rect() -> Rect2:
	return Rect2(Vector2(MAP_INSET, MAP_INSET), (size - Vector2(MAP_INSET, MAP_INSET) * 2.0).max(Vector2.ONE))


## Local position of a world point (old Phaser space) on the minimap.
func to_map(world_point: Vector2) -> Vector2:
	var area := map_rect()
	var world_size := _world_size()
	if world_size.x <= 0.0 or world_size.y <= 0.0:
		return area.position
	return area.position + world_point / world_size * area.size


## The player point (old Phaser centre) of the last overlay update; INF without a player.
func drawn_player() -> Vector2:
	return _drawn_player


## The camera view (world pixels) of the last overlay update; empty without a camera.
func drawn_view() -> Rect2:
	return _drawn_view


## The baked ground of the current world, one pixel per tile (null when there is none).
func terrain_image() -> Image:
	return _terrain_image


## The ground as drawn: `terrain_image()` scaled to the map area (null when there is none).
func terrain_texture() -> ImageTexture:
	return _terrain_texture


## Rebakes the current world's ground (WorldService.ground_layer) and follows its root.
func rebuild() -> void:
	_forget_world()
	var world := Services.world()
	if world == null or not is_instance_valid(world.world_root):
		visible = false
		return
	_world_root = world.world_root
	_world_root.tree_exiting.connect(_on_world_exiting)
	var dims := world.dimensions()
	if terrain_alpha > 0.0:   # see-through by default: nothing to bake
		_terrain_image = MapTerrain.bake(world.ground_layer, int(dims.get("columns", 0)), int(dims.get("rows", 0)))
	_scale_terrain()
	_map_size = Vector2(float(dims.get("width", 0.0)), float(dims.get("height", 0.0)))
	visible = true
	_markers_dirty = true
	queue_redraw()
	_overlay.queue_redraw()


# --- drawing ------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not visible:
		return
	var player := _player_point()
	var view := _view_rect()
	if _markers_dirty or player != _drawn_player or view != _drawn_view:
		_drawn_player = player
		_drawn_view = view
		_markers_dirty = false
		_overlay.queue_redraw()


func _draw() -> void:
	var area := map_rect()
	if _terrain_texture != null and terrain_alpha > 0.0:
		draw_texture_rect(_terrain_texture, area, false, Color(1.0, 1.0, 1.0, terrain_alpha))
	draw_rect(Rect2(Vector2.ZERO, size), TINT_COLOR)
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), BORDER_COLOR, false, 1.0)
	if _frame.texture == null:
		var pad := clampf(size.x * 0.033, 4.0, 6.0)
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.border_color = FALLBACK_FRAME_COLOR
		box.set_border_width_all(int(ceilf(FALLBACK_FRAME_WIDTH)))
		box.set_corner_radius_all(FALLBACK_FRAME_RADIUS)
		box.anti_aliasing = true
		draw_style_box(box, Rect2(Vector2(-pad, -pad), size + Vector2(pad, pad) * 2.0).grow(-0.75))


func _draw_overlay() -> void:
	var world := Services.world()
	var map_id := world.map_id() if world != null else ""
	for entry: Dictionary in markers.markers_in(map_id):
		MapMarkers.draw_marker(_overlay, to_map(entry["point"]), entry["kind"])
	if _drawn_view.size != Vector2.ZERO:
		var top_left := to_map(_drawn_view.position)
		var bottom_right := to_map(_drawn_view.end)
		var view_size := (bottom_right - top_left).max(Vector2(VIEW_MIN_SIZE, VIEW_MIN_SIZE))
		_overlay.draw_rect(Rect2(top_left, view_size), VIEW_COLOR, false, VIEW_WIDTH, true)
	if _drawn_player.is_finite():
		var at := to_map(_drawn_player)
		_overlay.draw_circle(at, PLAYER_RIM_RADIUS, MapMarkers.RIM_COLOR, true, -1.0, true)
		_overlay.draw_circle(at, PLAYER_RADIUS, PLAYER_COLOR, true, -1.0, true)


# --- internals ----------------------------------------------------------------------------------

func _build() -> void:
	_frame = TextureRect.new()
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: int in [SIDE_LEFT, SIDE_TOP]:
		_frame.set_offset(side, -FRAME_OUTSET)
	for side: int in [SIDE_RIGHT, SIDE_BOTTOM]:
		_frame.set_offset(side, FRAME_OUTSET)
	if ResourceLoader.exists(FRAME_TEXTURE):
		var art := load(FRAME_TEXTURE) as Texture2D
		if _frame_source == null and art != null:
			var image := art.get_image()
			if image != null and not image.is_empty():
				image = image.duplicate() as Image
				if not image.is_compressed() or image.decompress() == OK:
					_frame_source = image
		_frame.texture = art
	add_child(_frame)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## Places the box for the current viewport (Phaser re-publishes it on every resize).
func _layout() -> void:
	if not is_inside_tree():
		return
	var box := box_for(get_viewport().get_visible_rect().size)
	position = box.position
	size = box.size
	_shrink_frame(Vector2i(box.size + Vector2(FRAME_OUTSET, FRAME_OUTSET) * 2.0))
	_scale_terrain()
	_markers_dirty = true
	queue_redraw()


## The drawn ground: `_terrain_image` resized to the map area with cubic filtering.
func _scale_terrain() -> void:
	if _terrain_image == null:
		_terrain_texture = null
		return
	var pixels := Vector2i(map_rect().size.round())
	if _terrain_texture != null and Vector2i(_terrain_texture.get_size()) == pixels:
		return
	var image := _terrain_image.duplicate() as Image
	image.resize(maxi(1, pixels.x), maxi(1, pixels.y), Image.INTERPOLATE_CUBIC)
	_terrain_texture = ImageTexture.create_from_image(image)


## Shows the frame art at exactly `pixels` (redone only when the size changes).
func _shrink_frame(pixels: Vector2i) -> void:
	if _frame_source == null or pixels.x <= 0 or pixels.y <= 0:
		return
	if _frame.texture is ImageTexture and Vector2i(_frame.texture.get_size()) == pixels:
		return
	var image := _frame_source.duplicate() as Image
	image.resize(pixels.x, pixels.y, Image.INTERPOLATE_LANCZOS)
	_frame.texture = ImageTexture.create_from_image(image)


func _world_size() -> Vector2:
	return _map_size


func _player_point() -> Vector2:
	var world := Services.world()
	if world == null or not is_instance_valid(world.player) or not world.player.is_inside_tree():
		return Vector2.INF
	return world.player.get_centre()


## The camera's view in world pixels: `center ± viewport / (2 · zoom)`, the camera without its shake.
func _view_rect() -> Rect2:
	var world := Services.world()
	var camera: WorldCamera = world.camera if world != null else null
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return Rect2()
	var view := camera.get_viewport_rect().size / maxf(camera.target_zoom, 0.000001)
	return Rect2(camera.center - view * 0.5, view)


func _on_world_registered(_payload: Dictionary) -> void:
	rebuild()


func _on_world_exiting() -> void:
	_forget_world()
	visible = false


func _forget_world() -> void:
	if is_instance_valid(_world_root) and _world_root.tree_exiting.is_connected(_on_world_exiting):
		_world_root.tree_exiting.disconnect(_on_world_exiting)
	_world_root = null
	_terrain_image = null
	_terrain_texture = null
	_map_size = Vector2.ZERO
	_drawn_player = Vector2.INF
	_drawn_view = Rect2()


func _on_markers_changed() -> void:
	_markers_dirty = true
