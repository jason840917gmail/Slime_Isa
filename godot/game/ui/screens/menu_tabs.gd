extends Control
## The menu tab strip (Phaser `MenuTabsSurfacePort.ts` + `ui/menu-tabs.scene.json`; crafting spec
## 5.2): while the bag, crafting, journal or map window is open, a 360 × 36 strip at the top centre
## switches between them. The open window's tab is the disabled one, drawn in warning; a tab whose
## window does not exist yet (journal, map) is disabled and dimmed. The first time, a bubble under
## the strip explains the tabs (until a tab is clicked, or the menu closes after it was read 3 s).
## MenuWindows (menu_windows.gd) owns the state and calls `refresh`; a click emits `tab_pressed`.
##
## Owner: crafting / inventory (UI).

const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const Services := preload("res://game/shared/services.gd")

## A tab was clicked (its tab id).
signal tab_pressed(tab: StringName)

const TABS: Array[StringName] = [&"inventory", &"crafting", &"journal", &"map"]
const LABELS := {&"inventory": "Bag", &"crafting": "Crafting", &"journal": "Journal", &"map": "Map"}
const COACH_TEXT := "These tabs switch between your Bag, Crafting, Journal and Map. Click one!"
## menu-tabs.scene.json: the strip `(-180, 4)-(180, 40)` from `(0.5, 0)`; the bubble 12 px under it,
## 20 px wider on each side, 62 tall.
const STRIP_RECT := Rect2(-180.0, 4.0, 360.0, 36.0)
const COACH_RECT := Rect2(-200.0, 52.0, 400.0, 62.0)
const COACH_BACKGROUND := Color("#0b1528f2")
const COACH_BOB_PX := 4.0
const COACH_BOB_S := 1.1

var strip: PanelContainer
var buttons: Dictionary = {}
var coach: PanelContainer
var coach_label: Label
var _bob: Tween


func _init() -> void:
	name = "MenuTabs"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func _ready() -> void:
	strip = PanelContainer.new()
	strip.name = "Strip"
	strip.theme_type_variation = &"TabStripPanel"
	_anchor_top_centre(strip, STRIP_RECT)
	add_child(strip)
	var row := HBoxContainer.new()
	row.name = "Tabs"
	row.add_theme_constant_override(&"separation", 6)
	strip.add_child(row)
	for tab: StringName in TABS:
		var button := Button.new()
		button.name = String(LABELS[tab])
		button.text = String(LABELS[tab])
		button.theme_type_variation = &"TabButton"
		button.add_theme_font_size_override(&"font_size", 13)
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_pressed.bind(tab))
		row.add_child(button)
		buttons[tab] = button
	coach = PanelContainer.new()
	coach.name = "Coach"
	coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = COACH_BACKGROUND
	style.border_color = UiTokens.WARNING
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	coach.add_theme_stylebox_override(&"panel", style)
	_anchor_top_centre(coach, COACH_RECT)
	coach.visible = false
	add_child(coach)
	coach_label = Label.new()
	coach_label.name = "Text"
	coach_label.theme_type_variation = &"WarningLabel"
	coach_label.add_theme_font_size_override(&"font_size", 15)
	coach_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coach_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coach_label.text = COACH_TEXT
	coach.add_child(coach_label)


## Shows the strip while `current` (a tab id, &"" = none) is open. `available` holds the tabs
## whose window exists; `coach_visible` shows the bubble.
func refresh(current: StringName, available: Array[StringName], coach_visible: bool) -> void:
	visible = current != &""
	for tab: StringName in TABS:
		var button: Button = buttons[tab]
		var missing := not tab in available
		button.disabled = tab == current or missing
		button.set_pressed_no_signal(false)
		button.modulate.a = UiTokens.DISABLED_ALPHA if missing and tab != current else 1.0
		if missing and tab != current and button.is_inside_tree():
			button.add_theme_stylebox_override(&"disabled", button.get_theme_stylebox(&"normal"))
			button.add_theme_color_override(&"font_disabled_color", UiTokens.TEXT)
		else:
			button.remove_theme_stylebox_override(&"disabled")
			button.remove_theme_color_override(&"font_disabled_color")
	_set_coach(visible and coach_visible)


func is_tab_disabled(tab: StringName) -> bool:
	var button: Button = buttons.get(tab)
	return button == null or button.disabled


func _on_pressed(tab: StringName) -> void:
	tab_pressed.emit(tab)


func _set_coach(wanted: bool) -> void:
	if coach.visible == wanted:
		return
	coach.visible = wanted
	if _bob != null:
		_bob.kill()
		_bob = null
	coach.offset_top = COACH_RECT.position.y
	coach.offset_bottom = COACH_RECT.end.y
	var feel := Services.feel()
	if not wanted or (feel != null and feel.reduce_motion):
		return
	_bob = coach.create_tween()
	_bob.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_bob.set_loops()
	_bob.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob.tween_property(coach, "offset_top", COACH_RECT.position.y + COACH_BOB_PX, COACH_BOB_S / 2.0)
	_bob.parallel().tween_property(coach, "offset_bottom", COACH_RECT.end.y + COACH_BOB_PX, COACH_BOB_S / 2.0)
	_bob.tween_property(coach, "offset_top", COACH_RECT.position.y, COACH_BOB_S / 2.0)
	_bob.parallel().tween_property(coach, "offset_bottom", COACH_RECT.end.y, COACH_BOB_S / 2.0)


static func _anchor_top_centre(control: Control, rect: Rect2) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = rect.position.x
	control.offset_right = rect.end.x
	control.offset_top = rect.position.y
	control.offset_bottom = rect.end.y
