extends Panel
## The NPC conversation box (Phaser `features/ui/NpcDialogueSurfacePort.ts` on the authored
## `ui/npc-dialogue.scene.json`; quests spec 6.1-6.3 and 10.6). Godot-owned copy:
## res://game/ui/screens/dialogue_box.tscn on the UI theme (`DialoguePanel`, `NamePlate`,
## `PrimaryButton`, `MutedButton`, `CaptionLabel`). The quest service adds it to main's
## GameWindows, which pauses the world while it is open (surface "npc-dialogue": MenuOpen /
## MenuClose, the `modal` pause, the music duck).
##
## `open(request)`: {"speaker", "pages", "finish_label"?, "on_finished"?: Callable, "on_closed"?:
## Callable}. Pages are trimmed and blank ones dropped ("..." when none is left); an open
## conversation closes first. Each page types out at 45 characters a second on real time;
## `advance()` (the Next button, Space / Enter / keypad Enter, and the interact button: owner
## decision Q4) shows the whole page while it types, else turns the page, and on the last page
## ends the conversation (`on_finished`). Escape and ✕ end it without a decision (`on_closed`).
## Exactly one of the two callbacks runs, once. Key repeats are ignored and every key the box uses
## is consumed in `_input`, so Space never jumps and Escape never reaches the pause menu.
##
## Owner: quests.

const Services := preload("res://game/shared/services.gd")

const GROUP := &"dialogue_box"
const SURFACE_ID := &"npc-dialogue"
const GAME_WINDOWS_GROUP := &"game_windows"
## REVEAL_CHARS_PER_SECOND (NpcDialogueSurfacePort.ts).
const REVEAL_CHARS_PER_SECOND := 45.0
## A blip as letters appear (its player's minimum interval keeps it to about twelve a second).
const CUE_TYPE := &"TalkBlip"
## Box: width min(760, viewport - 24), 196 tall, 24 above the bottom edge.
const MAX_WIDTH := 760.0
const SIDE_ROOM := 24.0
const HEIGHT := 196.0
const BOTTOM_GAP := 24.0
const HINT_TEXT := "Space / Enter  continue   ·   Esc  close"
const Glyphs := preload("res://game/ui/glyphs.gd")
## Phaser "Next  ▸", "Skip  ▸▸", "Done  ✓" (glyphs: game/ui/glyphs.gd).
const NEXT_LABEL := "Next  " + Glyphs.NEXT
const SKIP_LABEL := "Skip  " + Glyphs.NEXT + Glyphs.NEXT
const DONE_LABEL := "Done  " + Glyphs.CHECK
const EMPTY_PAGE := "..."
const ADVANCE_KEYS: Array[Key] = [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
## `npc-dialogue-nudge`: the Next button eases 3 px right and back every 1.2 s.
const NUDGE_PX := 3.0
const NUDGE_PERIOD_MS := 1200.0
const NEXT_LEFT := -156.0
const NEXT_RIGHT := -18.0

## A conversation opened. Payload: {"speaker", "pages"}.
signal opened(payload: Dictionary)
## The conversation ended. Payload: {"finished": bool}.
signal closed(payload: Dictionary)

## Real-time clock in ms (tests replace it).
var clock: Callable = func() -> float: return float(Time.get_ticks_msec())

var _session: Dictionary = {}
var _pages: Array[String] = []
var _page: int = 0
var _revealed: int = 0
var _page_started_ms: float = 0.0

@onready var speaker_plate: PanelContainer = $Speaker
@onready var speaker_label: Label = $Speaker/Label
@onready var page_label_node: Label = $Page
@onready var close_button: Button = $Close
@onready var text_label: Label = $Text
@onready var hint_label: Label = $Hint
@onready var next_button: Button = $Next
@onready var click_sfx: AudioStreamPlayer = $ClickSfx


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	hint_label.text = HINT_TEXT
	# Bold, like the CSS `.scene-control--button { font-weight: 700 }` of the box.
	var bold := get_theme_font(&"font", &"BoldButton")
	if bold != null:
		next_button.add_theme_font_override(&"font", bold)
	next_button.pressed.connect(_on_next_pressed)
	close_button.text = Glyphs.CLOSE
	close_button.pressed.connect(_on_close_pressed)
	get_tree().root.size_changed.connect(_layout)


func _exit_tree() -> void:
	if get_tree().root.size_changed.is_connected(_layout):
		get_tree().root.size_changed.disconnect(_layout)


## Starts a conversation (see the file comment).
func open(request: Dictionary) -> void:
	close()
	var pages: Array[String] = []
	for page: Variant in request.get("pages", []):
		var text := str(page).strip_edges()
		if not text.is_empty():
			pages.append(text)
	if pages.is_empty():
		pages.append(EMPTY_PAGE)
	_session = request.duplicate()
	_pages = pages
	_page = 0
	_revealed = 0
	_page_started_ms = float(clock.call())
	visible = true
	_layout()
	var windows := _windows()
	if windows != null:
		windows.call(&"push", self, SURFACE_ID)
	_refresh()
	opened.emit({"speaker": str(request.get("speaker", "")), "pages": pages.duplicate()})


## Next / Space / Enter / interact: finish typing, else the next page, else end (finished).
func advance() -> void:
	if _session.is_empty():
		return
	var length := _pages[_page].length()
	if _revealed < length:
		_revealed = length
		_refresh()
		return
	if _page >= _pages.size() - 1:
		close(true)
		return
	_page += 1
	_revealed = 0
	_page_started_ms = float(clock.call())
	_refresh()


## Ends the conversation: `on_finished` when `finished` (and given), else `on_closed`.
func close(finished: bool = false) -> void:
	if _session.is_empty():
		return
	var session := _session
	_session = {}
	visible = false
	var windows := _windows()
	if windows != null:
		windows.call(&"pop", self)
	closed.emit({"finished": finished})
	var on_finished: Variant = session.get("on_finished")
	var on_closed: Variant = session.get("on_closed")
	if finished and on_finished is Callable and (on_finished as Callable).is_valid():
		(on_finished as Callable).call()
	elif on_closed is Callable and (on_closed as Callable).is_valid():
		(on_closed as Callable).call()


func is_open() -> bool:
	return not _session.is_empty()


func page_index() -> int:
	return _page


func page_count() -> int:
	return _pages.size() if is_open() else 0


func speaker() -> String:
	return str(_session.get("speaker", ""))


## A copy of the conversation's pages (trimmed); [] while closed.
func pages() -> Array[String]:
	var out: Array[String] = []
	if is_open():
		out.assign(_pages)
	return out


## The page typed so far (newlines kept).
func visible_text() -> String:
	return _pages[_page].substr(0, _revealed) if is_open() else ""


## "<page> / <count>" when there is more than one page.
func page_label() -> String:
	return "%d / %d" % [_page + 1, _pages.size()] if is_open() and _pages.size() > 1 else ""


## "Skip  ▸▸" while typing, the finish label on the last page, else "Next  ▸".
func next_label() -> String:
	if not is_open():
		return NEXT_LABEL
	if _revealed < _pages[_page].length():
		return SKIP_LABEL
	if _page >= _pages.size() - 1:
		var finish: Variant = _session.get("finish_label")
		return str(finish) if finish is String and not (finish as String).is_empty() else DONE_LABEL
	return NEXT_LABEL


func hint_text() -> String:
	return HINT_TEXT


## Test hook: the page started `ms` earlier (the reveal moves on by that much).
func advance_reveal(ms: float) -> void:
	if not is_open():
		return
	_page_started_ms -= ms
	_update_reveal()


func _process(_delta: float) -> void:
	if not is_open():
		return
	_update_reveal()
	var reduce_motion := Services.feel() != null and Services.feel().reduce_motion
	var phase := fmod(float(clock.call()), NUDGE_PERIOD_MS) / NUDGE_PERIOD_MS
	var nudge := 0.0 if reduce_motion else NUDGE_PX * (0.5 - 0.5 * cos(phase * TAU))
	next_button.offset_left = NEXT_LEFT + nudge
	next_button.offset_right = NEXT_RIGHT + nudge


## Space / Enter / keypad Enter and interact advance (repeats ignored); Escape closes. Every key
## the box uses is consumed here, before the GUI and the player.
func _input(event: InputEvent) -> void:
	if not is_open():
		return
	var key := event as InputEventKey
	if key != null:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code in ADVANCE_KEYS:
			get_viewport().set_input_as_handled()
			if key.pressed and not key.echo:
				advance()
			return
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		advance()


## `revealed = min(len, floor(elapsed / 1000 * 45))`, never going back (after a skip).
func _update_reveal() -> void:
	var length := _pages[_page].length()
	if _revealed >= length:
		return
	var elapsed := float(clock.call()) - _page_started_ms
	var target := mini(length, floori(maxf(0.0, elapsed) / 1000.0 * REVEAL_CHARS_PER_SECOND))
	if target > _revealed:
		var shown := _pages[_page].substr(_revealed, target - _revealed)
		_revealed = target
		if not shown.strip_edges().is_empty():
			var feel := Services.feel()
			if feel != null:
				feel.audio_cue(CUE_TYPE)
		_refresh()


func _refresh() -> void:
	if not is_open():
		return
	speaker_label.text = speaker()
	speaker_plate.reset_size()
	text_label.text = visible_text()
	page_label_node.text = page_label()
	next_button.text = next_label()


## Bottom-centre box: width min(760, max(1, viewport width - 24)), 196 tall, 24 px gap.
func _layout() -> void:
	var view_width := get_viewport_rect().size.x
	var width := minf(MAX_WIDTH, maxf(1.0, view_width - SIDE_ROOM))
	offset_left = -width / 2.0
	offset_right = width / 2.0
	offset_top = -(HEIGHT + BOTTOM_GAP)
	offset_bottom = -BOTTOM_GAP


func _on_next_pressed() -> void:
	click_sfx.call(&"play_cue")
	advance()


func _on_close_pressed() -> void:
	click_sfx.call(&"play_cue")
	close()


func _windows() -> Node:
	return get_tree().get_first_node_in_group(GAME_WINDOWS_GROUP) if is_inside_tree() else null
