extends RefCounted
## The interact button, doors, gates, chests and beds (docs/godot/specs/interaction.md 8.8).
## level-1: `home-door` (origin (270, 856), a north door pushed into -> slime-home; never offered
## to the interact key since 2026-10-14; since 2026-11-13 a real door in the round mushroom house's
## door frame, the house's front at y 889), the Verdant
## gate (origin (1728, 768) in chunk D4, green key, pushed open since 2026-10-15), the guarded chest
## in Fatty's old camp (`level-1-fatty-guarded-chest`, a green key, in D4: the camp moved into his
## Lair on 2026-10-17 and tests/lib/fatty_camp_fixture.gd puts it back for these tests). slime-home
## (a round mushroom room 16 x 12 since 2026-11-20: its `round-walls` at (512, 384), radii (500, 376),
## depth 128, the floor's edge at y 632 below the middle): `house-door`, the ring's `front-door`
## opening (south), the door the ring makes in the game at (512, ~735.7) with its leaf (the style's
## south door leaf, its `DoorLeaf` swinging on it); the west bed ((270, 340): sleep at
## (269.625, 275.95), wake at (269.625, 356)). The crafting station is the lit Forge's in C4
## ((1778, 182)); the Workshop has none since 2026-11-20.
## Since 2026-11-19 the Verdant Gate is a fallen tree (test_release_one_world.gd) and no world holds a
## keyed gate: the tests of the gate locked without its key, unlocked with it and opened by a handler
## are removed.
## level-1 is cut into chunk worlds (docs/godot/WORLD_ATLAS.md "Chunk worlds"): the tests start in
## the village chunk C4 (`level-1-c4`, origin (0, 0)); the gate and chest tests travel east into D4
## (`level-1-d4`, its origin at level-1's (2048, 0)), so their places are D4's.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const ChestScript := preload("res://game/scripts/chest.gd")
const InteractionController := preload("res://game/interaction/interaction_controller.gd")
const FattyCampFixture := preload("res://tests/lib/fatty_camp_fixture.gd")

## Just in front of the home door (centre; its trigger's bottom at y 876), below the house's front.
const HOME_DOOR_ARRIVAL := Vector2(270.0, 880.0)
## The home door's x (C4) and slime-home's door's x (the ring's middle).
const HOME_DOOR_X := 270.0
const ROOM_DOOR_X := 512.0
## The chunk of the Verdant gate and Fatty's camp.
const EAST_MAP := "level-1-d4"
const KEY := "green-key"
const CHEST_ID := "level-1-fatty-guarded-chest"
const BED_STAND := Vector2(270.0, 400.0)
const BED_WAKE := Vector2(269.625, 356.0)
## In front of the Forge (`level-1-forge`, C4 (1778, 182), its station's reach 130): 40 south of its
## station.
const FORGE_STAND_OFFSET := Vector2(0.0, 40.0)


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
	t.equal(t.world().map_id(), "level-1-c4", "map after the interact key")


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
	# The way out is a real door (the round walls' door, its leaf the style's south door leaf): it
	# stands open behind the slime while it walks in, then closes.
	var exit := _door(t, "house-door")
	if t.check(exit != null and exit.has_leaf(), "the slime-home way out has no leaf"):
		t.equal(exit.kind, "door", "the slime-home way out's kind")
		t.equal(exit.side, "south", "the slime-home way out's side")
		t.check(_leaf(exit) != null and _leaf(exit).progress > 0.5, "the way out is not open on arrival")
	t.check(await _walked_out(t), "the slime did not stop walking out of the slime-home door")
	var inside := t.player().get_centre()
	t.near(inside.x, ROOM_DOOR_X, 0.01, "walked straight out of the slime-home doorway")
	# Feet from the door (y ~735.7) up until clear of the ring's walls beside the passage (their floor
	# edge ~623 at 100 either side of the middle) and 6 more; the centre is 27.56 above the feet.
	t.between(inside.y, 555.0, 625.0, "stopped just inside slime-home (its floor's edge at 632, the door at ~736)")
	t.near_vec(t.player().get_facing(), Vector2.UP, 0.01, "facing into slime-home")
	t.equal(t.world().camera_mode(), "fixed", "slime-home camera")
	await t.sim_wait(600.0)
	# Found again: the ring makes its doors anew whenever it is built again.
	exit = _door(t, "house-door")
	if exit != null and exit.has_leaf() and _leaf(exit) != null:
		t.near(_leaf(exit).progress, 0.0, 0.001, "the way out closed behind the slime")
	t.check(not str(_interaction(t).current().get("id", "")).begins_with("world-doors:"), "the way out is offered to the interact key")
	# Walking down into the way out takes the slime back (into the chunk that holds the home door).
	t.press(&"move_down")
	went = await t.until(func() -> bool: return t.main.is_transitioning(), 2000.0, 4000.0)
	t.release(&"move_down")
	if not t.check(went, "walking into the slime-home way out did not travel"):
		return
	if not t.check(await _arrive(t, "level-1-c4"), "the slime-home door did not lead back"):
		return
	# The home door is a real door in the round mushroom house's door frame (since 2026-11-13): the
	# slime comes out in front of the house (its feet from the house's front, y 890) and walks out.
	var door := _door(t, "home-door")
	if t.check(door != null, "no home door"):
		t.equal(door.kind, "door", "the home door's kind")
		t.check(door.has_leaf(), "the home door has no leaf")
	t.check(await _walked_out(t), "the slime did not stop walking out of the home door")
	var outside := t.player().get_centre()
	t.near(outside.x, HOME_DOOR_X, 0.01, "walked straight out of the home door")
	t.between(outside.y, 856.0, 930.0, "stopped just in front of the house (door at 856, its front at 889)")
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
	t.equal(t.world().map_id(), "level-1-c4", "map at the locked door")
	t.check(door.get(&"_refused"), "the locked door did not refuse the push")
	run.quiet_items = true
	run.add_item(KEY, 1)
	await t.steps(2)
	t.press(&"move_up")
	var went := await t.until(func() -> bool: return t.main.is_transitioning(), 1500.0, 3000.0)
	t.release(&"move_up")
	t.check(went, "the key did not open the locked door")
	t.equal(run.item_count(KEY), 0, "green keys left after the door")
	t.check(run.is_gate_unlocked("level-1-c4", "test-home-lock"), "the door lock is not remembered")
	if went:
		t.check(await _arrive(t, "slime-home"), "the unlocked door did not lead to slime-home")


## Gates are pushed (owner, 2026-10-15): not offered to the interact key; pushing up into the gate
## without the key says the locked line once per push and the gate stays shut.
func test_chest_domain(t: TestContext) -> void:
	if not await _to_east(t):
		return
	FattyCampFixture.ensure(t.tree)
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
	if not await _to_east(t):
		return
	FattyCampFixture.ensure(t.tree)
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
	t.equal(run.respawn_point(), {"area_id": "slime-home", "map_id": "slime-home", "x": 270.0, "y": 356.0,
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


## The lit Forge's station (`forge.restored`) is offered in front of it; the Workshop has no station
## since 2026-11-20 (Pip carves there: test_main_quest.gd).
func test_forge_station_appears(t: TestContext) -> void:
	Services.run().set_flag("forge.restored")
	await t.steps(3)
	var interaction := _interaction(t)
	var station := _station(t, "forge")
	if not t.check(station != null, "the lit Forge has no station"):
		return
	t.teleport_player((station.call(&"origin") as Vector2) + FORGE_STAND_OFFSET)
	await t.steps(2)
	t.check(str(interaction.current().get("id", "")).begins_with("world-workbenches:"), "workbench target %s" % [interaction.current().get("id")])
	t.equal(interaction.get_prompt().get_text(), "Right-click: Use the Forge", "forge prompt")
	t.equal(interaction.current().get("priority"), 88, "workbench priority")
	t.check(_station(t, "workshop") == null, "the Workshop still has a station")


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


func _chest(t: TestContext, instance_id: String) -> ChestScript:
	for node: Node in t.tree.get_nodes_in_group(&"chest"):
		if node is ChestScript and (node as ChestScript).instance_id == instance_id:
			return node
	return null


## The crafting station of `context` ("forge") in the tree, or null.
func _station(t: TestContext, context: String) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"crafting_station"):
		if str(node.get(&"recipe_context")) == context and node.is_inside_tree():
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


## Travels from the village chunk into D4 (the gate and Fatty's camp); false (a failed check) when
## the travel was refused or never arrived.
func _to_east(t: TestContext) -> bool:
	if not t.check(t.main.travel_to(EAST_MAP, "west"), "travel to %s was refused" % EAST_MAP):
		return false
	return t.check(await _arrive(t, EAST_MAP), "no %s" % EAST_MAP)


## The leaf a real door swings (door.gd builds its `DoorLeaf` on its `house_art`), or null.
static func _leaf(door: Node) -> Node:
	var art := door.get(&"house_art") as Node
	return art.get_node_or_null(^"DoorLeaf") if art != null and is_instance_valid(art) else null


## The door `door_id` of the current world.
func _door(t: TestContext, door_id: String) -> Node:
	for node: Node in t.main.get_tree().get_nodes_in_group(&"door"):
		if str(node.get(&"door_id")) == door_id and t.world().world_root.is_ancestor_of(node):
			return node
	return null


## Waits for the walk out of a door to end (the iris's hold, then the walk).
func _walked_out(t: TestContext) -> bool:
	return await t.until(func() -> bool: return t.player() != null and not t.player().is_walking_out(), 2000.0, 4000.0)


## Waits for a travel to `map_id` to finish (`reload`: also when already in that map).
func _arrive(t: TestContext, map_id: String, reload: bool = false) -> bool:
	if reload:
		await t.until(func() -> bool: return t.main.is_transitioning(), 200.0)
	var arrived := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == map_id and t.player() != null, 3000.0, 6000.0)
	await t.steps(2)
	return arrived
