@tool
extends Node2D
class_name RoomDoor
## A room door (`object.room-door`, game/scenes/objects/dungeon/room-door.tscn; docs/godot/DUNGEON_ROOMS.md
## "Room doors"): in a dungeon of one world per room (Fatty's Lair), the way from one room's world
## into the next. Place it in a doorway's passage, on the room's edge: its position is the middle of
## the opening on the outer edge of the wall (a north door on the room's top edge). Pick in the
## Inspector:
##
## - `door_id`: its own id, unique in the dungeon (the far door names it);
## - `target_room`: the room it leads to (a list of the dungeon's rooms, from the layout:
##   game/dungeon/dungeon_layout.gd);
## - `target_door`: that room's door the slime comes out of (a list of the doors in that room);
## - `side`: the wall it is in (the way the slime pushes to go through);
## - `requires` (optional): a record that must be set before it lets the slime through, when what
##   holds the passage stands in the other room (the far side of a bolted door): `done:<door id>`
##   (a kit door opened for good), `gate:<gate id>` (a gate opened for good), `flag:<flag>` (a story
##   flag), `session:<name>` (a session record, such as a plate held down: heavy_plate.gd
##   `hold_record`); `locked_text` is what the slime hears then.
##
## What stands in the passage on this side (a bolted door, a barricade, a shutter, the seal, a stone
## door) blocks it as it always did: the trigger lies behind it, in the passage. Walking into the
## passage and pushing on (door.gd's push) scrolls the screen into the target room
## (game/dungeon/room_travel.gd, main.gd `request_exit` "scroll"); the slime walks out of the target
## door. In the editor it draws its passage (the trigger), an arrow out and "-> room / door", red
## while its target is not set or that door does not exist there.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")

const TRAVEL_NAME := "DoorScript"
const ARRIVAL_NAME := "arrival"
const ROOM_DOOR_SCENE := "res://game/scenes/objects/dungeon/room-door.tscn"
## The layout read when the room's Dungeon node names none (Fatty's Lair's).
const DEFAULT_LAYOUT := "res://game/scenes/worlds/rooms/fatty-lair/layout.tscn"
const OK_COLOR := Color(0.35, 0.85, 0.45, 0.9)
const BAD_COLOR := Color(0.95, 0.3, 0.25, 0.9)

## This door's id, unique in the dungeon.
@export var door_id: String = "":
	set(value):
		door_id = value
		queue_redraw()
## The room it leads to (its CameraRoom's name on the layout).
@export var target_room: String = "":
	set(value):
		target_room = value
		notify_property_list_changed()
		queue_redraw()
## The door of `target_room` the slime comes out of.
@export var target_door: String = "":
	set(value):
		target_door = value
		queue_redraw()
## The wall it is in: the way the slime walks to go through.
@export_enum("north", "south", "east", "west") var side: String = "north":
	set(value):
		side = value
		queue_redraw()
## The opening's width (along the wall) and how deep into the passage the trigger reaches from the
## outer edge (world units). A Lair doorway is 128 wide and its wall 128 deep.
@export var width: float = 128.0:
	set(value):
		width = value
		queue_redraw()
@export var depth: float = 96.0:
	set(value):
		depth = value
		queue_redraw()
## How far the trigger also reaches past this node, away from the room (world units): for a door
## whose far side is open floor in this world rather than the room's edge (the hub's door into Burr's
## cell, the lower hall's into the key alcove), so the slime is still in it where it stops.
@export var beyond: float = 0.0:
	set(value):
		beyond = value
		queue_redraw()
## How far inside from the outer edge the slime arrives (world units): past the wall's foot.
@export var arrival_inset: float = 176.0:
	set(value):
		arrival_inset = value
		queue_redraw()
## A record that must be set before the door lets the slime through ("" = none; see the notes).
@export var requires: String = ""
## The line when `requires` is not set yet.
@export var locked_text: String = "Bolted from the other side."
## How the screen goes to the target room: "scroll" (the Zelda slide, rooms side by side) or "iris"
## (the closing and opening circle, for a closet, a cellar or any room that is not beside this one).
@export_enum("scroll", "iris") var transition: String = "scroll"

static var _layout_worlds: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	var travel := get_node_or_null(TRAVEL_NAME)
	if travel == null:
		return
	var world_root := _world_root()
	var definition := world_root.get_node_or_null(^"world-definition") if world_root != null else null
	travel.set(&"map_id", str(definition.get(&"map_id")) if definition != null else "")
	travel.set(&"door_id", door_id)
	travel.set(&"target_area_id", target_world())
	travel.set(&"target_door_id", target_door)
	travel.set(&"side", side)
	travel.set(&"trigger_rect", trigger_rect())
	var arrival := get_node_or_null(ARRIVAL_NAME) as Node2D
	if arrival != null:
		arrival.position = inward() * arrival_inset


## The trigger in the passage, relative to this node (world units).
func trigger_rect() -> Rect2:
	match side:
		"north":
			return Rect2(-width * 0.5, -beyond, width, depth + beyond)
		"south":
			return Rect2(-width * 0.5, -depth, width, depth + beyond)
		"west":
			return Rect2(-beyond, -width * 0.5, depth + beyond, width)
	return Rect2(-depth, -width * 0.5, depth + beyond, width)


## Into the room from this door.
func inward() -> Vector2:
	match side:
		"north":
			return Vector2.DOWN
		"south":
			return Vector2.UP
		"west":
			return Vector2.RIGHT
	return Vector2.LEFT


## The world of `target_room` (from the layout); "" when the layout has no such room.
func target_world() -> String:
	return str(layout_worlds(layout_path()).get(target_room, ""))


## "" when the door lets the slime through, else `locked_text` (its `requires` is not set yet).
func refusal() -> String:
	if requires.is_empty() or is_required_set():
		return ""
	return locked_text


## True when `requires` is set (see the notes).
func is_required_set() -> bool:
	var run := Services.run()
	if run == null or requires.is_empty():
		return true
	var colon := requires.find(":")
	var kind := requires.left(colon) if colon > 0 else "flag"
	var id := requires.substr(colon + 1) if colon > 0 else requires
	match kind:
		"done":
			return DungeonState.is_done(get_tree(), "%s:%s" % [DungeonState.record_map_id(self), id])
		"gate":
			return bool(run.call(&"is_gate_unlocked", DungeonState.record_map_id(self), id))
		"session":
			return bool(DungeonState.session_value(run, id, false))
	return bool(run.call(&"has_flag", id))


## The layout scene: the room world's Dungeon node's `layout`, else Fatty's Lair's.
func layout_path() -> String:
	var root := _world_root()
	if root != null:
		for child: Node in root.get_children():
			if &"layout" in child and child.get(&"layout") is PackedScene:
				return (child.get(&"layout") as PackedScene).resource_path
	return DEFAULT_LAYOUT


## The layout's rooms: {room name: world id}, read once a session per layout.
static func layout_worlds(path: String) -> Dictionary:
	if _layout_worlds.has(path) and not Engine.is_editor_hint():
		return _layout_worlds[path]
	var out := {}
	if ResourceLoader.exists(path):
		var scene := (load(path) as PackedScene).instantiate()
		for child: Node in scene.get_children():
			if &"room_name" in child:
				out[str(child.get(&"room_name"))] = str(child.get(&"world_id"))
		scene.free()
	_layout_worlds[path] = out
	return out


## The room scene of `room_name` on the layout ("" when unknown).
static func layout_scene_of(path: String, room_name: String) -> String:
	if not ResourceLoader.exists(path):
		return ""
	var scene := (load(path) as PackedScene).instantiate()
	var found := ""
	for child: Node in scene.get_children():
		if &"room_name" in child and str(child.get(&"room_name")) == room_name:
			found = str(child.get(&"room_scene"))
	scene.free()
	return found


## The door ids of the room doors in the world scene at `scene_path` (read from its state).
static func doors_in_scene(scene_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return out
	var state := (load(scene_path) as PackedScene).get_state()
	for index: int in state.get_node_count():
		var instance := state.get_node_instance(index)
		if instance == null or instance.resource_path != ROOM_DOOR_SCENE:
			continue
		for p: int in state.get_node_property_count(index):
			if state.get_node_property_name(index, p) == &"door_id":
				out.append(str(state.get_node_property_value(index, p)))
	return out


# --- the editor ---------------------------------------------------------------------------------

func _validate_property(property: Dictionary) -> void:
	if not Engine.is_editor_hint():
		return
	match str(property["name"]):
		"target_room":
			var names := layout_worlds(layout_path()).keys()
			names.sort()
			property["hint"] = PROPERTY_HINT_ENUM_SUGGESTION
			property["hint_string"] = ",".join(PackedStringArray(names))
		"target_door":
			property["hint"] = PROPERTY_HINT_ENUM_SUGGESTION
			property["hint_string"] = ",".join(doors_in_scene(layout_scene_of(layout_path(), target_room)))
		"requires":
			property["hint"] = PROPERTY_HINT_ENUM_SUGGESTION
			property["hint_string"] = ",".join(_record_suggestions())


## Records this room's scene knows of: its kit doors ("done:"), gates ("gate:"), flags ("flag:"),
## plates' hold records ("session:").
func _record_suggestions() -> PackedStringArray:
	var out := PackedStringArray()
	var root := _world_root()
	if root == null:
		return out
	for node: Node in root.find_children("*", "", true, false):
		for pair: Array in [["link_id", "done:"], ["door_id", "done:"], ["gate_id", "gate:"], ["flag_id", "flag:"],
				["open_flag", "flag:"], ["hold_record", "session:"], ["open_while_record", "session:"]]:
			if node == self or not pair[0] in node:
				continue
			var value := str(node.get(pair[0]))
			if not value.is_empty() and not (pair[1] + value) in out and node.get_script() != get_script():
				out.append(pair[1] + value)
	out.sort()
	return out


func _world_root() -> Node:
	if Engine.is_editor_hint() and is_inside_tree():
		return get_tree().edited_scene_root
	var at := get_parent()
	while at != null:
		if at.get_node_or_null(^"world-definition") != null:
			return at
		at = at.get_parent()
	return owner


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var ok := not target_room.is_empty() and not target_door.is_empty() \
		and target_door in doors_in_scene(layout_scene_of(layout_path(), target_room))
	var colour := OK_COLOR if ok else BAD_COLOR
	var area := trigger_rect()
	draw_rect(area, Color(colour, 0.25))
	draw_rect(area, colour, false, 3.0)
	var out := -inward()
	draw_line(inward() * arrival_inset, out * 40.0, colour, 4.0)
	draw_line(out * 40.0, out * 40.0 + (-out + out.orthogonal()) * 16.0, colour, 4.0)
	draw_line(out * 40.0, out * 40.0 + (-out - out.orthogonal()) * 16.0, colour, 4.0)
	draw_circle(inward() * arrival_inset, 8.0, colour)
	var font := ThemeDB.fallback_font
	if font != null:
		var label := "%s -> %s / %s" % [door_id, target_room if not target_room.is_empty() else "?",
			target_door if not target_door.is_empty() else "?"]
		if not requires.is_empty():
			label += "  (needs %s)" % requires
		draw_string(font, inward() * (arrival_inset + 28.0) + Vector2(-120, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, colour)

