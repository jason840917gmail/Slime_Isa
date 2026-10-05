extends Node
## The quest service (Phaser `quests/QuestService.ts` + `QuestEventBridge.ts` + the quest half of
## `features/interaction/QuestNpcController.ts`; quests spec 2, 5 and 10). Child "Quests" of main,
## made once in main's `_ready` and kept across worlds; group "quests". It holds no state of its
## own: the records live in `RunState.quests` (one per quest, catalogue order, snake_case, saved
## with the run), and the known facts are RunState reads (discovered areas, talked NPCs, defeated
## bosses, story flags).
##
## Flow: main calls `on_world_built(map_id)` at the end of every world build (the first call
## creates the 14 locked records and evaluates the prerequisites, later calls re-evaluate; then
## `area.enter`). World scripts send input events with `QuestEvents.emit(event, payload)`, which
## lands in `handle_event` (the event bridge). The service itself forwards the boss camps'
## `boss_defeated`, the game windows' `window_opened` and the Shell's `menu_opened` (as
## `control.used`), and watches the slime for the sprint edge (`control.used sprint`). Every change
## emits `quest_changed` and `RunState.notify_quests_changed` (HUD, markers, autosave).
##
## Commands return {"ok": true, "state"} or {"ok": false, "code", "reason"}; a reward that does not
## fit in the bag is such a failure ("reward-items"), never an exception, and changes nothing.
##
## It owns the NPC conversations (`QuestNpcTalk`), the toasts and banners (`QuestNotifications`),
## and the dialogue box and quest offer window, which it adds to main's GameWindows.
##
## Owner: quests.

const Services := preload("res://game/shared/services.gd")
const QuestCatalog := preload("res://game/quests/quest_catalog.gd")
const QuestObjectives := preload("res://game/quests/quest_objectives.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")
const QuestNpcTalk := preload("res://game/quests/quest_npc_talk.gd")
const QuestNotifications := preload("res://game/quests/quest_notifications.gd")
const DialogueBox := preload("res://game/ui/screens/dialogue_box.gd")
const QuestOfferWindow := preload("res://game/ui/screens/quest_offer_window.gd")
const DIALOGUE_SCENE := preload("res://game/ui/screens/dialogue_box.tscn")
const OFFER_SCENE := preload("res://game/ui/screens/quest_offer_window.tscn")

const GROUP := &"quests"
const GAME_WINDOWS_GROUP := &"game_windows"
## QuestNpcController.ts:130-210.
const PRIORITY_TURN_IN := 100
const PRIORITY_OFFER := 90
const PRIORITY_REOFFER := 85
const PRIORITY_TALK := 50
## MENU_CONTROL_IDS (WorldScene.ts:141-147): a window that opens -> the `control.used` id.
const MENU_CONTROL_IDS := {
	&"inventory": "menu:inventory",
	&"crafting": "menu:crafting",
	&"quest-journal": "menu:journal",
	&"world-map": "menu:map",
	&"pause-menu": "pause",
}
## Dev launch option `--quest=<id>[:<stage>]` (`?quest=` on the web): owner decision Q3.
const LAUNCH_OPTION := "quest"
const REWARD_ITEMS_REASON := "Could not grant all reward items for quest '%s'."
const CUE_ABILITY_LEARNED := &"AbilityLearned"
const MOVE_ACTIONS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right"]

## {"questId", "source": "npc"|"condition"}
signal quest_available(payload: Dictionary)
## {"questId", "source": "npc"|"automatic"|"debug"}
signal quest_accepted(payload: Dictionary)
## {"questId", "stageId", "objectiveId", "before", "after"}
signal quest_progressed(payload: Dictionary)
## {"questId", "stageId"}
signal quest_stage_completed(payload: Dictionary)
## {"questId", "title", "rewards"}
signal quest_completed(payload: Dictionary)
## {"questId", "reason"}
signal quest_failed(payload: Dictionary)
## {"questId"}
signal quest_abandoned(payload: Dictionary)
## {"questId"}: after every change to a record (tracker, markers, autosave).
signal quest_changed(payload: Dictionary)
## {"npcId"}: a talk was recorded (NpcBlip).
signal npc_talked(payload: Dictionary)

var notifications: QuestNotifications
var talk: QuestNpcTalk
var dialogue: DialogueBox
var offer_window: QuestOfferWindow

## The RunState.quests array the index was built for (rebound when new_run/install replace it).
var _bound: Variant = null
## quest id -> position in RunState.quests.
var _index: Dictionary = {}
var _launch_option_applied: bool = false
## Sprinting while moving on the last played step (the `control.used sprint` edge).
var _sprinting: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	notifications = QuestNotifications.new(self)
	talk = QuestNpcTalk.new(self)
	_mount_windows()
	var shell := Services.shell()
	if shell != null and not shell.menu_opened.is_connected(_on_menu_opened):
		shell.menu_opened.connect(_on_menu_opened)
	var windows := get_tree().get_first_node_in_group(GAME_WINDOWS_GROUP)
	if windows != null and windows.has_signal(&"window_opened") and not windows.is_connected(&"window_opened", _on_menu_opened):
		windows.connect(&"window_opened", _on_menu_opened)
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	var shell := Services.shell()
	if shell != null and shell.menu_opened.is_connected(_on_menu_opened):
		shell.menu_opened.disconnect(_on_menu_opened)
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if talk != null:
		talk.release_pending()
	if notifications != null:
		notifications.disconnect_all()


## The sprint tutorial (`updateControlHints`, WorldScene.ts:612-624): sprinting while moving, as it
## starts, is `control.used sprint`. Runs only while the game plays (this node pauses with the
## tree) and the slime is alive and awake; otherwise the edge is kept as it was.
func _physics_process(_delta: float) -> void:
	var world := Services.world()
	var player: Variant = world.player if world != null else null
	if player == null or not is_instance_valid(player) or not (player as Node).is_inside_tree():
		return
	var slime := player as Node
	if bool(slime.call(&"is_dead")) or bool(slime.call(&"is_sleeping")):
		return
	var moving := false
	for action: StringName in MOVE_ACTIONS:
		moving = moving or bool(slime.call(&"is_action_held", action))
	var sprinting := moving and bool(slime.call(&"is_action_held", &"sprint"))
	if sprinting and not _sprinting:
		handle_event(QuestEvents.CONTROL_USED, {"controlId": "sprint"})
	_sprinting = sprinting


## The dialogue box and the offer window, as children of main's GameWindows.
func _mount_windows() -> void:
	var windows := get_tree().get_first_node_in_group(GAME_WINDOWS_GROUP)
	dialogue = DIALOGUE_SCENE.instantiate() as DialogueBox
	offer_window = OFFER_SCENE.instantiate() as QuestOfferWindow
	offer_window.service = self
	if windows != null and windows.has_method(&"add_window"):
		windows.call(&"add_window", dialogue)
		windows.call(&"add_window", offer_window)
	else:
		add_child(dialogue)
		add_child(offer_window)


# --- world hooks ----------------------------------------------------------------------------------

## main.gd, after every world build: the first call starts the run's quests (locked records,
## prerequisites, the `quest` launch option), later calls re-evaluate; then `area.enter`.
func on_world_built(map_id: String) -> void:
	_records()
	_connect_camps()
	evaluate_prerequisites()
	if not _launch_option_applied:
		_launch_option_applied = true
		_apply_launch_option()
	handle_event(QuestEvents.AREA_ENTER, {"areaId": map_id})


## `start()`: the locked records when the run has none, then the prerequisites.
func start() -> void:
	_records()
	evaluate_prerequisites()


## World teardown: closes the offer window and the dialogue box (their `on_closed` release the
## NPC locks) and runs pending releases.
func close_conversations() -> void:
	if offer_window != null:
		offer_window.close()
	if dialogue != null:
		dialogue.close()
	if talk != null:
		talk.release_pending()


func _connect_camps() -> void:
	for camp: Node in get_tree().get_nodes_in_group(&"boss_camp"):
		_connect_camp(camp)


func _on_node_added(node: Node) -> void:
	if node.has_signal(&"boss_defeated"):
		_connect_camp(node)


func _connect_camp(camp: Node) -> void:
	if camp.has_signal(&"boss_defeated") and not camp.is_connected(&"boss_defeated", _on_boss_defeated):
		camp.connect(&"boss_defeated", _on_boss_defeated)


## A camp's `boss_defeated({campId, bossId})` (the camp already recorded the defeat).
func _on_boss_defeated(payload: Dictionary) -> void:
	handle_event(QuestEvents.BOSS_DEFEATED, {"bossId": str(payload.get("bossId", ""))})


## A game window or a Shell window opened: the tutorial's `control.used`.
func _on_menu_opened(surface_id: StringName) -> void:
	if MENU_CONTROL_IDS.has(surface_id):
		handle_event(QuestEvents.CONTROL_USED, {"controlId": MENU_CONTROL_IDS[surface_id]})


func _apply_launch_option() -> void:
	var main := get_parent()
	if main == null or not main.has_method(&"launch_option"):
		return
	var option := str(main.call(&"launch_option", LAUNCH_OPTION))
	if option.is_empty():
		return
	var parts := option.split(":", false, 1)
	var quest_id := parts[0].strip_edges() if parts.size() > 0 else ""
	var stage_id := parts[1].strip_edges() if parts.size() > 1 else ""
	if not QuestCatalog.has(quest_id):
		push_warning("QuestService: the quest launch option names no quest ('%s')" % option)
		return
	if not stage_id.is_empty() and QuestCatalog.stage_index(QuestCatalog.definition(quest_id), stage_id) < 0:
		push_warning("QuestService: quest '%s' has no stage '%s'" % [quest_id, stage_id])
		return
	print("QuestService: launch option activates '%s'%s" % [quest_id, (" at " + stage_id) if not stage_id.is_empty() else ""])
	debug_activate(quest_id, stage_id)


# --- the state machine (QuestService.ts) ----------------------------------------------------------

## `evaluatePrerequisites`: one pass in catalogue order (later quests see earlier changes).
func evaluate_prerequisites() -> void:
	_records()
	for quest: Dictionary in QuestCatalog.definitions():
		var record := _record(str(quest["id"]))
		if record.is_empty() or str(record["status"]) != "locked" or not _prerequisites_met(quest):
			continue
		if str((quest["acquisition"] as Dictionary).get("kind", "")) == "automatic":
			_activate(record, quest, "automatic")
		else:
			record["status"] = "available"
			quest_available.emit({"questId": record["quest_id"], "source": "condition"})
			_changed(record)


## The event bridge (`handleEvent`): records the fact, evaluates, advances the current stage of
## every active quest, evaluates again.
func handle_event(event: StringName, payload: Dictionary) -> void:
	var run := Services.run()
	if run == null:
		return
	_records()
	if event == QuestEvents.NPC_TALKED:
		run.record_talk(str(payload.get("npcId", "")))
	elif event == QuestEvents.AREA_ENTER:
		run.mark_area_discovered(str(payload.get("areaId", "")))
	elif event == QuestEvents.BOSS_DEFEATED:
		var boss_id := str(payload.get("bossId", ""))
		var defeated: Array = run.world.get_or_add("defeated_boss_ids", [])
		if not boss_id.is_empty() and not boss_id in defeated:
			defeated.append(boss_id)
	evaluate_prerequisites()
	var active_ids: Array[String] = []
	for record: Dictionary in _records():
		if str(record["status"]) == "active":
			active_ids.append(str(record["quest_id"]))
	for quest_id in active_ids:
		var record := _record(quest_id)
		var quest := QuestCatalog.definition(quest_id)
		var stage_definition := QuestCatalog.stage(quest, str(record.get("active_stage_id", "")))
		if stage_definition.is_empty():
			continue
		var stage_id := str(stage_definition["id"])
		var progressed := false
		for objective: Dictionary in QuestCatalog.objectives(stage_definition):
			var result := QuestObjectives.match_objective(objective, event, payload, record["consumed_fact_ids"])
			if not bool(result["matched"]) or int(result["amount"]) <= 0:
				continue
			var fact_id := str(result["fact_id"])
			if not fact_id.is_empty():
				var facts := _consumed(record, str(objective["id"]))
				if fact_id in facts:
					continue
				facts.append(fact_id)
			progressed = _increment(record, quest, stage_id, str(objective["id"]), int(result["amount"])) or progressed
		if progressed:
			_try_complete_stage(record, quest, stage_id)
	evaluate_prerequisites()


func _prerequisites_met(quest: Dictionary) -> bool:
	for condition: Variant in quest.get("prerequisites", []):
		if not condition is Dictionary or not _condition_met(condition):
			return false
	return true


## `conditionSatisfied` over RunState's facts.
func _condition_met(condition: Dictionary) -> bool:
	var run := Services.run()
	match str(condition.get("kind", "")):
		"quest-status":
			return status(str(condition.get("questId", ""))) == str(condition.get("status", ""))
		"area-entered":
			for area_id: String in QuestCatalog.ids(condition, "areaIds"):
				if run.is_area_discovered(area_id):
					return true
			return false
		"inventory-count":
			return run.item_count(str(condition.get("itemId", ""))) >= int(condition.get("minimumCount", 0))
		"world-flag":
			return _world_flag(str(condition.get("flagId", "")))
		"npc-talked":
			for npc_id: String in QuestCatalog.ids(condition, "npcIds"):
				if run.has_talked_to(npc_id):
					return true
			return false
	return false


## A story flag, or `boss:<id>` for a defeated boss (Phaser's world-flag set).
func _world_flag(flag: String) -> bool:
	var run := Services.run()
	if run.has_flag(flag):
		return true
	return flag.begins_with("boss:") and run.is_boss_defeated(flag.substr(5))


## `activate`: active at the first stage, accepted, then the known facts of the first stage only.
func _activate(record: Dictionary, quest: Dictionary, source: String) -> void:
	var first := QuestCatalog.first_stage(quest)
	record["status"] = "active"
	record["active_stage_id"] = str(first.get("id", ""))
	record["accepted_at"] = _now_epoch_ms()
	_init_progress(record, first)
	quest_accepted.emit({"questId": record["quest_id"], "source": source})
	_changed(record)
	_apply_known_facts(record, quest)


## `applyKnownFacts` (spec 2.3): areas discovered, NPCs talked to, bosses defeated, for the
## objectives of the current (first) stage.
func _apply_known_facts(record: Dictionary, quest: Dictionary) -> void:
	var run := Services.run()
	var stage_definition := QuestCatalog.stage(quest, str(record.get("active_stage_id", "")))
	if stage_definition.is_empty():
		return
	var stage_id := str(stage_definition["id"])
	for objective: Dictionary in QuestCatalog.objectives(stage_definition):
		var facts: Array[String] = []
		match str(objective.get("kind", "")):
			"discover-area":
				for area_id: String in QuestCatalog.ids(objective, "areaIds"):
					if run.is_area_discovered(area_id):
						facts.append(area_id)
			"talk-to-npc":
				for npc_id: String in QuestCatalog.ids(objective, "npcIds"):
					if run.has_talked_to(npc_id):
						facts.append(npc_id)
			"defeat-boss":
				for boss_id: String in QuestCatalog.ids(objective, "bossIds"):
					if _world_flag("boss:" + boss_id):
						facts.append(boss_id)
		for fact_id in facts:
			var consumed := _consumed(record, str(objective["id"]))
			if fact_id in consumed:
				continue
			consumed.append(fact_id)
			_increment(record, quest, stage_id, str(objective["id"]), 1)
	_try_complete_stage(record, quest, stage_id)


## `increment`: capped at the target; false (and no event) when nothing changed.
func _increment(record: Dictionary, quest: Dictionary, stage_id: String, objective_id: String, amount: int) -> bool:
	var objective := {}
	for entry: Dictionary in QuestCatalog.objectives(QuestCatalog.stage(quest, stage_id)):
		if str(entry["id"]) == objective_id:
			objective = entry
	if objective.is_empty():
		return false
	var progress: Dictionary = record["progress"]
	var before := int(progress.get(objective_id, 0))
	var after := mini(int(objective["target"]), before + amount)
	if after <= before:
		return false
	progress[objective_id] = after
	quest_progressed.emit({"questId": record["quest_id"], "stageId": stage_id, "objectiveId": objective_id,
		"before": before, "after": after})
	_changed(record)
	return true


## `tryCompleteStage`: the next stage, or (last stage) ready to turn in / completed.
func _try_complete_stage(record: Dictionary, quest: Dictionary, stage_id: String) -> void:
	if str(record["status"]) != "active" or str(record.get("active_stage_id", "")) != stage_id:
		return
	var stage_definition := QuestCatalog.stage(quest, stage_id)
	if stage_definition.is_empty():
		return
	var progress: Dictionary = record["progress"]
	for objective: Dictionary in QuestCatalog.objectives(stage_definition):
		if int(progress.get(str(objective["id"]), 0)) < int(objective["target"]):
			return
	quest_stage_completed.emit({"questId": record["quest_id"], "stageId": stage_id})
	var stage_list := QuestCatalog.stages(quest)
	var index := QuestCatalog.stage_index(quest, stage_id)
	if index < 0 or index == stage_list.size() - 1:
		if str((quest["completion"] as Dictionary).get("kind", "")) == "automatic":
			_complete(record, quest)
		else:
			_changed(record)
		return
	var next: Dictionary = stage_list[index + 1]
	record["active_stage_id"] = str(next["id"])
	_init_progress(record, next)
	_changed(record)


## `complete`: rewards (once), completed, `quest_completed`, then the follow-up quests. Returns ""
## or the reason the rewards could not be granted (nothing changed then).
func _complete(record: Dictionary, quest: Dictionary) -> String:
	if str(record["status"]) == "completed":
		return ""
	var rewards: Dictionary = quest.get("rewards", {}) if quest.get("rewards") is Dictionary else {}
	if not bool(record.get("rewards_granted", false)):
		var refused := _grant(str(record["quest_id"]), rewards)
		if not refused.is_empty():
			return refused
		record["rewards_granted"] = true
	record["status"] = "completed"
	record["active_stage_id"] = ""
	record["completed_at"] = _now_epoch_ms()
	quest_completed.emit({"questId": record["quest_id"], "title": str(quest.get("title", record["quest_id"])),
		"rewards": rewards.duplicate(true)})
	_changed(record)
	evaluate_prerequisites()
	return ""


## `defaultRewards.grant` in Phaser's order: items (all or nothing, checked together first),
## recipes, abilities (AbilityLearned per new one), flags, coins.
func _grant(quest_id: String, rewards: Dictionary) -> String:
	var run := Services.run()
	var additions: Array = []
	for item: Variant in rewards.get("items", []):
		if item is Dictionary:
			additions.append({"item_id": str(item.get("itemId", "")), "count": int(item.get("count", 0))})
	if not additions.is_empty():
		if not run.transact_items([], additions, true) or not run.transact_items([], additions):
			return REWARD_ITEMS_REASON % quest_id
	var recipe_ids := QuestCatalog.ids(rewards, "recipeIds")
	if not recipe_ids.is_empty():
		run.learn_recipes(recipe_ids)
	for ability_id: String in QuestCatalog.ids(rewards, "abilityIds"):
		if run.learn_ability(ability_id):
			var feel := Services.feel()
			if feel != null:
				feel.audio_cue(CUE_ABILITY_LEARNED)
	for flag: String in QuestCatalog.ids(rewards, "flags"):
		run.set_flag(flag)
	var coins := int(rewards.get("coins", 0))
	if coins != 0:
		run.add_coins(coins)
	return ""


## `resetForRetry` (spec 2.8): "quest" starts over; "current-stage" drops the progress and facts of
## the resume stage (else the first unfinished one, else the first) and resumes there.
func _reset_for_retry(record: Dictionary, quest: Dictionary, reset: String) -> void:
	if reset == "quest":
		record["progress"] = {}
		record["consumed_fact_ids"] = {}
		var first := QuestCatalog.first_stage(quest)
		_init_progress(record, first)
		record["active_stage_id"] = str(first.get("id", ""))
	else:
		var stage_id := str(record.get("resume_stage_id", ""))
		if stage_id.is_empty():
			var progress: Dictionary = record["progress"]
			for stage_definition: Dictionary in QuestCatalog.stages(quest):
				for objective: Dictionary in QuestCatalog.objectives(stage_definition):
					if stage_id.is_empty() and int(progress.get(str(objective["id"]), 0)) < int(objective["target"]):
						stage_id = str(stage_definition["id"])
		var resumed := QuestCatalog.stage(quest, stage_id)
		if resumed.is_empty():
			resumed = QuestCatalog.first_stage(quest)
		var dropped := {}
		for objective: Dictionary in QuestCatalog.objectives(resumed):
			dropped[str(objective["id"])] = true
		for key: Variant in (record["progress"] as Dictionary).keys():
			if dropped.has(str(key)):
				(record["progress"] as Dictionary).erase(key)
		for key: Variant in (record["consumed_fact_ids"] as Dictionary).keys():
			if dropped.has(str(key)):
				(record["consumed_fact_ids"] as Dictionary).erase(key)
		record["active_stage_id"] = str(resumed.get("id", ""))
		_init_progress(record, resumed)
	for key: String in ["failed_at", "failure_reason", "abandoned_at", "completed_at", "resume_stage_id"]:
		record.erase(key)
	record["rewards_granted"] = false


# --- commands -------------------------------------------------------------------------------------

## `accept` (spec 2.8): an available NPC quest from one of its givers becomes active.
func accept(quest_id: String, npc_id: String) -> Dictionary:
	var record := _record(quest_id)
	var quest := QuestCatalog.definition(quest_id)
	if record.is_empty() or quest.is_empty():
		return _failure("unknown-quest", "Unknown quest '%s'." % quest_id)
	if str(record["status"]) == "active":
		return _success(record)
	if str(record["status"]) != "available" or not _npc_listed(quest, "acquisition", npc_id):
		return _failure("invalid-status", "Quest '%s' is not available from NPC '%s'." % [quest_id, npc_id])
	_activate(record, quest, "npc")
	return _success(record)


## `decline`: the same checks as accept, and no change.
func decline(quest_id: String, npc_id: String) -> Dictionary:
	var record := _record(quest_id)
	var quest := QuestCatalog.definition(quest_id)
	if record.is_empty() or quest.is_empty():
		return _failure("unknown-quest", "Unknown quest '%s'." % quest_id)
	if str(record["status"]) != "available" or not _npc_listed(quest, "acquisition", npc_id):
		return _failure("invalid-status", "Quest '%s' is not available from NPC '%s'." % [quest_id, npc_id])
	return _success(record)


## `turnIn`: a ready npc-turn-in quest completes (rewards first; a full bag refuses it).
func turn_in(quest_id: String, npc_id: String) -> Dictionary:
	var record := _record(quest_id)
	var quest := QuestCatalog.definition(quest_id)
	if record.is_empty() or quest.is_empty():
		return _failure("unknown-quest", "Unknown quest '%s'." % quest_id)
	if str(record["status"]) != "active" or not _npc_listed(quest, "completion", npc_id):
		return _failure("wrong-npc", "Quest '%s' cannot be turned in to NPC '%s'." % [quest_id, npc_id])
	if not bool(view(quest_id).get("ready_to_turn_in", false)):
		return _failure("not-ready", "Quest '%s' is not ready to turn in." % quest_id)
	var refused := _complete(record, quest)
	if not refused.is_empty():
		return _failure("reward-items", refused)
	return _success(record)


func abandon(quest_id: String) -> Dictionary:
	var record := _record(quest_id)
	var quest := QuestCatalog.definition(quest_id)
	if record.is_empty() or quest.is_empty():
		return _failure("unknown-quest", "Unknown quest '%s'." % quest_id)
	if str(record["status"]) != "active":
		return _failure("invalid-status", "Quest '%s' is not active." % quest_id)
	if str(quest.get("category", "")) == "mandatory" or _policy_kind(quest, "abandonmentPolicy") == "forbidden":
		return _failure("mandatory-quest", "Quest '%s' cannot be abandoned." % quest_id)
	record["status"] = "abandoned"
	var resume := str(record.get("active_stage_id", ""))
	if not resume.is_empty():
		record["resume_stage_id"] = resume
	record["active_stage_id"] = ""
	record["abandoned_at"] = _now_epoch_ms()
	quest_abandoned.emit({"questId": quest_id})
	_changed(record)
	return _success(record)


func reoffer(quest_id: String, npc_id: String) -> Dictionary:
	var record := _record(quest_id)
	var quest := QuestCatalog.definition(quest_id)
	if record.is_empty() or quest.is_empty():
		return _failure("unknown-quest", "Unknown quest '%s'." % quest_id)
	if str(record["status"]) != "abandoned" or not _npc_listed(quest, "acquisition", npc_id):
		return _failure("invalid-status", "Quest '%s' cannot be re-offered by NPC '%s'." % [quest_id, npc_id])
	if _policy_kind(quest, "abandonmentPolicy") != "retryable":
		return _failure("retry-not-allowed", "Quest '%s' cannot be retried after abandonment." % quest_id)
	_reset_for_retry(record, quest, _policy_reset(quest, "abandonmentPolicy"))
	record["status"] = "available"
	record["active_stage_id"] = ""
	quest_available.emit({"questId": quest_id, "source": "npc"})
	_changed(record)
	return _success(record)


func retry_failed(quest_id: String) -> Dictionary:
	var record := _record(quest_id)
	var quest := QuestCatalog.definition(quest_id)
	if record.is_empty() or quest.is_empty():
		return _failure("unknown-quest", "Unknown quest '%s'." % quest_id)
	if str(record["status"]) != "failed" or _policy_kind(quest, "failurePolicy") != "retryable":
		return _failure("retry-not-allowed", "Quest '%s' cannot be retried." % quest_id)
	_reset_for_retry(record, quest, _policy_reset(quest, "failurePolicy"))
	var npc_quest := str((quest["acquisition"] as Dictionary).get("kind", "")) == "npc"
	_activate(record, quest, "npc" if npc_quest else "automatic")
	return _success(record)


func retry_abandoned_automatic(quest_id: String) -> Dictionary:
	var record := _record(quest_id)
	var quest := QuestCatalog.definition(quest_id)
	if record.is_empty() or quest.is_empty():
		return _failure("unknown-quest", "Unknown quest '%s'." % quest_id)
	if str(record["status"]) != "abandoned" or str((quest["acquisition"] as Dictionary).get("kind", "")) != "automatic":
		return _failure("invalid-status", "Quest '%s' is not an abandoned automatic quest." % quest_id)
	if _policy_kind(quest, "abandonmentPolicy") != "retryable":
		return _failure("retry-not-allowed", "Quest '%s' cannot be retried after abandonment." % quest_id)
	_reset_for_retry(record, quest, _policy_reset(quest, "abandonmentPolicy"))
	record["status"] = "locked"
	record["active_stage_id"] = ""
	_changed(record)
	evaluate_prerequisites()
	return _success(record)


## `fail` (no caller in the game: no content fails).
func fail(quest_id: String, reason: String) -> Dictionary:
	var record := _record(quest_id)
	var quest := QuestCatalog.definition(quest_id)
	if record.is_empty() or quest.is_empty():
		return _failure("unknown-quest", "Unknown quest '%s'." % quest_id)
	if str(record["status"]) != "active":
		return _success(record)
	var normalized := reason.strip_edges()
	if normalized.is_empty():
		return _failure("invalid-state", "Quest '%s' requires a failure reason." % quest_id)
	record["status"] = "failed"
	var resume := str(record.get("active_stage_id", ""))
	if not resume.is_empty():
		record["resume_stage_id"] = resume
	record["active_stage_id"] = ""
	record["failed_at"] = _now_epoch_ms()
	record["failure_reason"] = normalized
	quest_failed.emit({"questId": quest_id, "reason": normalized})
	_changed(record)
	return _success(record)


# --- queries --------------------------------------------------------------------------------------

## A copy of the record of `quest_id`, {} when unknown.
func state(quest_id: String) -> Dictionary:
	var record := _record(quest_id)
	return record.duplicate(true)


## The record's status, "locked" when unknown.
func status(quest_id: String) -> String:
	var record := _record(quest_id)
	return str(record.get("status", "locked")) if not record.is_empty() else "locked"


## The record (a copy) plus "definition", "visible_stages" and "ready_to_turn_in" (spec 2.9).
func view(quest_id: String) -> Dictionary:
	var record := _record(quest_id)
	var quest := QuestCatalog.definition(quest_id)
	if record.is_empty() or quest.is_empty():
		return {}
	var stage_list := QuestCatalog.stages(quest)
	var active_index := -1
	var active_stage := str(record.get("active_stage_id", ""))
	if not active_stage.is_empty():
		active_index = QuestCatalog.stage_index(quest, active_stage)
	elif str(record["status"]) == "completed":
		active_index = stage_list.size() - 1
	elif not str(record.get("resume_stage_id", "")).is_empty():
		active_index = QuestCatalog.stage_index(quest, str(record["resume_stage_id"]))
	var ready := false
	if str((quest["completion"] as Dictionary).get("kind", "")) == "npc-turn-in" and str(record["status"]) == "active" \
			and active_index == stage_list.size() - 1:
		ready = true
		var progress: Dictionary = record["progress"]
		for objective: Dictionary in QuestCatalog.objectives(stage_list[stage_list.size() - 1]):
			if int(progress.get(str(objective["id"]), 0)) < int(objective["target"]):
				ready = false
	var out := record.duplicate(true)
	out["definition"] = quest
	out["visible_stages"] = stage_list.slice(0, maxi(0, active_index + 1))
	out["ready_to_turn_in"] = ready
	return out


## Views in catalogue order, optionally of one status.
func list(status_filter: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for record: Dictionary in _records():
		if status_filter.is_empty() or str(record["status"]) == status_filter:
			out.append(view(str(record["quest_id"])))
	return out


## Available NPC quests this NPC gives.
func offers_for_npc(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for quest: Dictionary in list("available"):
		if _npc_listed(quest["definition"], "acquisition", npc_id):
			out.append(quest)
	return out


## Abandoned NPC quests this NPC can give again (abandonment retryable).
func reoffers_for_npc(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for quest: Dictionary in list("abandoned"):
		if _npc_listed(quest["definition"], "acquisition", npc_id) and _policy_kind(quest["definition"], "abandonmentPolicy") == "retryable":
			out.append(quest)
	return out


## Active quests ready to be turned in to this NPC.
func turn_ins_for_npc(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for quest: Dictionary in list("active"):
		if bool(quest["ready_to_turn_in"]) and _npc_listed(quest["definition"], "completion", npc_id):
			out.append(quest)
	return out


## The first active quest this NPC gave (`activeQuestFrom`), {} when none.
func active_quest_from(npc_id: String) -> Dictionary:
	for quest: Dictionary in list("active"):
		if _npc_listed(quest["definition"], "acquisition", npc_id):
			return quest
	return {}


## The NPC's interaction (`candidateFor`): {"kind": "turn-in"|"offer"|"reoffer"|"talk",
## "priority", "quest_id"}.
func npc_candidate(npc_id: String) -> Dictionary:
	var turn_ins := turn_ins_for_npc(npc_id)
	if not turn_ins.is_empty():
		return {"kind": "turn-in", "priority": PRIORITY_TURN_IN, "quest_id": turn_ins[0]["quest_id"]}
	var offers := offers_for_npc(npc_id)
	if not offers.is_empty():
		return {"kind": "offer", "priority": PRIORITY_OFFER, "quest_id": offers[0]["quest_id"]}
	var reoffers := reoffers_for_npc(npc_id)
	if not reoffers.is_empty():
		return {"kind": "reoffer", "priority": PRIORITY_REOFFER, "quest_id": reoffers[0]["quest_id"]}
	return {"kind": "talk", "priority": PRIORITY_TALK, "quest_id": ""}


## `markerFor` (spec 4.5): "" | "turn-in" | "main-offer" | "side-offer" | "talk" | "in-progress".
func marker_for(npc_id: String) -> String:
	if not turn_ins_for_npc(npc_id).is_empty():
		return "turn-in"
	var offers := offers_for_npc(npc_id)
	for offer: Dictionary in offers:
		if str((offer["definition"] as Dictionary).get("category", "")) == "mandatory":
			return "main-offer"
	if not offers.is_empty() or not reoffers_for_npc(npc_id).is_empty():
		return "side-offer"
	var active := list("active")
	for quest: Dictionary in active:
		var stage_definition := QuestCatalog.stage(quest["definition"], str(quest.get("active_stage_id", "")))
		var progress: Dictionary = quest["progress"]
		for objective: Dictionary in QuestCatalog.objectives(stage_definition):
			if str(objective.get("kind", "")) == "talk-to-npc" and npc_id in QuestCatalog.ids(objective, "npcIds") \
					and int(progress.get(str(objective["id"]), 0)) < int(objective["target"]):
				return "talk"
	for quest: Dictionary in active:
		if _npc_listed(quest["definition"], "completion", npc_id):
			return "in-progress"
	return ""


## `trackedQuestViews` (spec 4.4): every active quest and every available NPC quest, main story
## first, quests in progress before offers, newest accepted first, then catalogue order.
func tracked_views() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for quest: Dictionary in list("active"):
		entries.append(quest)
	for quest: Dictionary in list("available"):
		if str((quest["definition"]["acquisition"] as Dictionary).get("kind", "")) == "npc":
			entries.append(quest)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rank_a := _rank(a)
		var rank_b := _rank(b)
		if rank_a != rank_b:
			return rank_a < rank_b
		var accepted_a := int(a.get("accepted_at", 0))
		var accepted_b := int(b.get("accepted_at", 0))
		if accepted_a != accepted_b:
			return accepted_a > accepted_b
		return QuestCatalog.index_of(str(a["quest_id"])) < QuestCatalog.index_of(str(b["quest_id"])))
	return entries


static func _rank(quest: Dictionary) -> int:
	var main_story := str((quest["definition"] as Dictionary).get("category", "")) == "mandatory"
	return (0 if main_story else 2) + (0 if str(quest["status"]) == "active" else 1)


## The interaction controller's execute for an NPC candidate (spec 5.2).
func talk_to(npc: Node, kind: String) -> bool:
	return talk.execute(kind, npc) if talk != null and npc != null else false


# --- dev and tests (spec 10.9) --------------------------------------------------------------------

## Active at `stage_id` (default the first stage); earlier stages' objectives at their targets,
## that stage's at 0. No prerequisite or NPC checks, no known facts.
func debug_activate(quest_id: String, stage_id: String = "") -> void:
	var record := _record(quest_id)
	var quest := QuestCatalog.definition(quest_id)
	if record.is_empty() or quest.is_empty():
		push_warning("QuestService.debug_activate: unknown quest '%s'" % quest_id)
		return
	var target_index := 0 if stage_id.is_empty() else QuestCatalog.stage_index(quest, stage_id)
	if target_index < 0:
		push_warning("QuestService.debug_activate: quest '%s' has no stage '%s'" % [quest_id, stage_id])
		return
	var stage_list := QuestCatalog.stages(quest)
	var progress := {}
	for index in target_index + 1:
		for objective: Dictionary in QuestCatalog.objectives(stage_list[index]):
			progress[str(objective["id"])] = int(objective["target"]) if index < target_index else 0
	for key: String in ["failed_at", "failure_reason", "abandoned_at", "completed_at", "resume_stage_id"]:
		record.erase(key)
	record["status"] = "active"
	record["active_stage_id"] = str((stage_list[target_index] as Dictionary)["id"])
	record["progress"] = progress
	record["consumed_fact_ids"] = {}
	record["rewards_granted"] = false
	record["accepted_at"] = _now_epoch_ms()
	quest_accepted.emit({"questId": quest_id, "source": "debug"})
	_changed(record)


## Completed without granting the rewards, then the follow-up quests.
func debug_mark_completed(quest_id: String) -> void:
	var record := _record(quest_id)
	if record.is_empty():
		push_warning("QuestService.debug_mark_completed: unknown quest '%s'" % quest_id)
		return
	for key: String in ["failed_at", "failure_reason", "abandoned_at", "resume_stage_id"]:
		record.erase(key)
	record["status"] = "completed"
	record["active_stage_id"] = ""
	record["rewards_granted"] = true
	record["completed_at"] = _now_epoch_ms()
	_changed(record)
	evaluate_prerequisites()


# --- records (RunState.quests) ----------------------------------------------------------------------

## RunState.quests, rebound (validated, completed with locked records, indexed) whenever the run
## replaced the array (new_run, install).
func _records() -> Array:
	var run := Services.run()
	if run == null:
		return []
	if _bound == null or not is_same(run.quests, _bound):
		_rebind(run)
	return run.quests


## The live record of `quest_id` ({} when unknown).
func _record(quest_id: String) -> Dictionary:
	var records := _records()
	var index := int(_index.get(quest_id, -1))
	return records[index] if index >= 0 and index < records.size() else {}


## Load validation (spec 10.8, owner decision Q7): retired ids are dropped; an unknown id, a
## duplicate, or a record that breaks the invariants warns and is reset to locked (Phaser rejects
## the whole save); a definition version mismatch warns and is kept; missing quests are added as
## locked. The array keeps its identity and ends in catalogue order.
func _rebind(run: Services.RunStateType) -> void:
	var source: Array = run.quests
	var by_id := {}
	for raw: Variant in source:
		if not raw is Dictionary:
			push_warning("QuestService: dropped a quest record that is not a dictionary")
			continue
		var record: Dictionary = raw
		var quest_id := str(record.get("quest_id", ""))
		if quest_id in QuestCatalog.RETIRED_IDS:
			continue
		var quest := QuestCatalog.definition(quest_id)
		if quest.is_empty():
			push_warning("QuestService: dropped the record of unknown quest '%s'" % quest_id)
			continue
		if by_id.has(quest_id):
			push_warning("QuestService: dropped a duplicate record of quest '%s'" % quest_id)
			continue
		var problems := _record_problems(record, quest)
		if not problems.is_empty():
			push_warning("QuestService: quest '%s' was reset (%s)" % [quest_id, "; ".join(problems)])
			by_id[quest_id] = _locked_record(quest)
			continue
		if int(record.get("definition_version", 0)) != int(quest.get("definitionVersion", 1)):
			push_warning("QuestService: quest '%s' was saved with definition version %s (now %s); kept as is"
				% [quest_id, record.get("definition_version"), quest.get("definitionVersion")])
		by_id[quest_id] = _normalized(record)
	var ordered: Array = []
	_index = {}
	for quest: Dictionary in QuestCatalog.definitions():
		var quest_id := str(quest["id"])
		_index[quest_id] = ordered.size()
		ordered.append(by_id.get(quest_id, _locked_record(quest)))
	source.clear()
	source.append_array(ordered)
	_bound = source


## `validateQuestState` (validateQuestCatalog.ts:284-317): [] when the record is sound.
func _record_problems(record: Dictionary, quest: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var record_status := str(record.get("status", ""))
	if not record_status in QuestCatalog.STATUSES:
		problems.append("unknown status '%s'" % record_status)
		return problems
	var active_stage: Variant = record.get("active_stage_id", "")
	var active_stage_id := "" if active_stage == null else str(active_stage)
	if record_status == "active":
		if QuestCatalog.stage_index(quest, active_stage_id) < 0:
			problems.append("an active quest needs a known stage")
	elif not active_stage_id.is_empty():
		problems.append("only an active quest has a stage")
	var resume := str(record.get("resume_stage_id", ""))
	if not resume.is_empty():
		if record_status != "failed" and record_status != "abandoned":
			problems.append("only a failed or abandoned quest has a resume stage")
		elif QuestCatalog.stage_index(quest, resume) < 0:
			problems.append("unknown resume stage '%s'" % resume)
	if not record.get("rewards_granted") is bool or bool(record["rewards_granted"]) != (record_status == "completed"):
		problems.append("rewards_granted does not match the status")
	var progress: Variant = record.get("progress", {})
	if not progress is Dictionary:
		problems.append("progress is not a dictionary")
	else:
		for key: Variant in progress:
			var objective := QuestCatalog.objective(quest, str(key))
			var value: Variant = progress[key]
			if objective.is_empty():
				problems.append("progress of unknown objective '%s'" % key)
			elif not _whole(value) or float(value) < 0.0 or float(value) > float(objective["target"]):
				problems.append("progress of '%s' out of range" % key)
	var consumed: Variant = record.get("consumed_fact_ids", {})
	if not consumed is Dictionary:
		problems.append("consumed facts are not a dictionary")
	else:
		for key: Variant in consumed:
			if QuestCatalog.objective(quest, str(key)).is_empty():
				problems.append("facts of unknown objective '%s'" % key)
			elif not consumed[key] is Array:
				problems.append("facts of '%s' are not a list" % key)
			else:
				for fact: Variant in consumed[key]:
					if not fact is String:
						problems.append("a fact of '%s' is not a string" % key)
	return problems


## Fills the optional keys and turns whole floats back into ints.
static func _normalized(record: Dictionary) -> Dictionary:
	var active_stage: Variant = record.get("active_stage_id", "")
	record["active_stage_id"] = "" if active_stage == null else str(active_stage)
	if not record.get("progress") is Dictionary:
		record["progress"] = {}
	var progress: Dictionary = record["progress"]
	for key: Variant in progress.keys():
		progress[key] = int(progress[key])
	if not record.get("consumed_fact_ids") is Dictionary:
		record["consumed_fact_ids"] = {}
	record["definition_version"] = int(record.get("definition_version", 1))
	for key: String in ["accepted_at", "completed_at", "failed_at", "abandoned_at"]:
		if record.has(key) and _whole(record[key]):
			record[key] = int(record[key])
	return record


static func _locked_record(quest: Dictionary) -> Dictionary:
	return {
		"quest_id": str(quest["id"]),
		"definition_version": int(quest.get("definitionVersion", 1)),
		"status": "locked",
		"active_stage_id": "",
		"progress": {},
		"consumed_fact_ids": {},
		"rewards_granted": false,
	}


static func _whole(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var number: float = value
		return is_finite(number) and number == floorf(number)
	return false


## `initializeProgress`: 0 for each objective of the stage that has no progress yet.
static func _init_progress(record: Dictionary, stage_definition: Dictionary) -> void:
	var progress: Dictionary = record.get_or_add("progress", {})
	for objective: Dictionary in QuestCatalog.objectives(stage_definition):
		if not progress.has(str(objective["id"])):
			progress[str(objective["id"])] = 0


## The consumed facts of one objective (created on first use).
static func _consumed(record: Dictionary, objective_id: String) -> Array:
	var consumed: Dictionary = record.get_or_add("consumed_fact_ids", {})
	if not consumed.get(objective_id) is Array:
		consumed[objective_id] = []
	return consumed[objective_id]


## `npcId` is listed in `quest[section]` (acquisition or completion) of kind npc / npc-turn-in.
static func _npc_listed(quest: Dictionary, section: String, npc_id: String) -> bool:
	var part: Dictionary = quest.get(section, {}) if quest.get(section) is Dictionary else {}
	var kind := str(part.get("kind", ""))
	if section == "acquisition" and kind != "npc":
		return false
	if section == "completion" and kind != "npc-turn-in":
		return false
	return npc_id in QuestCatalog.ids(part, "npcIds")


static func _policy_kind(quest: Dictionary, policy: String) -> String:
	var part: Variant = quest.get(policy)
	return str((part as Dictionary).get("kind", "")) if part is Dictionary else ""


static func _policy_reset(quest: Dictionary, policy: String) -> String:
	var part: Variant = quest.get(policy)
	return str((part as Dictionary).get("reset", "quest")) if part is Dictionary else "quest"


func _changed(record: Dictionary) -> void:
	var quest_id := str(record["quest_id"])
	quest_changed.emit({"questId": quest_id})
	var run := Services.run()
	if run != null:
		run.notify_quests_changed(quest_id)


func _success(record: Dictionary) -> Dictionary:
	return {"ok": true, "state": record.duplicate(true)}


static func _failure(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason}


## Phaser `Date.now()`: whole epoch ms (an int, so saves round-trip exactly).
static func _now_epoch_ms() -> int:
	return int(floorf(Time.get_unix_time_from_system() * 1000.0))
