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
const BorderCrossing := preload("res://game/world/crossings/border_crossing.gd")
const WorldChunks := preload("res://game/world/atlas/world_chunks.gd")
const MAIN_GROUP := &"world_main"
## How far from where the slime comes out the far side's exit back may lie (world units).
const BORDER_SLACK := 96.0

## JSON `mapId` (the world this exit belongs to).
@export var map_id: String = ""
## JSON `exitId`.
@export var exit_id: String = ""
## JSON `targetAreaId` (e.g. "gloop-forest").
@export var target_area_id: String = ""
## JSON `entry`: arrival edge in the target world ("west", ...). Crossing a border of the atlas the
## slime comes out at the same place across it (`_cross_by_coordinates`); otherwise at the target's
## spawn.
@export var entry: String = ""
## Not in Phaser (2026-10-31): the end in the target world the slime comes out of (a door's
## `door_id`: an arrival point, game/scripts/door.gd), for an exit that is no border (the mine's
## mouth and its way out). It wins over `entry`.
@export var target_door_id: String = ""
## Not in Phaser (chunk worlds, 2026-10-12): the player arrives at the same place along the `entry`
## edge as where it left this world (`entry_along`, `AreaTravel.arrival_point`): for an exit along a
## whole edge between two worlds that carry on from each other (the chunks of a region,
## godot/tools/split_region_chunks.gd).
@export var keep_along: bool = false
## Not in Phaser (2026-10-31): for a `keep_along` exit between two worlds that are not chunks of the
## atlas grid (the playground and its annex), how far the target's frame is shifted along the edge:
## the slime comes out at its place along this edge plus this (world units), and the screen scrolls
## across. 0 for chunks, whose grid lines up.
@export var along_offset: float = 0.0
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
		var request := {
			"map_id": map_id,
			"exit_id": exit_id,
			"target_area_id": target_area_id,
			"entry": entry,
			"target_door_id": target_door_id,
			"gate": gate,
		}
		if keep_along and world.player != null:
			request["entry_along"] = _along(world) + along_offset
			if not is_zero_approx(along_offset):
				request["scroll_across"] = true
				request["along_shift"] = along_offset
		elif world.player != null and target_door_id.is_empty():
			_cross_by_coordinates(world, request)
		result = main.call(&"request_exit", request)
	if str(result.get("status", "")) == "queued":
		_queued = true
	navigation_resolved.emit(result)


## An exit into a neighbouring region of the overworld (2026-10-31, docs/design/
## 2026-10-31-crossings-and-arrivals.md D5): when this world and the target are chunks of the atlas
## grid, the slime comes out across the border at the same place (BorderCrossing.across), in the
## chunk there, and the screen scrolls (`worldNavigation.regionBorderScroll`); the exit's `entry` is
## not used then. Where the far side's opening back lies elsewhere along the border (the two sides
## drawn apart), it comes out of that opening, the scroll shifted to meet it (`along_shift`). Without
## the grid, or when no exit leads back along the border (an opening drawn on this side only:
## BorderCrossing.opening_back), `request` is left as it is: the slime arrives at the region's spawn.
func _cross_by_coordinates(world: Node, request: Dictionary) -> void:
	var constants := Services.constants()
	if constants == null or constants.number("worldNavigation.regionBorderScroll") <= 0.0:
		return
	var here := map_id if not map_id.is_empty() else str(world.map_id())
	var crossing := BorderCrossing.across(here, target_area_id, exit_edge(world), world.player.get_centre())
	if crossing.is_empty():
		return
	# Only into an opening: the one back at this place, else the nearest one back along the border.
	var back := BorderCrossing.opening_back(crossing, PackedStringArray([here, WorldChunks.world_of(here)]), BORDER_SLACK)
	if back.is_empty():
		return
	var along := float(back["along"])
	request["target_area_id"] = back["world"]
	request["entry"] = back["edge"]
	request["entry_along"] = along
	request["scroll_across"] = true
	if not is_equal_approx(along, float(crossing["along"])):
		request["along_shift"] = along - float(crossing["along"])


## The edge of this world the exit lies on (`area`'s first rectangle); "" without an area.
func exit_edge(world: Node) -> String:
	var rect := _area_rect()
	if not rect.has_area():
		return ""
	return edge_of(rect, world.world_rect())


## The edge of `bounds` the exit strip `rect` lies along: a strip taller than wide lies on the west or
## east edge, a wider one on the north or south (an opening split between two chunks also touches
## the chunk's other edge at its end); the nearest of those.
static func edge_of(rect: Rect2, bounds: Rect2) -> String:
	var gaps := {"north": rect.position.y - bounds.position.y, "south": bounds.end.y - rect.end.y,
		"west": rect.position.x - bounds.position.x, "east": bounds.end.x - rect.end.x}
	var candidates: Array = gaps.keys()
	if rect.size.y > rect.size.x:
		candidates = ["west", "east"]
	elif rect.size.x > rect.size.y:
		candidates = ["north", "south"]
	var best := ""
	for edge: String in candidates:
		if best.is_empty() or float(gaps[edge]) < float(gaps[best]):
			best = edge
	return best


## The trigger area's first rectangle in world space (empty without one).
func _area_rect() -> Rect2:
	if area == null or not is_instance_valid(area):
		return Rect2()
	for child: Node in area.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node != null and shape_node.shape is RectangleShape2D:
			var size := (shape_node.shape as RectangleShape2D).size * shape_node.global_scale.abs()
			return Rect2(shape_node.global_position - size * 0.5, size)
	return Rect2()


## Where the player (its old Phaser centre) is along the edge it arrives at: its distance from the
## world's top edge for an east or west entry, from its left edge for a north or south one.
func _along(world: Node) -> float:
	var centre: Vector2 = world.player.get_centre()
	var bounds: Rect2 = world.world_rect()
	return centre.y - bounds.position.y if entry == "east" or entry == "west" else centre.x - bounds.position.x
