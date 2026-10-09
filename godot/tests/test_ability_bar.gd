extends RefCounted
## The HUD's ability buttons (game/ui/ability_bar.gd; abilities spec 2.6, the HUD console's icon
## slots since 2026-10-08): labels and states follow the abilities, a click runs an ability, a
## window pause disables every slot, and the row sits on the console.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const AbilityBar := preload("res://game/ui/ability_bar.gd")


func _bar(t: TestContext) -> Node:
	return t.main.get_node("Hud").call(&"get_ability_bar")


func test_labels_follow_the_abilities(t: TestContext) -> void:
	var bar := _bar(t)
	if not t.check(bar != null, "the HUD has no ability bar"):
		return
	var player := t.player()
	var model: Dictionary = bar.call(&"snapshot")
	t.check(not model.has(&"jump"), "Jump is on the bar (it left the interface on 2026-10-08)")
	t.equal(model[&"dodge"]["label"], "2\nRoll", "the Roll, the dodge id (learned in the trial; key 2 since 2026-10-09)")
	t.equal(model[&"dodge"]["state"], "ready", "the dodge's state")
	t.check(not model[&"dodge"]["disabled"], "the dodge is enabled")
	t.equal(model[&"teleport"]["label"], "Later\nTeleport", "a teleport not learned yet")
	t.equal(model[&"teleport"]["state"], "locked", "a teleport not learned yet is locked")
	Services.run().learn_ability("teleport")
	player.set_energy(10.0)
	model = bar.call(&"snapshot")
	t.equal(model[&"teleport"]["label"], "Need 35E\nTeleport", "too little energy for a teleport")
	t.equal(model[&"teleport"]["state"], "energy", "the teleport's state without energy")
	player.set_energy(100.0)
	t.check(bool(bar.call(&"activate", &"dodge")), "the bar's Roll slot did not roll")
	await t.steps(2)
	var label := str(bar.call(&"snapshot")[&"dodge"]["label"])
	t.check(label == "Busy\nRoll" or label.ends_with("s\nRoll"), "Roll label while rolling: %s" % label)


func test_window_pause_disables_the_bar(t: TestContext) -> void:
	var bar := _bar(t)
	var world := Services.world()
	world.set_pause_reason(Services.WorldServiceType.PAUSE_MODAL, true)
	await t.tree.process_frame
	var model: Dictionary = bar.call(&"snapshot")
	t.check(model[&"dodge"]["disabled"], "the dodge stays enabled under a window")
	t.check(not bool(bar.call(&"activate", &"dodge")), "the dodge ran under a window")
	world.set_pause_reason(Services.WorldServiceType.PAUSE_MODAL, false)
	await t.tree.process_frame
	t.check(not bar.call(&"snapshot")[&"dodge"]["disabled"], "the dodge is still disabled after the window closed")


## The row sits on the HUD console's ability rect, one slot per ability of the bar.
func test_the_row_sits_on_the_console(t: TestContext) -> void:
	var bar := _bar(t) as Control
	await t.tree.process_frame
	var console: Node = t.main.get_node("Hud").call(&"get_console")
	var rect: Rect2 = (console.call(&"rects") as Dictionary)["abilities"]
	t.near_vec(bar.position, rect.position, 0.5, "the row's place")
	t.near_vec(bar.size, AbilityBar.row_size(AbilityBar.slots().size()), 0.5, "the row's size")
	t.near_vec(bar.size, rect.size, 0.5, "the row fills the console's rect")
