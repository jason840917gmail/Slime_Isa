extends RefCounted
## The save slots window (game/saves/save_slots_menu.gd; Phaser SaveSlotsSurfacePort.ts): saving to
## an empty slot, the overwrite confirmation, load mode (the autosave first, empty slots
## disabled, an unreadable file says why) and loading a slot in a running game.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const SaveSlotsMenu := preload("res://game/saves/save_slots_menu.gd")

const SEP := "  ·  "


## The window, mounted on the Shell when it can host it, else standalone under main.
func _menu(t: TestContext) -> Node:
	var shell := Services.shell()
	var menu: Node = SaveSlotsMenu.install(shell) if shell != null else null
	if menu == null:
		menu = (load(SaveSlotsMenu.SCENE_PATH) as PackedScene).instantiate()
		t.main.add_child(menu)
	return menu


func test_save_to_empty_slot_then_overwrite(t: TestContext) -> void:
	var run := Services.run()
	var menu := _menu(t)
	menu.call(&"open_for", &"save")
	t.check(menu.call(&"is_open"), "the window did not open")
	t.equal((menu.get_node("Panel/Title") as Label).text, "Save game", "title")
	var slot1: Button = menu.call(&"slot_button", 1)
	t.equal(slot1.text, "Slot 1" + SEP + "Empty", "an empty slot")
	t.check(not slot1.disabled, "an empty slot is disabled in save mode")
	t.check(not (menu.get_node("Panel/Autosave") as Button).visible, "the autosave shows in save mode")
	slot1.pressed.emit()
	t.check(run.has_save(1), "slot 1 was not written")
	t.equal(menu.call(&"status_text"), "Saved to Slot 1.", "status after saving")
	t.check(slot1.text.begins_with("Slot 1" + SEP + "Slimeshire Meadow" + SEP + "0:00 played" + SEP), "slot 1 label: %s" % slot1.text)
	slot1.pressed.emit()
	t.equal(menu.call(&"status_text"), "Slot 1 already holds a save. Overwrite it?", "the overwrite question")
	t.check((menu.get_node("Panel/Confirm") as Button).visible, "no Overwrite button")
	(menu.get_node("Panel/Cancel") as Button).pressed.emit()
	t.check(not (menu.get_node("Panel/Confirm") as Button).visible, "Overwrite still shown after Cancel")
	t.equal(menu.call(&"status_text"), "Saved to Slot 1.", "status after Cancel (the last result stays, as in Phaser)")
	slot1.pressed.emit()
	(menu.get_node("Panel/Confirm") as Button).pressed.emit()
	t.equal(menu.call(&"status_text"), "Saved to Slot 1.", "status after overwriting")
	menu.call(&"close")


func test_load_mode_lists_autosave_and_unreadable_slots(t: TestContext) -> void:
	var run := Services.run()
	t.check(run.save_slot(0), "the autosave was not written")
	t.check(run.save_slot(2), "slot 2 was not written")
	DirAccess.make_dir_recursive_absolute(run.save_root)
	var broken := FileAccess.open(run.save_root.path_join("slot-3.json"), FileAccess.WRITE)
	broken.store_string("not json")
	broken.close()
	var menu := _menu(t)
	menu.call(&"open_for", &"load")
	t.equal((menu.get_node("Panel/Title") as Label).text, "Load game", "title")
	var autosave := menu.get_node("Panel/Autosave") as Button
	t.check(autosave.visible and not autosave.disabled, "the autosave is not offered")
	t.check(autosave.text.begins_with("Autosave (latest)" + SEP + "Slimeshire Meadow" + SEP), "autosave label: %s" % autosave.text)
	var slot1: Button = menu.call(&"slot_button", 1)
	t.check(slot1.disabled, "an empty slot can be loaded")
	t.check(not (menu.call(&"slot_button", 2) as Button).disabled, "slot 2 cannot be loaded")
	t.equal((menu.call(&"slot_button", 3) as Button).text, "Slot 3" + SEP + "Can't be loaded: not a save file", "an unreadable slot")
	t.check((menu.call(&"slot_button", 3) as Button).disabled, "an unreadable slot can be loaded")
	menu.call(&"close")


func test_load_slot_in_a_running_game(t: TestContext) -> void:
	var run := Services.run()
	t.teleport_player(Vector2(900.0, 1200.0))
	await t.steps(2)
	run.add_coins(25)
	t.check(run.save_slot(1), "slot 1 was not written")
	run.add_coins(100)
	t.teleport_player(Vector2(700.0, 900.0))
	await t.steps(2)
	var menu := _menu(t)
	menu.call(&"open_for", &"load")
	(menu.call(&"slot_button", 1) as Button).pressed.emit()
	await t.steps(3)
	t.check(not menu.call(&"is_open"), "the window stayed open after loading")
	t.equal(run.coins(), 75, "coins after loading slot 1")
	t.near_vec(t.player().get_centre(), Vector2(900.0, 1200.0), 40.0, "the slime is back where slot 1 was saved")
