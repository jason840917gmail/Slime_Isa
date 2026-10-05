extends RefCounted
## The chest window's model (Phaser `features/ui/ChestInventorySurfacePort.ts` `entries`,
## `snapshot`, `take`; docs/godot/specs/journal-and-chest.md 2.3): pure static functions over a
## chest's remaining contents (`ChestScript.remaining()`, record order). The window is
## res://game/ui/screens/chest_window.gd.
##
## Owner: interaction (UI).

const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")

const TITLE := "Chest"
const TAKE_TEXT := "Take Stack"
const CLOSE_TEXT := "Close"
const INITIAL_STATUS := "Select a stack to inspect. Right-click or press Take Stack to collect it."
const NO_ROOM_STATUS := "No inventory space for that item."
const TAKE_HINT := "Take Stack transfers as much as your inventory can hold."
const EMPTY_DETAILS := "The chest is empty."
const NO_SELECTION_DETAILS := "Select an item"
const MOVED_FORMAT := "Moved %d × %s"


## The stacks still inside: [[item_id, count]] with count > 0, in record order.
static func entries(remaining: Dictionary) -> Array:
	var out: Array = []
	for key: Variant in remaining:
		var count := int(remaining[key])
		if count > 0:
			out.append([str(key), count])
	return out


## The status after a take: "Moved <n> × <name>", or the no-room text when nothing moved.
static func moved_text(moved: int, item_id: String) -> String:
	return MOVED_FORMAT % [moved, ItemCatalog.item_name(item_id)] if moved > 0 else NO_ROOM_STATUS


## The window's model: {"cells": [{"id", "label" ("<name> ×<count>"), "count_text", "defined"}],
## "selected_index", "selected_id", "details", "status", "take_disabled"}. A selection that is no
## longer listed falls back to the first stack (or none).
static func snapshot(remaining: Dictionary, selected_id: String, status: String) -> Dictionary:
	var stacks := entries(remaining)
	var index := -1
	for position in stacks.size():
		if str(stacks[position][0]) == selected_id:
			index = position
			break
	if index < 0 and not stacks.is_empty():
		index = 0
	var selected := str(stacks[index][0]) if index >= 0 else ""
	var cells: Array[Dictionary] = []
	for stack: Array in stacks:
		var item_id := str(stack[0])
		cells.append({
			"id": item_id,
			"label": "%s ×%d" % [ItemCatalog.item_name(item_id), int(stack[1])],
			"count_text": str(int(stack[1])),
			"defined": not ItemCatalog.definition(item_id).is_empty(),
		})
	var details := EMPTY_DETAILS
	var definition := ItemCatalog.definition(selected) if index >= 0 else {}
	if not definition.is_empty():
		details = "\n".join([
			str(definition.get("name", selected)),
			"%s · ×%d" % [str(definition.get("category", "")).to_upper(), int(stacks[index][1])],
			"",
			str(definition.get("description", "")),
			"",
			TAKE_HINT,
		])
	elif not stacks.is_empty():
		details = NO_SELECTION_DETAILS
	return {
		"cells": cells,
		"selected_index": index,
		"selected_id": selected,
		"details": details,
		"status": status,
		"take_disabled": selected.is_empty(),
	}
