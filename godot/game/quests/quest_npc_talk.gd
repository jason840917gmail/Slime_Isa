extends RefCounted
## NPC conversations (Phaser `features/interaction/QuestNpcController.ts` `candidateFor`,
## `converse`, `talked`, `progressLine`; quests spec 5.2-5.5 and 10.5). Owned by the quest service.
##
## `execute(kind, npc)` runs an NPC's interaction: the NPC is locked (it stops and idles) for the
## whole conversation and released when it ends (Escape, ✕, the last window closing, teardown).
## - "turn-in": the quest's `complete` pages ("Claim reward  ▸"), then the turn-in window;
## - "offer": the `offer` pages ("Continue  ▸"), then the offer window;
## - "reoffer": the abandoned quest becomes available again and the offer window opens (no pages);
##   a refusal floats its reason in red over the NPC and releases it after 700 ms;
## - "talk" (and any kind that no longer applies): the progress pages of the first active quest
##   this NPC gave plus a "Still to do" line, else the first of the NPC's `talks` whose conditions
##   hold (quests spec 14.3), else the NPC's own lines; the talk is recorded when the box opens.
##   Offers and turn-ins record it only after Accept / Decline / Close.
##
## **Talks** (Godot, 2026-11-19): an NPC definition in npc-definitions.json may list `talks`, each
## {"id"?, conditions, effects}, checked in order, the first that matches is said:
## - conditions (all must hold; any may be left out): `ifFlags` (every story flag set; `boss:<id>`
##   for a beaten boss), `unlessFlags` (none of them set), `ifItems` ({item id: count} all in the
##   bag), `ifAbilities` / `unlessAbilities` (learned / not learned, RunState `learned_ability_ids`),
##   `ifRecipes` / `unlessRecipes` (known / not known, RunState `knows_recipe`: Dora skips her basket
##   lesson when the sally port's recipe page taught it);
## - effects: `pages` (said first, one to three lines a page), then, once they end (read to the end or
##   closed), the bag's `takeItems` and `giveItems` ({item id: count}) in one all-or-nothing
##   transaction (`RunState.transact_items`; when it does not fit nothing below happens and
##   `refusedPages` are said, else REFUSED_PAGE), `setFlags`, `learnRecipes` (recipe ids, a toast per
##   new one), `tip` ({"id", "text"}: heard for good, listed in the journal's Tips, a toast the first
##   time), and last `learnAbility` (an ability id: `RunState.learn_ability`, whose ceremony
##   QuestNotifications plays); `pagesAfter` are said once the ceremony is over (only when `pages`
##   were read to the end).
## Effects run each time the talk is chosen: a one-time lesson or gift names a flag in `unlessFlags`
## and sets it in `setFlags` (a recipe or an ability already known is not learned again).
##
## Owner: quests.

const Services := preload("res://game/shared/services.gd")
const QuestCatalog := preload("res://game/quests/quest_catalog.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
## Waiting out an ability's ceremony before `pagesAfter` (the prologue's own helper).
const PrologueScene := preload("res://game/prologue/prologue_scene.gd")

const Glyphs := preload("res://game/ui/glyphs.gd")
## Phaser "Claim reward  ▸" / "Continue  ▸" (glyphs: game/ui/glyphs.gd).
const TURN_IN_FINISH := "Claim reward  " + Glyphs.NEXT
const OFFER_FINISH := "Continue  " + Glyphs.NEXT
## A refused reoffer: red big text 52 px over the NPC, the NPC released 700 ms later.
const MESSAGE_RISE := 52.0
const MESSAGE_RELEASE_MS := 700.0
const REOFFER_FAILED := "The quest could not be reopened."
## A talk whose items do not fit (or are not all there) and has no `refusedPages` of its own.
const REFUSED_PAGE := "Oh, your bag is too full for this. Make a little room and come back!"
## Toasts over the slime for what a talk gave.
const RECIPE_TOAST := "New recipe: %s"
const TIP_TOAST := "A new tip in your journal"
const GIVE_TOAST := "+ %s"
const TAKE_TOAST := "- %s"

## The quest service (quest_service.gd), typed loosely to avoid a preload cycle.
var _service: Node
## Releases waiting for their 700 ms timer (run at once on teardown).
var _pending: Array[Callable] = []


func _init(service: Node) -> void:
	_service = service


func execute(kind: String, npc: Node) -> bool:
	if npc == null or not is_instance_valid(npc):
		return false
	var npc_id := str(npc.get(&"npc_definition_id"))
	var speaker := QuestCatalog.npc_name(npc_id)
	var release: Callable = npc.call(&"acquire_interaction_lock") if npc.has_method(&"acquire_interaction_lock") else func() -> void: pass
	var dialogue: Node = _service.get(&"dialogue")
	var offer_window: Node = _service.get(&"offer_window")
	match kind:
		"turn-in":
			var turn_ins: Array[Dictionary] = _service.call(&"turn_ins_for_npc", npc_id)
			if not turn_ins.is_empty():
				var quest_id := str(turn_ins[0]["quest_id"])
				_converse(speaker, _pages(turn_ins[0], "complete"), TURN_IN_FINISH, release,
					func() -> void: offer_window.call(&"open_turn_in", quest_id, npc_id, _talked.bind(npc_id), release))
				return true
		"offer":
			var offers: Array[Dictionary] = _service.call(&"offers_for_npc", npc_id)
			if not offers.is_empty():
				var offered_id := str(offers[0]["quest_id"])
				_converse(speaker, _pages(offers[0], "offer"), OFFER_FINISH, release,
					func() -> void: offer_window.call(&"open_offer", offered_id, npc_id, _talked.bind(npc_id), release))
				return true
		"reoffer":
			var reoffers: Array[Dictionary] = _service.call(&"reoffers_for_npc", npc_id)
			if not reoffers.is_empty():
				var reoffered_id := str(reoffers[0]["quest_id"])
				var result: Dictionary = _service.call(&"reoffer", reoffered_id, npc_id)
				if bool(result.get("ok", false)):
					offer_window.call(&"open_offer", reoffered_id, npc_id, _talked.bind(npc_id), release)
				else:
					_temporary_message(npc, str(result.get("reason", REOFFER_FAILED)), release)
				return true
	# Plain talk.
	var waiting: Dictionary = _service.call(&"active_quest_from", npc_id)
	var pages: Array = []
	if not waiting.is_empty():
		pages = _pages(waiting, "progress")
		pages.append(progress_line(waiting))
	else:
		var said := matching_talk(npc_id)
		if not said.is_empty():
			_say_talk(speaker, said, release)
			_talked(npc_id)
			return true
		pages = QuestCatalog.npc_default_pages(npc_id)
	dialogue.call(&"open", {"speaker": speaker, "pages": pages, "on_closed": release})
	_talked(npc_id)
	return true


# --- talks (spec 14.3) ----------------------------------------------------------------------------

## The first of the NPC's talks whose conditions hold now, {} when none does.
static func matching_talk(npc_id: String) -> Dictionary:
	var run := Services.run()
	if run == null:
		return {}
	for entry: Variant in QuestCatalog.npc_talks(npc_id):
		if entry is Dictionary and talk_matches(entry, run):
			return entry
	return {}


## True when the talk the NPC would give now has a tip not heard yet (the gold "!", spec 14.5).
static func has_unheard_tip(npc_id: String) -> bool:
	var tip_id := talk_tip_id(matching_talk(npc_id))
	var run := Services.run()
	return not tip_id.is_empty() and run != null and not run.has_heard_tip(tip_id)


## The tip id a talk gives ("" when none).
static func talk_tip_id(entry: Dictionary) -> String:
	var given: Variant = entry.get("tip")
	return str((given as Dictionary).get("id", "")) if given is Dictionary else ""


## Every condition of `entry` holds on `run`.
static func talk_matches(entry: Dictionary, run: Object) -> bool:
	for flag: String in QuestCatalog.ids(entry, "ifFlags"):
		if not _flag_holds(run, flag):
			return false
	for flag: String in QuestCatalog.ids(entry, "unlessFlags"):
		if _flag_holds(run, flag):
			return false
	for ability_id: String in QuestCatalog.ids(entry, "ifAbilities"):
		if not bool(run.call(&"has_learned_ability", ability_id)):
			return false
	for ability_id: String in QuestCatalog.ids(entry, "unlessAbilities"):
		if bool(run.call(&"has_learned_ability", ability_id)):
			return false
	for item: Dictionary in _item_list(entry.get("ifItems")):
		if int(run.call(&"item_count", str(item["item_id"]))) < int(item["count"]):
			return false
	for recipe_id: String in QuestCatalog.ids(entry, "ifRecipes"):
		if not bool(run.call(&"knows_recipe", recipe_id)):
			return false
	for recipe_id: String in QuestCatalog.ids(entry, "unlessRecipes"):
		if bool(run.call(&"knows_recipe", recipe_id)):
			return false
	return true


## A story flag, or `boss:<id>` for a beaten boss (as the quests' world-flag conditions).
static func _flag_holds(run: Object, flag: String) -> bool:
	if bool(run.call(&"has_flag", flag)):
		return true
	return flag.begins_with("boss:") and bool(run.call(&"is_boss_defeated", flag.substr(5)))


## {item id: count} -> [{"item_id", "count"}] (counts above 0 only).
static func _item_list(source: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if source is Dictionary:
		for key: Variant in source:
			var count := int(source[key])
			if count > 0:
				out.append({"item_id": str(key), "count": count})
	return out


## A talk's pages of `key` ("pages", "pagesAfter", "refusedPages"), [] when none.
static func _talk_pages(entry: Dictionary, key: String) -> Array:
	return (entry[key] as Array).duplicate() if entry.get(key) is Array else []


## Says the talk's pages, then gives what it gives (`_finish_talk`).
func _say_talk(speaker: String, entry: Dictionary, release: Callable) -> void:
	var pages := _talk_pages(entry, "pages")
	if pages.is_empty():
		_finish_talk(speaker, entry, release, true)
		return
	var dialogue: Node = _service.get(&"dialogue")
	dialogue.call(&"open", {"speaker": speaker, "pages": pages,
		"on_finished": _finish_talk.bind(speaker, entry, release, true),
		"on_closed": _finish_talk.bind(speaker, entry, release, false)})


## The pages ended (`finished`: read to the end): the effects, then `pagesAfter` once the ceremony of
## an ability it taught is over; the NPC is released at the end (a coroutine).
func _finish_talk(speaker: String, entry: Dictionary, release: Callable, finished: bool) -> void:
	var outcome := apply_talk(entry)
	var dialogue: Node = _service.get(&"dialogue")
	if not bool(outcome["ok"]):
		var refused := _talk_pages(entry, "refusedPages")
		if refused.is_empty():
			refused = [REFUSED_PAGE]
		dialogue.call(&"open", {"speaker": speaker, "pages": refused, "on_finished": release, "on_closed": release})
		return
	var after := _talk_pages(entry, "pagesAfter")
	if bool(outcome["learned"]):
		await PrologueScene.ceremony_done(_service.get_tree() if _service.is_inside_tree() else null)
	if finished and not after.is_empty() and is_instance_valid(dialogue):
		dialogue.call(&"open", {"speaker": speaker, "pages": after, "on_finished": release, "on_closed": release})
		return
	if release.is_valid():
		release.call()


## Gives what a talk gives (spec 14.3, in this order): the items (all or nothing), the flags, the
## recipes, the tip, then the ability. Returns {"ok": false} (nothing given) when the items do not
## fit or are not all in the bag, else {"ok": true, "learned": the ability was new}.
func apply_talk(entry: Dictionary) -> Dictionary:
	var run := Services.run()
	if run == null:
		return {"ok": true, "learned": false}
	var removals := _item_list(entry.get("takeItems"))
	var additions := _item_list(entry.get("giveItems"))
	if not removals.is_empty() or not additions.is_empty():
		if not run.transact_items(removals, additions, true) or not run.transact_items(removals, additions):
			return {"ok": false, "learned": false}
		for item: Dictionary in removals:
			_announce(TAKE_TOAST % _item_text(item), &"white", false)
		for item: Dictionary in additions:
			_announce(GIVE_TOAST % _item_text(item), &"green", true)
	for flag: String in QuestCatalog.ids(entry, "setFlags"):
		run.set_flag(flag)
	for recipe_id: String in run.learn_recipes(QuestCatalog.ids(entry, "learnRecipes")):
		_announce(RECIPE_TOAST % QuestCatalog.recipe_name(recipe_id), &"green", true)
	var tip_id := talk_tip_id(entry)
	if not tip_id.is_empty() and run.hear_tip(tip_id):
		_announce(TIP_TOAST, &"yellow", false)
	var ability_id := str(entry.get("learnAbility", ""))
	var learned := not ability_id.is_empty() and run.learn_ability(ability_id)
	return {"ok": true, "learned": learned}


## "<n>× Name" (just the name for one).
static func _item_text(item: Dictionary) -> String:
	var count := int(item["count"])
	var name := ItemCatalog.item_name(str(item["item_id"]))
	return "%d× %s" % [count, name] if count > 1 else name


func _announce(text: String, color: StringName, big: bool) -> void:
	var notifications: Object = _service.get(&"notifications")
	if notifications != null and notifications.has_method(&"announce"):
		notifications.call(&"announce", text, color, big)


## `progressLine`: what the giver still waits for, one "•" line per unfinished objective of the
## current stage (raw labels, count always shown).
static func progress_line(quest: Dictionary) -> String:
	var definition: Dictionary = quest.get("definition", {})
	var title := str(definition.get("title", quest.get("quest_id", "")))
	var stage_definition := QuestCatalog.stage(definition, str(quest.get("active_stage_id", "")))
	var progress: Dictionary = quest.get("progress", {})
	var remaining := PackedStringArray()
	for objective: Dictionary in QuestCatalog.objectives(stage_definition):
		var done := int(progress.get(str(objective["id"]), 0))
		if done < int(objective["target"]):
			remaining.append("• %s (%d/%d)" % [str(objective.get("label", "")), done, int(objective["target"])])
	if remaining.is_empty():
		return "\"%s\" — come back to me when you're ready." % title
	return "Still to do for \"%s\":\n%s" % [title, "\n".join(remaining)]


## Runs every release still waiting for its timer (teardown).
func release_pending() -> void:
	var pending := _pending.duplicate()
	_pending.clear()
	for release: Callable in pending:
		if release.is_valid():
			release.call()


## `converse`: the pages first, then the decision window; Escape during the pages ends the
## conversation without a decision. No pages: the decision at once.
func _converse(speaker: String, pages: Array, finish_label: String, release: Callable, decide: Callable) -> void:
	if pages.is_empty():
		decide.call()
		return
	var dialogue: Node = _service.get(&"dialogue")
	dialogue.call(&"open", {"speaker": speaker, "pages": pages, "finish_label": finish_label,
		"on_finished": decide, "on_closed": release})


## `talked`: remember the talk and tell the quests (and the NpcBlip cue) about it.
func _talked(npc_id: String) -> void:
	var run := Services.run()
	if run != null:
		run.record_talk(npc_id)
	_service.emit_signal(&"npc_talked", {"npcId": npc_id})
	_service.call(&"handle_event", QuestEvents.NPC_TALKED, {"npcId": npc_id})


## The quest's dialogue pages of `key` ("offer", "progress", "complete"), [] when none.
static func _pages(quest: Dictionary, key: String) -> Array:
	var definition: Dictionary = quest.get("definition", {})
	var dialogue: Variant = definition.get("dialogue")
	if dialogue is Dictionary and (dialogue as Dictionary).get(key) is Array:
		return ((dialogue as Dictionary)[key] as Array).duplicate()
	return []


## `showTemporaryMessage`: the reason floats over the NPC; the NPC is released 700 ms later (a
## timer that runs through the pause).
func _temporary_message(npc: Node, text: String, release: Callable) -> void:
	var feel := Services.feel()
	if feel != null and npc.has_method(&"get_phaser_position"):
		feel.floating_text((npc.call(&"get_phaser_position") as Vector2) - Vector2(0.0, MESSAGE_RISE), text, &"red", true)
	_pending.append(release)
	var tree := _service.get_tree()
	if tree == null:
		release_pending()
		return
	var timer := tree.create_timer(MESSAGE_RELEASE_MS / 1000.0, true)
	timer.timeout.connect(func() -> void:
		if release in _pending:
			_pending.erase(release)
			release.call())
