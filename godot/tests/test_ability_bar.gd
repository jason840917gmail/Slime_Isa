extends RefCounted
## The HUD's ability buttons (game/ui/ability_bar.gd; abilities spec 2.6, the HUD console's icon
## slots since 2026-10-08), in the body-shapes rework mode that is on in every world (BODY_SHAPES.md
## "HUD and bag": the Ability slot and the Roll): labels and states follow the abilities, a click runs
## an ability, a window pause disables every slot, and the row sits on the console.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const AbilityBar := preload("res://game/ui/ability_bar.gd")


func _bar(t: TestContext) -> Node:
	return t.main.get_node("Hud").call(&"get_ability_bar")


func test_labels_follow_the_abilities(t: TestContext) -> void:
	# The Roll is young Burr's lesson since 2026-11-19 (on the bar once learned): lent here.
	Services.run().learn_session_ability("dodge")
	# The bar follows the learned abilities in its own `_process` (`process_frame` fires before it).
	await t.tree.process_frame
	await t.tree.process_frame
	var bar := _bar(t)
	if not t.check(bar != null, "the HUD has no ability bar"):
		return
	var player := t.player()
	# The rework mode's bar (on in every world): at most the Ability slot and the Roll, no slot of
	# the Jump, Swallow, Lash, Slam or Teleport of their own (BODY_SHAPES.md "HUD and bag").
	var model: Dictionary = bar.call(&"snapshot")
	t.equal(model.keys(), [&"dodge"], "the slots with only the Roll learned (the box empty: no Ability slot)")
	t.equal(model[&"dodge"]["label"], "S\nRoll", "the Roll, the dodge id (on S in the keys-only default)")
	t.equal(model[&"dodge"]["state"], "ready", "the dodge's state")
	t.check(not model[&"dodge"]["disabled"], "the dodge is enabled")
	# A box ability learned (not quietly) becomes the box's choice and fills the Ability slot, with
	# the `ability_use` key (F) and its energy cost.
	Services.run().learn_ability("teleport")
	await t.tree.process_frame
	await t.tree.process_frame
	model = bar.call(&"snapshot")
	t.equal(model.keys(), [AbilityBar.BOX_SLOT, &"dodge"], "the slots once the Teleport is in the box")
	if not t.check(model.has(AbilityBar.BOX_SLOT), "no Ability slot after learning the Teleport"):
		return
	t.equal(model[AbilityBar.BOX_SLOT]["ability_id"], "teleport", "the Ability slot shows the Teleport")
	t.equal(model[AbilityBar.BOX_SLOT]["label"], "D\nTeleport", "the Ability slot's label (D in the keys-only default)")
	t.equal(model[AbilityBar.BOX_SLOT]["cost"], 35, "the Teleport's cost chip")
	player.set_energy(10.0)
	model = bar.call(&"snapshot")
	t.equal(model[AbilityBar.BOX_SLOT]["label"], "Need 35E\nTeleport", "too little energy for a teleport")
	t.equal(model[AbilityBar.BOX_SLOT]["state"], "energy", "the teleport's state without energy")
	player.set_energy(100.0)
	t.check(bool(bar.call(&"activate", &"dodge")), "the bar's Roll slot did not roll")
	await t.steps(2)
	var label := str(bar.call(&"snapshot")[&"dodge"]["label"])
	t.check(label == "Busy\nRoll" or label.ends_with("s\nRoll"), "Roll label while rolling: %s" % label)


func test_window_pause_disables_the_bar(t: TestContext) -> void:
	# The Roll is young Burr's lesson since 2026-11-19 (on the bar once learned): lent here.
	Services.run().learn_session_ability("dodge")
	# The bar follows the learned abilities in its own `_process` (`process_frame` fires before it).
	await t.tree.process_frame
	await t.tree.process_frame
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
