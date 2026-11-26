extends RefCounted
## Chapter 1's second pass: hidden hearts, the plateau stairs, cave exits and the east-west bridge.
## (Its matched chunk seams, the two chunks' grounds alike along every line, went with the chunk-line
## rule of 2026-11-01: each chunk closes its own side; tools/check_chunk_lines.gd checks the lines.)
const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const CHUNKS := "res://game/scenes/worlds/chunks/level-1-%s.tscn"
const MAP_ID := "level-1-c5"

## Hearts hide (level design, "Hearts are the exception", owner 2026-10-17): at most one heart in
## plain sight per map, the rest in chests and caves (pots' heart refills do not count). D4's meadow
## hearts wait in their chests.
func test_slimeshire_hearts_are_hidden(t: TestContext) -> void:
	for id: String in ["c4", "c5", "d4", "d5"]:
		var world := (load(CHUNKS % id) as PackedScene).instantiate()
		var in_sight := PackedStringArray()
		for heart: Node in world.find_children("GooHeartScript", "", true, false):
			in_sight.append(str(world.get_path_to(heart.get_parent())))
		t.check(in_sight.size() <= 1, "level-1-%s has %d hearts in plain sight: %s" % [id, in_sight.size(), ", ".join(in_sight)])
		if id == "d4":
			for heart: String in ["meadow-lakeside", "meadow-cliff-secret"]:
				t.check(world.has_node("Chapter1/heart-chest-" + heart), "missing heart chest " + heart)
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

## The island's falling planks (C5 (10-15, 5-6)) are longer than a quick roll: only the held Roll
## crosses them, and in the body-shapes mode (on everywhere) a hold rolls on only with the Roll's
## `roll-charge` upgrade, the Charged Roll (docs/godot/BODY_SHAPES.md, the Roll). The slime walks
## while the key is down before the roll launches (the 200 ms tap window and the 260 ms spin-up, about
## 80 units at the walk's 180), so the hold starts two cells east of the planks, on the shore.
func test_held_roll_crosses_the_island_bridge_east_to_west(t: TestContext) -> void:
	Services.run().learn_session_ability("dodge")
	Services.run().learn_session_ability("roll-charge")
	t.teleport_player(Vector2(18.0 * 64.0, 6.0 * 64.0 - 27.56))
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
