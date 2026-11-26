extends RefCounted
## The weapon belt (docs/godot/specs/crafting.md 8, 11.9): cycling, the wheel's step lock, assigning
## and swapping, holding a bag weapon on a full belt, reconcile, the harvest advice, weapon names and
## icons. The trial sword (owner decision C3) is set aside where a test needs its own belt.
## The body-shapes mode is on in every world (docs/godot/BODY_SHAPES.md "Running it"; one combat since
## 2026-11-25, the throw rules beside it): E and the wheel switch the body shapes, the HUD
## weapon slot is the Shape slot with its carousel, a switch during a strike waits for its cancel
## point, and the current shape is kept for the session (BODY_SHAPES.md 3, "Ability Box and HUD",
## "Not wired yet"); those tests play the shapes. No belt weapon is mounted in this mode (main.gd
## `equip_run_start`).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const WeaponLoadout := preload("res://game/player/weapon_loadout.gd")
const WheelStepper := preload("res://game/player/wheel_stepper.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const ItemIcons := preload("res://game/inventory/item_icons.gd")
const ResourceNodeScript := preload("res://game/scripts/resource_node.gd")
const WeaponHotbar := preload("res://game/ui/weapon_hotbar.gd")
const ShapeDefs := preload("res://game/shapes/shape_defs.gd")
const ShapeController := preload("res://game/shapes/shape_controller.gd")
const BodyCards := preload("res://game/ui/body_cards.gd")

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


## The wheel (and E) takes the next learned shape (BODY_SHAPES.md 3) without stopping the walk, and
## plays the shape's switch cue (ShapeController `SWITCH_CUES`: the War Axe's EquipBlade).
func test_wheel_switches(t: TestContext) -> void:
	var shapes := _shapes(t, [ShapeDefs.SPEAR, ShapeDefs.AXE], ShapeDefs.SPEAR)
	if shapes == null:
		return
	t.press(&"move_right")
	# Past the cue's 60 ms minimum interval (real time) since the setup's own switch.
	var since := Time.get_ticks_msec()
	await t.until(func() -> bool: return Time.get_ticks_msec() - since >= 80, 2000.0)
	var blade := _cue(&"EquipBlade")
	t.tap(&"weapon_next")
	var switched := await t.until(func() -> bool: return shapes.current_shape_id() == ShapeDefs.AXE, 40.0)
	t.check(switched, "the wheel did not switch to the War Axe")
	t.check(t.player_body().velocity.x > 0.0, "the switch stopped the slime (velocity %s)" % [t.player_body().velocity])
	t.check(blade != null and TestContext.played(blade), "EquipBlade did not play")
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


## A switch asked for during a strike (a click on the Shape slot takes the next shape, like E) waits
## for the step's cancel point and never cancels the strike (BODY_SHAPES.md 3).
func test_busy_refusal(t: TestContext) -> void:
	var shapes := _shapes(t, [ShapeDefs.SPEAR, ShapeDefs.AXE], ShapeDefs.SPEAR)
	if shapes == null:
		return
	var hotbar := _hotbar(t)
	t.player().face(Vector2.RIGHT)
	t.tap(&"attack")
	var striking := await t.until(func() -> bool: return shapes.is_busy(), 200.0)
	t.check(striking, "the Spear's jab did not start")
	hotbar.slot.pressed.emit()
	t.equal(shapes.current_shape_id(), ShapeDefs.SPEAR, "the shape right after a switch asked mid-strike")
	t.check(shapes.is_busy(), "the switch cancelled the strike")
	var switched := await t.until(func() -> bool: return shapes.current_shape_id() == ShapeDefs.AXE, 1500.0)
	t.check(switched, "the waiting switch never came")
	await t.steps(2)
	t.equal(hotbar.model()["selected_index"], 1, "Shape slot selection after the switch")


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


## The Shape slot (BODY_SHAPES.md "Ability Box and HUD"): hidden below two learned shapes; then the
## current shape's icon, the E badge, the learned shapes in the model, no focus, no carousel.
func test_hotbar_model(t: TestContext) -> void:
	var hotbar := _hotbar(t)
	if _shapes(t, [ShapeDefs.SPEAR], ShapeDefs.SPEAR) == null:
		return
	hotbar.refresh()
	t.check(not hotbar.visible, "the Shape slot shows with one shape learned")
	Services.run().learn_ability(String(ShapeDefs.AXE), true)
	hotbar.refresh()
	var model := hotbar.model()
	var entries: Array = model["weapons"]
	t.equal(entries.map(func(entry: Dictionary) -> Array: return [entry["id"], entry["label"], entry["disabled"]]),
		[[String(ShapeDefs.SPEAR), ShapeDefs.title(ShapeDefs.SPEAR), false], [String(ShapeDefs.AXE), ShapeDefs.title(ShapeDefs.AXE), false]],
		"the learned shapes in the model")
	t.equal(model["selected_index"], 0, "selected shape")
	t.check(hotbar.visible, "the Shape slot is hidden with two shapes learned")
	t.check(hotbar.icon.texture != null and hotbar.icon.texture == BodyCards.shape_icon(ShapeDefs.SPEAR), "the slot does not show the Spear's icon")
	t.check(hotbar.slot.tooltip_text.begins_with(ShapeDefs.title(ShapeDefs.SPEAR)), "the slot's tooltip: %s" % hotbar.slot.tooltip_text)
	t.equal(hotbar.key_badge.text, "E", "the shape switch's key on the slot")
	t.equal(hotbar.slot.focus_mode, Control.FOCUS_NONE, "the Shape slot takes focus")
	t.check(not hotbar.is_carousel_open(), "the carousel opened without a switch")


## Switching shapes opens the carousel over the Shape slot; learning a second shape alone does not.
func test_weapon_carousel(t: TestContext) -> void:
	var hotbar := _hotbar(t)
	var shapes := _shapes(t, [ShapeDefs.SPEAR], ShapeDefs.SPEAR)
	if shapes == null:
		return
	hotbar.refresh()
	Services.run().learn_ability(String(ShapeDefs.AXE), true)
	hotbar.refresh()
	t.check(not hotbar.is_carousel_open(), "the carousel opened on learning a second shape")
	shapes.cycle(1)
	hotbar.refresh()
	t.check(hotbar.is_carousel_open(), "the carousel did not open on a switch")
	t.check(hotbar.slot.tooltip_text.begins_with(ShapeDefs.title(ShapeDefs.AXE)), "the Shape slot after the switch: %s" % hotbar.slot.tooltip_text)


func test_harvest_advice(t: TestContext) -> void:
	var run := Services.run()
	var actions = t.main.inventory_actions
	run.add_item("stone-axe", 1)
	run.set_weapon_slots(["basic-sword", "stone-axe", null, null])
	t.equal(actions.harvest_message(BLOCKED_TREE), "Requires an Axe: switch with E", "axe on the belt")
	var tree := _resource(t, TREE)
	if t.check(tree != null, "no %s" % TREE):
		var blocked: Array = []
		tree.harvest_blocked.connect(func(payload: Dictionary) -> void: blocked.append(payload))
		_hit(t, tree.damage_area, ["weapon"])
		t.check(blocked.size() == 1 and blocked[0]["message"] == AXE_ADVICE, "the payload keeps the plain message (%s)" % [blocked])
		t.check(_floating_texts().has("Requires an Axe: switch with E"), "the tree did not show the advice")
	run.set_weapon_slots(["basic-sword", null, null, null])
	t.equal(actions.harvest_message(BLOCKED_TREE), "Requires an Axe: put yours on the belt (B)", "axe in the bag")
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


## The current shape is kept for the session across world builds (BODY_SHAPES.md "Not wired yet":
## `ShapeController._last_shape_id`), and the belt record with it.
func test_travel_keeps_weapon(t: TestContext) -> void:
	var run := Services.run()
	_loadout(t, [{"item_id": "basic-sword", "count": 1}, {"item_id": "stone-axe", "count": 1}],
		["basic-sword", "stone-axe", null, null], "stone-axe")
	if _shapes(t, [ShapeDefs.SPEAR, ShapeDefs.AXE], ShapeDefs.AXE) == null:
		return
	t.main.travel_to("slime-home", "", "house-door")
	await t.until(func() -> bool: return t.main.is_transitioning(), 100.0)
	await t.until(func() -> bool: return not t.main.is_transitioning() and t.player() != null and t.world().map_id() == "slime-home", 3000.0, 6000.0)
	await t.steps(2)
	t.equal(t.world().map_id(), "slime-home", "map after the travel")
	var shapes := t.player().get_shapes()
	t.check(shapes != null and shapes.current_shape_id() == ShapeDefs.AXE, "the War Axe is not the current shape after the travel")
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


## Learns `ids` quietly and makes `current` the current shape. Null (a failed check) without a
## ShapeController.
static func _shapes(t: TestContext, ids: Array[StringName], current: StringName) -> ShapeController:
	var run := Services.run()
	for id: StringName in ids:
		run.learn_ability(String(id), true)
	var shapes := t.player().get_shapes()
	if not t.check(shapes != null, "the player has no ShapeController (the body-shapes mode is off)"):
		return null
	t.check(shapes.set_current(current), "%s could not be made current" % current)
	return shapes


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
