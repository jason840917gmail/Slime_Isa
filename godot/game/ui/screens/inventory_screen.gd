extends "res://game/ui/screens/game_window.gd"
## The bag window (Phaser `InventorySurfacePort.ts` + `ui/inventory-ui.scene.json`; crafting
## spec 6): the weapon belt (4 slots; click one to hold that weapon, drag a weapon onto one), the
## bag's cells (20 at a new run), and the selected item's details with its actions: Use / Hold in
## hand / Place, the belt assignment list for weapons, and for other items the amount (-10, -1,
## +1, +10), Drop, Drop all, Destroy, Destroy all. The model is
## res://game/ui/screens/inventory_model.gd; the belt and item actions run through
## InventoryActions (group `inventory_actions`) and InventoryDrops.
##
## Dropping closes the bag (also when it failed, K8). Destroy has no confirmation (K7). "Place"
## stays disabled until furniture placement is ported (owner decision C1).
##
## Owner: inventory (UI).

const InventoryModel := preload("res://game/ui/screens/inventory_model.gd")
const InventoryDrops := preload("res://game/inventory/inventory_drops.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const WeaponLoadout := preload("res://game/player/weapon_loadout.gd")
const ItemCell := preload("res://game/ui/screens/item_cell.gd")
const ItemIcons := preload("res://game/inventory/item_icons.gd")
const Services := preload("res://game/shared/services.gd")

const SURFACE_ID := &"inventory"
const INVENTORY_ACTIONS_GROUP := &"inventory_actions"
const BELT_HELP := "Click a slot to hold that weapon. Drag a weapon from the bag onto a slot to put it there. Outside, the mouse wheel switches."
const ITEMS_TITLE := "In the bag — click an item to see it"
const ASSIGN_TITLE := "Or put it on a belt slot:"
const IN_HAND_TAG := "IN HAND"
## inventory-ui.scene.json sizes.
const BELT_CELL_HEIGHT := 78.0
const BELT_ICON := 36
const ITEM_CELL_HEIGHT := 88.0
const ITEM_ICON := 44
const ASSIGN_ROW_HEIGHT := 40.0
const QUANTITY_STEPS := {"Minus10": -10, "Minus1": -1, "Plus1": 1, "Plus10": 10}

## The window state (InventoryModel.new_state()).
var state: Dictionary = InventoryModel.new_state()

var title_label: Label
var close_button: Button
var belt_title_label: Label
var belt_help_label: Label
var belt_list: GridContainer
var items_title_label: Label
var item_list: GridContainer
var details_name_label: Label
var details_status_label: Label
var details_label: Label
var primary_button: Button
var assign_title_label: Label
var assign_list: GridContainer
var quantity_label: Label
var quantity_buttons: Dictionary = {}
var drop_button: Button
var drop_all_button: Button
var remove_button: Button
var remove_all_button: Button
var _items_scroll: ScrollContainer
var _model: Dictionary = {}


func _init() -> void:
	super()
	name = "InventoryScreen"
	surface_id = SURFACE_ID
	max_size = Vector2(1000.0, 640.0)
	min_width = 320.0
	content_height = 640.0


func _ready() -> void:
	super()
	var run := Services.run()
	if run != null:
		for changed: Signal in [run.inventory_changed, run.weapon_loadout_changed, run.weapon_equipped]:
			if not changed.is_connected(_on_run_changed):
				changed.connect(_on_run_changed)


func _exit_tree() -> void:
	var run := Services.run()
	if run != null:
		for changed: Signal in [run.inventory_changed, run.weapon_loadout_changed, run.weapon_equipped]:
			if changed.is_connected(_on_run_changed):
				changed.disconnect(_on_run_changed)


func _on_opening() -> void:
	InventoryModel.ensure_selected(state)


## The current model (inventory_model.gd keys).
func model() -> Dictionary:
	return _model


# --- actions (InventorySurfacePort.invoke) --------------------------------------------------------

## `select-item {index}`: a non-empty bag slot becomes the selection, amount 1.
func select_item(index: int) -> void:
	if not is_open():
		return
	var slots := Services.run().slots()
	if index < 0 or index >= slots.size():
		refresh()
		return
	state["selected_slot_index"] = index
	state["selected_item_id"] = str(slots[index]["item_id"])
	state["quantity"] = 1
	refresh()


## `hold-belt-slot {index}`: the slot's weapon is selected in the bag and held.
func hold_belt_slot(index: int) -> void:
	if not is_open():
		return
	var weapon_id := WeaponLoadout.weapon_at(index)
	if not weapon_id.is_empty():
		_select_item_id(weapon_id)
		var actions := _actions()
		if actions != null:
			actions.call(&"equip_weapon_from_bag", weapon_id)
	refresh()


## `drop-on-belt {index, sourceItemId, sourceIndex}`: a weapon dragged from a bag cell ("slot-N")
## or another belt cell ("belt-N") goes onto belt slot `index`.
func drop_on_belt(index: int, source_item_id: String, source_index: int) -> void:
	if not is_open():
		return
	if index < 0 or index >= WeaponLoadout.SLOT_COUNT or source_index < 0:
		refresh()
		return
	var weapon_id := ""
	if source_item_id.begins_with("belt-"):
		weapon_id = WeaponLoadout.weapon_at(source_index)
	elif source_item_id.begins_with("slot-"):
		var slots := Services.run().slots()
		if source_index < slots.size():
			weapon_id = ItemCatalog.weapon_id_of(str(slots[source_index]["item_id"]))
	if not weapon_id.is_empty():
		_select_item_id(weapon_id)
		var actions := _actions()
		if actions != null:
			actions.call(&"assign_weapon_slot", weapon_id, index)
	refresh()


## `use-or-equip` (Primary): a weapon is held, a consumable used; "Place" waits for placement.
func use_or_equip() -> void:
	var slot := _selected_slot()
	if slot.is_empty():
		return
	var item_id := str(slot["item_id"])
	var definition := ItemCatalog.definition(item_id)
	var actions := _actions()
	var weapon_id := ItemCatalog.weapon_id_of(item_id)
	if not weapon_id.is_empty():
		if actions != null:
			actions.call(&"equip_weapon_from_bag", weapon_id)
	elif definition.has("placeable"):
		pass # Furniture placement is not ported (owner decision C1).
	elif definition.has("use") and actions != null:
		actions.call(&"use_item", item_id)
	refresh()


## `assign-slot {index}`: the selected weapon goes onto belt slot `index`.
func assign_slot(index: int) -> void:
	var slot := _selected_slot()
	var weapon_id := ItemCatalog.weapon_id_of(str(slot.get("item_id", "")))
	if weapon_id.is_empty() or index < 0 or index >= WeaponLoadout.SLOT_COUNT:
		refresh()
		return
	var actions := _actions()
	if actions != null:
		actions.call(&"assign_weapon_slot", weapon_id, index)
	refresh()


## `quantity-*`: the amount moves within 1..the slot's count.
func adjust_quantity(delta: int) -> void:
	var slot := _selected_slot()
	if slot.is_empty():
		return
	state["quantity"] = clampi(int(state["quantity"]) + delta, 1, maxi(1, int(slot["count"])))
	refresh()


## `drop` / `drop-all`: the amount (or the whole slot) onto the ground in front of the slime, then
## the bag closes (also when there was no room, K8).
func drop(all: bool = false) -> void:
	var slot := _selected_slot()
	if slot.is_empty():
		return
	var item_id := str(slot["item_id"])
	if not ItemCatalog.weapon_id_of(item_id).is_empty() or not InventoryDrops.can_drop(item_id):
		refresh()
		return
	var amount := int(slot["count"]) if all else int(state["quantity"])
	var index := int(state["selected_slot_index"])
	close()
	InventoryDrops.drop_from_slot(index, amount)


## `remove` / `remove-all` (Destroy): the amount (or the whole slot) is gone, no confirmation (K7).
func destroy(all: bool = false) -> void:
	var slot := _selected_slot()
	if slot.is_empty() or not ItemCatalog.weapon_id_of(str(slot["item_id"])).is_empty():
		return
	var count := int(slot["count"])
	var amount := count if all else int(state["quantity"])
	var index := int(state["selected_slot_index"])
	if amount >= count:
		state["selected_slot_index"] = -1
		state["selected_item_id"] = ""
		state["quantity"] = 1
	else:
		state["quantity"] = mini(int(state["quantity"]), count - amount)
	Services.run().remove_from_slot(index, amount)
	refresh()


# --- view ---------------------------------------------------------------------------------------

func refresh() -> void:
	if content == null:
		return
	_model = InventoryModel.snapshot(state)
	var belt: Array = _model["belt"]
	for index in belt.size():
		var entry: Dictionary = belt[index]
		var cell := belt_list.get_child(index) as ItemCell
		var item_id := str(entry["item_id"])
		var in_hand := index == int(_model["belt_selected_index"])
		cell.set_content(str(entry["label"]), ItemIcons.icon(item_id) if bool(entry["owned"]) else null,
			IN_HAND_TAG if in_hand else "")
		cell.corner_label.text = str(entry["shortcut"])
		cell.set_selected(in_hand)
		cell.drag_payload = {"source_item_id": str(entry["id"]), "source_index": index} if bool(entry["owned"]) else {}
	var items: Array = _model["items"]
	_sync_items(items.size())
	for index in items.size():
		var entry: Dictionary = items[index]
		var cell := item_list.get_child(index) as ItemCell
		var item_id := str(entry["item_id"])
		cell.set_content(str(entry["label"]), ItemIcons.icon(item_id) if not item_id.is_empty() else null, str(entry["tag"]))
		cell.set_enabled(not bool(entry["disabled"]))
		cell.set_selected(index == int(_model["selected_index"]))
		cell.drag_payload = {"source_item_id": str(entry["id"]), "source_index": index} if bool(entry["draggable"]) else {}
	details_name_label.text = str(_model["details_name"])
	details_status_label.text = str(_model["details_status"])
	details_status_label.add_theme_color_override(&"font_color", _model["details_status_color"])
	details_label.text = str(_model["details"])
	primary_button.text = str(_model["primary_label"])
	primary_button.disabled = bool(_model["primary_disabled"])
	var hotbar_visible := bool(_model["hotbar_visible"])
	assign_title_label.visible = hotbar_visible
	assign_list.visible = hotbar_visible
	var assign_rows: Array = _model["hotbar_slots"]
	for index in assign_rows.size():
		var cell := assign_list.get_child(index) as ItemCell
		cell.set_content(str((assign_rows[index] as Dictionary)["label"]))
		cell.set_selected(index == int(_model["hotbar_selected_index"]))
	var quantity_visible := bool(_model["quantity_visible"])
	quantity_label.visible = quantity_visible
	quantity_label.text = str(_model["quantity"])
	for button: Button in quantity_buttons.values():
		button.visible = quantity_visible
	var actions_visible := bool(_model["actions_visible"])
	for button: Button in [drop_button, drop_all_button, remove_button, remove_all_button]:
		button.visible = actions_visible
	drop_button.disabled = bool(_model["drop_disabled"])
	drop_all_button.disabled = bool(_model["drop_disabled"])
	remove_button.disabled = bool(_model["remove_disabled"])
	remove_all_button.disabled = bool(_model["remove_disabled"])


func _build() -> void:
	title_label = _label("Title", &"PanelTitle", 26)
	title_label.text = "Bag"
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	close_button = _button("Close", "Close (Esc)", &"MutedButton", 15, close)
	belt_title_label = _label("BeltTitle", &"PanelTitle", 16)
	belt_title_label.text = "Weapon belt"
	belt_help_label = _label("BeltHelp", &"MutedLabel", 13)
	belt_help_label.text = BELT_HELP
	belt_help_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	belt_list = _grid(content, "Belt", WeaponLoadout.SLOT_COUNT, 10)
	for index in WeaponLoadout.SLOT_COUNT:
		var cell := ItemCell.new(ItemCell.Layout.TILE, BELT_ICON, 12)
		cell.custom_minimum_size = Vector2(0.0, BELT_CELL_HEIGHT)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.index = index
		cell.drop_handler = _on_belt_drop
		cell.pressed.connect(_on_belt_pressed.bind(cell))
		belt_list.add_child(cell)
	items_title_label = _label("ItemsTitle", &"PanelTitle", 15)
	items_title_label.text = ITEMS_TITLE
	_items_scroll = ScrollContainer.new()
	_items_scroll.name = "ItemsScroll"
	_items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(_items_scroll)
	item_list = _grid(_items_scroll, "Items", 5, 8)
	details_name_label = _label("DetailsName", &"PanelTitle", 21)
	details_status_label = _label("DetailsStatus", &"", 14)
	details_label = _label("Details", &"", 14)
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	primary_button = _button("Primary", "Use", &"PrimaryButton", 17, use_or_equip)
	assign_title_label = _label("AssignTitle", &"MutedLabel", 13)
	assign_title_label.text = ASSIGN_TITLE
	assign_list = _grid(content, "HotbarSlots", 2, 6)
	for index in WeaponLoadout.SLOT_COUNT:
		var cell := ItemCell.new(ItemCell.Layout.TEXT, 0, 13)
		cell.custom_minimum_size = Vector2(0.0, ASSIGN_ROW_HEIGHT)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.index = index
		cell.pressed.connect(_on_assign_pressed.bind(cell))
		assign_list.add_child(cell)
	quantity_label = _label("Quantity", &"WarningLabel", 14)
	for key: String in QUANTITY_STEPS:
		var delta: int = QUANTITY_STEPS[key]
		quantity_buttons[key] = _button(key, "%+d" % delta, &"MutedButton", 15, adjust_quantity.bind(delta))
	drop_button = _button("Drop", "Drop", &"PrimaryButton", 15, drop.bind(false))
	drop_all_button = _button("DropAll", "Drop all", &"PrimaryButton", 15, drop.bind(true))
	remove_button = _button("Remove", "Destroy", &"DangerButton", 15, destroy.bind(false))
	remove_all_button = _button("RemoveAll", "Destroy all", &"DangerButton", 15, destroy.bind(true))


func _layout(width: float) -> void:
	var w := width
	var right := 0.62 * w
	_place(title_label, _rect(20.0, 12.0, w - 150.0, 52.0))
	_place(close_button, _rect(w - 140.0, 14.0, w - 20.0, 50.0))
	_place(belt_title_label, _rect(20.0, 58.0, w - 20.0, 80.0))
	_place(belt_help_label, _rect(20.0, 80.0, w - 20.0, 102.0))
	_place(belt_list, _rect(20.0, 106.0, w - 20.0, 188.0))
	_place(items_title_label, _rect(20.0, 200.0, 0.6 * w - 8.0, 224.0))
	_place(_items_scroll, _rect(20.0, 230.0, 0.6 * w - 8.0, 620.0))
	_place(details_name_label, _rect(right, 200.0, w - 20.0, 228.0))
	_place(details_status_label, _rect(right, 230.0, w - 20.0, 252.0))
	_place(details_label, _rect(right, 258.0, w - 20.0, 360.0))
	_place(primary_button, _rect(right, 366.0, w - 20.0, 412.0))
	_place(assign_title_label, _rect(right, 422.0, w - 20.0, 444.0))
	_place(assign_list, _rect(right, 448.0, w - 20.0, 540.0))
	_place(quantity_label, _rect(right, 422.0, w - 20.0, 444.0))
	_place(quantity_buttons["Minus10"], _rect(right, 448.0, 0.715 * w - 2.0, 488.0))
	_place(quantity_buttons["Minus1"], _rect(0.715 * w + 2.0, 448.0, 0.81 * w - 2.0, 488.0))
	_place(quantity_buttons["Plus1"], _rect(0.81 * w + 2.0, 448.0, 0.905 * w - 2.0, 488.0))
	_place(quantity_buttons["Plus10"], _rect(0.905 * w + 2.0, 448.0, w - 20.0, 488.0))
	_place(drop_button, _rect(right, 496.0, 0.81 * w - 4.0, 536.0))
	_place(drop_all_button, _rect(0.81 * w + 4.0, 496.0, w - 20.0, 536.0))
	_place(remove_button, _rect(right, 544.0, 0.81 * w - 4.0, 584.0))
	_place(remove_all_button, _rect(0.81 * w + 4.0, 544.0, w - 20.0, 584.0))


# --- private ------------------------------------------------------------------------------------

func _selected_slot() -> Dictionary:
	if not is_open():
		return {}
	return InventoryModel.selected_slot(state)


## Selects the first bag slot holding `item_id` (amount 1); nothing when none does.
func _select_item_id(item_id: String) -> void:
	var slots := Services.run().slots()
	for index in slots.size():
		if str(slots[index]["item_id"]) == item_id:
			state["selected_slot_index"] = index
			state["selected_item_id"] = item_id
			state["quantity"] = 1
			return


func _actions() -> Node:
	return get_tree().get_first_node_in_group(INVENTORY_ACTIONS_GROUP) if is_inside_tree() else null


func _on_run_changed(_payload: Dictionary) -> void:
	if is_open():
		refresh()


func _on_item_pressed(cell: ItemCell) -> void:
	play_select()
	select_item(cell.index)


func _on_belt_pressed(cell: ItemCell) -> void:
	play_select()
	hold_belt_slot(cell.index)


func _on_assign_pressed(cell: ItemCell) -> void:
	play_select()
	assign_slot(cell.index)


func _on_belt_drop(index: int, data: Dictionary) -> void:
	drop_on_belt(index, str(data.get("source_item_id", "")), int(data.get("source_index", -1)))


## Keeps one cell per bag slot (`max_slots` can grow).
func _sync_items(count: int) -> void:
	while item_list.get_child_count() > count:
		var last := item_list.get_child(item_list.get_child_count() - 1)
		item_list.remove_child(last)
		last.queue_free()
	while item_list.get_child_count() < count:
		var cell := ItemCell.new(ItemCell.Layout.TILE, ITEM_ICON, 12)
		cell.custom_minimum_size = Vector2(0.0, ITEM_CELL_HEIGHT)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.index = item_list.get_child_count()
		cell.pressed.connect(_on_item_pressed.bind(cell))
		item_list.add_child(cell)


static func _grid(parent: Control, node_name: String, columns: int, gap: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = node_name
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", gap)
	grid.add_theme_constant_override(&"v_separation", gap)
	parent.add_child(grid)
	return grid
