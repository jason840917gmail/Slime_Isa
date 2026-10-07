extends Panel
## The quest offer / turn-in window (Phaser `features/ui/QuestOfferSurfacePort.ts` on the authored
## `ui/quest-offer-modal.scene.json`; quests spec 6.4 and 10.6). Godot-owned copy:
## res://game/ui/screens/quest_offer_window.tscn on the UI theme (`WindowPanel`, `PanelTitle`,
## `MutedLabel`, `DangerLabel`, `PrimaryButton`, `MutedButton`). The quest service adds it to main's
## GameWindows (surface "quest-offer": the `modal` pause, MenuOpen / MenuClose) and sets `service`.
##
## `open_offer` / `open_turn_in(quest_id, npc_id, on_finished, on_closed)` show the quest: title
## (turn-in: "Complete: <title>"), the description, the objectives of the last visible stage (else
## the first) as "• <label> (<p>/<t>)", and the reward summary. Accept runs the service's
## `accept` (turn-in: `turn_in`), Decline runs `decline` (turn-in: "Close" just ends it); success
## runs `on_finished` then closes, a refusal shows its reason and keeps the window open. Escape
## closes without a decision (`on_closed` only). Every close runs `on_closed`.
##
## Owner: quests.

const QuestCatalog := preload("res://game/quests/quest_catalog.gd")

const GROUP := &"quest_offer_window"
const SURFACE_ID := &"quest-offer"
const GAME_WINDOWS_GROUP := &"game_windows"
## Centred, min(720, viewport - 32) by min(460, viewport - 32).
const MAX_WIDTH := 720.0
const MAX_HEIGHT := 460.0
const ROOM := 32.0
const OFFER_ACCEPT := "Accept quest"
const OFFER_DECLINE := "Decline / close"
const TURN_IN_ACCEPT := "Turn in and claim reward"
const TURN_IN_DECLINE := "Close"
const TURN_IN_TITLE := "Complete: %s"
const ACTION_FAILED := "The quest action failed."
const SWALLOWED_KEYS: Array[Key] = [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]

## The window opened. Payload: {"quest_id", "npc_id", "kind": "offer"|"turn-in"}.
signal opened(payload: Dictionary)
## The window closed. Payload: {"quest_id"}.
signal closed(payload: Dictionary)

## The quest service (quest_service.gd), set when it mounts the window.
var service: Node

## {"quest_id", "npc_id", "kind", "on_finished", "on_closed"}; {} while closed.
var _session: Dictionary = {}
var _error: String = ""

@onready var title_label: Label = $Scroll/Content/Title
@onready var description_label: Label = $Scroll/Content/Description
@onready var error_label: Label = $Scroll/Content/Error
@onready var accept_button: Button = $Scroll/Content/Accept
@onready var decline_button: Button = $Scroll/Content/Decline
@onready var click_sfx: AudioStreamPlayer = $ClickSfx


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	accept_button.pressed.connect(_on_button.bind("accept"))
	decline_button.pressed.connect(_on_button.bind("decline"))
	get_tree().root.size_changed.connect(_layout)


func _exit_tree() -> void:
	if get_tree().root.size_changed.is_connected(_layout):
		get_tree().root.size_changed.disconnect(_layout)


func open_offer(quest_id: String, npc_id: String, on_finished: Callable, on_closed: Callable) -> void:
	_open({"quest_id": quest_id, "npc_id": npc_id, "kind": "offer", "on_finished": on_finished, "on_closed": on_closed})


func open_turn_in(quest_id: String, npc_id: String, on_finished: Callable, on_closed: Callable) -> void:
	_open({"quest_id": quest_id, "npc_id": npc_id, "kind": "turn-in", "on_finished": on_finished, "on_closed": on_closed})


## "accept" | "decline" | "close" (QuestOfferSurfacePort.invoke).
func invoke(action: String) -> void:
	if action == "close":
		close()
		return
	if _session.is_empty():
		return
	var session := _session
	var turn_in := str(session["kind"]) == "turn-in"
	if action == "decline" and turn_in:
		_call(session.get("on_finished"))
		close()
		return
	if action != "accept" and action != "decline":
		return
	var result := _run(session, action)
	if not bool(result.get("ok", false)):
		_error = str(result.get("reason", ACTION_FAILED))
		if _error.is_empty():
			_error = ACTION_FAILED
		refresh()
		return
	_call(session.get("on_finished"))
	close()


## Closes without a decision (or after one): `on_closed` runs.
func close() -> void:
	if _session.is_empty():
		return
	var session := _session
	_session = {}
	_error = ""
	visible = false
	var windows := _windows()
	if windows != null:
		windows.call(&"pop", self)
	closed.emit({"quest_id": session["quest_id"]})
	_call(session.get("on_closed"))


func is_open() -> bool:
	return not _session.is_empty()


func kind() -> String:
	return str(_session.get("kind", ""))


func title_text() -> String:
	if not is_open():
		return ""
	var title := QuestCatalog.title(str(_session["quest_id"]))
	return TURN_IN_TITLE % title if kind() == "turn-in" else title


## Description, the objectives, the reward summary, separated by blank lines.
func description_text() -> String:
	if not is_open() or service == null:
		return ""
	var view: Dictionary = service.call(&"view", str(_session["quest_id"]))
	if view.is_empty():
		return ""
	var definition: Dictionary = view["definition"]
	var visible_stages: Array = view.get("visible_stages", [])
	var stage_definition: Dictionary = visible_stages.back() if not visible_stages.is_empty() else QuestCatalog.first_stage(definition)
	var progress: Dictionary = view.get("progress", {})
	var lines: Array[String] = [str(definition.get("description", "")), ""]
	for objective: Dictionary in QuestCatalog.objectives(stage_definition):
		lines.append("• %s (%d/%d)" % [str(objective.get("label", "")), int(progress.get(str(objective["id"]), 0)), int(objective["target"])])
	lines.append("")
	lines.append(QuestCatalog.reward_summary(definition.get("rewards", {}) if definition.get("rewards") is Dictionary else {}))
	return "\n".join(lines)


func error_text() -> String:
	return _error


func accept_label() -> String:
	return TURN_IN_ACCEPT if kind() == "turn-in" else OFFER_ACCEPT


func decline_label() -> String:
	return TURN_IN_DECLINE if kind() == "turn-in" else OFFER_DECLINE


func refresh() -> void:
	title_label.text = title_text()
	description_label.text = description_text()
	error_label.text = _error
	accept_button.text = accept_label()
	decline_button.text = decline_label()


## Escape closes; held Space / Enter repeats (a key held from the dialogue) are swallowed so they
## cannot press the focused button.
func _input(event: InputEvent) -> void:
	if not is_open():
		return
	var key := event as InputEventKey
	if key != null and key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code in SWALLOWED_KEYS:
			get_viewport().set_input_as_handled()
			return
	if event.is_pressed() and not event.is_echo() and (event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")):
		get_viewport().set_input_as_handled()
		invoke("close")


func _open(session: Dictionary) -> void:
	close()
	_session = session
	_error = ""
	visible = true
	_layout()
	var windows := _windows()
	if windows != null:
		windows.call(&"push", self, SURFACE_ID)
	refresh()
	accept_button.grab_focus()
	opened.emit({"quest_id": session["quest_id"], "npc_id": session["npc_id"], "kind": session["kind"]})


func _run(session: Dictionary, action: String) -> Dictionary:
	if service == null:
		return {"ok": false, "code": "no-service", "reason": ACTION_FAILED}
	var quest_id := str(session["quest_id"])
	var npc_id := str(session["npc_id"])
	if str(session["kind"]) == "turn-in":
		return service.call(&"turn_in", quest_id, npc_id)
	return service.call(&"accept" if action == "accept" else &"decline", quest_id, npc_id)


func _layout() -> void:
	var view_size := get_viewport_rect().size
	var width := minf(MAX_WIDTH, maxf(1.0, view_size.x - ROOM))
	var height := minf(MAX_HEIGHT, maxf(1.0, view_size.y - ROOM))
	offset_left = -roundf(width / 2.0)
	offset_right = roundf(width / 2.0)
	offset_top = -roundf(height / 2.0)
	offset_bottom = roundf(height / 2.0)


func _on_button(action: String) -> void:
	click_sfx.call(&"play_cue")
	invoke(action)


static func _call(callback: Variant) -> void:
	if callback is Callable and (callback as Callable).is_valid():
		(callback as Callable).call()


func _windows() -> Node:
	return get_tree().get_first_node_in_group(GAME_WINDOWS_GROUP) if is_inside_tree() else null
