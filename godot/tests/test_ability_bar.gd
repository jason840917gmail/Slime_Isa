extends RefCounted
## The HUD's ability bar (game/ui/ability_bar.gd; abilities spec 2.6): labels follow the
## abilities' state, a click runs an ability, a window pause disables every button.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")


func _bar(t: TestContext) -> Node:
	return t.main.get_node("Hud").call(&"get_ability_bar")


func test_labels_follow_the_abilities(t: TestContext) -> void:
	var bar := _bar(t)
	if not t.check(bar != null, "the HUD has no ability bar"):
		return
	var player := t.player()
	var model: Dictionary = bar.call(&"snapshot")
	t.equal(model[&"jump"]["label"], "Quest\nJump", "a jump not learned yet")
	t.check(model[&"jump"]["disabled"], "a jump not learned yet is disabled")
	t.equal(model[&"dodge"]["label"], "1\nDodge", "the dodge (learned in the trial)")
	t.check(not model[&"dodge"]["disabled"], "the dodge is enabled")
	t.equal(model[&"teleport"]["label"], "Later\nTeleport", "a teleport not learned yet")
	Services.run().learn_ability("teleport")
	player.set_energy(10.0)
	t.equal(bar.call(&"snapshot")[&"teleport"]["label"], "Need 35E\nTeleport", "too little energy for a teleport")
	Services.run().learn_ability("jump")
	t.equal(bar.call(&"snapshot")[&"jump"]["label"], "Space\nJump", "a learned jump")
	t.check(bool(bar.call(&"activate", &"jump")), "the bar's Jump button did not jump")
	await t.steps(2)
	t.check(player.is_ability_busy(), "no jump under way after the click")
	var label := str(bar.call(&"snapshot")[&"jump"]["label"])
	t.check(label == "Busy\nJump" or label.ends_with("s\nJump"), "jump label while jumping: %s" % label)


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
