extends PanelContainer
## The HUD's ability bar (Phaser `features/ui/AbilityBarSurfacePort.ts` + `ui.ability-bar`;
## abilities spec 2.6): five buttons, Jump, Dodge, Lash, Slam, Teleport (key order: Space, then
## 1-4), bottom centre, offsets (-180, -84)-(180, -12) from (0.5, 1); 64 px buttons 6 px apart
## inside an 8 px margin.
##
## Each button reads the player's `ability_status(id)` every frame. Label, first match:
## - locked → "<earnedBy>\n<name>";
## - cooling down → "<s>s\n<name>" (s = ceil(ms / 100) / 10 with one decimal: 1234 ms → "1.3s");
## - too little energy → "Need <cost>E\n<name>";
## - busy or action-locked → "Busy\n<name>";
## - else "<key label>\n<name>" ("Space\nJump", "2\nLash").
## A button is disabled unless the game is playing (no menu pause, not dead) and the ability can
## run. A click on an enabled button runs the ability through `player.activate_ability_from_ui`
## (ClickSfx plays first). The buttons never take keyboard focus.
##
## Look (styles.css .game-ui--ability-bar): the window panel with radius 10; buttons with padding
## 4, radius 6, 12 px bold special text, a special border at 65 % while enabled.
##
## Owner: abilities.

const Services := preload("res://game/shared/services.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")
const Definitions := preload("res://game/player/abilities/ability_definitions.gd")

## Phaser `ABILITIES` (AbilityBarSurfacePort.ts:8-14): bar order and short names.
const SLOTS: Array[StringName] = [&"jump", &"dodge", &"stretch-lash", &"squash-slam", &"teleport"]
const OFFSET_MIN := Vector2(-180.0, -84.0)
const OFFSET_MAX := Vector2(180.0, -12.0)
const BUTTON_WIDTH := 64.0
const BUTTON_GAP := 6.0
const MARGIN := 8.0
const FONT_SIZE := 12
const PANEL_RADIUS := 10
const BUTTON_RADIUS := 6
const BUTTON_PADDING := 4.0
const ENABLED_BORDER_ALPHA := 0.65
## `sfx.ui.click` (min interval 40 ms), played through the converter's cue player.
const CLICK_STREAM := "res://asset/audio/sfx/library/ui/click.ogg"
const CLICK_MIN_INTERVAL_MS := 40.0
const SfxPlayer := preload("res://game/runtime/sfx_player.gd")

## The player script (ability_status, activate_ability_from_ui, is_dead), or null.
var player: Node
var _buttons: Dictionary = {}
## The theme's own button styles per state (before any override), the base of every restyle.
var _button_styles: Dictionary = {}
var _signature: String = ""
var _click: AudioStreamPlayer


func _ready() -> void:
	name = "AbilityBar"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = OFFSET_MIN.x
	offset_top = OFFSET_MIN.y
	offset_right = OFFSET_MAX.x
	offset_bottom = OFFSET_MAX.y
	_style_panel()
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", int(BUTTON_GAP))
	add_child(row)
	for id in SLOTS:
		var button := _make_button(id)
		row.add_child(button)
		_buttons[id] = button
	_click = AudioStreamPlayer.new()
	_click.name = "ClickSfx"
	_click.set_script(SfxPlayer)
	_click.set(&"min_interval_ms", CLICK_MIN_INTERVAL_MS)
	_click.max_polyphony = 4
	_click.bus = &"Effects"
	_click.process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(CLICK_STREAM):
		_click.stream = load(CLICK_STREAM)
	add_child(_click)
	refresh()


func _process(_delta: float) -> void:
	refresh()


## Rebuilds the labels and the disabled states from the player (cheap; skips unchanged models).
func refresh() -> void:
	var model := snapshot()
	var signature := str(model)
	if signature == _signature:
		return
	_signature = signature
	for id in SLOTS:
		var button: Button = _buttons[id]
		var entry: Dictionary = model[id]
		button.text = str(entry["label"])
		button.disabled = bool(entry["disabled"])
		_style_button(button, not button.disabled)


## {id: {"label": String, "disabled": bool}} for the five slots (tests read it).
func snapshot() -> Dictionary:
	var live := player != null and is_instance_valid(player)
	var interactive := live and not bool(player.call(&"is_dead")) and not _menu_paused()
	var model := {}
	for id in SLOTS:
		var name_text := str(Definitions.BAR_NAMES.get(id, id))
		var status: Dictionary = player.call(&"ability_status", id) if live else {}
		model[id] = {"label": _label(id, name_text, status), "disabled": not interactive or not bool(status.get("canActivate", false))}
	return model


## Clicks a slot (the button's `pressed`; tests call it): runs the ability when it can run now.
func activate(id: StringName) -> bool:
	if player == null or not is_instance_valid(player) or bool(player.call(&"is_dead")) or _menu_paused():
		return false
	var status: Dictionary = player.call(&"ability_status", id)
	if not bool(status.get("canActivate", false)):
		return false
	var used := bool(player.call(&"activate_ability_from_ui", id))
	_signature = ""
	return used


static func _label(id: StringName, name_text: String, status: Dictionary) -> String:
	if not bool(status.get("unlocked", false)):
		return "%s\n%s" % [str(status.get("earnedBy", Definitions.entry(id).get("earned_by", ""))), name_text]
	var cooldown := float(status.get("cooldownRemainingMs", 0.0))
	if cooldown > 0.0:
		return "%.1fs\n%s" % [ceilf(cooldown / 100.0) / 10.0, name_text]
	if bool(status.get("insufficientEnergy", false)):
		return "Need %dE\n%s" % [roundi(Definitions.energy_cost(id)), name_text]
	if bool(status.get("busy", false)) or bool(status.get("actionLocked", false)):
		return "Busy\n%s" % name_text
	return "%s\n%s" % [ControlLabels.control_label(Definitions.action(id)), name_text]


## Phaser's `interactive` is "not paused": a menu or window pause, not a hit-stop.
func _menu_paused() -> bool:
	if not is_inside_tree() or not get_tree().paused:
		return false
	var world := Services.world()
	return world == null or world.has_pause_reason(Services.WorldServiceType.PAUSE_MODAL) \
		or not world.has_pause_reason(Services.WorldServiceType.PAUSE_HIT_STOP)


func _make_button(id: StringName) -> Button:
	var button := Button.new()
	button.name = str(Definitions.BAR_NAMES.get(id, id))
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, 0.0)
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = str(Definitions.BAR_NAMES.get(id, id))
	button.theme_type_variation = &"BoldButton"
	button.add_theme_font_size_override(&"font_size", FONT_SIZE)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.clip_text = false
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		button.add_theme_color_override(color_name, UiTokens.SPECIAL)
	button.add_theme_color_override(&"font_disabled_color", Color(UiTokens.SPECIAL, 0.45))
	button.pressed.connect(_on_pressed.bind(id))
	return button


func _on_pressed(id: StringName) -> void:
	if _click != null and _click.stream != null:
		_click.call(&"play_cue")
	activate(id)


func _style_panel() -> void:
	var base := get_theme_stylebox(&"panel", &"PanelContainer")
	var style: StyleBoxFlat = (base.duplicate() as StyleBoxFlat) if base is StyleBoxFlat else StyleBoxFlat.new()
	style.set_corner_radius_all(PANEL_RADIUS)
	style.content_margin_left = MARGIN
	style.content_margin_right = MARGIN
	style.content_margin_top = MARGIN
	style.content_margin_bottom = MARGIN
	add_theme_stylebox_override(&"panel", style)


## Radius 6 and padding 4 on every state; a special border at 65 % while enabled.
func _style_button(button: Button, enabled: bool) -> void:
	if _button_styles.is_empty():
		for state: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
			_button_styles[state] = button.get_theme_stylebox(state, &"Button")
	for state: StringName in _button_styles:
		var base: Variant = _button_styles[state]
		if not base is StyleBoxFlat:
			continue
		var style := (base as StyleBoxFlat).duplicate() as StyleBoxFlat
		style.set_corner_radius_all(BUTTON_RADIUS)
		style.content_margin_left = BUTTON_PADDING
		style.content_margin_right = BUTTON_PADDING
		style.content_margin_top = BUTTON_PADDING
		style.content_margin_bottom = BUTTON_PADDING
		if enabled and state != &"focus":
			style.border_color = Color(UiTokens.SPECIAL, ENABLED_BORDER_ALPHA)
		button.add_theme_stylebox_override(state, style)
