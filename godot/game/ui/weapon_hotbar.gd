extends Control
## The HUD weapon hotbar (Phaser `WeaponHotbarSurfacePort.ts` + `ui/weapon-hotbar.scene.json`;
## crafting spec 8.6): the four belt slots at the bottom centre, 256 × 56 at (-128, -172)-(128,
## -116) from (0.5, 1). An owned weapon shows its icon (its name is the tooltip); an empty or
## unowned slot shows its label as text and is disabled. The weapon in hand has a warning border
## and a small warning triangle under its cell (never colour alone). A click puts that slot's
## weapon in hand (InventoryActions.switch_weapon_slot: "<name> equipped", or "Finish the attack
## first" mid-swing) and plays the select cue. The cells never take keyboard focus, and a click
## never attacks. Under an open game window it cannot be clicked ([DIFF] K16).
##
## Built by hud.gd as a child of the HUD layer; refreshes on RunState `inventory_changed`,
## `weapon_loadout_changed` and `weapon_equipped`.
##
## Owner: crafting / inventory (UI).

const Services := preload("res://game/shared/services.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const ItemIcons := preload("res://game/inventory/item_icons.gd")
const WeaponLoadout := preload("res://game/player/weapon_loadout.gd")
const SfxPlayer := preload("res://game/runtime/sfx_player.gd")

const SLOT_COUNT := 4
## weapon-hotbar.scene.json: the container from (0.5, 1); 4 cells, gap 4 (61 × 56 each).
const RECT := Rect2(-128.0, -172.0, 256.0, 56.0)
const GAP := 4.0
const ICON_PX := 30
const FONT_PX := 10
## `.game-ui--weapon-hotbar` cells: 1 px #f5f7ff border at 38 %, radius 5, padding 2/3.
const CELL_BORDER := Color(UiTokens.TEXT, 0.38)
const CELL_RADIUS := 5
const MARKER_PX := 5.0
const INVENTORY_ACTIONS_GROUP := &"inventory_actions"
const SELECT_STREAM := "res://asset/audio/sfx/library/ui/hover.ogg"
const SELECT_VOLUME_DB := -1.9382

var cells: Array[Button] = []
var icons: Array[TextureRect] = []
var select_sfx: AudioStreamPlayer
var _model: Dictionary = {}


func _init() -> void:
	name = "WeaponHotbar"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = RECT.position.x
	offset_right = RECT.end.x
	offset_top = RECT.position.y
	offset_bottom = RECT.end.y


func _ready() -> void:
	if theme == null:
		theme = UiTokens.theme()
	var cell_width := (RECT.size.x - GAP * (SLOT_COUNT - 1)) / SLOT_COUNT
	for index in SLOT_COUNT:
		var cell := Button.new()
		cell.name = "Slot%d" % (index + 1)
		cell.focus_mode = Control.FOCUS_NONE
		cell.position = Vector2(index * (cell_width + GAP), 0.0)
		cell.size = Vector2(cell_width, RECT.size.y)
		cell.clip_text = true
		cell.add_theme_font_size_override(&"font_size", FONT_PX)
		cell.add_theme_color_override(&"font_shadow_color", UiTokens.SHADOW)
		cell.add_theme_constant_override(&"shadow_offset_y", 1)
		for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
			cell.add_theme_stylebox_override(state, _cell_style(CELL_BORDER, 1))
		cell.pressed.connect(_on_cell_pressed.bind(index))
		add_child(cell)
		cells.append(cell)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.set_anchors_preset(Control.PRESET_CENTER)
		icon.offset_left = -ICON_PX / 2.0
		icon.offset_right = ICON_PX / 2.0
		icon.offset_top = -ICON_PX / 2.0
		icon.offset_bottom = ICON_PX / 2.0
		cell.add_child(icon)
		icons.append(icon)
	select_sfx = SfxPlayer.new()
	select_sfx.name = "SelectSfx"
	select_sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	select_sfx.bus = &"Effects"
	select_sfx.volume_db = SELECT_VOLUME_DB
	select_sfx.set(&"min_interval_ms", 40.0)
	if ResourceLoader.exists(SELECT_STREAM):
		select_sfx.stream = load(SELECT_STREAM) as AudioStream
	add_child(select_sfx)
	var run := Services.run()
	if run != null:
		for changed: Signal in [run.inventory_changed, run.weapon_loadout_changed, run.weapon_equipped]:
			if not changed.is_connected(_on_run_changed):
				changed.connect(_on_run_changed)
	refresh()


func _exit_tree() -> void:
	var run := Services.run()
	if run != null:
		for changed: Signal in [run.inventory_changed, run.weapon_loadout_changed, run.weapon_equipped]:
			if changed.is_connected(_on_run_changed):
				changed.disconnect(_on_run_changed)


## The model (WeaponHotbarSurfacePort.snapshot): {"weapons": [{"id" "slot-N", "label", "item_id",
## "disabled"}], "selected_index"}.
static func snapshot() -> Dictionary:
	var run := Services.run()
	var belt := run.weapon_slots()
	var in_hand: Variant = run.equipped_weapon_id()
	var weapons: Array = []
	var selected := -1
	for index in belt.size():
		var entry: Variant = belt[index]
		var owned := WeaponLoadout.owns_weapon(entry)
		weapons.append({"id": "slot-%d" % (index + 1),
			"label": ItemCatalog.item_name(str(entry)) if entry != null else "Empty",
			"item_id": str(entry) if owned else "", "disabled": not owned})
		if owned and entry == in_hand and selected < 0:
			selected = index
	return {"weapons": weapons, "selected_index": selected}


func model() -> Dictionary:
	return _model


func refresh() -> void:
	_model = snapshot()
	var weapons: Array = _model["weapons"]
	for index in mini(weapons.size(), cells.size()):
		var entry: Dictionary = weapons[index]
		var cell := cells[index]
		var owned := not bool(entry["disabled"])
		cell.disabled = not owned
		cell.text = "" if owned else str(entry["label"])
		cell.tooltip_text = str(entry["label"]) if owned else ""
		icons[index].texture = ItemIcons.icon(str(entry["item_id"])) if owned else null
		var selected := index == int(_model["selected_index"])
		var border := UiTokens.WARNING if selected else CELL_BORDER
		for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
			cell.add_theme_stylebox_override(state, _cell_style(border, 2 if selected else 1))
	queue_redraw()


## The triangle under the cell in hand.
func _draw() -> void:
	var selected := int(_model.get("selected_index", -1))
	if selected < 0 or selected >= cells.size():
		return
	var cell := cells[selected]
	var centre := cell.position.x + cell.size.x / 2.0
	var top := RECT.size.y + 2.0
	draw_colored_polygon(PackedVector2Array([Vector2(centre - MARKER_PX, top), Vector2(centre + MARKER_PX, top),
		Vector2(centre, top + MARKER_PX)]), UiTokens.WARNING)


func _on_cell_pressed(index: int) -> void:
	if select_sfx != null and select_sfx.has_method(&"play_cue"):
		select_sfx.call(&"play_cue")
	if index >= 0 and index < SLOT_COUNT and not WeaponLoadout.weapon_at(index).is_empty():
		var actions := get_tree().get_first_node_in_group(INVENTORY_ACTIONS_GROUP)
		if actions != null:
			actions.call(&"switch_weapon_slot", index)
	# A refused equip leaves the real selection in place.
	refresh()


func _on_run_changed(_payload: Dictionary) -> void:
	refresh()


static func _cell_style(border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(CELL_RADIUS)
	style.content_margin_left = 3.0
	style.content_margin_right = 3.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style
