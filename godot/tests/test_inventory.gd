extends RefCounted
## The bag window and the menu key (docs/godot/specs/crafting.md 5, 6, 7, 11.9): the menu key and
## its refusals, the tab strip, the bag model (cells, tags, details, actions), consumables, the
## amount, Destroy, dropping on the ground (placement, records, pickup), the workbench item and the
## pause menu's Inventory button. The trial sword (owner decision C3) is set aside where a test
## needs a given bag.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const InventoryDrops := preload("res://game/inventory/inventory_drops.gd")
const InventoryModel := preload("res://game/ui/screens/inventory_model.gd")
const MenuWindows := preload("res://game/ui/screens/menu_windows.gd")
const InventoryScreen := preload("res://game/ui/screens/inventory_screen.gd")
const CollectibleScript := preload("res://game/scripts/collectible.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")

const DIMS := {"tile_size": 64, "columns": 56, "rows": 56}
## Player pickup rect centre = old Phaser centre + (0, 14.56) (player_slime.tscn PickupShape).
const PICKUP_OFFSET := Vector2(0.0, 14.56)


# --- the menu key ----------------------------------------------------------------------------------

func test_menu_key_opens_bag(t: TestContext) -> void:
	var menu := _menu(t)
	await t.steps(2)
	t.tap(&"menu")
	t.check(menu.bag.is_open(), "the menu key did not open the bag")
	t.check(t.tree.paused and t.world().has_pause_reason(&"modal"), "the world is not paused by the bag")
	t.check(menu.tabs.visible, "the tab strip is hidden")
	t.check(menu.tabs.is_tab_disabled(&"inventory"), "the Bag tab is enabled while the bag is open")
	t.check(not menu.tabs.is_tab_disabled(&"crafting"), "the Crafting tab is disabled")
	t.equal(menu.current_tab(), &"inventory", "current tab")
	t.tap(&"menu")
	t.check(not menu.bag.is_open(), "the menu key did not close the bag")
	t.check(not t.tree.paused, "the world stayed paused")
	t.check(not menu.tabs.visible, "the tab strip stayed")


func test_menu_key_refused(t: TestContext) -> void:
	var menu := _menu(t)
	t.player().face(Vector2.RIGHT)
	t.tap(&"attack")
	var swinging := await t.until(func() -> bool: return t.player().is_action_locked(), 200.0)
	t.check(swinging, "the sword swing did not start")
	t.tap(&"menu")
	t.check(not menu.bag.is_open(), "the menu key opened the bag mid-swing")
	await t.until(func() -> bool: return not t.player().is_action_locked(), 2000.0)
	var shell := Services.shell()
	t.check(shell.open_pause(), "the pause menu did not open")
	t.tap(&"menu")
	t.check(not menu.bag.is_open(), "the menu key opened the bag over the pause menu")
	shell.pause_menu.close()


func test_tab_coach(t: TestContext) -> void:
	var menu := _menu(t)
	var run := Services.run()
	menu.open_bag()
	t.check(menu.tabs.coach.visible, "the coach is hidden the first time")
	t.equal(menu.tabs.coach_label.text, "These tabs switch between your Bag, Crafting, Journal and Map. Click one!", "coach text")
	menu.tabs.buttons[&"crafting"].pressed.emit()
	t.check(run.has_flag("hint.menu-tabs"), "a tab click did not learn the coach")
	t.check(not menu.tabs.coach.visible, "the coach stayed after a tab click")
	menu.crafting.close()


func test_map_and_registered_tabs(t: TestContext) -> void:
	var menu := _menu(t)
	var map_ui := t.tree.get_first_node_in_group(&"map_ui")
	menu.open_bag()
	if map_ui != null:
		t.check(not menu.tabs.is_tab_disabled(&"map"), "the Map tab is disabled with a world map")
		menu.tabs.buttons[&"map"].pressed.emit()
		t.check(bool(map_ui.call(&"is_world_map_open")), "the Map tab did not open the world map")
		t.check(not menu.bag.is_open(), "the bag stayed open")
		t.equal(menu.current_tab(), &"map", "current tab")
		t.tap(&"menu")
		t.check(not bool(map_ui.call(&"is_world_map_open")), "the menu key did not close the world map")
		menu.open_bag()
	var journal := {"open": false}
	menu.register_tab(&"journal", func() -> void: journal["open"] = true, func() -> void: journal["open"] = false,
		func() -> bool: return journal["open"])
	t.check(not menu.tabs.is_tab_disabled(&"journal"), "the Journal tab is disabled after registering")
	menu.switch_tab(&"journal")
	t.check(bool(journal["open"]) and not menu.bag.is_open(), "the Journal tab did not switch")
	t.equal(menu.current_tab(), &"journal", "current tab")
	t.check(menu.toggle_menu(), "the menu key did not act on the journal")
	t.check(not bool(journal["open"]), "the menu key did not close the journal")
	menu.register_tab(&"journal", null)
	menu.open_bag()
	t.check(menu.tabs.is_tab_disabled(&"journal"), "the Journal tab stayed enabled after unregistering")
	menu.bag.close()


# --- the model -------------------------------------------------------------------------------------

func test_bag_model_new_run(t: TestContext) -> void:
	_set_bag([])
	var bag := _open_bag(t)
	var model := bag.model()
	var items: Array = model["items"]
	t.equal(items.size(), 20, "cells")
	t.check(items.all(func(cell: Dictionary) -> bool: return cell["label"] == "Empty" and cell["disabled"]), "a cell is not an empty disabled one")
	t.equal(model["details_name"], "Your bag is empty", "details name")
	t.equal(model["details"], "Pick things up in the world and they land here.", "details")
	t.check(bag.primary_button.disabled, "Use is enabled")
	t.check(not bag.quantity_label.visible and not bag.drop_button.visible, "the amount or the actions show")
	t.check(bag.close_button.has_focus(), "Close does not have the focus")
	bag.close()


func test_new_run_holds_the_trial_sword(t: TestContext) -> void:
	var run := Services.run()
	t.equal(run.slots(), [{"item_id": "basic-sword", "count": 1}], "bag at a new run")
	t.equal(run.weapon_slots(), ["basic-sword", null, null, null], "belt at a new run")
	t.equal(run.equipped_weapon_id(), "basic-sword", "hand at a new run")
	var weapon = t.player().get_combat().get_weapon()
	t.check(weapon != null and weapon.weapon_id == "basic-sword", "the sword is not mounted")
	t.check(not run.trial_weapon_pending, "the trial grant is still pending")
	var bag := _open_bag(t)
	var cell: Dictionary = (bag.model()["items"] as Array)[0]
	t.equal([cell["label"], cell["tag"]], ["Basic sword", "in hand"], "the sword's cell")
	t.equal(bag.model()["details"], "A reusable weapon definition.", "the sword's placeholder description (K17)")
	bag.close()


func test_bag_model_items(t: TestContext) -> void:
	var run := Services.run()
	_set_bag([{"item_id": "wood", "count": 25}, {"item_id": "hp-potion", "count": 3}, {"item_id": "stone-axe", "count": 1}])
	run.set_weapon_slots(["stone-axe", null, null, null])
	run.set_equipped_weapon("stone-axe")
	var bag := _open_bag(t)
	var model := bag.model()
	var items: Array = model["items"]
	t.equal([items[0]["label"], items[0]["tag"]], ["Wood", "×25"], "cell 0")
	t.equal([items[2]["label"], items[2]["tag"]], ["Stone Axe", "in hand"], "cell 2")
	t.equal(model["selected_index"], 0, "selected cell")
	t.equal(model["details_status"], "Material · 25 in the bag", "wood status")
	t.equal(model["details_status_color"], Color("#a9c4b4"), "wood status colour")
	t.check(bag.primary_button.disabled and bag.primary_button.text == "Use", "wood's Use is enabled")
	t.check(not bag.drop_button.disabled, "wood's Drop is disabled")
	bag.item_list.get_child(2).pressed.emit()
	model = bag.model()
	t.equal(model["details_status"], "In your hand · belt slot 1", "axe status")
	t.equal(model["details_status_color"], UiTokens.WARNING, "axe status colour")
	t.check(bag.primary_button.disabled and bag.primary_button.text == "In your hand", "axe primary")
	t.equal((model["hotbar_slots"] as Array).map(func(row: Dictionary) -> String: return row["label"]),
		["1: Stone Axe", "2: empty", "3: empty", "4: empty"], "assignment rows")
	t.equal(model["hotbar_selected_index"], 0, "assignment index")
	t.check(bag.assign_list.visible and not bag.quantity_label.visible, "a weapon shows the amount instead of the belt list")
	bag.close()


func test_drag_weapon_onto_belt(t: TestContext) -> void:
	var run := Services.run()
	_set_bag([{"item_id": "basic-sword", "count": 1}, {"item_id": "stone-axe", "count": 1}, {"item_id": "wood", "count": 5}])
	var bag := _open_bag(t)
	var data: Variant = bag.item_list.get_child(1).call(&"_get_drag_data", Vector2.ZERO)
	t.equal(data, {"source_item_id": "slot-2", "source_index": 1}, "drag data of the axe cell")
	t.equal(bag.item_list.get_child(2).call(&"_get_drag_data", Vector2.ZERO), null, "wood can be dragged")
	var target := bag.belt_list.get_child(2)
	t.check(bool(target.call(&"_can_drop_data", Vector2.ZERO, data)), "the belt slot refuses the axe")
	target.call(&"_drop_data", Vector2.ZERO, data)
	t.equal(run.weapon_slots(), ["basic-sword", null, "stone-axe", null], "belt after the drop")
	t.equal(run.equipped_weapon_id(), "basic-sword", "hand after the drop")
	var belt_data: Variant = bag.belt_list.get_child(2).call(&"_get_drag_data", Vector2.ZERO)
	bag.belt_list.get_child(0).call(&"_drop_data", Vector2.ZERO, belt_data)
	t.equal(run.weapon_slots(), ["stone-axe", null, "basic-sword", null], "belt after dragging within it")
	t.equal(bag.model()["details_name"], "Stone Axe", "the dragged weapon is selected")
	bag.belt_list.get_child(0).pressed.emit()
	t.equal(run.equipped_weapon_id(), "stone-axe", "a belt click did not hold its weapon")
	bag.close()


# --- consumables -----------------------------------------------------------------------------------

func test_use_potion(t: TestContext) -> void:
	var run := Services.run()
	var player := t.player()
	_set_bag([{"item_id": "hp-potion", "count": 3}])
	player.restore_run_state({"hp": 50})
	var messages := _messages(t)
	var heal := _cue(&"Heal")
	var bag := _open_bag(t)
	bag.primary_button.pressed.emit()
	t.equal(player.get_hp(), 90, "HP after a tonic")
	t.equal(run.item_count("hp-potion"), 2, "tonics left")
	if t.check(messages.size() == 1, "messages %s" % [messages]):
		t.equal([messages[0]["text"], messages[0]["color"], messages[0]["big"]], ["+40", "green", true], "heal text")
		t.near_vec(Vector2(messages[0]["x"], messages[0]["y"]), player.get_centre() - Vector2(0.0, 30.0), 0.01, "heal text position")
	t.check(heal != null and heal.playing, "Heal did not play")
	if heal != null:
		heal.stop()
	player.restore_run_state({"hp": 100})
	bag.primary_button.pressed.emit()
	t.equal(player.get_hp(), 100, "HP at full health")
	t.equal(run.item_count("hp-potion"), 1, "a tonic was used at full health (K10)")
	t.equal(messages.size(), 1, "a text at full health")
	t.check(heal == null or not heal.playing, "Heal played at full health")
	bag.close()


func test_berry_basket_and_energy(t: TestContext) -> void:
	var run := Services.run()
	var player := t.player()
	_set_bag([{"item_id": "berry-basket", "count": 1}, {"item_id": "energy-potion", "count": 1}])
	var bag := _open_bag(t)
	player.restore_run_state({"hp": 90, "energy": 50})
	var restore := _cue(&"EnergyRestore")
	bag.primary_button.pressed.emit()
	t.equal(player.get_hp(), 100, "HP after the basket")
	t.near(player.get_energy(), 80.0, 0.001, "energy after the basket")
	t.check(restore != null and restore.playing, "EnergyRestore did not play")
	t.equal(run.item_count("berry-basket"), 0, "baskets left")
	if restore != null:
		restore.stop()
	player.set_energy(95.0)
	t.equal(str(bag.model()["details_name"]), "Fizzy Brew", "the selection after the basket")
	bag.primary_button.pressed.emit()
	t.near(player.get_energy(), 100.0, 0.001, "energy after the brew")
	t.check(restore == null or not restore.playing, "EnergyRestore played for a gain of 5")
	t.equal(run.item_count("energy-potion"), 0, "brews left")
	bag.close()


func test_use_takes_first_stack(t: TestContext) -> void:
	var run := Services.run()
	_set_bag([{"item_id": "hp-potion", "count": 9}, {"item_id": "hp-potion", "count": 2}])
	t.player().restore_run_state({"hp": 50})
	var bag := _open_bag(t)
	bag.item_list.get_child(1).pressed.emit()
	bag.primary_button.pressed.emit()
	t.equal(run.slots(), [{"item_id": "hp-potion", "count": 8}, {"item_id": "hp-potion", "count": 2}], "slots (K11)")
	bag.close()


# --- amount and Destroy ----------------------------------------------------------------------------

func test_quantity_clamp(t: TestContext) -> void:
	_set_bag([{"item_id": "wood", "count": 25}])
	var bag := _open_bag(t)
	var seen: Array = []
	for key: String in ["Plus10", "Plus10", "Plus10", "Minus10", "Minus10", "Minus10"]:
		(bag.quantity_buttons[key] as Button).pressed.emit()
		seen.append(bag.model()["quantity"])
	t.equal(seen, ["Quantity: 11", "Quantity: 21", "Quantity: 25", "Quantity: 15", "Quantity: 5", "Quantity: 1"], "amounts")
	bag.close()


func test_destroy(t: TestContext) -> void:
	var run := Services.run()
	_set_bag([{"item_id": "wood", "count": 25}, {"item_id": "stone", "count": 10}])
	var bag := _open_bag(t)
	for i in 4:
		(bag.quantity_buttons["Plus1"] as Button).pressed.emit()
	bag.remove_button.pressed.emit()
	t.equal(run.item_count("wood"), 20, "wood after Destroy 5")
	t.equal(bag.model()["quantity"], "Quantity: 5", "amount after Destroy")
	bag.remove_all_button.pressed.emit()
	t.equal(run.slots(), [{"item_id": "stone", "count": 10}], "slots after Destroy all")
	t.equal([bag.model()["selected_index"], bag.model()["details_name"]], [0, "Stone"], "selection after Destroy all")
	bag.close()


# --- dropping --------------------------------------------------------------------------------------

func test_drop_destination_static(t: TestContext) -> void:
	var open := func(_cell: Vector2i) -> Dictionary: return {"kind": "open"}
	var source := Vector2(640.0, 704.0)
	t.equal(InventoryDrops.find_destination(source, Vector2.DOWN, DIMS, open), Vector2(672.0, 832.0), "facing down")
	t.equal(InventoryDrops.find_destination(source, Vector2.RIGHT, DIMS, open), Vector2(800.0, 704.0), "facing right")
	t.equal(InventoryDrops.find_destination(source, Vector2.UP, DIMS, open), Vector2(672.0, 576.0), "facing up")
	t.equal(InventoryDrops.find_destination(source, Vector2.LEFT, DIMS, open), Vector2(544.0, 704.0), "facing left")
	var blocked := func(cell: Vector2i) -> Dictionary: return {"kind": "blocked" if cell == Vector2i(10, 12) else "open"}
	t.equal(InventoryDrops.find_destination(source, Vector2.DOWN, DIMS, blocked), Vector2(736.0, 832.0), "(10, 12) blocked")
	var stack := func(cell: Vector2i) -> Dictionary:
		return {"kind": "compatible-stack", "x": 1.0, "y": 2.0} if cell == Vector2i(9, 12) else {"kind": "open"}
	t.equal(InventoryDrops.find_destination(source, Vector2.DOWN, DIMS, stack), Vector2(1.0, 2.0), "a same-item pile in the ring")
	var none := func(_cell: Vector2i) -> Dictionary: return {"kind": "blocked"}
	t.equal(InventoryDrops.find_destination(source, Vector2.DOWN, {"tile_size": 64, "columns": 8, "rows": 8}, none), null, "nowhere")


func test_drop_from_bag(t: TestContext) -> void:
	var run := Services.run()
	_set_bag([{"item_id": "wood", "count": 25}])
	var player := t.player()
	player.face(Vector2.DOWN)
	var expected: Variant = InventoryDrops.find_destination(player.get_centre(), Vector2.DOWN, t.world().dimensions(),
		InventoryDrops.world_inspector("level-1", "wood"))
	if not t.check(expected is Vector2, "no drop destination at the spawn"):
		return
	var bag := _open_bag(t)
	for i in 4:
		(bag.quantity_buttons["Plus1"] as Button).pressed.emit()
	bag.drop_button.pressed.emit()
	t.equal(run.item_count("wood"), 20, "wood after dropping 5")
	t.check(not bag.is_open(), "the bag stayed open after the drop")
	var records := run.inventory_drops("level-1")
	if not t.check(records.size() == 1, "drop records %s" % [records]):
		return
	var record: Dictionary = records[0]
	t.equal([record["id"], record["item_id"], record["amount"], record["object_id"], record["visual_id"]],
		["inventory-drop-1", "wood", 5, "collectible.wood-pile", "wood-pile"], "record")
	t.near_vec(Vector2(record["x"], record["y"]), expected, 0.01, "record position")
	var pile := _pile(t, "inventory-drop-1")
	if not t.check(pile != null, "no pile for the drop"):
		return
	t.equal([pile.source_inventory_drop_id, pile.quantity], ["inventory-drop-1", 5], "pile")
	await t.until(func() -> bool: return pile.pickup_area.monitorable, 600.0)
	t.near_vec((pile.get_parent() as Node2D).global_position, expected, 0.01, "pile landing")
	t.teleport_player((pile.get_parent() as Node2D).global_position - PICKUP_OFFSET)
	await t.until(func() -> bool: return run.item_count("wood") == 25, 300.0)
	t.equal(run.item_count("wood"), 25, "wood after picking the pile up")
	t.check(run.inventory_drops("level-1").is_empty(), "the drop record survived the pickup")
	t.equal(run.coins(), 50, "coins after picking up a bag drop")


func test_drop_disabled_for_workbench(t: TestContext) -> void:
	_set_bag([{"item_id": "workbench", "count": 1}])
	var bag := _open_bag(t)
	t.check(bag.drop_button.disabled and bag.drop_all_button.disabled, "the workbench can be dropped")
	t.check(not bag.remove_button.disabled, "the workbench cannot be destroyed (K7)")
	t.equal(bag.primary_button.text, "Place", "primary label")
	t.check(bag.primary_button.disabled, "Place is enabled before furniture placement (C1)")
	t.equal(bag.model()["details_status"], "Furniture · 1 in the bag", "status")
	bag.close()


func test_pause_menu_inventory_action(t: TestContext) -> void:
	var shell := Services.shell()
	t.check(shell.has_action(&"inventory"), "no inventory action")
	t.check(shell.open_pause(), "the pause menu did not open")
	var button: Button = shell.pause_menu.button_for(&"inventory")
	t.check(not button.disabled, "Inventory is disabled")
	button.pressed.emit()
	t.check(not shell.pause_menu.is_open(), "the pause menu stayed open")
	t.check(_menu(t).bag.is_open(), "the bag did not open")
	_menu(t).bag.close()


# --- helpers -------------------------------------------------------------------------------------

func _menu(t: TestContext) -> MenuWindows:
	return t.main.menu_windows


func _open_bag(t: TestContext) -> InventoryScreen:
	var menu := _menu(t)
	if not menu.bag.is_open():
		menu.open_bag()
	return menu.bag


static func _set_bag(slots: Array) -> void:
	var run := Services.run()
	run.inventory["slots"] = slots.duplicate(true)
	run.inventory_changed.emit({})


static func _messages(t: TestContext) -> Array:
	var messages: Array = []
	t.listen(t.main.inventory_actions.message_shown, func(payload: Dictionary) -> void: messages.append(payload))
	return messages


static func _pile(t: TestContext, instance_id: String) -> CollectibleScript:
	for node: Node in t.tree.get_nodes_in_group(&"collectible"):
		var script := node as CollectibleScript
		if script != null and script.instance_id == instance_id and not script.get_parent().is_queued_for_deletion():
			return script
	return null


static func _cue(cue: StringName) -> AudioStreamPlayer:
	var feel := Services.feel()
	if feel == null:
		return null
	feel.warm_up()
	var player := feel.get_node_or_null(NodePath("GlobalAudio/Effects/" + String(cue))) as AudioStreamPlayer
	if player != null:
		player.stop()
	return player
