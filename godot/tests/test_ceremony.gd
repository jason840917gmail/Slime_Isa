extends RefCounted
## The ceremony for permanent things (roadmap 4.13, owner 2026-10-09): the first time a weapon, a
## tool or a key comes into the bag, by any way in, RunState announces it once
## (`permanent_item_gained`); quiet grants (the start weapon) count as celebrated without it. With
## main's `ability_ceremonies` on, a key and a level-1 Goo Heart each play the ceremony, one after
## the other, with the world paused.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const AbilityCeremony := preload("res://game/ui/ceremony/ability_ceremony.gd")
const GooHeartScript := preload("res://game/scripts/goo_heart.gd")

const HEART_NODE := "level-1-goo-heart-meadow-lakeside"
const CEREMONY_PAUSE := &"ceremony"


func test_a_permanent_item_is_announced_once(t: TestContext) -> void:
	var run := Services.run()
	var gained: Array = []
	var record := func(payload: Dictionary) -> void: gained.append(str(payload.get("item_id", "")))
	run.permanent_item_gained.connect(record)
	run.add_item("stone-axe", 1)
	run.remove_item("stone-axe", 1)
	run.add_item("stone-axe", 1)
	run.add_item("wood", 3)
	run.transact_items([], [{"item_id": "crystal-key", "count": 1}])
	run.quiet_items = true
	run.add_item("green-key", 1)
	run.quiet_items = false
	run.permanent_item_gained.disconnect(record)
	t.equal(gained, ["stone-axe", "crystal-key"], "the permanent items announced")
	t.check(run.is_item_celebrated("green-key"), "a quiet grant did not count the Verdant Key")
	t.check(run.is_item_celebrated("basic-sword"), "the start sword (a quiet grant) is not counted")
	t.check(not run.is_item_celebrated("wood"), "wood counted as a permanent item")


func test_the_card_says_what_the_item_is(t: TestContext) -> void:
	var tool := AbilityCeremony.item_entry("stone-axe")
	t.equal(str(tool["kicker"]), "New tool", "the stone axe's heading")
	t.check(str(tool["how"]).contains("trees"), "the stone axe's how-to: %s" % tool["how"])
	t.check(tool["icon"] is Texture2D, "the stone axe has no icon")
	t.equal(str(AbilityCeremony.item_entry("iron-spear")["kicker"]), "New weapon", "the iron spear's heading")
	var key := AbilityCeremony.item_entry("green-key")
	t.equal(str(key["kicker"]), "Key item", "the Verdant Key's heading")
	t.equal(str(key["name"]), "Verdant Key", "the Verdant Key's name")


func test_a_heart_and_a_key_play_the_ceremony_in_level_1(t: TestContext) -> void:
	var world := Services.world()
	t.main.set(&"ability_ceremonies", true)
	var heart := t.main.find_child(HEART_NODE, true, false) as Node2D
	if not t.check(heart != null, "no %s in level-1" % HEART_NODE):
		return
	var requested: Array = []
	var record := func(payload: Dictionary) -> void: requested.append(payload)
	var notifications: Object = t.main.quests.notifications
	notifications.connect(&"ceremony_requested", record)
	t.teleport_player(heart.global_position)
	var root := t.main.get_tree().root
	await t.until(func() -> bool: return _playing(root) == "Goo Heart", 1000.0)
	var ceremony := root.get_node_or_null(AbilityCeremony.NODE_NAME)
	if not t.check(ceremony != null, "the Goo Heart did not ask for the ceremony"):
		notifications.disconnect(&"ceremony_requested", record)
		return
	t.equal(_playing(root), "Goo Heart", "the ceremony playing")
	t.check(world.has_pause_reason(CEREMONY_PAUSE), "the world is not paused for the ceremony")
	Services.run().add_item("green-key", 1)
	await t.steps(2)
	t.equal(requested, [{"item_id": "green-key"}], "the ceremonies the notifications asked for")
	t.equal(int(ceremony.call(&"waiting")), 1, "the key's ceremony is not waiting its turn")
	ceremony.call(&"_finish", t.player())
	await t.until(func() -> bool: return _playing(root) == "Key item", 1000.0)
	t.equal(_playing(root), "Key item", "the ceremony after the heart's")
	notifications.disconnect(&"ceremony_requested", record)
	ceremony.call(&"_finish", t.player())
	ceremony.free()
	t.check(not world.has_pause_reason(CEREMONY_PAUSE), "the ceremony's pause stayed on")


## The heading of the ceremony playing ("" when none plays).
func _playing(root: Node) -> String:
	var ceremony := root.get_node_or_null(AbilityCeremony.NODE_NAME)
	return str(ceremony.call(&"current").get("kicker", "")) if ceremony != null else ""
