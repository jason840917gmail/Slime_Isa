extends CanvasLayer
## The juice dev panel (combat-feel plan section 9 item 6 "Feel switches"; docs/godot/BODY_SHAPES.md
## "Juice"): a tiny label in the top-left corner that lists the juice layers (HitJuice.LAYERS) with
## their keys and whether each is on, so the owner can see each effect and compare a hit with and
## without it. HitJuice.PANEL_KEY (F9) shows or hides it; while it shows, HitJuice.LAYER_KEYS (1-9, 0)
## PLAY each layer once (game/feel/juice_demo.gd: on the nearest dummy or enemy, else the slime; the
## current shape's finisher value, then an exaggerated replay "shown 4x") and the panel names what
## just played; Shift + the same key switches the layer off and on (those key presses go no further).
## Hidden with a layer still off, it keeps one line ("Juice: 2 off (F9)") so a switched-off layer is
## never forgotten. Rework mode only: with the mode off it hides and reads no key. GameFeel makes it
## the first time the mode is on.
##
## PROCESS_MODE_ALWAYS (it works through a hit-stop, and runs the demo's real-time schedule). Layer
## 90: over the HUD, under nothing that matters for a dev label.
##
## Owner: juice.

const HitJuice := preload("res://game/feel/hit_juice.gd")
const ReworkMode := preload("res://game/shapes/rework_mode.gd")
const JuiceDemo := preload("res://game/feel/juice_demo.gd")

const LAYER := 90
const MARGIN := Vector2(8.0, 8.0)
const FONT_SIZE := 11
const OUTLINE_SIZE := 3
const TEXT_COLOR := Color("#f6f2d8")
const OFF_COLOR := Color("#ff8f8f")
const OUTLINE_COLOR := Color("#0b1020")

var _label: Label
var _shown: bool = false
var _demo: JuiceDemo = JuiceDemo.new()
## The demo's `revision` the label last showed.
var _demo_revision: int = -1


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.name = "JuiceLayers"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = MARGIN
	_label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_label.add_theme_color_override(&"font_color", TEXT_COLOR)
	_label.add_theme_color_override(&"font_outline_color", OUTLINE_COLOR)
	_label.add_theme_constant_override(&"outline_size", OUTLINE_SIZE)
	add_child(_label)
	_refresh()


## True while the panel shows.
func is_shown() -> bool:
	return _shown and ReworkMode.is_on()


## Runs the demo's schedule (real time, also during a freeze) and redraws when a layer's state, the
## panel's visibility or the demo's lines changed.
func _process(_delta: float) -> void:
	if not ReworkMode.is_on():
		_demo.cancel()
	else:
		_demo.step()
	var visible_now := ReworkMode.is_on() and (_shown or _off_count() > 0)
	if _label.visible != visible_now or _demo.revision != _demo_revision:
		_refresh()


func _input(event: InputEvent) -> void:
	if not ReworkMode.is_on():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == HitJuice.PANEL_KEY:
		_shown = not _shown
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if not _shown or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	var layer_id := HitJuice.layer_for_key(code)
	if layer_id.is_empty():
		return
	if key.shift_pressed:
		HitJuice.toggle_layer(layer_id)
	else:
		_demo.play(layer_id)
	_refresh()
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	if _label == null:
		return
	var off := _off_count()
	var panel_key := OS.get_keycode_string(HitJuice.PANEL_KEY)
	_demo_revision = _demo.revision
	if _shown:
		var lines: PackedStringArray = ["Juice (%s hides)   1-0: play once   Shift+1-0: on / off" % panel_key]
		for i in HitJuice.LAYERS.size():
			var layer_id: StringName = HitJuice.LAYERS[i]
			var key_name := OS.get_keycode_string(HitJuice.LAYER_KEYS[i]) if i < HitJuice.LAYER_KEYS.size() else "?"
			lines.append("%s %s %s" % [key_name, "on " if HitJuice.layer_on(layer_id) else "OFF", String(layer_id)])
		var played := _demo.lines()
		if not played.is_empty():
			lines.append("Played:")
			lines.append_array(played)
		_label.text = "\n".join(lines)
	else:
		_label.text = "Juice: %d off (%s)" % [off, panel_key]
	_label.add_theme_color_override(&"font_color", OFF_COLOR if off > 0 else TEXT_COLOR)
	_label.visible = ReworkMode.is_on() and (_shown or off > 0)


func _off_count() -> int:
	var count := 0
	for layer_id: StringName in HitJuice.LAYERS:
		if not HitJuice.layer_on(layer_id):
			count += 1
	return count
