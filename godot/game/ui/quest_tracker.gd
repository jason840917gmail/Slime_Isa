extends Panel
## The quest tracker under the HUD (Phaser `features/ui/QuestTrackerSurfacePort.ts` on the authored
## `ui/quest-tracker.scene.json`; quests spec 4.4 and 10.7). Godot-owned copy:
## res://game/ui/quest_tracker.tscn on the UI theme (`TrackerPanel`, `HudLabel`, `CaptionLabel`,
## `GhostButton`), mounted by the Hud (CanvasLayer 10).
##
## Shows up to four quests from the quest service's `tracked_views()` (main story first, in
## progress before offers, newest first): the title (#ffd277 main story, #d9ecff side quests;
## "➜ " while the waypoint follows it) and its lines: "! Talk to <giver>" for an offer, "? Return
## to <npc>" when it is ready to turn in, else one "•"/"✓" line per objective of the current stage
## with "  p/t" when the target is above 1 (tutorial objectives name their key). Rows wrap every
## 40 characters (Phaser's estimate), which sizes each block and the card: card at (16, 96), 284
## wide, header 26, title 20, line 18, gap 8, footer 22. Hidden while nothing is tracked.
##
## Clicking quest n shows the way to it (the gold waypoint, res://game/ui/quest_waypoint_view.gd);
## clicking the quest the waypoint follows hides it. Only the four quest blocks take the mouse.
## Rebuilt on every `quest_changed`.
##
## Owner: quests.

const QuestCatalog := preload("res://game/quests/quest_catalog.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")

const GROUP := &"quest_tracker"
const QUESTS_GROUP := &"quests"
## TRACKED_QUEST_SLOTS and the layout constants (QuestTrackerSurfacePort.ts:11-25).
const SLOTS := 4
const WIDTH := 284.0
const TOP := 96.0
const LEFT := 16.0
const HEADER_HEIGHT := 26.0
const TITLE_HEIGHT := 20.0
const LINE_HEIGHT := 18.0
const QUEST_GAP := 8.0
const FOOTER_HEIGHT := 22.0
const CHARS_PER_ROW := 40
const SLOT_INSET := 10.0
const MAIN_COLOR := Color("#ffd277")
const SIDE_COLOR := Color("#d9ecff")
const POINTING_PREFIX := "➜ "
const HINT_OFF := "Click a quest to show the way"
const HINT_FOUND := "➜ Follow the gold arrow · click it again to hide"
const HINT_NOT_FOUND := "Nothing to point at on this map"
const BOOK_HINT := "%s · Journal tab"
const NO_GIVER := "the quest giver"

## The waypoint was switched on or off. Payload: {"on": bool, "quest_id": String}.
signal waypoint_toggled(payload: Dictionary)

var _service: Node
var _model: Dictionary = {}
var _entries: Array[Dictionary] = []
var _waypoint_on: bool = false
var _waypoint_found: bool = false
var _selected_quest_id: String = ""

@onready var heading_label: Label = $Heading
@onready var book_hint_label: Label = $BookHint
@onready var hint_label: Label = $Hint
@onready var click_sfx: AudioStreamPlayer = $ClickSfx


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	for slot in range(1, SLOTS + 1):
		var button := _slot(slot)
		button.pressed.connect(_on_slot_pressed.bind(slot))


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


## Rebuilds the model and the card from the quest service.
func rebuild() -> void:
	_model = _build()
	_apply()


## The presentation model (Phaser's keys): visible, heading, hint, bookHint, offsetMin/Max and per
## slot n: quest<n>Visible, Title, Color, Objectives, OffsetMin, OffsetMax.
func model() -> Dictionary:
	return _model


## Click on quest `slot` (1-based): select it and show the way, or hide the way when the waypoint
## already follows it (`invoke track-n`).
func invoke_track(slot: int) -> void:
	if slot < 1 or slot > _entries.size():
		return
	var quest_id := str(_entries[slot - 1]["quest_id"])
	if _waypoint_on and quest_id == tracked_quest_id():
		_waypoint_on = false
	else:
		_selected_quest_id = quest_id
		_waypoint_on = true
	waypoint_toggled.emit({"on": _waypoint_on, "quest_id": tracked_quest_id()})
	rebuild()


## Whether the player asked for the way.
func showing_way() -> bool:
	return _waypoint_on


## The quest the waypoint follows: the selected one while it is listed, else the first.
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


## Rows a line takes once it wraps (Phaser's 40-characters-per-row estimate).
static func wrapped_rows(line: String) -> int:
	return maxi(1, ceili(float(line.length()) / float(CHARS_PER_ROW)))


## `describe`: {"quest_id", "main", "title", "lines"} for one tracked quest view.
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
			lines.append("%s %s%s" % ["✓" if current >= target else "•", QuestCatalog.objective_label(objective), count])
		if lines.is_empty():
			lines.append(str(stage_definition.get("description", "")))
	return {"quest_id": str(quest["quest_id"]), "main": main_story, "title": str(definition.get("title", quest["quest_id"])),
		"lines": lines}


func _views() -> Array[Dictionary]:
	if _service == null or not is_instance_valid(_service):
		return []
	return _service.call(&"tracked_views")


## QuestTrackerSurfacePort.build.
func _build() -> Dictionary:
	var all := _views()
	_entries = []
	for index in mini(SLOTS, all.size()):
		_entries.append(describe(all[index]))
	var selected := tracked_quest_id()
	var out := {}
	var y := HEADER_HEIGHT
	for slot in range(1, SLOTS + 1):
		var entry: Dictionary = _entries[slot - 1] if slot <= _entries.size() else {}
		var rows := 0
		for line: String in entry.get("lines", []):
			rows += wrapped_rows(line)
		var height := TITLE_HEIGHT + rows * LINE_HEIGHT if not entry.is_empty() else 0.0
		var pointing := not entry.is_empty() and _waypoint_on and str(entry["quest_id"]) == selected
		out["quest%dVisible" % slot] = not entry.is_empty()
		out["quest%dTitle" % slot] = (POINTING_PREFIX if pointing else "") + str(entry.get("title", ""))
		out["quest%dColor" % slot] = MAIN_COLOR if bool(entry.get("main", false)) else SIDE_COLOR
		out["quest%dObjectives" % slot] = "\n".join(PackedStringArray(entry.get("lines", [])))
		out["quest%dOffsetMin" % slot] = Vector2(SLOT_INSET, y)
		out["quest%dOffsetMax" % slot] = Vector2(-SLOT_INSET, y + height)
		if not entry.is_empty():
			y += height + QUEST_GAP
	var more := all.size() - _entries.size()
	var footer := (HINT_FOUND if _waypoint_found else HINT_NOT_FOUND) if _waypoint_on else HINT_OFF
	out["visible"] = not _entries.is_empty()
	out["heading"] = "QUESTS · %d" % all.size()
	out["hint"] = "%s  (+%d in the book)" % [footer, more] if more > 0 else footer
	out["bookHint"] = BOOK_HINT % ControlLabels.control_label(&"menu")
	out["offsetMin"] = Vector2(LEFT, TOP)
	out["offsetMax"] = Vector2(LEFT + WIDTH, TOP + (y - QUEST_GAP + FOOTER_HEIGHT))
	return out


func _apply() -> void:
	visible = bool(_model.get("visible", false))
	heading_label.text = str(_model.get("heading", ""))
	hint_label.text = str(_model.get("hint", ""))
	book_hint_label.text = str(_model.get("bookHint", ""))
	var top_left: Vector2 = _model.get("offsetMin", Vector2(LEFT, TOP))
	var bottom_right: Vector2 = _model.get("offsetMax", Vector2(LEFT + WIDTH, TOP))
	offset_left = top_left.x
	offset_top = top_left.y
	offset_right = bottom_right.x
	offset_bottom = bottom_right.y
	for slot in range(1, SLOTS + 1):
		var button := _slot(slot)
		button.visible = bool(_model.get("quest%dVisible" % slot, false))
		var slot_min: Vector2 = _model.get("quest%dOffsetMin" % slot, Vector2.ZERO)
		var slot_max: Vector2 = _model.get("quest%dOffsetMax" % slot, Vector2.ZERO)
		button.offset_left = slot_min.x
		button.offset_top = slot_min.y
		button.offset_right = slot_max.x
		button.offset_bottom = slot_max.y
		var title := button.get_node(^"Title") as Label
		title.text = str(_model.get("quest%dTitle" % slot, ""))
		title.add_theme_color_override(&"font_color", _model.get("quest%dColor" % slot, SIDE_COLOR))
		(button.get_node(^"Objectives") as Label).text = str(_model.get("quest%dObjectives" % slot, ""))


func _slot(slot: int) -> Button:
	return get_node(NodePath("Quest%d" % slot)) as Button


func _on_slot_pressed(slot: int) -> void:
	click_sfx.call(&"play_cue")
	invoke_track(slot)


func _on_quest_changed(_payload: Dictionary) -> void:
	rebuild()
