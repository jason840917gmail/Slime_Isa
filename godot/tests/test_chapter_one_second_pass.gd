extends RefCounted
## Chapter 1's second pass: matched chunk seams, hidden hearts, cave exits and the east-west bridge.
const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const CHUNKS := "res://game/scenes/worlds/chunks/level-1-%s.tscn"
const MAP_ID := "level-1-c5"

func test_chunk_seams_and_hidden_hearts(t: TestContext) -> void:
	var worlds := {}
	for id: String in ["c4", "c5", "d4", "d5"]:
		worlds[id] = (load(CHUNKS % id) as PackedScene).instantiate()
	for seam: Array in [["c4", "d4", true], ["c4", "c5", false], ["c5", "d5", true], ["d4", "d5", false]]:
		var a := worlds[seam[0]].get_node("ground") as TileMapLayer
		var b := worlds[seam[1]].get_node("ground") as TileMapLayer
		for i in 32:
			var ac := Vector2i(31, i) if seam[2] else Vector2i(i, 31)
			var bc := Vector2i(0, i) if seam[2] else Vector2i(i, 0)
			t.equal(a.get_cell_source_id(ac), b.get_cell_source_id(bc), "%s/%s seam %d" % [seam[0], seam[1], i])
	var d4 := worlds["d4"] as Node
	for id: String in ["meadow-lakeside", "meadow-cliff-secret"]:
		t.check(d4.has_node("Chapter1/heart-chest-" + id), "missing heart chest " + id)
	for node: Node in d4.get_node("Encounters").get_children():
		t.check(not node.has_node("GooHeartScript"), "an exposed heart remains in D4")
	for world: Node in worlds.values():
		world.free()

func test_plateau_stairs_reach_the_top(t: TestContext) -> void:
	t.main.travel_to("level-1-c4")
	await t.until(func() -> bool: return t.in_world("level-1-c4") and not t.main.is_transitioning(), 5000.0)
	t.teleport_player(Vector2(704, 1010))
	t.world().elevation.track(t.player_body(), 0)
	await t.steps(3)
	t.press(&"move_down")
	var climbed := await t.until(func() -> bool: return t.world().elevation.level_of(t.player_body()) == 1, 2500.0)
	t.release_all()
	t.check(climbed, "north stairs did not reach the plateau")
	t.teleport_player(Vector2(1216, 1830))
	t.world().elevation.track(t.player_body(), 1)
	await t.steps(3)
	t.press(&"move_down")
	var descended := await t.until(func() -> bool: return t.world().elevation.level_of(t.player_body()) == 0, 2500.0)
	t.release_all()
	t.check(descended, "south stairs did not reach the lake road")

func test_held_roll_crosses_the_island_bridge_east_to_west(t: TestContext) -> void:
	Services.run().learn_session_ability("dodge")
	t.teleport_player(Vector2(16.4 * 64.0, 6.0 * 64.0 - 27.56))
	t.player().face(Vector2.LEFT)
	await t.steps(3)
	var watch := t.world().world_root.find_child("HazardWatch", true, false)
	if not t.check(watch != null, "no water hazard watch"):
		return
	var falls: Array = []
	watch.connect(&"fell", func(payload: Dictionary) -> void: falls.append(payload))
	t.press(&"move_left")
	t.press(&"dodge")
	var crossed := await t.until(func() -> bool: return t.player().get_centre().x < 9.8 * 64.0 or not falls.is_empty(), 3500.0)
	t.release_all()
	t.check(crossed and falls.is_empty(), "held Roll did not cross the east-west planks")
	t.check(t.player().get_centre().x < 10.0 * 64.0, "Roll did not reach the island")
func test_bomb_caves_have_working_return_doors(t: TestContext) -> void:
	for place: Array in [["level-1-c5", "lake-island-cave", "island-crack", Vector2(320, 320)],
			["level-1-d5", "hollow-hill-cave", "hill-crack", Vector2(1024, 768)]]:
		t.main.travel_to(str(place[0]))
		await t.until(func() -> bool: return t.in_world(str(place[0])) and not t.main.is_transitioning(), 5000.0)
		var crack := t.world().world_root.get_node("Chapter1/" + str(place[2]))
		t.check(bool(crack.call(&"receive_blast", {})), "bomb did not open " + str(place[2]))
		t.teleport_player((place[3] as Vector2) + Vector2(0, 30))
		t.world().elevation.track(t.player_body(), 1 if str(place[0]) == "level-1-d5" else 0)
		await t.steps(3)
		t.press(&"move_up")
		var entered := await t.until(func() -> bool: return t.in_world(str(place[1])) and not t.main.is_transitioning(), 4000.0)
		t.release_all()
		if not t.check(entered, "could not enter " + str(place[1])):
			continue
		t.teleport_player(Vector2(512, 760))
		await t.steps(3)
		t.press(&"move_down")
		var returned := await t.until(func() -> bool: return t.in_world(str(place[0])) and not t.main.is_transitioning(), 4000.0)
		t.release_all()
		t.check(returned, "could not leave " + str(place[1]))
