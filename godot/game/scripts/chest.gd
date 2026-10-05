extends Node
class_name ChestScript
## Scene script `game.chest` (Phaser `features/scripts/ChestScript.ts`; interaction spec 3.4, 6.3).
## Persistent contents in `RunState.map_record(map_id).chests` (created from `initial_contents`
## on first sight); a live boss camp may guard the chest. Opening emits `open_requested` and hands
## the chest to the chest window (`CHEST_VIEW_SERVICE`: the first node of group `chest_window`,
## game/ui/screens/chest_window.gd, `open_chest`); each stack moved into the bag emits
## `stack_transferred`; closing tells the window (`close_for`) and emits `closed`. Leaving the tree
## while open closes the window without `closed` (Phaser's entry disposable, owner decision K4).
##
## Owner: interaction.

const Services := preload("res://game/shared/services.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

const GROUP := &"chest"
const BOSS_CAMP_GROUP := &"boss_camp"
const VIEW_GROUP := &"chest_window"

## JSON `mapId`.
@export var map_id: String = ""
## JSON `instanceId`.
@export var instance_id: String = ""
## JSON `initialContents`: {item_id: positive count}.
@export var initial_contents: Dictionary = {}

## The chest is guarded by a live boss. Payload: {"instanceId"}.
signal guard_blocked(payload: Dictionary)
## The chest opened. Payload: {"mapId", "instanceId", "contents"}.
signal open_requested(payload: Dictionary)
## A stack moved into the bag. Payload: {"itemId", "moved"}.
signal stack_transferred(payload: Dictionary)
## The chest closed. Payload: {"instanceId"}.
signal closed(payload: Dictionary)

var _open: bool = false


func _enter_tree() -> void:
	add_to_group(GROUP)
	var run := Services.run()
	if run != null:
		run.ensure_chest(map_id, instance_id, positive_counts(initial_contents))


func _exit_tree() -> void:
	if _open:
		_open = false
		var view := _view()
		if view != null:
			view.call(&"close_for", instance_id)


## Old Phaser position of the chest (its parent).
func origin() -> Vector2:
	var parent := get_parent() as Node2D
	return FeetAnchor.phaser_position(parent) if parent != null else Vector2.ZERO


## A copy of what is left inside.
func remaining() -> Dictionary:
	var run := Services.run()
	return run.chest_remaining(map_id, instance_id) if run != null else {}


func is_empty() -> bool:
	return remaining().is_empty()


## A live boss camp guards this chest (BossCampScript.isChestGuarded).
func is_guarded() -> bool:
	for camp: Node in get_tree().get_nodes_in_group(BOSS_CAMP_GROUP):
		if camp.has_method(&"is_chest_guarded") and bool(camp.call(&"is_chest_guarded", instance_id)):
			return true
	return false


## "guarded" (emits `guard_blocked`) or "opened" (emits `open_requested`, then the chest window
## shows this chest; an empty chest opens too).
func request_open() -> String:
	if is_guarded():
		guard_blocked.emit({"instanceId": instance_id})
		return "guarded"
	_open = true
	open_requested.emit({"mapId": map_id, "instanceId": instance_id, "contents": remaining()})
	var view := _view()
	if view != null:
		view.call(&"open_chest", self)
	return "opened"


## Moves as much of `item_id` as fits into the bag; emits `stack_transferred` when anything moved.
func transfer_stack(item_id: String) -> int:
	var run := Services.run()
	var moved := run.transfer_chest_stack(map_id, instance_id, item_id) if run != null else 0
	if moved > 0:
		stack_transferred.emit({"itemId": item_id, "moved": moved})
	return moved


## `ChestScript.close`: the window lets go of this chest (a no-op when it closed itself first),
## then `closed`.
func close() -> void:
	_open = false
	var view := _view()
	if view != null:
		view.call(&"close_for", instance_id)
	closed.emit({"instanceId": instance_id})


## The chest window (group `chest_window`), or null.
func _view() -> Node:
	return get_tree().get_first_node_in_group(VIEW_GROUP) if is_inside_tree() else null


## `syncChestFrame`: the first Sprite2D under the chest root shows frame 1 when empty, else 0.
func sync_frame() -> void:
	var root := get_parent()
	if root == null:
		return
	var sprites := root.find_children("*", "Sprite2D", true, false)
	if sprites.is_empty():
		return
	var visual := sprites[0] as Sprite2D
	var frame := 1 if is_empty() else 0
	if visual.frame != frame and visual.hframes * visual.vframes > frame:
		visual.frame = frame


## `recordOfPositiveIntegers`: entries whose count is a whole number > 0.
static func positive_counts(contents: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in contents:
		var value: Variant = contents[key]
		if (value is int or value is float) and float(value) == roundf(float(value)) and float(value) > 0.0:
			out[str(key)] = int(value)
	return out
