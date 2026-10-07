extends "res://game/ui/screens/game_window.gd"
## The crafting window (Phaser `CraftingSurfacePort.ts` + `ui/crafting-ui.scene.json`; crafting
## spec 4), one window for every site: the Crafting tab (portable) and the stations (workbench,
## workshop, forge). Left: the site's recipes (name and state; locked rows dimmed, short rows red).
## Right: the selected recipe's output, description and stats, the materials it needs, the status
## line, the amount (-10, -1, +1, +10, MAX), Craft and Close. The model is
## res://game/ui/screens/crafting_model.gd.
##
## The selection and the per-recipe amounts live as long as the window (one per main). A refused
## Craft shows why in red and plays CraftFail; a bag change then gives way to the live hint. A
## craft shows "Crafted N × <name>" in green and hands the result to InventoryActions.on_crafted.
##
## Owner: crafting (UI).

const CraftingModel := preload("res://game/ui/screens/crafting_model.gd")
const CraftingService := preload("res://game/crafting/crafting_service.gd")
const RecipeCatalog := preload("res://game/crafting/recipe_catalog.gd")
const ItemCell := preload("res://game/ui/screens/item_cell.gd")
const ItemIcons := preload("res://game/inventory/item_icons.gd")
const Services := preload("res://game/shared/services.gd")

const SURFACE_ID := &"crafting"
const INVENTORY_ACTIONS_GROUP := &"inventory_actions"
## crafting-ui.scene.json sizes.
const RECIPE_ROW_HEIGHT := 60.0
const RECIPE_ICON := 36
const MATERIAL_ROW_HEIGHT := 52.0
const MATERIAL_ICON := 30
const QUANTITY_STEPS := {"Minus10": -10, "Minus1": -1, "Plus1": 1, "Plus10": 10}

## The window state (CraftingModel.new_state()).
var state: Dictionary = CraftingModel.new_state()

var title_label: Label
var recipe_list: GridContainer
var details_name_label: Label
var details_label: Label
var materials_title_label: Label
var material_list: GridContainer
var status_label: Label
var quantity_label: Label
var quantity_buttons: Dictionary = {}
var max_button: Button
var craft_button: Button
var close_button: Button
var _recipe_scroll: ScrollContainer
var _material_scroll: ScrollContainer
var _model: Dictionary = {}


func _init() -> void:
	super()
	name = "CraftingScreen"
	surface_id = SURFACE_ID
	max_size = Vector2(1080.0, 660.0)
	content_height = 660.0


func _ready() -> void:
	super()
	var run := Services.run()
	if run != null and not run.inventory_changed.is_connected(_on_inventory_changed):
		run.inventory_changed.connect(_on_inventory_changed)


func _exit_tree() -> void:
	var run := Services.run()
	if run != null and run.inventory_changed.is_connected(_on_inventory_changed):
		run.inventory_changed.disconnect(_on_inventory_changed)


## `open(site)` (CraftingSurfacePort.ts:47-58): no-op when open. Keeps the selected recipe when
## the site lists it (else the first), clears the status, opens.
func open_site(site: Dictionary = RecipeCatalog.PORTABLE_SITE) -> void:
	if is_open():
		return
	state["site"] = {"station": str(site.get("station", "portable")), "tier": int(site.get("tier", 1))}
	CraftingModel.selected_recipe(state)
	state["status"] = null
	state["status_color"] = null
	open()


## The current model (crafting_model.gd keys).
func model() -> Dictionary:
	return _model


func site() -> Dictionary:
	return state["site"]


# --- actions (CraftingSurfacePort.invoke) ---------------------------------------------------------

## `select-recipe {index}`: selects a listed recipe and clears the message.
func select_recipe(index: int) -> void:
	if not is_open():
		return
	var list := CraftingModel.recipes(state)
	if index < 0 or index >= list.size():
		return
	state["selected_recipe_id"] = str((list[index] as Dictionary)["id"])
	_clear_status()
	refresh()


## `quantity-minus-10/-1`, `plus-1/-10`: the amount moves by `delta` within 1..MAX.
func adjust_quantity(delta: int) -> void:
	var recipe := _selected()
	if recipe.is_empty():
		return
	var max_craftable := int(CraftingService.quote(recipe, 1, state["site"])["maxCraftable"])
	var current := int(CraftingModel.quote_for(state, recipe)["requestedQuantity"])
	(state["quantities"] as Dictionary)[str(recipe["id"])] = CraftingService.normalize_quantity(current + delta, max_craftable)
	_clear_status()
	refresh()


## `quantity-max`: the amount becomes the maximum (0 when nothing can be made).
func quantity_max() -> void:
	var recipe := _selected()
	if recipe.is_empty():
		return
	(state["quantities"] as Dictionary)[str(recipe["id"])] = int(CraftingService.quote(recipe, 1, state["site"])["maxCraftable"])
	_clear_status()
	refresh()


## `craft`: crafts the amount; success shows "Crafted N × <name>" (accent) and runs
## InventoryActions.on_crafted; a refusal shows why (danger) and reports `craft.failed`.
func craft() -> void:
	var recipe := _selected()
	if recipe.is_empty():
		return
	var site_now: Dictionary = state["site"]
	var amount := int(CraftingModel.quote_for(state, recipe)["requestedQuantity"])
	var result := CraftingService.craft(recipe, amount, site_now)
	if bool(result["ok"]):
		state["status"] = "Crafted %d × %s" % [int(result["output_quantity"]), str(recipe.get("name", ""))]
		state["status_color"] = CraftingModel.SUCCESS_COLOR
		var actions := get_tree().get_first_node_in_group(INVENTORY_ACTIONS_GROUP)
		if actions != null and actions.has_method(&"on_crafted"):
			actions.call(&"on_crafted", result)
	else:
		var reason := str(result["reason"])
		state["status"] = CraftingModel.reason_text(reason, recipe, site_now, result.get("quote", {}))
		state["status_color"] = CraftingModel.REFUSED_COLOR
		CraftingService.report_failure(str(recipe["id"]), reason)
	refresh()


# --- view ---------------------------------------------------------------------------------------

func refresh() -> void:
	if content == null:
		return
	_model = CraftingModel.snapshot(state)
	title_label.text = str(_model["title"])
	var rows: Array = _model["recipes"]
	_sync_cells(recipe_list, rows.size(), _make_recipe_cell)
	for index in rows.size():
		var row: Dictionary = rows[index]
		var cell := recipe_list.get_child(index) as ItemCell
		var item_id := str(row["item_id"])
		cell.set_content(str(row["label"]), ItemIcons.icon(item_id) if not item_id.is_empty() else null)
		cell.set_short(bool(row["short"]))
		cell.set_locked(bool(row["locked"]))
		cell.set_selected(index == int(_model["selected_index"]))
	details_name_label.text = str(_model["details_name"])
	details_label.text = str(_model["details"])
	var materials: Array = _model["materials"]
	_sync_cells(material_list, materials.size(), _make_material_cell)
	for index in materials.size():
		var material: Dictionary = materials[index]
		var cell := material_list.get_child(index) as ItemCell
		var item_id := str(material["item_id"])
		cell.set_content(str(material["label"]), ItemIcons.icon(item_id) if not item_id.is_empty() else null)
		cell.set_short(bool(material["short"]))
		cell.set_selected(false)
	status_label.text = str(_model["status"])
	status_label.add_theme_color_override(&"font_color", _model["status_color"])
	quantity_label.text = str(_model["quantity"])
	for button: Button in quantity_buttons.values():
		button.disabled = bool(_model["quantity_disabled"])
	max_button.disabled = bool(_model["quantity_disabled"])
	craft_button.disabled = bool(_model["craft_disabled"])


func _build() -> void:
	title_label = _label("Title", &"PanelTitle", 24)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_recipe_scroll = _list_scroll("RecipesScroll")
	recipe_list = _grid(_recipe_scroll, "Recipes", 1, 8)
	details_name_label = _label("DetailsName", &"PanelTitle", 22)
	details_label = _label("Details", &"", 14)
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	materials_title_label = _label("MaterialsTitle", &"PanelTitle", 15)
	materials_title_label.text = "You need"
	_material_scroll = _list_scroll("MaterialsScroll")
	material_list = _grid(_material_scroll, "Materials", 2, 6)
	status_label = _label("Status", &"", 14)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quantity_label = _label("Quantity", &"InfoLabel", 14)
	for key: String in QUANTITY_STEPS:
		var delta: int = QUANTITY_STEPS[key]
		quantity_buttons[key] = _button(key, ("%+d" % delta), &"MutedButton", 15, adjust_quantity.bind(delta))
	max_button = _button("Max", "MAX", &"MutedButton", 15, quantity_max)
	craft_button = _button("Craft", "Craft", &"PrimaryButton", 18, craft)
	close_button = _button("Close", "Close (Esc)", &"MutedButton", 16, close)


func _layout(width: float) -> void:
	var w := width
	var right := 0.58 * w
	_place(title_label, _rect(20.0, 12.0, w - 20.0, 54.0))
	_place(_recipe_scroll, _rect(20.0, 66.0, 0.56 * w - 12.0, 640.0))
	_place(details_name_label, _rect(right, 66.0, w - 20.0, 96.0))
	_place(details_label, _rect(right, 100.0, w - 20.0, 196.0))
	_place(materials_title_label, _rect(right, 202.0, w - 20.0, 226.0))
	_place(_material_scroll, _rect(right, 230.0, w - 20.0, 392.0))
	_place(status_label, _rect(right, 484.0, w - 20.0, 512.0))
	_place(quantity_label, _rect(right, 518.0, w - 20.0, 544.0))
	var columns := [[0.58, 0.655, "Minus10"], [0.66, 0.735, "Minus1"], [0.74, 0.815, "Plus1"], [0.82, 0.895, "Plus10"]]
	for column: Array in columns:
		_place(quantity_buttons[column[2]], _rect(float(column[0]) * w, 550.0, float(column[1]) * w, 590.0))
	_place(max_button, _rect(0.90 * w, 550.0, 0.98 * w, 590.0))
	_place(craft_button, _rect(right, 600.0, 0.79 * w - 6.0, 648.0))
	_place(close_button, _rect(0.79 * w + 6.0, 600.0, w - 20.0, 648.0))


# --- private ------------------------------------------------------------------------------------

func _selected() -> Dictionary:
	if not is_open():
		return {}
	return CraftingModel.selected_recipe(state)


func _clear_status() -> void:
	state["status"] = null
	state["status_color"] = null


## `inventory.changed`: a refusal gives way to the live hint; a success message stays (K5).
func _on_inventory_changed(_payload: Dictionary) -> void:
	if state.get("status_color") == CraftingModel.REFUSED_COLOR:
		_clear_status()
	if is_open():
		refresh()


func _on_recipe_pressed(cell: ItemCell) -> void:
	play_select()
	select_recipe(cell.index)
	refresh()


func _on_material_pressed(cell: ItemCell) -> void:
	play_select()
	cell.set_selected(false)


func _make_recipe_cell() -> ItemCell:
	var cell := ItemCell.new(ItemCell.Layout.ROW, RECIPE_ICON, 14)
	cell.custom_minimum_size = Vector2(0.0, RECIPE_ROW_HEIGHT)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.pressed.connect(_on_recipe_pressed.bind(cell))
	return cell


func _make_material_cell() -> ItemCell:
	var cell := ItemCell.new(ItemCell.Layout.ROW, MATERIAL_ICON, 13)
	cell.custom_minimum_size = Vector2(0.0, MATERIAL_ROW_HEIGHT)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.set_text_color(UiTokens.ACCENT)
	cell.pressed.connect(_on_material_pressed.bind(cell))
	return cell


## Keeps `count` cells in `grid` (made by `factory`), indexed in order.
static func _sync_cells(grid: GridContainer, count: int, factory: Callable) -> void:
	while grid.get_child_count() > count:
		var last := grid.get_child(grid.get_child_count() - 1)
		grid.remove_child(last)
		last.queue_free()
	while grid.get_child_count() < count:
		grid.add_child(factory.call())
	for index in grid.get_child_count():
		(grid.get_child(index) as ItemCell).index = index


func _list_scroll(node_name: String) -> ScrollContainer:
	var list_scroll := ScrollContainer.new()
	list_scroll.name = node_name
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(list_scroll)
	return list_scroll


static func _grid(parent: Control, node_name: String, columns: int, gap: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = node_name
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", gap)
	grid.add_theme_constant_override(&"v_separation", gap)
	parent.add_child(grid)
	return grid
