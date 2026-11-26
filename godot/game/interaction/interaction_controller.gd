extends Node2D
class_name InteractionController
## The interact button (Phaser `features/interaction/InteractionRouter.ts` with the providers of
## `UniversalSceneWorldController.ts` and `QuestNpcController.ts`; interaction spec 2, 7).
## A child "Interaction" of main, made once and kept across world swaps (it finds the current
## world's interactables through their groups). PAUSABLE: it stops with hit-stop and menus,
## leaving the last prompt on screen as Phaser does.
##
## Every physics step (before the player, priority -10) each provider offers at most one target,
## the nearest of its kind within that object's reach: workbenches 88, beds 85,
## chests 80 (reach 112), and every NPC in reach (quest turn-in 100, offer 90, reoffer 85, talk 50,
## from the quest service). A building (`reach_from_walls`: a restoration site, the Forge's station)
## measures its reach from its walls, the collision boxes of the body it belongs to, not from the
## middle of its base. A pointer within 64 px of a target's pick point chooses it; otherwise the
## nearest target wins (owner, 2026-11-21, replacing Phaser's highest priority first: "I'm closer to
## Pip but the interaction is with the shop"): each target's `distance` from the slime, less
## `interaction.facingBonusPx` as much as the slime faces it; a tie goes to the higher priority, then
## the smaller id. The chosen target shows as "Right-click: <prompt>" at the bottom of the screen and
## a key badge over it. The player's interact press (right click, buffered 150 ms) runs
## `handle_interact`.
##
## A chest opens the chest window (chest.gd hands itself to game/ui/screens/chest_window.gd). An
## NPC opens its conversation (the quest service: dialogue box, offer and turn-in window). A
## workbench opens the crafting window for its site (game/ui/screens/menu_windows.gd).
##
## Doors, ladders and holes are not offered (owner, 2026-10-14: no keys for transitions): the slime
## goes through them by pushing into them (game/scripts/door.gd). Gates are not offered either
## (owner, 2026-10-15): pushed with the key they open (game/scripts/gate.gd).
##
## Owner: interaction.

const Services := preload("res://game/shared/services.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const InteractionPrompt := preload("res://game/interaction/interaction_prompt.gd")
const InteractionBadge := preload("res://game/interaction/interaction_badge.gd")
const ChestScript := preload("res://game/scripts/chest.gd")
const BedScript := preload("res://game/scripts/bed.gd")
const BathScript := preload("res://game/scripts/bath.gd")
const WorkbenchScript := preload("res://game/scripts/workbench.gd")
const PlacedFurniture := preload("res://game/building/placed_furniture.gd")

const GROUP := &"interaction"
const MAIN_GROUP := &"world_main"
const FURNITURE_GROUP := &"furniture_placement"
## InteractionRouter.ts:44.
const POINTER_PICK_PX := 64.0
## Two targets this close in the choice's score are a tie (priority, then id, decide).
const SCORE_TIE := 0.5
## UniversalSceneWorldController.ts:343-345.
const TARGET_BODY_RISE_PX := 24.0
const CHEST_REACH := 112.0
const CHEST_BADGE_RISE := 56.0
## QuestNpcController.ts:12-16.
const NPC_REACH := 96.0
const NPC_BADGE_OFFSET := Vector2(30.0, -30.0)
const NPC_BODY_RISE := 24.0
const PRIORITY_WORKBENCH := 88
const PRIORITY_BED := 85
const PRIORITY_BATH := 84
const PRIORITY_CHEST := 80
const PRIORITY_TALK := 50
const PRIORITY_RESTORATION := 89
const PRIORITY_GULP := 60
## Things the slime works with the interact key (a worm lever, a winch; Fatty's Lair,
## docs/godot/DUNGEONS.md): nodes in USABLE_GROUP answering `origin()`, `interact_radius`, `prompt`,
## `badge_rise`, `use() -> bool` and, optionally, `can_use() -> bool` (not offered while false).
const USABLE_GROUP := &"usable"
const PRIORITY_USE := 70
## Message literals (UniversalSceneWorldController.ts:984-999, :909-915).
const CHEST_GUARDED_PROMPT := "Chest locked by Fatty One Eye"
const CHEST_EMPTY_PROMPT := "Inspect empty chest"
const CHEST_OPEN_PROMPT := "Open chest"
const CHEST_GUARDED_MESSAGE := "Fatty One Eye is guarding this chest!"
const CHEST_MESSAGE_RISE := 48.0
const NPC_DEFINITIONS_FILE := "npc-definitions.json"
## game/scripts/essence.gd GROUP: essences on the ground.
const ESSENCE_GROUP := &"essence"
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


func _physics_process(_delta: float) -> void:
	var player := _player()
	# Sleeping, bathing or placing furniture offers nothing (WorldScene.ts:820).
	var furniture := get_tree().get_first_node_in_group(FURNITURE_GROUP)
	var placing := furniture != null and bool(furniture.call(&"is_active"))
	set_suppressed((player != null and bool(player.call(&"is_resting"))) or placing)
	# Keys only: the nearest target the slime faces wins (no pointer picks).
	refresh(null)


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


## InteractionRouter.choose (spec 2.4). A `pointer` (a world point; tests) within POINTER_PICK_PX of a
## target's pick point picks it; otherwise the nearest target the slime faces wins.
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
		var player := _player()
		var centre: Vector2 = player.call(&"get_centre") if player != null else Vector2.ZERO
		var facing: Vector2 = player.call(&"get_facing") if player != null and player.has_method(&"get_facing") else Vector2.ZERO
		var constants := Services.constants()
		var bonus := constants.number("interaction.facingBonusPx") if constants != null else 0.0
		var best_score := INF
		for candidate in candidates:
			var score := _score(candidate, centre, facing, bonus)
			if not best.is_empty():
				if score > best_score + SCORE_TIE:
					continue
				if absf(score - best_score) <= SCORE_TIE:
					var priority := int(candidate["priority"])
					var best_priority := int(best["priority"])
					if priority < best_priority or (priority == best_priority and str(candidate["id"]) > str(best["id"])):
						continue
			best = candidate
			best_score = score
	return best


## How near `candidate` is for the choice: its `distance` from the slime (else its pick point's), less
## `bonus` times how squarely the slime at `centre` faces it.
static func _score(candidate: Dictionary, centre: Vector2, facing: Vector2, bonus: float) -> float:
	var at: Variant = _pick_point(candidate)
	var distance := float(candidate.get("distance", (at as Vector2).distance_to(centre) if at is Vector2 else INF))
	if at is Vector2 and facing != Vector2.ZERO and (at as Vector2) != centre:
		distance -= bonus * maxf(0.0, facing.normalized().dot(((at as Vector2) - centre).normalized()))
	return distance


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


## What identifies `candidate` across polls: its node when it has one (an NPC keeps it while its
## quest kind changes), else its id.
static func key_of(candidate: Dictionary) -> Variant:
	var node: Variant = candidate.get("node")
	if is_instance_valid(node) and node is Node:
		return node
	return str(candidate.get("id", ""))


## True when `candidate` is the target `key` names (`key_of`).
static func matches(candidate: Dictionary, key: Variant) -> bool:
	if candidate.is_empty() or key == null:
		return false
	if key is Node:
		var node: Variant = candidate.get("node")
		return is_instance_valid(key) and node is Node and node == key
	return str(candidate.get("id", "")) == str(key)


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

## Phaser provider order: quest NPCs, chests, (doors and gates: pushed into, no longer offered),
## beds, workbenches.
func _gather() -> Array[Dictionary]:
	var player := _player()
	if player == null:
		return []
	return _gather_at(player.call(&"get_centre"))


## The targets in reach of `at` (the slime's centre).
func _gather_at(at: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _player() == null:
		return out
	out.append_array(_npc_candidates(at))
	_append(out, _chest_candidate(at))
	_append(out, _nearest(at, BedScript.GROUP, PRIORITY_BED, "world-beds:", _path_id, Callable(), _use_bed))
	_append(out, _nearest(at, BathScript.GROUP, PRIORITY_BATH, "world-baths:", _path_id, Callable(), _use_bath))
	_append(out, _with_pick_up(_nearest(at, WorkbenchScript.GROUP, PRIORITY_WORKBENCH, "world-workbenches:", _path_id, Callable(), _use_workbench)))
	_append(out, _nearest(at, &"restoration_site", PRIORITY_RESTORATION, "world-restorations:", _path_id, Callable(), _use_restoration))
	_append(out, _nearest(at, USABLE_GROUP, PRIORITY_USE, "world-usables:", _path_id, _can_use, _use_usable))
	_append(out, _essence_candidate(at))
	return out


## A usable (USABLE_GROUP) is offered unless its `can_use()` says no.
static func _can_use(node: Node) -> bool:
	return not node.has_method(&"can_use") or bool(node.call(&"can_use"))


## Works a usable (a lever, a winch), not while the game is paused or the world changes.
func _use_usable(node: Node) -> bool:
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	if get_tree().paused or (main != null and main.has_method(&"is_transitioning") and bool(main.call(&"is_transitioning"))):
		return false
	return bool(node.call(&"use"))


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


## An essence on the ground in reach (owner, 2026-10-08): "Pick up Stone Essence" puts it in the
## bag (walking over it never does; Q sucks it into the slime instead). The nearest takeable
## essence within its own `interact_radius` of `at`.
func _essence_candidate(at: Vector2) -> Dictionary:
	var essence: Node = null
	var best_distance := INF
	for node: Node in get_tree().get_nodes_in_group(ESSENCE_GROUP):
		if not bool(node.call(&"can_take")):
			continue
		var distance := at.distance_to(node.call(&"origin"))
		if distance <= float(node.get(&"interact_radius")) and distance < best_distance:
			essence = node
			best_distance = distance
	if essence == null:
		return {}
	var essence_at: Vector2 = essence.call(&"origin")
	return {
		"id": "essences:%d" % essence.get_instance_id(),
		"prompt": "Pick up " + str(essence.call(&"display_name")),
		"priority": PRIORITY_GULP,
		"distance": best_distance,
		"origin": func() -> Vector2: return essence_at,
		"execute": func() -> bool: return is_instance_valid(essence) and bool(essence.call(&"pick_up")),
		"node": essence,
	}


## The nearest node of `group` within its own `interact_radius` (exact ties: the first found).
func _nearest(at: Vector2, group: StringName, priority: int, prefix: String, key: Callable, offer: Callable, use: Callable) -> Dictionary:
	var best: Node = null
	var best_distance := INF
	for node: Node in get_tree().get_nodes_in_group(group):
		if not node.is_inside_tree() or (offer.is_valid() and not bool(offer.call(node))):
			continue
		var distance := reach_distance(node, at)
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
		"distance": best_distance,
		"anchor": func() -> Vector2: return (target.call(&"origin") as Vector2) - Vector2(0.0, float(target.get(&"badge_rise"))),
		"origin": func() -> Vector2: return (target.call(&"origin") as Vector2) - Vector2(0.0, TARGET_BODY_RISE_PX),
		"execute": func() -> bool: return bool(use.call(target)),
		"node": target,
	}


## How far `at` is from `node` for its reach: from the walls of the body it belongs to when it
## measures from them (`reach_from_walls`: a building), else from its `origin()`.
static func reach_distance(node: Node, at: Vector2) -> float:
	if node.get(&"reach_from_walls") == true:
		var walls := wall_distance(node, at)
		if walls >= 0.0:
			return walls
	return at.distance_to(node.call(&"origin"))


## The distance from `at` to the walls of the body `node` belongs to (its nearest CollisionObject2D
## ancestor's enabled rectangle and polygon shapes, each as its box; 0 inside one); -1 without any.
static func wall_distance(node: Node, at: Vector2) -> float:
	var body := node.get_parent()
	while body != null and not body is CollisionObject2D:
		body = body.get_parent()
	if body == null:
		return -1.0
	var best := -1.0
	for child: Node in body.get_children():
		var box := Rect2()
		var shape := child as CollisionShape2D
		var polygon := child as CollisionPolygon2D
		if shape != null and not shape.disabled and shape.shape is RectangleShape2D:
			var size := (shape.shape as RectangleShape2D).size
			box = shape.global_transform * Rect2(-size * 0.5, size)
		elif polygon != null and not polygon.disabled and not polygon.polygon.is_empty():
			var points := polygon.global_transform * polygon.polygon
			box = Rect2(points[0], Vector2.ZERO)
			for point in points:
				box = box.expand(point)
		else:
			continue
		var dx := maxf(maxf(box.position.x - at.x, 0.0), at.x - box.end.x)
		var dy := maxf(maxf(box.position.y - at.y, 0.0), at.y - box.end.y)
		var distance := Vector2(dx, dy).length()
		if best < 0.0 or distance < best:
			best = distance
	return best


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
		"distance": best_distance,
		"anchor": func() -> Vector2: return chest.origin() - Vector2(0.0, CHEST_BADGE_RISE),
		"origin": func() -> Vector2: return chest.origin() - Vector2(0.0, TARGET_BODY_RISE_PX),
		"execute": func() -> bool: return _use_chest(chest),
		"node": chest,
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
		var distance := at.distance_to(position)
		if distance > NPC_REACH:
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
			"distance": distance,
			"anchor": func() -> Vector2: return (npc.call(&"get_phaser_position") as Vector2) + NPC_BADGE_OFFSET,
			"origin": func() -> Vector2: return (npc.call(&"get_phaser_position") as Vector2) - Vector2(0.0, NPC_BODY_RISE),
			"execute": func() -> bool: return _talk(npc, kind),
			"node": npc,
		})
	return out


# --- execute per kind (spec 7.3) ---------------------------------------------------------------

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


## A bath (game/scripts/bath.gd): refused as a bed is, while paused or travelling.
func _use_bath(bath: Node) -> bool:
	var player := _player()
	var main := get_tree().get_first_node_in_group(MAIN_GROUP)
	if player == null or get_tree().paused:
		return false
	if main != null and main.has_method(&"is_transitioning") and bool(main.call(&"is_transitioning")):
		return false
	return bool(player.call(&"bathe_in", bath.call(&"bath_request")))


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
