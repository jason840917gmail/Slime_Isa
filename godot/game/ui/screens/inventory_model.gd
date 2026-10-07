extends RefCounted
## The bag window's model (Phaser `InventorySurfacePort.snapshot`, crafting spec 6.3): what the
## window shows for its selection, with the exact texts. Reads the bag and the belt (RunState).
##
## `state` (owned by the window, updated here): {"selected_slot_index": int (-1 = none),
## "selected_item_id": String, "quantity": int >= 1}.
##
## Model keys: belt [{id, label, item_id, owned, shortcut}], belt_selected_index, items [{id,
## label, item_id, tag, disabled, draggable}], selected_index, details_name, details_status,
## details_status_color, details, quantity, primary_label, primary_disabled, hotbar_visible,
## hotbar_slots [{id, label}], hotbar_selected_index, quantity_visible, actions_visible,
## drop_disabled, remove_disabled.
##
## Owner: inventory (UI).

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const WeaponLoadout := preload("res://game/player/weapon_loadout.gd")
const InventoryDrops := preload("res://game/inventory/inventory_drops.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

## STATUS_COLOR (InventorySurfacePort.ts:274): in hand, on the belt, anything else. The muted one
## is not a theme token (K12).
const IN_HAND_COLOR := UiTokens.WARNING
const ON_BELT_COLOR := UiTokens.ACCENT
const MUTED_COLOR := Color("#a9c4b4")


static func new_state() -> Dictionary:
	return {"selected_slot_index": -1, "selected_item_id": "", "quantity": 1}


## `ensureSelectedItem` (InventorySurfacePort.ts:254-264): the selected slot still holds the
## selected item -> the quantity is clamped to its count; else slot 0 (or nothing) with quantity 1.
static func ensure_selected(state: Dictionary) -> void:
	var slots := Services.run().slots()
	var index := int(state.get("selected_slot_index", -1))
	if index >= 0 and index < slots.size() and str(slots[index]["item_id"]) == str(state.get("selected_item_id", "")):
		state["quantity"] = clampi(int(state.get("quantity", 1)), 1, maxi(1, int(slots[index]["count"])))
		return
	state["selected_slot_index"] = 0 if not slots.is_empty() else -1
	state["selected_item_id"] = str(slots[0]["item_id"]) if not slots.is_empty() else ""
	state["quantity"] = 1


## The selected bag slot ({"item_id", "count"}) when it still holds the selected item, else {}.
static func selected_slot(state: Dictionary) -> Dictionary:
	var slots := Services.run().slots()
	var index := int(state.get("selected_slot_index", -1))
	if index < 0 or index >= slots.size() or str(slots[index]["item_id"]) != str(state.get("selected_item_id", "")):
		return {}
	return slots[index]


static func snapshot(state: Dictionary) -> Dictionary:
	ensure_selected(state)
	var run := Services.run()
	var slots := run.slots()
	var index := int(state["selected_slot_index"])
	var slot: Dictionary = slots[index] if index >= 0 and index < slots.size() else {}
	var item_id := str(slot.get("item_id", ""))
	var definition := ItemCatalog.definition(item_id) if not slot.is_empty() else {}
	var weapon_id := ItemCatalog.weapon_id_of(item_id) if not definition.is_empty() else ""
	var belt := run.weapon_slots()
	var in_hand: Variant = run.equipped_weapon_id()
	var assigned_index := belt.find(weapon_id) if not weapon_id.is_empty() else -1
	var equipped: bool = not weapon_id.is_empty() and in_hand == weapon_id
	var belt_rows: Array = []
	var assign_rows: Array = []
	for belt_index in belt.size():
		var entry: Variant = belt[belt_index]
		var owned := WeaponLoadout.owns_weapon(entry)
		var weapon_name := ItemCatalog.item_name(str(entry)) if owned else ""
		belt_rows.append({"id": "belt-%d" % (belt_index + 1),
			"label": weapon_name if owned else "Slot %d\nEmpty" % (belt_index + 1),
			"item_id": str(entry) if owned else "", "owned": owned,
			"shortcut": str(belt_index + 1) if owned else ""})
		assign_rows.append({"id": "assign-%d" % (belt_index + 1),
			"label": "%d: %s" % [belt_index + 1, weapon_name if owned else "empty"]})
	var items: Array = []
	for slot_index in int(run.inventory.get("max_slots", 0)):
		var stack: Dictionary = slots[slot_index] if slot_index < slots.size() else {}
		var stack_id := str(stack.get("item_id", ""))
		var stack_def := ItemCatalog.definition(stack_id) if not stack.is_empty() else {}
		if stack_def.is_empty():
			items.append({"id": "slot-%d" % (slot_index + 1), "label": "Empty", "item_id": "", "tag": "",
				"disabled": true, "draggable": false})
			continue
		var stack_weapon := ItemCatalog.weapon_id_of(stack_id)
		var tag := ""
		if not stack_weapon.is_empty():
			var on_belt := belt.find(stack_weapon)
			if stack_weapon == in_hand:
				tag = "in hand"
			elif on_belt >= 0:
				tag = "belt %d" % (on_belt + 1)
		elif int(stack.get("count", 0)) > 1:
			tag = "×%d" % int(stack["count"])
		items.append({"id": "slot-%d" % (slot_index + 1), "label": str(stack_def.get("name", stack_id)),
			"item_id": stack_id, "tag": tag, "disabled": false, "draggable": not stack_weapon.is_empty()})
	var status := ""
	var status_color := MUTED_COLOR
	if not definition.is_empty():
		if not weapon_id.is_empty():
			if equipped:
				status = "In your hand · belt slot %d" % (assigned_index + 1)
				status_color = IN_HAND_COLOR
			elif assigned_index >= 0:
				status = "On belt slot %d · not in your hand" % (assigned_index + 1)
				status_color = ON_BELT_COLOR
			else:
				status = "In the bag · not on your belt"
		else:
			status = "%s · %d in the bag" % [str(definition.get("category", "")).capitalize(), int(slot["count"])]
	var details := "Pick things up in the world and they land here."
	if not definition.is_empty():
		details = str(definition.get("description", ""))
		var effects := use_effects(definition)
		if not effects.is_empty():
			details += "\n\n" + effects
	var is_weapon := not weapon_id.is_empty()
	var placeable := definition.has("placeable")
	var primary_label := "Use"
	if is_weapon:
		primary_label = "In your hand" if equipped else "Hold in hand"
	elif placeable:
		primary_label = "Place"
	return {
		"belt": belt_rows,
		"belt_selected_index": belt.find(in_hand) if in_hand != null else -1,
		"items": items,
		"selected_index": index,
		"details_name": str(definition.get("name", item_id)) if not definition.is_empty() else "Your bag is empty",
		"details_status": status,
		"details_status_color": status_color,
		"details": details,
		"quantity": "Quantity: %d" % int(state["quantity"]),
		"primary_label": primary_label,
		"primary_disabled": definition.is_empty() or equipped or (not is_weapon and not placeable and not definition.has("use")),
		"hotbar_visible": is_weapon,
		"hotbar_slots": assign_rows,
		"hotbar_selected_index": assigned_index,
		"quantity_visible": not definition.is_empty() and not is_weapon,
		"actions_visible": not definition.is_empty() and not is_weapon,
		"drop_disabled": definition.is_empty() or is_weapon or not InventoryDrops.can_drop(item_id),
		"remove_disabled": definition.is_empty() or is_weapon,
	}


## The effects line of a consumable: "Heal HP +20 · Energy +30" (+ "Cures …"); "" without `use`.
static func use_effects(definition: Dictionary) -> String:
	var use: Variant = definition.get("use")
	if not use is Dictionary:
		return ""
	var parts := PackedStringArray()
	if float((use as Dictionary).get("healHp", 0.0)) != 0.0:
		parts.append("Heal HP +%s" % _number(use["healHp"]))
	if float((use as Dictionary).get("healEnergy", 0.0)) != 0.0:
		parts.append("Energy +%s" % _number(use["healEnergy"]))
	var cures: Variant = (use as Dictionary).get("cureStatus")
	if cures is Array and not (cures as Array).is_empty():
		parts.append("Cures " + ", ".join(PackedStringArray(cures)))
	return " · ".join(parts)


static func _number(value: Variant) -> String:
	var number := float(value)
	return str(int(number)) if number == floorf(number) else str(number)
