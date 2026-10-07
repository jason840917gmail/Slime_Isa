extends Node
## Scene script `game.story-variant` (Phaser `features/scripts/StoryVariantScript.ts`): one
## subtree for before and one for after a story flag, authored side by side. Only the matching
## subtree stays in the scene tree, so its visuals, collision, doors and stations exist and the
## other's do not. The handler `set` (converter name `on_set`) sets the flag.
##
## Phaser checks the flag every frame; here the variant follows `RunState.story_flag_changed`.
## The first swap is deferred one frame: a node cannot be taken out of its parent while that
## parent is still readying its children (the arrival fade covers that frame).
##
## Owner: world objects.

const Services := preload("res://game/shared/services.gd")

## JSON `flagId`.
@export var flag_id: String = ""
## JSON `whenSet`: the subtree kept once the flag is set (optional).
@export var when_set: Node
## JSON `whenUnset`: the subtree kept before (optional).
@export var when_unset: Node

## After every swap. Payload: {"flagId": String, "set": bool}.
signal switched(payload: Dictionary)

var _shown: Variant = null
## Variant subtrees taken out of the tree -> the parent to put them back under.
var _parked: Dictionary = {}


func _ready() -> void:
	var run := Services.run()
	if run != null and not run.story_flag_changed.is_connected(_on_story_flag_changed):
		run.story_flag_changed.connect(_on_story_flag_changed)
	_apply.call_deferred()


func _exit_tree() -> void:
	var run := Services.run()
	if run != null and run.story_flag_changed.is_connected(_on_story_flag_changed):
		run.story_flag_changed.disconnect(_on_story_flag_changed)
	# Parked subtrees are out of the tree, so the tree cannot free them: free them with us.
	for node: Node in _parked.keys():
		if is_instance_valid(node):
			node.queue_free()
	_parked.clear()


## True while the "flag set" variant is the one in the tree.
func is_flag_shown() -> bool:
	return _shown == true


## Handler `set`: sets the flag (once) and swaps.
func on_set(_payload: Variant = null) -> void:
	var run := Services.run()
	if flag_id.is_empty() or run == null or run.has_flag(flag_id):
		return
	run.set_flag(flag_id)
	_apply()


func _on_story_flag_changed(payload: Dictionary) -> void:
	if str(payload.get("flag", "")) == flag_id and _flag_is_set() != _shown:
		_apply()


func _flag_is_set() -> bool:
	var run := Services.run()
	return not flag_id.is_empty() and run != null and run.has_flag(flag_id)


func _apply() -> void:
	if not is_inside_tree():
		return
	var flag_set := _flag_is_set()
	_shown = flag_set
	var active: Node = when_set if flag_set else when_unset
	var inactive: Node = when_unset if flag_set else when_set
	if inactive != null and is_instance_valid(inactive) and inactive.is_inside_tree():
		var parent := inactive.get_parent()
		if parent != null:
			_parked[inactive] = parent
			parent.remove_child(inactive)
	if active != null and is_instance_valid(active) and _parked.has(active):
		var parent: Node = _parked[active]
		_parked.erase(active)
		if is_instance_valid(parent):
			parent.add_child(active)
	switched.emit({"flagId": flag_id, "set": flag_set})
