extends Control
## The dungeon's rooms on the HUD minimap (docs/godot/DUNGEONS.md "The dungeon map"): a Control the
## Dungeon node puts into the minimap (game/ui/map/minimap.gd), under its Overlay (the player's dot
## and markers stay on top). It draws DungeonMapDraw's rooms (visited ones, all of them with the map,
## the compass's marks) at the minimap's own scale (`Minimap.to_map`). Gone with the dungeon's world.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonMapDraw := preload("res://game/dungeon/dungeon_map_draw.gd")

const MAP_UI_GROUP := &"map_ui"

var dungeon: Node
var _minimap: Control
var _drawn_room := ""
var _drawn_rect := Rect2()


## Puts the rooms view into the HUD's minimap; null when there is none.
static func attach(owner_dungeon: Node) -> Control:
	var map_ui := owner_dungeon.get_tree().get_first_node_in_group(MAP_UI_GROUP)
	var minimap: Control = map_ui.get(&"minimap") if map_ui != null else null
	if minimap == null or not is_instance_valid(minimap):
		return null
	var view: Control = (load("res://game/dungeon/dungeon_minimap.gd") as GDScript).new()
	view.name = "DungeonRooms"
	view.set(&"dungeon", owner_dungeon)
	view.set(&"_minimap", minimap)
	minimap.add_child(view)
	var overlay := minimap.get_node_or_null(^"Overlay")
	if overlay != null:
		minimap.move_child(view, overlay.get_index())
	return view


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var run := Services.run()
	if run != null:
		run.world_progress_changed.connect(_on_progress)


func _exit_tree() -> void:
	var run := Services.run()
	if run != null and run.world_progress_changed.is_connected(_on_progress):
		run.world_progress_changed.disconnect(_on_progress)


func _on_progress(_payload: Dictionary) -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	if dungeon == null or not is_instance_valid(dungeon) or _minimap == null:
		return
	var room := str(dungeon.call(&"current_room_key"))
	var rect: Rect2 = _minimap.call(&"map_rect")
	if room != _drawn_room or rect != _drawn_rect:
		_drawn_room = room
		_drawn_rect = rect
		queue_redraw()


func _draw() -> void:
	if dungeon == null or not is_instance_valid(dungeon) or _minimap == null:
		return
	DungeonMapDraw.draw(self, dungeon, func(point: Vector2) -> Vector2: return _minimap.call(&"to_map", point),
		Vector2.INF, false)
