@tool
extends VBoxContainer
## The live strike preview above a StrikeAnimation's fields in the Inspector (BODY_SHAPES.md "Editing the strike
## animations"; added by strike_inspector.gd). The slime in side, down and up, large, each drawn as the game draws a
## strike: a Visual with the strike sheet's body frame (ShapeStrikes: the sheet, its row and origin; the direction's
## mirror) and the three StrikeRig nodes under it, as in game/characters/player_slime.tscn (game/shapes/strike_rig.gd:
## the weapon, the neck, the views, the swoosh and the overlay: the hit area from the hit centre, the reach ring,
## the hit centre's cross and the ring's handle, the body's edge, the weapon's tip and the socket), at the time
## bar's time on the step's own timing (game-constants.json, read by StrikeLibrary). Under each view, the reach past
## the body and the numbers behind it. The play button loops the strike in real time; the time bar shows the windup,
## active and recovery windows and every key of each direction, and a click or a drag on it moves the time.
##
## In a view, dragging the cross moves the direction's `hit_center` and dragging the handle on the ring sets its
## `hit_reach`; the picture follows while dragging, and the release is one undoable edit (the editor's undo history,
## so Ctrl+Z undoes it and Ctrl+S saves it). Nothing else here changes the file, and the player scene is not touched.
## The file is checked every frame: after any change the views are redrawn and rendered for REFRESH_FRAMES frames
## (the editor idles between edits, so one frame could show the picture before the rig had redrawn), and a paused,
## unchanged preview lets the editor idle.

const StrikeLibrary := preload("res://game/shapes/strike_library.gd")
const ShapeStrikes := preload("res://game/shapes/shape_strikes.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const RigScript := preload("res://game/shapes/strike_rig.gd")
const AnimationType := preload("res://game/shapes/strike_animation.gd")

const DIRECTIONS: Array[String] = ["side", "down", "up"]
const DIRECTION_TITLES := {"side": "Side (a left strike is its mirror)", "down": "Down (toward the viewer)",
	"up": "Up (away from the viewer)"}
## The slime's body on screen (px) at least; its frame is about BODY_GAME_PX game px tall.
const BODY_SCREEN_PX := 130.0
const BODY_GAME_PX := 48.0
## The game px a view shows across, round the slime's centre, when the Inspector is wide enough.
const VIEW_GAME_PX := 260.0
## Every view's height for its width (the same for all three), and where the slime's centre sits in it (shares of
## its width and height: the down and up weapons reach far below and above the body, so the slime sits a little away
## from them), and the width (screen px) a view needs before two or three sit side by side. All three views use one
## zoom, so the slime and its reach have the same size on screen in each.
const VIEW_HEIGHT_SHARE := 1.0
const VIEW_ANCHOR := {"side": Vector2(0.5, 0.5), "down": Vector2(0.5, 0.38), "up": Vector2(0.5, 0.62)}
const MIN_VIEW_WIDTH_PX := 560.0
## The player scene's Visual scale (its sheets' game px per cell px).
const VISUAL_SCALE := 0.28125
const COLUMNS := 8
## The pause at the strike's end before the loop starts again (real ms).
const LOOP_REST_MS := 300.0
## Frames the views are redrawn and rendered after a change.
const REFRESH_FRAMES := 6
## How near (screen px, before the editor scale) the pointer must be to grab a handle; the values' rounding (game px).
const GRAB_PX := 12.0
const SNAP_PX := 0.5
const BACKGROUND := Color(0.19, 0.24, 0.15)
const WINDUP_COLOR := Color(0.35, 0.55, 0.95, 0.6)
const ACTIVE_COLOR := Color(0.95, 0.35, 0.3, 0.75)
const RECOVERY_COLOR := Color(0.55, 0.62, 0.5, 0.55)
const KEY_COLORS := {"side": Color(1.0, 0.85, 0.35), "down": Color(0.45, 0.9, 1.0), "up": Color(0.75, 1.0, 0.45)}
const JUMP_COLOR := Color(1.0, 0.45, 0.85)
const ROW_LINE := Color(1.0, 1.0, 1.0, 0.18)
const PLAYHEAD_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const BAND_TEXT := Color(1.0, 1.0, 1.0, 0.95)
const HINT := "Drag the cross to move where the hit is measured from, the blue handle on the ring to change the reach. Ctrl+Z undoes, Ctrl+S saves."

## The strike shown (set by strike_inspector.gd before the preview enters the tree).
var strike: AnimationType

var _time_ms := 0.0
var _playing := true
## What the views were last drawn from (the time, the sizes, the timing, the file's values, the handles): unchanged
## while paused, so nothing is redrawn and the editor can idle.
var _drawn_from: Array = []
var _refresh_left := 0
var _scale := 1.0
var _views: Array[Dictionary] = []
var _grid: GridContainer
var _timeline: Control
var _play: Button
var _title: Label
var _time_label: Label
## The drag in progress: {"view": index, "what": RigScript.HOT_CENTRE / HOT_RING, "field", "start"}; {} for none.
var _drag: Dictionary = {}

## The time and the play state per strike shown, kept while the Inspector rebuilds its controls.
static var _remembered: Dictionary = {}
static var _textures: Dictionary = {}


func _ready() -> void:
	_scale = EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	size_flags_horizontal = SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", roundi(4.0 * _scale))
	var top := HBoxContainer.new()
	_play = Button.new()
	_play.custom_minimum_size = Vector2(72.0 * _scale, 0.0)
	_play.pressed.connect(_on_play)
	top.add_child(_play)
	_title = Label.new()
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_title)
	add_child(top)
	_time_label = Label.new()
	add_child(_time_label)
	_timeline = Control.new()
	_timeline.custom_minimum_size = Vector2(0.0, _timeline_height())
	_timeline.mouse_filter = Control.MOUSE_FILTER_PASS
	_timeline.tooltip_text = "Click or drag to move the time. Bands: windup, active, recovery. Ticks: the keys of each direction (pink: a jump)."
	_timeline.draw.connect(_draw_timeline)
	_timeline.gui_input.connect(_on_timeline_input)
	add_child(_timeline)
	var hint := Label.new()
	hint.text = HINT
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override(&"font_size", roundi(float(get_theme_font_size(&"font_size", &"Label")) * 0.8))
	add_child(hint)
	_grid = GridContainer.new()
	_grid.columns = 1
	_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(_grid)
	for direction: String in DIRECTIONS:
		_views.append(_make_view(direction, _views.size()))
	if strike != null and _remembered.has(strike.get_instance_id()):
		var kept: Array = _remembered[strike.get_instance_id()]
		_time_ms = float(kept[0])
		_playing = bool(kept[1])
	_update_play_text()


func _process(delta: float) -> void:
	if strike == null or not is_visible_in_tree():
		return
	var timing := StrikeLibrary.timing_of(strike)
	var total := timing.x + timing.y + timing.z
	if _playing and total > 0.0:
		_time_ms += delta * 1000.0
		if _time_ms > total + LOOP_REST_MS:
			_time_ms = 0.0
	_time_ms = clampf(_time_ms, 0.0, maxf(0.0, total + LOOP_REST_MS))
	_remembered[strike.get_instance_id()] = [_time_ms, _playing]
	var view_sizes := PackedVector2Array()
	var hot := PackedInt32Array()
	for view: Dictionary in _views:
		view_sizes.append(Vector2((view["viewport"] as SubViewport).size))
		hot.append(int((view["rig"] as Node2D).get(&"overlay_hot")))
	var now := [_time_ms, size, view_sizes, timing, _values_hash(), hot]
	if now != _drawn_from:
		_drawn_from = now
		_refresh_left = REFRESH_FRAMES
	if _refresh_left <= 0:
		return
	# Redrawn and rendered for a few frames after the change: one rendered frame may come before the rig redrew.
	_refresh_left -= 1
	var shown := minf(_time_ms, total)
	_title.text = "%s (%s %s): %.0f + %.0f + %.0f ms" % [StrikeLibrary.strike_of(strike), strike.shape, strike.step,
		timing.x, timing.y, timing.z]
	_time_label.text = "t %.0f ms of %.0f  (%s, unit %.2f)" % [shown, total, _phase_name(shown, timing),
		StrikeLibrary.unit_at(shown, timing)]
	var columns := clampi(int(floorf(size.x / MIN_VIEW_WIDTH_PX)), 1, DIRECTIONS.size())
	if _grid.columns != columns:
		_grid.columns = columns
	# One zoom for every view: the largest that fits each of them (the body at least BODY_SCREEN_PX tall).
	var zoom := INF
	for view: Dictionary in _views:
		var view_size := Vector2((view["viewport"] as SubViewport).size)
		zoom = minf(zoom, maxf(BODY_SCREEN_PX / BODY_GAME_PX, minf(view_size.x, view_size.y) / VIEW_GAME_PX))
	for view: Dictionary in _views:
		_update_view(view, shown, timing, zoom)
		var viewport: SubViewport = view["viewport"]
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if _refresh_left == 0 \
			else SubViewport.UPDATE_ALWAYS
	_timeline.queue_redraw()


## A hash of every value of the file the views draw: it changes as soon as a field is edited.
func _values_hash() -> int:
	var values: Array = [strike.shape, strike.step]
	for direction: String in DIRECTIONS:
		var spec := StrikeLibrary.direction_of(strike, direction)
		if spec == null:
			values.append(null)
			continue
		values.append_array([spec.hit_reach, spec.hit_center, spec.arm_px, spec.socket_nudge, spec.flip_h,
			spec.spear_inside, spec.spear_fade, spec.spear_shaft, spec.keys.size()])
		for key: Resource in spec.keys:
			if key == null:
				values.append(null)
				continue
			values.append_array([key.get(&"phase"), key.get(&"share"), key.get(&"frame"), key.get(&"angle"),
				key.get(&"length"), key.get(&"layer"), key.get(&"view"), key.get(&"view_frame"), key.get(&"head_angle"),
				key.get(&"jump")])
	return values.hash()


## One view: a SubViewport with the stage (the slime's centre at its middle), the Visual and the rig's three nodes,
## the reach past the body (large) and the numbers behind it under it.
func _make_view(direction: String, index: int) -> Dictionary:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = str(DIRECTION_TITLES[direction])
	box.add_child(name_label)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = SIZE_EXPAND_FILL
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	container.custom_minimum_size = Vector2(0.0, BODY_SCREEN_PX * 2.4)
	container.tooltip_text = HINT
	container.gui_input.connect(_on_view_input.bind(index))
	container.mouse_exited.connect(_on_view_exited.bind(index))
	box.add_child(container)
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(background)
	var stage := Node2D.new()
	viewport.add_child(stage)
	var visual := Sprite2D.new()
	visual.name = "Visual"
	visual.centered = false
	visual.scale = Vector2(VISUAL_SCALE, VISUAL_SCALE)
	visual.hframes = COLUMNS
	visual.vframes = COLUMNS
	stage.add_child(visual)
	var rig_scale := Vector2.ONE / VISUAL_SCALE
	for node_name: String in [RigScript.FRONT_NODE, RigScript.NECK_NODE]:
		var node := Node2D.new()
		node.name = node_name
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		node.scale = rig_scale
		if node_name == RigScript.FRONT_NODE:
			node.z_index = 1
		visual.add_child(node)
	var rig := Node2D.new()
	rig.name = RigScript.NODE_NAME
	rig.show_behind_parent = true
	rig.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rig.scale = rig_scale
	rig.set_script(RigScript)
	visual.add_child(rig)
	visual.move_child(rig, 0)
	rig.set(&"overlay_text", false)
	var font_size := float(get_theme_font_size(&"font_size", &"Label"))
	var past := Label.new()
	past.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	past.add_theme_font_size_override(&"font_size", roundi(font_size * 1.15))
	box.add_child(past)
	var readout := Label.new()
	readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readout.add_theme_font_size_override(&"font_size", roundi(font_size * 0.85))
	box.add_child(readout)
	_grid.add_child(box)
	return {"direction": direction, "container": container, "viewport": viewport, "background": background,
		"stage": stage, "visual": visual, "rig": rig, "past": past, "readout": readout}


## The view at `shown` ms of a step with `timing`: the Visual's body frame and mirror from the strike's state, the rig
## on the same strike and time, the stage at the view's anchor and at `zoom` (the same in every view), the readouts.
func _update_view(view: Dictionary, shown: float, timing: Vector3, zoom: float) -> void:
	var direction: String = view["direction"]
	var visual: Sprite2D = view["visual"]
	var rig: Node2D = view["rig"]
	var past: Label = view["past"]
	var readout: Label = view["readout"]
	var container: SubViewportContainer = view["container"]
	var viewport: SubViewport = view["viewport"]
	var strike_id := StrikeLibrary.strike_of(strike)
	var path := ShapeStrikes.texture_path(strike_id)
	var row := ShapeStrikes.row(strike_id, direction)
	if strike_id.is_empty() or path.is_empty() or row < 0 or StrikeLibrary.direction_of(strike, direction) == null:
		visual.visible = false
		rig.set(&"clock_ms", -1.0)
		past.text = ""
		readout.text = "Nothing to show: check `shape`, `step` and the %s direction." % direction
		return
	visual.visible = true
	visual.texture = _texture(path)
	visual.offset = -ShapeStrikes.origin()
	var state := StrikeLibrary.state_at(strike, direction, shown, timing)
	visual.frame = clampi(row * COLUMNS + int(state["frame"]) - 1, 0, COLUMNS * COLUMNS - 1)
	visual.flip_h = bool(state["flip_h"])
	rig.set(&"animation", strike)
	rig.set(&"direction", direction)
	rig.set(&"timing", timing)
	rig.set(&"clock_ms", shown)
	# Redrawn even when nothing it reads changed (the refresh frames).
	rig.call(&"_changed")
	var height := maxf(BODY_SCREEN_PX * 2.4, container.size.x * VIEW_HEIGHT_SHARE)
	if absf(container.custom_minimum_size.y - height) > 1.0:
		container.custom_minimum_size = Vector2(0.0, height)
	var view_size := Vector2(viewport.size)
	(view["background"] as ColorRect).size = view_size
	var stage: Node2D = view["stage"]
	stage.position = (view_size * (VIEW_ANCHOR[direction] as Vector2)).round()
	stage.scale = Vector2(zoom, zoom)
	var numbers: Dictionary = rig.call(&"overlay_numbers")
	if numbers.is_empty():
		past.text = ""
		readout.text = ""
		return
	var edge := float(numbers["edge"])
	var tip := float(numbers["tip"])
	var far := float(numbers["far"])
	var centre: Vector2 = StrikeLibrary.hit_center(strike, direction)
	past.text = "Past the body:  weapon tip %s   hit edge %.1f px" % ["%.1f px," % (tip - edge) if tip < INF else "none,",
		far - edge]
	readout.text = "Hit centre (%.1f, %.1f) px from the slime's centre; hit reach %.1f. Along the aim from the centre: weapon tip %s, hit edge %.1f, body edge %.1f." % [
		centre.x, centre.y, StrikeLibrary.hit_reach(strike, direction), "%.1f" % tip if tip < INF else "none", far, edge]


# --- the handles --------------------------------------------------------------------------------------

## The pointer over view `index`: a press on the cross or the ring's handle starts a drag (the strike pauses), a move
## while dragging sets the value (live), the release makes it one undoable edit; without a drag it marks the handle
## under the pointer.
func _on_view_input(event: InputEvent, index: int) -> void:
	if strike == null or index < 0 or index >= _views.size():
		return
	var view: Dictionary = _views[index]
	var rig: Node2D = view["rig"]
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var button := event as InputEventMouseButton
		if button.pressed:
			var what := _handle_at(view, button.position)
			if what == RigScript.HOT_NONE:
				return
			var spec := StrikeLibrary.direction_of(strike, str(view["direction"]))
			var field := &"hit_center" if what == RigScript.HOT_CENTRE else &"hit_reach"
			_drag = {"view": index, "what": what, "field": field, "start": spec.get(field)}
			_playing = false
			_update_play_text()
			rig.set(&"overlay_hot", what)
			(view["container"] as Control).accept_event()
		elif not _drag.is_empty():
			_finish_drag()
			(view["container"] as Control).accept_event()
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if not _drag.is_empty() and int(_drag["view"]) == index:
			_drag_to(view, motion.position)
			(view["container"] as Control).accept_event()
			return
		var hot := _handle_at(view, motion.position)
		if int(rig.get(&"overlay_hot")) != hot:
			rig.set(&"overlay_hot", hot)
		(view["container"] as Control).mouse_default_cursor_shape = Control.CURSOR_MOVE if hot != RigScript.HOT_NONE \
			else Control.CURSOR_ARROW


func _on_view_exited(index: int) -> void:
	if _drag.is_empty() and index >= 0 and index < _views.size():
		((_views[index] as Dictionary)["rig"] as Node2D).set(&"overlay_hot", RigScript.HOT_NONE)


## The handle under `at` (the view's control px): HOT_CENTRE, HOT_RING or HOT_NONE.
func _handle_at(view: Dictionary, at: Vector2) -> int:
	var numbers: Dictionary = (view["rig"] as Node2D).call(&"overlay_numbers")
	if numbers.is_empty():
		return RigScript.HOT_NONE
	var grab := GRAB_PX * _scale
	var centre := _to_screen(view, numbers["centre"])
	var handle := _to_screen(view, numbers["handle"])
	var to_centre := at.distance_to(centre)
	var to_handle := at.distance_to(handle)
	if to_handle <= grab and to_handle <= to_centre:
		return RigScript.HOT_RING
	if to_centre <= grab:
		return RigScript.HOT_CENTRE
	return RigScript.HOT_NONE


## A point of the rig's px (game px from the slime's centre) in the view's control px, and back.
func _to_screen(view: Dictionary, point: Vector2) -> Vector2:
	var stage: Node2D = view["stage"]
	return stage.position + point * stage.scale.x


func _to_game(view: Dictionary, at: Vector2) -> Vector2:
	var stage: Node2D = view["stage"]
	return (at - stage.position) / maxf(0.001, stage.scale.x)


## The dragged value for the pointer at `at`: the hit centre under it (mirrored back while the view shows the
## strip flipped), or the reach that puts the ring's far edge under it along the aim (the Hammer's: less its circle).
func _drag_to(view: Dictionary, at: Vector2) -> void:
	var direction: String = view["direction"]
	var spec := StrikeLibrary.direction_of(strike, direction)
	var numbers: Dictionary = (view["rig"] as Node2D).call(&"overlay_numbers")
	if spec == null or numbers.is_empty():
		return
	var point := _to_game(view, at)
	var flipped := (view["visual"] as Sprite2D).flip_h
	if int(_drag["what"]) == RigScript.HOT_CENTRE:
		var centre := point.snapped(Vector2(SNAP_PX, SNAP_PX))
		spec.hit_center = Vector2(-centre.x, centre.y) if flipped else centre
	else:
		var aim: Vector2 = numbers["aim"]
		var ring := (point - (numbers["centre"] as Vector2)).dot(aim)
		var data := StrikeLibrary.step_data(strike)
		if ShapeDefs.area_kind(data) == ShapeDefs.AREA_CIRCLE:
			ring -= ShapeDefs.num(data, "radius")
		spec.hit_reach = maxf(1.0, snappedf(ring, SNAP_PX))


## Ends the drag: the value from its start to now as one action in the editor's undo history (Ctrl+Z undoes it;
## the strike file is marked changed, so Ctrl+S saves it).
func _finish_drag() -> void:
	var view: Dictionary = _views[int(_drag["view"])]
	var direction: String = view["direction"]
	var spec := StrikeLibrary.direction_of(strike, direction)
	var field: StringName = _drag["field"]
	var start: Variant = _drag["start"]
	(view["rig"] as Node2D).set(&"overlay_hot", RigScript.HOT_NONE)
	_drag = {}
	if spec == null:
		return
	var final: Variant = spec.get(field)
	if final == start or not Engine.is_editor_hint():
		return
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("%s: %s %s" % [StrikeLibrary.strike_of(strike), direction,
		"move the hit centre" if field == &"hit_center" else "set the hit reach"])
	undo.add_do_property(spec, field, final)
	undo.add_undo_property(spec, field, start)
	undo.commit_action()


# --- the time bar ---------------------------------------------------------------------------------------

func _draw_timeline() -> void:
	if strike == null:
		return
	var timing := StrikeLibrary.timing_of(strike)
	var total := timing.x + timing.y + timing.z
	if total <= 0.0:
		return
	var font := _timeline.get_theme_font(&"font", &"Label")
	var font_size := roundi(float(_timeline.get_theme_font_size(&"font_size", &"Label")) * 0.85)
	var band := 20.0 * _scale
	var row_height := 13.0 * _scale
	var left := _gutter()
	var span := _span()
	var ends := [0.0, timing.x, timing.x + timing.y, total]
	var colors := [WINDUP_COLOR, ACTIVE_COLOR, RECOVERY_COLOR]
	var names := ["windup", "active", "recovery"]
	for index in 3:
		var from := left + span * float(ends[index]) / total
		var to := left + span * float(ends[index + 1]) / total
		_timeline.draw_rect(Rect2(from, 0.0, maxf(1.0, to - from), band), colors[index])
		var text := "%s %.0f" % [names[index], float(ends[index + 1]) - float(ends[index])]
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x < to - from - 4.0:
			_timeline.draw_string(font, Vector2(from + 3.0 * _scale, band * 0.72), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size, BAND_TEXT)
	for index in DIRECTIONS.size():
		var direction: String = DIRECTIONS[index]
		var top := band + 4.0 * _scale + float(index) * row_height
		var middle := top + row_height * 0.5
		_timeline.draw_string(font, Vector2(2.0 * _scale, top + row_height * 0.85), direction, HORIZONTAL_ALIGNMENT_LEFT,
			-1, font_size, KEY_COLORS[direction])
		_timeline.draw_line(Vector2(left, middle), Vector2(left + span, middle), ROW_LINE, 1.0)
		var spec := StrikeLibrary.direction_of(strike, direction)
		if spec == null:
			continue
		for key: Resource in spec.keys:
			if key == null:
				continue
			var x := left + span * _ms_of(StrikeLibrary.key_unit(key), timing) / total
			_timeline.draw_line(Vector2(x, top + 1.0), Vector2(x, top + row_height - 1.0),
				JUMP_COLOR if bool(key.get("jump")) else KEY_COLORS[direction], 2.0 * _scale)
	var at := left + span * minf(_time_ms, total) / total
	_timeline.draw_line(Vector2(at, 0.0), Vector2(at, _timeline.size.y), PLAYHEAD_COLOR, 2.0 * _scale)


func _on_timeline_input(event: InputEvent) -> void:
	var press := event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
		and (event as InputEventMouseButton).pressed
	var drag := event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if strike == null or not (press or drag):
		return
	var timing := StrikeLibrary.timing_of(strike)
	var total := timing.x + timing.y + timing.z
	var x := (event as InputEventMouse).position.x
	_time_ms = clampf((x - _gutter()) / maxf(1.0, _span()), 0.0, 1.0) * total
	_playing = false
	_update_play_text()
	_timeline.accept_event()


func _on_play() -> void:
	_playing = not _playing
	if _playing and strike != null:
		var timing := StrikeLibrary.timing_of(strike)
		if _time_ms >= timing.x + timing.y + timing.z:
			_time_ms = 0.0
	_update_play_text()


func _update_play_text() -> void:
	if _play != null:
		_play.text = "Pause" if _playing else "Play"


func _timeline_height() -> float:
	return (20.0 + 4.0 + 13.0 * float(DIRECTIONS.size()) + 4.0) * _scale


func _gutter() -> float:
	return 44.0 * _scale


func _span() -> float:
	return maxf(1.0, _timeline.size.x - _gutter() - 4.0 * _scale)


## The ms of a 0-3 unit on `timing` (the inverse of StrikeLibrary.unit_at).
static func _ms_of(unit: float, timing: Vector3) -> float:
	if unit <= 1.0:
		return unit * timing.x
	if unit <= 2.0:
		return timing.x + (unit - 1.0) * timing.y
	return timing.x + timing.y + (unit - 2.0) * timing.z


static func _phase_name(ms: float, timing: Vector3) -> String:
	if ms < timing.x:
		return "windup"
	if ms < timing.x + timing.y:
		return "active"
	return "recovery"


static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D
	return _textures[path]
