extends Control
## The dungeon's map on the map screen (docs/godot/DUNGEONS.md "The dungeon map"). Inside a dungeon
## the world map window (game/ui/map/world_map_window.gd, group `world_map`) shows this page over
## its regions: the dungeon's rooms as DungeonMapDraw draws them (fog over rooms not visited until
## the map is found; the compass's marks), the slime's dot, the dungeon's name as the window's title
## and what is held on its summary line. The page sits in the window's Panel under its title,
## summary and Close button, covering the grid; the window keeps its own pause, keys and cues. The
## Dungeon node attaches it (`attach`) and it leaves with the dungeon's world (`detach` gives the
## window its title back).
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const DungeonMapDraw := preload("res://game/dungeon/dungeon_map_draw.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

const WINDOW_GROUP := &"world_map"
const WORLD_TITLE := "World Map"
const BACKDROP := Color("#1b2436")
const FRAME := Color(UiTokens.BORDER, 0.95)
const PAD := 18.0
const NO_MAP_TEXT := "Rooms you have walked through. The map shows the rest"

var dungeon: Node
var _window: Control
var _title_text := ""


## Makes the page for `owner_dungeon`; it finds the map window (now or as soon as it exists).
static func attach(owner_dungeon: Node) -> Control:
	var page: Control = (load("res://game/dungeon/dungeon_map_page.gd") as GDScript).new()
	page.name = "DungeonMapPage"
	page.set(&"dungeon", owner_dungeon)
	page.visible = false
	owner_dungeon.add_child(page)
	return page


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


## Gives the window back its own title and leaves it.
func detach() -> void:
	if _window != null and is_instance_valid(_window):
		var title := _window.get(&"title_label") as Label
		if title != null:
			title.text = WORLD_TITLE
	_window = null


func _process(_delta: float) -> void:
	if dungeon == null or not is_instance_valid(dungeon):
		return
	if _window == null or not is_instance_valid(_window):
		_find_window()
		return
	var open := bool(_window.call(&"is_open"))
	visible = open
	if not open:
		return
	var grid: Rect2 = _window.call(&"grid_rect")
	position = grid.position
	size = grid.size
	var title := _window.get(&"title_label") as Label
	var name_text := str(dungeon.get(&"display_name"))
	if title != null and not name_text.is_empty():
		title.text = name_text
	var summary := _window.get(&"summary_label") as Label
	if summary != null:
		summary.text = summary_text()
	queue_redraw()


## The summary line: the keys and what else is held.
func summary_text() -> String:
	var run := Services.run()
	var id := str(dungeon.get(&"dungeon_id")) if dungeon != null else ""
	var parts: PackedStringArray = ["Small keys: %d" % DungeonState.small_keys(run, id)]
	if DungeonState.has_item(run, id, DungeonState.BIG_KEY):
		parts.append("Big key")
	if DungeonState.has_item(run, id, DungeonState.MAP):
		parts.append("Map")
	else:
		parts.append(NO_MAP_TEXT)
	if DungeonState.has_item(run, id, DungeonState.COMPASS):
		parts.append("Compass")
	return " · ".join(parts)


func _find_window() -> void:
	var window := get_tree().get_first_node_in_group(WINDOW_GROUP) as Control
	if window == null:
		return
	var panel := window.get_node_or_null(^"Panel") as Control
	if panel == null:
		return
	_window = window
	get_parent().remove_child(self)
	panel.add_child(self)
	var overlay := panel.get_node_or_null(^"Overlay")
	if overlay != null:
		panel.move_child(self, overlay.get_index() + 1)


func _draw() -> void:
	if dungeon == null or not is_instance_valid(dungeon):
		return
	var area := Rect2(Vector2.ZERO, size)
	draw_rect(area, BACKDROP)
	draw_rect(area, FRAME, false, 1.5, true)
	var box := DungeonMapDraw.bounds(dungeon)
	if not box.has_area():
		return
	var room := area.grow(-PAD)
	var scale := minf(room.size.x / box.size.x, room.size.y / box.size.y)
	var offset := room.position + (room.size - box.size * scale) * 0.5
	var to_view := func(point: Vector2) -> Vector2: return offset + (point - box.position) * scale
	var world := Services.world()
	var player_point: Vector2 = world.player.get_centre() if world != null and world.player != null \
		and is_instance_valid(world.player) else Vector2.INF
	DungeonMapDraw.draw(self, dungeon, to_view, player_point, true)
