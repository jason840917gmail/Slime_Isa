@tool
extends Node2D
class_name Dungeon
## Marks its world as a dungeon, or as one world of a dungeon (docs/godot/DUNGEONS.md "The Dungeon
## node"; decisions archive question 109). Place one `Dungeon` node in each world of the dungeon,
## all with the same `dungeon_id`. While its world is played:
##
## - **No saving** (RunState `saving_blocked_reason` is "dungeon", DungeonState.is_inside): Save is
##   greyed out, the autosave waits until the slime is out. A quit or a closed window writes the
##   resume save (`resume_saves`): the run with the slime at the entrance and all it did kept.
## - **Fainting resumes at the entrance**: this node is the player's respawn override
##   (player.gd RESPAWN_OVERRIDE_GROUP): `respawn_point` is the entrance marker's spot in this
##   world; in another world of the dungeon `respawn_elsewhere` travels there.
## - **Rooms**: its world's CameraRooms (game/world/camera_room.gd) are the dungeon's rooms. The
##   room the slime stands in is visited (the map shows it); walking into another room brings back
##   the beaten placed enemies (EnemyPopulation.spawn_placed: "ordinary room enemies come back when
##   a room is entered again"; room fights keep their own, game/dungeon/room_fight.gd) and the
##   room's pots and other light things that were taken (`room_resets`).
## - **The HUD**: the dungeon's key chip (game/dungeon/dungeon_hud.gd), its rooms on the minimap
##   (dungeon_minimap.gd) and its map on the map screen (dungeon_map_page.gd).
## - **Dev launch options** (once a session): `keys=<n>` small keys, `bigkey`, `dmap` (the map and
##   the compass), `room=<CameraRoom name>` (start in that room, at its `RoomEntry` child or its
##   middle).
##
## In the editor it draws its name.
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const CameraRoom := preload("res://game/world/camera_room.gd")
const DungeonHud := preload("res://game/dungeon/dungeon_hud.gd")
const DungeonMinimap := preload("res://game/dungeon/dungeon_minimap.gd")
const DungeonMapPage := preload("res://game/dungeon/dungeon_map_page.gd")
const LiftableScript := preload("res://game/scripts/liftable.gd")

## player.gd RESPAWN_OVERRIDE_GROUP.
const RESPAWN_OVERRIDE_GROUP := &"respawn_override"
const WORLD_MAIN_GROUP := &"world_main"
const ROOM_ENTRY_NAME := "RoomEntry"
const LABEL_COLOR := Color(1.0, 0.8, 0.35, 0.95)

## The slime walked into another room. Payload: {"room": the room key, "from": the room key left ("" at first)}.
signal room_entered(payload: Dictionary)

## The dungeon's id, the same in every world of it ("fatty-lair"); its record in RunState.
@export var dungeon_id: String = "":
	set(value):
		dungeon_id = value
		queue_redraw()
## Its name on the map screen and the HUD ("Fatty's Lair").
@export var display_name: String = ""
## The Node2D (a marker) where a faint or a quit resumes: its position is the slime's centre there.
## Looked up by name in the world of `entrance_map_id`.
@export var entrance_marker: String = "dungeon-entrance"
## The world of the entrance ("" = this world).
@export var entrance_map_id: String = ""
## A quit or a closed window inside writes the resume save to the autosave slot (off in the dev
## lab, so the title's Continue never starts there, as for the playground).
@export var resume_saves: bool = true
## Walking into another room brings back its beaten enemies and its taken pots.
@export var room_resets: bool = true

## Dev launch options apply once a session per dungeon.
static var _dev_applied: Dictionary = {}

var _rooms: Array[CameraRoom] = []
var _room_key := ""
var _templates: Array[Dictionary] = []
var _hud: Node
var _minimap: Control
var _page: Control
var _registered := false


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(DungeonState.GROUP)
	add_to_group(RESPAWN_OVERRIDE_GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	var world := Services.world()
	if world != null:
		world.world_registered.connect(_on_world_registered)
		if world.world_root != null and world.world_root.is_ancestor_of(self):
			_on_world_registered.call_deferred({})


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var world := Services.world()
	if world != null and world.world_registered.is_connected(_on_world_registered):
		world.world_registered.disconnect(_on_world_registered)
	for template: Dictionary in _templates:
		var node: Node = template.get("template")
		if is_instance_valid(node):
			node.free()
	_templates.clear()
	if is_instance_valid(_minimap):
		_minimap.queue_free()
	if is_instance_valid(_page):
		_page.call(&"detach")
		_page.queue_free()


func _on_world_registered(_payload: Dictionary) -> void:
	if _registered:
		return
	var world := Services.world()
	if world == null or world.world_root == null or not world.world_root.is_ancestor_of(self):
		return
	_registered = true
	_rooms.clear()
	for node: Node in get_tree().get_nodes_in_group(CameraRoom.GROUP):
		if node is CameraRoom and world.world_root.is_ancestor_of(node):
			_rooms.append(node as CameraRoom)
	_record_entrance()
	if room_resets:
		_snapshot_light_things()
	_hud = DungeonHud.new()
	_hud.set(&"dungeon", self)
	add_child(_hud)
	_minimap = DungeonMinimap.attach(self)
	_page = DungeonMapPage.attach(self)
	_apply_dev_options.call_deferred()


# --- the entrance and fainting ------------------------------------------------------------------

## The world of the entrance.
func entrance_world() -> String:
	if not entrance_map_id.is_empty():
		return entrance_map_id
	var world := Services.world()
	return world.map_id() if world != null else ""


## The entrance marker's spot (an old centre) when it is in this world, else null.
func entrance_point() -> Variant:
	var world := Services.world()
	if world == null or world.world_root == null or entrance_world() != world.map_id():
		return null
	var marker := world.world_root.find_child(entrance_marker, true, false) as Node2D
	return marker.global_position if marker != null else null


## player.gd's respawn override: a fainted slime wakes at the entrance (null when it is in another
## world: `respawn_elsewhere` then travels there).
func respawn_point() -> Variant:
	return entrance_point()


## A fainted slime whose entrance is in another world of the dungeon travels there (main.gd
## `respawn_in_world`). False when the entrance is in this world or not known yet.
func respawn_elsewhere() -> bool:
	var world := Services.world()
	var run := Services.run()
	if world == null or run == null or entrance_world() == world.map_id():
		return false
	var at := DungeonState.entrance(run, dungeon_id)
	if at.is_empty() or str(at.get("map_id", "")) == world.map_id():
		return false
	var main := get_tree().get_first_node_in_group(WORLD_MAIN_GROUP)
	return main != null and main.has_method(&"respawn_in_world") and bool(main.call(&"respawn_in_world", at))


func _record_entrance() -> void:
	var at: Variant = entrance_point()
	var run := Services.run()
	var world := Services.world()
	if at is Vector2 and run != null and world != null:
		DungeonState.set_entrance(run, dungeon_id, world.map_id(), at)


# --- rooms --------------------------------------------------------------------------------------

## The dungeon's rooms in this world: [{"key", "name", "rect", "node"}].
func rooms() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room: CameraRoom in _rooms:
		if is_instance_valid(room):
			out.append({"key": room_key_of(room), "name": String(room.name), "rect": room.rect(), "node": room})
	return out


## A room's key in the record: "<map id>/<room name>".
func room_key_of(room: CameraRoom) -> String:
	var world := Services.world()
	return "%s/%s" % [world.map_id() if world != null else "", room.name]


## The room that holds `point` (global), or null.
func room_at(point: Vector2) -> CameraRoom:
	for room: CameraRoom in _rooms:
		if is_instance_valid(room) and room.rect().has_point(point):
			return room
	return null


## The key of the room the slime is in ("" before it stood in one).
func current_room_key() -> String:
	return _room_key


func _physics_process(_delta: float) -> void:
	if not _registered:
		return
	var world := Services.world()
	if world == null or world.player == null or not is_instance_valid(world.player):
		return
	var room := room_at(world.player.get_centre())
	if room == null:
		return
	var key := room_key_of(room)
	if key == _room_key:
		return
	var left := _room_key
	_room_key = key
	var run := Services.run()
	if run != null:
		DungeonState.visit_room(run, dungeon_id, key)
	if room_resets and not left.is_empty():
		_reset_room(room)
	room_entered.emit({"room": key, "from": left})


## The room's beaten enemies come back (every placed enemy that is not standing: EnemyPopulation
## spawns them again) and its taken light things are put back.
func _reset_room(room: CameraRoom) -> void:
	var main := get_tree().get_first_node_in_group(WORLD_MAIN_GROUP)
	var population: Node = main.get(&"enemy_population") if main != null else null
	if population != null and is_instance_valid(population) and population.has_method(&"spawn_placed"):
		population.call(&"spawn_placed")
	var rect := room.rect()
	for template: Dictionary in _templates:
		var current: Variant = template.get("current")
		if is_instance_valid(current) and not (current as Node).is_queued_for_deletion():
			continue
		if not rect.has_point(template["position"]):
			continue
		var parent: Node = template.get("parent")
		var source: Node = template.get("template")
		if not is_instance_valid(parent) or not is_instance_valid(source):
			continue
		var copy := source.duplicate() as Node2D
		parent.add_child(copy)
		copy.global_position = template["position"]
		template["current"] = copy


## Keeps a copy of every light thing (a liftable: pots, crates, ...) standing in a room, so it can
## be put back when the room is entered again.
func _snapshot_light_things() -> void:
	var world := Services.world()
	for node: Node in get_tree().get_nodes_in_group(LiftableScript.GROUP):
		var root := node.get_parent() as Node2D
		if root == null or world.world_root == null or not world.world_root.is_ancestor_of(root):
			continue
		if room_at(root.global_position) == null:
			continue
		_templates.append({"template": root.duplicate(), "parent": root.get_parent(), "position": root.global_position,
			"current": root})


# --- dev launch options -------------------------------------------------------------------------

func _apply_dev_options() -> void:
	var main := get_tree().get_first_node_in_group(WORLD_MAIN_GROUP)
	var run := Services.run()
	if main == null or run == null or not main.has_method(&"launch_option") or _dev_applied.has(dungeon_id):
		return
	_dev_applied[dungeon_id] = true
	var keys := str(main.call(&"launch_option", "keys"))
	if keys.is_valid_int() and int(keys) > 0:
		DungeonState.add_small_key(run, dungeon_id, int(keys))
	if bool(main.call(&"has_launch_option", "bigkey")):
		DungeonState.give_item(run, dungeon_id, DungeonState.BIG_KEY)
	if bool(main.call(&"has_launch_option", "dmap")):
		DungeonState.give_item(run, dungeon_id, DungeonState.MAP)
		DungeonState.give_item(run, dungeon_id, DungeonState.COMPASS)
	var room_name := str(main.call(&"launch_option", "room"))
	if not room_name.is_empty():
		for room: CameraRoom in _rooms:
			if String(room.name) == room_name:
				var entry := room.get_node_or_null(ROOM_ENTRY_NAME) as Node2D
				var world := Services.world()
				if world != null and world.player != null:
					world.player.teleport(entry.global_position if entry != null else room.rect().get_center())


# --- the editor ---------------------------------------------------------------------------------

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_circle(Vector2.ZERO, 10.0, LABEL_COLOR)
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, Vector2(14, 6), "dungeon: " + dungeon_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, LABEL_COLOR)
