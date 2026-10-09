extends RefCounted
## Shared look of the HUD console's pieces (docs/design/2026-10-07-hud-console-mockup.md): the
## wooden slot frame (`slot.webp`) behind buttons and the small key badge in a slot's corner.
## Used by hud_console.gd, weapon_hotbar.gd and ability_bar.gd.
##
## Owner: UI (HUD console).

const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")

const SLOT_TEXTURE := "res://asset/UI/hud-console/slot.webp"
const KEY_FONT_SIZE := 10
const KEY_HEIGHT := 13.0
const KEY_MIN_WIDTH := 14.0
## Inset of the badge from the slot's bottom-right corner.
const KEY_INSET := 3.0
const OUTLINE := Color("#180e08")

static var _slot_texture: Texture2D


## The slot frame as a stylebox (a flat dark square while the art is missing).
static func slot_style() -> StyleBox:
	if _slot_texture == null and ResourceLoader.exists(SLOT_TEXTURE):
		_slot_texture = load(SLOT_TEXTURE) as Texture2D
	if _slot_texture == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(UiTokens.SURFACE_BASE, 0.8)
		flat.set_corner_radius_all(8)
		return flat
	var style := StyleBoxTexture.new()
	style.texture = _slot_texture
	return style


## Applies the slot frame to every state of `button`.
static func style_slot_button(button: BaseButton) -> void:
	var style := slot_style()
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		button.add_theme_stylebox_override(state, style)


## A key badge Label (dark rounded box, bordered, small bold text).
static func make_key_badge() -> Label:
	var key := Label.new()
	key.name = "Key"
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.add_theme_font_size_override(&"font_size", KEY_FONT_SIZE)
	key.add_theme_color_override(&"font_color", UiTokens.TEXT)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UiTokens.SURFACE_BASE, 0.92)
	box.border_color = UiTokens.BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 3.0
	box.content_margin_right = 3.0
	key.add_theme_stylebox_override(&"normal", box)
	return key


## Puts `text` on `key` and sizes it into the bottom-right corner of a `slot`-sized parent;
## hidden when `text` is empty.
static func place_key(key: Label, text: String, slot: Vector2) -> void:
	key.text = text
	key.visible = not text.is_empty()
	var font := key.get_theme_font(&"font")
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, KEY_FONT_SIZE).x if font != null else 8.0
	var width := maxf(KEY_MIN_WIDTH, text_width + 8.0)
	key.size = Vector2(width, KEY_HEIGHT)
	key.position = slot - Vector2(KEY_INSET + width, KEY_INSET + KEY_HEIGHT)


## The first keyboard key's label of `action` ("E" for `weapon_next`, whose first binding is the
## mouse wheel); "" when it has no key.
static func key_of(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var label := ControlLabels.event_label(event)
			if not label.is_empty():
				return label
	return ""
