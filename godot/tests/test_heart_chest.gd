extends RefCounted
## A Goo Heart inside a chest (docs/godot/DUNGEONS.md "Chests"; chest.gd `goo_heart_id`), in the
## plank lab's island (game/dev/planks/playground-planks.tscn): opening the chest grants the heart
## once (its flag "goo-heart.<id>", max HP up by `gooHeart.maxHpBonus`, health full), with only the
## heart inside no window opens, a heart beside other things opens the window on them once the heart
## has risen (one `open_requested`, the world running meanwhile), the dungeon chest does the same,
## and the opened chest stays open in a save loaded again.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const Chest := preload("res://game/scripts/chest.gd")

const HEART_RISE_MS := Chest.HEART_RISE_MS
const LAB := "playground-planks"
const SLOT := 4
const FEET := 27.56
const ISLAND := Vector2(9.3 * 64.0, 3.7 * 64.0)


func test_a_chest_grants_its_heart_once_and_stays_open(t: TestContext) -> void:
	await _enter_lab(t)
	var run := Services.run()
	var player := t.player()
	var chest := _chest(t, "heart-chest")
	if not t.check(chest != null, "the lab has no heart chest"):
		return
	t.check(not chest.call(&"is_empty"), "a chest holding a heart reads empty")
	var max_before := player.get_max_hp()
	var bonus := Services.constants().integer("character.player.gooHeart.maxHpBonus")
	t.equal(str(chest.call(&"request_open")), "opened", "the chest's opening")
	await t.steps(2)
	t.check(run.has_flag("goo-heart.plank-lab-heart"), "the heart's flag is not set")
	t.equal(player.get_max_hp(), max_before + bonus, "max HP after the chest's heart")
	t.equal(player.get_hp(), player.get_max_hp(), "health after the chest's heart")
	t.check(bool(chest.call(&"is_empty")), "the chest is not empty after giving its heart")
	t.check(_window_chest(t) == null, "a chest with only a heart opened the chest window")
	# Opened again: nothing more, and still no window once the heart has risen.
	chest.call(&"request_open")
	await t.steps(2)
	t.equal(player.get_max_hp(), max_before + bonus, "max HP after opening the chest again")
	await t.sim_wait(HEART_RISE_MS + 100.0)
	t.check(not bool(chest.call(&"is_heart_rising")), "the heart is still rising")
	t.check(_window_chest(t) == null, "a chest with only a heart opened the chest window after its rise")
	var window := _window(t)
	if window != null and window.has_method(&"close"):
		window.call(&"close")
	# A save loaded again: the chest stays open, the heart is not given twice.
	t.check(run.save_slot(SLOT), "the run was not saved")
	t.check(bool(t.main.call(&"load_run", SLOT)), "the save did not load")
	await t.until(func() -> bool: return t.in_world(LAB) and t.player() != null \
		and not bool(t.main.call(&"is_transitioning")), 5000.0)
	await t.steps(4)
	var again := _chest(t, "heart-chest")
	t.check(again != null and bool(again.call(&"is_empty")), "the opened chest is closed again after a load")
	t.equal(t.player().get_max_hp(), max_before + bonus, "max HP after the load")
	if again != null:
		again.call(&"request_open")
		await t.steps(2)
		t.equal(t.player().get_max_hp(), max_before + bonus, "max HP after opening the loaded chest")
	run.delete_slot(SLOT)


func test_a_heart_beside_other_things_and_in_a_dungeon_chest(t: TestContext) -> void:
	await _enter_lab(t)
	var run := Services.run()
	var player := t.player()
	var bonus := Services.constants().integer("character.player.gooHeart.maxHpBonus")
	var max_before := player.get_max_hp()
	# A heart and wood: the heart rises first (the world runs on), then the window shows the wood.
	var mixed := _chest(t, "heart-wood-chest")
	var requested: Array = []
	mixed.connect(&"open_requested", func(payload: Dictionary) -> void: requested.append(payload))
	var opened_at := t.now()
	t.equal(str(mixed.call(&"request_open")), "opened", "the mixed chest's opening")
	await t.steps(2)
	t.check(run.has_flag("goo-heart.plank-lab-heart-2"), "the mixed chest's heart flag is not set")
	t.equal(player.get_max_hp(), max_before + bonus, "max HP after the mixed chest")
	t.check(_window_chest(t) == null, "the mixed chest's window opened before its heart rose")
	t.check(not t.tree.paused, "the world paused while the heart rises")
	t.equal(str(mixed.call(&"request_open")), "opened", "the mixed chest asked again during the rise")
	var shown := await t.until(func() -> bool: return _window_chest(t) == mixed, HEART_RISE_MS + 1000.0)
	t.check(shown, "the mixed chest's window did not open on its wood")
	t.check(t.now() - opened_at >= HEART_RISE_MS - 1.0, "the window opened %.0f ms after the chest, before the heart rose" \
		% (t.now() - opened_at))
	t.equal(requested.size(), 1, "the mixed chest's open_requested count")
	t.check(not bool(mixed.call(&"is_empty")), "the mixed chest lost its wood")
	var window := _window(t)
	if window != null and window.has_method(&"close"):
		window.call(&"close")
	await t.steps(2)
	# The dungeon chest with only a heart.
	var dungeon := _chest(t, "heart-dungeon-chest")
	t.equal(str(dungeon.call(&"request_open")), "opened", "the dungeon chest's opening")
	await t.steps(2)
	t.check(run.has_flag("goo-heart.plank-lab-heart-3"), "the dungeon chest's heart flag is not set")
	t.equal(player.get_max_hp(), max_before + bonus * 2, "max HP after the dungeon chest")
	t.check(bool(dungeon.call(&"is_empty")), "the dungeon chest is not empty after its heart")


func _enter_lab(t: TestContext) -> void:
	t.main.call(&"travel_to", LAB)
	await t.until(func() -> bool: return t.in_world(LAB) and t.player() != null \
		and not bool(t.main.call(&"is_transitioning")), 5000.0)
	await t.steps(4)
	t.teleport_player(ISLAND - Vector2(0.0, FEET))
	await t.steps(3)


func _chest(t: TestContext, root_name: String) -> Node:
	var world_root: Node = t.world().world_root if t.world() != null else null
	var root := world_root.find_child(root_name, true, false) if world_root != null else null
	return root.get_node_or_null(^"ChestScript") if root != null else null


func _window(t: TestContext) -> Node:
	return t.tree.get_first_node_in_group(&"chest_window")


func _window_chest(t: TestContext) -> Node:
	var window := _window(t)
	return window.call(&"current_chest") if window != null and window.has_method(&"current_chest") else null
