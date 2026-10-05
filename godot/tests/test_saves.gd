extends RefCounted
## Saves (RunState `save_slot` / `load_slot` / `list_saves`, Main.load_run; Phaser SaveSystem):
## the run round-trips through a JSON file (counts come back as integers), a load rebuilds the
## saved world with the player at the saved spot, a dead slime is never autosaved, and a broken or
## newer file is refused. The runner points `save_root` at its per-process user://test-saves-<pid>.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")

const SLOT := 3
const SPOT := Vector2(768.0, 832.0)


func test_round_trip_keeps_the_run(t: TestContext) -> void:
	var run := Services.run()
	run.delete_slot(SLOT)
	run.add_item("wood", 30)
	run.add_coins(7)
	run.set_flag("test.saved-flag")
	run.learn_ability("jump")
	run.set_resource_record("level-1", "level-1-tree-004", {"stage": "node", "value": 26.0})
	t.check(run.save_slot(SLOT), "save_slot failed")
	t.check(run.has_save(SLOT), "no file after saving")
	run.new_run()
	t.equal(run.item_count("wood"), 0, "wood after a new run")
	t.check(run.load_slot(SLOT), "load_slot failed")
	t.equal(run.item_count("wood"), 30, "wood after loading")
	t.equal(typeof((run.inventory["slots"] as Array)[0]["count"]), TYPE_INT, "slot counts load as integers")
	t.equal(run.coins(), 57, "coins after loading")
	t.check(run.has_flag("test.saved-flag"), "story flag lost")
	t.check(run.has_learned_ability("jump"), "learned ability lost")
	t.equal(float(run.resource_record("level-1", "level-1-tree-004").get("value", 0.0)), 26.0, "tree record lost")
	t.equal(run.consume_navigation().get("kind"), "load", "the load queues a load navigation")
	var saves := run.list_saves()
	t.check(saves.any(func(entry: Dictionary) -> bool: return int(entry["slot"]) == SLOT and entry["map_id"] == "level-1"),
		"list_saves %s" % [saves])
	run.delete_slot(SLOT)


func test_load_run_rebuilds_at_the_saved_spot(t: TestContext) -> void:
	var run := Services.run()
	run.delete_slot(SLOT)
	t.teleport_player(SPOT)
	t.player().face(Vector2.LEFT)
	t.player().restore_run_state({"hp": 77})
	await t.steps(2)
	var saved_at := t.player().get_centre()
	t.check(run.save_slot(SLOT), "save_slot failed")
	t.teleport_player(Vector2(640.0, 704.0))
	t.player().restore_run_state({"hp": 100})
	await t.steps(1)
	t.check(t.main.load_run(SLOT), "load_run failed")
	await t.steps(3)
	t.near_vec(t.player().get_centre(), saved_at, 0.5, "player at the saved spot")
	t.equal(t.player().get_hp(), 77, "HP from the save")
	t.check(t.player().get_facing().x < 0.0, "saved facing (left) lost")
	run.delete_slot(SLOT)


func test_dead_slime_is_not_autosaved(t: TestContext) -> void:
	var run := Services.run()
	run.delete_slot(run.AUTOSAVE_SLOT)
	run.autosave_enabled = true
	run.player["hp"] = 0
	run.location_provider = Callable()
	t.check(not run.write_recovery(), "a dead slime was autosaved")
	t.check(not run.has_save(run.AUTOSAVE_SLOT), "an autosave file appeared")
	run.player["hp"] = 50
	t.check(run.write_recovery(), "a living slime was not autosaved")
	run.delete_slot(run.AUTOSAVE_SLOT)


func test_unreadable_and_newer_saves_are_refused(t: TestContext) -> void:
	var run := Services.run()
	DirAccess.make_dir_recursive_absolute(run.save_root)
	var path: String = run.save_root.path_join("slot-%d.json" % SLOT)
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{ not json")
	broken.close()
	t.check(not run.load_slot(SLOT), "a broken file loaded")
	var newer := FileAccess.open(path, FileAccess.WRITE)
	newer.store_string(JSON.stringify({"schema_version": run.SAVE_SCHEMA_VERSION + 1, "data": run.serialize()}))
	newer.close()
	t.check(not run.load_slot(SLOT), "a save from a newer version loaded")
	run.delete_slot(SLOT)


## A defeated slime whose last bed is in slime-home wakes there, full HP.
func test_respawn_at_bed_in_another_world(t: TestContext) -> void:
	var run := Services.run()
	run.set_respawn_point({"area_id": "slime-home", "map_id": "slime-home", "x": 160.0, "y": 356.0, "bed_id": "world.slime-home.west-bed"})
	var player := t.player()
	player.restore_run_state({"hp": 1})
	player.call(&"_die")
	var arrived := await t.until(func() -> bool:
		return t.world().map_id() == "slime-home" and t.player() != null and not t.main.is_transitioning(), 4000.0, 8000.0)
	if not t.check(arrived, "the slime did not wake in slime-home"):
		return
	await t.steps(2)
	t.equal(t.player().get_hp(), t.player().get_max_hp(), "HP at the bed")
	t.check(t.player().get_centre().distance_to(Vector2(160.0, 356.0)) < 40.0, "not at the bed: %s" % [t.player().get_centre()])


## A load in a running game refreshes the views main keeps across worlds: the HUD weapon belt and
## the quest tracker show the loaded run, not the one before it.
func test_load_in_game_refreshes_the_hud_views(t: TestContext) -> void:
	var run := Services.run()
	await t.steps(2)
	t.check(run.save_slot(SLOT), "save_slot failed")
	run.add_item("stone-axe", 1)
	run.set_weapon_slots(["basic-sword", "stone-axe", null, null])
	t.main.quests.debug_activate("a-place-to-work")
	await t.steps(2)
	var hotbar: Node = null
	var tracker: Node = null
	for child: Node in t.main.get_node("Hud").get_children():
		var path := str(child.get_script().resource_path) if child.get_script() != null else ""
		if path.ends_with("weapon_hotbar.gd"):
			hotbar = child
		elif path.ends_with("quest_tracker.gd"):
			tracker = child
	if not t.check(hotbar != null and tracker != null, "no hotbar or tracker on the HUD"):
		return
	t.equal(str(hotbar.call(&"model")["weapons"][1]["item_id"]), "stone-axe", "belt slot 2 before the load")
	var before := str(tracker.call(&"model").get("quest1Objectives", ""))
	t.check(t.main.load_run(SLOT), "load_run failed")
	await t.steps(3)
	t.equal(str(hotbar.call(&"model")["weapons"][1]["item_id"]), "", "belt slot 2 after the load")
	t.check(str(tracker.call(&"model").get("quest1Objectives", "")) != before, "the tracker still shows the run before the load")


## A slot file without the run's sections is unreadable, not loadable (it would crash the load).
func test_slot_without_sections_is_unreadable(t: TestContext) -> void:
	var run := Services.run()
	DirAccess.make_dir_recursive_absolute(run.save_root)
	var file := FileAccess.open(run.save_root.path_join("slot-%d.json" % SLOT), FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 1, "data": {}}))
	file.close()
	t.equal(run.inspect_slot(SLOT)["problem"], "not a save file", "an empty data section")
	t.check(not run.load_slot(SLOT), "an empty save loaded")
	t.equal(run.list_saves().size(), 0, "listed saves")
