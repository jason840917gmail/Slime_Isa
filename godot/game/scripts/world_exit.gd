extends Node
class_name WorldExitScript
## Scene script `game.world-exit` (Phaser `features/scripts/WorldExitScript.ts`). World spec 8.
##
## Level-triggered like Phaser: on `area.body_entered` and on every physics step for every body
## still inside, once `arrival_grace_ms` of simulation time has passed since the exit entered the
## tree and until a request was queued, the player's body asks main.gd to travel
## (`Main.request_exit`: gate check, then the leave fade and the next world). Standing in an exit
## when a world loads does nothing until the grace ends; unlocking its gate while standing in it
## travels without stepping out. Other bodies (NPCs) never count
## (UniversalSceneWorldController.ts:648-655).
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")
const MAIN_GROUP := &"world_main"

## JSON `mapId` (the world this exit belongs to).
@export var map_id: String = ""
## JSON `exitId`.
@export var exit_id: String = ""
## JSON `targetAreaId` (e.g. "gloop-forest").
@export var target_area_id: String = ""
## JSON `entry`: arrival edge in the target world ("west", ...).
@export var entry: String = ""
## JSON `area`: the Area2D (layer trigger, mask player|npc) whose bodies are tested.
@export var area: Area2D
## JSON `gate` (camelCase keys: id, requiredItemId, consumeOnUnlock, lockedMessage).
@export var gate: Dictionary = {}
## JSON `arrivalGraceMs` (absent in every scene): < 0 means use game-constants
## `worldNavigation.edgeTransitionGraceMs` (650).
@export var arrival_grace_ms: float = -1.0

## The exit service's answer to each request. Payload: {"status": "ignored"|"blocked"|"queued",
## "message"?}.
signal navigation_resolved(result: Dictionary)

var _simulation_ms: float = 0.0
var _queued: bool = false
var _grace_ms: float = 0.0


func _enter_tree() -> void:
	_simulation_ms = 0.0
	_queued = false
	_grace_ms = arrival_grace_ms
	if _grace_ms < 0.0:
		var constants := Services.constants()
		_grace_ms = constants.number("worldNavigation.edgeTransitionGraceMs") if constants != null else 0.0
	set_physics_process(true)


func _exit_tree() -> void:
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	_simulation_ms += delta * 1000.0
	if _queued or _simulation_ms < _grace_ms or area == null or not is_instance_valid(area):
		return
	for body: Node2D in area.get_overlapping_bodies():
		_evaluate(body)
		if _queued:
			return


## Connected from `area.body_entered`.
func on_body_entered(body: Node) -> void:
	_evaluate(body)


func _evaluate(body: Node) -> void:
	if _queued or _simulation_ms < _grace_ms or not body is CharacterBody2D:
		return
	var world := Services.world()
	if world == null or body != world.player_body:
		return
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	var result: Dictionary = {"status": "blocked", "message": "Navigation unavailable"}
	if main != null and main.has_method(&"request_exit"):
		result = main.call(&"request_exit", {
			"map_id": map_id,
			"exit_id": exit_id,
			"target_area_id": target_area_id,
			"entry": entry,
			"gate": gate,
		})
	if str(result.get("status", "")) == "queued":
		_queued = true
	navigation_resolved.emit(result)
