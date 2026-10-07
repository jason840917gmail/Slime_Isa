extends Node2D
class_name InteractionController
## The interact button (Phaser `features/interaction/InteractionRouter.ts` with the providers of
## `UniversalSceneWorldController.ts` and `QuestNpcController.ts`; interaction spec 2, 7).
## A child "Interaction" of main, made once and kept across world swaps (it finds the current
## world's interactables through their groups). PAUSABLE: it stops with hit-stop and menus,
## leaving the last prompt on screen as Phaser does.
##
## Every physics step (before the player, priority -10) each provider offers at most one target,
## the nearest of its kind within that object's reach: gates 95, doors 90, workbenches 88, beds 85,
## chests 80 (reach 112), and every NPC in reach (quest turn-in 100, offer 90, reoffer 85, talk 50,
## from the quest service). A pointer within 64 px of a target's
## pick point chooses it; otherwise the highest priority wins and a tie goes to the smaller id
## (so two NPCs are picked by id, not distance: a Phaser quirk kept). The chosen target shows as
## "Right-click: <prompt>" at the bottom of the screen and a key badge over it. The player's
## interact press (right click, buffered 150 ms) runs `handle_interact`.
##
## A chest opens the chest window (chest.gd hands itself to game/ui/screens/chest_window.gd). An
## NPC opens its conversation (the quest service: dialogue box, offer and turn-in window). A
## workbench opens the crafting window for its site (game/ui/screens/menu_windows.gd).
##
## Owner: interaction.

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const InteractionPrompt := preload("res://game/interaction/interaction_prompt.gd")
const InteractionBadge := preload("res://game/interaction/interaction_badge.gd")
const DoorScript := preload("res://game/scripts/door.gd")
const GateScript := preload("res://game/scripts/gate.gd")
const ChestScript := preload("res://game/scripts/chest.gd")
const BedScript := preload("res://game/scripts/bed.gd")
const WorkbenchScript := preload("res://game/scripts/workbench.gd")
const PlacedFurniture := preload("res://game/building/placed_furniture.gd")

const GROUP := &"interaction"
const MAIN_GROUP := &"world_main"
const FURNITURE_GROUP := &"furniture_placement"
## InteractionRouter.ts:44.
const POINTER_PICK_PX := 64.0
## UniversalSceneWorldController.ts:343-345.
const TARGET_BODY_RISE_PX := 24.0
const CHEST_REACH := 112.0
const CHEST_BADGE_RISE := 56.0
## QuestNpcController.ts:12-16.
const NPC_REACH := 96.0
const NPC_BADGE_OFFSET := Vector2(30.0, -30.0)
const NPC_BODY_RISE := 24.0
const PRIORITY_GATE := 95
const PRIORITY_DOOR := 90
const PRIORITY_WORKBENCH := 88
const PRIORITY_BED := 85
const PRIORITY_CHEST := 80
const PRIORITY_TALK := 50
const PRIORITY_RESTORATION := 89
const PRIORITY_GULP := 60
## Message literals (UniversalSceneWorldController.ts:984-999, :909-915).
const GATE_STUCK_MESSAGE := "The gate will not budge."
const CUE_GATE_UNLOCK := &"GateUnlock"
const CUE_GATE_LOCKED := &"GateLocked"
const CHEST_GUARDED_PROMPT := "Chest locked by Fatty One Eye"
const CHEST_EMPTY_PROMPT := "Inspect empty chest"
const CHEST_OPEN_PROMPT := "Open chest"
const CHEST_GUARDED_MESSAGE := "Fatty One Eye is guarding this chest!"
const CHEST_MESSAGE_RISE := 48.0
const NPC_DEFINITIONS_FILE := "npc-definitions.json"
## The quest service (game/quests/quest_service.gd) runs NPC conversations.
const QUESTS_GROUP := &"quests"

## The chosen target changed. Payload: {"id": String, "prompt": String} ("" when none).
signal candidate_changed(payload: Dictionary)
## A message was shown. Payload: {"text", "color", "x", "y"} (test hook).
signal message_shown(payload: Dictionary)
## The interact button ran the chosen target (the control hint learns "interact"). Payload: {"id"}.
signal interacted(payload: Dictionary)
## A crafting station's window opened (Phaser `workbench.opened`). Payload: {"mapId", "context"}.
signal workbench_opened(payload: Dictionary)

var _prompt: InteractionPrompt
var _badge: InteractionBadge
var _current: Dictionary = {}
var _suppressed: bool = false
var _pointer_seen: bool = false
var _npc_names: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	process_physics_priority = -10
	_prompt = InteractionPrompt.new()
	_prompt.name = "InteractionPrompt"
	add_child(_prompt)
	_badge = InteractionBadge.new()
	_badge.name = "InteractionBadge"
	add_child(_badge)
	_load_npc_definitions()


## Phaser `pointerSeen`: picking by pointer starts once the mouse moved or clicked.
func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer_seen = true


func _physics_process(_delta: float) -> void:
	var player := _player()
	# Sleeping or placing furniture offers nothing (WorldScene.ts:820).
	var furniture := get_tree().get_first_node_in_group(FURNITURE_GROUP)
	var placing := furniture != null and bool(furniture.call(&"is_active"))
	set_suppressed((player != null and bool(player.call(&"is_sleeping"))) or placing)
	refresh(get_global_mouse_position() if _pointer_seen else null)


## InteractionRouter.update: gathers the targets, chooses one, updates the prompt and the badge.
func refresh(pointer: Variant = null) -> void:
	if _suppressed:
		return
	var chosen := choose(_gather(), pointer)
	var previous_id := str(_current.get("id", ""))
	_current = chosen
	var id := str(chosen.get("id", ""))
	if chosen.is_empty():
		_prompt.hide_prompt()
		_badge.hide_badge()
	else:
		_prompt.show_prompt(prompt_text(chosen))
		var anchor: Callable = chosen.get("anchor", Callable())
		if anchor.is_valid():
			_badge.show_at(anchor.call(), id != previous_id)
		else:
			_badge.hide_badge()
	if id != previous_id:
		candidate_changed.emit({"id": id, "prompt": str(chosen.get("prompt", ""))})


## InteractionRouter.choose (spec 2.4).
func choose(candidates: Array[Dictionary], pointer: Variant) -> Dictionary:
	var best := {}
	if pointer is Vector2:
		var best_distance := POINTER_PICK_PX
		for candidate in candidates:
			var at: Variant = _pick_point(candidate)
			if at == null:
				continue
			var distance := (at as Vector2).distance_to(pointer)
			if distance <= best_distance:
				best = candidate
				best_distance = distance
	if best.is_empty():
		for candidate in candidates:
			if not best.is_empty():
				var priority := int(candidate["priority"])
				var best_priority := int(best["priority"])
				if priority < best_priority or (priority == best_priority and str(candidate["id"]) > str(best["id"])):
					continue
			best = candidate
	return best


## Runs the chosen target (Phaser `handleInteract`). False when there is none or it refused.
func handle_interact() -> bool:
	if _current.is_empty() or _suppressed:
		return false
	var execute: Callable = _current.get("execute", Callable())
	var target_id := str(_current.get("id", ""))
	var done := bool(execute.call()) if execute.is_valid() else false
	if done:
		interacted.emit({"id": target_id})
	return done


func has_candidate() -> bool:
	return not _current.is_empty()


## True when the chosen target also has a hold action (`secondary`: a placed bench's "Pick up").
func has_secondary() -> bool:
	return not _suppressed and _current.get("secondary") is Dictionary


## Runs the chosen target's hold action (Phaser `handleSecondary`). False when there is none.
func handle_secondary() -> bool:
	if not has_secondary():
		return false
	var target_id := str(_current.get("id", ""))
	var execute: Callable = (_current["secondary"] as Dictionary).get("execute", Callable())
	var done := bool(execute.call()) if execute.is_valid() else false
	if done:
		interacted.emit({"id": target_id})
		refresh(null)
	return done


## The chosen target: {"id", "prompt", "priority", "anchor", "origin", "execute"}; {} when none.
func current() -> Dictionary:
	return _current


## Sleeping hides the prompt and the badge and offers nothing.
func set_suppressed(value: bool) -> void:
	if value == _suppressed:
		return
	_suppressed = value
	if value:
		_set_none()


## World teardown: forgets the target (it points into the freed world) and hides both.
func clear() -> void:
	_set_none()


## "Right-click: <prompt>" (the verb follows the `interact` binding), plus "     Hold: <prompt>"
## (five spaces, InteractionRouter.ts:27-31) for a target with a hold action.
func prompt_text(candidate: Dictionary) -> String:
	var text := "%s: %s" % [InteractionPrompt.interact_verb(), str(candidate.get("prompt", ""))]
	var secondary: Variant = candidate.get("secondary")
	if secondary is Dictionary:
		text += "     Hold: %s" % str((secondary as Dictionary).get("prompt", ""))
	return text


func get_prompt() -> InteractionPrompt:
	return _prompt


func get_badge() -> InteractionBadge:
	return _badge


# --- providers -------------------------------------------------------------------------------

## Phaser provider order: quest NPCs, chests, doors, gates, beds, workbenches.
func _gather() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var player := _player()
	if player == null:
		return out
	var at: Vector2 = player.call(&"get_centre")
	out.append_array(_npc_candidates(at))
	_append(out, _chest_candidate(at))
	_append(out, _nearest(at, DoorScript.GROUP, PRIORITY_DOOR, "world-doors:", _door_id, Callable(), _use_door))
	_append(out, _nearest(at, GateScript.GROUP, PRIORITY_GATE, "world-gates:", _gate_id, _gate_closed, _use_gate))
	_append(out, _nearest(at, BedScript.GROUP, PRIORITY_BED, "world-beds:", _path_id, Callable(), _use_bed))
	_append(out, _with_pick_up(_nearest(at, WorkbenchScript.GROUP, PRIORITY_WORKBENCH, "world-workbenches:", _path_id, Callable(), _use_workbench)))
	_append(out, _nearest(at, &"restoration_site", PRIORITY_RESTORATION, "world-restorations:", _path_id, Callable(), _use_restoration))
	_append(out, _gulp_candidate(player))
	return out


## A placed station's candidate also offers "Hold: Pick up" (`pickUpAction`,
## UniversalSceneWorldController.ts:1003-1008; furniture spec 8.1).
func _with_pick_up(candidate: Dictionary) -> Dictionary:
	if candidate.is_empty():
		return candidate
	var node: Variant = candidate.get("node")
	var placement_id := PlacedFurniture.placement_of(node) if node is Node else ""
	if placement_id.is_empty():
		return candidate
	candidate["secondary"] = {"prompt": "Pick up", "execute": func() -> bool:
		var furniture := get_tree().get_first_node_in_group(FURNITURE_GROUP)
		return furniture != null and bool(furniture.call(&"pick_up", placement_id))}
	return candidate


## A Gulp spot in reach (WorldScene.ts:1109-1128): "Gulp the Stone", no badge (the spot's own
## "[Q] Gulp" hint floats over it), picked by pointer at the spot.
func _gulp_candidate(player: Node) -> Dictionary:
	var spot: Node = player.call(&"nearest_gulp_spot") if player.has_method(&"nearest_gulp_spot") else null
	if spot == null:
		return {}
	var at: Vector2 = spot.call(&"origin")
	var target := player
	return {
		"id": "gulp-spots:%d:%d" % [roundi(at.x), roundi(at.y)],
		"prompt": "Gulp the " + (str(spot.call(&"prompt_name")) if spot.has_method(&"prompt_name") else ItemCatalog.item_name(str(spot.get(&"material_item_id")))),
		"priority": PRIORITY_GULP,
		"origin": func() -> Vector2: return at,
		"execute": func() -> bool: return str(target.call(&"eat")) != "nothing",
	}


## The nearest node of `group` within its own `interact_radius` (exact ties: the first found).
func _nearest(at: Vector2, group: StringName, priority: int, prefix: String, key: Callable, offer: Callable, use: Callable) -> Dictionary:
	var best: Node = null
	var best_distance := INF
	for node: Node in get_tree().get_nodes_in_group(group):
		if not node.is_inside_tree() or (offer.is_valid() and not bool(offer.call(node))):
			continue
		var distance := at.distance_to(node.call(&"origin"))
		if distance <= float(node.get(&"interact_radius")) and distance < best_distance:
			best = node
			best_distance = distance
	if best == null:
		return {}
	var target := best
	return {
		"id": prefix + str(key.call(target)),
		"prompt": str(target.get(&"prompt")),
		"priority": priority,
		"anchor": func() -> Vector2: return (target.call(&"origin") as Vector2) - Vector2(0.0, float(target.get(&"badge_rise"))),
		"origin": func() -> Vector2: return (target.call(&"origin") as Vector2) - Vector2(0.0, TARGET_BODY_RISE_PX),
		"execute": func() -> bool: return bool(use.call(target)),
		"node": target,
	}


## Every chest syncs its open/closed frame on every poll; the nearest within 112 px is offered.
func _chest_candidate(at: Vector2) -> Dictionary:
	var best: ChestScript = null
	var best_distance := INF
	for node: Node in get_tree().get_nodes_in_group(ChestScript.GROUP):
		var chest := node as ChestScript
		if chest == null:
			continue
		chest.sync_frame()
		var distance := at.distance_to(chest.origin())
		if distance <= CHEST_REACH and distance < best_distance:
			best = chest
			best_distance = distance
	if best == null:
		return {}
	var chest := best
	var empty := chest.is_empty()
	var prompt := CHEST_EMPTY_PROMPT if empty else (CHEST_GUARDED_PROMPT if chest.is_guarded() else CHEST_OPEN_PROMPT)
	return {
		"id": "managed-chests:" + chest.instance_id,
		"prompt": prompt,
		"priority": PRIORITY_CHEST,
		"anchor": func() -> Vector2: return chest.origin() - Vector2(0.0, CHEST_BADGE_RISE),
		"origin": func() -> Vector2: return chest.origin() - Vector2(0.0, TARGET_BODY_RISE_PX),
		"execute": func() -> bool: return _use_chest(chest),
	}


## Every NPC in reach (QuestNpcController `getCandidates` / `candidateFor`, quests spec 5.2): the
## quest service (group "quests") names the kind and priority: turn-in 100 "Return to <name>",
## offer 90, reoffer 85 "Resume quest with <name>", talk 50 ("Talk to <name>" for both).
func _npc_candidates(at: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var quests := get_tree().get_first_node_in_group(QUESTS_GROUP)
	for node: Node in get_tree().get_nodes_in_group(&"npc"):
		if not node.is_inside_tree() or not node.has_method(&"get_phaser_position"):
			continue
		var definition_id := str(node.get(&"npc_definition_id"))
		if not _npc_names.has(definition_id):
			continue
		var position: Vector2 = node.call(&"get_phaser_position")
		if at.distance_to(position) > NPC_REACH:
			continue
		var npc := node
		var candidate: Dictionary = quests.call(&"npc_candidate", definition_id) if quests != null \
				else {"kind": "talk", "priority": PRIORITY_TALK}
		var kind := str(candidate.get("kind", "talk"))
		var name_text := str(_npc_names[definition_id])
		var prompt := "Talk to " + name_text
		if kind == "turn-in":
			prompt = "Return to " + name_text
		elif kind == "reoffer":
			prompt = "Resume quest with " + name_text
		out.append({
			"id": "quest-npcs:%s:%s" % [str(npc.call(&"get_instance_id_key")), kind],
			"prompt": prompt,
			"priority": int(candidate.get("priority", PRIORITY_TALK)),
			"anchor": func() -> Vector2: return (npc.call(&"get_phaser_position") as Vector2) + NPC_BADGE_OFFSET,
			"origin": func() -> Vector2: return (npc.call(&"get_phaser_position") as Vector2) - Vector2(0.0, NPC_BODY_RISE),
			"execute": func() -> bool: return _talk(npc, kind),
		})
	return out


# --- execute per kind (spec 7.3) ---------------------------------------------------------------

func _use_door(door: Node) -> bool:
	var result: Dictionary = door.call(&"use")
	var queued := str(result.get("status", "")) == "queued"
	if queued:
		_cue(StringName(door.get(&"use_cue")))
	return queued


func _use_gate(gate: Node) -> bool:
	var result := str(gate.call(&"try_unlock"))
	var at: Vector2 = (gate.call(&"origin") as Vector2) - Vector2(0.0, float(gate.get(&"badge_rise")))
	if result == "unlocked" or result == "already-unlocked":
		if result == "unlocked":
			_cue(CUE_GATE_UNLOCK)
		gate.call(&"open")
		_message(at, str(gate.get(&"unlocked_message")), &"green")
	elif result == "missing-item":
		_cue(CUE_GATE_LOCKED)
		_message(at, str(gate.get(&"locked_message")), &"white")
	else:
		_cue(CUE_GATE_LOCKED)
		_message(at, GATE_STUCK_MESSAGE, &"white")
	return true


## Opens the chest (its window shows it, also when empty); a live guard says so instead.
func _use_chest(chest: ChestScript) -> bool:
	if chest.request_open() == "guarded":
		_message(chest.origin() - Vector2(0.0, CHEST_MESSAGE_RISE), CHEST_GUARDED_MESSAGE, &"white")
	return true


func _use_bed(bed: Node) -> bool:
	var player := _player()
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	if player == null or get_tree().paused:
		return false
	if main != null and main.has_method(&"is_transitioning") and bool(main.call(&"is_transitioning")):
		return false
	return bool(player.call(&"sleep_in", bed.call(&"sleep_request")))


func _use_restoration(site: Node) -> bool:
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	if get_tree().paused or (main != null and main.has_method(&"is_transitioning") and bool(main.call(&"is_transitioning"))):
		return false
	return bool(site.call(&"restore"))


## `openCraftingStation` (WorldScene.ts:1279-1285): the station's crafting window (MenuWindows,
## group "menu_windows"), refused while the game is paused or a game window is open; then
## `workbench_opened`.
func _use_workbench(bench: Node) -> bool:
	if get_tree().paused:
		return false
	var windows := get_tree().get_first_node_in_group(&"game_windows")
	var menu := get_tree().get_first_node_in_group(&"menu_windows")
	if menu == null or (windows != null and bool(windows.call(&"is_any_open"))):
		return false
	var site: Dictionary = bench.call(&"site")
	if not bool(menu.call(&"open_station", site)):
		return false
	var world := Services.world()
	workbench_opened.emit({"mapId": world.map_id() if world != null else "", "context": str(site.get("station", ""))})
	return true


## The NPC's conversation (dialogue box, offer / turn-in window): the quest service runs it
## (`talk_to`, quests spec 5.2-5.4). False without the service.
func _talk(npc: Node, kind: String) -> bool:
	var quests := get_tree().get_first_node_in_group(QUESTS_GROUP)
	if quests == null or get_tree().paused:
		return false
	return bool(quests.call(&"talk_to", npc, kind))


# --- helpers -----------------------------------------------------------------------------------

func _cue(cue: StringName) -> void:
	var feel := Services.feel()
	if feel != null and not cue.is_empty():
		feel.audio_cue(cue)


func _message(at: Vector2, text: String, color: StringName, big: bool = true) -> void:
	var feel := Services.feel()
	if feel != null:
		feel.floating_text(at, text, color, big)
	message_shown.emit({"text": text, "color": String(color), "x": at.x, "y": at.y})


func _set_none() -> void:
	var had := not _current.is_empty()
	_current = {}
	if _prompt != null:
		_prompt.hide_prompt()
	if _badge != null:
		_badge.hide_badge()
	if had:
		candidate_changed.emit({"id": "", "prompt": ""})


func _player() -> Node:
	var world := Services.world()
	var player: Node = world.player if world != null else null
	return player if player != null and is_instance_valid(player) and player.is_inside_tree() else null


static func _append(out: Array[Dictionary], candidate: Dictionary) -> void:
	if not candidate.is_empty():
		out.append(candidate)


static func _pick_point(candidate: Dictionary) -> Variant:
	var origin: Callable = candidate.get("origin", Callable())
	if origin.is_valid():
		return origin.call()
	var anchor: Callable = candidate.get("anchor", Callable())
	return anchor.call() if anchor.is_valid() else null


static func _door_id(door: Node) -> String:
	return str(door.get(&"door_id"))


static func _gate_id(gate: Node) -> String:
	return str(gate.get(&"gate_id"))


static func _gate_closed(gate: Node) -> bool:
	return not bool(gate.call(&"is_open"))


static func _path_id(node: Node) -> String:
	return str(node.get_path())


func _load_npc_definitions() -> void:
	var constants := Services.constants()
	if constants == null:
		return
	var definitions: Variant = constants.data_file(NPC_DEFINITIONS_FILE)
	if not definitions is Array:
		return
	for entry: Variant in definitions:
		if not entry is Dictionary:
			continue
		var id := str((entry as Dictionary).get("id", ""))
		if id.is_empty():
			continue
		_npc_names[id] = str(entry.get("displayName", id))
