extends Control
## Base of the menu's game windows (the bag, crafting; Phaser `UiSurfacePort` + its scene-JSON
## ModalRoot): a full-screen Control that stops the mouse (the world and the HUD behind take no
## clicks or wheel, [DIFF] K16) holding a centred `WindowPanel` sized from the viewport
## (`min(max, viewport - 32)`), with a vertical ScrollContainer over a fixed-height content area
## whose children subclasses place by the panel width (`_layout`). Built in code; added to
## GameWindows with `add_window`.
##
## `open()` shows it, refreshes it, reports it to GameWindows (`push`: the `modal` pause, MenuOpen)
## and focuses its first control; `close()` hides it and pops it (MenuClose; the last window
## unpauses). Escape reaches GameWindows, which calls `close()`. Every action button plays the
## click cue (`sfx.ui.click`), list selections the select cue (`sfx.ui.hover`, volume 0.8).
##
## Subclasses override `_build()`, `_layout(width)`, `refresh()` and `_on_opening()`.
##
## Owner: crafting / inventory (UI).

const SfxPlayer := preload("res://game/runtime/sfx_player.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

const WINDOWS_GROUP := &"game_windows"
const CLICK_STREAM := "res://asset/audio/sfx/library/ui/click.ogg"
const SELECT_STREAM := "res://asset/audio/sfx/library/ui/hover.ogg"
## 20·log10(0.8): the select cue plays at volume 0.8.
const SELECT_VOLUME_DB := -1.9382
const SFX_MIN_INTERVAL_MS := 40.0
## The panel keeps 16 px to every viewport edge.
const VIEWPORT_MARGIN := 32.0

signal opened(window: Control)
signal closed(window: Control)

## Phaser surface id: GameWindows' stack entry ("inventory", "crafting").
var surface_id: StringName = &""
## Largest panel size (Phaser `min(1080, …)` / `min(660, …)`) and smallest width.
var max_size: Vector2 = Vector2(1080.0, 660.0)
var min_width: float = 1.0
## Height of the scrolled content (the scene's Content node).
var content_height: float = 660.0

var panel: Panel
var scroll: ScrollContainer
var content: Control
var click_sfx: AudioStreamPlayer
var select_sfx: AudioStreamPlayer
var _open: bool = false
var _panel_width: float = 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func _ready() -> void:
	panel = Panel.new()
	panel.name = "Panel"
	panel.theme_type_variation = &"WindowPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(panel)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	content = Control.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.custom_minimum_size = Vector2(0.0, content_height)
	scroll.add_child(content)
	click_sfx = _make_sfx("ClickSfx", CLICK_STREAM, 0.0)
	select_sfx = _make_sfx("SelectSfx", SELECT_STREAM, SELECT_VOLUME_DB)
	_build()
	resized.connect(_layout_panel)
	_layout_panel()


func is_open() -> bool:
	return _open


## Shows the window (no-op when open), reports it to GameWindows and focuses it.
func open() -> void:
	if _open:
		return
	_open = true
	_on_opening()
	visible = true
	_layout_panel()
	refresh()
	var windows := game_windows()
	if windows != null:
		windows.call(&"push", self, surface_id)
	focus_initial()
	opened.emit(self)


## Hides the window (no-op when closed) and pops it from GameWindows.
func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()
	var windows := game_windows()
	if windows != null:
		windows.call(&"pop", self)
	closed.emit(self)


## Fills the window from the current state (on open and whenever the state changes).
func refresh() -> void:
	pass


## Focuses the first visible, enabled, focusable button (tree order).
func focus_initial() -> void:
	for node: Node in find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button.is_visible_in_tree() and not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			button.grab_focus()
			return


## The GameWindows layer (group `game_windows`), or null.
func game_windows() -> Node:
	return get_tree().get_first_node_in_group(WINDOWS_GROUP) if is_inside_tree() else null


## The panel width the content is laid out for.
func panel_width() -> float:
	return _panel_width


# --- for subclasses ---------------------------------------------------------------------------------

## Builds the controls under `content` (called once from `_ready`).
func _build() -> void:
	pass


## Places the controls for a panel `width` px wide.
func _layout(_width: float) -> void:
	pass


## Resets per-opening state before the first refresh.
func _on_opening() -> void:
	pass


## A Label under `content` with a theme variation and an optional font size.
func _label(node_name: String, variation: StringName = &"", font_size: int = 0) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if variation != &"":
		label.theme_type_variation = variation
	if font_size > 0:
		label.add_theme_font_size_override(&"font_size", font_size)
	content.add_child(label)
	return label


## A Button under `content` that plays the click cue and calls `on_pressed`.
func _button(node_name: String, text: String, variation: StringName, font_size: int, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.theme_type_variation = variation
	if font_size > 0:
		button.add_theme_font_size_override(&"font_size", font_size)
	button.pressed.connect(play_click)
	button.pressed.connect(on_pressed)
	content.add_child(button)
	return button


## Puts `control` at `rect` (content coordinates).
static func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


## Rect2 from two corners (Phaser `offsetMin` / `offsetMax`).
static func _rect(left: float, top: float, right: float, bottom: float) -> Rect2:
	return Rect2(left, top, maxf(0.0, right - left), maxf(0.0, bottom - top))


func play_click() -> void:
	if click_sfx != null and click_sfx.has_method(&"play_cue"):
		click_sfx.call(&"play_cue")


func play_select() -> void:
	if select_sfx != null and select_sfx.has_method(&"play_cue"):
		select_sfx.call(&"play_cue")


# --- private ------------------------------------------------------------------------------------

func _layout_panel() -> void:
	if panel == null or not is_inside_tree():
		return
	var viewport := get_viewport_rect().size
	var width := minf(max_size.x, maxf(min_width, viewport.x - VIEWPORT_MARGIN))
	var height := minf(max_size.y, maxf(1.0, viewport.y - VIEWPORT_MARGIN))
	var half := Vector2(roundf(width / 2.0), roundf(height / 2.0))
	panel.offset_left = -half.x
	panel.offset_top = -half.y
	panel.offset_right = half.x
	panel.offset_bottom = half.y
	_panel_width = half.x * 2.0
	content.custom_minimum_size = Vector2(0.0, content_height)
	_layout(_panel_width)


func _make_sfx(node_name: String, path: String, volume_db: float) -> AudioStreamPlayer:
	var sfx: AudioStreamPlayer = SfxPlayer.new()
	sfx.name = node_name
	sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	sfx.bus = &"Effects"
	sfx.max_polyphony = 4
	sfx.volume_db = volume_db
	sfx.set(&"min_interval_ms", SFX_MIN_INTERVAL_MS)
	if ResourceLoader.exists(path):
		sfx.stream = load(path) as AudioStream
	add_child(sfx)
	return sfx
