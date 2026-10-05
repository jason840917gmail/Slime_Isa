extends RefCounted
## Quest toasts, banners and cues (Phaser `features/quests/QuestNotificationPresenter.ts`, the
## "QUEST COMPLETE" handler and the ability banner of `WorldScene.ts:483-502`, the quest rows of
## `AudioEventBridge.ts:95-109`; quests spec 4.1-4.3). Owned by the quest service; it never changes
## quest state.
##
## Toasts are floating texts over the player (`get_centre()`), lifted by: 112 px "New quest
## available" (yellow, big), 70 px "Quest accepted" (green, big; a chapter quest shows its banner
## first), "Stage complete" (green), "Quest failed" (red, big), "Quest abandoned" (red), "QUEST
## COMPLETE" (yellow, big, 2400 ms) with one "+ <reward>" line per reward below it (green, big,
## 2400 ms, at p - (0, 46) + 20 px per line). Owner decision Q5: toasts shown in the same frame
## stack 22 px apart instead of overlapping.
##
## Banners use the Shell's area title card: chapters in #ffd277; "<title> learned: press <key>" in
## #9ff0c8 for every ability RunState learns (passive Goo Trail: its own line).
##
## Cues: npc talked NpcBlip, accepted QuestAccept, progressed / stage completed QuestProgress,
## completed QuestComplete, failed QuestFailed.
##
## Owner: quests.

const Services := preload("res://game/shared/services.gd")
const QuestCatalog := preload("res://game/quests/quest_catalog.gd")
const AbilityDefinitions := preload("res://game/player/abilities/ability_definitions.gd")
const ControlLabels := preload("res://game/shell/control_labels.gd")

const AVAILABLE_LIFT := 112.0
const TOAST_LIFT := 70.0
const REWARD_TOP := 46.0
const REWARD_STEP := 20.0
const COMPLETE_MS := 2400.0
## Owner decision Q5.
const STACK_PX := 22.0
const CHAPTER_COLOR := Color("#ffd277")
## ABILITY_LEARNED_COLOR (WorldScene.ts:153).
const ABILITY_COLOR := Color("#9ff0c8")
## PASSIVE_ABILITY_DEFINITIONS learnedText (PlayerAbilityDefinitions.ts:59).
const PASSIVE_TEXTS := {"goo-trail": "Goo Trail learned: enemies on your goo slow down"}

## A toast was shown. Payload: {"text", "color" (TEXT_COLORS key), "big", "lift", "x", "y", "duration_ms"}.
signal toast_shown(payload: Dictionary)
## A banner was shown. Payload: {"text", "color" (Color)}.
signal banner_shown(payload: Dictionary)

var _service: Node
## Lifts used by toasts this frame (Q5 stacking); the frame is the pair (process, physics frame).
var _frame: Vector2i = Vector2i(-1, -1)
var _lifts: Array[float] = []


func _init(service: Node) -> void:
	_service = service
	service.connect(&"quest_available", _on_available)
	service.connect(&"quest_accepted", _on_accepted)
	service.connect(&"quest_progressed", _on_progressed)
	service.connect(&"quest_stage_completed", _on_stage_completed)
	service.connect(&"quest_completed", _on_completed)
	service.connect(&"quest_failed", _on_failed)
	service.connect(&"quest_abandoned", _on_abandoned)
	service.connect(&"npc_talked", _on_npc_talked)
	var run := Services.run()
	if run != null and not run.ability_learned.is_connected(_on_ability_learned):
		run.ability_learned.connect(_on_ability_learned)


## The service leaves: forget the autoload connection.
func disconnect_all() -> void:
	var run := Services.run()
	if run != null and run.ability_learned.is_connected(_on_ability_learned):
		run.ability_learned.disconnect(_on_ability_learned)


func _on_available(payload: Dictionary) -> void:
	_toast("New quest available: " + QuestCatalog.title(str(payload.get("questId", ""))), &"yellow", true, AVAILABLE_LIFT)


func _on_accepted(payload: Dictionary) -> void:
	var quest_id := str(payload.get("questId", ""))
	var chapter := str(QuestCatalog.definition(quest_id).get("chapter", ""))
	if not chapter.is_empty():
		_banner(chapter, CHAPTER_COLOR)
	_toast("Quest accepted: " + QuestCatalog.title(quest_id), &"green", true, TOAST_LIFT)
	_cue(&"QuestAccept")


func _on_progressed(_payload: Dictionary) -> void:
	_cue(&"QuestProgress")


func _on_stage_completed(payload: Dictionary) -> void:
	_toast("Stage complete: " + QuestCatalog.title(str(payload.get("questId", ""))), &"green", false, TOAST_LIFT)
	_cue(&"QuestProgress")


func _on_failed(payload: Dictionary) -> void:
	_toast("Quest failed: %s (%s)" % [QuestCatalog.title(str(payload.get("questId", ""))), str(payload.get("reason", ""))],
		&"red", true, TOAST_LIFT)
	_cue(&"QuestFailed")


func _on_abandoned(payload: Dictionary) -> void:
	_toast("Quest abandoned: " + QuestCatalog.title(str(payload.get("questId", ""))), &"red", false, TOAST_LIFT)


## "QUEST COMPLETE: <title>" and the reward lines under it (WorldScene.ts:497-502).
func _on_completed(payload: Dictionary) -> void:
	_toast("QUEST COMPLETE: " + str(payload.get("title", "")), &"yellow", true, TOAST_LIFT, COMPLETE_MS)
	var rewards: Dictionary = payload.get("rewards", {}) if payload.get("rewards") is Dictionary else {}
	var index := 0
	for line: String in QuestCatalog.reward_lines(rewards):
		_text("+ " + line, &"green", true, REWARD_TOP - REWARD_STEP * index, COMPLETE_MS)
		index += 1
	_cue(&"QuestComplete")


func _on_npc_talked(_payload: Dictionary) -> void:
	_cue(&"NpcBlip")


## WorldScene's `ability.learned` handler: the banner with the ability's key.
func _on_ability_learned(payload: Dictionary) -> void:
	var ability_id := str(payload.get("ability_id", ""))
	if PASSIVE_TEXTS.has(ability_id):
		_banner(str(PASSIVE_TEXTS[ability_id]), ABILITY_COLOR)
		return
	if not AbilityDefinitions.has(StringName(ability_id)):
		return
	var key := ControlLabels.control_label(AbilityDefinitions.action(StringName(ability_id)))
	_banner("%s learned: press %s" % [AbilityDefinitions.title(StringName(ability_id)), key], ABILITY_COLOR)


## A toast that stacks with this frame's other toasts (Q5).
func _toast(text: String, color: StringName, big: bool, lift: float, duration_ms: float = -1.0) -> void:
	_text(text, color, big, _stacked(lift), duration_ms)


func _text(text: String, color: StringName, big: bool, lift: float, duration_ms: float = -1.0) -> void:
	var world := Services.world()
	var player: Variant = world.player if world != null else null
	if player == null or not is_instance_valid(player):
		return
	var at: Vector2 = (player as Object).call(&"get_centre") - Vector2(0.0, lift)
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(at, text, color, big, duration_ms)
	toast_shown.emit({"text": text, "color": String(color), "big": big, "lift": lift, "x": at.x, "y": at.y,
		"duration_ms": duration_ms})


## The lift for a new toast: 22 px above any toast of this frame that it would overlap.
func _stacked(lift: float) -> float:
	var frame := Vector2i(Engine.get_process_frames(), Engine.get_physics_frames())
	if frame != _frame:
		_frame = frame
		_lifts.clear()
	var at := lift
	var moved := true
	while moved:
		moved = false
		for used in _lifts:
			if absf(used - at) < STACK_PX - 0.001:
				at = used + STACK_PX
				moved = true
	_lifts.append(at)
	return at


func _banner(text: String, color: Color) -> void:
	var shell := Services.shell()
	if shell != null:
		shell.show_area_title(text, color)
	banner_shown.emit({"text": text, "color": color})


static func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.audio_cue(cue)
