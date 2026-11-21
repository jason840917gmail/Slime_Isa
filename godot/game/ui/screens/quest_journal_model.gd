extends RefCounted
## The quest journal's model (Phaser `features/ui/QuestJournalSurfacePort.ts` `listedQuests`,
## `questMarker`, `questState`, `actionFor`, `detailsFor`, `snapshot`; docs/godot/specs/
## journal-and-chest.md 1.3): pure static functions over the quest service's views
## (`QuestService.list()`, catalogue order). The window is res://game/ui/screens/quest_journal_window.gd.
##
## Only quests the player has taken on are listed: active, then completed (each main story first,
## then the newest accepted), then failed, then abandoned. Available offers stay with their NPC.
## Since 2026-11-19 (quests spec 14.7) a "Tips" row follows the active quests once a tip is heard:
## its page lists the tips NPCs gave, newest first; and the main quest's page shows its Pearl slots
## (`pearls`, `pearlSlots` in its definition) in place of the reward line, each lit (✓) once its
## Pearl is home (story flag `pearl.<id>.home`), ▶ once won and not home yet. Since 2026-11-20
## (quests spec 14.8) a "War journal" row follows (after the Tips row) once a page of the Thorn
## Guard's war journal is found: its page shows every page found, in order, to read again.
##
## Glyphs (owner decision J2): Phaser's ✓ ★ ◆ ▶ ○ from game/ui/glyphs.gd (the MARK_* constants
## below), drawn by the theme's font and its symbol fallback; `•`, `×` and `·` are Phaser's own.
##
## Owner: quests (UI).

const QuestCatalog := preload("res://game/quests/quest_catalog.gd")
const Glyphs := preload("res://game/ui/glyphs.gd")

const TITLE := "Quest Book"
const CLOSE_TEXT := "Close (Esc)"
const EMPTY_NAME := "Nothing written yet"
const EMPTY_DETAILS := "Talk to the slimes marked with ! to hear what they know."
## The Tips row (spec 14.7): its id in the rows (never a quest id), title, state and page texts.
const TIPS_ID := "@tips"
const TIPS_TITLE := "Tips"
const TIPS_STATE := "What the slimes told you"
const TIPS_COUNT := "%d heard"
const TIP_LINE := "%s %s\n   %s"
## The War journal row (spec 14.8): its id in the rows, title, state and page texts.
const WAR_ID := "@war-journal"
const WAR_TITLE := "War journal"
const WAR_STATE := "Pages of the Thorn Guard's war journal"
const WAR_COUNT := "%d of %d pages"
const WAR_PAGE_HEADING := "Page %d: %s"
const WAR_ONE_LOST := "One page is still lost."
const WAR_MANY_LOST := "%d pages are still lost."
## The main quest's Pearl slots (spec 14.7).
const PEARLS_HEADING := "Pearls of the Wellspring: %d of %d home"
const PEARL_HOME := "%s %s: home. %s"
const PEARL_WON := "%s %s: won, on its way home. %s"
const PEARL_NOT_FOUND := "%s %s"
const PEARL_LOST := "A Pearl still lost"
const PEARL_TAKEN_FLAG := "pearl.%s"
const PEARL_HOME_FLAG := "pearl.%s.home"
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
## A tip, and the Tips row.
const MARK_TIP := "•"
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
## reward summary (the main quest: its Pearl slots instead, read through `extras.has_flag`), and for
## an abandoned NPC quest how to resume it.
static func details(view: Dictionary, extras: Dictionary = {}) -> String:
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
	if definition.get("pearls") is Array:
		lines.append_array(pearl_lines(definition, extras.get("has_flag", Callable())))
	else:
		lines.append(QuestCatalog.reward_summary(definition.get("rewards", {}) if definition.get("rewards") is Dictionary else {}))
	var acquisition: Dictionary = definition.get("acquisition", {}) if definition.get("acquisition") is Dictionary else {}
	if status == "abandoned" and str(acquisition.get("kind", "")) == "npc":
		lines.append("")
		lines.append(RETURN_TO_GIVER)
	return "\n".join(lines)


## The window's model (`snapshot`): {"rows": [{"id", "label", "finished"}], "selected_index",
## "selected_id", "details_name", "details_status", "details", "status", "action", "action_label",
## "action_disabled"}. The selection follows `selected_id`, else falls back to the first row.
## `extras` (spec 14.7, 14.8): {"tips": the quest service's `heard_tips()` (newest first), "has_flag":
## Callable(flag) -> bool (the Pearl slots), "war_pages": the war-journal pages found
## (game/quests/war_journal.gd `found_pages`, by number), "war_page_count": how many pages there are}.
static func snapshot(views: Array, selected_id: String, status: String, extras: Dictionary = {}) -> Dictionary:
	var entries := listed(views)
	var tips: Array = extras.get("tips", []) if extras.get("tips") is Array else []
	var after_active := _with_status(views, "active").size()
	if not tips.is_empty():
		entries.insert(after_active, {"quest_id": TIPS_ID, "tips": tips})
		after_active += 1
	var war_pages: Array = extras.get("war_pages", []) if extras.get("war_pages") is Array else []
	var war_count := maxi(int(extras.get("war_page_count", war_pages.size())), war_pages.size())
	if not war_pages.is_empty():
		entries.insert(after_active, {"quest_id": WAR_ID})
	var index := -1
	for position in entries.size():
		if str(entries[position].get("quest_id", "")) == selected_id:
			index = position
			break
	if index < 0 and not entries.is_empty():
		index = 0
	var selected: Dictionary = entries[index] if index >= 0 else {}
	var rows: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if is_tips(entry):
			rows.append({"id": TIPS_ID, "label": "%s %s\n%s" % [MARK_TIP, TIPS_TITLE, TIPS_COUNT % tips.size()],
				"finished": false})
			continue
		if is_war_journal(entry):
			rows.append({"id": WAR_ID, "label": "%s %s\n%s" % [MARK_TIP, WAR_TITLE, WAR_COUNT % [war_pages.size(), war_count]],
				"finished": false})
			continue
		rows.append({
			"id": str(entry.get("quest_id", "")),
			"label": "%s %s\n%s" % [marker(entry), title_of(entry), state_text(entry)],
			"finished": is_finished(entry),
		})
	var action := action_for(selected)
	var name := EMPTY_NAME
	var state := ""
	var page := EMPTY_DETAILS
	if is_tips(selected):
		name = TIPS_TITLE
		state = TIPS_STATE
		page = tips_page(tips)
	elif is_war_journal(selected):
		name = WAR_TITLE
		state = WAR_STATE
		page = war_journal_page(war_pages, war_count)
	elif not selected.is_empty():
		name = title_of(selected)
		state = state_text(selected)
		page = details(selected, extras)
	return {
		"rows": rows,
		"selected_index": index,
		"selected_id": str(selected.get("quest_id", "")),
		"details_name": name,
		"details_status": state,
		"details": page,
		"status": status,
		"action": action,
		"action_label": str(ACTION_LABELS[action]),
		"action_disabled": action.is_empty(),
	}


## True for the Tips row's entry.
static func is_tips(entry: Dictionary) -> bool:
	return str(entry.get("quest_id", "")) == TIPS_ID


## True for the War journal row's entry.
static func is_war_journal(entry: Dictionary) -> bool:
	return str(entry.get("quest_id", "")) == WAR_ID


## The War journal page: every page found, by number ("Page N: <title>" and its lines), then how
## many are still lost.
static func war_journal_page(pages: Array, count: int) -> String:
	var parts: Array[String] = []
	for entry: Variant in pages:
		if not entry is Dictionary:
			continue
		var page_entry: Dictionary = entry
		var lines: Array[String] = [WAR_PAGE_HEADING % [int(page_entry.get("number", 0)), str(page_entry.get("title", ""))]]
		for line: Variant in page_entry.get("lines", []):
			lines.append(str(line))
		parts.append("\n".join(lines))
	var lost := count - pages.size()
	if lost == 1:
		parts.append(WAR_ONE_LOST)
	elif lost > 1:
		parts.append(WAR_MANY_LOST % lost)
	return "\n\n".join(parts)


## The Tips page: one "• <tip>" line per tip with who said it under it, newest first.
static func tips_page(tips: Array) -> String:
	var lines: Array[String] = []
	for tip: Variant in tips:
		if tip is Dictionary:
			lines.append(TIP_LINE % [MARK_TIP, str((tip as Dictionary).get("text", "")), str((tip as Dictionary).get("speaker", ""))])
	return "\n\n".join(lines)


## The main quest's Pearl slots: a heading, then one line per slot (`pearlSlots`, at least the named
## ones): ✓ home (with what the Pearl gives), ▶ won and on its way home, ○ not found yet; the slots
## past the named Pearls are "A Pearl still lost".
static func pearl_lines(definition: Dictionary, has_flag: Callable) -> Array[String]:
	var pearls: Array = definition.get("pearls", []) if definition.get("pearls") is Array else []
	var slots := maxi(int(definition.get("pearlSlots", pearls.size())), pearls.size())
	var home := 0
	var lines: Array[String] = []
	for pearl: Variant in pearls:
		var entry: Dictionary = pearl if pearl is Dictionary else {}
		var pearl_id := str(entry.get("pearlId", ""))
		var pearl_name := str(entry.get("name", pearl_id))
		var gift := str(entry.get("gift", ""))
		if _flag(has_flag, PEARL_HOME_FLAG % pearl_id):
			home += 1
			lines.append((PEARL_HOME % [MARK_DONE, pearl_name, gift]).strip_edges())
		elif _flag(has_flag, PEARL_TAKEN_FLAG % pearl_id):
			lines.append((PEARL_WON % [MARK_CURRENT, pearl_name, gift]).strip_edges())
		else:
			lines.append(PEARL_NOT_FOUND % [MARK_PENDING, pearl_name])
	for _slot in slots - pearls.size():
		lines.append(PEARL_NOT_FOUND % [MARK_PENDING, PEARL_LOST])
	var out: Array[String] = [PEARLS_HEADING % [home, slots]]
	for line in lines:
		out.append(REQUIREMENT_INDENT + line)
	return out


static func _flag(has_flag: Callable, flag: String) -> bool:
	return has_flag.is_valid() and bool(has_flag.call(flag))


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
