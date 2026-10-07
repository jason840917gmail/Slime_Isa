extends RefCounted
## Furniture placement (game/building/; docs/godot/specs/furniture.md 11.10): the ghost's target
## and free test, placing (record, mount, quest event), the wheel and cancelling, walking while
## placing, a placed bench as a station with "Hold: Pick up", the bench coming back on a load.
## A fresh level-1 has the player's centre at (640, 704); tests aim with `aim_override`.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const FurniturePlacement := preload("res://game/building/furniture_placement.gd")
const PlacedFurniture := preload("res://game/building/placed_furniture.gd")

const BENCH := "object.interior-workshop-workbench"
const VISE := "object.interior-workshop-workbench-vise"
const SPAWN := Vector2(640.0, 704.0)
const SLOT := 7


func _placement(t: TestContext) -> FurniturePlacement:
	return t.tree.get_first_node_in_group(&"furniture_placement") as FurniturePlacement


func _messages(t: TestContext, placement: FurniturePlacement) -> Array:
	var messages: Array = []
	t.listen(placement.message_shown, func(payload: Dictionary) -> void: messages.append(payload))
	return messages


func _start(t: TestContext, benches: int = 1) -> FurniturePlacement:
	Services.run().add_item("workbench", benches)
	t.teleport_player(SPAWN)
	await t.steps(2)
	var placement := _placement(t)
	placement.start("workbench")
	return placement


func _place_at(t: TestContext, placement: FurniturePlacement, aim: Vector2) -> void:
	placement.aim_override = aim
	await t.steps(2)
	t.tap(&"attack")
	await t.steps(3)


func test_describe_and_snap(t: TestContext) -> void:
	t.equal(FurniturePlacement.snap(700.0), 704.0, "snap 700")
	t.equal(FurniturePlacement.snap(650.0), 640.0, "snap 650")
	t.equal(FurniturePlacement.snap(16.0), 32.0, "snap 16 (halves go up)")
	t.equal(FurniturePlacement.snap(-16.0), 0.0, "snap -16")
	t.equal(FurniturePlacement.snap(-17.0), -32.0, "snap -17")
	var bench := PlacedFurniture.describe(BENCH)
	var sprite: Sprite2D = bench["sprite"]
	t.equal(sprite.frame, 8, "bench frame")
	t.near_vec(sprite.scale, Vector2(0.85, 0.85), 0.0001, "bench scale")
	var footprint: Rect2 = bench["footprint"]
	t.near_vec(footprint.position, Vector2(-39.644, -30.889), 0.001, "bench footprint position")
	t.near_vec(footprint.size, Vector2(79.288, 27.489), 0.001, "bench footprint size")
	t.equal((PlacedFurniture.describe(VISE)["sprite"] as Sprite2D).frame, 9, "vise frame")
	t.equal(PlacedFurniture.describe("object.nope"), {}, "an unknown scene")
	sprite.free()
	(PlacedFurniture.describe(VISE)["sprite"] as Sprite2D).free()


func test_start_shows_hint_and_blocks(t: TestContext) -> void:
	var placement := _placement(t)
	t.check(not placement.start("workbench"), "placement started without a bench in the bag")
	var messages := _messages(t, placement)
	placement = await _start(t)
	t.check(placement.is_active(), "placement did not start")
	t.equal(placement.variant_index(), 0, "first variant")
	t.equal(messages.size(), 1, "texts on start")
	if messages.size() > 0:
		t.equal(messages[0]["text"], "Left click to place · Mouse wheel to switch · Right click or Esc to cancel", "hint")
		t.near_vec(Vector2(messages[0]["x"], messages[0]["y"]), SPAWN - Vector2(0.0, 56.0), 0.5, "hint position")
	await t.steps(2)
	t.check(not t.main.interaction.has_candidate(), "the interaction offers a target while placing")
	t.check(not t.main.menu_windows.can_open_menu(), "the bag can open while placing")
	t.check(not t.tree.paused, "placing paused the game")
	placement.cancel()


func test_valid_and_invalid_targets(t: TestContext) -> void:
	var placement := await _start(t)
	var messages := _messages(t, placement)
	placement.aim_override = Vector2(700.0, 650.0)
	await t.steps(2)
	var target := placement.target()
	t.equal([target.get("x"), target.get("y"), target.get("valid")], [704.0, 640.0, true], "target near the spawn")
	t.near_vec((target["footprint"] as Rect2).position, Vector2(664.356, 609.111), 0.001, "footprint")
	placement.aim_override = Vector2(900.0, 704.0)
	await t.steps(2)
	t.equal([placement.target().get("x"), placement.target().get("valid")], [896.0, false], "out of reach (256 px)")
	t.tap(&"attack")
	await t.steps(2)
	t.check(placement.is_active(), "a refused press ended placement")
	t.equal(Services.run().item_count("workbench"), 1, "benches after a refused press")
	t.check(not t.player().is_action_locked(), "the press swung the weapon")
	t.check(messages.any(func(m: Dictionary) -> bool: return m["text"] == "Can't place it there"), "no refusal text")
	placement.aim_override = Vector2(640.0, 740.0)
	await t.steps(2)
	t.check(not bool(placement.target()["valid"]), "a footprint over the slime is valid")
	placement.cancel()


func test_place_commits_record_and_mount(t: TestContext) -> void:
	var placement := await _start(t)
	var messages := _messages(t, placement)
	var placed: Array = []
	t.listen(placement.placed, func(record: Dictionary) -> void: placed.append(record))
	await _place_at(t, placement, Vector2(700.0, 650.0))
	var run := Services.run()
	t.check(not placement.is_active(), "placement still active after placing")
	t.equal(run.item_count("workbench"), 0, "benches left in the bag")
	t.equal(run.placed_furniture("level-1"), [{"id": "placed-furniture-1", "item_id": "workbench", "scene_id": BENCH, "x": 704.0, "y": 640.0}], "records")
	t.equal(int(run.map_record("level-1")["next_placed_furniture_sequence"]), 2, "sequence")
	t.equal(placed.size(), 1, "placed signals")
	var node := PlacedFurniture.find("placed-furniture-1")
	if t.check(node != null, "no bench was mounted"):
		t.check(node is StaticBody2D, "the bench is not a StaticBody2D")
		t.near_vec(node.global_position, Vector2(704.0, 640.0), 0.01, "bench position")
	t.check(messages.any(func(m: Dictionary) -> bool: return m["text"] == "Placed Workbench" and m["color"] == &"green"), "no placed text")


func test_wheel_cancel_and_esc(t: TestContext) -> void:
	var placement := await _start(t)
	var hand: Variant = Services.run().equipped_weapon_id()
	t.tap(&"weapon_next")
	await t.steps(2)
	t.equal(placement.variant_index(), 1, "the wheel switched the variant")
	t.equal(Services.run().equipped_weapon_id(), hand, "the wheel switched the weapon")
	t.tap(&"interact")
	await t.steps(2)
	t.check(not placement.is_active(), "right click did not cancel")
	t.equal(Services.run().item_count("workbench"), 1, "the bench left the bag on cancel")
	placement.start("workbench")
	t.tap(&"pause")
	await t.steps(2)
	t.check(not placement.is_active(), "Esc did not cancel")
	t.check(not Services.shell().is_any_open() if Services.shell() != null else true, "Esc opened the pause menu")
	placement.start("workbench")
	await t.sim_wait(200.0)
	placement.cycle_variant(1)
	await _place_at(t, placement, Vector2(700.0, 650.0))
	t.equal(Services.run().placed_furniture("level-1")[0]["scene_id"], VISE, "placed variant")


func test_player_walks_while_placing(t: TestContext) -> void:
	var placement := await _start(t)
	placement.aim_override = Vector2(700.0, 650.0)
	var before := t.player().get_centre()
	t.press(&"move_right")
	await t.sim_wait(500.0)
	t.release_all()
	t.between(t.player().get_centre().x - before.x, 90.0, 110.0, "walked while placing")
	t.check(placement.is_active(), "walking ended placement")
	Services.run().learn_ability("jump")
	t.tap(&"jump")
	await t.steps(2)
	t.check(not t.player().is_ability_busy(), "a jump started while placing")
	placement.cancel()


func test_second_bench_blocked_by_first(t: TestContext) -> void:
	var placement := await _start(t, 2)
	await _place_at(t, placement, Vector2(700.0, 650.0))
	placement.start("workbench")
	placement.aim_override = Vector2(700.0, 650.0)
	await t.steps(2)
	t.check(not bool(placement.target()["valid"]), "a bench can go on another bench")
	await _place_at(t, placement, Vector2(800.0, 650.0))
	var records := Services.run().placed_furniture("level-1")
	t.equal(records.size(), 2, "records")
	if records.size() == 2:
		t.equal([records[1]["id"], records[1]["x"]], ["placed-furniture-2", 800.0], "second record")


func test_bench_station_and_hold_pick_up(t: TestContext) -> void:
	var placement := await _start(t)
	await _place_at(t, placement, Vector2(700.0, 650.0))
	var picked: Array = []
	t.listen(placement.picked_up, func(payload: Dictionary) -> void: picked.append(payload))
	t.teleport_player(Vector2(704.0, 700.0))
	await t.steps(2)
	var interaction = t.main.interaction
	interaction.refresh(null)
	var current: Dictionary = interaction.current()
	t.check(str(current.get("id", "")).begins_with("world-workbenches:"), "the placed bench is not offered: %s" % current.get("id", ""))
	t.equal(interaction.prompt_text(current), "Right-click: Use workbench     Hold: Pick up", "prompt")
	t.press(&"interact")
	await t.sim_wait(480.0)
	t.release(&"interact")
	await t.steps(2)
	t.check(PlacedFurniture.find("placed-furniture-1") == null, "the bench is still in the world")
	t.equal(Services.run().placed_furniture("level-1"), [], "records after the pick-up")
	t.equal(Services.run().item_count("workbench"), 1, "benches after the pick-up")
	t.equal(picked.size(), 1, "picked_up signals")
	t.equal(int(Services.run().map_record("level-1")["next_placed_furniture_sequence"]), 2, "the sequence never goes down")
	# A tap on a placed bench opens the crafting window instead.
	placement.start("workbench")
	await _place_at(t, placement, Vector2(700.0, 650.0))
	t.teleport_player(Vector2(704.0, 700.0))
	await t.steps(2)
	t.tap(&"interact")
	await t.steps(3)
	t.check(t.main.menu_windows.crafting.is_open(), "a tap on a placed bench did not open crafting")
	t.check(PlacedFurniture.find("placed-furniture-2") != null, "a tap picked the bench up")
	t.main.menu_windows.crafting.close()


func test_pick_up_refused_when_bag_full(t: TestContext) -> void:
	var placement := await _start(t)
	await _place_at(t, placement, Vector2(700.0, 650.0))
	var messages := _messages(t, placement)
	var run := Services.run()
	run.add_item("stone", run.item_capacity("stone"))
	t.check(not placement.pick_up("placed-furniture-1"), "picked up into a full bag")
	t.check(messages.any(func(m: Dictionary) -> bool: return m["text"] == "Inventory full" and bool(m["big"])), "no full-bag text")
	t.check(PlacedFurniture.find("placed-furniture-1") != null, "the bench left the world")


func test_bench_comes_back_on_load(t: TestContext) -> void:
	var placement := await _start(t)
	await _place_at(t, placement, Vector2(700.0, 650.0))
	var run := Services.run()
	t.check(run.save_slot(SLOT), "the save was not written")
	t.check(t.main.load_run(SLOT), "the save did not load")
	await t.steps(3)
	var node := PlacedFurniture.find("placed-furniture-1")
	if t.check(node != null, "the bench did not come back"):
		t.near_vec(node.global_position, Vector2(704.0, 640.0), 0.01, "bench position after the load")
	t.teleport_player(Vector2(704.0, 700.0))
	await t.steps(2)
	t.press(&"move_up")
	await t.sim_wait(600.0)
	t.release_all()
	t.check(t.player().get_centre().y > 630.0, "the slime walked through the bench (centre y %.1f)" % t.player().get_centre().y)


func test_crafting_a_bench_places_it_for_the_quest(t: TestContext) -> void:
	var quests = t.main.quests
	quests.debug_activate("a-place-to-work")
	var run := Services.run()
	run.add_item("wood", 40)
	t.teleport_player(SPAWN)
	await t.steps(2)
	t.check(t.main.menu_windows.open_crafting(), "the crafting window did not open")
	var crafting = t.main.menu_windows.crafting
	crafting.call(&"select_recipe", 0)
	crafting.call(&"craft")
	await t.steps(2)
	var placement := _placement(t)
	t.check(not crafting.is_open(), "the crafting window stayed open after crafting a bench")
	t.check(placement.is_active(), "crafting a bench did not start placement")
	await _place_at(t, placement, Vector2(700.0, 650.0))
	t.check(bool(quests.view("a-place-to-work").get("ready_to_turn_in", false)), "placing the bench did not finish the quest's stages")


func test_death_ends_placement(t: TestContext) -> void:
	var placement := await _start(t)
	t.player().defeated.emit({"receiverNodeId": ""})
	await t.steps(1)
	t.check(not placement.is_active(), "placement survived the slime's defeat (owner decision F1)")
