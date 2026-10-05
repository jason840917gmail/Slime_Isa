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
## chests 80 (reach 112), and every NPC in reach for talk 50. A pointer within 64 px of a target's
## pick point chooses it; otherwise the highest priority wins and a tie goes to the smaller id
## (so two NPCs are picked by id, not distance: a Phaser quirk kept). The chosen target shows as
## "Right-click: <prompt>" at the bottom of the screen and a key badge over it. The player's
## interact press (right click, buffered 150 ms) runs `handle_interact`.
##
## Phase 3 screens are stand-ins until then: a chest gives everything at once ("Moved 1 × Verdant
## Key"), an NPC says its first dialogue page as floating text, a workbench does nothing.
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

const GROUP := &"interaction"
const MAIN_GROUP := &"world_main"
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
## Message literals (UniversalSceneWorldController.ts:984-999, :909-915).
const GATE_STUCK_MESSAGE := "The gate will not budge."
const CHEST_GUARDED_PROMPT := "Chest locked by Fatty One Eye"
const CHEST_EMPTY_PROMPT := "Inspect empty chest"
const CHEST_OPEN_PROMPT := "Open chest"
const CHEST_GUARDED_MESSAGE := "Fatty One Eye is guarding this chest!"
const CHEST_MESSAGE_RISE := 48.0
## Chest stand-in texts: one line per stack, stacked upwards.
const CHEST_LINE_SPACING := 18.0
const NO_ROOM_MESSAGE := "No inventory space for that item."
## NPC stand-in: the first page over the NPC.
const TALK_TEXT_RISE := 52.0
const NPC_DEFINITIONS_FILE := "npc-definitions.json"

## The chosen target changed. Payload: {"id": String, "prompt": String} ("" when none).
signal candidate_changed(payload: Dictionary)
## A message was shown. Payload: {"text", "color", "x", "y"} (test hook).
signal message_shown(payload: Dictionary)

var _prompt: InteractionPrompt
var _badge: InteractionBadge
var _current: Dictionary = {}
var _suppressed: bool = false
var _pointer_seen: bool = false
var _npc_names: Dictionary = {}
var _npc_pages: Dictionary = {}


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
	set_suppressed(player != null and bool(player.call(&"is_sleeping")))
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
	return bool(execute.call()) if execute.is_valid() else false


func has_candidate() -> bool:
	return not _current.is_empty()


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


## "Right-click: <prompt>" (the verb follows the `interact` binding).
func prompt_text(candidate: Dictionary) -> String:
	return "%s: %s" % [InteractionPrompt.interact_verb(), str(candidate.get("prompt", ""))]


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
	_append(out, _nearest(at, WorkbenchScript.GROUP, PRIORITY_WORKBENCH, "world-workbenches:", _path_id, Callable(), _use_workbench))
	return out


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


## Every NPC in reach (QuestNpcController `getCandidates`, talk only: quests are a later phase).
func _npc_candidates(at: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
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
		out.append({
			"id": "quest-npcs:%s:talk" % str(npc.call(&"get_instance_id_key")),
			"prompt": "Talk to " + str(_npc_names[definition_id]),
			"priority": PRIORITY_TALK,
			"anchor": func() -> Vector2: return (npc.call(&"get_phaser_position") as Vector2) + NPC_BADGE_OFFSET,
			"origin": func() -> Vector2: return (npc.call(&"get_phaser_position") as Vector2) - Vector2(0.0, NPC_BODY_RISE),
			"execute": func() -> bool: return _talk(npc, definition_id),
		})
	return out


# --- execute per kind (spec 7.3) ---------------------------------------------------------------

func _use_door(door: Node) -> bool:
	var result: Dictionary = door.call(&"use")
	return str(result.get("status", "")) == "queued"


func _use_gate(gate: Node) -> bool:
	var result := str(gate.call(&"try_unlock"))
	var at: Vector2 = (gate.call(&"origin") as Vector2) - Vector2(0.0, float(gate.get(&"badge_rise")))
	if result == "unlocked" or result == "already-unlocked":
		gate.call(&"open")
		_message(at, str(gate.get(&"unlocked_message")), &"green")
	elif result == "missing-item":
		_message(at, str(gate.get(&"locked_message")), &"white")
	else:
		_message(at, GATE_STUCK_MESSAGE, &"white")
	return true


## Opens the chest; until the Phase 3 window exists, everything moves into the bag at once.
func _use_chest(chest: ChestScript) -> bool:
	var at := chest.origin() - Vector2(0.0, CHEST_MESSAGE_RISE)
	if chest.request_open() == "guarded":
		_message(at, CHEST_GUARDED_MESSAGE, &"white")
		return true
	var line := 0
	for result: Dictionary in chest.take_all():
		var line_at := at - Vector2(0.0, CHEST_LINE_SPACING * line)
		if int(result["moved"]) > 0:
			_message(line_at, "Moved %d × %s" % [int(result["moved"]), ItemCatalog.item_name(str(result["item_id"]))], &"cyan", false)
		else:
			_message(line_at, NO_ROOM_MESSAGE, &"white", false)
		line += 1
	chest.close()
	return true


func _use_bed(bed: Node) -> bool:
	var player := _player()
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	if player == null or get_tree().paused:
		return false
	if main != null and main.has_method(&"is_transitioning") and bool(main.call(&"is_transitioning")):
		return false
	return bool(player.call(&"sleep_in", bed.call(&"sleep_request")))


## The crafting window is a later phase: nothing happens yet.
func _use_workbench(_bench: Node) -> bool:
	return false


## Stand-in for the dialogue box: the first page over the NPC; the NPC is released at once.
func _talk(npc: Node, definition_id: String) -> bool:
	var release: Variant = npc.call(&"acquire_interaction_lock") if npc.has_method(&"acquire_interaction_lock") else null
	var run := Services.run()
	if run != null:
		run.record_talk(definition_id)
	var pages: Array = _npc_pages.get(definition_id, [])
	if not pages.is_empty():
		var at: Vector2 = (npc.call(&"get_phaser_position") as Vector2) - Vector2(0.0, TALK_TEXT_RISE)
		_message(at, str(pages[0]), &"white", false)
	if release is Callable and (release as Callable).is_valid():
		(release as Callable).call()
	return true


# --- helpers -----------------------------------------------------------------------------------

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
		var pages: Array = entry.get("dialogue", [])
		if pages.is_empty() and entry.has("description"):
			pages = [str(entry["description"])]
		if pages.is_empty():
			pages = ["Hello!"]
		_npc_pages[id] = pages
