extends Button
## The goal line under the coin chip (roadmap 4.12, docs/design/2026-10-07-hud-console-mockup.md;
## it replaced on 2026-10-08 the four-quest card of Phaser's `QuestTrackerSurfacePort.ts`, quests
## spec 4.4 and 10.7). res://game/ui/quest_tracker.tscn, mounted by the Hud (CanvasLayer 10).
##
## One quest at a time: the one the waypoint follows (`waypoint_quest()`: the selected quest while
## it is listed, else the first of the quest service's `tracked_views()`, main story first). Its
## title in small capitals (#ffd277 main story, #d9ecff side quests; "➜ " while the waypoint
## follows it) and its next step: "Talk to <giver>" for an offer, "Return to <npc>" when it is ready
## to turn in, else the first unfinished objective of the current stage ("  p/t" when the target is
## above 1; tutorial objectives name their key). "+n" when more quests are tracked: clicking it
## shows the next one. The full list is in the Journal (J). Hidden while nothing is tracked.
##
## Clicking the line shows the way to its quest (the gold waypoint,
## res://game/ui/quest_waypoint_view.gd); clicking again hides it. The waypoint's state is the
## tooltip ("Click to show the way", ...). Rebuilt on every `quest_changed`.
##
## Owner: quests.

const QuestCatalog := preload("res://game/quests/quest_catalog.gd")
const Glyphs := preload("res://game/ui/glyphs.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

const GROUP := &"quest_tracker"
const QUESTS_GROUP := &"quests"
## The line's place and size: under the coin chip (hud.gd COIN_CHIP), as wide as its text.
const LEFT := 14.0
const TOP := 46.0
const HEIGHT := 46.0
const MIN_WIDTH := 160.0
const MAX_WIDTH := 380.0
const PADDING := 11.0
const STEP_INDENT := 13.0
const MORE_WIDTH := 30.0
const TITLE_FONT_SIZE := 10
const STEP_FONT_SIZE := 14
const MAIN_COLOR := Color("#ffd277")
const SIDE_COLOR := Color("#d9ecff")
const POINTING_PREFIX := "➜ "
const HINT_OFF := "Click to show the way"
const HINT_FOUND := "➜ Follow the gold arrow · click again to hide"
const HINT_NOT_FOUND := "Nothing to point at on this map"
const BOOK_HINT := "%s · Journal"
const NO_GIVER := "the quest giver"

## The waypoint was switched on or off. Payload: {"on": bool, "quest_id": String}.
signal waypoint_toggled(payload: Dictionary)

var _service: Node
var _model: Dictionary = {}
var _waypoint_on: bool = false
var _waypoint_found: bool = false
var _selected_quest_id: String = ""

@onready var title_label: Label = $Title
@onready var marker_label: Label = $Marker
@onready var step_label: Label = $Step
@onready var more_button: Button = $More
@onready var click_sfx: AudioStreamPlayer = $ClickSfx


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	focus_mode = Control.FOCUS_NONE
	visible = false
	pressed.connect(_on_pressed)
	more_button.pressed.connect(_on_more_pressed)


## Binds to the quest service once main made it (the HUD is ready first).
func _process(_delta: float) -> void:
	if _service == null or not is_instance_valid(_service):
		_bind()


func _bind() -> void:
	_service = get_tree().get_first_node_in_group(QUESTS_GROUP) if is_inside_tree() else null
	if _service == null:
		return
	if not _service.is_connected(&"quest_changed", _on_quest_changed):
		_service.connect(&"quest_changed", _on_quest_changed)
	rebuild()


## Rebuilds the model and the line from the quest service.
func rebuild() -> void:
	_model = _build()
	_apply()


## The presentation model: visible, quest_id, title, color, step, more (other tracked quests),
## count (all tracked quests), hint (the waypoint's state), bookHint, rect.
func model() -> Dictionary:
	return _model


## Click on the line: show the way to its quest, or hide the way when the waypoint follows it.
func invoke_track() -> void:
	var quest_id := tracked_quest_id()
	if quest_id.is_empty():
		return
	if _waypoint_on and quest_id == _selected_quest_id:
		_waypoint_on = false
	else:
		_selected_quest_id = quest_id
		_waypoint_on = true
	waypoint_toggled.emit({"on": _waypoint_on, "quest_id": tracked_quest_id()})
	rebuild()


## Shows the next tracked quest (the "+n" button); the waypoint, when on, follows it.
func show_next() -> void:
	var views := _views()
	if views.size() < 2:
		return
	var index := 0
	for i in views.size():
		if str(views[i]["quest_id"]) == tracked_quest_id():
			index = i
	_selected_quest_id = str(views[(index + 1) % views.size()]["quest_id"])
	if _waypoint_on:
		waypoint_toggled.emit({"on": true, "quest_id": _selected_quest_id})
	rebuild()


## Whether the player asked for the way.
func showing_way() -> bool:
	return _waypoint_on


## The quest the line shows and the waypoint follows: the selected one while it is listed, else
## the first.
func waypoint_quest() -> Dictionary:
	var views := _views()
	for quest: Dictionary in views:
		if str(quest["quest_id"]) == _selected_quest_id:
			return quest
	return views[0] if not views.is_empty() else {}


func tracked_quest_id() -> String:
	return str(waypoint_quest().get("quest_id", ""))


## The waypoint view reports whether it found something on this map.
func set_waypoint_found(found: bool) -> void:
	if found == _waypoint_found:
		return
	_waypoint_found = found
	rebuild()


## `describe`: {"quest_id", "main", "title", "lines"} for one tracked quest view (every line of
## Phaser's card: "! Talk to ...", "? Return to ...", or one "•"/"✓" line per objective).
static func describe(quest: Dictionary) -> Dictionary:
	var definition: Dictionary = quest["definition"]
	var main_story := str(definition.get("category", "")) == "mandatory"
	var lines: Array[String] = []
	var completion: Dictionary = definition.get("completion", {})
	if str(quest["status"]) != "active":
		var acquisition: Dictionary = definition.get("acquisition", {})
		var givers := QuestCatalog.ids(acquisition, "npcIds")
		var giver := QuestCatalog.npc_name(givers[0]) if str(acquisition.get("kind", "")) == "npc" and not givers.is_empty() else NO_GIVER
		lines.append("! Talk to " + giver)
	elif bool(quest.get("ready_to_turn_in", false)) and str(completion.get("kind", "")) == "npc-turn-in":
		var npcs := QuestCatalog.ids(completion, "npcIds")
		lines.append("? Return to " + (QuestCatalog.npc_name(npcs[0]) if not npcs.is_empty() else NO_GIVER))
	else:
		var stage_definition := QuestCatalog.stage(definition, str(quest.get("active_stage_id", "")))
		var progress: Dictionary = quest.get("progress", {})
		for objective: Dictionary in QuestCatalog.objectives(stage_definition):
			var target := int(objective["target"])
			var current := mini(target, int(progress.get(str(objective["id"]), 0)))
			var count := "  %d/%d" % [current, target] if target > 1 else ""
			lines.append("%s %s%s" % [Glyphs.CHECK if current >= target else "•", QuestCatalog.objective_label(objective), count])
		if lines.is_empty():
			lines.append(str(stage_definition.get("description", "")))
	return {"quest_id": str(quest["quest_id"]), "main": main_story, "title": str(definition.get("title", quest["quest_id"])),
		"lines": lines}


## The next step of a described quest: its first unfinished line without the bullet.
static func next_step(entry: Dictionary) -> String:
	var lines: Array = entry.get("lines", [])
	for line: String in lines:
		if line.begins_with(Glyphs.CHECK):
			continue
		for bullet: String in ["! ", "? ", "• "]:
			if line.begins_with(bullet):
				return line.substr(bullet.length())
		return line
	return str(lines[lines.size() - 1]).substr(2) if not lines.is_empty() else ""


func _views() -> Array[Dictionary]:
	if _service == null or not is_instance_valid(_service):
		return []
	return _service.call(&"tracked_views")


func _build() -> Dictionary:
	var views := _views()
	var shown := waypoint_quest()
	var entry := describe(shown) if not shown.is_empty() else {}
	var pointing := not entry.is_empty() and _waypoint_on and str(entry["quest_id"]) == _selected_quest_id
	var hint := (HINT_FOUND if _waypoint_found else HINT_NOT_FOUND) if pointing else HINT_OFF
	var out := {
		"visible": not entry.is_empty(),
		"quest_id": str(entry.get("quest_id", "")),
		"title": (POINTING_PREFIX if pointing else "") + str(entry.get("title", "")),
		"color": MAIN_COLOR if bool(entry.get("main", false)) else SIDE_COLOR,
		"step": next_step(entry) if not entry.is_empty() else "",
		"more": maxi(0, views.size() - 1),
		"count": views.size(),
		"hint": hint,
		"bookHint": BOOK_HINT % ControlLabels.control_label(&"journal"),
	}
	out["rect"] = Rect2(LEFT, TOP, _width(out), HEIGHT)
	return out


## As wide as the title or the step (and the "+n" button), within MIN_WIDTH..MAX_WIDTH.
func _width(out: Dictionary) -> float:
	var font := get_theme_default_font()
	if font == null:
		return MAX_WIDTH
	var title_width := font.get_string_size(str(out["title"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, TITLE_FONT_SIZE).x
	var step_width := font.get_string_size(str(out["step"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, STEP_FONT_SIZE).x + STEP_INDENT
	var more := MORE_WIDTH if int(out["more"]) > 0 else 0.0
	return clampf(maxf(title_width, step_width) + PADDING * 2.0 + more, MIN_WIDTH, MAX_WIDTH)


func _apply() -> void:
	visible = bool(_model.get("visible", false))
	var rect: Rect2 = _model.get("rect", Rect2(LEFT, TOP, MIN_WIDTH, HEIGHT))
	position = rect.position
	size = rect.size
	title_label.text = str(_model.get("title", "")).to_upper()
	title_label.add_theme_color_override(&"font_color", _model.get("color", SIDE_COLOR))
	step_label.text = str(_model.get("step", ""))
	tooltip_text = "%s · %s" % [str(_model.get("hint", "")), str(_model.get("bookHint", ""))]
	var more := int(_model.get("more", 0))
	step_label.offset_right = -(PADDING + (MORE_WIDTH if more > 0 else 0.0))
	more_button.visible = more > 0
	more_button.text = "+%d" % more
	more_button.tooltip_text = "Show the next quest (%d tracked)" % int(_model.get("count", 0))


func _on_pressed() -> void:
	click_sfx.call(&"play_cue")
	invoke_track()


func _on_more_pressed() -> void:
	click_sfx.call(&"play_cue")
	show_next()


func _on_quest_changed(_payload: Dictionary) -> void:
	rebuild()
