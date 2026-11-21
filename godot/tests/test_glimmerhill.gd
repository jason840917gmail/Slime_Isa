extends RefCounted
## Glimmerhill asleep and the Pearls' homecoming (docs/godot/VILLAGERS.md "Asleep until its Pearl
## comes home", docs/godot/PROLOGUE.md "The homecoming"): each part of the town sleeps until its wake
## flag is set (its villagers frozen and out of the talk, its animals away, the TownSleep grey over
## its town rectangle, its goo fountain dry) and wakes live when it is; a Pearl taken and not home
## plays its homecoming at the Wellspring (west-village-b4), which sets `pearl.<id>.home`, the part's
## wake flag and the Pearl's other flags (Pearl 2: `workshop.restored`, Slimeshire's Workshop raised;
## Pearl 3: `forge.restored`, its Forge lit; owner, 2026-11-20), and counts for the main quest.
## B4: Market Hill's town rectangle (0, 0) 2048 x 1152; the Wellspring's pool at (500, 1588), the
## homecoming spot at (500, 1758).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const GlimmerhillWake := preload("res://game/glimmerhill/glimmerhill_wake.gd")
const VillagerScript := preload("res://game/world/villagers/villager_script.gd")
const Critter := preload("res://game/world/villagers/critter.gd")
const ShopCatalog := preload("res://game/shop/shop_catalog.gd")
const QuestEvents := preload("res://game/quests/quest_events.gd")

const MAP_ID := "west-village-b4"
const MARKET_HILL := "market-hill"
const MARKET_FLAG := "glimmerhill.market-hill.awake"
const WEST_FLAG := "glimmerhill.west-hill.awake"
const SOUTH_GATE_FLAG := "glimmerhill.south-gate.awake"
const TOWN := Rect2(0.0, 0.0, 2048.0, 1152.0)
const HOME_SPOT := Vector2(500.0, 1758.0)
## Far from the pool (beyond its 300-unit reach), on the town's road.
const AWAY := Vector2(1024.0, 1000.0)
const SHOP_ROOM := "west-village-shop"


func test_market_hill_sleeps_until_its_flag_and_then_wakes(t: TestContext) -> void:
	var run := Services.run()
	t.check(not GlimmerhillWake.is_awake(MARKET_HILL), "Market Hill starts awake")
	var root := t.world().world_root
	var villagers := _in_town(_villagers(root))
	if not t.check(not villagers.is_empty(), "no villagers in Market Hill"):
		return
	for villager: VillagerScript in villagers:
		t.check(villager.is_asleep(), "%s is awake before Market Hill's Pearl" % villager.name)
		t.check(not villager.is_in_group(&"npc") and not villager.is_in_group(&"interactable"),
			"the sleeping %s can be talked to" % villager.name)
	var critters := _in_town(_critters(root))
	for critter: Critter in critters:
		t.check(not critter.visible and critter.collision_layer == 0 and critter.collision_mask == 0,
			"the animal %s is out while its town sleeps" % critter.name)
	var overlay := root.get_node_or_null("TownSleep")
	t.check(overlay != null, "no TownSleep grey over the sleeping town")
	var fountains := _fountains(t)
	t.check(not fountains.is_empty(), "no goo fountain in Market Hill")
	for fountain: Node in fountains:
		t.check(bool(fountain.call(&"is_dry")), "the goo fountain runs while its part sleeps")
	run.set_flag(MARKET_FLAG)
	var woken := await t.until(func() -> bool:
		for villager: VillagerScript in villagers:
			if villager.is_asleep():
				return false
		return true, 4000.0)
	t.check(woken, "Market Hill's villagers did not all wake within 4 s")
	for villager: VillagerScript in villagers:
		t.check(villager.is_in_group(&"npc"), "the woken %s cannot be talked to" % villager.name)
	await t.sim_wait(2500.0)
	for critter: Critter in critters:
		t.check(critter.visible and critter.modulate.a > 0.99, "the animal %s did not come back" % critter.name)
	t.check(root.get_node_or_null("TownSleep") == null, "the TownSleep grey stayed after the town woke")
	for fountain: Node in fountains:
		t.check(not bool(fountain.call(&"is_dry")), "the goo fountain stayed dry after its part woke")


func test_a_woken_part_is_awake_when_built_again(t: TestContext) -> void:
	Services.run().set_flag(MARKET_FLAG)
	if not await _travel(t, MAP_ID):
		return
	var root := t.world().world_root
	for villager: VillagerScript in _in_town(_villagers(root)):
		t.check(not villager.is_asleep(), "%s sleeps in a woken Market Hill" % villager.name)
	t.check(root.get_node_or_null("TownSleep") == null, "a woken town was built grey")


func test_fatty_s_pearl_comes_home_and_wakes_market_hill(t: TestContext) -> void:
	var run := Services.run()
	var quests: Node = t.main.quests
	var homecoming := _homecoming(t)
	if not t.check(homecoming != null, "no WellspringHomecoming in B4"):
		return
	t.teleport_player(AWAY)
	await t.steps(3)
	t.check(not bool(homecoming.call(&"is_playing")), "the homecoming played without a Pearl")
	# No Pearl: nothing happens at the pool.
	_stand(t, HOME_SPOT)
	await t.sim_wait(600.0)
	t.check(not bool(homecoming.call(&"is_playing")), "the homecoming played without a Pearl taken")
	_stand(t, AWAY)
	await t.steps(2)
	run.set_flag("pearl.fatty-one-eye")
	quests.call(&"handle_event", QuestEvents.BOSS_DEFEATED, {"bossId": "fatty-one-eye"})
	_stand(t, HOME_SPOT)
	t.check(await t.until(func() -> bool: return bool(homecoming.call(&"is_playing")), 1000.0),
		"the homecoming did not start at the pool with Fatty's Pearl")
	var done := await t.until(func() -> bool: return not bool(homecoming.call(&"is_playing")), 20000.0, 60000.0)
	if not t.check(done, "the homecoming did not end within 20 s"):
		return
	t.check(run.has_flag("pearl.fatty-one-eye.home"), "Fatty's Pearl is not home")
	t.check(run.has_flag(MARKET_FLAG), "Market Hill did not wake")
	t.check(not run.has_flag(WEST_FLAG), "West Hill woke with Fatty's Pearl")
	t.equal(GlimmerhillWake.pearls_home(), 1, "Pearls home")
	t.equal(str((quests.call(&"state", "win-back-the-pearls") as Dictionary).get("active_stage_id", "")), "pearl-2",
		"the main quest after Fatty's Pearl came home")
	# Walking up to the pool again plays nothing.
	_stand(t, AWAY)
	await t.steps(2)
	_stand(t, HOME_SPOT)
	await t.sim_wait(600.0)
	t.check(not bool(homecoming.call(&"is_playing")), "the homecoming played again for a Pearl already home")


func test_the_matron_s_pearl_wakes_west_hill_and_raises_the_workshop(t: TestContext) -> void:
	var run := Services.run()
	var homecoming := _homecoming(t)
	if not t.check(homecoming != null, "no WellspringHomecoming in B4"):
		return
	run.set_flag("pearl.orb-weaver-matron")
	_stand(t, HOME_SPOT)
	t.check(await t.until(func() -> bool: return bool(homecoming.call(&"is_playing")), 1000.0),
		"the homecoming did not start with the Matron's Pearl")
	var done := await t.until(func() -> bool: return not bool(homecoming.call(&"is_playing")), 20000.0, 60000.0)
	if not t.check(done, "the homecoming did not end within 20 s"):
		return
	t.check(run.has_flag("pearl.orb-weaver-matron.home"), "the Matron's Pearl is not home")
	t.check(run.has_flag(WEST_FLAG), "West Hill did not wake")
	t.check(run.has_flag("workshop.restored"), "the Matron's Pearl did not raise the Workshop")
	t.check(not run.has_flag("forge.restored"), "the Matron's Pearl lit the Forge")
	t.check(not run.has_flag(MARKET_FLAG), "Market Hill woke with the Matron's Pearl")


func test_the_colossus_s_pearl_wakes_the_south_gate_and_lights_the_forge(t: TestContext) -> void:
	var run := Services.run()
	var homecoming := _homecoming(t)
	if not t.check(homecoming != null, "no WellspringHomecoming in B4"):
		return
	run.set_flag("pearl.crystal-colossus")
	_stand(t, HOME_SPOT)
	t.check(await t.until(func() -> bool: return bool(homecoming.call(&"is_playing")), 1000.0),
		"the homecoming did not start with the Colossus's Pearl")
	var done := await t.until(func() -> bool: return not bool(homecoming.call(&"is_playing")), 20000.0, 60000.0)
	if not t.check(done, "the homecoming did not end within 20 s"):
		return
	t.check(run.has_flag("pearl.crystal-colossus.home"), "the Colossus's Pearl is not home")
	t.check(run.has_flag(SOUTH_GATE_FLAG), "the south gate's quarter did not wake")
	t.check(run.has_flag("forge.restored"), "the Colossus's Pearl did not light the Forge")
	t.check(not run.has_flag("workshop.restored"), "the Colossus's Pearl raised the Workshop")


func test_dollop_sleeps_and_her_counter_opens_with_market_hill(t: TestContext) -> void:
	if not await _travel(t, SHOP_ROOM):
		return
	var root := t.world().world_root
	var villagers := _villagers(root)
	t.check(not villagers.is_empty(), "no villagers in the shop")
	for villager: VillagerScript in villagers:
		t.check(villager.is_asleep(), "%s is awake in the sleeping shop" % villager.name)
	var counter := root.find_child("shop-counter", true, false)
	if not t.check(counter != null, "no shop counter in the shop"):
		return
	t.check(not bool(counter.call(&"can_use")), "the counter sells while Market Hill sleeps")
	t.check(not ShopCatalog.is_open("dollop"), "Dollop's shop is open while she sleeps")
	Services.run().set_flag(MARKET_FLAG)
	await t.sim_wait(1500.0)
	for villager: VillagerScript in villagers:
		t.check(not villager.is_asleep(), "%s did not wake in the shop" % villager.name)
	t.check(ShopCatalog.is_open("dollop"), "Dollop's shop did not open with Market Hill")


# --- helpers ---------------------------------------------------------------------------------------

static func _villagers(root: Node) -> Array[VillagerScript]:
	var out: Array[VillagerScript] = []
	for node: Node in root.find_children("*", "", true, false):
		if node is VillagerScript:
			out.append(node as VillagerScript)
	return out


static func _critters(root: Node) -> Array[Critter]:
	var out: Array[Critter] = []
	for node: Node in root.find_children("*", "", true, false):
		if node is Critter:
			out.append(node as Critter)
	return out


## The ones whose feet are inside Market Hill's town rectangle.
static func _in_town(nodes: Array) -> Array:
	var out := []
	for node: Variant in nodes:
		var feet: Vector2 = (node.get(&"body") as Node2D).global_position if node.get(&"body") is Node2D \
			else (node as Node2D).global_position
		if TOWN.has_point(feet):
			out.append(node)
	return out


func _fountains(t: TestContext) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in t.tree.get_nodes_in_group(&"goo_fountains"):
		if node.is_inside_tree() and str(node.call(&"part_id")) == MARKET_HILL:
			out.append(node)
	return out


func _homecoming(t: TestContext) -> Node:
	return t.world().world_root.find_child("WellspringHomecoming", true, false)


## Puts the slime's feet at `feet`, still.
func _stand(t: TestContext, feet: Vector2) -> void:
	var body := t.player_body()
	body.velocity = Vector2.ZERO
	body.global_position = feet
	body.reset_physics_interpolation()


static func _travel(t: TestContext, map: String) -> bool:
	if not t.check(t.main.travel_to(map), "travel to %s was refused" % map):
		return false
	var arrived := await t.until(func() -> bool:
		return not t.main.is_transitioning() and t.world().map_id() == map and t.player() != null, 3000.0, 6000.0)
	if not t.check(arrived, "the player did not reach %s" % map):
		return false
	await t.steps(2)
	return true
