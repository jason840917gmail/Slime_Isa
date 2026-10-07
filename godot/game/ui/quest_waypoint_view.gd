extends Node2D
## The quest waypoint (Phaser `features/quests/QuestWaypointPresenter.ts` driven by
## `WorldScene.updateQuestWaypoint`; quests spec 4.6 and 10.7): while the quest tracker shows the
## way (a click on a tracked quest), a gold pin bobs over the place the tracked quest wants next,
## with its label while the place is on screen, and a gold chevron circles the slime toward it
## with the distance in metres (one metre = one 64 px tile) while it is off screen.
##
## Child "QuestWaypoint" of main in world space, `z_index = 2` (above the markers and the world),
## made once and kept across worlds. The target is resolved (res://game/quests/quest_waypoint.gd)
## every 250 ms of play from the player's centre and reported to the tracker
## (`set_waypoint_found`). Hidden while the game is paused or the waypoint is off. The target is
## also a "waypoint" marker on the minimap and world map (`MapUi.set_marker`, group "map_ui").
##
## Owner: quests.

const Services := preload("res://game/shared/services.gd")
const QuestWaypoint := preload("res://game/quests/quest_waypoint.gd")

const GROUP := &"quest_waypoint"
const TRACKER_GROUP := &"quest_tracker"
const MAP_UI_GROUP := &"map_ui"
const MAP_MARKER_ID := &"quest-waypoint"
const RESOLVE_MS := 250.0
const ARROW_RADIUS := 72.0
const ARROW_LIFT := 16.0
const DISTANCE_GAP := 30.0
const PIXELS_PER_METRE := 64.0
const VIEW_INSET := 48.0
const MARKER_RISE := 58.0
const LABEL_RISE := 86.0
const GOLD := Color("#ffd277")
const INK := Color("#081022")
const TEXT_COLOR := Color("#ffe8a8")
const TEXT_OUTLINE := 4

## {"position": Vector2, "label": String} or {} (nothing to point at).
var _target: Dictionary = {}
var _elapsed_ms: float = 0.0
var _next_resolve_ms: float = 0.0
var _marker_at: Vector2 = Vector2.ZERO
var _marker_alpha: float = 1.0
var _marker_visible: bool = false
var _arrow_at: Vector2 = Vector2.ZERO
var _arrow_angle: float = 0.0
var _arrow_visible: bool = false
var _label: Label
var _distance: Label
## The map marker currently shown (Vector2.INF = none).
var _map_marker: Vector2 = Vector2.INF


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 2
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = _make_text(13)
	_distance = _make_text(12)


func _process(delta: float) -> void:
	var tracker := get_tree().get_first_node_in_group(TRACKER_GROUP)
	var world := Services.world()
	var player: Variant = world.player if world != null else null
	var showing := tracker != null and bool(tracker.call(&"showing_way"))
	if not showing or player == null or not is_instance_valid(player) or not (player as Node).is_inside_tree():
		_target = {}
		_hide()
		_sync_map_marker()
		return
	if get_tree().paused:
		_hide()
		return
	_elapsed_ms += delta * 1000.0
	var from: Vector2 = (player as Node).call(&"get_centre")
	if _elapsed_ms >= _next_resolve_ms:
		_next_resolve_ms = _elapsed_ms + RESOLVE_MS
		var quest: Dictionary = tracker.call(&"waypoint_quest")
		_target = QuestWaypoint.resolve(quest, from)
		tracker.call(&"set_waypoint_found", not _target.is_empty())
		_sync_map_marker()
	_update(from)


## The current target ({} when none).
func target() -> Dictionary:
	return _target


## World teardown: forget the target (the next world resolves its own).
func clear() -> void:
	_target = {}
	_next_resolve_ms = 0.0
	_hide()
	_sync_map_marker()


## The target as the maps' "waypoint" marker (removed when there is none).
func _sync_map_marker() -> void:
	var point: Vector2 = _target["position"] if not _target.is_empty() else Vector2.INF
	if point == _map_marker:
		return
	var map_ui := get_tree().get_first_node_in_group(MAP_UI_GROUP) if is_inside_tree() else null
	if map_ui == null:
		return
	if point == Vector2.INF:
		if map_ui.has_method(&"clear_marker"):
			map_ui.call(&"clear_marker", MAP_MARKER_ID)
	elif map_ui.has_method(&"set_marker"):
		map_ui.call(&"set_marker", MAP_MARKER_ID, point)
	_map_marker = point


func is_showing_marker() -> bool:
	return _marker_visible


func is_showing_arrow() -> bool:
	return _arrow_visible


func _update(player: Vector2) -> void:
	if _target.is_empty():
		_hide()
		return
	var at: Vector2 = _target["position"]
	var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()
	var inset := view.grow(-VIEW_INSET)
	var on_screen := at.x > inset.position.x and at.x < inset.end.x and at.y > inset.position.y and at.y < inset.end.y
	var pulse := 0.5 + 0.5 * sin(_elapsed_ms / 220.0)
	var bob := sin(_elapsed_ms / 260.0) * 5.0
	_marker_visible = true
	_marker_at = Vector2(at.x, at.y - MARKER_RISE + bob)
	_marker_alpha = 0.8 + 0.2 * pulse
	_label.visible = on_screen
	if on_screen:
		_label.text = str(_target.get("label", ""))
		_label.reset_size()
		_label.position = Vector2(at.x - _label.size.x / 2.0, at.y - LABEL_RISE + bob - _label.size.y)
	var offset := at - player
	var metres := roundi(offset.length() / PIXELS_PER_METRE)
	_arrow_visible = not on_screen and metres > 1
	_distance.visible = _arrow_visible
	if _arrow_visible:
		_arrow_angle = offset.angle()
		var radius := ARROW_RADIUS + pulse * 6.0
		var direction := Vector2.from_angle(_arrow_angle)
		_arrow_at = player + direction * radius - Vector2(0.0, ARROW_LIFT)
		_distance.text = "%d m" % metres
		_distance.reset_size()
		var centre := player + direction * (radius + DISTANCE_GAP) - Vector2(0.0, ARROW_LIFT)
		_distance.position = centre - _distance.size / 2.0
	queue_redraw()


func _hide() -> void:
	if not _marker_visible and not _arrow_visible and not _label.visible and not _distance.visible:
		return
	_marker_visible = false
	_arrow_visible = false
	_label.visible = false
	_distance.visible = false
	queue_redraw()


func _draw() -> void:
	if _marker_visible:
		_draw_marker(_marker_at, _marker_alpha)
	if _arrow_visible:
		draw_set_transform(_arrow_at, _arrow_angle, Vector2.ONE)
		_draw_arrow()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A downward pin: a ring with a point below (QuestWaypointPresenter.drawMarker).
func _draw_marker(at: Vector2, alpha: float) -> void:
	draw_circle(at, 13.0, Color(INK, 0.85 * alpha))
	draw_colored_polygon(PackedVector2Array([at + Vector2(-9, 7), at + Vector2(9, 7), at + Vector2(0, 24)]), Color(INK, 0.85 * alpha))
	draw_circle(at, 10.0, Color(GOLD, alpha))
	draw_colored_polygon(PackedVector2Array([at + Vector2(-6, 6), at + Vector2(6, 6), at + Vector2(0, 20)]), Color(GOLD, alpha))
	draw_circle(at, 4.0, Color(INK, alpha))


## A chevron pointing along +x (QuestWaypointPresenter.drawArrow).
func _draw_arrow() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(20, 0), Vector2(-12, -15), Vector2(-12, 15)]), Color(INK, 0.85))
	draw_colored_polygon(PackedVector2Array([Vector2(16, 0), Vector2(-9, -11), Vector2(-9, 11)]), GOLD)
	draw_colored_polygon(PackedVector2Array([Vector2(-1, 0), Vector2(-10, -6), Vector2(-10, 6)]), Color(INK, 0.9))


func _make_text(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", TEXT_COLOR)
	label.add_theme_constant_override(&"outline_size", TEXT_OUTLINE)
	label.add_theme_color_override(&"font_outline_color", INK)
	label.visible = false
	add_child(label)
	return label
