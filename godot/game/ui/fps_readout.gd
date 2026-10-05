extends CanvasLayer
class_name FpsReadout
## Trial performance readout (the 60-fps test instrument). World spec section 7.
## Top-right panel on layer 100, PROCESS_MODE_ALWAYS, mouse_filter IGNORE, styled by the UI theme's
## `DebugPanel` (border 1 px #72d8ff, background rgba(8,16,34,0.9), padding 9/11 px) and `DebugLabel`
## (#d7e7f8 11 px monospace) variations (docs/godot/UI_THEME.md).
## Refreshed every UPDATE_INTERVAL_MS with:
##   fps %.1f | frame ms %.2f (mean over the window) | worst ms %.2f
##   zoom %.3f  mode gameplay|overview | deadzone W x H
##   draw calls (RENDER_TOTAL_DRAW_CALLS_IN_FRAME), objects, nodes (OBJECT_NODE_COUNT)
## Visible by default; F3 (raw KEY_F3 in `_unhandled_input`) toggles it.
##
## Owner: world builder.

const WorldCamera := preload("res://game/world/world_camera.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

const UPDATE_INTERVAL_MS := 200.0
## dev/RenderingDiagnostics.ts: the panel sits 10 px from the top-right corner.
const PANEL_MARGIN := 10.0

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
	anchor.theme = UiTokens.theme()
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
	_panel.theme_type_variation = &"DebugPanel"
	anchor.add_child(_panel)

	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.theme_type_variation = &"DebugLabel"
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
