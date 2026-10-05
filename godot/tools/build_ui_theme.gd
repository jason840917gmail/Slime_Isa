extends SceneTree
## Builds res://game/ui/theme/slime_theme.tres, the one UI Theme of the game, from the design
## tokens in res://game/ui/theme/ui_tokens.gd (which port src/styles.css and the field-kit theme
## resource). Every theme type variation it defines is listed, with the CSS role it replaces and
## when to use it, in docs/godot/UI_THEME.md.
##
##   "<Godot 4.7.2 console exe>" --headless --path godot -s res://tools/build_ui_theme.gd
##
## The .tres is this tool's output: change the tokens or this file and rebuild, do not edit the
## theme in the editor (a rebuild would drop those edits). Icons (slider grabbers, check boxes,
## the option arrow) are drawn here and stored inside the .tres, so the theme needs no imported
## image. Excluded from exports with the rest of res://tools/.
##
## Owner: shell / UI theme.

const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

## Supersampling per axis for the drawn icons.
const ICON_SAMPLES := 4
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)


func _initialize() -> void:
	var theme := build()
	var error := ResourceSaver.save(theme, UiTokens.THEME_PATH)
	if error != OK:
		push_error("build_ui_theme: could not save %s (error %d)" % [UiTokens.THEME_PATH, error])
		quit(1)
		return
	var variations := 0
	for type_name: StringName in theme.get_type_list():
		if theme.get_type_variation_base(type_name) != &"":
			variations += 1
	print("build_ui_theme: wrote %s (%d types, %d type variations)" % [UiTokens.THEME_PATH, theme.get_type_list().size(), variations])
	quit(0)


## The whole theme. Static so tests can build it without writing the file.
static func build() -> Theme:
	var theme := Theme.new()
	var fonts := _fonts()
	if fonts["regular"] != null:
		theme.default_font = fonts["regular"]
	theme.default_font_size = UiTokens.FONT_SIZE
	_palette(theme)
	_labels(theme, fonts)
	_buttons(theme, fonts)
	_toggles(theme)
	_panels(theme)
	_bars(theme, fonts)
	_sliders(theme)
	_scrolling(theme)
	_tabs(theme)
	_text_inputs(theme)
	_lists_and_popups(theme)
	_misc(theme, fonts)
	return theme


# --- fonts ------------------------------------------------------------------------------------

## {"regular": Font or null (= Godot's default font), "bold": Font, "mono": Font}.
static func _fonts() -> Dictionary:
	var regular: Font = null
	if not UiTokens.FONT_PATH.is_empty():
		regular = load(UiTokens.FONT_PATH) as Font
	var bold: Font
	if not UiTokens.BOLD_FONT_PATH.is_empty():
		bold = load(UiTokens.BOLD_FONT_PATH) as Font
	else:
		# A FontVariation without a base font draws with Godot's default font.
		var variation := FontVariation.new()
		variation.resource_name = "Bold"
		variation.base_font = regular
		variation.variation_embolden = UiTokens.BOLD_EMBOLDEN
		bold = variation
	var mono := SystemFont.new()
	mono.resource_name = "Monospace"
	mono.font_names = UiTokens.MONOSPACE_FONTS
	return {"regular": regular, "bold": bold, "mono": mono}


# --- palette ----------------------------------------------------------------------------------

## Theme type `Palette`: the tokens for scripts that draw by hand
## (`get_theme_color(&"danger", &"Palette")`).
static func _palette(theme: Theme) -> void:
	var colors := {
		"page": UiTokens.PAGE, "surface_base": UiTokens.SURFACE_BASE,
		"surface_raised": UiTokens.SURFACE_RAISED, "surface_inset": UiTokens.SURFACE_INSET,
		"border": UiTokens.BORDER, "shadow": UiTokens.SHADOW, "drop_shadow": UiTokens.DROP_SHADOW,
		"text": UiTokens.TEXT, "text_secondary": UiTokens.TEXT_SECONDARY,
		"text_tertiary": UiTokens.TEXT_TERTIARY, "muted": UiTokens.TEXT_MUTED,
		"accent": UiTokens.ACCENT, "accent_strong": UiTokens.ACCENT_STRONG, "info": UiTokens.INFO,
		"warning": UiTokens.WARNING, "danger": UiTokens.DANGER, "special": UiTokens.SPECIAL,
	}
	for key: String in colors:
		theme.set_color(key, &"Palette", colors[key])
	theme.set_constant(&"spacing", &"Palette", UiTokens.SPACING)
	theme.set_constant(&"focus_width", &"Palette", UiTokens.FOCUS_WIDTH)


# --- labels -----------------------------------------------------------------------------------

static func _labels(theme: Theme, fonts: Dictionary) -> void:
	theme.set_color(&"font_color", &"Label", UiTokens.TEXT)
	theme.set_color(&"font_shadow_color", &"Label", CLEAR)
	theme.set_color(&"font_outline_color", &"Label", UiTokens.SHADOW)
	theme.set_constant(&"line_spacing", &"Label", 3)
	theme.set_constant(&"outline_size", &"Label", 0)
	theme.set_constant(&"shadow_offset_x", &"Label", 0)
	theme.set_constant(&"shadow_offset_y", &"Label", 1)
	theme.set_font_size(&"font_size", &"Label", UiTokens.FONT_SIZE)

	# Tone variations (Phaser Label `tone`).
	_label_variation(theme, &"MutedLabel", UiTokens.TEXT_MUTED)
	_label_variation(theme, &"SecondaryLabel", UiTokens.TEXT_SECONDARY)
	_label_variation(theme, &"TertiaryLabel", UiTokens.TEXT_TERTIARY)
	_label_variation(theme, &"AccentLabel", UiTokens.ACCENT)
	_label_variation(theme, &"InfoLabel", UiTokens.INFO)
	_label_variation(theme, &"WarningLabel", UiTokens.WARNING)
	_label_variation(theme, &"DangerLabel", UiTokens.DANGER)
	_label_variation(theme, &"SpecialLabel", UiTokens.SPECIAL)
	# Status / hint lines under a menu: 12 px muted.
	_label_variation(theme, &"CaptionLabel", UiTokens.TEXT_MUTED, UiTokens.FONT_SIZE_SMALL)

	# Window titles: 24 px bold warning ("Settings", "Controls", "Paused" at 26).
	_label_variation(theme, &"PanelTitle", UiTokens.WARNING, UiTokens.FONT_SIZE_TITLE, fonts["bold"])
	# Key names in the controls list and key hints: bold accent.
	_label_variation(theme, &"KeyLabel", UiTokens.ACCENT, UiTokens.FONT_SIZE, fonts["bold"])
	# HUD text over the world: 12 px bold with a dark drop shadow (`.game-ui--hud` text-shadow).
	_label_variation(theme, &"HudLabel", UiTokens.TEXT, UiTokens.FONT_SIZE_SMALL, fonts["bold"])
	theme.set_color(&"font_shadow_color", &"HudLabel", UiTokens.SHADOW)
	theme.set_constant(&"shadow_outline_size", &"HudLabel", 2)
	# The boss name over its health bar: 16 px bold danger.
	_label_variation(theme, &"BossName", UiTokens.DANGER, 16, fonts["bold"])
	theme.set_color(&"font_shadow_color", &"BossName", UiTokens.SHADOW)
	theme.set_constant(&"shadow_outline_size", &"BossName", 2)
	# The area / ability banner text (`.game-ui--area-title-card .scene-control--label`).
	_label_variation(theme, &"AreaTitle", UiTokens.WARNING, UiTokens.FONT_SIZE_TITLE, fonts["bold"])
	theme.set_color(&"font_shadow_color", &"AreaTitle", Color(UiTokens.SHADOW, 0.9))
	theme.set_constant(&"shadow_offset_y", &"AreaTitle", 2)
	theme.set_constant(&"shadow_outline_size", &"AreaTitle", 4)
	# Game over "Defeated".
	_label_variation(theme, &"DefeatTitle", UiTokens.DANGER, 32, fonts["bold"])
	theme.set_color(&"font_shadow_color", &"DefeatTitle", UiTokens.SHADOW)
	theme.set_constant(&"shadow_offset_y", &"DefeatTitle", 2)
	# End card title (`text-shadow: 0 3px 0 #081022, 0 0 18px #7a5cff66`).
	_label_variation(theme, &"EndCardTitle", UiTokens.SPECIAL, 34, fonts["bold"])
	theme.set_color(&"font_shadow_color", &"EndCardTitle", UiTokens.SHADOW)
	theme.set_color(&"font_outline_color", &"EndCardTitle", Color("#7a5cff40"))
	theme.set_constant(&"shadow_offset_y", &"EndCardTitle", 3)
	theme.set_constant(&"outline_size", &"EndCardTitle", 8)
	# Developer readouts (FPS panel): 11 px monospace.
	_label_variation(theme, &"DebugLabel", UiTokens.DEBUG_TEXT, 11, fonts["mono"])
	# Quest tracker objective lines: 12 px regular text with the soft HUD shadow.
	_label_variation(theme, &"TrackerObjectiveLabel", UiTokens.TEXT, UiTokens.FONT_SIZE_SMALL)
	theme.set_color(&"font_shadow_color", &"TrackerObjectiveLabel", UiTokens.SHADOW)
	theme.set_constant(&"shadow_offset_x", &"TrackerObjectiveLabel", 0)
	theme.set_constant(&"shadow_offset_y", &"TrackerObjectiveLabel", 1)
	theme.set_constant(&"shadow_outline_size", &"TrackerObjectiveLabel", 2)


static func _label_variation(theme: Theme, variation: StringName, color: Color, size: int = -1,
		font: Font = null) -> void:
	theme.set_type_variation(variation, &"Label")
	theme.set_color(&"font_color", variation, color)
	if size > 0:
		theme.set_font_size(&"font_size", variation, size)
	if font != null:
		theme.set_font(&"font", variation, font)


# --- buttons ----------------------------------------------------------------------------------

## `.scene-control--button`: inset fill, 1 px border, square; hover = accent text and border;
## focus = 2 px warning outline 2 px out; disabled = 45 % opacity.
static func _buttons(theme: Theme, fonts: Dictionary) -> void:
	_button_styles(theme, &"Button", 0)
	_button_colors(theme, &"Button", UiTokens.TEXT)
	theme.set_constant(&"h_separation", &"Button", 6)
	theme.set_constant(&"outline_size", &"Button", 0)
	theme.set_font_size(&"font_size", &"Button", UiTokens.FONT_SIZE)

	# Tone variations (Phaser Button `tone`).
	_button_variation(theme, &"PrimaryButton", UiTokens.ACCENT)
	_button_variation(theme, &"MutedButton", UiTokens.TEXT_MUTED)
	_button_variation(theme, &"DangerButton", UiTokens.DANGER)
	_button_variation(theme, &"WarningButton", UiTokens.WARNING)

	# Menu tabs (`.game-ui--menu-tabs`): radius 6; the open tab is drawn selected whether it is
	# the disabled button (Phaser) or a pressed toggle button.
	theme.set_type_variation(&"TabButton", &"Button")
	_button_styles(theme, &"TabButton", 6)
	var tab_selected := _box(UiTokens.SURFACE_INSET, UiTokens.WARNING, 1, 6, 10.0, 4.0)
	theme.set_stylebox(&"disabled", &"TabButton", tab_selected)
	theme.set_stylebox(&"pressed", &"TabButton", tab_selected)
	theme.set_stylebox(&"hover_pressed", &"TabButton", tab_selected)
	theme.set_color(&"font_disabled_color", &"TabButton", UiTokens.WARNING)
	theme.set_color(&"font_pressed_color", &"TabButton", UiTokens.WARNING)
	theme.set_color(&"font_hover_pressed_color", &"TabButton", UiTokens.WARNING)

	# Item cells (bag, chest, belt, crafting rows): radius 8; toggled = selected (warning border on
	# the raised surface, `[aria-selected="true"]`).
	theme.set_type_variation(&"SlotButton", &"Button")
	_button_styles(theme, &"SlotButton", 8)
	theme.set_stylebox(&"hover", &"SlotButton", _box(UiTokens.SURFACE_RAISED, UiTokens.ACCENT, 1, 8, 6.0, 4.0))
	var slot_selected := _box(UiTokens.SURFACE_RAISED, UiTokens.WARNING, 1, 8, 6.0, 4.0)
	theme.set_stylebox(&"pressed", &"SlotButton", slot_selected)
	theme.set_stylebox(&"hover_pressed", &"SlotButton", slot_selected)
	theme.set_color(&"font_pressed_color", &"SlotButton", UiTokens.WARNING)
	theme.set_color(&"font_hover_pressed_color", &"SlotButton", UiTokens.WARNING)
	theme.set_font_size(&"font_size", &"SlotButton", UiTokens.FONT_SIZE_SMALL)

	# HUD weapon hotbar slots (artwork-first HUD): transparent, 1 px text-colour border at 38 %,
	# radius 5; the selected slot (toggled) gets the warning border.
	theme.set_type_variation(&"HotbarSlot", &"Button")
	var hotbar_border := Color(UiTokens.TEXT, 0.38)
	theme.set_stylebox(&"normal", &"HotbarSlot", _box(CLEAR, hotbar_border, 1, 5, 4.0, 2.0))
	theme.set_stylebox(&"hover", &"HotbarSlot", _box(CLEAR, UiTokens.ACCENT, 1, 5, 4.0, 2.0))
	theme.set_stylebox(&"disabled", &"HotbarSlot", _box(CLEAR, Color(hotbar_border, hotbar_border.a * UiTokens.DISABLED_ALPHA), 1, 5, 4.0, 2.0))
	var hotbar_selected := _box(CLEAR, UiTokens.WARNING, 1, 5, 4.0, 2.0)
	theme.set_stylebox(&"pressed", &"HotbarSlot", hotbar_selected)
	theme.set_stylebox(&"hover_pressed", &"HotbarSlot", hotbar_selected)
	theme.set_stylebox(&"focus", &"HotbarSlot", _outline(UiTokens.WARNING, UiTokens.FOCUS_WIDTH, 2.0, 5))
	_button_colors(theme, &"HotbarSlot", UiTokens.TEXT)
	theme.set_color(&"font_pressed_color", &"HotbarSlot", UiTokens.WARNING)
	theme.set_color(&"font_hover_pressed_color", &"HotbarSlot", UiTokens.WARNING)
	theme.set_font_size(&"font_size", &"HotbarSlot", UiTokens.FONT_SIZE_BAR)

	# Belt slots in the bag window: SlotButton with a 60 % border while empty (`BeltSlot`) and a
	# solid one once a weapon sits there (`BeltSlotFilled`).
	for entry: Array in [[&"BeltSlot", 0.6], [&"BeltSlotFilled", 1.0]]:
		var belt: StringName = entry[0]
		theme.set_type_variation(belt, &"SlotButton")
		theme.set_stylebox(&"normal", belt, _box(UiTokens.SURFACE_INSET, Color(UiTokens.BORDER, float(entry[1])), 1, 8, 8.0, 4.0))

	# The dialogue box's Next button: accent, bold, radius 8.
	theme.set_type_variation(&"DialogueNextButton", &"Button")
	_button_styles(theme, &"DialogueNextButton", 8)
	_button_colors(theme, &"DialogueNextButton", UiTokens.ACCENT)
	theme.set_color(&"font_hover_color", &"DialogueNextButton", UiTokens.WARNING)
	theme.set_color(&"font_pressed_color", &"DialogueNextButton", UiTokens.WARNING)
	theme.set_color(&"font_hover_pressed_color", &"DialogueNextButton", UiTokens.WARNING)
	theme.set_font(&"font", &"DialogueNextButton", fonts["bold"])

	# Borderless clickable text (quest tracker "show the way" blocks, inline links).
	theme.set_type_variation(&"GhostButton", &"Button")
	var ghost := StyleBoxEmpty.new()
	_margins(ghost, 4.0, 2.0)
	var ghost_hover := _box(Color(UiTokens.WARNING, 0.1), CLEAR, 0, 6, 4.0, 2.0)
	theme.set_stylebox(&"normal", &"GhostButton", ghost)
	theme.set_stylebox(&"disabled", &"GhostButton", ghost)
	theme.set_stylebox(&"hover", &"GhostButton", ghost_hover)
	theme.set_stylebox(&"pressed", &"GhostButton", ghost_hover)
	theme.set_stylebox(&"hover_pressed", &"GhostButton", ghost_hover)
	theme.set_stylebox(&"focus", &"GhostButton", _outline(Color(UiTokens.WARNING, 0.6), UiTokens.FOCUS_WIDTH, 0.0, 6))
	theme.set_color(&"font_hover_color", &"GhostButton", UiTokens.TEXT)
	theme.set_color(&"font_pressed_color", &"GhostButton", UiTokens.TEXT)

	# Bold button text where a window wants it (`.scene-control--modalroot .scene-control--button`
	# asks for 700, which Phaser's inline font weight overrides; kept available).
	theme.set_type_variation(&"BoldButton", &"Button")
	theme.set_font(&"font", &"BoldButton", fonts["bold"])

	theme.set_color(&"font_color", &"LinkButton", UiTokens.ACCENT)
	theme.set_color(&"font_hover_color", &"LinkButton", UiTokens.WARNING)
	theme.set_color(&"font_pressed_color", &"LinkButton", UiTokens.WARNING)
	theme.set_color(&"font_focus_color", &"LinkButton", UiTokens.ACCENT)
	theme.set_color(&"font_disabled_color", &"LinkButton", Color(UiTokens.ACCENT, UiTokens.DISABLED_ALPHA))

	# MenuButton and OptionButton draw like buttons.
	for type_name: StringName in [&"MenuButton", &"OptionButton"]:
		_button_styles(theme, type_name, 0)
		_button_colors(theme, type_name, UiTokens.TEXT)
	theme.set_icon(&"arrow", &"OptionButton", _chevron_icon())
	theme.set_constant(&"arrow_margin", &"OptionButton", 8)
	theme.set_constant(&"modulate_arrow", &"OptionButton", 1)


static func _button_styles(theme: Theme, type_name: StringName, radius: int) -> void:
	var border := Color(UiTokens.BORDER, UiTokens.BUTTON_BORDER_ALPHA)
	theme.set_stylebox(&"normal", type_name, _box(UiTokens.SURFACE_INSET, border, 1, radius, 8.0, 4.0))
	theme.set_stylebox(&"hover", type_name, _box(UiTokens.SURFACE_INSET, UiTokens.ACCENT, 1, radius, 8.0, 4.0))
	var pressed := _box(UiTokens.SURFACE_BASE, UiTokens.ACCENT, 1, radius, 8.0, 4.0)
	theme.set_stylebox(&"pressed", type_name, pressed)
	theme.set_stylebox(&"hover_pressed", type_name, pressed)
	theme.set_stylebox(&"disabled", type_name, _box(Color(UiTokens.SURFACE_INSET, UiTokens.DISABLED_ALPHA),
		Color(border, border.a * UiTokens.DISABLED_ALPHA), 1, radius, 8.0, 4.0))
	theme.set_stylebox(&"focus", type_name, _outline(UiTokens.WARNING, UiTokens.FOCUS_WIDTH, 2.0, radius))


static func _button_colors(theme: Theme, type_name: StringName, text: Color) -> void:
	theme.set_color(&"font_color", type_name, text)
	theme.set_color(&"font_focus_color", type_name, text)
	theme.set_color(&"font_hover_color", type_name, UiTokens.ACCENT)
	theme.set_color(&"font_pressed_color", type_name, UiTokens.ACCENT)
	theme.set_color(&"font_hover_pressed_color", type_name, UiTokens.ACCENT)
	theme.set_color(&"font_disabled_color", type_name, Color(text, UiTokens.DISABLED_ALPHA))
	theme.set_color(&"font_outline_color", type_name, UiTokens.SHADOW)
	theme.set_color(&"icon_normal_color", type_name, text)
	theme.set_color(&"icon_focus_color", type_name, text)
	theme.set_color(&"icon_hover_color", type_name, UiTokens.ACCENT)
	theme.set_color(&"icon_pressed_color", type_name, UiTokens.ACCENT)
	theme.set_color(&"icon_hover_pressed_color", type_name, UiTokens.ACCENT)
	theme.set_color(&"icon_disabled_color", type_name, Color(text, UiTokens.DISABLED_ALPHA))


static func _button_variation(theme: Theme, variation: StringName, text: Color) -> void:
	theme.set_type_variation(variation, &"Button")
	theme.set_color(&"font_color", variation, text)
	theme.set_color(&"font_focus_color", variation, text)
	theme.set_color(&"font_disabled_color", variation, Color(text, UiTokens.DISABLED_ALPHA))
	theme.set_color(&"icon_normal_color", variation, text)
	theme.set_color(&"icon_focus_color", variation, text)


# --- check boxes and toggles --------------------------------------------------------------------

static func _toggles(theme: Theme) -> void:
	for type_name: StringName in [&"CheckBox", &"CheckButton"]:
		var empty := StyleBoxEmpty.new()
		_margins(empty, 4.0, 2.0)
		for style: StringName in [&"normal", &"pressed", &"hover", &"hover_pressed", &"disabled"]:
			theme.set_stylebox(style, type_name, empty)
		theme.set_stylebox(&"focus", type_name, _outline(UiTokens.WARNING, UiTokens.FOCUS_WIDTH, 2.0, 4))
		_button_colors(theme, type_name, UiTokens.TEXT)
		theme.set_color(&"font_pressed_color", type_name, UiTokens.TEXT)
		theme.set_constant(&"h_separation", type_name, 8)
	var border := Color(UiTokens.BORDER, UiTokens.BUTTON_BORDER_ALPHA)
	var off := UiTokens.SURFACE_INSET
	theme.set_icon(&"unchecked", &"CheckBox", _check_icon(off, border, false, 1.0))
	theme.set_icon(&"checked", &"CheckBox", _check_icon(UiTokens.ACCENT, UiTokens.ACCENT, true, 1.0))
	theme.set_icon(&"unchecked_disabled", &"CheckBox", _check_icon(off, border, false, UiTokens.DISABLED_ALPHA))
	theme.set_icon(&"checked_disabled", &"CheckBox", _check_icon(UiTokens.ACCENT, UiTokens.ACCENT, true, UiTokens.DISABLED_ALPHA))
	theme.set_icon(&"radio_unchecked", &"CheckBox", _radio_icon(false, 1.0))
	theme.set_icon(&"radio_checked", &"CheckBox", _radio_icon(true, 1.0))
	theme.set_icon(&"radio_unchecked_disabled", &"CheckBox", _radio_icon(false, UiTokens.DISABLED_ALPHA))
	theme.set_icon(&"radio_checked_disabled", &"CheckBox", _radio_icon(true, UiTokens.DISABLED_ALPHA))
	theme.set_icon(&"unchecked", &"CheckButton", _switch_icon(false, false, 1.0))
	theme.set_icon(&"checked", &"CheckButton", _switch_icon(true, false, 1.0))
	theme.set_icon(&"unchecked_disabled", &"CheckButton", _switch_icon(false, false, UiTokens.DISABLED_ALPHA))
	theme.set_icon(&"checked_disabled", &"CheckButton", _switch_icon(true, false, UiTokens.DISABLED_ALPHA))
	theme.set_icon(&"unchecked_mirrored", &"CheckButton", _switch_icon(false, true, 1.0))
	theme.set_icon(&"checked_mirrored", &"CheckButton", _switch_icon(true, true, 1.0))
	theme.set_icon(&"unchecked_disabled_mirrored", &"CheckButton", _switch_icon(false, true, UiTokens.DISABLED_ALPHA))
	theme.set_icon(&"checked_disabled_mirrored", &"CheckButton", _switch_icon(true, true, UiTokens.DISABLED_ALPHA))


# --- panels -----------------------------------------------------------------------------------

static func _panels(theme: Theme) -> void:
	var surface := Color(UiTokens.SURFACE_BASE, UiTokens.PANEL_ALPHA)
	var border := Color(UiTokens.BORDER, UiTokens.PANEL_BORDER_ALPHA)
	# `.scene-control--modalroot`: the shell windows (title, pause, settings, controls, credits,
	# game over, end card, save slots). Square, as Phaser draws them.
	var modal := _box(surface, border, 1, 0, 24.0, 16.0)
	theme.set_stylebox(&"panel", &"Panel", modal)
	theme.set_stylebox(&"panel", &"PanelContainer", modal)
	_panel_variation(theme, &"ModalPanel", modal)

	# Game windows with a drop shadow, radius 12 (inventory, chest, crafting, journal, quest
	# offer, world map: `border-radius: 12px; box-shadow: 0 18px 48px #080e1abf`).
	var window := _box(surface, border, 1, 12, 20.0, 16.0)
	_shadow(window, UiTokens.DROP_SHADOW, 22, Vector2(0.0, 12.0))
	_panel_variation(theme, &"WindowPanel", window)

	# NPC dialogue box: 2 px warning border at 55 %, radius 14.
	var dialogue := _box(surface, Color(UiTokens.WARNING, 0.55), 2, 14, 24.0, 18.0)
	_shadow(dialogue, Color("#080e1ad9"), 20, Vector2(0.0, 12.0))
	_panel_variation(theme, &"DialoguePanel", dialogue)

	# The speaker pill riding the dialogue's top edge.
	var name_plate := _box(UiTokens.SURFACE_INSET, Color(UiTokens.WARNING, 0.7), 2, 999, 14.0, 3.0)
	_shadow(name_plate, Color("#080e1a99"), 6, Vector2(0.0, 4.0))
	_panel_variation(theme, &"NamePlate", name_plate)

	# The menu tab strip over the bag / crafting / journal / map.
	var tab_strip := _box(surface, border, 1, 10, 8.0, 6.0)
	_shadow(tab_strip, UiTokens.DROP_SHADOW, 14, Vector2(0.0, 8.0))
	_panel_variation(theme, &"TabStripPanel", tab_strip)

	# Area / ability banner (`.game-ui--area-title-card`): accent border at 50 %, radius 12; the
	# CSS gradient #192642 -> #101a31 is drawn flat as its middle.
	var banner := _box(Color(UiTokens.SURFACE_RAISED.lerp(UiTokens.SURFACE_BASE, 0.5), UiTokens.PANEL_ALPHA),
		Color(UiTokens.ACCENT, 0.5), 1, 12, 20.0, 8.0)
	_panel_variation(theme, &"BannerPanel", banner)

	# First-time control hint pill (`.game-ui--control-hint`).
	var hint := _box(Color(UiTokens.SHADOW, 0.72), Color(UiTokens.ACCENT, 0.45), 1, 999, 18.0, 6.0)
	_panel_variation(theme, &"HintPanel", hint)

	# Quest tracker card (`.game-ui--quest-tracker`): warning border, thick left edge, radius 10.
	var tracker := _box(Color(UiTokens.SHADOW, 0.5), Color(UiTokens.WARNING, 0.45), 1, 10, 14.0, 10.0)
	tracker.border_width_left = 3
	_panel_variation(theme, &"TrackerPanel", tracker)

	# Boss health card (`.game-ui--boss-health-bar`): red border, radius 12, padding 0 12 px; the
	# gradient #261727 -> #101a31 is drawn flat as its middle.
	var boss := _box(Color(UiTokens.BOSS_SURFACE_TOP.lerp(UiTokens.SURFACE_BASE, 0.5), UiTokens.PANEL_ALPHA),
		UiTokens.BOSS_BORDER, 1, 12, 12.0, 0.0)
	_panel_variation(theme, &"BossPanel", boss)

	# A recessed well inside a window (detail panes, empty slots, list backgrounds).
	var inset := _box(Color(UiTokens.SURFACE_INSET, 0.7), Color(UiTokens.BORDER, 0.5), 1, 6, 10.0, 8.0)
	_panel_variation(theme, &"InsetPanel", inset)

	# No background: HUD groups and layout wrappers that must not draw.
	var bare := StyleBoxEmpty.new()
	_panel_variation(theme, &"BarePanel", bare)

	# Developer readouts (dev/RenderingDiagnostics.ts): cyan border, padding 9 / 11.
	var debug := _box(Color(UiTokens.SHADOW, 0.9), UiTokens.INFO, 1, 0, 11.0, 9.0)
	_panel_variation(theme, &"DebugPanel", debug)

	theme.set_stylebox(&"panel", &"TooltipPanel", _tooltip_box())
	theme.set_color(&"font_color", &"TooltipLabel", UiTokens.TEXT)
	theme.set_color(&"font_shadow_color", &"TooltipLabel", CLEAR)
	theme.set_color(&"font_outline_color", &"TooltipLabel", UiTokens.SHADOW)
	theme.set_font_size(&"font_size", &"TooltipLabel", UiTokens.FONT_SIZE_SMALL)


## A variation of both Panel and PanelContainer named `variation` (PanelContainer is the base,
## Panel picks the same stylebox through the `panel` item).
static func _panel_variation(theme: Theme, variation: StringName, style: StyleBox) -> void:
	theme.set_type_variation(variation, &"PanelContainer")
	theme.set_stylebox(&"panel", variation, style)


static func _tooltip_box() -> StyleBoxFlat:
	var box := _box(Color(UiTokens.SURFACE_RAISED, 0.97), UiTokens.BORDER, 1, 6, 10.0, 6.0)
	_shadow(box, UiTokens.DROP_SHADOW, 8, Vector2(0.0, 4.0))
	return box


# --- bars -------------------------------------------------------------------------------------

static func _bars(theme: Theme, _fonts: Dictionary) -> void:
	# `.scene-control--progressbar`: inset well, border 68 %, tone fill, 11 px text.
	var bar_border := Color(UiTokens.BORDER, UiTokens.BAR_BORDER_ALPHA)
	theme.set_stylebox(&"background", &"ProgressBar", _box(UiTokens.SURFACE_INSET, bar_border, 1, 0, 6.0, 2.0))
	theme.set_stylebox(&"fill", &"ProgressBar", _box(UiTokens.ACCENT, CLEAR, 0, 0, 0.0, 0.0))
	theme.set_color(&"font_color", &"ProgressBar", UiTokens.TEXT)
	theme.set_color(&"font_outline_color", &"ProgressBar", UiTokens.SHADOW)
	theme.set_font_size(&"font_size", &"ProgressBar", UiTokens.FONT_SIZE_BAR)

	# HUD pill bars (`.game-ui--hud .scene-control--progressbar`): no well, a 42 % white border,
	# a dark 1 px ring outside it, full radius; the fill is tinted per bar (HudBar.fill_color).
	theme.set_type_variation(&"HudBar", &"ProgressBar")
	var hud_background := _box(CLEAR, Color(UiTokens.TEXT, 0.42), 1, 9, 6.0, 2.0)
	_shadow(hud_background, Color("#0810224d"), 1, Vector2.ZERO)
	theme.set_stylebox(&"background", &"HudBar", hud_background)
	theme.set_stylebox(&"fill", &"HudBar", _box(UiTokens.ACCENT, CLEAR, 0, 8, 0.0, 0.0))
	theme.set_color(&"font_shadow_color", &"HudBar", UiTokens.SHADOW)
	theme.set_color(&"font_color", &"HudBar", UiTokens.TEXT)
	theme.set_font_size(&"font_size", &"HudBar", UiTokens.FONT_SIZE_BAR)

	# The boss bar inside its card: the inset well, radius 5, 16 px tall.
	theme.set_type_variation(&"BossBar", &"ProgressBar")
	theme.set_stylebox(&"background", &"BossBar", _box(UiTokens.SURFACE_INSET, bar_border, 1, 5, 6.0, 2.0))
	theme.set_stylebox(&"fill", &"BossBar", _box(UiTokens.DANGER, CLEAR, 0, 4, 0.0, 0.0))
	theme.set_color(&"font_shadow_color", &"BossBar", UiTokens.SHADOW)

	# The 56 x 8 player bar over the slime (`.game-ui--health-bar`): radius 4, no text.
	theme.set_type_variation(&"FloatingHealthBar", &"ProgressBar")
	theme.set_stylebox(&"background", &"FloatingHealthBar", _box(UiTokens.SURFACE_INSET, bar_border, 1, 4, 0.0, 0.0))
	theme.set_stylebox(&"fill", &"FloatingHealthBar", _box(UiTokens.ACCENT, CLEAR, 0, 3, 0.0, 0.0))


# --- sliders ----------------------------------------------------------------------------------

## `.scene-control--slider > input[type="range"]`: an 8 px track (inset, border 78 %, radius 4)
## filled with the tone up to the thumb; a 16 px warning thumb with a 2 px inset ring.
static func _sliders(theme: Theme) -> void:
	var border := Color(UiTokens.BORDER, UiTokens.BUTTON_BORDER_ALPHA)
	for vertical: bool in [false, true]:
		var type_name: StringName = &"VSlider" if vertical else &"HSlider"
		var track := _box(UiTokens.SURFACE_INSET, border, 1, 4, 0.0, 0.0)
		var fill := _box(UiTokens.ACCENT, CLEAR, 0, 4, 0.0, 0.0)
		for box: StyleBoxFlat in [track, fill]:
			if vertical:
				box.content_margin_left = 4.0
				box.content_margin_right = 4.0
			else:
				box.content_margin_top = 4.0
				box.content_margin_bottom = 4.0
		theme.set_stylebox(&"slider", type_name, track)
		theme.set_stylebox(&"grabber_area", type_name, fill)
		theme.set_stylebox(&"grabber_area_highlight", type_name, fill)
		theme.set_stylebox(&"focus", type_name, _outline(UiTokens.WARNING, UiTokens.FOCUS_WIDTH, 4.0, 6))
		theme.set_icon(&"grabber", type_name, _grabber_icon(UiTokens.WARNING, 1.0))
		theme.set_icon(&"grabber_highlight", type_name, _grabber_icon(UiTokens.WARNING.lightened(0.25), 1.0))
		theme.set_icon(&"grabber_disabled", type_name, _grabber_icon(UiTokens.WARNING, UiTokens.DISABLED_ALPHA))
		theme.set_constant(&"center_grabber", type_name, 0)
		theme.set_constant(&"grabber_offset", type_name, 0)


# --- scrolling --------------------------------------------------------------------------------

static func _scrolling(theme: Theme) -> void:
	for vertical: bool in [false, true]:
		var type_name: StringName = &"VScrollBar" if vertical else &"HScrollBar"
		var track := _box(Color(UiTokens.SURFACE_INSET, 0.6), CLEAR, 0, 4, 0.0, 0.0)
		var grabber := _box(UiTokens.BORDER, CLEAR, 0, 4, 0.0, 0.0)
		var highlight := _box(Color(UiTokens.ACCENT, 0.7), CLEAR, 0, 4, 0.0, 0.0)
		var pressed := _box(UiTokens.ACCENT, CLEAR, 0, 4, 0.0, 0.0)
		for box: StyleBoxFlat in [track, grabber, highlight, pressed]:
			box.set_content_margin_all(4.0)
		theme.set_stylebox(&"scroll", type_name, track)
		theme.set_stylebox(&"scroll_focus", type_name, track)
		theme.set_stylebox(&"grabber", type_name, grabber)
		theme.set_stylebox(&"grabber_highlight", type_name, highlight)
		theme.set_stylebox(&"grabber_pressed", type_name, pressed)
	var none := StyleBoxEmpty.new()
	theme.set_stylebox(&"panel", &"ScrollContainer", none)
	theme.set_stylebox(&"focus", &"ScrollContainer", none)


# --- tabs -------------------------------------------------------------------------------------

## TabContainer / TabBar drawn like the menu tab strip: rounded tab buttons, the open one in
## warning; the page is a modal panel.
static func _tabs(theme: Theme) -> void:
	var border := Color(UiTokens.BORDER, UiTokens.BUTTON_BORDER_ALPHA)
	var unselected := _box(UiTokens.SURFACE_INSET, border, 1, 6, 14.0, 6.0)
	var hovered := _box(UiTokens.SURFACE_INSET, UiTokens.ACCENT, 1, 6, 14.0, 6.0)
	var selected := _box(UiTokens.SURFACE_RAISED, UiTokens.WARNING, 1, 6, 14.0, 6.0)
	var disabled := _box(Color(UiTokens.SURFACE_INSET, UiTokens.DISABLED_ALPHA),
		Color(border, border.a * UiTokens.DISABLED_ALPHA), 1, 6, 14.0, 6.0)
	for type_name: StringName in [&"TabContainer", &"TabBar"]:
		theme.set_stylebox(&"tab_unselected", type_name, unselected)
		theme.set_stylebox(&"tab_hovered", type_name, hovered)
		theme.set_stylebox(&"tab_selected", type_name, selected)
		theme.set_stylebox(&"tab_disabled", type_name, disabled)
		theme.set_stylebox(&"tab_focus", type_name, _outline(UiTokens.WARNING, UiTokens.FOCUS_WIDTH, 2.0, 6))
		theme.set_color(&"font_selected_color", type_name, UiTokens.WARNING)
		theme.set_color(&"font_hovered_color", type_name, UiTokens.ACCENT)
		theme.set_color(&"font_unselected_color", type_name, UiTokens.TEXT)
		theme.set_color(&"font_disabled_color", type_name, Color(UiTokens.TEXT, UiTokens.DISABLED_ALPHA))
		theme.set_color(&"font_outline_color", type_name, UiTokens.SHADOW)
		theme.set_color(&"drop_mark_color", type_name, UiTokens.WARNING)
		theme.set_constant(&"tab_separation", type_name, 6)
		theme.set_constant(&"icon_separation", type_name, 6)
	theme.set_stylebox(&"tabbar_background", &"TabContainer", StyleBoxEmpty.new())
	var page := _box(Color(UiTokens.SURFACE_BASE, UiTokens.PANEL_ALPHA),
		Color(UiTokens.BORDER, UiTokens.PANEL_BORDER_ALPHA), 1, 0, 12.0, 12.0)
	theme.set_stylebox(&"panel", &"TabContainer", page)
	theme.set_constant(&"side_margin", &"TabContainer", 0)


# --- text input -------------------------------------------------------------------------------

static func _text_inputs(theme: Theme) -> void:
	var border := Color(UiTokens.BORDER, UiTokens.BUTTON_BORDER_ALPHA)
	var normal := _box(UiTokens.SURFACE_INSET, border, 1, 0, 8.0, 6.0)
	var read_only := _box(Color(UiTokens.SURFACE_INSET, 0.6), Color(border, 0.4), 1, 0, 8.0, 6.0)
	var focus := _outline(UiTokens.WARNING, UiTokens.FOCUS_WIDTH, 2.0, 0)
	for type_name: StringName in [&"LineEdit", &"TextEdit"]:
		theme.set_stylebox(&"normal", type_name, normal)
		theme.set_stylebox(&"read_only", type_name, read_only)
		theme.set_stylebox(&"focus", type_name, focus)
		theme.set_color(&"font_color", type_name, UiTokens.TEXT)
		theme.set_color(&"font_selected_color", type_name, UiTokens.TEXT)
		theme.set_color(&"font_placeholder_color", type_name, Color(UiTokens.TEXT_MUTED, 0.8))
		theme.set_color(&"font_outline_color", type_name, UiTokens.SHADOW)
		theme.set_color(&"caret_color", type_name, UiTokens.WARNING)
		theme.set_color(&"selection_color", type_name, Color(UiTokens.ACCENT, 0.35))
	theme.set_color(&"font_uneditable_color", &"LineEdit", Color(UiTokens.TEXT, UiTokens.DISABLED_ALPHA))
	theme.set_color(&"clear_button_color", &"LineEdit", UiTokens.TEXT_MUTED)
	theme.set_color(&"clear_button_color_pressed", &"LineEdit", UiTokens.ACCENT)
	theme.set_color(&"font_readonly_color", &"TextEdit", Color(UiTokens.TEXT, UiTokens.DISABLED_ALPHA))
	theme.set_color(&"background_color", &"TextEdit", CLEAR)
	theme.set_color(&"current_line_color", &"TextEdit", Color(UiTokens.SURFACE_RAISED, 0.5))


# --- lists and popups -------------------------------------------------------------------------

static func _lists_and_popups(theme: Theme) -> void:
	# ItemList rows read like `.scene-control--itemlist > button`: hover = accent border, selected =
	# warning text and border on the raised surface.
	var list_panel := StyleBoxEmpty.new()
	list_panel.set_content_margin_all(4.0)
	theme.set_stylebox(&"panel", &"ItemList", list_panel)
	theme.set_stylebox(&"focus", &"ItemList", StyleBoxEmpty.new())
	var hovered := _box(UiTokens.SURFACE_INSET, UiTokens.ACCENT, 1, 6, 6.0, 4.0)
	var selected := _box(UiTokens.SURFACE_RAISED, UiTokens.WARNING, 1, 6, 6.0, 4.0)
	theme.set_stylebox(&"hovered", &"ItemList", hovered)
	theme.set_stylebox(&"selected", &"ItemList", selected)
	theme.set_stylebox(&"selected_focus", &"ItemList", selected)
	theme.set_stylebox(&"hovered_selected", &"ItemList", selected)
	theme.set_stylebox(&"hovered_selected_focus", &"ItemList", selected)
	theme.set_stylebox(&"cursor", &"ItemList", _outline(UiTokens.WARNING, UiTokens.FOCUS_WIDTH, 0.0, 6))
	theme.set_stylebox(&"cursor_unfocused", &"ItemList", StyleBoxEmpty.new())
	theme.set_color(&"font_color", &"ItemList", UiTokens.TEXT)
	theme.set_color(&"font_hovered_color", &"ItemList", UiTokens.ACCENT)
	theme.set_color(&"font_selected_color", &"ItemList", UiTokens.WARNING)
	theme.set_color(&"font_hovered_selected_color", &"ItemList", UiTokens.WARNING)
	theme.set_color(&"font_outline_color", &"ItemList", UiTokens.SHADOW)
	theme.set_color(&"guide_color", &"ItemList", Color(UiTokens.BORDER, 0.3))
	theme.set_constant(&"h_separation", &"ItemList", 8)
	theme.set_constant(&"v_separation", &"ItemList", 8)
	theme.set_constant(&"line_separation", &"ItemList", 4)
	theme.set_constant(&"icon_margin", &"ItemList", 6)

	var popup := _box(UiTokens.SURFACE_RAISED, Color(UiTokens.BORDER, UiTokens.PANEL_BORDER_ALPHA), 1, 0, 6.0, 6.0)
	_shadow(popup, UiTokens.DROP_SHADOW, 10, Vector2(0.0, 6.0))
	theme.set_stylebox(&"panel", &"PopupMenu", popup)
	theme.set_stylebox(&"panel", &"PopupPanel", popup)
	theme.set_stylebox(&"hover", &"PopupMenu", _box(UiTokens.SURFACE_INSET, UiTokens.ACCENT, 1, 0, 6.0, 4.0))
	var separator := StyleBoxLine.new()
	separator.color = Color(UiTokens.BORDER, UiTokens.PANEL_BORDER_ALPHA)
	separator.thickness = 1
	theme.set_stylebox(&"separator", &"PopupMenu", separator)
	theme.set_color(&"font_color", &"PopupMenu", UiTokens.TEXT)
	theme.set_color(&"font_hover_color", &"PopupMenu", UiTokens.ACCENT)
	theme.set_color(&"font_disabled_color", &"PopupMenu", Color(UiTokens.TEXT, UiTokens.DISABLED_ALPHA))
	theme.set_color(&"font_accelerator_color", &"PopupMenu", UiTokens.TEXT_MUTED)
	theme.set_color(&"font_separator_color", &"PopupMenu", UiTokens.TEXT_MUTED)
	theme.set_color(&"font_outline_color", &"PopupMenu", UiTokens.SHADOW)
	theme.set_constant(&"v_separation", &"PopupMenu", 8)
	theme.set_constant(&"h_separation", &"PopupMenu", 8)


# --- the rest ---------------------------------------------------------------------------------

static func _misc(theme: Theme, fonts: Dictionary) -> void:
	theme.set_color(&"default_color", &"RichTextLabel", UiTokens.TEXT)
	theme.set_color(&"font_selected_color", &"RichTextLabel", UiTokens.TEXT)
	theme.set_color(&"selection_color", &"RichTextLabel", Color(UiTokens.ACCENT, 0.35))
	theme.set_color(&"font_shadow_color", &"RichTextLabel", CLEAR)
	theme.set_color(&"font_outline_color", &"RichTextLabel", UiTokens.SHADOW)
	theme.set_font(&"bold_font", &"RichTextLabel", fonts["bold"])
	theme.set_font(&"mono_font", &"RichTextLabel", fonts["mono"])
	for size_name: StringName in [&"normal_font_size", &"bold_font_size", &"italics_font_size",
			&"bold_italics_font_size", &"mono_font_size"]:
		theme.set_font_size(size_name, &"RichTextLabel", UiTokens.FONT_SIZE)
	theme.set_constant(&"line_separation", &"RichTextLabel", 3)
	theme.set_stylebox(&"normal", &"RichTextLabel", StyleBoxEmpty.new())
	theme.set_stylebox(&"focus", &"RichTextLabel", StyleBoxEmpty.new())

	for vertical: bool in [false, true]:
		var line := StyleBoxLine.new()
		line.color = Color(UiTokens.BORDER, UiTokens.PANEL_BORDER_ALPHA)
		line.thickness = 1
		line.vertical = vertical
		var type_name: StringName = &"VSeparator" if vertical else &"HSeparator"
		theme.set_stylebox(&"separator", type_name, line)
		theme.set_constant(&"separation", type_name, UiTokens.SPACING * 2)

	# Gaps: two spacing units, the gap Phaser's menus use between buttons.
	for type_name: StringName in [&"BoxContainer", &"HBoxContainer", &"VBoxContainer"]:
		theme.set_constant(&"separation", type_name, UiTokens.SPACING * 2)
	for type_name: StringName in [&"GridContainer", &"HFlowContainer", &"VFlowContainer"]:
		theme.set_constant(&"h_separation", type_name, UiTokens.SPACING * 2)
		theme.set_constant(&"v_separation", type_name, UiTokens.SPACING * 2)

	# Embedded windows and dialogs use the modal panel.
	var window_border := _box(Color(UiTokens.SURFACE_BASE, UiTokens.PANEL_ALPHA),
		Color(UiTokens.BORDER, UiTokens.PANEL_BORDER_ALPHA), 1, 0, 8.0, 8.0)
	window_border.expand_margin_top = 28.0
	theme.set_stylebox(&"embedded_border", &"Window", window_border)
	theme.set_stylebox(&"embedded_unfocused_border", &"Window", window_border)
	theme.set_color(&"title_color", &"Window", UiTokens.WARNING)
	theme.set_font(&"title_font", &"Window", fonts["bold"])
	theme.set_stylebox(&"panel", &"AcceptDialog", _box(Color(UiTokens.SURFACE_BASE, UiTokens.PANEL_ALPHA),
		CLEAR, 0, 0, 16.0, 12.0))


# --- stylebox helpers -------------------------------------------------------------------------

static func _box(background: Color, border: Color, border_width: int, radius: int, margin_x: float,
		margin_y: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.corner_detail = 8
	# Square boxes stay crisp; rounded ones are smoothed.
	box.anti_aliasing = radius > 0
	_margins(box, margin_x, margin_y)
	return box


static func _margins(box: StyleBox, margin_x: float, margin_y: float) -> void:
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y


## A focus ring: `width` px of `color`, `offset` px outside the control (CSS outline-offset).
static func _outline(color: Color, width: int, offset: float, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = color
	box.set_border_width_all(width)
	box.set_expand_margin_all(offset + float(width))
	box.set_corner_radius_all(radius + roundi(offset) + width if radius > 0 else 0)
	box.anti_aliasing = radius > 0
	return box


static func _shadow(box: StyleBoxFlat, color: Color, size: int, offset: Vector2) -> void:
	box.shadow_color = color
	box.shadow_size = size
	box.shadow_offset = offset


# --- drawn icons ------------------------------------------------------------------------------

## The slider thumb: a 16 px disc of `fill` with a 2 px inset-surface ring.
static func _grabber_icon(fill: Color, alpha: float) -> Texture2D:
	var ring := UiTokens.SURFACE_INSET
	var painter := func(p: Vector2) -> Color:
		var distance := p.distance_to(Vector2(8.0, 8.0))
		if distance <= 6.0:
			return Color(fill, alpha)
		if distance <= 8.0:
			return Color(ring, alpha)
		return CLEAR
	return _paint(16, 16, painter)


## A 16 px check box: rounded square, and a dark tick when checked.
static func _check_icon(fill: Color, border: Color, checked: bool, alpha: float) -> Texture2D:
	var tick := UiTokens.SURFACE_BASE
	var tick_points: Array = [Vector2(4.2, 8.4), Vector2(6.9, 11.0), Vector2(11.8, 5.2)]
	var painter := func(p: Vector2) -> Color:
		var distance := _rounded_box_distance(p, Vector2(8.0, 8.0), Vector2(7.0, 7.0), 3.0)
		if distance > 0.0:
			return CLEAR
		if checked and _polyline_distance(p, tick_points) <= 1.1:
			return Color(tick, alpha)
		if distance > -1.0:
			return Color(border, border.a * alpha)
		return Color(fill, alpha)
	return _paint(16, 16, painter)


## A 16 px radio button: ring, and an accent dot when checked.
static func _radio_icon(checked: bool, alpha: float) -> Texture2D:
	var ring := UiTokens.ACCENT if checked else Color(UiTokens.BORDER, UiTokens.BUTTON_BORDER_ALPHA)
	var painter := func(p: Vector2) -> Color:
		var distance := p.distance_to(Vector2(8.0, 8.0))
		if distance > 7.5:
			return CLEAR
		if checked and distance <= 3.5:
			return Color(UiTokens.ACCENT, alpha)
		if distance > 6.5:
			return Color(ring, ring.a * alpha)
		return Color(UiTokens.SURFACE_INSET, alpha)
	return _paint(16, 16, painter)


## A 32 x 16 switch for CheckButton: a pill and a knob (right and accent when on).
static func _switch_icon(on: bool, mirrored: bool, alpha: float) -> Texture2D:
	var knob_centre := Vector2(24.0 if on != mirrored else 8.0, 8.0)
	var track := Color(UiTokens.ACCENT, 0.35) if on else UiTokens.SURFACE_INSET
	var edge := UiTokens.ACCENT if on else Color(UiTokens.BORDER, UiTokens.BUTTON_BORDER_ALPHA)
	var knob := UiTokens.ACCENT if on else UiTokens.TEXT_MUTED
	var painter := func(p: Vector2) -> Color:
		if p.distance_to(knob_centre) <= 5.0:
			return Color(knob, alpha)
		var distance := _rounded_box_distance(p, Vector2(16.0, 8.0), Vector2(15.5, 7.5), 7.5)
		if distance > 0.0:
			return CLEAR
		if distance > -1.0:
			return Color(edge, edge.a * alpha)
		return Color(track, track.a * alpha)
	return _paint(32, 16, painter)


## The option button arrow: a 10 x 6 white chevron (tinted by the button's font colour).
static func _chevron_icon() -> Texture2D:
	var points: Array = [Vector2(1.0, 1.0), Vector2(5.0, 5.0), Vector2(9.0, 1.0)]
	var painter := func(p: Vector2) -> Color:
		return Color.WHITE if _polyline_distance(p, points) <= 0.9 else CLEAR
	return _paint(10, 6, painter)


## Rasterises `painter` (pixel-space point -> colour) with ICON_SAMPLES^2 samples per pixel.
static func _paint(width: int, height: int, painter: Callable) -> Texture2D:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var samples := float(ICON_SAMPLES * ICON_SAMPLES)
	for y in height:
		for x in width:
			var r := 0.0
			var g := 0.0
			var b := 0.0
			var a := 0.0
			for sy in ICON_SAMPLES:
				for sx in ICON_SAMPLES:
					var point := Vector2(x + (sx + 0.5) / ICON_SAMPLES, y + (sy + 0.5) / ICON_SAMPLES)
					var color: Color = painter.call(point)
					r += color.r * color.a
					g += color.g * color.a
					b += color.b * color.a
					a += color.a
			if a > 0.0:
				image.set_pixel(x, y, Color(r / a, g / a, b / a, a / samples))
	# Stored losslessly compressed inside the .tres (no import step, a few hundred bytes each).
	var texture := PortableCompressedTexture2D.new()
	# The compressed bytes are what the .tres stores; without them the icon would be saved empty.
	texture.keep_compressed_buffer = true
	texture.create_from_image(image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	return texture


static func _rounded_box_distance(p: Vector2, centre: Vector2, half: Vector2, radius: float) -> float:
	var q := (p - centre).abs() - (half - Vector2(radius, radius))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


static func _polyline_distance(p: Vector2, points: Array) -> float:
	var best := INF
	for index in range(points.size() - 1):
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + (b - a) * t))
	return best
