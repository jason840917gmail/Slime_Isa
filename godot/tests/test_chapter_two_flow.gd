extends RefCounted
## Slimeshire's Forge in Release 1 (docs/godot/specs/quests.md 14.6, crafting.md 12.1): the forge ruin
## is story-only (paying for it does nothing; its locked message shows); Pip gives his mission in a new
## run, and with the Workshop raised (the Matron's Pearl) and the Bow carved talks of the cold Forge;
## the Colossus's Pearl home sets `forge.restored` (owner, 2026-11-20; its story variant brings the
## Forge station), Pip's talk then teaches the Fizzy Brew with his tip, and the relit Forge lists and
## brews it (never the old smelting nobody teaches).
## Rewritten 2026-11-20: the quests Rekindle the Forge and Iron Gear are retired, with their test of
## the paid restore, the smelting and the iron spear.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const RecipeCatalog := preload("res://game/crafting/recipe_catalog.gd")
const QuestNpcTalk := preload("res://game/quests/quest_npc_talk.gd")

const CENTRE := Vector2(900.0, 1200.0)
const NPC_OFFSET := Vector2(40.0, 0.0)
const PIP := "level-1-npc-red-slime-boy"
const PIP_ID := "red-slime-boy"


func test_the_forge_lights_with_the_colossuss_pearl_and_pip_teaches_the_fizzy_brew(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	var site: Node = null
	for node: Node in t.tree.get_nodes_in_group(&"restoration_site"):
		if str(node.get(&"flag_id")) == "forge.restored":
			site = node
	if not t.check(site != null, "no forge ruin in C4"):
		return
	t.check(bool(site.get(&"story_only")), "the forge ruin can be restored by paying")
	# Paying does nothing: the ruin keeps its locked message.
	run.add_item("stone", 40)
	run.add_item("wood", 20)
	run.add_item("iron-ore", 6)
	t.teleport_player(site.call(&"origin") as Vector2 + Vector2(0.0, 40.0))
	await t.steps(2)
	t.main.interaction.refresh(null)
	t.tap(&"interact")
	await t.steps(3)
	t.check(not run.has_flag("forge.restored"), "the interact button restored the story-only forge")
	t.equal(run.item_count("stone"), 40, "the ruin took its cost")
	t.equal(str(QuestNpcTalk.matching_talk(PIP_ID).get("id", "")), "mission", "Pip's talk in a new run")
	# His mission given, the Workshop raised by the Matron's Pearl and the Bow carved from his rune
	# (test_main_quest.gd): the Forge is still cold.
	run.set_flag("pip.mission-given")
	run.set_flag("workshop.restored")
	run.learn_ability("bow")
	t.equal(str(QuestNpcTalk.matching_talk(PIP_ID).get("id", "")), "forge-cold", "Pip's talk before the Forge is lit")
	t.equal(str(quests.call(&"marker_for", PIP_ID)), "", "Pip's marker before the Forge is lit")
	# The Colossus's Pearl home lights it (the homecoming sets the flag: test_glimmerhill.gd).
	run.set_flag("forge.restored")
	await t.steps(3)
	var forge := _forge(t)
	if not t.check(forge != null, "the lit Forge is no crafting station"):
		return
	t.equal(_ids(RecipeCatalog.recipes_at(forge.call(&"site"))), [], "the Forge's recipes before Pip's lesson")
	t.equal(str(quests.call(&"marker_for", PIP_ID)), "tip", "Pip's marker once the Forge is lit")
	var dialogue: Node = t.tree.get_first_node_in_group(&"dialogue_box")
	await _talk_to(t, PIP)
	await _read_all(t, dialogue)
	t.check(run.knows_recipe("brew-fizzy"), "Pip did not teach the Fizzy Brew")
	t.check(run.has_heard_tip("pip.fizzy-brew"), "Pip's tip was not heard")
	t.equal(_ids(RecipeCatalog.recipes_at(forge.call(&"site"))), ["brew-fizzy"], "the Forge's recipes after Pip's lesson")
	# Brew one at the Forge.
	run.add_item("purple-berry-mat", 2)
	run.add_item("shard", 1)
	var menus: Node = t.main.menu_windows
	t.check(bool(menus.call(&"open_station", forge.call(&"site"))), "the Forge window did not open")
	var crafting: Node = menus.get(&"crafting")
	crafting.call(&"select_recipe", 0)
	crafting.call(&"craft")
	crafting.call(&"close")
	t.equal(run.item_count("energy-potion"), 1, "Fizzy Brews brewed at the Forge")


func _forge(t: TestContext) -> Node:
	for node: Node in t.tree.get_nodes_in_group(&"crafting_station"):
		if str(node.get(&"recipe_context")) == "forge" and node.is_inside_tree():
			return node
	return null


static func _ids(recipes: Array) -> Array:
	return recipes.map(func(recipe: Dictionary) -> String: return str(recipe["id"]))


## NPC `instance_id` 40 px right of the player at CENTRE, then the interact button.
func _talk_to(t: TestContext, instance_id: String) -> void:
	var npc: Node = null
	for node: Node in t.tree.get_nodes_in_group(&"npc"):
		if str(node.call(&"get_instance_id_key")) == instance_id:
			npc = node
	if not t.check(npc != null, "no %s in level-1" % instance_id):
		return
	npc.call(&"configure_wander", {})
	var body := npc.get(&"body") as CharacterBody2D
	body.velocity = Vector2.ZERO
	var offset: Vector2 = npc.call(&"get_phaser_position") - body.global_position
	body.global_position = CENTRE + NPC_OFFSET - offset
	body.reset_physics_interpolation()
	t.teleport_player(CENTRE)
	await t.steps(2)
	t.main.interaction.refresh(null)
	t.tap(&"interact")
	await t.steps(2)


## Reads every page until the box stays shut.
static func _read_all(t: TestContext, dialogue: Node) -> void:
	var shut_steps := 0
	var guard := 600
	while shut_steps < 20 and guard > 0 and not t.aborted:
		guard -= 1
		if bool(dialogue.call(&"is_open")):
			shut_steps = 0
			dialogue.call(&"advance")
		else:
			shut_steps += 1
		await t.tree.process_frame
