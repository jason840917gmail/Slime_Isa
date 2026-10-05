extends RefCounted
## Crafting (docs/godot/specs/crafting.md 11.9): the recipe table and sites, quotes and the status
## order, crafts and their transactions, a crafted weapon going onto the belt and into an empty
## hand, and the crafting window (portable and at a station: rows, details, amount, refusals,
## Escape and the menu key). The trial sword (owner decision C3) is set aside where a test needs an
## empty bag or an empty hand.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const RecipeCatalog := preload("res://game/crafting/recipe_catalog.gd")
const CraftingService := preload("res://game/crafting/crafting_service.gd")
const CraftingModel := preload("res://game/ui/screens/crafting_model.gd")
const WeaponLoadout := preload("res://game/player/weapon_loadout.gd")
const UiTokens := preload("res://game/ui/theme/ui_tokens.gd")
const MenuWindows := preload("res://game/ui/screens/menu_windows.gd")

const PORTABLE := {"station": "portable", "tier": 1}
const WORKBENCH := {"station": "workbench", "tier": 1}
const FORGE := {"station": "forge", "tier": 1}
const WORKBENCH_IDS := ["craft-wooden-spear", "craft-stone-axe", "craft-stone-pickaxe", "craft-stone-spear",
	"craft-reinforced-pickaxe", "craft-iron-spear", "craft-iron-axe", "craft-slam-hammer"]


# --- data and service ------------------------------------------------------------------------------

func test_recipe_data(t: TestContext) -> void:
	t.equal(RecipeCatalog.all().size(), 15, "recipes")
	t.equal(_ids(RecipeCatalog.recipes_at(PORTABLE)), ["craft-workbench", "brew-tonic", "cook-berry-basket"], "portable list")
	t.equal(_ids(RecipeCatalog.recipes_at(WORKBENCH)), WORKBENCH_IDS, "workbench list")
	var workshop := _ids(RecipeCatalog.recipes_at({"station": "workshop", "tier": 1}))
	t.equal(workshop.size(), 8, "workshop list size")
	t.equal(workshop[0] if not workshop.is_empty() else "", "craft-slam-hammer", "workshop list starts with its own recipe")
	t.equal(_ids(RecipeCatalog.recipes_at(FORGE)), ["smelt-charcoal", "smelt-iron-bar"], "forge list")
	t.equal(_ids(RecipeCatalog.recipes_at({"station": "kitchen", "tier": 1})), ["brew-fizzy", "weave-tonics"], "kitchen list")
	t.equal(RecipeCatalog.site_title({"station": "workshop", "tier": 2}), "Workshop · Tier 2", "tier-2 title")
	t.equal(RecipeCatalog.site_title(PORTABLE), "Crafting", "portable title")


func test_normalize_quantity(t: TestContext) -> void:
	t.equal(CraftingService.normalize_quantity(5, 0), 0, "(5, 0)")
	t.equal(CraftingService.normalize_quantity(0, 3), 1, "(0, 3)")
	t.equal(CraftingService.normalize_quantity(-4, 3), 1, "(-4, 3)")
	t.equal(CraftingService.normalize_quantity(2.9, 3), 2, "(2.9, 3)")
	t.equal(CraftingService.normalize_quantity("7", 3), 3, "(\"7\", 3)")
	t.equal(CraftingService.normalize_quantity("x", 3), 1, "(\"x\", 3)")


func test_workbench_from_wood(t: TestContext) -> void:
	var run := Services.run()
	_set_bag([{"item_id": "wood", "count": 25}, {"item_id": "wood", "count": 15}])
	var crafted: Array = []
	t.listen(run.recipe_crafted, func(payload: Dictionary) -> void: crafted.append(payload))
	var success := _cue(&"CraftSuccess")
	var recipe := RecipeCatalog.find("craft-workbench")
	var quote := CraftingService.quote(recipe, 1)
	t.equal(quote["status"], "ready", "quote status")
	t.equal(quote["maxCraftable"], 1, "max craftable")
	var result := CraftingService.craft(recipe, 1)
	t.check(bool(result["ok"]), "the craft failed: %s" % [result.get("reason")])
	t.equal(result.get("output_quantity"), 1, "output quantity")
	t.equal(run.slots(), [{"item_id": "workbench", "count": 1}], "bag after the craft")
	t.equal(crafted, [{"recipeId": "craft-workbench", "itemId": "workbench", "quantity": 1}], "recipe_crafted payloads")
	t.check(success != null and success.playing, "CraftSuccess did not play")


func test_status_order(t: TestContext) -> void:
	var run := Services.run()
	var axe := RecipeCatalog.find("craft-stone-axe")
	var tonic := RecipeCatalog.find("brew-tonic")
	_set_bag([{"item_id": "wood", "count": 25}, {"item_id": "stone", "count": 20}])
	run.learn_recipes(["craft-stone-axe"])
	t.equal(CraftingService.quote(axe, 1, PORTABLE)["status"], "wrong-station", "stone axe at the portable site")
	t.equal(CraftingService.quote(axe, 1, PORTABLE)["maxCraftable"], 1, "a wrong-station quote still has a MAX (K3)")
	run.story["learned_recipe_ids"] = []
	var unlearned := CraftingService.quote(axe, 1, WORKBENCH)
	t.equal(unlearned["status"], "not-learned", "not learned")
	t.equal(unlearned["maxCraftable"], 1, "a not-learned quote still has a MAX (K3)")
	run.learn_recipes(["craft-stone-axe"])
	_set_bag([{"item_id": "wood", "count": 25}, {"item_id": "stone", "count": 20}, {"item_id": "stone-axe", "count": 1}])
	var owned := CraftingService.quote(axe, 1, WORKBENCH)
	t.equal(owned["status"], "unique-owned", "unique output owned")
	t.equal(owned["maxCraftable"], 0, "unique-owned max")
	_set_bag([{"item_id": "wood", "count": 5}])
	var short := CraftingService.quote(axe, 1, WORKBENCH)
	t.equal(short["status"], "missing-materials", "missing materials")
	t.equal((short["requirements"] as Array).map(func(r: Dictionary) -> int: return r["missing"]), [5, 10], "missing wood and stone")
	_set_bag(_stone_slots(19, {"item_id": "purple-berry-mat", "count": 6}, true))
	var full := CraftingService.quote(tonic, 1, PORTABLE)
	t.equal(full["status"], "inventory-full", "a full bag")
	t.equal(full["maxCraftable"], 0, "inventory-full max")
	_set_bag(_stone_slots(19, {"item_id": "purple-berry-mat", "count": 3}, true))
	var ready := CraftingService.quote(tonic, 1, PORTABLE)
	t.equal(ready["status"], "ready", "the berry slot frees")
	t.equal(ready["maxCraftable"], 1, "ready max")
	t.check(bool(CraftingService.craft(tonic, 1, PORTABLE)["ok"]), "the tonic craft failed")
	var slots := run.slots()
	t.equal(slots.size(), 20, "slots after the tonic")
	t.equal(slots.back() if not slots.is_empty() else {}, {"item_id": "hp-potion", "count": 1}, "the tonic in the last slot")


func test_quantity_and_max(t: TestContext) -> void:
	var run := Services.run()
	var tonic := RecipeCatalog.find("brew-tonic")
	_set_bag([{"item_id": "purple-berry-mat", "count": 7}])
	var quote := CraftingService.quote(tonic, 5)
	t.equal([quote["requestedQuantity"], quote["maxCraftable"], quote["outputQuantity"]], [2, 2, 2], "berry 7: amount, max, output")
	CraftingService.craft(tonic, 5)
	t.equal(run.slots(), [{"item_id": "purple-berry-mat", "count": 1}, {"item_id": "hp-potion", "count": 2}], "bag after two tonics")
	var charcoal := RecipeCatalog.find("smelt-charcoal")
	_set_bag([{"item_id": "wood", "count": 25}])
	var smelt := CraftingService.quote(charcoal, 99, FORGE)
	t.equal([smelt["requestedQuantity"], smelt["outputQuantity"]], [5, 10], "charcoal: amount, output")
	CraftingService.craft(charcoal, 99, FORGE)
	t.equal(run.slots(), [{"item_id": "charcoal", "count": 10}], "bag after smelting")


func test_first_slot_consumed(t: TestContext) -> void:
	var run := Services.run()
	_set_bag([{"item_id": "wood", "count": 25}, {"item_id": "wood", "count": 25}, {"item_id": "stone", "count": 20}])
	run.learn_recipes(["craft-stone-axe"])
	t.check(bool(CraftingService.craft(RecipeCatalog.find("craft-stone-axe"), 1, WORKBENCH)["ok"]), "the stone axe craft failed")
	t.equal(run.slots(), [{"item_id": "wood", "count": 15}, {"item_id": "wood", "count": 25},
		{"item_id": "stone", "count": 10}, {"item_id": "stone-axe", "count": 1}], "bag after the stone axe")


# --- after a craft ---------------------------------------------------------------------------------

func test_crafted_weapon_to_belt_and_hand(t: TestContext) -> void:
	var run := Services.run()
	_empty_hand(t)
	_set_bag([{"item_id": "wood", "count": 25}, {"item_id": "wood", "count": 25}, {"item_id": "stone", "count": 20}])
	run.learn_recipes(["craft-stone-axe"])
	var messages := _messages(t)
	var equip := _cue(&"EquipTool")
	var success := _cue(&"CraftSuccess")
	var crafting := _menu(t).crafting
	t.check(_menu(t).open_station(WORKBENCH), "the workbench window did not open")
	crafting.select_recipe(1)
	crafting.craft()
	t.equal(run.weapon_slots(), ["stone-axe", null, null, null], "belt after the craft")
	t.equal(run.equipped_weapon_id(), "stone-axe", "weapon in hand")
	var weapon = t.player().get_combat().get_weapon()
	t.check(weapon != null and weapon.weapon_id == "stone-axe", "PlayerCombat does not hold the stone axe")
	var centre := t.player().get_centre()
	if t.check(messages.size() == 2, "messages %s" % [messages]):
		t.equal([messages[0]["text"], messages[0]["color"], messages[0]["big"]], ["Stone Axe equipped", "yellow", true], "equip message")
		t.near_vec(Vector2(messages[0]["x"], messages[0]["y"]), centre - Vector2(0.0, 48.0), 0.01, "equip message position")
		t.equal([messages[1]["text"], messages[1]["color"], messages[1]["big"]], ["Crafted: Stone Axe", "green", true], "crafted message")
		t.near_vec(Vector2(messages[1]["x"], messages[1]["y"]), centre - Vector2(0.0, 44.0), 0.01, "crafted message position")
	t.check(equip != null and equip.playing, "EquipTool did not play")
	t.check(success != null and success.playing, "CraftSuccess did not play")
	crafting.close()


func test_crafted_weapon_keeps_hand(t: TestContext) -> void:
	var run := Services.run()
	_empty_hand(t)
	_set_bag([{"item_id": "stone-axe", "count": 1}, {"item_id": "wood", "count": 25}, {"item_id": "stone", "count": 20}])
	run.set_weapon_slots(["stone-axe", null, null, null])
	t.main.inventory_actions.equip_weapon_slot(0)
	run.learn_recipes(["craft-stone-pickaxe"])
	var messages := _messages(t)
	var result := CraftingService.craft(RecipeCatalog.find("craft-stone-pickaxe"), 1, WORKBENCH)
	t.check(bool(result["ok"]), "the pickaxe craft failed")
	t.main.inventory_actions.on_crafted(result)
	t.equal(run.weapon_slots(), ["stone-axe", "stone-pickaxe", null, null], "belt after the pickaxe")
	t.equal(run.equipped_weapon_id(), "stone-axe", "hand kept")
	t.equal(messages.map(func(m: Dictionary) -> String: return m["text"]), ["Crafted: Stone Pickaxe"], "messages")


# --- the window ------------------------------------------------------------------------------------

func test_portable_window_new_run(t: TestContext) -> void:
	var failed: Array = []
	t.listen(Services.run().craft_failed, func(payload: Dictionary) -> void: failed.append(payload))
	var crafting := _menu(t).crafting
	t.check(_menu(t).open_crafting(PORTABLE), "the crafting window did not open")
	var model := crafting.model()
	t.equal(model["title"], "Crafting", "title")
	t.equal(_labels(model["recipes"]), ["Workbench\nMissing 40 Wood", "Brew Slime Tonic\nMissing 3 Purple Berry",
		"Berry Basket\nMissing 2 Purple Berry, 5 Wood"], "rows")
	t.equal((model["recipes"] as Array).map(func(r: Dictionary) -> bool: return r["short"]), [true, true, true], "short rows")
	t.equal(model["details_name"], "Workbench", "details name")
	t.equal(_labels(model["materials"]), ["Wood\n0 / 40  (need 40 more)"], "materials")
	t.equal(model["status"], "Missing: 40 Wood.", "status")
	t.equal(model["status_color"], UiTokens.WARNING, "status colour")
	t.equal(model["quantity"], "Amount: 0  ·  MAX 0", "amount")
	t.check(not crafting.craft_button.disabled, "Craft is disabled")
	t.check(crafting.max_button.disabled and (crafting.quantity_buttons["Plus1"] as Button).disabled, "the amount buttons are enabled")
	t.check(t.tree.paused and t.world().has_pause_reason(&"modal"), "the world is not paused by the window")
	var fail := _cue(&"CraftFail")
	crafting.craft_button.pressed.emit()
	model = crafting.model()
	t.equal(model["status"], "Missing: 40 Wood.", "refused status")
	t.equal(model["status_color"], UiTokens.DANGER, "refused colour")
	t.check(fail != null and fail.playing, "CraftFail did not play")
	t.equal(failed, [{"recipeId": "craft-workbench", "reason": "missing-materials"}], "craft_failed payloads")
	crafting.close()
	t.check(not t.tree.paused, "the world stayed paused after closing")


func test_refusal_clears_on_bag_change(t: TestContext) -> void:
	var crafting := _menu(t).crafting
	_menu(t).open_crafting(PORTABLE)
	crafting.craft()
	t.equal(crafting.model()["status_color"], UiTokens.DANGER, "refused colour")
	Services.run().add_item("wood", 40)
	var model := crafting.model()
	t.equal(model["status"], "", "status after the wood")
	t.equal((model["recipes"] as Array)[0]["label"], "Workbench\nReady to craft", "workbench row")
	t.equal(_labels(model["materials"]), ["Wood\n40 / 40  √"], "materials")
	t.equal(model["quantity"], "Amount: 1  ·  MAX 1", "amount")
	crafting.close()


func test_success_message_stays(t: TestContext) -> void:
	var run := Services.run()
	_set_bag([{"item_id": "wood", "count": 25}, {"item_id": "stone", "count": 20}])
	run.learn_recipes(["craft-stone-axe"])
	var crafting := _menu(t).crafting
	_menu(t).open_station(WORKBENCH)
	crafting.select_recipe(1)
	crafting.craft()
	var model := crafting.model()
	t.equal(model["status"], "Crafted 1 × Stone Axe", "success status")
	t.equal(model["status_color"], UiTokens.ACCENT, "success colour")
	t.equal((model["recipes"] as Array)[1]["label"], "Stone Axe\nAlready owned", "stone axe row")
	t.check(crafting.craft_button.disabled, "Craft enabled for an owned unique output")
	run.inventory_changed.emit({})
	t.equal(crafting.model()["status"], "Crafted 1 × Stone Axe", "the success message went on a bag change (K5)")
	crafting.close()


func test_station_window_rows(t: TestContext) -> void:
	var crafting := _menu(t).crafting
	t.check(_menu(t).open_station(WORKBENCH), "the workbench window did not open")
	var model := crafting.model()
	t.equal(model["title"], "Workbench", "title")
	var rows: Array = model["recipes"]
	t.equal(rows.size(), 8, "rows")
	if rows.size() == 8:
		t.equal([rows[0]["label"], rows[0]["locked"]], ["Wooden Spear\nNot learned yet", true], "row 0")
		t.equal([rows[7]["label"], rows[7]["locked"]], ["Slam Hammer\nAt the Workshop", true], "row 7")
	t.equal(model["details"], "A light starter weapon with a visible golden thrust.\n\nDamage: 5  ·  Cooldown: 0.8s", "details")
	t.equal(_labels(model["materials"]), ["Wood\n0 / 20  (need 20 more)"], "materials")
	t.equal(model["status"], "Not learned yet — a quest will teach it.", "status")
	t.check(crafting.craft_button.disabled, "Craft is enabled")
	crafting.close()


func test_workbench_interaction_opens_station(t: TestContext) -> void:
	Services.run().set_flag("workshop.restored")
	await t.steps(3)
	t.teleport_player(Vector2(640.0, 470.0))
	await t.steps(2)
	var interaction = t.main.interaction
	var opened: Array = []
	interaction.workbench_opened.connect(func(payload: Dictionary) -> void: opened.append(payload))
	t.tap(&"interact")
	await t.until(func() -> bool: return _menu(t).crafting.is_open(), 200.0)
	t.check(_menu(t).crafting.is_open(), "the Workshop did not open the crafting window")
	t.equal(_menu(t).crafting.model().get("title"), "Workshop", "title")
	t.equal(opened, [{"mapId": "level-1", "context": "workshop"}], "workbench_opened payloads")
	_menu(t).crafting.close()


func test_station_refused_when_open(t: TestContext) -> void:
	var menu := _menu(t)
	t.check(menu.open_bag(), "the bag did not open")
	t.check(not menu.open_station(WORKBENCH), "a station opened over the bag")
	t.check(not menu.crafting.is_open(), "crafting is open")
	menu.bag.close()


func test_quantity_buttons(t: TestContext) -> void:
	_set_bag([{"item_id": "purple-berry-mat", "count": 30}])
	var crafting := _menu(t).crafting
	_menu(t).open_crafting(PORTABLE)
	crafting.select_recipe(1)
	var amounts: Array = []
	for key: String in ["Plus10", "Plus1", "Minus10", "Minus1"]:
		(crafting.quantity_buttons[key] as Button).pressed.emit()
		amounts.append(crafting.model()["quantity"])
	crafting.max_button.pressed.emit()
	amounts.append(crafting.model()["quantity"])
	t.equal(amounts, ["Amount: 10  ·  MAX 10", "Amount: 10  ·  MAX 10", "Amount: 1  ·  MAX 10", "Amount: 1  ·  MAX 10",
		"Amount: 10  ·  MAX 10"], "amounts after +10, +1, -10, -1, MAX")
	crafting.close()
	_menu(t).open_crafting(PORTABLE)
	t.equal(crafting.model()["quantity"], "Amount: 10  ·  MAX 10", "amount after reopening")
	t.equal(crafting.model()["details_name"], "Slime Tonic", "selection after reopening")
	crafting.close()


func test_escape_and_menu_key(t: TestContext) -> void:
	var menu := _menu(t)
	menu.open_bag()
	menu.tabs.buttons[&"crafting"].pressed.emit()
	t.check(menu.crafting.is_open() and not menu.bag.is_open(), "the Crafting tab did not switch windows")
	t.equal(menu.crafting.site(), PORTABLE, "the tab opens the portable site")
	t.tap(&"ui_cancel")
	t.check(not menu.crafting.is_open(), "Escape did not close crafting")
	t.check(not t.tree.paused, "the world stayed paused")
	t.check(not Services.shell().pause_menu.is_open(), "Escape also opened the pause menu")
	menu.open_bag()
	menu.switch_tab(&"crafting")
	t.tap(&"menu")
	t.check(not menu.crafting.is_open(), "the menu key did not close crafting")
	t.check(not menu.bag.is_open(), "the menu key opened the bag again")


# --- helpers -------------------------------------------------------------------------------------

func _menu(t: TestContext) -> MenuWindows:
	return t.main.menu_windows


static func _set_bag(slots: Array) -> void:
	var run := Services.run()
	run.inventory["slots"] = slots.duplicate(true)
	run.inventory_changed.emit({})


## `count` full stone stacks; `last` appended (first when `first` is true).
static func _stone_slots(count: int, other: Dictionary, first: bool) -> Array:
	var slots: Array = []
	for i in count:
		slots.append({"item_id": "stone", "count": 25})
	if first:
		slots.push_front(other)
	else:
		slots.append(other)
	return slots


## Nothing in hand: the trial sword off the belt, out of the bag and unmounted.
static func _empty_hand(t: TestContext) -> void:
	var run := Services.run()
	run.set_weapon_slots([null, null, null, null])
	run.set_equipped_weapon(null)
	run.remove_item("basic-sword", run.item_count("basic-sword"))
	t.player().get_combat().unequip()


static func _messages(t: TestContext) -> Array:
	var messages: Array = []
	t.listen(t.main.inventory_actions.message_shown, func(payload: Dictionary) -> void: messages.append(payload))
	return messages


static func _ids(recipes: Array) -> Array:
	return recipes.map(func(recipe: Dictionary) -> String: return recipe["id"])


static func _labels(rows: Array) -> Array:
	return rows.map(func(row: Dictionary) -> String: return row["label"])


## The global cue player, stopped so a test sees only its own plays.
static func _cue(cue: StringName) -> AudioStreamPlayer:
	var feel := Services.feel()
	if feel == null:
		return null
	feel.warm_up()
	var player := feel.get_node_or_null(NodePath("GlobalAudio/Effects/" + String(cue))) as AudioStreamPlayer
	if player != null:
		player.stop()
	return player
