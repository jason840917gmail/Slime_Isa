extends CanvasLayer
## The interaction prompt (Phaser `InteractionRouter.ts:27-31, 59-66, 199-201`; interaction spec
## 2.5, 7.4): "Right-click: <prompt>" in 14 px #e7fff5 on #101a31 at 0.8 alpha, padded 12 x 7,
## centred 42 px above the bottom of the screen. Layer 9: above the travel fades (5) and the
## floating text (8), below the HUD (10), like Phaser's unfaded UI camera. PAUSABLE: it keeps its
## last text while the game is paused.
##
## Owner: interaction.

const FONT_SIZE := 14
const TEXT_COLOR := Color("#e7fff5")
const BACKGROUND := Color(Color("#101a31"), 0.8)
const PADDING_X := 12.0
const PADDING_Y := 7.0
const BOTTOM_GAP := 42.0
const LAYER := 9
const INTERACT_ACTION := &"interact"
const ControlScheme := preload("res://game/player/mouse/control_scheme.gd")

var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	layer = LAYER
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.content_margin_left = PADDING_X
	style.content_margin_right = PADDING_X
	style.content_margin_top = PADDING_Y
	style.content_margin_bottom = PADDING_Y
	_panel.add_theme_stylebox_override(&"panel", style)
	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_label.add_theme_color_override(&"font_color", TEXT_COLOR)
	_panel.add_child(_label)
	add_child(_panel)
	_panel.visible = false
	get_viewport().size_changed.connect(_place)


func show_prompt(text: String) -> void:
	if _label.text != text:
		_label.text = text
		_panel.reset_size()
	_panel.visible = true
	_place()


func hide_prompt() -> void:
	if _panel != null:
		_panel.visible = false


func is_showing() -> bool:
	return _panel != null and _panel.visible


func get_text() -> String:
	return _label.text if _label != null else ""


## "Right-click" for the right mouse button (ControlLabels `controlVerb('interact')`), following the
## first event bound to `interact`. A mouse control scheme names its order button instead ("Click").
static func interact_verb() -> String:
	var order_verb := ControlScheme.order_verb(ControlScheme.current())
	if not order_verb.is_empty():
		return order_verb
	for event: InputEvent in InputMap.action_get_events(INTERACT_ACTION):
		if event is InputEventMouseButton:
			match (event as InputEventMouseButton).button_index:
				MOUSE_BUTTON_RIGHT:
					return "Right-click"
				MOUSE_BUTTON_LEFT:
					return "Left-click"
				MOUSE_BUTTON_MIDDLE:
					return "Middle-click"
		elif event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return "Press " + OS.get_keycode_string(code)
	return "Right-click"


func _place() -> void:
	if _panel == null:
		return
	var view := get_viewport().get_visible_rect().size
	var size := _panel.get_combined_minimum_size()
	_panel.size = size
	_panel.position = Vector2(roundf(view.x / 2.0 - size.x / 2.0), roundf(view.y - BOTTOM_GAP - size.y / 2.0))
