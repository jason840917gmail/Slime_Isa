extends Node
class_name DoorScript
## Scene script `game.door` (Phaser `features/scripts/DoorScript.ts`; interaction spec 3.2, 6.1).
## A data holder: the interaction controller offers it (priority 90, within `interact_radius` of
## the door's parent) and `use()` asks main.gd to travel to `target_area_id`, arriving at
## `target_door_id`'s arrival point there (the door's parent's child named "arrival", else the
## parent; game/world/area_travel.gd snaps it to a tile centre).
##
## Owner: interaction.

const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

## Contract of game/world/area_travel.gd: doors are found by `door_id` in this group.
const GROUP := &"door"
const MAIN_GROUP := &"world_main"
const DEFAULT_RADIUS := 96.0
const DEFAULT_BADGE_RISE := 56.0

## JSON `mapId`.
@export var map_id: String = ""
## JSON `doorId`.
@export var door_id: String = ""
## JSON `targetAreaId`.
@export var target_area_id: String = ""
## JSON `targetDoorId`.
@export var target_door_id: String = ""
## JSON `prompt` ("Enter house", "Leave hut", ...).
@export var prompt: String = "Use door"
## JSON `interactRadius` (> 0, else 96).
@export var interact_radius: float = DEFAULT_RADIUS
## JSON `badgeRise`: how far above the door the key badge floats.
@export var badge_rise: float = DEFAULT_BADGE_RISE
## The global audio cue played when the door is used (the cracked-ground hole falls instead).
@export var use_cue: StringName = &"DoorUse"


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if not (is_finite(interact_radius) and interact_radius > 0.0):
		interact_radius = DEFAULT_RADIUS
	if not is_finite(badge_rise):
		badge_rise = DEFAULT_BADGE_RISE


## Old Phaser position of the door (its parent).
func origin() -> Vector2:
	var parent := get_parent() as Node2D
	return FeetAnchor.phaser_position(parent) if parent != null else Vector2.ZERO


## `WorldSceneLoader.doorArrivals`: the parent's child named "arrival", else the parent, rounded.
func arrival_point() -> Vector2:
	var parent := get_parent() as Node2D
	if parent == null:
		return Vector2.ZERO
	var arrival := parent.get_node_or_null(^"arrival") as Node2D
	var point := (arrival if arrival != null else parent).global_position
	return Vector2(floorf(point.x + 0.5), floorf(point.y + 0.5))


## The door's execute (UniversalSceneWorldController.doorCandidate): main's `request_exit` result.
func use() -> Dictionary:
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	if main == null or not main.has_method(&"request_exit"):
		return {"status": "blocked", "message": "Navigation unavailable"}
	return main.call(&"request_exit", {"map_id": map_id, "exit_id": door_id,
		"target_area_id": target_area_id, "entry": "", "target_door_id": target_door_id, "gate": {}})
