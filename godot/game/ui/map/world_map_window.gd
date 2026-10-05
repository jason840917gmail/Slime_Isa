extends Control
class_name WorldMapWindow
## The world map window (Phaser `features/ui/WorldMapSurfacePort.ts` + `ui/world-map-ui.scene.json`;
## docs/godot/specs/map.md 2 and 3.4): which areas the run has discovered, the current one and the
## ways between them, on a centred `WindowPanel` (620 x 340, at most the viewport minus 32 px).
## Scene: res://game/ui/map/world_map_window.tscn (Godot-owned), group "world_map".
##
## A game window: `MapUi` hands it to GameWindows (game/ui/screens/game_windows.gd, main's
## CanvasLayer 40) with `add_window`; `open()` pushes it there as surface `world-map` (the `modal`
## pause, the MenuOpen cue, `window_opened(&"world-map")`) and `close()` pops it. GameWindows'
## Escape calls `close()`. While open, `_input` closes it on the `map` and `menu` keys.
##
## The Chart control draws the area discs, the links between discovered neighbours and the marker
## badges (MapMarkers), since the UI font has no `◉ ● ━` glyphs.
##
## Owner: map (game/ui/map).

const Services := preload("res://game/shared/services.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const AreaTitles := preload("res://game/shell/area_titles.gd")
const MapMarkers := preload("res://game/ui/map/map_markers.gd")

## Opened / closed (after the GameWindows push / pop).
signal opened
signal closed

## The GameWindows surface id (the quests session maps it to `menu:map`).
const SURFACE_ID := &"world-map"
const GROUP := &"world_map"
const GAME_WINDOWS_GROUP := &"game_windows"
const WORLD_MAIN_GROUP := &"world_main"
## WorldMapSurfacePort.ts:57-58.
const PANEL_MAX := Vector2(620.0, 340.0)
const VIEWPORT_MARGIN := 32.0
## Area labels: 15 px, 10 px at <= 520 px (styles.css:3681-3683).
const AREA_FONT_SIZE := 15
const AREA_FONT_SIZE_NARROW := 10
const NARROW_WIDTH := 520.0
## The columns, by `mapX` (world/Area.ts:24-72): area id -> label node.
const AREA_ORDER: PackedStringArray = ["icege", "level-1", "gloop-forest", "crystal-caverns"]
const AREA_LABELS := {
	"icege": ^"Panel/Icege",
	"level-1": ^"Panel/Level1",
	"gloop-forest": ^"Panel/GloopForest",
	"crystal-caverns": ^"Panel/CrystalCaverns",
}
## Neighbours shown as links when both ends are discovered (WorldMapSurfacePort.ts:72-73).
const LINKS := [["level-1", "gloop-forest"], ["gloop-forest", "crystal-caverns"]]
const UNKNOWN_TEXT := "Unknown"
const CURRENT_TEXT := "Current area"
const SUMMARY_FORMAT := "%d discovered · Areas stay marked as you travel"
## Chart geometry: the disc centre sits DISC_DROP px below the top of the label column
## (anchors y 0.34); the label starts LABEL_DROP px below it.
const COLUMN_TOP_RATIO := 0.34
const DISC_DROP := 22.0
const DISC_RADIUS := 12.0
const DISC_RIM := 1.5
const CURRENT_RING_RADIUS := 17.0
const CURRENT_RING_WIDTH := 2.5
const UNKNOWN_FILL := UiTokens.SURFACE_INSET
const UNKNOWN_RING := Color(UiTokens.BORDER, 0.9)
## Link colours (legacy WorldMapUI.ts:112-115).
const LINK_UNDER := Color(UiTokens.BORDER, 0.95)
const LINK_UNDER_WIDTH := 4.0
const LINK_OVER := Color(UiTokens.ACCENT, 0.55)
const LINK_OVER_WIDTH := 1.5
const CURRENT_RING := UiTokens.WARNING
## The waypoint badge: the minimap pin at 1.5x, its tip this far from the disc centre.
const BADGE_OFFSET := Vector2(19.0, -11.0)
const BADGE_SCALE := 1.5
## The pin's teardrop on the dark panel: a deep gold instead of the minimap's ink.
const BADGE_RIM := Color("#b9822e")
## Close button: radius 6 (`.game-ui--world-map-ui .scene-control--button`).
const BUTTON_RADIUS := 6

## The shared markers (MapUi sets it; a lone window makes its own).
var markers: MapMarkers

@onready var panel: Control = $Panel
@onready var chart: Control = $Panel/Chart
@onready var title_label: Label = $Panel/Title
@onready var summary_label: Label = $Panel/Summary
@onready var close_button: Button = $Panel/Close

var _open: bool = false
var _game_windows: Node


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if markers == null:
		markers = MapMarkers.new()
	markers.changed.connect(_on_markers_changed)
	chart.draw.connect(_draw_chart)
	close_button.pressed.connect(_on_close_pressed)
	_style_close_button()
	get_viewport().size_changed.connect(_layout)
	_layout()
	refresh()


func _exit_tree() -> void:
	close()


# --- public API ---------------------------------------------------------------------------------

func is_open() -> bool:
	return _open


## Opens the window (WorldMapSurfacePort.open): marks the current world discovered, refreshes,
## shows it, focuses Close and pushes it to GameWindows. False without GameWindows or a world.
## True when already open.
func open() -> bool:
	if _open:
		return true
	var windows := game_windows()
	var world := Services.world()
	if windows == null or world == null or not is_instance_valid(world.world_root):
		return false
	if get_parent() == null:
		windows.call(&"add_window", self)
	var run := Services.run()
	if run != null and not world.map_id().is_empty():
		run.mark_area_discovered(world.map_id())
	_open = true
	_layout()
	refresh()
	visible = true
	windows.call(&"push", self, SURFACE_ID)
	opened.emit()
	close_button.grab_focus()
	return true


## Hides the window and pops it from GameWindows (no-op when closed).
func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	var windows := game_windows()
	if windows != null:
		windows.call(&"pop", self)
	closed.emit()


func toggle() -> bool:
	if _open:
		close()
		return false
	return open()


## The GameWindows node (group `game_windows`), or null.
func game_windows() -> Node:
	if is_instance_valid(_game_windows):
		return _game_windows
	var tree := get_tree() if is_inside_tree() else Engine.get_main_loop() as SceneTree
	_game_windows = tree.get_first_node_in_group(GAME_WINDOWS_GROUP) if tree != null else null
	return _game_windows


## Adds or moves a marker (MapMarkers.set_marker; docs/godot/specs/map.md 3.3).
func set_marker(id: StringName, world_point: Vector2, kind: StringName = MapMarkers.KIND_WAYPOINT, map_id: String = "") -> void:
	markers.set_marker(id, world_point, kind, map_id)


func clear_marker(id: StringName) -> void:
	markers.clear_marker(id)


func clear_markers() -> void:
	markers.clear_markers()


## The ids of the discovered areas (RunState `world.discovered_areas`).
static func discovered_areas() -> PackedStringArray:
	var run := Services.run()
	var out := PackedStringArray()
	if run != null:
		for area_id: Variant in run.world.get("discovered_areas", []):
			out.append(str(area_id))
	return out


## The label of one column (WorldMapSurfacePort.ts:59-63 without the glyph line).
static func area_text(area_id: String, discovered: PackedStringArray, current: String) -> String:
	if not area_id in discovered:
		return UNKNOWN_TEXT
	var text := AreaTitles.area_name(area_id)
	return text + "\n" + CURRENT_TEXT if area_id == current else text


## The summary line (WorldMapSurfacePort.ts:74).
static func summary_text(discovered: PackedStringArray) -> String:
	return SUMMARY_FORMAT % discovered.size()


## True when the link `index` of LINKS is shown (both ends discovered).
static func is_link_shown(index: int, discovered: PackedStringArray) -> bool:
	var link: Array = LINKS[index]
	return discovered.has(str(link[0])) and discovered.has(str(link[1]))


## Fills the labels from RunState and the current world, and redraws the chart.
func refresh() -> void:
	if not is_node_ready():
		return
	var discovered := discovered_areas()
	var current := _current_area()
	for area_id: String in AREA_ORDER:
		(get_node(AREA_LABELS[area_id]) as Label).text = area_text(area_id, discovered, current)
	summary_label.text = summary_text(discovered)
	chart.queue_redraw()


# --- input --------------------------------------------------------------------------------------

## While open, `map` and `menu` close the window (Phaser's M toggle; the menu key closes the open
## tab). Runs before GameWindows' key trap and before the GUI.
func _input(event: InputEvent) -> void:
	if not _open or event.is_echo() or not event.is_pressed():
		return
	if event is InputEventWithModifiers:
		var keys := event as InputEventWithModifiers
		if keys.ctrl_pressed or keys.alt_pressed or keys.meta_pressed:
			return
	for action: StringName in [&"map", &"menu"]:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			close()
			get_viewport().set_input_as_handled()
			return


# --- layout and drawing -------------------------------------------------------------------------

## Panel size for the viewport (`min(620, w − 32)` x `min(340, h − 32)`), centred; narrow fonts.
func _layout() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport().get_visible_rect().size
	var half := Vector2(
		minf(PANEL_MAX.x, maxf(1.0, viewport.x - VIEWPORT_MARGIN)),
		minf(PANEL_MAX.y, maxf(1.0, viewport.y - VIEWPORT_MARGIN))) * 0.5
	panel.offset_left = -roundf(half.x)
	panel.offset_right = roundf(half.x)
	panel.offset_top = -roundf(half.y)
	panel.offset_bottom = roundf(half.y)
	var font_size := AREA_FONT_SIZE_NARROW if viewport.x <= NARROW_WIDTH else AREA_FONT_SIZE
	for area_id: String in AREA_ORDER:
		(get_node(AREA_LABELS[area_id]) as Label).add_theme_font_size_override(&"font_size", font_size)
	chart.queue_redraw()


## Centre of an area's disc in the chart (panel) coordinates.
func disc_centre(area_id: String) -> Vector2:
	var label := get_node(AREA_LABELS[area_id]) as Label
	var x := (label.anchor_left + label.anchor_right) * 0.5 * panel.size.x
	return Vector2(x, COLUMN_TOP_RATIO * panel.size.y + DISC_DROP)


func _draw_chart() -> void:
	var discovered := discovered_areas()
	var current := _current_area()
	for index in LINKS.size():
		if is_link_shown(index, discovered):
			var link: Array = LINKS[index]
			var from := disc_centre(str(link[0]))
			var to := disc_centre(str(link[1]))
			chart.draw_line(from, to, LINK_UNDER, LINK_UNDER_WIDTH, true)
			chart.draw_line(from, to, LINK_OVER, LINK_OVER_WIDTH, true)
	var font := chart.get_theme_default_font()
	for area_id: String in AREA_ORDER:
		var centre := disc_centre(area_id)
		if area_id in discovered:
			chart.draw_circle(centre, DISC_RADIUS + DISC_RIM, UiTokens.SHADOW, true, -1.0, true)
			chart.draw_circle(centre, DISC_RADIUS, AreaTitles.title_color(area_id), true, -1.0, true)
			if area_id == current:
				chart.draw_circle(centre, CURRENT_RING_RADIUS, CURRENT_RING, false, CURRENT_RING_WIDTH, true)
				chart.draw_circle(centre, 4.0, UiTokens.SHADOW, true, -1.0, true)
		else:
			chart.draw_circle(centre, DISC_RADIUS, UNKNOWN_FILL, true, -1.0, true)
			chart.draw_circle(centre, DISC_RADIUS, UNKNOWN_RING, false, DISC_RIM, true)
			if font != null:
				var font_size := 15
				var baseline := centre.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
				chart.draw_string(font, Vector2(centre.x - DISC_RADIUS, baseline), "?",
					HORIZONTAL_ALIGNMENT_CENTER, DISC_RADIUS * 2.0, font_size, UiTokens.TEXT_MUTED)
		_draw_badges(area_id, centre)


## An area holding a waypoint marker gets the gold pin, enlarged, on its disc's upper right (the
## other kinds only show on the minimap).
func _draw_badges(area_id: String, centre: Vector2) -> void:
	for entry: Dictionary in markers.markers_in(area_id):
		if entry["kind"] == MapMarkers.KIND_WAYPOINT:
			chart.draw_set_transform(centre + BADGE_OFFSET, 0.0, Vector2(BADGE_SCALE, BADGE_SCALE))
			MapMarkers.draw_pin(chart, Vector2.ZERO, BADGE_RIM)
			chart.draw_set_transform(Vector2.ZERO)
			return


func _current_area() -> String:
	var world := Services.world()
	return world.map_id() if world != null else ""


## MutedButton text with the bold font and radius-6 boxes (modal window buttons are bold).
func _style_close_button() -> void:
	var bold := get_theme_font(&"font", &"BoldButton")
	if bold != null:
		close_button.add_theme_font_override(&"font", bold)
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
		var box := close_button.get_theme_stylebox(state)
		if box is StyleBoxFlat:
			var rounded := (box as StyleBoxFlat).duplicate() as StyleBoxFlat
			rounded.set_corner_radius_all(BUTTON_RADIUS)
			close_button.add_theme_stylebox_override(state, rounded)


func _on_close_pressed() -> void:
	close()


func _on_markers_changed() -> void:
	if visible:
		chart.queue_redraw()
