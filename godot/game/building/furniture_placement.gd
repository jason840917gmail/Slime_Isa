extends Node2D
## Furniture placement (Phaser `features/building/FurniturePlacementController.ts` + the
## `WorldScene` glue: `startFurniturePlacement`, `isFootprintFree`, `placeFurniture`,
## `pickUpFurniture`; furniture spec). Child "FurniturePlacement" of main (after World), made once,
## kept across worlds; group `furniture_placement`.
##
## Crafting a Workbench, or "Place" in the bag, starts placement mode: a translucent ghost of the
## bench follows the pointer snapped to 32 px, green (#9dffc8) where it is within 220 px of the
## slime's centre on a free footprint, red (#ff7a7a) otherwise, with a 2 px outline round the
## footprint. The game keeps running and the slime keeps walking. Left click places (the bench
## leaves the bag, a record joins the map's `placed_furniture`, the bench is mounted and the quest
## event `furniture.placed` goes out, "Placed Workbench"); the mouse wheel switches the variant
## (bench / bench with vise); right click or Esc cancels (the bench stays in the bag). A placed
## bench is a crafting station; holding the interact button on it for 450 ms picks it up again.
## Every world load mounts the map's records again.
##
## Free footprint: inside the world and touching no static body (walls, props, water, other
## benches) and not the player (a physics shape query on the world, player and water layers).
## Owner decision F1 (recommended in the spec): placement ends when the slime dies.
##
## Owner: world objects (building).

const Services := preload("res://game/shared/services.gd")
const PlacedFurniture := preload("res://game/building/placed_furniture.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")

const GROUP := &"furniture_placement"
## FurniturePlacementController.ts:47-51, 121, 160.
const SNAP_PX := 32.0
const REACH_PX := 220.0
const VALID_TINT := Color("#9dffc8")
const INVALID_TINT := Color("#ff7a7a")
const GHOST_ALPHA := 0.65
const OUTLINE_WIDTH := 2.0
const OUTLINE_ALPHA := 0.9
## WorldScene.ts:1210, 1245, 1251, 1261, 1271, 1275.
const HINT_RISE := 56.0
const PLACED_TEXT_RISE := 48.0
const PICK_UP_TEXT_RISE := 56.0
const RESPAWN_CLEAR_PX := 128.0
## Blocking layers for the free test: world (1) | player (2) | water (11).
const BLOCKING_MASK := 1 | 2 | 1024
const BOUNDS_NAME := &"WorldBounds"

## Placement started or ended. Payload: {"active": bool, "item_id": String}.
signal placement_changed(payload: Dictionary)
## A text was shown. Payload: {"text", "color", "big", "x", "y"} (test hook).
signal message_shown(payload: Dictionary)
## A bench was placed and mounted. Payload: the record.
signal placed(payload: Dictionary)
## A bench was picked up (Phaser `furniture.picked-up`). Payload: {"mapId", "placementId", "itemId"}.
signal picked_up(payload: Dictionary)

## Test hook: a world point used instead of the mouse.
var aim_override: Variant = null

var _item_id: String = ""
var _scene_ids: PackedStringArray = PackedStringArray()
var _variant: int = 0
var _visual: Dictionary = {}
var _target: Dictionary = {}
var _ghost: Node2D
var _outline: Node2D
var _bound_player: Node


func _init() -> void:
	name = "FurniturePlacement"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -5
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	add_to_group(GROUP)
	_ghost = Node2D.new()
	_ghost.name = "Ghost"
	_ghost.visible = false
	_ghost.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_ghost)
	_outline = Node2D.new()
	_outline.name = "Outline"
	_outline.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_outline.draw.connect(_draw_outline)
	add_child(_outline)


func _physics_process(_delta: float) -> void:
	_bind_player()
	if not is_active() or get_tree().paused:
		return
	update_target(aim_override if aim_override is Vector2 else get_global_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or event.is_echo() or not event.is_pressed():
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()


func is_active() -> bool:
	return not _item_id.is_empty()


func item_id() -> String:
	return _item_id


func scene_ids() -> PackedStringArray:
	return _scene_ids


func variant_index() -> int:
	return _variant


## {} before the first step, else {"x", "y", "valid": bool, "footprint": Rect2 or null}.
func target() -> Dictionary:
	return _target


## `startFurniturePlacement` + `controller.start` (§2.2): refused (false) while the game is paused,
## a travel runs, the slime is dead, the bag lacks the item or it is not placeable.
func start(item_id_value: String) -> bool:
	var run := Services.run()
	var player := _player()
	var main := get_tree().get_first_node_in_group(&"world_main")
	if run == null or player == null or get_tree().paused or bool(player.call(&"is_dead")) or run.item_count(item_id_value) < 1:
		return false
	if main != null and main.has_method(&"is_transitioning") and bool(main.call(&"is_transitioning")):
		return false
	var placeable: Variant = ItemCatalog.definition(item_id_value).get("placeable")
	var ids := PackedStringArray()
	if placeable is Dictionary:
		for id: Variant in (placeable as Dictionary).get("sceneIds", []):
			ids.append(str(id))
	if ids.is_empty():
		return false
	cancel()
	_item_id = item_id_value
	_scene_ids = ids
	_variant = 0
	if not _show_variant():
		cancel()
		return false
	placement_changed.emit({"active": true, "item_id": _item_id})
	var place := ControlLabels.control_label(&"attack")
	var leave := "%s or %s" % [ControlLabels.control_label(&"interact"), ControlLabels.control_label(&"pause")]
	var hint := ("%s to place · %s to switch · %s to cancel" % [place, ControlLabels.control_label(&"weapon_next"), leave]) \
		if ids.size() > 1 else ("%s to place · %s to cancel" % [place, leave])
	_text((player.call(&"get_centre") as Vector2) - Vector2(0.0, HINT_RISE), hint, &"white", false)
	return true


## Ends placement mode (no text, no sound); the item never left the bag.
func cancel() -> void:
	var was_active := is_active()
	_item_id = ""
	_scene_ids = PackedStringArray()
	_visual = {}
	_target = {}
	for child in _ghost.get_children():
		child.queue_free()
	_ghost.visible = false
	_outline.queue_redraw()
	if was_active:
		placement_changed.emit({"active": false, "item_id": ""})


## The next (+1) or previous (-1) variant (the mouse wheel); nothing with a single variant.
func cycle_variant(step: int) -> void:
	if not is_active() or _scene_ids.size() < 2:
		return
	_variant = posmod(_variant + step, _scene_ids.size())
	_show_variant()
	if not _target.is_empty():
		update_target(Vector2(float(_target["x"]), float(_target["y"])))


## `handlePointerDown` (§6.1): the place press. True when placement used it.
func press_place() -> bool:
	if not is_active():
		return false
	var player := _player()
	if _target.is_empty() or not bool(_target["valid"]):
		var at := (player.call(&"get_centre") as Vector2) - Vector2(0.0, HINT_RISE) if player != null else Vector2.ZERO
		_text(at, "Can't place it there" if not _target.is_empty() else "Aim at a free spot", &"white", false)
		return true
	if place(_item_id, _scene_ids[_variant], Vector2(float(_target["x"]), float(_target["y"]))):
		cancel()
	return true


## One `update()` (§3.1) for the world point `pointer`.
func update_target(pointer: Vector2) -> void:
	if not is_active() or _visual.is_empty():
		return
	var player := _player()
	var point := Vector2(snap(pointer.x), snap(pointer.y))
	var in_reach := player != null and (player.call(&"get_centre") as Vector2).distance_to(point) <= REACH_PX
	var footprint: Variant = null
	if _visual["footprint"] is Rect2:
		var local: Rect2 = _visual["footprint"]
		footprint = Rect2(point + local.position, local.size)
	var valid := in_reach and (footprint == null or is_footprint_free(footprint))
	_target = {"x": point.x, "y": point.y, "valid": valid, "footprint": footprint}
	var tint := VALID_TINT if valid else INVALID_TINT
	_ghost.position = point + (_visual["depth_anchor"] as Vector2)
	_ghost.modulate = Color(tint, GHOST_ALPHA)
	_ghost.visible = true
	_outline.queue_redraw()


## `isFootprintFree` (§4): inside the world, no static body and not the player.
func is_footprint_free(rect: Rect2) -> bool:
	var world := Services.world()
	if world == null or not world.world_rect().encloses(rect):
		return false
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, rect.get_center())
	query.collision_mask = BLOCKING_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 32):
		var collider: Object = hit.get("collider")
		if collider == world.player_body:
			return false
		if collider is StaticBody2D and (collider as Node).name != BOUNDS_NAME:
			return false
	return true


## The commit (§6.2): the bench leaves the bag, is recorded, mounted, announced. False when nothing
## was placed (a failed mount gives the bench back).
func place(item_id_value: String, scene_id: String, point: Vector2) -> bool:
	var run := Services.run()
	var world := Services.world()
	if run == null or world == null:
		return false
	var map_id := world.map_id()
	var item_name := ItemCatalog.item_name(item_id_value)
	if not run.transact_items([{"item_id": item_id_value, "count": 1}], []):
		return false
	var record := run.place_furniture(map_id, item_id_value, scene_id, point.x, point.y)
	if PlacedFurniture.mount(record) == null:
		run.remove_placed_furniture(map_id, str(record["id"]))
		run.transact_items([], [{"item_id": item_id_value, "count": 1}])
		_text(point - Vector2(0.0, PLACED_TEXT_RISE), "%s could not be placed" % item_name, &"white", true)
		return false
	QuestEvents.emit(QuestEvents.FURNITURE_PLACED, {"mapId": map_id, "placementId": record["id"], "itemId": item_id_value,
		"sceneId": scene_id, "x": point.x, "y": point.y})
	placed.emit(record)
	_text(point - Vector2(0.0, PLACED_TEXT_RISE), "Placed %s" % item_name, &"green", false)
	return true


## `pickUpFurniture` (§8.3): the bench goes back into the bag. False when refused.
func pick_up(placement_id: String) -> bool:
	var run := Services.run()
	var world := Services.world()
	if run == null or world == null or get_tree().paused or is_active():
		return false
	var map_id := world.map_id()
	var record: Dictionary = {}
	for entry in run.placed_furniture(map_id):
		if str(entry["id"]) == placement_id:
			record = entry
	if record.is_empty():
		return false
	var at := Vector2(float(record["x"]), float(record["y"]))
	var item := str(record["item_id"])
	var add := [{"item_id": item, "count": 1}]
	if not run.transact_items([], add, true):
		_text(at - Vector2(0.0, PICK_UP_TEXT_RISE), "Inventory full", &"white", true)
		return false
	run.remove_placed_furniture(map_id, placement_id)
	PlacedFurniture.unmount(placement_id)
	run.transact_items([], add)
	var respawn := run.respawn_point()
	if not respawn.is_empty() and str(respawn.get("map_id", "")) == map_id:
		var bed_id := str(respawn.get("bed_id", ""))
		var clears := bed_id == "placed-furniture:" + placement_id if not bed_id.is_empty() \
			else Vector2(float(respawn.get("x", 0.0)), float(respawn.get("y", 0.0))).distance_to(at) < RESPAWN_CLEAR_PX
		if clears:
			run.clear_respawn_point()
	picked_up.emit({"mapId": map_id, "placementId": placement_id, "itemId": item})
	_text(at - Vector2(0.0, PICK_UP_TEXT_RISE), "Picked up %s" % ItemCatalog.item_name(item), &"cyan", false)
	return true


## Mounts every placed record of `map_id` (§7.3); main calls it on every world build.
func restore_world(map_id: String) -> void:
	var run := Services.run()
	if run == null:
		return
	for record in run.placed_furniture(map_id):
		PlacedFurniture.mount(record)


## World teardown: placement ends quietly (the benches go with the world root).
func clear() -> void:
	cancel()


## `Math.round(v / 32) * 32` (halves go up, as in JS).
static func snap(value: float) -> float:
	return floorf(value / SNAP_PX + 0.5) * SNAP_PX


func _show_variant() -> bool:
	for child in _ghost.get_children():
		child.queue_free()
	_visual = PlacedFurniture.describe(_scene_ids[_variant])
	if _visual.is_empty():
		return false
	var sprite: Sprite2D = _visual["sprite"]
	_ghost.add_child(sprite)
	return true


func _draw_outline() -> void:
	if not is_active() or _target.is_empty() or not (_target["footprint"] is Rect2):
		return
	var tint := VALID_TINT if bool(_target["valid"]) else INVALID_TINT
	_outline.draw_rect(_target["footprint"], Color(tint, OUTLINE_ALPHA), false, OUTLINE_WIDTH)


## Owner decision F1: the slime's defeat ends placement.
func _bind_player() -> void:
	var player := _player()
	if player == _bound_player:
		return
	_bound_player = player
	if player != null and player.has_signal(&"defeated") and not player.is_connected(&"defeated", _on_player_defeated):
		player.connect(&"defeated", _on_player_defeated)


func _on_player_defeated(_payload: Dictionary) -> void:
	cancel()


func _text(at: Vector2, text: String, color: StringName, big: bool) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(at, text, color, big)
	message_shown.emit({"text": text, "color": color, "big": big, "x": at.x, "y": at.y})


func _player() -> Node:
	var world := Services.world()
	var player: Variant = world.player if world != null else null
	return player if player != null and is_instance_valid(player) else null
