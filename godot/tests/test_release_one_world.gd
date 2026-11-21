extends RefCounted
## Release 1's world pieces in Slimeshire (level-1): the fallen trees on the Market Hill road (C4,
## `Chapter1/market-hill-tree`) and at the Verdant Gate (D4, `Chapter1/verdant-tree`), which only a
## Heavy Roll smashes, for good (game/scripts/plank_barricade.gd; a save whose old Verdant Gate was
## unlocked counts its tree smashed); the heap hatch over Yoi's home in Lili's west yard (C4,
## `Chapter1/yoi-hatch`: shut while a crate lies on it, open for good once the last is taken off,
## game/scripts/heap_hatch.gd); and the finds (docs/godot/specs/quests.md 14.8): a war-journal page,
## the recipe page and the Charged Roll never sit in the bag, a page is kept for the journal's War
## journal, the recipe page teaches its recipe and the Charged Roll its upgrade; and the four Roll
## fragments (owner, 2026-11-20): counted as they come, never in the bag, the fourth teaches the Charged
## Roll, and a save past Burr's cell from before them counts his fragment on load.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const QuestJournalModel := preload("res://game/ui/screens/quest_journal_model.gd")
const WarJournal := preload("res://game/quests/war_journal.gd")

const VILLAGE := "level-1-c4"
const GATE_MAP := "level-1-d4"
const MARKET_TREE := "Chapter1/market-hill-tree"
const MARKET_FLAG := "level-1.market-hill-tree-smashed"
const VERDANT_TREE := "Chapter1/verdant-tree"
const VERDANT_FLAG := "level-1.verdant-tree-smashed"
const HATCH := "Chapter1/yoi-hatch"
const HATCH_FLAG := "level-1.yoi-hatch-open"


func test_only_a_heavy_roll_smashes_the_market_hill_tree_for_good(t: TestContext) -> void:
	var run := Services.run()
	var tree := t.world().world_root.get_node_or_null(MARKET_TREE)
	if not t.check(tree != null, "no fallen tree on the Market Hill road"):
		return
	t.equal(str(tree.get(&"flag_id")), MARKET_FLAG, "the tree's flag")
	t.check(not bool(tree.call(&"is_smashed")), "the tree starts smashed")
	var area := tree.get_node("DamageArea") as Area2D
	_route(t, area, ["roll"])
	t.check(not bool(tree.call(&"is_smashed")), "a plain Roll smashed the fallen tree")
	_route(t, area, ["spear"])
	t.check(not bool(tree.call(&"is_smashed")), "the Spear smashed the fallen tree")
	_route(t, area, ["roll", "heavy"])
	t.check(bool(tree.call(&"is_smashed")), "a Heavy Roll did not smash the fallen tree")
	t.check(run.has_flag(MARKET_FLAG), "the smash is not kept")
	# Built again, it lies smashed.
	if not await _travel(t, GATE_MAP) or not await _travel(t, VILLAGE):
		return
	tree = t.world().world_root.get_node_or_null(MARKET_TREE)
	t.check(tree != null and bool(tree.call(&"is_smashed")), "the smashed tree stands again after a travel")


func test_the_verdant_gate_is_a_fallen_tree_and_an_old_open_gate_counts(t: TestContext) -> void:
	var run := Services.run()
	if not await _travel(t, GATE_MAP):
		return
	var root := t.world().world_root
	t.check(root.find_child("level-1-verdant-gate", true, false) == null, "the old Verdant Gate is still in D4")
	var tree := root.get_node_or_null(VERDANT_TREE)
	if not t.check(tree != null, "no fallen tree at the Verdant Gate"):
		return
	t.equal(str(tree.get(&"flag_id")), VERDANT_FLAG, "the Verdant tree's flag")
	var area := tree.get_node("DamageArea") as Area2D
	_route(t, area, ["roll"])
	t.check(not bool(tree.call(&"is_smashed")), "a plain Roll smashed the Verdant tree")
	# A save from before, its Verdant Gate unlocked, loads with the tree smashed.
	var data := run.serialize()
	var maps: Dictionary = data["world"].get_or_add("maps", {})
	var record: Dictionary = maps.get_or_add(GATE_MAP, {})
	record["unlocked_gate_ids"] = ["level-1-east-verdant-gate"]
	t.check(run.install(data), "install refused the save")
	t.check(run.has_flag(VERDANT_FLAG), "an old unlocked Verdant Gate did not count its tree smashed")


func test_the_heap_hatch_opens_once_its_crates_are_gone(t: TestContext) -> void:
	var run := Services.run()
	var hatch := t.world().world_root.get_node_or_null(HATCH)
	if not t.check(hatch != null, "no heap hatch in Lili's west yard"):
		return
	var crates := (hatch.get_node("Heap") as Node).get_children()
	t.equal(crates.size(), 7, "crates on the hatch")
	t.check(not bool(hatch.call(&"is_open")), "the hatch starts open")
	t.equal(int(hatch.call(&"lying_on")), 7, "crates lying on the hatch")
	var opened: Array = []
	hatch.connect(&"opened", func(payload: Dictionary) -> void: opened.append(payload))
	# Take all but one off: still shut.
	for i in crates.size() - 1:
		(crates[i] as Node2D).global_position += Vector2(0.0, 400.0)
	await t.steps(3)
	t.check(not bool(hatch.call(&"is_open")), "the hatch opened with a crate still on it")
	(crates[crates.size() - 1] as Node2D).global_position += Vector2(0.0, 400.0)
	t.check(await t.until(func() -> bool: return bool(hatch.call(&"is_open")), 500.0), "the hatch did not open once its crates were gone")
	t.equal(opened.size(), 1, "the hatch's opened signals")
	t.check(run.has_flag(HATCH_FLAG), "the open hatch is not kept")
	var door: Node = hatch.get(&"door")
	t.check((door.get(&"trigger_rect") as Rect2).has_area(), "the open hatch's way down is off")
	# Built again, it lies open with its crates gone.
	if not await _travel(t, GATE_MAP) or not await _travel(t, VILLAGE):
		return
	hatch = t.world().world_root.get_node_or_null(HATCH)
	t.check(hatch != null and bool(hatch.call(&"is_open")), "the hatch is shut again after a travel")
	if hatch != null:
		t.equal(int(hatch.call(&"lying_on")), 0, "crates on the open hatch after a travel")


func test_four_roll_fragments_teach_the_charged_roll(t: TestContext) -> void:
	var run := Services.run()
	var found: Array = []
	t.listen(run.fragment_found, func(payload: Dictionary) -> void: found.append(payload))
	t.equal(run.fragments_needed("roll-fragment"), 4, "Roll fragments needed")
	for i in 3:
		t.equal(run.add_item("roll-fragment", 1), 1, "fragment %d added" % (i + 1))
	t.equal(run.fragment_count("roll-fragment"), 3, "fragments counted")
	t.equal(run.item_count("roll-fragment"), 0, "a fragment in the bag")
	t.check(not run.has_learned_ability("roll-charge"), "three fragments taught the Charged Roll")
	t.equal(found.size(), 3, "fragment_found signals")
	if found.size() == 3:
		t.equal([int(found[2]["count"]), int(found[2]["total"])], [3, 4], "the third fragment's count")
	run.add_item("roll-fragment", 1)
	t.check(run.has_learned_ability("roll-charge"), "the fourth fragment did not teach the Charged Roll")
	# A save that freed Burr before the fragments existed counts his on load, quietly.
	var data := run.serialize()
	var story: Dictionary = data["story"]
	story.erase("fragments")
	var flags: Array = story.get_or_add("world_flags", [])
	flags.erase("fatty-lair.burr-fragment")
	if not "fatty-lair.burr-freed" in flags:
		flags.append("fatty-lair.burr-freed")
	var learned: Array = story.get_or_add("learned_ability_ids", [])
	learned.erase("roll-charge")
	if not t.check(run.install(data), "install refused the save"):
		return
	t.check(not run.has_learned_ability("roll-charge"), "the old save knows the Charged Roll")
	t.equal(run.fragment_count("roll-fragment"), 1, "Burr's fragment on load")
	t.check(run.has_flag("fatty-lair.burr-fragment"), "Burr's fragment flag on load")


func test_finds_never_sit_in_the_bag(t: TestContext) -> void:
	var run := Services.run()
	var found: Array = []
	t.listen(run.page_found, func(payload: Dictionary) -> void: found.append(payload))
	run.quiet_items = true
	t.equal(run.add_item("war-journal-page-2", 1), 1, "a page added")
	t.equal(run.item_count("war-journal-page-2"), 0, "a page in the bag")
	t.check(run.has_war_page("war-journal-page-2"), "the page was not kept")
	t.equal(run.war_page_ids(), ["war-journal-page-2"], "the pages found")
	t.equal(found.size(), 1, "page_found signals")
	t.check(not run.knows_recipe("cook-berry-basket"), "the basket is known before its page")
	run.add_item("recipe-page-berry-basket", 1)
	t.check(run.knows_recipe("cook-berry-basket"), "the recipe page did not teach the basket")
	t.equal(run.item_count("recipe-page-berry-basket"), 0, "the recipe page in the bag")
	t.check(not run.has_war_page("recipe-page-berry-basket"), "the recipe page counts as a war-journal page")
	run.add_item("charged-roll", 1)
	t.check(run.has_learned_ability("roll-charge"), "the Charged Roll find did not teach its upgrade")
	t.equal(run.item_count("charged-roll"), 0, "the Charged Roll in the bag")
	run.quiet_items = false
	# The journal's War journal lists the page found.
	var quests: Node = t.main.quests
	var page := QuestJournalModel.snapshot(quests.call(&"list"), QuestJournalModel.WAR_ID, "",
		{"tips": [], "has_flag": run.has_flag, "war_pages": WarJournal.found_pages(run),
		"war_page_count": WarJournal.page_count()})
	t.equal(page["details_name"], QuestJournalModel.WAR_TITLE, "the War journal page")
	t.check(page["details"].contains(QuestJournalModel.WAR_PAGE_HEADING % [2, str(WarJournal.page("war-journal-page-2").get("title", "?"))]),
		"the War journal lacks page 2:\n%s" % page["details"])
	t.check(page["details"].contains(QuestJournalModel.WAR_MANY_LOST % 2), "the War journal does not count the pages still lost")
	# A save keeps the pages.
	var data := run.serialize()
	t.check(run.install(data), "install refused the save")
	t.equal(run.war_page_ids(), ["war-journal-page-2"], "the pages found after a load")


# --- helpers ---------------------------------------------------------------------------------------

## A hit with `tags` on `area` (its own activation), as a Roll's bonk or a weapon would send it.
func _route(t: TestContext, area: Area2D, tags: Array) -> void:
	var router := Services.router()
	var source := Node2D.new()
	var attack := Area2D.new()
	t.main.add_child(source)
	t.main.add_child(attack)
	var areas: Array[Area2D] = [attack]
	var activation := router.begin_activation(source, areas)
	router.route({"activation_id": activation, "source": source, "attack_area": attack, "target_area": area,
		"weapon_id": "test-" + str(tags[0]), "weapon_tags": tags, "damage_types": ["physical"], "base_damage": 20.0,
		"effects": [], "impact": {"position": area.global_position, "knock": Vector2.LEFT}})
	router.end_activation(activation)
	source.queue_free()
	attack.queue_free()


static func _travel(t: TestContext, map: String) -> bool:
	if not t.check(t.main.travel_to(map, "west"), "travel to %s was refused" % map):
		return false
	var arrived := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == map and t.player() != null, 3000.0, 6000.0)
	if not t.check(arrived, "the player did not reach %s" % map):
		return false
	await t.steps(2)
	return true
