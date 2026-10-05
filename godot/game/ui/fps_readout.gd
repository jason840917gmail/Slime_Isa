extends CanvasLayer
class_name FpsReadout
## Trial performance readout (the 60-fps test instrument). World spec section 7.
## Top-right panel on layer 100, PROCESS_MODE_ALWAYS, mouse_filter IGNORE, panel border 1 px
## #72d8ff, background rgba(8,16,34,0.9), text #d7e7f8 11 px monospace, padding 9/11 px.
## Refreshed every UPDATE_INTERVAL_MS with:
##   fps %.1f | frame ms %.2f (mean over the window) | worst ms %.2f
##   zoom %.3f  mode gameplay|overview | deadzone W x H
##   draw calls (RENDER_TOTAL_DRAW_CALLS_IN_FRAME), objects, nodes (OBJECT_NODE_COUNT)
## Visible by default; F3 (raw KEY_F3 in `_unhandled_input`) toggles it.
##
## Owner: world builder.

const WorldCamera := preload("res://game/world/world_camera.gd")

const UPDATE_INTERVAL_MS := 200.0
## dev/RenderingDiagnostics.ts panel style.
const PANEL_MARGIN := 10.0
const PANEL_BORDER := Color("#72d8ff")
const PANEL_BACKGROUND := Color(8.0 / 255.0, 16.0 / 255.0, 34.0 / 255.0, 0.9)
const TEXT_COLOR := Color("#d7e7f8")
const FONT_SIZE := 11
const PADDING_X := 11
const PADDING_Y := 9
const MONOSPACE_FONTS: PackedStringArray = ["Consolas", "Menlo", "DejaVu Sans Mono", "Courier New", "monospace"]

var _camera: WorldCamera
var _panel: PanelContainer
var _label: Label
var _window_ms: float = 0.0
var _frame_count: int = 0
var _frame_sum_ms: float = 0.0
var _frame_worst_ms: float = 0.0


## Builds the panel and label.
func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var anchor := Control.new()
	anchor.name = "Anchor"
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(anchor)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -PANEL_MARGIN
	_panel.offset_right = -PANEL_MARGIN
	_panel.offset_top = PANEL_MARGIN
	_panel.offset_bottom = PANEL_MARGIN
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BACKGROUND
	style.border_color = PANEL_BORDER
	style.set_border_width_all(1)
	style.content_margin_left = PADDING_X
	style.content_margin_right = PADDING_X
	style.content_margin_top = PADDING_Y
	style.content_margin_bottom = PADDING_Y
	_panel.add_theme_stylebox_override(&"panel", style)
	anchor.add_child(_panel)

	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	var mono := SystemFont.new()
	mono.font_names = MONOSPACE_FONTS
	mono.fallbacks = [ThemeDB.fallback_font]
	settings.font = mono
	settings.font_size = FONT_SIZE
	settings.font_color = TEXT_COLOR
	_label.label_settings = settings
	_label.text = "fps --"
	_panel.add_child(_label)


## Camera whose zoom/mode/deadzone are shown (`get_zoom_mode()`, `get_deadzone_size()`).
func bind_camera(camera: WorldCamera) -> void:
	_camera = camera


## Accumulates frame times and refreshes the text every UPDATE_INTERVAL_MS.
func _process(delta: float) -> void:
	var frame_ms := delta * 1000.0
	_frame_count += 1
	_frame_sum_ms += frame_ms
	_frame_worst_ms = maxf(_frame_worst_ms, frame_ms)
	_window_ms += frame_ms
	if _window_ms < UPDATE_INTERVAL_MS:
		return
	if visible:
		_label.text = _compose_text()
	_window_ms = 0.0
	_frame_count = 0
	_frame_sum_ms = 0.0
	_frame_worst_ms = 0.0


## F3 toggles visibility.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		visible = not visible
		if visible:
			_label.text = _compose_text()
		get_viewport().set_input_as_handled()


func _compose_text() -> String:
	var mean_ms := _frame_sum_ms / float(_frame_count) if _frame_count > 0 else 0.0
	var lines := PackedStringArray()
	lines.append("fps %.1f" % Engine.get_frames_per_second())
	lines.append("frame ms %.2f  worst ms %.2f" % [mean_ms, _frame_worst_ms])
	if _camera != null and is_instance_valid(_camera):
		var deadzone := _camera.get_deadzone_size()
		lines.append("zoom %.3f  mode %s" % [_camera.target_zoom, _camera.get_zoom_mode()])
		lines.append("deadzone %d x %d" % [roundi(deadzone.x), roundi(deadzone.y)])
	lines.append("draw calls %d  objects %d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	lines.append("nodes %d" % int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	return "\n".join(lines)
