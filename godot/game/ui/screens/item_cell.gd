extends Button
## One cell of a game-window list (Phaser `ItemList` buttons in the bag, the belt, the crafting
## window and the HUD hotbar): a `SlotButton` with an icon, a name and an optional corner tag,
## selected = pressed (toggle mode). Built in code by its list owner:
##   ROW  - icon left, then a two-line label (crafting recipes and materials, belt assignment);
##   TILE - icon above a centred two-line name, tag at the top right (bag cells, belt cells);
##   TEXT - a label only.
## Locked rows are dimmed with a grey icon; short rows get a 4 px danger edge and a danger label
## (styles.css:3604-3610). A cell can be a drag source (`drag_payload`) and a drop target
## (`drop_handler`), used by the bag's belt.
##
## Owner: crafting / inventory (UI).

const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

enum Layout { ROW, TILE, TEXT }

## Locked row text (crafting `.is-locked`).
const LOCKED_TEXT := Color("#9aa6b8")
const LOCKED_ALPHA := 0.5
const LOCKED_ICON_BRIGHTNESS := 0.8
const SHORT_EDGE_PX := 4.0
const GREYSCALE_SHADER := """
shader_type canvas_item;
uniform float brightness = 0.8;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114)) * brightness;
	COLOR = vec4(vec3(g), c.a);
}
"""

## The cell's index in its list.
var index: int = -1
## Not empty: the cell can be dragged and this Dictionary is the drag data.
var drag_payload: Dictionary = {}
## (target index: int, data: Dictionary) -> void; valid: the cell accepts drops with a
## "source_item_id".
var drop_handler: Callable = Callable()

var layout: int = Layout.ROW
var icon_rect: TextureRect
var name_label: Label
var tag_label: Label
var corner_label: Label
var _edge: ColorRect
var _box: Control
var _locked: bool = false
var _greyscale: ShaderMaterial
var _text_color: Variant = null


## `cell_layout`: Layout; `icon_px`: icon box (0 = none); `font_px`: label size.
func _init(cell_layout: int = Layout.ROW, icon_px: int = 36, font_px: int = 13) -> void:
	layout = cell_layout
	theme_type_variation = &"SlotButton"
	toggle_mode = true
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	_build(icon_px, font_px)


func _build(icon_px: int, font_px: int) -> void:
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad_x := 10 if layout == Layout.ROW or layout == Layout.TEXT else 4
	var pad_y := 6 if layout != Layout.TILE else 4
	margin.add_theme_constant_override(&"margin_left", pad_x)
	margin.add_theme_constant_override(&"margin_right", pad_x)
	margin.add_theme_constant_override(&"margin_top", pad_y)
	margin.add_theme_constant_override(&"margin_bottom", pad_y)
	add_child(margin)
	_box = margin
	var row: BoxContainer
	if layout == Layout.TILE:
		row = VBoxContainer.new()
	else:
		row = HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 10 if layout == Layout.ROW else 2)
	margin.add_child(row)
	if icon_px > 0 and layout != Layout.TEXT:
		icon_rect = TextureRect.new()
		icon_rect.name = "Icon"
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_rect.custom_minimum_size = Vector2(icon_px, icon_px)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon_rect)
	name_label = Label.new()
	name_label.name = "Name"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override(&"font_size", font_px)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if layout == Layout.TILE:
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	tag_label = Label.new()
	tag_label.name = "Tag"
	tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_label.theme_type_variation = &"WarningLabel"
	tag_label.add_theme_font_size_override(&"font_size", 12)
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tag_label.offset_left = -120.0
	tag_label.offset_right = -5.0
	tag_label.offset_top = 3.0
	tag_label.offset_bottom = 19.0
	add_child(tag_label)
	corner_label = Label.new()
	corner_label.name = "Corner"
	corner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner_label.theme_type_variation = &"MutedLabel"
	corner_label.add_theme_font_size_override(&"font_size", 11)
	corner_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	corner_label.offset_left = 6.0
	corner_label.offset_top = 3.0
	corner_label.offset_right = 40.0
	corner_label.offset_bottom = 18.0
	add_child(corner_label)
	_edge = ColorRect.new()
	_edge.name = "ShortEdge"
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.color = UiTokens.DANGER
	_edge.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_edge.offset_right = SHORT_EDGE_PX
	_edge.visible = false
	add_child(_edge)


## The name (and icon, and corner tag) of the cell. A null icon hides the icon box's picture.
func set_content(text: String, texture: Texture2D = null, tag: String = "") -> void:
	name_label.text = text
	tag_label.text = tag
	if icon_rect != null:
		icon_rect.texture = texture
		icon_rect.visible = texture != null or layout == Layout.ROW


func label_text() -> String:
	return name_label.text


func tag_text() -> String:
	return tag_label.text


## Selected = pressed, without the `pressed` signal.
func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)


func is_selected() -> bool:
	return button_pressed


## A disabled cell takes no clicks and no keyboard focus (arrows skip it).
func set_enabled(enabled: bool) -> void:
	disabled = not enabled
	focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	_box.modulate.a = 1.0 if enabled else UiTokens.DISABLED_ALPHA


## Locked recipe rows: dimmed, grey label and a greyscale icon; still selectable.
func set_locked(locked: bool) -> void:
	_locked = locked
	modulate.a = LOCKED_ALPHA if locked else 1.0
	if icon_rect != null:
		if locked and _greyscale == null:
			_greyscale = _greyscale_material()
		icon_rect.material = _greyscale if locked else null
	_apply_text_color()


## Short rows (missing materials): a 4 px danger edge and a danger label.
func set_short(short: bool) -> void:
	_edge.visible = short
	_apply_text_color()


## The label colour when the cell is neither locked nor short (null = the theme's).
func set_text_color(color: Variant) -> void:
	_text_color = color
	_apply_text_color()


func _apply_text_color() -> void:
	var color: Variant = _text_color
	if _locked:
		color = LOCKED_TEXT
	elif _edge.visible:
		color = UiTokens.DANGER
	if color is Color:
		name_label.add_theme_color_override(&"font_color", color)
	else:
		name_label.remove_theme_color_override(&"font_color")


# --- drag and drop (the bag's belt) ---------------------------------------------------------------

func _get_drag_data(_at_position: Vector2) -> Variant:
	if drag_payload.is_empty() or disabled:
		return null
	# A preview only inside a real drag (a direct call, as in tests, has none).
	if icon_rect != null and icon_rect.texture != null and is_inside_tree() and get_viewport().gui_is_dragging():
		var preview := TextureRect.new()
		preview.texture = icon_rect.texture
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		preview.size = icon_rect.custom_minimum_size
		preview.modulate.a = 0.8
		set_drag_preview(preview)
	return drag_payload.duplicate()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return drop_handler.is_valid() and data is Dictionary and (data as Dictionary).has("source_item_id")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if drop_handler.is_valid() and data is Dictionary:
		drop_handler.call(index, data)


static func _greyscale_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = GREYSCALE_SHADER
	var grey := ShaderMaterial.new()
	grey.shader = shader
	grey.set_shader_parameter(&"brightness", LOCKED_ICON_BRIGHTNESS)
	return grey
