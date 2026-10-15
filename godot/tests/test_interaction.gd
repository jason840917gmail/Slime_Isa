extends RefCounted
## The interact button, doors, gates, chests and beds (docs/godot/specs/interaction.md 8.8).
## level-1: `home-door` (origin (1081, 903), a north door pushed into -> slime-home; never offered
## to the interact key since 2026-10-14; an open archway since 2026-10-15), the Verdant
## gate (origin (3776, 768), green key, pushed open since 2026-10-15), the guarded chest in Fatty's
## camp (`level-1-fatty-guarded-chest`, a green key). slime-home: `house-door` ((448, 694), south,
## a real door with the room's door picture `house-door-art`),
## the west bed ((160, 340): sleep at (159.625, 275.95), wake at (159.625, 356)).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ChestScript := preload("res://game/scripts/chest.gd")
const GateScript := preload("res://game/scripts/gate.gd")
const InteractionController := preload("res://game/interaction/interaction_controller.gd")

const HOME_DOOR_ARRIVAL := Vector2(1083.0, 954.0)
const GATE_ID := "level-1-east-verdant-gate"
const GATE_STAND := Vector2(3776.0, 840.0)
const KEY := "green-key"
const CHEST_ID := "level-1-fatty-guarded-chest"
const BED_STAND := Vector2(160.0, 400.0)
const BED_WAKE := Vector2(159.625, 356.0)


func test_no_candidate_at_spawn(t: TestContext) -> void:
	await t.steps(2)
	var interaction := _interaction(t)
	t.check(not interaction.has_candidate(), "a target at the spawn: %s" % [interaction.current().get("id")])
	t.check(not interaction.get_prompt().is_showing(), "the prompt shows at the spawn")
	t.check(not interaction.get_badge().visible, "the badge shows at the spawn")


func test_door_not_offered_to_interact(t: TestContext) -> void:
	var interaction := _interaction(t)
	t.teleport_player(HOME_DOOR_ARRIVAL)
	await t.steps(2)
	t.check(not str(interaction.current().get("id", "")).begins_with("world-doors:"), "a door is offered: %s" % [interaction.current().get("id")])
	t.tap(&"interact")
	await t.sim_wait(600.0)
	t.check(not t.main.is_transitioning(), "the interact key went through the door")
	t.equal(t.world().map_id(), "level-1", "map after the interact key")


func test_door_travel_round_trip(t: TestContext) -> void:
	t.teleport_player(HOME_DOOR_ARRIVAL)
	await t.steps(2)
	# Push into the north door: walk up into the doorway and keep pushing (doorPushMs); the leaf
	# swings open (doorOpenMs), then the iris closes.
	t.press(&"move_up")
	var went := await t.until(func() -> bool: return t.main.is_transitioning(), 1500.0, 3000.0)
	t.release(&"move_up")
	if not t.check(went, "pushing into the home door did not travel"):
		return
	if not t.check(await _arrive(t, "slime-home"), "the door did not lead to slime-home"):
		return
	# Sided doors (north outside, south inside): the slime walks out of the doorway into the room,
	# facing in, and stops once clear of the doorway posts (game/player/door_walk_out.gd).
	# The way out is a real door (the room's door picture): it stands open behind the slime while it
	# walks in, then closes.
	var exit := _door(t, "house-door")
	if t.check(exit != null and exit.has_leaf(), "the slime-home way out has no leaf"):
		t.check(exit.get_node(^"../../house-door-art/DoorLeaf").progress > 0.5, "the way out is not open on arrival")
	t.check(await _walked_out(t), "the slime did not stop walking out of the slime-home door")
	var inside := t.player().get_centre()
	t.near(inside.x, 448.0, 0.01, "walked straight out of the slime-home doorway")
	t.between(inside.y, 600.0, 640.0, "stopped just inside slime-home (door at 694)")
	t.near_vec(t.player().get_facing(), Vector2.UP, 0.01, "facing into slime-home")
	t.equal(t.world().camera_mode(), "fixed", "slime-home camera")
	await t.sim_wait(600.0)
	if exit != null and exit.has_leaf():
		t.near(exit.get_node(^"../../house-door-art/DoorLeaf").progress, 0.0, 0.001, "the way out closed behind the slime")
	t.check(not str(_interaction(t).current().get("id", "")).begins_with("world-doors:"), "the way out is offered to the interact key")
	# Walking down into the way out takes the slime back.
	t.press(&"move_down")
	went = await t.until(func() -> bool: return t.main.is_transitioning(), 2000.0, 4000.0)
	t.release(&"move_down")
	if not t.check(went, "walking into the slime-home way out did not travel"):
		return
	if not t.check(await _arrive(t, "level-1"), "the slime-home door did not lead back"):
		return
	# The forge has no door (owner, 2026-10-15): an open archway, its painted fire showing.
	var door := _door(t, "home-door")
	if t.check(door != null, "no home door"):
		t.equal(door.kind, "opening", "the home door's kind")
		t.check(not door.has_leaf(), "the forge archway has a leaf")
	t.check(await _walked_out(t), "the slime did not stop walking out of the home door")
	var outside := t.player().get_centre()
	t.near(outside.x, 1081.0, 0.01, "walked straight out of the home door")
	t.between(outside.y, 905.0, 960.0, "stopped just in front of the house (door at 903)")
	t.near_vec(t.player().get_facing(), Vector2.DOWN, 0.01, "facing away from the house")


## A door with a lock (door.gd `gate`, set here on the home door): pushing without the key says the
## locked line once per push and stays; with the key the push unlocks it, spends the key and goes in.
func test_locked_door_push(t: TestContext) -> void:
	var run := Services.run()
	var door := _door(t, "home-door")
	if not t.check(door != null, "no home door"):
		return
	door.gate = {"id": "test-home-lock", "requiredItemId": KEY, "consumeOnUnlock": true, "lockedMessage": "Locked."}
	t.teleport_player(HOME_DOOR_ARRIVAL)
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(1500.0)
	t.release(&"move_up")
	t.check(not t.main.is_transitioning(), "a locked door let the slime through")
	t.equal(t.world().map_id(), "level-1", "map at the locked door")
	t.check(door.get(&"_refused"), "the locked door did not refuse the push")
	run.quiet_items = true
	run.add_item(KEY, 1)
	await t.steps(2)
	t.press(&"move_up")
	var went := await t.until(func() -> bool: return t.main.is_transitioning(), 1500.0, 3000.0)
	t.release(&"move_up")
	t.check(went, "the key did not open the locked door")
	t.equal(run.item_count(KEY), 0, "green keys left after the door")
	t.check(run.is_gate_unlocked("level-1", "test-home-lock"), "the door lock is not remembered")
	if went:
		t.check(await _arrive(t, "slime-home"), "the unlocked door did not lead to slime-home")


## Gates are pushed (owner, 2026-10-15): not offered to the interact key; pushing up into the gate
## without the key says the locked line once per push and the gate stays shut.
func test_gate_locked_without_key(t: TestContext) -> void:
	var interaction := _interaction(t)
	var gate := _gate(t)
	if not t.check(gate != null, "no gate"):
		return
	var messages: Array = []
	gate.message_shown.connect(func(payload: Dictionary) -> void: messages.append(payload))
	t.teleport_player(GATE_STAND)
	await t.steps(2)
	t.check(not str(interaction.current().get("id", "")).begins_with("world-gates:"), "the gate is offered: %s" % [interaction.current().get("id")])
	t.tap(&"interact")
	await t.steps(3)
	t.equal(messages.size(), 0, "messages after the interact key")
	t.press(&"move_up")
	await t.sim_wait(1500.0)
	t.release(&"move_up")
	if t.check(messages.size() == 1, "%d messages after one long push" % messages.size()):
		t.equal(messages[0]["text"], "The Verdant Gate is locked. Fatty One Eye guards the Green Key.", "locked message")
		t.equal(messages[0]["color"], "white", "locked message colour")
		t.near_vec(Vector2(messages[0]["x"], messages[0]["y"]), Vector2(3776.0, 648.0), 0.01, "locked message position")
	await t.steps(3)
	t.press(&"move_up")
	await t.sim_wait(500.0)
	t.release(&"move_up")
	t.equal(messages.size(), 2, "messages after a second push")
	t.check(not gate.is_open(), "the gate opened without the key")
	t.check(not Services.run().is_gate_unlocked("level-1", GATE_ID), "the gate record unlocked")


func test_gate_unlock_consumes_key_and_persists(t: TestContext) -> void:
	var run := Services.run()
	run.quiet_items = true
	run.add_item(KEY, 1)
	var interaction := _interaction(t)
	var gate := _gate(t)
	if not t.check(gate != null, "no gate"):
		return
	var messages: Array = []
	gate.message_shown.connect(func(payload: Dictionary) -> void: messages.append(payload))
	t.teleport_player(GATE_STAND)
	await t.steps(2)
	t.press(&"move_up")
	await t.until(func() -> bool: return gate.is_open(), 1500.0, 3000.0)
	t.release(&"move_up")
	await t.steps(3)
	t.check(run.is_gate_unlocked("level-1", GATE_ID), "the gate record is not unlocked")
	t.equal(run.item_count(KEY), 0, "green keys left")
	t.check(gate.is_open(), "the gate is closed")
	t.equal(gate.visual.frame, gate.open_frame, "gate frame")
	for shape: Node in gate.doors.find_children("*", "CollisionShape2D", true, false):
		t.check((shape as CollisionShape2D).disabled, "a gate door shape still collides")
	t.check(messages.size() == 1 and messages[0]["text"] == "The Verdant Gate swings open!" and messages[0]["color"] == "green",
		"unlock message %s" % [messages])
	t.check(not str(interaction.current().get("id", "")).begins_with("world-gates:"), "the gate is offered to the interact key")
	t.main.travel_to("level-1", "south")
	if not t.check(await _arrive(t, "level-1", true), "level-1 did not reload"):
		return
	gate = _gate(t)
	t.check(gate != null and gate.is_open(), "the gate is closed after a reload")


func test_gate_open_handler_not_persisted(t: TestContext) -> void:
	var gate := _gate(t)
	if not t.check(gate != null, "no gate"):
		return
	var opened: Array = []
	gate.opened.connect(func(payload: Dictionary) -> void: opened.append(payload))
	gate.open({})
	gate.open({})
	t.equal(opened, [{"gateId": GATE_ID}], "opened signals")
	t.equal(gate.visual.frame, gate.open_frame, "frame after open()")
	t.check(not Services.run().is_gate_unlocked("level-1", GATE_ID), "open() saved the gate")


func test_chest_domain(t: TestContext) -> void:
	var run := Services.run()
	var chest := _chest(t, CHEST_ID)
	if not t.check(chest != null, "no %s" % CHEST_ID):
		return
	t.equal(chest.remaining(), {KEY: 1}, "chest contents")
	var moves: Array = []
	chest.stack_transferred.connect(func(payload: Dictionary) -> void: moves.append(payload))
	t.equal(chest.transfer_stack(KEY), 1, "keys moved")
	t.equal(run.item_count(KEY), 1, "keys in the bag")
	t.equal(chest.remaining(), {}, "chest after the move")
	t.equal(moves, [{"itemId": KEY, "moved": 1}], "stack_transferred")
	await t.steps(2)
	var visual := chest.get_parent().find_children("*", "Sprite2D", true, false)[0] as Sprite2D
	t.equal(visual.frame, 1, "empty chest frame")
	t.equal(chest.transfer_stack(KEY), 0, "a second move")
	t.equal(moves.size(), 1, "a second stack_transferred")


## Using a chest opens the chest window on it: nothing moves into the bag and no message shows
## (the window itself is test_chest_window.gd).
func test_use_chest_opens_window(t: TestContext) -> void:
	var chest := _chest(t, CHEST_ID)
	if not t.check(chest != null, "no %s" % CHEST_ID):
		return
	var interaction := _interaction(t)
	var messages: Array = []
	interaction.message_shown.connect(func(payload: Dictionary) -> void: messages.append(payload))
	var closed: Array = []
	chest.closed.connect(func(payload: Dictionary) -> void: closed.append(payload))
	t.check(interaction.call(&"_use_chest", chest), "using the chest failed")
	var view := t.tree.get_first_node_in_group(&"chest_window")
	if not t.check(view != null, "no chest window"):
		return
	t.check(view.call(&"current_chest") == chest, "the window does not show the chest")
	t.check(t.tree.get_first_node_in_group(&"game_windows").call(&"is_open", &"chest-inventory"), "the chest window is not open")
	t.equal(Services.run().item_count(KEY), 0, "keys in the bag")
	t.equal(messages, [], "messages")
	t.equal(closed.size(), 0, "closed signals")
	view.call(&"close")
	t.equal(closed, [{"instanceId": CHEST_ID}], "closed signals after Close")


func test_bed_sleep_and_wake(t: TestContext) -> void:
	var run := Services.run()
	t.main.travel_to("slime-home", "", "house-door")
	if not t.check(await _arrive(t, "slime-home"), "no slime-home"):
		return
	var interaction := _interaction(t)
	t.teleport_player(BED_STAND)
	await t.steps(2)
	t.equal(interaction.get_prompt().get_text(), "Right-click: Sleep", "bed prompt")
	t.equal(interaction.current().get("priority"), 85, "bed priority")
	t.tap(&"interact")
	await t.steps(3)
	var player := t.player()
	if not t.check(player.is_sleeping(), "the player is not sleeping"):
		return
	t.near_vec(player.get_centre(), BED_WAKE, 0.01, "body at the wake point")
	t.check(player.is_action_locked(), "a sleeper is not action-locked")
	t.check(not interaction.get_prompt().is_showing(), "the prompt shows while asleep")
	t.equal(run.respawn_point(), {"area_id": "slime-home", "map_id": "slime-home", "x": 160.0, "y": 356.0,
		"bed_id": "world.slime-home.west-bed"}, "respawn point")
	t.press(&"move_right")
	await t.steps(5)
	t.check(player.is_sleeping(), "a move before 400 ms woke the sleeper")
	t.release_all()
	await t.sim_wait(450.0)
	t.press(&"move_right")
	await t.steps(3)
	t.release_all()
	t.check(not player.is_sleeping(), "a move after 400 ms did not wake the sleeper")
	t.check(not player.is_action_locked(), "still locked after waking")
	await t.steps(2)
	t.check(interaction.get_prompt().is_showing(), "the prompt did not come back")


func test_sleep_heals(t: TestContext) -> void:
	t.main.travel_to("slime-home", "", "house-door")
	if not t.check(await _arrive(t, "slime-home"), "no slime-home"):
		return
	var player := t.player()
	player.restore_run_state({"hp": 50})
	t.teleport_player(BED_STAND)
	await t.steps(2)
	t.tap(&"interact")
	await t.until(func() -> bool: return player.is_sleeping(), 200.0)
	await t.sim_wait(4000.0)
	t.between(float(player.get_hp()), 55.0, 57.0, "HP after 1 s doze + 3 s sleep (2 HP/s)")


func test_workshop_station_appears(t: TestContext) -> void:
	Services.run().set_flag("workshop.restored")
	await t.steps(3)
	var interaction := _interaction(t)
	t.teleport_player(Vector2(640.0, 470.0))
	await t.steps(2)
	t.check(str(interaction.current().get("id", "")).begins_with("world-workbenches:"), "workbench target %s" % [interaction.current().get("id")])
	t.equal(interaction.get_prompt().get_text(), "Right-click: Use the Workshop", "workshop prompt")
	t.equal(interaction.current().get("priority"), 88, "workbench priority")


## Two NPCs in reach: the smaller id wins, not the nearer one (a Phaser quirk kept); the pointer
## picks the one it is near.
func test_npc_tie_breaks_by_id_and_pointer_picks(t: TestContext) -> void:
	var interaction := _interaction(t)
	var lili := _npc(t, "level-1-npc-lili")
	var pip := _npc(t, "level-1-npc-red-slime-boy")
	if not t.check(lili != null and pip != null, "no Lili or Pip"):
		return
	var centre := Vector2(900.0, 1200.0)
	t.teleport_player(centre)
	_place_npc(pip, centre + Vector2(40.0, 0.0))
	_place_npc(lili, centre + Vector2(-80.0, 0.0))
	await t.steps(1)
	interaction.refresh(null)
	t.equal(interaction.current().get("id"), "quest-npcs:level-1-npc-lili:talk", "id tie-break")
	t.equal(interaction.get_prompt().get_text(), "Right-click: Talk to Lili", "talk prompt")
	interaction.refresh(pip.get_phaser_position() - Vector2(0.0, 24.0))
	t.equal(interaction.current().get("id"), "quest-npcs:level-1-npc-red-slime-boy:talk", "pointer pick")


# --- helpers ----------------------------------------------------------------------------------

func _interaction(t: TestContext) -> InteractionController:
	return t.tree.get_first_node_in_group(&"interaction") as InteractionController


func _gate(t: TestContext) -> GateScript:
	for node: Node in t.tree.get_nodes_in_group(&"gate"):
		if node is GateScript and (node as GateScript).gate_id == GATE_ID and not node.get_parent().is_queued_for_deletion():
			return node
	return null


func _chest(t: TestContext, instance_id: String) -> ChestScript:
	for node: Node in t.tree.get_nodes_in_group(&"chest"):
		if node is ChestScript and (node as ChestScript).instance_id == instance_id:
			return node
	return null


func _npc(t: TestContext, instance_id: String) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"npc"):
		if str(node.call(&"get_instance_id_key")) == instance_id:
			return node
	return null


## Puts an NPC (old Phaser position = sprite bottom) at `point` and keeps it there.
func _place_npc(npc: Node, point: Vector2) -> void:
	var body := npc.get(&"body") as CharacterBody2D
	if body == null:
		return
	body.velocity = Vector2.ZERO
	var offset: Vector2 = npc.get_phaser_position() - body.global_position
	body.global_position = point - offset
	body.reset_physics_interpolation()
	if npc.has_method(&"acquire_interaction_lock"):
		npc.call(&"acquire_interaction_lock")


## Waits for a travel to `map_id` to finish (`reload`: also when already in that map).
## Waits for the walk out of a door to end (the iris's hold, then the walk).
func _door(t: TestContext, door_id: String) -> Node:
	for node: Node in t.main.get_tree().get_nodes_in_group(&"door"):
		if str(node.get(&"door_id")) == door_id and t.world().world_root.is_ancestor_of(node):
			return node
	return null


func _walked_out(t: TestContext) -> bool:
	return await t.until(func() -> bool: return t.player() != null and not t.player().is_walking_out(), 2000.0, 4000.0)


func _arrive(t: TestContext, map_id: String, reload: bool = false) -> bool:
	if reload:
		await t.until(func() -> bool: return t.main.is_transitioning(), 200.0)
	var arrived := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == map_id and t.player() != null, 3000.0, 6000.0)
	await t.steps(2)
	return arrived
