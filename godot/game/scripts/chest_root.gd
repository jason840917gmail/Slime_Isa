@tool
extends StaticBody2D
## The root of a chest (`object.chest-wooden`, `object.dungeon-chest`, `object.dungeon-big-chest`;
## docs/godot/specs/interaction.md "Chests"): what a designer sets on a placed chest, in the
## Inspector, on the chest itself (owner, 2026-11-23: "a list of items on a coffer property by
## default, then a list of what is left"). Properties on an instance's root survive every editor
## save and the Editable Children toggle; the older way, overrides on its `ChestScript` child, is
## lost when Editable Children is turned off.
##
## - `contents`: what it holds at the start, {item_id: count}. The run keeps what is left in the
##   map's chest record (RunState `ensure_chest`, `chest_remaining`: created from this list the
##   first time the chest is seen, then only what the slime has not taken).
## - `heart_id`: a Goo Heart inside (chest.gd `goo_heart_id`).
## - `starts_hidden` (dungeon chests): it is not there until it appears (dungeon_chest.gd `hidden`).
## - `chest_id`, `map_id`: its record's place. Empty, the chest's own name and the world's map are
##   used (chest.gd); set them only to keep an older record.
##
## Each value overrides the `ChestScript` child's when set (an empty list, an empty id or
## `starts_hidden` off leave the child's own: older scenes keep working). Handed over as each is
## set and as the chest enters the tree, before the child reads its record; never in the editor,
## so a save writes nothing on the child.
##
## Owner: interaction.

const SCRIPT_NODE := "ChestScript"

## What it holds at the start: {item_id: count} ("coins", "hp-potion", "dungeon-small-key", ...).
## The run keeps what is left.
@export var contents: Dictionary = {}:
	set(value):
		contents = value
		_hand_over()
## A Goo Heart inside: its heart id (unique across maps); "": none.
@export var heart_id: String = "":
	set(value):
		heart_id = value
		_hand_over()
## Dungeon chests: not there until it appears (a room fight cleared, a lock opened).
@export var starts_hidden: bool = false:
	set(value):
		starts_hidden = value
		_hand_over()
@export_group("Save record")
## Its record's id ("": the chest's name).
@export var chest_id: String = "":
	set(value):
		chest_id = value
		_hand_over()
## The map whose record keeps it ("": the world's).
@export var map_id: String = "":
	set(value):
		map_id = value
		_hand_over()


func _validate_property(property: Dictionary) -> void:
	# Only a dungeon chest can start hidden.
	if property["name"] == "starts_hidden":
		var script_node := get_node_or_null(SCRIPT_NODE)
		if script_node != null and not &"hidden" in script_node:
			property["usage"] = PROPERTY_USAGE_NO_EDITOR


## Before the ChestScript child's `_enter_tree` (a parent enters the tree before its children).
func _enter_tree() -> void:
	_hand_over()


## In the game, each value reaches the child as it is set (a scene being built sets the root's
## values once its children exist, so a chest read before it enters the tree holds them too) and
## again as it enters the tree. Never in the editor: the child's values would be saved with it.
func _hand_over() -> void:
	if not Engine.is_editor_hint():
		apply_to_script()


## Hands the set values to the ChestScript child.
func apply_to_script() -> void:
	var script_node := get_node_or_null(SCRIPT_NODE)
	if script_node == null:
		return
	if not contents.is_empty():
		script_node.set(&"initial_contents", contents.duplicate())
	if not heart_id.is_empty():
		script_node.set(&"goo_heart_id", heart_id)
	if starts_hidden and &"hidden" in script_node:
		script_node.set(&"hidden", true)
	if not chest_id.is_empty():
		script_node.set(&"instance_id", chest_id)
	if not map_id.is_empty():
		script_node.set(&"map_id", map_id)
