extends RefCounted
## Release 1's potions (docs/godot/specs/crafting.md 12): the campfire lists only the recipes the
## slime knows; Dollop's shop sells only while Market Hill is awake, refuses what the coins or the bag
## cannot take and sells its belt slot once; the potion belt's slots are finds (never in the bag, at
## most four), a potion kind is set to an open slot in the bag, and its key (1-4) drinks one of that
## kind until the stack is gone, refusing an empty slot, an empty stack and a drink that would do
## nothing. level-1 (C4) unless stated.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const RecipeCatalog := preload("res://game/crafting/recipe_catalog.gd")
const ShopCatalog := preload("res://game/shop/shop_catalog.gd")
const PotionBelt := preload("res://game/inventory/potion_belt.gd")
const ItemCatalog := preload("res://game/world_objects/item_catalog.gd")
const InventoryActions := preload("res://game/inventory/inventory_actions.gd")

const SHOP := "dollop"
const OPEN_FLAG := "glimmerhill.market-hill.awake"
const TONIC := "hp-potion"
const FIZZY := "energy-potion"
const BELT_SLOT := "belt-slot"
## The campfire on C4's plaza meadow (level-1-c4 `Scenery/campfire`).
const CAMPFIRE := Vector2(952.0, 1424.0)


func test_a_campfire_lists_only_the_recipes_the_slime_knows(t: TestContext) -> void:
	var run := Services.run()
	t.equal(_recipe_ids({"station": "campfire", "tier": 1}), [], "a campfire's recipes before any lesson")
	t.equal(_recipe_ids({"station": "forge", "tier": 1}), [], "the Forge's recipes before any lesson (no smelting)")
	run.learn_recipes(["brew-tonic"])
	t.equal(_recipe_ids({"station": "campfire", "tier": 1}), ["brew-tonic"], "a campfire's recipes after Lili's lesson")
	run.learn_recipes(["cook-berry-basket", "brew-fizzy"])
	t.equal(_recipe_ids({"station": "campfire", "tier": 1}), ["brew-tonic", "cook-berry-basket"], "a campfire after Dora's lesson")
	t.equal(_recipe_ids({"station": "forge", "tier": 1}), ["brew-fizzy"], "the Forge after Pip's lesson")
	# The campfire on C4's meadow is a station: its use opens the crafting window titled Campfire.
	var station := _station_near(t, CAMPFIRE)
	if not t.check(station != null, "no cook station at C4's campfire"):
		return
	t.equal(str(station.get(&"recipe_context")), "campfire", "the campfire's station")


func test_the_shop_sells_only_while_market_hill_is_awake(t: TestContext) -> void:
	var run := Services.run()
	var coins := run.coins()
	var refused := ShopCatalog.buy(SHOP, TONIC)
	t.equal(refused.get("reason"), ShopCatalog.CLOSED, "a purchase while Dollop sleeps")
	t.equal(run.coins(), coins, "coins after a refused purchase")
	run.set_flag(OPEN_FLAG)
	run.add_coins(200 - coins)
	var bought := ShopCatalog.buy(SHOP, TONIC)
	t.check(bool(bought.get("ok")), "a tonic was not sold: %s" % [bought])
	t.equal(run.coins(), 200 - 30, "coins after a 30-coin tonic")
	t.equal(run.item_count(TONIC), 1, "tonics after buying one")
	t.equal(ShopCatalog.buy(SHOP, "wood").get("reason"), ShopCatalog.UNKNOWN, "wood (found in the world, not sold)")
	t.equal(ShopCatalog.buy(SHOP, "stone-axe").get("reason"), ShopCatalog.UNKNOWN, "something Dollop does not sell")


func test_the_shop_refuses_what_the_coins_or_the_bag_cannot_take(t: TestContext) -> void:
	var run := Services.run()
	run.set_flag(OPEN_FLAG)
	run.spend_coins(run.coins())
	run.add_coins(20)
	t.equal(ShopCatalog.buy(SHOP, TONIC).get("reason"), ShopCatalog.NO_COINS, "a 30-coin tonic with 20 coins")
	t.equal(run.coins(), 20, "coins after a refusal")
	t.equal(run.item_count(TONIC), 0, "tonics after a refusal")
	run.add_coins(500)
	_fill_the_bag(run)
	t.equal(ShopCatalog.buy(SHOP, "shard").get("reason"), ShopCatalog.BAG_FULL, "a shard with a full bag")
	t.equal(run.coins(), 520, "coins after a bag-full refusal")


func test_the_belt_slot_is_sold_once_and_never_sits_in_the_bag(t: TestContext) -> void:
	var run := Services.run()
	run.set_flag(OPEN_FLAG)
	run.add_coins(1000)
	t.equal(run.potion_belt_open(), 0, "belt slots of a new run")
	_fill_the_bag(run)
	var bought := ShopCatalog.buy(SHOP, BELT_SLOT)
	t.check(bool(bought.get("ok")), "the belt slot was not sold with a full bag: %s" % [bought])
	t.equal(run.potion_belt_open(), 1, "belt slots after buying one")
	t.equal(run.item_count(BELT_SLOT), 0, "a belt slot in the bag")
	t.equal(ShopCatalog.buy(SHOP, BELT_SLOT).get("reason"), ShopCatalog.SOLD_OUT, "the belt slot a second time")
	# Finds: a chest's or a pickup's slot opens one more, up to four.
	for i in 3:
		run.add_item(BELT_SLOT, 1)
	t.equal(run.potion_belt_open(), 4, "belt slots after three more finds")
	t.equal(run.item_capacity(BELT_SLOT), 0, "room for a fifth belt slot")
	t.check(not run.open_potion_belt_slot(), "a fifth belt slot opened")
	t.equal(run.item_count(BELT_SLOT), 0, "belt slots in the bag after the finds")


func test_a_belt_key_drinks_its_kind_until_the_stack_is_gone(t: TestContext) -> void:
	var run := Services.run()
	var player := t.player()
	var actions: Node = t.main.inventory_actions
	var lines: Array = []
	t.listen(actions.message_shown, func(payload: Dictionary) -> void: lines.append(str(payload.get("text", ""))))
	run.add_item(TONIC, 2)
	# No slot found yet: the key does nothing.
	player.restore_run_state({"hp": 40})
	t.tap(&"potion_1")
	await t.steps(3)
	t.equal(run.item_count(TONIC), 2, "a tonic drunk with no belt slot")
	run.add_item(BELT_SLOT, 1)
	run.add_item(BELT_SLOT, 1)
	t.equal(run.potion_belt_open(), 2, "belt slots open")
	# An open slot with no kind refuses.
	lines.clear()
	t.tap(&"potion_1")
	await t.steps(3)
	t.equal(run.item_count(TONIC), 2, "a tonic drunk from an empty slot")
	t.check(lines.has(InventoryActions.BELT_EMPTY_TEXT % 1), "no empty-slot line: %s" % [lines])
	# The bag sets the kind (only potions, only open slots).
	t.check(not actions.assign_belt_slot(0, "wood"), "wood was set to a belt slot")
	t.check(not actions.assign_belt_slot(2, TONIC), "a closed slot took a kind")
	t.check(actions.assign_belt_slot(0, TONIC), "the tonic was not set to slot 1")
	t.equal(PotionBelt.slot_of(TONIC), 0, "the tonic's slot")
	t.check(actions.assign_belt_slot(1, TONIC), "the tonic did not move to slot 2")
	t.equal(run.potion_belt_kinds(), ["", TONIC, "", ""], "one kind per slot")
	t.check(actions.assign_belt_slot(0, TONIC), "the tonic did not move back to slot 1")
	# Its key drinks one; at full health it refuses.
	t.tap(&"potion_1")
	await t.steps(3)
	t.equal(run.item_count(TONIC), 1, "tonics after one key press")
	t.equal(player.get_hp(), 80, "HP after a tonic from the belt")
	player.restore_run_state({"hp": player.get_max_hp()})
	lines.clear()
	t.tap(&"potion_1")
	await t.steps(3)
	t.equal(run.item_count(TONIC), 1, "a tonic drunk at full health from the belt")
	t.check(lines.has(PotionBelt.FULL_HP_TEXT), "no full-health line: %s" % [lines])
	player.restore_run_state({"hp": 40})
	t.tap(&"potion_1")
	await t.steps(3)
	t.equal(run.item_count(TONIC), 0, "tonics after the last one")
	# The slot keeps its kind with the stack gone, and says so.
	t.equal(run.potion_belt_kind(0), TONIC, "the slot's kind after its stack ran out")
	lines.clear()
	t.tap(&"potion_1")
	await t.steps(3)
	t.check(lines.has(InventoryActions.BELT_NONE_LEFT_TEXT % "Slime Tonic"), "no none-left line: %s" % [lines])
	# The kind survives a save and a load.
	var data := run.serialize()
	t.check(run.install(data), "install refused the save")
	t.equal(run.potion_belt_open(), 2, "belt slots after a load")
	t.equal(run.potion_belt_kind(0), TONIC, "the slot's kind after a load")


func test_potions_stack_five_to_a_slot(t: TestContext) -> void:
	var run := Services.run()
	for item_id: String in [TONIC, FIZZY, "berry-basket"]:
		t.equal(ItemCatalog.max_stack(item_id), 5, "%s's stack" % item_id)
	run.add_item(TONIC, 7)
	var stacks: Array = []
	for slot: Dictionary in run.inventory["slots"]:
		if str(slot["item_id"]) == TONIC:
			stacks.append(int(slot["count"]))
	t.equal(stacks, [5, 2], "seven tonics in the bag")


# --- helpers ---------------------------------------------------------------------------------------

static func _recipe_ids(site: Dictionary) -> Array:
	var out := []
	for recipe: Dictionary in RecipeCatalog.recipes_at(site):
		out.append(str(recipe.get("id", "")))
	return out


## Fills the bag: one slot, holding a full stack of stone, so nothing new fits.
static func _fill_the_bag(run: Node) -> void:
	run.set(&"inventory", {"max_slots": 1, "slots": [{"item_id": "stone", "count": ItemCatalog.max_stack("stone")}]})
	run.emit_signal(&"inventory_changed", {})


## The crafting station (workbench.gd, a child of its object) nearest `point`.
func _station_near(t: TestContext, point: Vector2) -> Node:
	var best: Node = null
	var best_distance := INF
	for node: Node in t.tree.get_nodes_in_group(&"crafting_station"):
		var holder := node as Node2D if node is Node2D else node.get_parent() as Node2D
		if holder == null or not node.is_inside_tree():
			continue
		var distance := holder.global_position.distance_to(point)
		if distance < best_distance:
			best = node
			best_distance = distance
	return best if best_distance < 200.0 else null
