extends RefCounted
## The interact button, doors, gates, chests and beds (docs/godot/specs/interaction.md 8.8).
## level-1: `home-door` (origin (1081, 903), reach 90, "Enter house" -> slime-home), the Verdant
## gate (origin (3264, 768), reach 150, green key), the guarded chest in Fatty's camp
## (`level-1-fatty-guarded-chest`, a green key). slime-home: `house-door` ((448, 694), reach 80),
## the west bed ((160, 340): sleep at (159.625, 275.95), wake at (159.625, 356)).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ChestScript := preload("res://game/scripts/chest.gd")
const GateScript := preload("res://game/scripts/gate.gd")
const InteractionController := preload("res://game/interaction/interaction_controller.gd")

const HOME_DOOR_ARRIVAL := Vector2(1083.0, 954.0)
const GATE_ID := "level-1-east-verdant-gate"
const GATE_STAND := Vector2(3264.0, 840.0)
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


func test_door_prompt_and_badge(t: TestContext) -> void:
	var interaction := _interaction(t)
	t.teleport_player(HOME_DOOR_ARRIVAL)
	await t.steps(2)
	t.equal(interaction.current().get("id"), "world-doors:home-door", "door target")
	t.equal(interaction.current().get("priority"), 90, "door priority")
	t.equal(interaction.get_prompt().get_text(), "Right-click: Enter house", "door prompt")
	var badge := interaction.get_badge()
	t.check(badge.visible, "the door badge is hidden")
	t.equal(badge.global_position.x, 1081.0, "badge x")
	t.between(badge.global_position.y, 845.0, 850.0, "badge y (847 with the bob)")
	t.teleport_player(Vector2(1200.0, 954.0))
	await t.steps(2)
	t.check(not interaction.has_candidate(), "the door is still offered 129.5 px away")
	t.check(not interaction.get_prompt().is_showing() and not badge.visible, "prompt or badge still showing")


func test_door_travel_round_trip(t: TestContext) -> void:
	var interaction := _interaction(t)
	t.teleport_player(HOME_DOOR_ARRIVAL)
	await t.steps(2)
	t.tap(&"interact")
	if not t.check(await _arrive(t, "slime-home"), "the door did not lead to slime-home"):
		return
	t.near_vec(t.player().get_centre(), Vector2(480.0, 608.0), 0.01, "arrival in slime-home")
	t.equal(t.world().camera_mode(), "fixed", "slime-home camera")
	await t.steps(2)
	t.check(not interaction.has_candidate(), "a target right at the slime-home arrival (91.8 px from the door)")
	t.teleport_player(Vector2(448.0, 624.0))
	await t.steps(2)
	t.equal(interaction.get_prompt().get_text(), "Right-click: Leave house", "slime-home door prompt")
	t.tap(&"interact")
	if not t.check(await _arrive(t, "level-1"), "the slime-home door did not lead back"):
		return
	t.near_vec(t.player().get_centre(), Vector2(1056.0, 928.0), 0.01, "arrival back in level-1")
	await t.steps(2)
	t.equal(interaction.current().get("id"), "world-doors:home-door", "the home door is offered on arrival (35.4 px)")


func test_gate_locked_without_key(t: TestContext) -> void:
	var interaction := _interaction(t)
	var messages: Array = []
	interaction.message_shown.connect(func(payload: Dictionary) -> void: messages.append(payload))
	t.teleport_player(GATE_STAND)
	await t.steps(2)
	t.equal(interaction.current().get("id"), "world-gates:" + GATE_ID, "gate target")
	t.equal(interaction.current().get("priority"), 95, "gate priority")
	t.equal(interaction.get_prompt().get_text(), "Right-click: Unlock the Verdant Gate", "gate prompt")
	t.tap(&"interact")
	await t.steps(3)
	if t.check(messages.size() == 1, "%d messages" % messages.size()):
		t.equal(messages[0]["text"], "The Verdant Gate is locked. Fatty One Eye guards the Green Key.", "locked message")
		t.equal(messages[0]["color"], "white", "locked message colour")
		t.near_vec(Vector2(messages[0]["x"], messages[0]["y"]), Vector2(3264.0, 648.0), 0.01, "locked message position")
	var gate := _gate(t)
	t.check(gate != null and not gate.is_open(), "the gate opened without the key")
	t.check(not Services.run().is_gate_unlocked("level-1", GATE_ID), "the gate record unlocked")


func test_gate_unlock_consumes_key_and_persists(t: TestContext) -> void:
	var run := Services.run()
	run.add_item(KEY, 1)
	var interaction := _interaction(t)
	var messages: Array = []
	interaction.message_shown.connect(func(payload: Dictionary) -> void: messages.append(payload))
	t.teleport_player(GATE_STAND)
	await t.steps(2)
	t.tap(&"interact")
	await t.steps(3)
	t.check(run.is_gate_unlocked("level-1", GATE_ID), "the gate record is not unlocked")
	t.equal(run.item_count(KEY), 0, "green keys left")
	var gate := _gate(t)
	if t.check(gate != null, "no gate"):
		t.check(gate.is_open(), "the gate is closed")
		t.equal(gate.visual.frame, gate.open_frame, "gate frame")
		for shape: Node in gate.doors.find_children("*", "CollisionShape2D", true, false):
			t.check((shape as CollisionShape2D).disabled, "a gate door shape still collides")
	t.check(messages.size() == 1 and messages[0]["text"] == "The Verdant Gate swings open!" and messages[0]["color"] == "green",
		"unlock message %s" % [messages])
	t.check(not str(interaction.current().get("id", "")).begins_with("world-gates:"), "the open gate is still offered")
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


## The chest stand-in takes everything at once: "Moved 1 × Verdant Key".
func test_chest_take_all_stand_in(t: TestContext) -> void:
	var chest := _chest(t, CHEST_ID)
	if not t.check(chest != null, "no %s" % CHEST_ID):
		return
	var interaction := _interaction(t)
	var messages: Array = []
	interaction.message_shown.connect(func(payload: Dictionary) -> void: messages.append(payload))
	var closed: Array = []
	chest.closed.connect(func(payload: Dictionary) -> void: closed.append(payload))
	t.check(interaction.call(&"_use_chest", chest), "using the chest failed")
	t.equal(Services.run().item_count(KEY), 1, "keys in the bag")
	t.check(messages.size() == 1 and messages[0]["text"] == "Moved 1 × Verdant Key", "chest messages %s" % [messages])
	t.equal(closed.size(), 1, "closed signals")


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
func _arrive(t: TestContext, map_id: String, reload: bool = false) -> bool:
	if reload:
		await t.until(func() -> bool: return t.main.is_transitioning(), 200.0)
	var arrived := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == map_id and t.player() != null, 3000.0, 6000.0)
	await t.steps(2)
	return arrived
