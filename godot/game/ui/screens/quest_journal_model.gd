extends RefCounted
## The quest journal's model (Phaser `features/ui/QuestJournalSurfacePort.ts` `listedQuests`,
## `questMarker`, `questState`, `actionFor`, `detailsFor`, `snapshot`; docs/godot/specs/
## journal-and-chest.md 1.3): pure static functions over the quest service's views
## (`QuestService.list()`, catalogue order). The window is res://game/ui/screens/quest_journal_window.gd.
##
## Only quests the player has taken on are listed: active, then completed (each main story first,
## then the newest accepted), then failed, then abandoned. Available offers stay with their NPC.
##
## Glyphs (owner decision J2): Phaser's ✓ ★ ◆ ▶ ○ from game/ui/glyphs.gd (the MARK_* constants
## below), drawn by the theme's font and its symbol fallback; `•`, `×` and `·` are Phaser's own.
##
## Owner: quests (UI).

const QuestCatalog := preload("res://game/quests/quest_catalog.gd")
const Glyphs := preload("res://game/ui/glyphs.gd")

const TITLE := "Quest Book"
const CLOSE_TEXT := "Close (Esc)"
const EMPTY_NAME := "No quests yet"
const EMPTY_DETAILS := "Talk to the slimes marked with ! to take on a quest."
const ACTION_LABELS := {"abandon": "Abandon", "retry": "Retry", "": "No action"}
const ABANDONED_STATUS := "Quest abandoned."
const RESTARTED_STATUS := "Quest restarted."
const CONFIRM_FORMAT := "Abandon \"%s\"? You can retry it later."
const CONFIRM_ACCEPT := "Abandon"
const CONFIRM_CANCEL := "Cancel"
const RETURN_TO_GIVER := "Return to the quest giver to continue."
const TURN_IN_FORMAT := "? Return to %s for your reward."
const NO_GIVER := "the quest giver"
const SEPARATOR := " · "
## Phaser ✓: a completed quest, a finished step or requirement.
const MARK_DONE := Glyphs.CHECK
## Phaser ★: a main-story quest.
const MARK_MAIN := Glyphs.MAIN
## Phaser ◆: a side quest.
const MARK_SIDE := Glyphs.SIDE
## Phaser ▶: the current step.
const MARK_CURRENT := Glyphs.CURRENT
## Phaser ○: a step not reached (abandoned and failed quests show every step so).
const MARK_PENDING := Glyphs.PENDING
## A requirement still to do (Phaser's own glyph).
const MARK_TODO := "•"
## Three spaces before each requirement, two before its count.
const REQUIREMENT_INDENT := "   "
const COUNT_GAP := "  "


## The listed quests (`listedQuests`): `views` in catalogue order -> active, then completed, each
## mainFirst (main story first, then `accepted_at` descending, missing = 0, then the input order);
## then failed, then abandoned, in the input order.
static func listed(views: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_main_first(_with_status(views, "active")))
	out.append_array(_main_first(_with_status(views, "completed")))
	out.append_array(_with_status(views, "failed"))
	out.append_array(_with_status(views, "abandoned"))
	return out


## Completed, failed and abandoned quests step back in the list (dimmed).
static func is_finished(view: Dictionary) -> bool:
	return str(view.get("status", "")) in ["completed", "failed", "abandoned"]


## `questMarker`: done, else main story, else side quest.
static func marker(view: Dictionary) -> String:
	if str(view.get("status", "")) == "completed":
		return MARK_DONE
	return MARK_MAIN if _is_main(view) else MARK_SIDE


## `questState`: "<Main|Side> · In progress · Step 2/2", "· Ready to turn in", "· Done", ...
static func state_text(view: Dictionary) -> String:
	var definition := _definition(view)
	var kind := "Main" if _is_main(view) else "Side"
	match str(view.get("status", "")):
		"active":
			if bool(view.get("ready_to_turn_in", false)):
				return kind + SEPARATOR + "Ready to turn in"
			return kind + SEPARATOR + "In progress" + _step_of(view)
		"available":
			# Unreachable: available quests are not listed (kept for parity).
			var acquisition: Dictionary = definition.get("acquisition", {}) if definition.get("acquisition") is Dictionary else {}
			if str(acquisition.get("kind", "")) == "npc":
				return kind + SEPARATOR + "Talk to " + _npc_name(QuestCatalog.ids(acquisition, "npcIds"))
			return kind + SEPARATOR + "Available"
		"completed":
			return kind + SEPARATOR + "Done"
		"failed":
			return kind + SEPARATOR + "Failed"
	return kind + SEPARATOR + "Abandoned"


## `actionFor`: "abandon" (an active side quest whose abandonment is retryable), "retry" (a
## retryable failed quest, or an abandoned automatic quest whose abandonment is retryable), else "".
static func action_for(view: Dictionary) -> String:
	if view.is_empty():
		return ""
	var definition := _definition(view)
	var status := str(view.get("status", ""))
	var abandon_retryable := _policy_kind(definition, "abandonmentPolicy") == "retryable"
	if status == "active" and str(definition.get("category", "")) == "optional" and abandon_retryable:
		return "abandon"
	if status == "failed" and _policy_kind(definition, "failurePolicy") == "retryable":
		return "retry"
	var acquisition: Dictionary = definition.get("acquisition", {}) if definition.get("acquisition") is Dictionary else {}
	if status == "abandoned" and abandon_retryable and str(acquisition.get("kind", "")) == "automatic":
		return "retry"
	return ""


## `detailsFor`: the description, every visible step with its requirements, the turn-in line, the
## reward summary, and for an abandoned NPC quest how to resume it.
static func details(view: Dictionary) -> String:
	var definition := _definition(view)
	var stage_list := QuestCatalog.stages(definition)
	var visible: Array = view.get("visible_stages", []) if view.get("visible_stages") is Array else []
	if visible.is_empty():
		visible = stage_list.slice(0, 1)
	var active_index := QuestCatalog.stage_index(definition, str(view.get("active_stage_id", "")))
	var status := str(view.get("status", ""))
	var finished := status == "completed"
	var progress: Dictionary = view.get("progress", {}) if view.get("progress") is Dictionary else {}
	var lines: Array[String] = [str(definition.get("description", "")), ""]
	for stage_entry: Variant in visible:
		if not stage_entry is Dictionary:
			continue
		var stage_definition: Dictionary = stage_entry
		var index := QuestCatalog.stage_index(definition, str(stage_definition.get("id", "")))
		var done := finished or (active_index >= 0 and index < active_index)
		var current := not finished and index == active_index
		if stage_list.size() > 1:
			var heading_mark := MARK_DONE if done else (MARK_CURRENT if current else MARK_PENDING)
			lines.append("%s Step %d: %s" % [heading_mark, index + 1, str(stage_definition.get("title", ""))])
		for objective: Dictionary in QuestCatalog.objectives(stage_definition):
			var target := int(objective.get("target", 1))
			var value := target if done else mini(target, int(progress.get(str(objective.get("id", "")), 0)))
			var count := (COUNT_GAP + "%d/%d" % [value, target]) if target > 1 else ""
			lines.append(REQUIREMENT_INDENT + (MARK_DONE if value >= target else MARK_TODO) + " "
				+ QuestCatalog.objective_label(objective) + count)
		lines.append("")
	var completion: Dictionary = definition.get("completion", {}) if definition.get("completion") is Dictionary else {}
	if status == "active" and bool(view.get("ready_to_turn_in", false)) and str(completion.get("kind", "")) == "npc-turn-in":
		lines.append(TURN_IN_FORMAT % _npc_name(QuestCatalog.ids(completion, "npcIds")))
		lines.append("")
	lines.append(QuestCatalog.reward_summary(definition.get("rewards", {}) if definition.get("rewards") is Dictionary else {}))
	var acquisition: Dictionary = definition.get("acquisition", {}) if definition.get("acquisition") is Dictionary else {}
	if status == "abandoned" and str(acquisition.get("kind", "")) == "npc":
		lines.append("")
		lines.append(RETURN_TO_GIVER)
	return "\n".join(lines)


## The window's model (`snapshot`): {"rows": [{"id", "label", "finished"}], "selected_index",
## "selected_id", "details_name", "details_status", "details", "status", "action", "action_label",
## "action_disabled"}. The selection follows `selected_id`, else falls back to the first row.
static func snapshot(views: Array, selected_id: String, status: String) -> Dictionary:
	var quests := listed(views)
	var index := -1
	for position in quests.size():
		if str(quests[position].get("quest_id", "")) == selected_id:
			index = position
			break
	if index < 0 and not quests.is_empty():
		index = 0
	var selected: Dictionary = quests[index] if index >= 0 else {}
	var rows: Array[Dictionary] = []
	for quest: Dictionary in quests:
		rows.append({
			"id": str(quest.get("quest_id", "")),
			"label": "%s %s\n%s" % [marker(quest), title_of(quest), state_text(quest)],
			"finished": is_finished(quest),
		})
	var action := action_for(selected)
	return {
		"rows": rows,
		"selected_index": index,
		"selected_id": str(selected.get("quest_id", "")),
		"details_name": title_of(selected) if not selected.is_empty() else EMPTY_NAME,
		"details_status": state_text(selected) if not selected.is_empty() else "",
		"details": details(selected) if not selected.is_empty() else EMPTY_DETAILS,
		"status": status,
		"action": action,
		"action_label": str(ACTION_LABELS[action]),
		"action_disabled": action.is_empty(),
	}


## The quest's title, else its id.
static func title_of(view: Dictionary) -> String:
	return str(_definition(view).get("title", view.get("quest_id", "")))


# --- private ------------------------------------------------------------------------------------

static func _with_status(views: Array, status: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for view: Variant in views:
		if view is Dictionary and str((view as Dictionary).get("status", "")) == status:
			out.append(view)
	return out


## `mainFirst`: GDScript sorts are not stable, so the input position breaks the remaining ties.
static func _main_first(views: Array[Dictionary]) -> Array[Dictionary]:
	var keyed: Array = []
	for position in views.size():
		var view := views[position]
		keyed.append([0 if _is_main(view) else 1, -float(view.get("accepted_at", 0)), position, view])
	keyed.sort_custom(func(a: Array, b: Array) -> bool:
		for key in 3:
			if a[key] != b[key]:
				return a[key] < b[key]
		return false)
	var out: Array[Dictionary] = []
	for entry: Array in keyed:
		out.append(entry[3])
	return out


static func _definition(view: Dictionary) -> Dictionary:
	return view.get("definition", {}) if view.get("definition") is Dictionary else {}


static func _is_main(view: Dictionary) -> bool:
	return str(_definition(view).get("category", "")) == "mandatory"


## `stepOf`: " · Step <i>/<n>" when the quest has more than one stage and the active one is known.
static func _step_of(view: Dictionary) -> String:
	var definition := _definition(view)
	var count := QuestCatalog.stages(definition).size()
	var index := QuestCatalog.stage_index(definition, str(view.get("active_stage_id", "")))
	return SEPARATOR + "Step %d/%d" % [index + 1, count] if count > 1 and index >= 0 else ""


## `npcName` of the first id: its display name, else the id; "the quest giver" when there is none.
static func _npc_name(npc_ids: Array[String]) -> String:
	return QuestCatalog.npc_name(npc_ids[0]) if not npc_ids.is_empty() else NO_GIVER


static func _policy_kind(definition: Dictionary, policy: String) -> String:
	var part: Variant = definition.get(policy)
	return str((part as Dictionary).get("kind", "")) if part is Dictionary else ""
