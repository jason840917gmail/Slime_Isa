extends RefCounted
## The weapon belt (docs/godot/specs/crafting.md 8, 11.9): cycling, the mouse wheel and its step
## lock, assigning and swapping, holding a bag weapon on a full belt, the busy refusal, reconcile,
## the HUD hotbar, the harvest advice, weapon names and icons, and the hand across a travel. The
## trial sword (owner decision C3) is set aside where a test needs its own belt.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const WeaponLoadout := preload("res://game/player/weapon_loadout.gd")
const WheelStepper := preload("res://game/player/wheel_stepper.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const ItemIcons := preload("res://game/inventory/item_icons.gd")
const ResourceNodeScript := preload("res://game/scripts/resource_node.gd")
const WeaponHotbar := preload("res://game/ui/weapon_hotbar.gd")

const TREE := "level-1-tree-004"
const AXE_ADVICE := "Requires an Axe"
const BLOCKED_TREE := {"targetTag": "wood", "minimumTier": 1, "message": AXE_ADVICE}


func test_cycle_slot(t: TestContext) -> void:
	var run := Services.run()
	_loadout(t, [{"item_id": "stone-axe", "count": 1}, {"item_id": "stone-pickaxe", "count": 1}],
		["stone-axe", null, "stone-pickaxe", null], "stone-axe")
	t.equal([WeaponLoadout.cycle_slot(1), WeaponLoadout.cycle_slot(-1)], [2, 2], "axe in hand: next, previous")
	run.set_equipped_weapon("stone-pickaxe")
	t.equal(WeaponLoadout.cycle_slot(1), 0, "pickaxe in hand: next")
	run.set_weapon_slots([null, "stone-axe", null, null])
	run.set_equipped_weapon(null)
	t.equal([WeaponLoadout.cycle_slot(1), WeaponLoadout.cycle_slot(-1)], [1, 1], "empty hand: next, previous")
	run.set_equipped_weapon("stone-axe")
	t.equal([WeaponLoadout.cycle_slot(1), WeaponLoadout.cycle_slot(-1)], [-1, -1], "one weapon, in hand")


func test_wheel_switches(t: TestContext) -> void:
	var run := Services.run()
	_loadout(t, [{"item_id": "stone-axe", "count": 1}, {"item_id": "stone-pickaxe", "count": 1}],
		["stone-axe", null, "stone-pickaxe", null], "stone-axe")
	var messages := _messages(t)
	t.press(&"move_right")
	# Past the cue's 60 ms minimum interval (real time) since the setup's own equip.
	var since := Time.get_ticks_msec()
	await t.until(func() -> bool: return Time.get_ticks_msec() - since >= 80, 2000.0)
	var equip := _cue(&"EquipTool")
	t.tap(&"weapon_next")
	var switched := await t.until(func() -> bool: return run.equipped_weapon_id() == "stone-pickaxe", 40.0)
	t.check(switched, "the wheel did not switch to the pickaxe")
	t.check(t.player_body().velocity.x > 0.0, "the switch stopped the slime (velocity %s)" % [t.player_body().velocity])
	var weapon = t.player().get_combat().get_weapon()
	t.check(weapon != null and weapon.weapon_id == "stone-pickaxe", "the pickaxe is not mounted")
	t.equal(messages.map(func(m: Dictionary) -> Array: return [m["text"], m["color"]]), [["Stone Pickaxe equipped", "yellow"]], "messages")
	t.check(equip != null and TestContext.played(equip), "EquipTool did not play")
	t.release(&"move_right")


func test_wheel_stepper(t: TestContext) -> void:
	var stepper := WheelStepper.new()
	var steps := [stepper.step(&"weapon_next", 50.0, 0.0), stepper.step(&"weapon_next", 50.0, 100.0),
		stepper.step(&"weapon_next", 50.0, 200.0), stepper.step(&"weapon_next", 50.0, 400.0),
		stepper.step(&"weapon_next", 30.0, 1000.0), stepper.step(&"weapon_next", 30.0, 1001.0)]
	t.equal(steps, [true, false, false, true, false, true], "steps")
	stepper.step(&"weapon_next", 30.0, 2000.0)
	t.check(not stepper.step(&"weapon_previous", 30.0, 2001.0), "a direction change kept the partial notch")
	t.check(stepper.step(&"weapon_previous", 30.0, 2002.0), "two partial notches back did not step")


func test_assign_swap_and_replace_hand(t: TestContext) -> void:
	var run := Services.run()
	_loadout(t, [{"item_id": "stone-axe", "count": 1}, {"item_id": "stone-pickaxe", "count": 1}],
		["stone-axe", "stone-pickaxe", null, null], "stone-axe")
	var swap := WeaponLoadout.assign_weapon(0, "stone-pickaxe")
	t.equal(run.weapon_slots(), ["stone-pickaxe", "stone-axe", null, null], "belt after the swap")
	t.equal(swap, {"ok": true, "equip_assigned_weapon": false}, "swap result")
	t.equal(run.equipped_weapon_id(), "stone-axe", "hand after the swap")
	_loadout(t, [{"item_id": "stone-axe", "count": 1}, {"item_id": "stone-spear", "count": 1}],
		["stone-axe", null, null, null], "stone-axe")
	var messages := _messages(t)
	var blade := _cue(&"EquipBlade")
	t.main.inventory_actions.assign_weapon_slot("stone-spear", 0)
	t.equal(run.weapon_slots(), ["stone-spear", null, null, null], "belt after replacing the hand's slot")
	t.equal(run.equipped_weapon_id(), "stone-spear", "hand after replacing its slot")
	t.equal(messages.map(func(m: Dictionary) -> String: return m["text"]), ["Stone Spear equipped"], "messages")
	t.check(blade != null and TestContext.played(blade), "EquipBlade did not play")
	t.equal(run.item_count("stone-axe"), 1, "the replaced weapon left the bag")


func test_empty_hand_assign_equips(t: TestContext) -> void:
	var run := Services.run()
	_loadout(t, [{"item_id": "stone-axe", "count": 1}], [null, null, null, null], null)
	t.main.inventory_actions.assign_weapon_slot("stone-axe", 2)
	t.equal(run.weapon_slots(), [null, null, "stone-axe", null], "belt")
	t.equal(run.equipped_weapon_id(), "stone-axe", "hand")


func test_hold_from_full_belt(t: TestContext) -> void:
	var run := Services.run()
	_loadout(t, [{"item_id": "stone-axe", "count": 1}, {"item_id": "stone-pickaxe", "count": 1},
		{"item_id": "stone-spear", "count": 1}, {"item_id": "iron-axe", "count": 1}, {"item_id": "iron-spear", "count": 1}],
		["stone-axe", "stone-pickaxe", "stone-spear", "iron-axe"], "stone-pickaxe")
	t.main.inventory_actions.equip_weapon_from_bag("iron-spear")
	t.equal(run.weapon_slots(), ["stone-axe", "iron-spear", "stone-spear", "iron-axe"], "belt")
	t.equal(run.equipped_weapon_id(), "iron-spear", "hand")
	t.equal(run.item_count("stone-pickaxe"), 1, "the pickaxe left the bag")


func test_busy_refusal(t: TestContext) -> void:
	var run := Services.run()
	run.add_item("stone-axe", 1)
	run.set_weapon_slots(["basic-sword", "stone-axe", null, null])
	var messages := _messages(t)
	t.player().face(Vector2.RIGHT)
	t.tap(&"attack")
	var swinging := await t.until(func() -> bool: return t.player().get_combat().is_attacking(), 200.0)
	t.check(swinging, "the sword swing did not start")
	var hotbar := _hotbar(t)
	hotbar.cells[1].pressed.emit()
	t.equal(run.equipped_weapon_id(), "basic-sword", "hand after a refused switch")
	if t.check(messages.size() == 1, "messages %s" % [messages]):
		t.equal([messages[0]["text"], messages[0]["color"], messages[0]["big"]], ["Finish the attack first", "white", false], "refusal")
		t.near_vec(Vector2(messages[0]["x"], messages[0]["y"]), t.player().get_centre() - Vector2(0.0, 42.0), 0.5, "refusal position")
	t.equal(hotbar.model()["selected_index"], 0, "hotbar selection after the refusal")


func test_reconcile(t: TestContext) -> void:
	var run := Services.run()
	_loadout(t, [{"item_id": "stone-axe", "count": 1}, {"item_id": "iron-spear", "count": 1}],
		["stone-axe", "stone-axe", "ghost", null], "iron-spear")
	WeaponLoadout.reconcile()
	t.equal(run.weapon_slots(), ["stone-axe", "iron-spear", null, null], "belt")
	t.equal(run.equipped_weapon_id(), "iron-spear", "hand")
	run.set_equipped_weapon("ghost")
	WeaponLoadout.reconcile()
	t.equal(run.equipped_weapon_id(), "stone-axe", "an unowned hand takes the first belt weapon")
	run.add_item("slam-hammer", 1)
	WeaponLoadout.reconcile()
	t.equal(run.weapon_slots(), ["stone-axe", "iron-spear", null, null], "a slam hammer in the bag stays off the belt (K13 dropped, C5)")


func test_hotbar_model(t: TestContext) -> void:
	_loadout(t, [{"item_id": "stone-axe", "count": 1}], ["stone-axe", null, null, null], "stone-axe")
	var hotbar := _hotbar(t)
	var model := hotbar.model()
	var weapons: Array = model["weapons"]
	t.equal(weapons.size(), 4, "cells")
	t.equal([hotbar.cells[0].tooltip_text, hotbar.cells[0].disabled, hotbar.icons[0].texture != null], ["Stone Axe", false, true], "cell 0")
	for index in range(1, 4):
		t.equal([hotbar.cells[index].text, hotbar.cells[index].disabled], ["Empty", true], "cell %d" % index)
	t.equal(model["selected_index"], 0, "selected cell")
	t.equal(hotbar.cells[0].focus_mode, Control.FOCUS_NONE, "a hotbar cell takes focus")


func test_harvest_advice(t: TestContext) -> void:
	var run := Services.run()
	var actions = t.main.inventory_actions
	run.add_item("stone-axe", 1)
	run.set_weapon_slots(["basic-sword", "stone-axe", null, null])
	t.equal(actions.harvest_message(BLOCKED_TREE), "Requires an Axe: switch with the mouse wheel", "axe on the belt")
	var tree := _resource(t, TREE)
	if t.check(tree != null, "no %s" % TREE):
		var blocked: Array = []
		tree.harvest_blocked.connect(func(payload: Dictionary) -> void: blocked.append(payload))
		_hit(t, tree.damage_area, ["weapon"])
		t.check(blocked.size() == 1 and blocked[0]["message"] == AXE_ADVICE, "the payload keeps the plain message (%s)" % [blocked])
		t.check(_floating_texts().has("Requires an Axe: switch with the mouse wheel"), "the tree did not show the advice")
	run.set_weapon_slots(["basic-sword", null, null, null])
	t.equal(actions.harvest_message(BLOCKED_TREE), "Requires an Axe: put yours on the belt (E)", "axe in the bag")
	run.remove_item("stone-axe", 1)
	t.equal(actions.harvest_message(BLOCKED_TREE), "Requires an Axe", "no axe")


func test_weapon_names(t: TestContext) -> void:
	t.equal(ItemCatalog.item_name("basic-sword"), "Basic sword", "sword name")
	t.equal(ItemCatalog.item_name("stone-axe"), "Stone Axe", "axe name")
	t.equal(ItemCatalog.max_stack("iron-axe"), 1, "weapon max stack")
	t.equal(ItemCatalog.definition("stone-axe").get("category"), "weapon", "weapon category")
	var icon := ItemIcons.icon("stone-axe") as AtlasTexture
	if t.check(icon != null, "the stone axe icon is not an atlas frame"):
		t.equal(icon.region, Rect2(256.0, 0.0, 128.0, 128.0), "stone axe icon region")
	var basket := ItemIcons.icon("berry-basket") as AtlasTexture
	if t.check(basket != null, "the berry basket icon is not an atlas frame"):
		t.equal(basket.region, Rect2(256.0, 768.0, 128.0, 128.0), "berry basket icon region")
	t.check(ItemIcons.icon("goo-gauntlet") is ImageTexture, "the gauntlet has no placeholder icon")


func test_travel_keeps_weapon(t: TestContext) -> void:
	var run := Services.run()
	_loadout(t, [{"item_id": "basic-sword", "count": 1}, {"item_id": "stone-axe", "count": 1}],
		["basic-sword", "stone-axe", null, null], "stone-axe")
	t.main.travel_to("slime-home", "", "house-door")
	await t.until(func() -> bool: return t.main.is_transitioning(), 100.0)
	await t.until(func() -> bool: return not t.main.is_transitioning() and t.player() != null and t.world().map_id() == "slime-home", 3000.0, 6000.0)
	await t.steps(2)
	t.equal(t.world().map_id(), "slime-home", "map after the travel")
	var weapon = t.player().get_combat().get_weapon()
	t.check(weapon != null and weapon.weapon_id == "stone-axe", "the stone axe is not in hand after the travel")
	t.equal(run.weapon_slots(), ["basic-sword", "stone-axe", null, null], "belt after the travel")


# --- helpers -------------------------------------------------------------------------------------

## A bag, a belt and a hand (mounted on PlayerCombat, or unmounted for an empty hand).
static func _loadout(t: TestContext, bag: Array, belt: Array, hand: Variant) -> void:
	var run := Services.run()
	run.inventory["slots"] = bag.duplicate(true)
	run.inventory_changed.emit({})
	run.set_weapon_slots(belt)
	run.set_equipped_weapon(hand)
	var combat = t.player().get_combat()
	if hand == null:
		combat.unequip()
	else:
		combat.equip(str(hand))


static func _messages(t: TestContext) -> Array:
	var messages: Array = []
	t.listen(t.main.inventory_actions.message_shown, func(payload: Dictionary) -> void: messages.append(payload))
	return messages


static func _hotbar(t: TestContext) -> WeaponHotbar:
	return t.main.hud.get_node("WeaponHotbar") as WeaponHotbar


static func _resource(t: TestContext, instance_id: String) -> ResourceNodeScript:
	for node: Node in t.tree.get_nodes_in_group(&"resource_node"):
		var script := node as ResourceNodeScript
		if script != null and script.instance_id == instance_id and script.is_inside_tree():
			return script
	return null


## One weapon hit through the router with its own activation (as test_world_objects).
static func _hit(t: TestContext, target_area: Area2D, tags: Array) -> Dictionary:
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var activation := router.begin_activation(source, [attack])
	var result := router.route({"activation_id": activation, "source": source, "attack_area": attack,
		"target_area": target_area, "weapon_id": "test-tool", "weapon_tags": tags,
		"damage_types": ["physical"], "base_damage": 24.0, "effects": [],
		"impact": {"position": target_area.global_position, "knock": Vector2.RIGHT}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()
	return result


## The texts of GameFeel's floating labels (shown now or before; a label off screen is hidden).
static func _floating_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	var layer := Services.feel().get_node_or_null(^"FloatingTextLayer")
	if layer != null:
		for child: Node in layer.get_children():
			if child is Label:
				texts.append((child as Label).text)
	return texts


static func _cue(cue: StringName) -> AudioStreamPlayer:
	var feel := Services.feel()
	if feel == null:
		return null
	feel.warm_up()
	var player := feel.get_node_or_null(NodePath("GlobalAudio/Effects/" + String(cue))) as AudioStreamPlayer
	if player != null:
		TestContext.silence(player)
	return player
