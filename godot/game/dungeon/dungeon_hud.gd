extends CanvasLayer
## The dungeon's HUD chip (docs/godot/DUNGEONS.md "The HUD"): beside the coin chip, top left, the
## small keys held (the key icon and "x N") and, once found, the big key, the map and the compass.
## Made by the Dungeon node (game/dungeon/dungeon.gd) for its world and gone with it; it follows
## RunState `world_progress_changed` (DungeonState.notify).
##
## Owner: dungeon kit.

const Services := preload("res://game/shared/services.gd")
const DungeonState := preload("res://game/dungeon/dungeon_state.gd")
const DungeonItems := preload("res://game/dungeon/dungeon_items.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

## The HUD's layer (hud.gd's CanvasLayer is 10).
const LAYER := 10
## Right of the coin chip (hud.gd COIN_CHIP: 14, 12, 78 x 28).
const CHIP_AT := Vector2(100.0, 12.0)
const CHIP_HEIGHT := 28.0
const ICON := 22.0
const GAP := 4.0
const PAD := 7.0
const COUNT_WIDTH := 30.0

## The Dungeon node it shows (set before it enters the tree).
var dungeon: Node
var _chip: Panel
var _key: TextureRect
var _count: Label
var _items: Array[TextureRect] = []


func _init() -> void:
	name = "DungeonHud"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTokens.theme()
	root.position = CHIP_AT
	add_child(root)
	_chip = Panel.new()
	_chip.name = "KeyChip"
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTokens.SURFACE_BASE, 0.78)
	style.border_color = Color(UiTokens.BORDER, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(CHIP_HEIGHT * 0.5))
	_chip.add_theme_stylebox_override(&"panel", style)
	root.add_child(_chip)
	_key = _icon_rect(DungeonState.SMALL_KEY)
	_key.position = Vector2(PAD, (CHIP_HEIGHT - ICON) * 0.5)
	_chip.add_child(_key)
	_count = Label.new()
	_count.name = "Keys"
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count.theme_type_variation = &"HudLabel"
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.add_theme_color_override(&"font_color", UiTokens.TEXT)
	_count.position = Vector2(PAD + ICON + 2.0, 0.0)
	_count.size = Vector2(COUNT_WIDTH, CHIP_HEIGHT)
	_chip.add_child(_count)
	for item: String in [DungeonState.BIG_KEY, DungeonState.MAP, DungeonState.COMPASS]:
		var rect := _icon_rect(item)
		rect.set_meta(&"item", item)
		_chip.add_child(rect)
		_items.append(rect)
	var run := Services.run()
	if run != null:
		run.world_progress_changed.connect(_on_progress)
	refresh()


func _exit_tree() -> void:
	var run := Services.run()
	if run != null and run.world_progress_changed.is_connected(_on_progress):
		run.world_progress_changed.disconnect(_on_progress)


func _on_progress(_payload: Dictionary) -> void:
	refresh()


## Shows the record as it is now.
func refresh() -> void:
	var run := Services.run()
	var id := str(dungeon.get(&"dungeon_id")) if dungeon != null else ""
	if _count == null or run == null:
		return
	_count.text = "x %d" % DungeonState.small_keys(run, id)
	var x := PAD + ICON + 2.0 + COUNT_WIDTH
	for rect: TextureRect in _items:
		var held := DungeonState.has_item(run, id, str(rect.get_meta(&"item")))
		rect.visible = held
		if held:
			rect.position = Vector2(x, (CHIP_HEIGHT - ICON) * 0.5)
			x += ICON + GAP
	_chip.size = Vector2(x + PAD - GAP * 0.5, CHIP_HEIGHT)


## The text the key count shows (tests).
func key_text() -> String:
	return _count.text if _count != null else ""


func _icon_rect(item: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = item.capitalize().replace(" ", "")
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = DungeonItems.icon(item)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size = Vector2(ICON, ICON)
	return rect
