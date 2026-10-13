extends Control
class_name WorldMapWindow
## The world map window (Phaser `features/ui/WorldMapSurfacePort.ts` + `ui/world-map-ui.scene.json`;
## docs/godot/specs/map.md 2 and 3.4): the overworld of res://game/data/world-map.json
## (WorldMapData) as its chunk grid, each region drawn over its cells, named once the run has
## discovered it and fogged with a `?` until then; the current region ringed, the player's dot on
## it, the two-way passages between discovered regions and the quest waypoint badges. A centred
## `WindowPanel` (`panel_size_for`: 720 x 816 at most, clear of the menu tab strip above), the grid
## square in it. Scene: res://game/ui/map/world_map_window.tscn (Godot-owned), group "world_map".
##
## A game window: `MapUi` hands it to GameWindows (game/ui/screens/game_windows.gd, main's
## CanvasLayer 40) with `add_window`; `open()` pushes it there as surface `world-map` (the `modal`
## pause, the MenuOpen cue, `window_opened(&"world-map")`) and `close()` pops it. GameWindows'
## Escape calls `close()`. While open, `_input` closes it on the `map` and `menu` keys.
##
## A region is discovered when one of its maps (its overworld `world` or an interior) is in RunState
## `world.discovered_areas`; it is current when the current world is one of them. The layout is read
## once for the run (`map_data()`); without it the window shows MISSING_TEXT over an empty grid.
## The Chart control draws the regions, the chunk lines, the edges, the passages and the current
## ring; one Label per region (under Regions) names it; the Overlay control draws the player's dot
## and the waypoint badges (MapMarkers) over the names.
##
## Owner: map (game/ui/map).

const Services := preload("res://game/shared/services.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const AreaTitles := preload("res://game/shell/area_titles.gd")
const MapMarkers := preload("res://game/ui/map/map_markers.gd")
const Minimap := preload("res://game/ui/map/minimap.gd")
const WorldMapData := preload("res://game/world/atlas/world_map_data.gd")
const WorldChunks := preload("res://game/world/atlas/world_chunks.gd")

## Opened / closed (after the GameWindows push / pop).
signal opened
signal closed

## The GameWindows surface id (the quests session maps it to `menu:map`).
const SURFACE_ID := &"world-map"
const GROUP := &"world_map"
const GAME_WINDOWS_GROUP := &"game_windows"
const WORLD_MAIN_GROUP := &"world_main"
## The panel: at most PANEL_MAX, 16 px from the sides of the viewport, and TAB_STRIP_ROOM px from
## its top and bottom (the menu tab strip, menu_tabs.gd STRIP_RECT, ends 40 px down).
const PANEL_MAX := Vector2(720.0, 816.0)
const VIEWPORT_MARGIN := 32.0
const TAB_STRIP_ROOM := 44.0
## The grid inside the panel: GRID_SIDE px from its sides, under the title (GRID_TOP) and over the
## summary and Close (GRID_BOTTOM); whole pixels per chunk.
const GRID_SIDE := 24.0
const GRID_TOP := 58.0
const GRID_BOTTOM := 86.0
## Region names: 14 px (10 px at <= 520 px), the unknown `?` larger; kept LABEL_PADDING px inside
## the largest block of whole chunks the region holds.
const REGION_FONT_SIZE := 14
const REGION_FONT_SIZE_NARROW := 10
const UNKNOWN_FONT_SIZE := 22
const UNKNOWN_FONT_SIZE_NARROW := 14
const NARROW_WIDTH := 520.0
const LABEL_PADDING := 4.0
const NAME_STYLE := &"HudLabel"
const UNKNOWN_STYLE := &"MutedLabel"
const UNKNOWN_TEXT := "?"
const CURRENT_TEXT := "Current area"
const SUMMARY_FORMAT := "%d of %d regions discovered · Areas stay marked as you travel"
## The summary without a layout: every discovered map id.
const SUMMARY_NO_LAYOUT := "%d discovered · Areas stay marked as you travel"
const MISSING_TEXT := "The world layout could not be read."
## Grid colours: the well under unplanned cells, its frame and the chunk lines.
const GRID_FILL := UiTokens.SHADOW
const GRID_FRAME := Color(UiTokens.BORDER, 0.95)
const GRID_FRAME_WIDTH := 1.5
const CHUNK_LINE := Color(UiTokens.BORDER, 0.35)
const CHUNK_LINE_WIDTH := 1.0
## Regions: fog until discovered, then the region's colour mixed into the inset surface.
const FOG_FILL := UiTokens.SURFACE_INSET
const DISCOVERED_TINT := 0.5
const REGION_EDGE := Color(UiTokens.BORDER, 0.95)
const REGION_EDGE_WIDTH := 1.5
const CURRENT_RING := UiTokens.WARNING
const CURRENT_RING_WIDTH := 2.5
## Passage links: an accent bar on a dark one (the legacy WorldMapUI.ts:112-115 link, darker and
## stronger to read on the tinted regions), LINK_HALF_LENGTH of a chunk to each side of the
## opening, across the border.
const LINK_UNDER := Color(UiTokens.SHADOW, 0.9)
const LINK_UNDER_WIDTH := 5.0
const LINK_OVER := UiTokens.ACCENT
const LINK_OVER_WIDTH := 2.0
const LINK_HALF_LENGTH := 0.18
## The waypoint badge: the minimap pin at 1.5x, its tip this far from the top right of the
## region's name.
const BADGE_OFFSET := Vector2(2.0, -1.0)
const BADGE_SCALE := 1.5
## The pin's teardrop on the dark panel: a deep gold instead of the minimap's ink.
const BADGE_RIM := Color("#b9822e")
## Close button: radius 6 (`.game-ui--world-map-ui .scene-control--button`).
const BUTTON_RADIUS := 6

## The layout, read once for the run (null when the file is missing or not a world map).
static var _map: WorldMapData
static var _map_read := false
## Each region's shapes in cells (`_region_shapes`), made with `_map`.
static var _shapes: Dictionary = {}

## The shared markers (MapUi sets it; a lone window makes its own).
var markers: MapMarkers

@onready var panel: Control = $Panel
@onready var chart: Control = $Panel/Chart
@onready var regions_root: Control = $Panel/Regions
@onready var overlay: Control = $Panel/Overlay
@onready var title_label: Label = $Panel/Title
@onready var message_label: Label = $Panel/Message
@onready var summary_label: Label = $Panel/Summary
@onready var close_button: Button = $Panel/Close

var _open: bool = false
var _game_windows: Node
## The grid in panel coordinates, and the size of one cell on it.
var _grid := Rect2()
var _cell := Vector2.ZERO
var _narrow: bool = false
## Region key -> its name Label, made for `_labels_map`.
var _labels: Dictionary = {}
var _labels_map: WorldMapData
var _labels_made: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if markers == null:
		markers = MapMarkers.new()
	markers.changed.connect(_on_markers_changed)
	chart.draw.connect(_draw_chart)
	overlay.draw.connect(_draw_overlay)
	close_button.pressed.connect(_on_close_pressed)
	_style_close_button()
	message_label.text = MISSING_TEXT
	get_viewport().size_changed.connect(_layout)
	_sync_labels()
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


## The panel's size for a viewport of `viewport`: at most PANEL_MAX, `w − 32` across and `h − 88`
## down, and no bigger than the square grid those leave needs with the title, summary and Close
## (720 x 816 at 1024 x 1024; 448 x 544 at 480 x 900).
static func panel_size_for(viewport: Vector2) -> Vector2:
	var room := Vector2(
		minf(PANEL_MAX.x, maxf(1.0, viewport.x - VIEWPORT_MARGIN)),
		minf(PANEL_MAX.y, maxf(1.0, viewport.y - TAB_STRIP_ROOM * 2.0)))
	var side := maxf(0.0, minf(room.x - GRID_SIDE * 2.0, room.y - GRID_TOP - GRID_BOTTOM))
	return Vector2(minf(room.x, side + GRID_SIDE * 2.0), minf(room.y, side + GRID_TOP + GRID_BOTTOM))


## The world layout (res://game/data/world-map.json), read the first time it is asked for; null
## when the file is missing or is not a world map.
static func map_data() -> WorldMapData:
	if not _map_read:
		_map_read = true
		if FileAccess.file_exists(WorldMapData.PATH):
			_map = WorldMapData.load_file(WorldMapData.PATH)
		else:
			push_warning("WorldMapWindow: no world layout at %s" % WorldMapData.PATH)
		_shapes = _region_shapes(_map)
	return _map


## Uses `map` as the layout from now on (tools and tests; null = no layout). Open windows show it
## on their next `refresh()`.
static func use_map(map: WorldMapData) -> void:
	_map = map
	_map_read = true
	_shapes = _region_shapes(map)


## Reads the layout file again on the next `map_data()`.
static func reload_map() -> void:
	_map = null
	_map_read = false
	_shapes = {}


## The region with key `key_or_map_id`, else the region whose overworld or interior is that map, or
## whose overworld a chunk world of that id was cut from (WorldChunks) ({} when none, or without a
## layout).
static func region_of(key_or_map_id: String) -> Dictionary:
	var map := map_data()
	if map == null or key_or_map_id.is_empty():
		return {}
	var region := map.region(key_or_map_id)
	if region.is_empty():
		region = map.region_for_map(key_or_map_id)
	if region.is_empty() and not WorldChunks.world_of(key_or_map_id).is_empty():
		region = map.region_for_map(WorldChunks.world_of(key_or_map_id))
	return region


## A region's map ids: its overworld world, then its interiors.
static func region_maps(region: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var world := str(region.get("world", ""))
	if not world.is_empty():
		out.append(world)
	for interior: Variant in region.get("interiors", []):
		out.append(str(interior))
	return out


## True when one of the region's maps is discovered.
static func is_region_discovered(region: Dictionary, discovered: PackedStringArray) -> bool:
	for map_id: String in region_maps(region):
		if discovered.has(map_id):
			return true
	return false


## A region's label: `?` until discovered, then its name (`AreaTitles.region_name`, the area
## banner's: without a trailing planning note such as " (open)"; its key without a name), and
## "Current area" under the name of the region whose map `current_map` is.
static func region_label(region: Dictionary, discovered: PackedStringArray, current_map: String) -> String:
	if not is_region_discovered(region, discovered):
		return UNKNOWN_TEXT
	var text := AreaTitles.region_name(region)
	if text.is_empty():
		text = str(region.get("key", ""))
	return text + "\n" + CURRENT_TEXT if region_maps(region).has(current_map) else text


## The summary line: the discovered regions of the layout (every discovered map id without one).
static func summary_text(discovered: PackedStringArray) -> String:
	var map := map_data()
	if map == null:
		return SUMMARY_NO_LAYOUT % discovered.size()
	var count := 0
	for region: Dictionary in map.regions():
		if is_region_discovered(region, discovered):
			count += 1
	return SUMMARY_FORMAT % [count, map.regions().size()]


## True when the layout has a passage between the regions of `a` and `b` (region keys or map ids).
static func has_passage(a: String, b: String) -> bool:
	return not _passage_between(a, b).is_empty()


## True when the link of the passage between `a` and `b` (region keys or map ids) is shown: there
## is one and `passage_shown`.
static func link_shown(a: String, b: String, discovered: PackedStringArray) -> bool:
	var passage := _passage_between(a, b)
	return not passage.is_empty() and passage_shown(map_data(), passage, discovered)


## True when a passage of `map` gets its link: both of its regions are discovered and it can be
## travelled both ways (`is_two_way`).
static func passage_shown(map: WorldMapData, passage: Dictionary, discovered: PackedStringArray) -> bool:
	if map == null:
		return false
	var a := map.region(str(passage.get("a", "")))
	var b := map.region(str(passage.get("b", "")))
	return not a.is_empty() and not b.is_empty() and is_two_way(a, b) \
		and is_region_discovered(a, discovered) and is_region_discovered(b, discovered)


## True when a passage between regions `a` and `b` can be travelled both ways, as far as the layout
## tells (the world scenes are not read for the map): both are placeholders (the region builder
## gives each side of every opening its exit) or both are hand-made worlds (`placeholder` false:
## their own exits; level-1, gloop-forest and crystal-caverns lead to each other). Between a
## placeholder and a hand-made world only the placeholder's exit is built, the hand-made worlds
## have none back yet (docs/godot/WORLD_ATLAS.md, "Openings on hand-made worlds"): no link.
static func is_two_way(a: Dictionary, b: Dictionary) -> bool:
	return bool(a.get("placeholder", false)) == bool(b.get("placeholder", false))


## The region the current world belongs to ({} in a world off the layout, e.g. the playground).
func current_region() -> Dictionary:
	return region_of(_current_map())


## The text of a region's label (by region key or map id; "" when there is no such region).
func region_text(key_or_map_id: String) -> String:
	var label := _labels.get(str(region_of(key_or_map_id).get("key", ""))) as Label
	return label.text if label != null else ""


## The grid in panel coordinates (empty without a layout).
func grid_rect() -> Rect2:
	return _grid


## The block of whole chunks a region spans (its overworld world's place), in panel coordinates.
func region_rect(key_or_map_id: String) -> Rect2:
	var key := str(region_of(key_or_map_id).get("key", ""))
	var shape: Dictionary = _shapes.get(key, {})
	return _cells_to_panel(shape["block"]) if not shape.is_empty() else Rect2()


## Where the player's dot is drawn (panel coordinates): the player's place in the current world
## mapped onto its region's block (a chunk world's onto its chunk); INF when the current world is
## not a region's overworld or a chunk of one.
func player_dot() -> Vector2:
	var region := current_region()
	var bounds := _world_rect()
	var point := _player_point()
	var chunk := WorldChunks.chunk_of(_current_map())
	if region.is_empty() or (str(region.get("world", "")) != _current_map() and chunk.is_empty()) or not bounds.has_area() or not point.is_finite():
		return Vector2.INF
	var block := region_rect(str(region.get("key", ""))) if chunk.is_empty() else _chunk_panel_rect(chunk)
	var at := ((point - bounds.position) / bounds.size).clamp(Vector2.ZERO, Vector2.ONE)
	return block.position + at * block.size


## Fills the labels from RunState and the current world, and redraws the chart.
func refresh() -> void:
	if not is_node_ready():
		return
	_sync_labels()
	var map := map_data()
	var discovered := discovered_areas()
	var current := _current_map()
	if map != null:
		for region: Dictionary in map.regions():
			var label := _labels.get(str(region.get("key", ""))) as Label
			if label != null:
				label.text = region_label(region, discovered, current)
				_style_label(label, is_region_discovered(region, discovered))
	message_label.visible = map == null
	summary_label.text = summary_text(discovered)
	chart.queue_redraw()
	overlay.queue_redraw()


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


# --- layout -------------------------------------------------------------------------------------

## Panel size for the viewport (`panel_size_for`), centred; the grid in it, the region labels on the
## grid and their font sizes.
func _layout() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport().get_visible_rect().size
	var half := panel_size_for(viewport) * 0.5
	panel.offset_left = -roundf(half.x)
	panel.offset_right = roundf(half.x)
	panel.offset_top = -roundf(half.y)
	panel.offset_bottom = roundf(half.y)
	_narrow = viewport.x <= NARROW_WIDTH
	_place_grid(Vector2(roundf(half.x), roundf(half.y)) * 2.0)
	message_label.position = _grid.position
	message_label.size = _grid.size
	for key: String in _labels:
		var label: Label = _labels[key]
		var shape: Dictionary = _shapes.get(key, {})
		var box := _cells_to_panel(shape["label"]).grow(-LABEL_PADDING) if not shape.is_empty() else Rect2()
		label.position = box.position
		label.size = box.size.max(Vector2.ZERO)
		_style_label(label, label.theme_type_variation == NAME_STYLE)
	chart.queue_redraw()
	overlay.queue_redraw()


## The grid for a panel of `panel_size`: the layout's chunks at whole pixels, centred across the
## room between the title and the summary (a square well without a layout).
func _place_grid(panel_size: Vector2) -> void:
	var map := map_data()
	var room := Vector2(panel_size.x - GRID_SIDE * 2.0, panel_size.y - GRID_TOP - GRID_BOTTOM).max(Vector2.ZERO)
	var chunks := Vector2(map.chunk_cols, map.chunk_rows) if map != null else Vector2.ONE
	var chunk := floorf(minf(room.x / chunks.x, room.y / chunks.y))
	var size := chunks * chunk
	_grid = Rect2(Vector2(roundf((panel_size.x - size.x) * 0.5), GRID_TOP + roundf((room.y - size.y) * 0.5)), size)
	_cell = Vector2(chunk, chunk) / Vector2(map.chunk_cells().max(Vector2i.ONE)) if map != null else Vector2.ZERO


## One Label per region of the layout (made again when the layout changes).
func _sync_labels() -> void:
	var map := map_data()
	if _labels_made and map == _labels_map:
		return
	for label: Label in _labels.values():
		label.free()
	_labels.clear()
	_labels_map = map
	_labels_made = true
	for region: Dictionary in map.regions() if map != null else []:
		var key := str(region.get("key", ""))
		if not _shapes.has(key) or _labels.has(key):
			continue
		var label := Label.new()
		label.name = str(region.get("id", key)).validate_node_name()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = UNKNOWN_TEXT
		regions_root.add_child(label)
		_labels[key] = label
		_style_label(label, false)
	if is_inside_tree():
		_layout()


## A name in the HUD text style; an unknown region's `?` muted and larger.
func _style_label(label: Label, discovered: bool) -> void:
	label.theme_type_variation = NAME_STYLE if discovered else UNKNOWN_STYLE
	var font_size: int
	if discovered:
		font_size = REGION_FONT_SIZE_NARROW if _narrow else REGION_FONT_SIZE
	else:
		font_size = UNKNOWN_FONT_SIZE_NARROW if _narrow else UNKNOWN_FONT_SIZE
	label.add_theme_font_size_override(&"font_size", font_size)


# --- drawing ------------------------------------------------------------------------------------

## The well, the regions (fog or their tint), the chunk lines, the region edges, the links of the
## two-way passages between discovered regions (`passage_shown`), the well's frame and the current
## region's ring.
func _draw_chart() -> void:
	chart.draw_rect(_grid, GRID_FILL)
	var map := map_data()
	if map == null or not _grid.has_area():
		chart.draw_rect(_grid, GRID_FRAME, false, GRID_FRAME_WIDTH, true)
		return
	var discovered := discovered_areas()
	for region: Dictionary in map.regions():
		var shape: Dictionary = _shapes.get(str(region.get("key", "")), {})
		if shape.is_empty():
			continue
		var fill := FOG_FILL
		if is_region_discovered(region, discovered):
			fill = FOG_FILL.lerp(Color.from_string(str(region.get("color", "")), FOG_FILL), DISCOVERED_TINT)
		for rect: Rect2i in shape["rects"]:
			chart.draw_rect(_cells_to_panel(rect), fill)
	var chunk := _cell * Vector2(map.chunk_cells())
	for x in range(1, map.chunk_cols):
		var at := _grid.position.x + chunk.x * x
		chart.draw_line(Vector2(at, _grid.position.y), Vector2(at, _grid.end.y), CHUNK_LINE, CHUNK_LINE_WIDTH)
	for y in range(1, map.chunk_rows):
		var at := _grid.position.y + chunk.y * y
		chart.draw_line(Vector2(_grid.position.x, at), Vector2(_grid.end.x, at), CHUNK_LINE, CHUNK_LINE_WIDTH)
	for key: String in _shapes:
		chart.draw_multiline(_outline(key), REGION_EDGE, REGION_EDGE_WIDTH, true)
	for passage: Dictionary in map.passages():
		if passage_shown(map, passage, discovered):
			_draw_link(map, passage, chunk)
	chart.draw_rect(_grid, GRID_FRAME, false, GRID_FRAME_WIDTH, true)
	var current := str(current_region().get("key", ""))
	if _shapes.has(current):
		var ring := _outline(current)
		chart.draw_multiline(ring, CURRENT_RING, CURRENT_RING_WIDTH, true)
		# Round the corners the separate segments leave notched.
		for point: Vector2 in ring:
			chart.draw_circle(point, CURRENT_RING_WIDTH * 0.5, CURRENT_RING, true, -1.0, true)


## A passage's link: a short bar across its regions' border at the middle of its opening.
func _draw_link(map: WorldMapData, passage: Dictionary, chunk: Vector2) -> void:
	var opening := Rect2(float(passage.get("x", 0)), float(passage.get("y", 0)),
		maxf(1.0, float(passage.get("w", 1))), maxf(1.0, float(passage.get("h", 1))))
	var centre := _grid.position + opening.get_center() * _cell
	var half := _passage_axis(map, passage) * chunk * LINK_HALF_LENGTH
	chart.draw_line(centre - half, centre + half, LINK_UNDER, LINK_UNDER_WIDTH, true)
	chart.draw_line(centre - half, centre + half, LINK_OVER, LINK_OVER_WIDTH, true)


## Over the names: the player's dot (the minimap's) and the waypoint badges.
func _draw_overlay() -> void:
	var map := map_data()
	if map == null or not _grid.has_area():
		return
	for region: Dictionary in map.regions():
		_draw_badge(region)
	var dot := player_dot()
	if dot.is_finite():
		overlay.draw_circle(dot, Minimap.PLAYER_RIM_RADIUS, MapMarkers.RIM_COLOR, true, -1.0, true)
		overlay.draw_circle(dot, Minimap.PLAYER_RADIUS, Minimap.PLAYER_COLOR, true, -1.0, true)


## A region with a waypoint marker in one of its maps gets the gold pin, enlarged, at the upper right
## of its name (the other kinds only show on the minimap).
func _draw_badge(region: Dictionary) -> void:
	var label := _labels.get(str(region.get("key", ""))) as Label
	if label == null:
		return
	for map_id: String in region_maps(region):
		for entry: Dictionary in markers.markers_in(map_id):
			if entry["kind"] != MapMarkers.KIND_WAYPOINT:
				continue
			var text := Vector2.ZERO
			var font := label.get_theme_font(&"font")
			if font != null:
				text = font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, label.size.x,
					label.get_theme_font_size(&"font_size"))
			var corner := label.position + label.size * 0.5 + Vector2(text.x, -text.y) * 0.5
			overlay.draw_set_transform(corner + BADGE_OFFSET, 0.0, Vector2(BADGE_SCALE, BADGE_SCALE))
			MapMarkers.draw_pin(overlay, Vector2.ZERO, BADGE_RIM)
			overlay.draw_set_transform(Vector2.ZERO)
			return


## A cell rectangle on the panel.
func _cells_to_panel(cells: Rect2i) -> Rect2:
	return Rect2(_grid.position + Vector2(cells.position) * _cell, Vector2(cells.size) * _cell)


## Region `key`'s edge as segment pairs on the panel.
func _outline(key: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in _shapes[key]["outline"]:
		out.append(_grid.position + point * _cell)
	return out


## The panel rectangle of chunk `chunk_name` ("A6"); empty without a layout.
func _chunk_panel_rect(chunk_name: String) -> Rect2:
	var map := map_data()
	var column := WorldMapData.COLUMN_LETTERS.find(chunk_name.left(1))
	if map == null or column < 0 or not chunk_name.substr(1).is_valid_int():
		return Rect2()
	return _cells_to_panel(map.chunk_rect_cells(Rect2i(Vector2i(column, int(chunk_name.substr(1)) - 1), Vector2i.ONE)))


func _current_map() -> String:
	var world := Services.world()
	return world.map_id() if world != null else ""


func _world_rect() -> Rect2:
	var world := Services.world()
	return world.world_rect() if world != null else Rect2()


func _player_point() -> Vector2:
	var world := Services.world()
	if world == null or not is_instance_valid(world.player) or not world.player.is_inside_tree():
		return Vector2.INF
	return world.player.get_centre()


# --- layout shapes ------------------------------------------------------------------------------

## Each region's shapes in cells: {key: {"rects": its cells as row runs merged downwards,
## "outline": segment pairs along its edge (Vector2 cell corners), "block": the chunks it holds
## (more than half their cells, WorldMapData.region_chunks) as one cell rectangle, else its cells'
## bounds, "label": the largest rectangle of those chunks (its cells' bounds without one)}}.
static func _region_shapes(map: WorldMapData) -> Dictionary:
	var shapes := {}
	if map == null:
		return shapes
	var rects := {}
	var outlines := {}
	var counts := {}
	for region: Dictionary in map.regions():
		var key := str(region.get("key", ""))
		if key.length() == 1 and key != WorldMapData.NO_REGION:
			rects[key] = [] as Array[Rect2i]
			outlines[key] = [] as Array[Vector2]
			counts[key] = {}
	var grid: Array = map.grids["regionCells"]
	var chunk := map.chunk_cells().max(Vector2i.ONE)
	# Row runs, merged with the same run of the row above; the cells per chunk.
	var open := {}
	for y in map.rows:
		var row: PackedByteArray = grid[y]
		var next_open := {}
		var x := 0
		while x < map.cols:
			var end := x + 1
			while end < map.cols and row[end] == row[x]:
				end += 1
			var key := String.chr(row[x])
			if rects.has(key):
				var list: Array[Rect2i] = rects[key]
				var run := Vector3i(row[x], x, end)
				var index: int = open.get(run, -1)
				if index >= 0:
					var rect := list[index]
					rect.size.y += 1
					list[index] = rect
				else:
					list.append(Rect2i(x, y, end - x, 1))
					index = list.size() - 1
				next_open[run] = index
				var per_chunk: Dictionary = counts[key]
				var from := x
				while from < end:
					var at := Vector2i(from, y) / chunk
					var stop := mini(end, (at.x + 1) * chunk.x)
					per_chunk[at] = int(per_chunk.get(at, 0)) + stop - from
					from = stop
			x = end
		open = next_open
	# Edges: where the cells on either side of a cell edge differ (-1 off the grid).
	for y in map.rows + 1:
		var row_above: PackedByteArray = grid[y - 1] if y > 0 else PackedByteArray()
		var row_below: PackedByteArray = grid[y] if y < map.rows else PackedByteArray()
		for x in map.cols:
			var above := int(row_above[x]) if y > 0 else -1
			var below := int(row_below[x]) if y < map.rows else -1
			if above != below:
				_add_edge(outlines, above, Vector2(x, y), Vector2(x + 1, y))
				_add_edge(outlines, below, Vector2(x, y), Vector2(x + 1, y))
	for x in map.cols + 1:
		for y in map.rows:
			var row: PackedByteArray = grid[y]
			var left := int(row[x - 1]) if x > 0 else -1
			var right := int(row[x]) if x < map.cols else -1
			if left != right:
				_add_edge(outlines, left, Vector2(x, y), Vector2(x, y + 1))
				_add_edge(outlines, right, Vector2(x, y), Vector2(x, y + 1))
	var half := chunk.x * chunk.y * 0.5
	for key: String in rects:
		var list: Array[Rect2i] = rects[key]
		if list.is_empty():
			continue
		var bounds := list[0]
		for rect in list:
			bounds = bounds.merge(rect)
		var held := {}
		for at: Vector2i in counts[key]:
			if float(counts[key][at]) > half:
				held[at] = true
		var block := Rect2i()
		for at: Vector2i in held:
			block = Rect2i(at, Vector2i.ONE) if not block.has_area() else block.expand(at).expand(at + Vector2i.ONE)
		var label := _largest_block(held)
		shapes[key] = {
			"rects": list,
			"outline": PackedVector2Array(outlines[key]),
			"block": map.chunk_rect_cells(block) if block.has_area() else bounds,
			"label": map.chunk_rect_cells(label) if label.has_area() else bounds,
		}
	return shapes


## Adds the edge `from`-`to` to the outline of the region whose key is the character `code` (when
## it is a region), lengthening the last segment when it runs on in the same line.
static func _add_edge(outlines: Dictionary, code: int, from: Vector2, to: Vector2) -> void:
	var key := String.chr(code) if code >= 0 else ""
	if not outlines.has(key):
		return
	var outline: Array[Vector2] = outlines[key]
	var count := outline.size()
	if count >= 2 and outline[count - 1] == from \
			and (outline[count - 2].x == to.x or outline[count - 2].y == to.y):
		outline[count - 1] = to
	else:
		outline.append(from)
		outline.append(to)


## The largest rectangle of the chunks in `held` (chunk -> true): the bigger area, then the squarer,
## then the first in reading order. Empty when `held` is.
static func _largest_block(held: Dictionary) -> Rect2i:
	var best := Rect2i()
	for start: Vector2i in held:
		var width := 0
		while held.has(start + Vector2i(width, 0)):
			width += 1
		var height := 0
		while width > 0:
			var run := 0
			while run < width and held.has(start + Vector2i(run, height)):
				run += 1
			if run == 0:
				break
			width = run
			height += 1
			var rect := Rect2i(start, Vector2i(width, height))
			var area := rect.get_area()
			if area > best.get_area() or (area == best.get_area() and mini(width, height) > mini(best.size.x, best.size.y)):
				best = rect
	return best


## The passage between the regions of `a` and `b` (region keys or map ids), {} when none.
static func _passage_between(a: String, b: String) -> Dictionary:
	var map := map_data()
	var key_a := str(region_of(a).get("key", ""))
	var key_b := str(region_of(b).get("key", ""))
	if map == null or key_a.is_empty() or key_b.is_empty() or key_a == key_b:
		return {}
	for passage: Dictionary in map.passages():
		var ends := [str(passage.get("a", "")), str(passage.get("b", ""))]
		if ends.has(key_a) and ends.has(key_b):
			return passage
	return {}


## Which way a passage crosses its border: sideways when the cells left and right of its opening
## belong to its two regions, downwards when those above and below do, else across the opening's
## long side.
static func _passage_axis(map: WorldMapData, passage: Dictionary) -> Vector2:
	var opening := Rect2i(int(passage.get("x", 0)), int(passage.get("y", 0)),
		maxi(1, int(passage.get("w", 1))), maxi(1, int(passage.get("h", 1))))
	var ends := [str(passage.get("a", "")), str(passage.get("b", ""))]
	var middle := opening.position + opening.size / 2
	var left := map.region_key_at(Vector2i(opening.position.x - 1, middle.y))
	var right := map.region_key_at(Vector2i(opening.end.x, middle.y))
	var up := map.region_key_at(Vector2i(middle.x, opening.position.y - 1))
	var down := map.region_key_at(Vector2i(middle.x, opening.end.y))
	var sideways := left != right and ends.has(left) and ends.has(right)
	var upright := up != down and ends.has(up) and ends.has(down)
	if sideways != upright:
		return Vector2.RIGHT if sideways else Vector2.DOWN
	return Vector2.RIGHT if opening.size.y >= opening.size.x else Vector2.DOWN


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
		overlay.queue_redraw()
