extends "res://game/ui/screens/game_window.gd"
## The shop window (docs/godot/specs/crafting.md 12.3), modelled on the chest window
## (chest_window.gd): built in code, main adds it to GameWindows (surface "shop": the `modal`
## pause, MenuOpen / MenuClose). Group `shop_window`: a shop counter (game/shop/shop_counter.gd)
## opens it with `open_shop(shop_id)`. The stock and the purchase rules are
## res://game/shop/shop_catalog.gd.
##
## Top: the shop's name, the slime's coins (the coins' picture and the count) and the keeper's
## greeting. Left: the stock, two to a row (icon, name and price; a sold-out row is dimmed, a row the
## coins do not reach has the red edge). Right: the selected entry's name, description, price and
## how many the bag holds (for the belt slot, how many belt slots are found). Below: the status line, Buy and Close. A left click selects; a right click
## (or Space / Enter on a focused cell) selects and buys; Buy buys the selected entry; the arrows or
## WASD move the selection. The status shows the last purchase or refusal ("Bought ...", "Not enough
## coins ...", "Your bag is full ..."), else why the selected entry cannot be bought now. It follows
## the coins and the bag while open.
##
## Owner: shop (UI).

const ShopCatalog := preload("res://game/shop/shop_catalog.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const ItemIcons := preload("res://game/inventory/item_icons.gd")
const ItemCell := preload("res://game/ui/screens/item_cell.gd")
const ChestModel := preload("res://game/ui/screens/chest_model.gd")
const WindowStyle := preload("res://game/ui/screens/window_style.gd")
const ControlScheme := preload("res://game/player/mouse/control_scheme.gd")
const Services := preload("res://game/shared/services.gd")

const SURFACE_ID := &"shop"
const GROUP := &"shop_window"
const COLUMNS := 2
const CELL_GAP := 10
const CELL_HEIGHT := 60.0
const CELL_ICON := 36
const CELL_FONT := 14
const COIN_ICON := 30
const CORNER_RADIUS := 5
const DETAILS_FONT := 14
const DETAILS_PITCH := 19.6

const BUY_TEXT := "Buy"
const CLOSE_TEXT := "Close"
const OPEN_STATUS := "Select something to buy. Right-click or press Buy to buy it."
const KEYS_OPEN_STATUS := "Arrows or WASD choose. Space buys."
const READY_STATUS := "Press Buy to buy it."
const BOUGHT_FORMAT := "Bought %s for %d coins."
const BOUGHT_MANY_FORMAT := "Bought %d × %s for %d coins."
const NO_COINS_FORMAT := "Not enough coins: it costs %d and you have %d."
const BAG_FULL_STATUS := "Your bag is full: make room first."
const SOLD_OUT_STATUS := "Sold out."
const CLOSED_STATUS := "The shop is closed."
const PRICE_FORMAT := "%d coins"
const SOLD_OUT_ROW := "Sold out"
## The belt slot never sits in the bag (it opens a belt slot): its details count the slots found.
const BELT_SLOTS_FORMAT := "Belt slots found: %d of %d"

var title_label: Label
var coin_icon: TextureRect
var coins_label: Label
var greeting_label: Label
var stock_scroll: ScrollContainer
var stock_list: GridContainer
var details_name_label: Label
var details_label: Label
var status_label: Label
var buy_button: Button
var close_button: Button

var _shop_id: String = ""
var _selected_id: String = ""
## The last purchase's or refusal's line ("" = show the live hint) and its colour.
var _message: String = ""
var _message_color: Color = UiTokens.TEXT_SECONDARY
var _cell_width: float = 0.0


func _init() -> void:
	super()
	name = "ShopWindow"
	surface_id = SURFACE_ID
	max_size = Vector2(920.0, 600.0)
	content_height = 600.0


func _ready() -> void:
	super()
	add_to_group(GROUP)
	var run := Services.run()
	if run != null:
		if not run.coins_changed.is_connected(_on_run_changed):
			run.coins_changed.connect(_on_run_changed)
		if not run.inventory_changed.is_connected(_on_run_changed):
			run.inventory_changed.connect(_on_run_changed)


func _exit_tree() -> void:
	var run := Services.run()
	if run != null:
		if run.coins_changed.is_connected(_on_run_changed):
			run.coins_changed.disconnect(_on_run_changed)
		if run.inventory_changed.is_connected(_on_run_changed):
			run.inventory_changed.disconnect(_on_run_changed)


## Opens the shop `shop_id` with its first entry selected; false when it is closed, has no stock or
## the window is open already.
func open_shop(shop_id: String) -> bool:
	if is_open() or not ShopCatalog.is_open(shop_id):
		return false
	var stock := ShopCatalog.stock(shop_id)
	if stock.is_empty():
		return false
	_shop_id = shop_id
	_selected_id = str(stock[0].get("itemId", ""))
	_message = KEYS_OPEN_STATUS if ControlScheme.current() == ControlScheme.KEYS else OPEN_STATUS
	_message_color = UiTokens.TEXT_SECONDARY
	open()
	return is_open()


## The open shop's id ("" when closed).
func shop_id() -> String:
	return _shop_id if is_open() else ""


func selected_id() -> String:
	return _selected_id


func status_text() -> String:
	return status_label.text if status_label != null else ""


func close() -> void:
	super()
	_shop_id = ""


# --- actions ------------------------------------------------------------------------------------

## Selects stock entry `index` (the message gives way to the live hint).
func select_item(index: int) -> void:
	var item_id := _item_at(index)
	if item_id.is_empty():
		return
	_selected_id = item_id
	_message = ""
	refresh()


## Buy: buys the selected entry and says how it went.
func buy_selected() -> void:
	if not is_open() or _selected_id.is_empty():
		return
	var result := ShopCatalog.buy(_shop_id, _selected_id)
	if bool(result["ok"]):
		var name_text := ItemCatalog.item_name(_selected_id)
		var count := int(result["count"])
		_message = BOUGHT_MANY_FORMAT % [count, name_text, int(result["price"])] if count > 1 \
				else BOUGHT_FORMAT % [name_text, int(result["price"])]
		_message_color = UiTokens.ACCENT
	else:
		_message = _reason_text(str(result["reason"]), int(result["price"]))
		_message_color = UiTokens.DANGER
	refresh()


## Right click (or Space on a cell): selects entry `index`, then buys it.
func buy_at(index: int) -> void:
	var item_id := _item_at(index)
	if item_id.is_empty():
		return
	_selected_id = item_id
	buy_selected()


# --- view ---------------------------------------------------------------------------------------

func refresh() -> void:
	if content == null:
		return
	var stock: Array[Dictionary] = ShopCatalog.stock(_shop_id)
	title_label.text = ShopCatalog.shop_name(_shop_id) if not _shop_id.is_empty() else ""
	var keeper := str(ShopCatalog.shop(_shop_id).get("keeper", ""))
	var line := ShopCatalog.greeting(_shop_id)
	greeting_label.text = ("%s: \"%s\"" % [keeper, line]) if not keeper.is_empty() and not line.is_empty() else line
	var run := Services.run()
	var coins := run.coins() if run != null else 0
	coins_label.text = PRICE_FORMAT % coins
	_sync_cells(stock.size())
	var selected_index := -1
	for index in stock.size():
		var entry: Dictionary = stock[index]
		var item_id := str(entry.get("itemId", ""))
		var cell := stock_list.get_child(index) as ItemCell
		var sold_out := ShopCatalog.is_sold_out(_shop_id, entry)
		var price := ShopCatalog.price(entry)
		cell.set_content("%s\n%s" % [_entry_name(entry), SOLD_OUT_ROW if sold_out else PRICE_FORMAT % price],
				ItemIcons.icon(item_id))
		cell.tooltip_text = ItemCatalog.item_name(item_id)
		cell.set_locked(sold_out)
		cell.set_short(not sold_out and coins < price)
		if item_id == _selected_id:
			selected_index = index
		cell.set_selected(item_id == _selected_id)
	var selected := ShopCatalog.entry_of(_shop_id, _selected_id)
	if selected.is_empty():
		details_name_label.text = ""
		details_label.text = ""
		buy_button.disabled = true
	else:
		details_name_label.text = _entry_name(selected)
		details_label.text = _details(selected)
		buy_button.disabled = ShopCatalog.is_sold_out(_shop_id, selected)
	buy_button.focus_mode = Control.FOCUS_NONE if buy_button.disabled else Control.FOCUS_ALL
	if not _message.is_empty():
		status_label.text = _message
		status_label.add_theme_color_override(&"font_color", _message_color)
	elif selected_index >= 0:
		var reason := ShopCatalog.status(_shop_id, _selected_id)
		status_label.text = READY_STATUS if reason == ShopCatalog.READY \
				else _reason_text(reason, ShopCatalog.price(selected))
		status_label.add_theme_color_override(&"font_color",
				UiTokens.TEXT_SECONDARY if reason == ShopCatalog.READY else UiTokens.WARNING)
	else:
		status_label.text = ""


func _build() -> void:
	var bold := WindowStyle.bold_font(self)
	title_label = _label("Title", &"PanelTitle", 22)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin_icon = TextureRect.new()
	coin_icon.name = "CoinIcon"
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.texture = ChestModel.icon(ChestModel.COINS)
	content.add_child(coin_icon)
	coins_label = _label("Coins", &"WarningLabel", 18)
	coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	greeting_label = _label("Greeting", &"MutedLabel", 14)
	greeting_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stock_scroll = ScrollContainer.new()
	stock_scroll.name = "StockScroll"
	stock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stock_scroll.follow_focus = true
	content.add_child(stock_scroll)
	stock_list = GridContainer.new()
	stock_list.name = "Stock"
	stock_list.columns = COLUMNS
	stock_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_list.add_theme_constant_override(&"h_separation", CELL_GAP)
	stock_list.add_theme_constant_override(&"v_separation", CELL_GAP)
	stock_scroll.add_child(stock_list)
	details_name_label = _label("DetailsName", &"PanelTitle", 20)
	details_label = _label("Details", &"MutedLabel", DETAILS_FONT)
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	WindowStyle.set_line_pitch(details_label, DETAILS_FONT, DETAILS_PITCH)
	status_label = _label("Status", &"InfoLabel", 14)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buy_button = _button("Buy", BUY_TEXT, &"PrimaryButton", 16, buy_selected)
	close_button = _button("Close", CLOSE_TEXT, &"MutedButton", 14, close)
	for button: Button in [buy_button, close_button]:
		if bold != null:
			button.add_theme_font_override(&"font", bold)
		WindowStyle.round_corners(button, CORNER_RADIUS)


func _layout(width: float) -> void:
	var w := width
	_place(title_label, _rect(24.0, 14.0, w - 200.0, 54.0))
	_place(coin_icon, _rect(w - 170.0, 19.0, w - 170.0 + COIN_ICON, 19.0 + COIN_ICON))
	_place(coins_label, _rect(w - 134.0, 14.0, w - 24.0, 54.0))
	_place(greeting_label, _rect(24.0, 58.0, w - 24.0, 98.0))
	_place(stock_scroll, _rect(24.0, 108.0, 0.62 * w - 8.0, 500.0))
	_cell_width = maxf(1.0, (stock_scroll.size.x - (COLUMNS - 1) * CELL_GAP) / COLUMNS)
	for cell: Node in stock_list.get_children():
		(cell as Control).custom_minimum_size.x = _cell_width
	_place(details_name_label, _rect(0.64 * w, 108.0, w - 24.0, 140.0))
	_place(details_label, _rect(0.64 * w, 146.0, w - 24.0, 500.0))
	_place(status_label, _rect(24.0, 508.0, w - 24.0, 540.0))
	_place(buy_button, _rect(24.0, 548.0, 180.0, 590.0))
	_place(close_button, _rect(w - 112.0, 548.0, w - 24.0, 590.0))


# --- private ------------------------------------------------------------------------------------

## "Wood × 5" for an entry that gives several, else the item's name.
static func _entry_name(entry: Dictionary) -> String:
	var item_id := str(entry.get("itemId", ""))
	var count := ShopCatalog.count(entry)
	return "%s × %d" % [ItemCatalog.item_name(item_id), count] if count > 1 else ItemCatalog.item_name(item_id)


## The description, then the price and how many the bag holds.
func _details(entry: Dictionary) -> String:
	var item_id := str(entry.get("itemId", ""))
	var lines := PackedStringArray()
	lines.append(str(ItemCatalog.definition(item_id).get("description", "")))
	lines.append("")
	if ShopCatalog.is_sold_out(_shop_id, entry):
		lines.append(SOLD_OUT_STATUS)
	else:
		lines.append("Price: " + PRICE_FORMAT % ShopCatalog.price(entry))
	var run := Services.run()
	if run != null and Services.RunStateType.is_belt_item(item_id):
		lines.append(BELT_SLOTS_FORMAT % [run.potion_belt_open(), Services.RunStateType.POTION_BELT_SLOTS])
	else:
		lines.append("In your bag: %d" % (run.item_count(item_id) if run != null else 0))
	return "\n".join(lines)


func _reason_text(reason: String, price: int) -> String:
	match reason:
		ShopCatalog.NO_COINS:
			var run := Services.run()
			return NO_COINS_FORMAT % [price, run.coins() if run != null else 0]
		ShopCatalog.BAG_FULL:
			return BAG_FULL_STATUS
		ShopCatalog.SOLD_OUT:
			return SOLD_OUT_STATUS
		ShopCatalog.CLOSED:
			return CLOSED_STATUS
	return ""


## The item id of stock entry `index`, "" when there is none.
func _item_at(index: int) -> String:
	var stock := ShopCatalog.stock(_shop_id)
	return str(stock[index].get("itemId", "")) if index >= 0 and index < stock.size() else ""


func _on_run_changed(_payload: Dictionary) -> void:
	if is_open():
		refresh()


func _on_cell_pressed(cell: ItemCell) -> void:
	play_select()
	select_item(cell.index)


## Right click: select and buy. Space or Enter (`ui_accept`) buys the selected entry; the arrows (and
## WASD), Home and End move the selection on the two-column grid.
func _on_cell_input(event: InputEvent, cell: ItemCell) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null:
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			cell.accept_event()
			play_click()
			buy_at(cell.index)
		return
	if not event.is_pressed():
		return
	var current := cell.index
	if event.is_action_pressed(&"ui_accept") and not event.is_echo():
		cell.accept_event()
		play_click()
		buy_at(current)
		return
	var count := stock_list.get_child_count()
	var step := 0
	if event.is_action_pressed(&"ui_left", true):
		step = -1
	elif event.is_action_pressed(&"ui_right", true):
		step = 1
	elif event.is_action_pressed(&"ui_up", true):
		step = -COLUMNS
	elif event.is_action_pressed(&"ui_down", true):
		step = COLUMNS
	var target := -1
	if step != 0:
		target = current + step
	elif event.is_action_pressed(&"ui_home"):
		target = 0
	elif event.is_action_pressed(&"ui_end"):
		target = count - 1
	else:
		return
	cell.accept_event()
	if target < 0 or target >= count:
		return
	play_select()
	select_item(target)
	(stock_list.get_child(target) as Control).grab_focus()


func _make_cell() -> ItemCell:
	var cell := ItemCell.new(ItemCell.Layout.ROW, CELL_ICON, CELL_FONT)
	cell.custom_minimum_size = Vector2(_cell_width, CELL_HEIGHT)
	cell.pressed.connect(_on_cell_pressed.bind(cell))
	cell.gui_input.connect(_on_cell_input.bind(cell))
	return cell


## Keeps `count` cells, indexed in order; new cells get radius-5 corners.
func _sync_cells(count: int) -> void:
	while stock_list.get_child_count() > count:
		var last := stock_list.get_child(stock_list.get_child_count() - 1)
		stock_list.remove_child(last)
		last.queue_free()
	while stock_list.get_child_count() < count:
		var cell := _make_cell()
		stock_list.add_child(cell)
		WindowStyle.round_corners(cell, CORNER_RADIUS)
	for index in stock_list.get_child_count():
		(stock_list.get_child(index) as ItemCell).index = index
