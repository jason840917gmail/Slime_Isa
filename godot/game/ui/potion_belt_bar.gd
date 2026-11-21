extends Control
## The HUD console's potions group (docs/godot/specs/crafting.md 12.4): one 46-unit wooden slot per
## open belt slot (RunState `potion_belt_open`, at most four), in a row 4 apart, placed by hud.gd on
## the console's "potions" rect after the abilities. Slots not found yet are not drawn.
## - A slot set to a potion kind shows the kind's bag icon (ItemIcons), how many of that kind the bag
##   holds in a chip at the top left and the slot's key (`potion_<n>`: 1 to 4) in the corner badge;
##   at 0 the icon dims and the chip turns red (the slot keeps its kind).
## - An open slot set to nothing shows just its number, in the middle.
## The model follows RunState and the bag every frame (cheap; the view changes only when it does). A
## click on a slot with a kind drinks one (InventoryActions `drink_belt_slot`, as its key does); on an
## empty slot it opens the bag, where the Belt row sets a kind. The slots never take keyboard focus,
## and take no click while a window pauses the game.
##
## Owner: crafting / inventory (the look: UI, HUD console).

const Services := preload("res://game/shared/services.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const ConsoleStyle := preload("res://game/ui/console/console_style.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const ItemIcons := preload("res://game/inventory/item_icons.gd")
const PotionBelt := preload("res://game/inventory/potion_belt.gd")

const SLOT_SIZE := 46.0
const SLOT_GAP := 4.0
const ICON_SHARE := 0.74
## The kind's icon sits this far down from the slot's centre, clear of the count chip.
const ICON_DROP := 2.0
const EMPTY_FONT_SIZE := 18
const EMPTY_MODULATE := Color(1.0, 1.0, 1.0, 0.55)
const SPENT_MODULATE := Color(0.6, 0.6, 0.6, 0.45)
const INVENTORY_ACTIONS_GROUP := &"inventory_actions"
const MENU_WINDOWS_GROUP := &"menu_windows"

## The player script (to tell a dead slime), or null.
var player: Node
## index -> {"button", "icon", "count", "key", "number"}.
var _views: Array[Dictionary] = []
var _model: Array[Dictionary] = []
var _signature: String = ""


## How many slots the group shows now (the open belt slots).
static func slot_count() -> int:
	return PotionBelt.open_count()


## The row's size for `count` slots.
static func row_size(count: int) -> Vector2:
	return Vector2(count * SLOT_SIZE + maxf(0.0, count - 1.0) * SLOT_GAP, SLOT_SIZE)


func _ready() -> void:
	name = "PotionBelt"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh()


func _process(_delta: float) -> void:
	refresh()


## [{"kind", "name", "count", "key", "label", "interactive"}] per open slot (tests read it).
func snapshot() -> Array[Dictionary]:
	var run := Services.run()
	var out: Array[Dictionary] = []
	if run == null:
		return out
	var kinds := run.potion_belt_kinds()
	var interactive := player != null and is_instance_valid(player) and not bool(player.call(&"is_dead")) \
		and not _menu_paused()
	for index in run.potion_belt_open():
		var kind := kinds[index]
		var count := run.item_count(kind) if not kind.is_empty() else 0
		var key := PotionBelt.key_label(index)
		var item_name := ItemCatalog.item_name(kind) if not kind.is_empty() else ""
		var label := "Belt slot %d: empty, set a potion to it in your bag" % (index + 1)
		if not kind.is_empty():
			label = "%s × %d · %s drinks one" % [item_name, count, key if not key.is_empty() else str(index + 1)]
		out.append({"kind": kind, "name": item_name, "count": count, "key": key, "label": label,
			"interactive": interactive})
	return out


## Rebuilds the slots and their look when the model changed.
func refresh() -> void:
	_model = snapshot()
	var signature := str(_model)
	if signature == _signature:
		return
	_signature = signature
	if _views.size() != _model.size():
		_rebuild(_model.size())
	for index in _model.size():
		_show(index, _model[index])


## Clicks slot `index` (the button's `pressed`; tests call it): drinks one of its kind, or opens the
## bag for an empty slot. True when one was drunk.
func activate(index: int) -> bool:
	if index < 0 or index >= _model.size() or not bool(_model[index]["interactive"]):
		return false
	if str(_model[index]["kind"]).is_empty():
		var menu := get_tree().get_first_node_in_group(MENU_WINDOWS_GROUP)
		if menu != null and menu.has_method(&"toggle_menu"):
			menu.call(&"toggle_menu")
		return false
	var actions := get_tree().get_first_node_in_group(INVENTORY_ACTIONS_GROUP)
	var drunk := actions != null and bool(actions.call(&"drink_belt_slot", index))
	_signature = ""
	return drunk


## A window or the ceremony pauses the game (a hit-stop alone does not count), as the ability bar.
func _menu_paused() -> bool:
	if not is_inside_tree() or not get_tree().paused:
		return false
	var world := Services.world()
	return world == null or world.has_pause_reason(Services.WorldServiceType.PAUSE_MODAL) \
		or not world.has_pause_reason(Services.WorldServiceType.PAUSE_HIT_STOP)


func _rebuild(count: int) -> void:
	for view: Dictionary in _views:
		var old: Button = view["button"]
		remove_child(old)
		old.queue_free()
	_views.clear()
	size = row_size(count)
	for index in count:
		var button := Button.new()
		button.name = "Belt%d" % (index + 1)
		button.position = Vector2(index * (SLOT_SIZE + SLOT_GAP), 0.0)
		button.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		button.focus_mode = Control.FOCUS_NONE
		ConsoleStyle.style_slot_button(button)
		button.pressed.connect(activate.bind(index))
		add_child(button)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var inset := SLOT_SIZE * (1.0 - ICON_SHARE) * 0.5
		icon.position = Vector2(inset, inset + ICON_DROP)
		icon.size = Vector2.ONE * SLOT_SIZE * ICON_SHARE
		button.add_child(icon)
		var number := Label.new()
		number.name = "Number"
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		number.size = button.size
		number.add_theme_font_size_override(&"font_size", EMPTY_FONT_SIZE)
		number.add_theme_color_override(&"font_color", UiTokens.TEXT_MUTED)
		number.add_theme_color_override(&"font_outline_color", ConsoleStyle.OUTLINE)
		number.add_theme_constant_override(&"outline_size", 4)
		number.modulate = EMPTY_MODULATE
		button.add_child(number)
		var chip := ConsoleStyle.make_key_badge()
		chip.name = "Count"
		button.add_child(chip)
		var key := ConsoleStyle.make_key_badge()
		button.add_child(key)
		_views.append({"button": button, "icon": icon, "count": chip, "key": key, "number": number})


func _show(index: int, entry: Dictionary) -> void:
	var view: Dictionary = _views[index]
	var button: Button = view["button"]
	var icon: TextureRect = view["icon"]
	var chip: Label = view["count"]
	var key: Label = view["key"]
	var number: Label = view["number"]
	var kind := str(entry["kind"])
	var count := int(entry["count"])
	var empty := kind.is_empty()
	button.disabled = not bool(entry["interactive"])
	button.tooltip_text = str(entry["label"])
	icon.texture = ItemIcons.icon(kind) if not empty else null
	icon.modulate = SPENT_MODULATE if count <= 0 else Color.WHITE
	number.visible = empty
	number.text = str(entry["key"]) if not str(entry["key"]).is_empty() else str(index + 1)
	ConsoleStyle.place_key(key, "" if empty else str(entry["key"]), button.size)
	ConsoleStyle.place_key(chip, "" if empty else str(count), button.size)
	chip.position = Vector2.ONE * ConsoleStyle.KEY_INSET
	chip.add_theme_color_override(&"font_color", UiTokens.DANGER if count <= 0 else UiTokens.TEXT)
