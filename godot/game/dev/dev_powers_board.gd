extends "res://game/ui/screens/game_window.gd"
## The dev powers board (docs/godot/CONVENTIONS.md "The powers board"): **F10** in any world opens a
## window that lists every power the slime can have and switches each on or off for the session:
## the three shapes, the moves (the Roll, its Charged Roll upgrade, Swallow, the Goo Trail), the
## Ability Box abilities the game has (AbilityBox.socket_ids that AbilityDefinitions knows), the
## skins (SkinState.order) and the Gulp's level (ThrowMode's dev level).
##
## - **On** lends the power for the session (RunState.learn_session_ability, SkinState.lend): no save
##   carries it.
## - **Off** takes it away for the session (RunState.switch_off_ability / switch_off_skin): a lent one
##   is given back; one the run has for good is only set aside, and every save still keeps it.
##   What the board switched off stays off through world changes (the playground, `shapes` and a
##   dungeon's F6 powers lend again on every world build: `_reapply_off` takes them back), until it
##   is switched on again, a save is loaded or the game goes back to the title.
##
## A game window like the others (surface "dev-powers": the `modal` pause, Escape closes; F10 closes
## too): the arrows or WASD move, Space or Enter switch the focused power, the mouse works as well.
## It opens only while nothing else pauses the game.
##
## Dev only: main.gd adds it when this file exists, and the production web export leaves `game/dev/`
## out (godot/export_presets.cfg "Web"), so the released game has no board; "Web (dev)" keeps it.
##
## Owner: dev tools.

const Services := preload("res://game/shared/services.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")
const AbilityBox := preload("res://game/player/abilities/ability_box.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const SkinState := preload("res://game/player/skins/skin_state.gd")
const ThrowMode := preload("res://game/throw/throw_mode.gd")
const WindowStyle := preload("res://game/ui/screens/window_style.gd")

## Dev key (checked free on 2026-11-21: F1 throw feel, F2 control scheme, F3 FPS, F4 pen, F5 energy,
## F6 Gulp level, F7/F8 sound audition, F9 juice panel; Shift+F10 is the chest's menu key).
const BOARD_KEY := KEY_F10
const SURFACE_ID := &"dev-powers"
const KIND_ABILITY := "ability"
const KIND_SKIN := "skin"
const GOO_TRAIL_TITLE := "Goo Trail"
## The moves: abilities outside the Ability Box (the jump is hidden: no key is bound to it).
const MOVES: Array[StringName] = [AbilityDefinitions.DODGE, AbilityDefinitions.ROLL_CHARGE,
	AbilityDefinitions.SWALLOW, AbilityDefinitions.GOO_TRAIL]

const TITLE_TEXT := "Dev powers"
const HINT_TEXT := "F10 or Esc closes  ·  arrows or WASD move  ·  Space or Enter switches"
const NOTE_TEXT := "On lends a power for this session; it is never saved. Off sets it aside for this session; a power the run really has stays in its saves."
const STATE_ON := "ON"
const STATE_LENT := "ON (lent)"
const STATE_OFF := "off"
const STATE_OFF_KEPT := "off (saved)"
const ROW_TEXT := "%s:  %s"
const ALL_ON_TEXT := "All on"
const ALL_OFF_TEXT := "All off"
const CLOSE_TEXT := "Close (F10)"
const GULP_RUN_TEXT := "Run's"
const GULP_HEADER_TEXT := "Gulp level (the run has %d)"
const ON_VARIATION := &"PrimaryButton"
const OFF_VARIATION := &"MutedButton"
## A switch that is on reads in the accent colour, one that is off in the muted one.
const ON_COLOR := UiTokens.ACCENT
const OFF_COLOR := UiTokens.TEXT_TERTIARY
const FONT_COLORS: Array[StringName] = [&"font_color", &"font_hover_color", &"font_focus_color",
	&"font_pressed_color", &"font_hover_pressed_color"]

const COLUMNS := 3
const MARGIN := 24.0
const COLUMN_GAP := 16.0
const TOP := 78.0
const ROW_HEIGHT := 38.0
const ROW_GAP := 6.0
const HEADER_HEIGHT := 26.0
const SECTION_GAP := 14.0
const BOTTOM_GAP := 12.0
const NOTE_HEIGHT := 44.0
const ROW_FONT := 16
const CORNER_RADIUS := 6

var title_label: Label
var hint_label: Label
var note_label: Label
var all_on_button: Button
var all_off_button: Button
var close_button: Button
## One per power: {"kind": KIND_*, "id": String, "title": String, "button": Button}.
var rows: Array[Dictionary] = []
## The Gulp level's buttons (hidden outside the throw combat): index 0 gives the run's level back,
## 1..3 set that dev level.
var gulp_buttons: Array[Button] = []
var gulp_header: Label

## What the board switched off this session ("<kind>:<id>" -> true), taken back again after every
## world build.
var _off: Dictionary = {}
## Where each control goes: {"control": Control, "column": int, "y": float, "height": float,
## "part": int, "parts": int} (a row of `parts` controls side by side shares one line).
var _placed: Array[Dictionary] = []
var _cursor: Array[float] = []
var _bottom_y: float = 0.0


func _init() -> void:
	super()
	name = "DevPowersBoard"
	surface_id = SURFACE_ID
	max_size = Vector2(880.0, 640.0)


func _ready() -> void:
	super()
	var world := Services.world()
	if world != null and not world.world_registered.is_connected(_on_world_registered):
		world.world_registered.connect(_on_world_registered)
	var run := Services.run()
	if run != null and not run.loaded.is_connected(_on_run_loaded):
		run.loaded.connect(_on_run_loaded)


func _exit_tree() -> void:
	var world := Services.world()
	if world != null and world.world_registered.is_connected(_on_world_registered):
		world.world_registered.disconnect(_on_world_registered)
	var run := Services.run()
	if run != null and run.loaded.is_connected(_on_run_loaded):
		run.loaded.disconnect(_on_run_loaded)


## F10 opens the board (only while nothing else pauses the game) and closes it.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != BOARD_KEY or key.shift_pressed:
		return
	if is_open():
		close()
	elif _can_open():
		open()
	else:
		return
	get_viewport().set_input_as_handled()


## True when power `id` of `kind` (KIND_ABILITY, KIND_SKIN) is on now.
func is_on(kind: String, id: String) -> bool:
	var run := Services.run()
	if run == null:
		return false
	return run.has_skin(id) if kind == KIND_SKIN else run.has_learned_ability(id)


## Switches power `id` of `kind` on or off for the session (see the header) and shows it.
func set_power(kind: String, id: String, on: bool) -> void:
	_set_power(kind, id, on)
	_after_change()


## Every power on, or every power off.
func set_all(on: bool) -> void:
	for row: Dictionary in rows:
		_set_power(str(row["kind"]), str(row["id"]), on)
	_after_change()


## The Gulp's level for the session: 1..3, or 0 for the run's own.
func set_gulp_level(level: int) -> void:
	ThrowMode.set_dev_level(level)
	refresh()


func refresh() -> void:
	if content == null:
		return
	var run := Services.run()
	for row: Dictionary in rows:
		var kind := str(row["kind"])
		var id := str(row["id"])
		var on := is_on(kind, id)
		var state := STATE_OFF
		if run != null:
			var lent: Array[String] = run.session_skin_ids if kind == KIND_SKIN else run.session_ability_ids
			var kept: Array[String] = run.session_off_skin_ids if kind == KIND_SKIN else run.session_off_ability_ids
			if on:
				state = STATE_LENT if lent.has(id) else STATE_ON
			elif kept.has(id):
				state = STATE_OFF_KEPT
		var button := row["button"] as Button
		button.text = ROW_TEXT % [str(row["title"]), state]
		_mark(button, on)
	var chosen := ThrowMode.gulp_level() if ThrowMode.has_dev_level() else 0
	for index in gulp_buttons.size():
		_mark(gulp_buttons[index], index == chosen)
	# The run's own level (what the first button gives back), read with the dev level set aside.
	ThrowMode.set_dev_level(0)
	gulp_header.text = GULP_HEADER_TEXT % ThrowMode.gulp_level()
	ThrowMode.set_dev_level(chosen)


func _build() -> void:
	_cursor.resize(COLUMNS)
	_cursor.fill(TOP)
	title_label = _label("Title", &"PanelTitle", 24)
	hint_label = _label("Hint", &"MutedLabel", 14)
	hint_label.text = HINT_TEXT
	title_label.text = TITLE_TEXT
	var bold := WindowStyle.bold_font(self)
	if bold != null:
		title_label.add_theme_font_override(&"font", bold)
	# Column 1: the shapes, then the moves.
	_header(0, "Shapes")
	for id: StringName in ShapeDefs.IDS:
		_row(0, KIND_ABILITY, String(id), ShapeDefs.title(id))
	_cursor[0] += SECTION_GAP
	_header(0, "Moves")
	for id: StringName in MOVES:
		_row(0, KIND_ABILITY, String(id), _move_title(id))
	# Column 2: the Ability Box.
	_header(1, "Ability Box")
	for id: StringName in AbilityBox.socket_ids():
		if AbilityDefinitions.has(id):
			_row(1, KIND_ABILITY, String(id), AbilityDefinitions.title(id))
	# Column 3: the skins, then the Gulp's level (throw combat only).
	_header(2, "Skins")
	for id: StringName in SkinState.order():
		_row(2, KIND_SKIN, String(id), SkinState.display_name(id))
	_cursor[2] += SECTION_GAP
	gulp_header = _header(2, "Gulp level")
	var parts := ThrowMode.MAX_LEVEL + 1
	for level in parts:
		var text := GULP_RUN_TEXT if level == 0 else str(level)
		var button := _button("Gulp%d" % level, text, OFF_VARIATION, ROW_FONT, set_gulp_level.bind(level))
		WindowStyle.round_corners(button, CORNER_RADIUS)
		button.clip_text = true
		gulp_buttons.append(button)
		_placed.append({"control": button, "column": 2, "y": _cursor[2], "height": ROW_HEIGHT,
			"part": level, "parts": parts})
	_cursor[2] += ROW_HEIGHT + ROW_GAP
	_bottom_y = maxf(_cursor[0], maxf(_cursor[1], _cursor[2])) + BOTTOM_GAP
	all_on_button = _button("AllOn", ALL_ON_TEXT, ON_VARIATION, ROW_FONT, set_all.bind(true))
	all_off_button = _button("AllOff", ALL_OFF_TEXT, OFF_VARIATION, ROW_FONT, set_all.bind(false))
	close_button = _button("Close", CLOSE_TEXT, OFF_VARIATION, ROW_FONT, close)
	for button: Button in [all_on_button, all_off_button, close_button]:
		WindowStyle.round_corners(button, CORNER_RADIUS)
	note_label = _label("Note", &"MutedLabel", 14)
	note_label.text = NOTE_TEXT
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_height = _bottom_y + ROW_HEIGHT + BOTTOM_GAP + NOTE_HEIGHT + MARGIN
	max_size.y = content_height


func _layout(width: float) -> void:
	var column_width := (width - MARGIN * 2.0 - COLUMN_GAP * (COLUMNS - 1)) / COLUMNS
	_place(title_label, _rect(MARGIN, 16.0, width - MARGIN, 48.0))
	_place(hint_label, _rect(MARGIN, 48.0, width - MARGIN, 68.0))
	for entry: Dictionary in _placed:
		var left := MARGIN + (column_width + COLUMN_GAP) * int(entry["column"])
		var parts := int(entry.get("parts", 1))
		var part_width := (column_width - ROW_GAP * (parts - 1)) / parts
		left += (part_width + ROW_GAP) * int(entry.get("part", 0))
		var top := float(entry["y"])
		_place(entry["control"] as Control, _rect(left, top, left + part_width, top + float(entry["height"])))
	var buttons: Array[Button] = [all_on_button, all_off_button, close_button]
	for index in buttons.size():
		var left := MARGIN + (column_width + COLUMN_GAP) * index
		_place(buttons[index], _rect(left, _bottom_y, left + column_width, _bottom_y + ROW_HEIGHT))
	var note_top := _bottom_y + ROW_HEIGHT + BOTTOM_GAP
	_place(note_label, _rect(MARGIN, note_top, width - MARGIN, note_top + NOTE_HEIGHT))


## Shows `button` as on or off: its variation and its text colour.
static func _mark(button: Button, on: bool) -> void:
	button.theme_type_variation = ON_VARIATION if on else OFF_VARIATION
	for color_name: StringName in FONT_COLORS:
		button.add_theme_color_override(color_name, ON_COLOR if on else OFF_COLOR)


## A section's name at the column's cursor.
func _header(column: int, text: String) -> Label:
	var label := _label("Header%s" % text.replace(" ", ""), &"AccentLabel", 15)
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placed.append({"control": label, "column": column, "y": _cursor[column], "height": HEADER_HEIGHT})
	_cursor[column] += HEADER_HEIGHT + ROW_GAP * 0.5
	return label


## A power's switch at the column's cursor.
func _row(column: int, kind: String, id: String, title: String) -> void:
	var button := _button("Power_%s" % id, title, OFF_VARIATION, ROW_FONT, _toggle.bind(rows.size()))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	WindowStyle.round_corners(button, CORNER_RADIUS)
	rows.append({"kind": kind, "id": id, "title": title, "button": button})
	_placed.append({"control": button, "column": column, "y": _cursor[column], "height": ROW_HEIGHT})
	_cursor[column] += ROW_HEIGHT + ROW_GAP


## A move's name: the ability table's, an upgrade's, or the Goo Trail's (a passive with no entry).
static func _move_title(id: StringName) -> String:
	if AbilityDefinitions.is_upgrade(id):
		return str(AbilityDefinitions.upgrade(id).get("title", String(id)))
	if id == AbilityDefinitions.GOO_TRAIL:
		return GOO_TRAIL_TITLE
	return AbilityDefinitions.title(id)


func _toggle(index: int) -> void:
	var row := rows[index]
	var kind := str(row["kind"])
	var id := str(row["id"])
	set_power(kind, id, not is_on(kind, id))


func _set_power(kind: String, id: String, on: bool) -> void:
	var run := Services.run()
	if run == null:
		return
	var key := "%s:%s" % [kind, id]
	if on:
		_off.erase(key)
		if kind == KIND_SKIN:
			SkinState.lend(StringName(id))
		else:
			run.learn_session_ability(id)
	else:
		_off[key] = true
		if kind == KIND_SKIN:
			run.switch_off_skin(id)
		else:
			run.switch_off_ability(id)


## The slime's shape controller follows the learned shapes, and the board shows the new state.
func _after_change() -> void:
	var world := Services.world()
	var slime: Variant = world.player if world != null else null
	if slime != null and is_instance_valid(slime) and (slime as Node).has_method(&"get_shapes"):
		var shapes: Variant = (slime as Node).call(&"get_shapes")
		if shapes != null and is_instance_valid(shapes) and (shapes as Object).has_method(&"sync_learned"):
			(shapes as Object).call(&"sync_learned")
	refresh()


## Nothing else pauses the game (a window, the pause menu, a ceremony) and a slime is in the world.
func _can_open() -> bool:
	if not is_inside_tree() or get_tree().paused:
		return false
	var world := Services.world()
	var slime: Variant = world.player if world != null else null
	return slime != null and is_instance_valid(slime)


## A world was built: its lending (the playground's kit, `shapes`, a dungeon's F6 powers) comes
## after this signal, so what the board switched off is taken back once the build is done.
func _on_world_registered(_payload: Dictionary) -> void:
	if not _off.is_empty():
		_reapply_off.call_deferred()


func _reapply_off() -> void:
	var run := Services.run()
	if run == null:
		return
	for key: String in _off:
		var parts := key.split(":", true, 1)
		if parts[0] == KIND_SKIN:
			run.switch_off_skin(parts[1])
		else:
			run.switch_off_ability(parts[1])
	_after_change()


## A loaded save is another run: the board's choices do not follow it.
func _on_run_loaded(_payload: Dictionary) -> void:
	_off.clear()
