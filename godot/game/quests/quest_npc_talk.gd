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
##   this NPC gave plus a "Still to do" line, else the NPC's own lines; the talk is recorded when
##   the box opens. Offers and turn-ins record it only after Accept / Decline / Close.
##
## Owner: quests.

const Services := preload("res://game/shared/services.gd")
const QuestCatalog := preload("res://game/quests/quest_catalog.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")

const Glyphs := preload("res://game/ui/glyphs.gd")
## Phaser "Claim reward  ▸" / "Continue  ▸" (glyphs: game/ui/glyphs.gd).
const TURN_IN_FINISH := "Claim reward  " + Glyphs.NEXT
const OFFER_FINISH := "Continue  " + Glyphs.NEXT
## A refused reoffer: red big text 52 px over the NPC, the NPC released 700 ms later.
const MESSAGE_RISE := 52.0
const MESSAGE_RELEASE_MS := 700.0
const REOFFER_FAILED := "The quest could not be reopened."

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
		pages = QuestCatalog.npc_default_pages(npc_id)
	dialogue.call(&"open", {"speaker": speaker, "pages": pages, "on_closed": release})
	_talked(npc_id)
	return true


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
