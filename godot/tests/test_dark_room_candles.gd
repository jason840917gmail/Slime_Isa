extends RefCounted
## Dark rooms and their candles (docs/godot/DARKNESS.md "A share of the room per candle", owner
## 2026-11-25: "candles dont light up the room ... definitly a lot more"): every candle, sconce or
## brazier standing inside a dark room's rectangle (and every one it lists) lifts a share of its dark
## while it burns, (lit / all) ^ `darkness.candleShareCurve`; all burning, the room is lit; a room with
## no candle never lifts; `lifts_by_candles` off counts only the listed ones, all together (the
## Colossus's arena). A candle's light is its `light_radius`, else its kind's radius from the data.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const DarkRoom := preload("res://game/world/darkness/dark_room.gd")
const CandleScript := preload("res://game/world/fire/candle.gd")
const BRAZIER := preload("res://game/scenes/objects/brazier.tscn")

const ROOM_SIZE := Vector2(1152, 1024)


func test_each_burning_candle_inside_lifts_its_share_and_all_light_the_room(t: TestContext) -> void:
	var made := _room(t, [Vector2(100, 100), Vector2(1000, 100), Vector2(500, 900)])
	var room: Node2D = made[0]
	var fires: Array = made[1]
	var curve := _number("abilities.lantern.darkness.candleShareCurve", 0.5)
	t.equal((room.call(&"room_candles") as Array).size(), 3, "the three braziers inside are the room's candles (none listed)")
	t.near(float(room.call(&"lift_share")), 0.0, 0.001, "no candle burns: no lift")
	fires[0].call(&"light")
	t.near(float(room.call(&"lift_share")), pow(1.0 / 3.0, curve), 0.001, "one of three lifts its share on the curve")
	t.check(float(room.call(&"lift_share")) > 0.5, "the first candle is seen: more than half the dark lifts (%.2f)" % float(room.call(&"lift_share")))
	fires[1].call(&"light")
	fires[2].call(&"light")
	t.near(float(room.call(&"lift_share")), 1.0, 0.001, "all three lift it all")
	await t.steps(3)
	t.check(not bool(room.call(&"is_dark")), "all its candles burn: the room is lit")
	fires[2].call(&"put_out")
	await t.steps(3)
	t.check(bool(room.call(&"is_dark")), "one goes out: the room is dark again (its share lifted)")
	(made[2] as Node).free()


func test_a_room_with_no_candle_never_lifts(t: TestContext) -> void:
	var made := _room(t, [Vector2(ROOM_SIZE.x + 200, 100)])
	var room: Node2D = made[0]
	(made[1][0] as Node).call(&"light")
	t.equal((room.call(&"room_candles") as Array).size(), 0, "a brazier outside its rectangle is not its candle")
	t.near(float(room.call(&"lift_share")), 0.0, 0.001, "a room with no candle never lifts")
	await t.steps(3)
	t.check(bool(room.call(&"is_dark")), "it stays dark")
	(made[2] as Node).free()


func test_a_listed_candle_outside_counts_too(t: TestContext) -> void:
	var made := _room(t, [Vector2(200, 200), Vector2(ROOM_SIZE.x + 200, 100)])
	var room: Node2D = made[0]
	var fires: Array = made[1]
	var listed: Array[NodePath] = [room.get_path_to(fires[1])]
	room.set(&"candles", listed)
	t.equal((room.call(&"room_candles") as Array).size(), 2, "the one inside and the listed one outside")
	fires[1].call(&"light")
	t.near(float(room.call(&"lift_share")), pow(0.5, _number("abilities.lantern.darkness.candleShareCurve", 0.5)), 0.001,
		"the listed candle outside lifts its share")
	(made[2] as Node).free()


func test_without_lifts_by_candles_only_the_listed_count_and_only_together(t: TestContext) -> void:
	var made := _room(t, [Vector2(200, 200), Vector2(900, 200)], false)
	var room: Node2D = made[0]
	var fires: Array = made[1]
	fires[0].call(&"light")
	fires[1].call(&"light")
	t.equal((room.call(&"room_candles") as Array).size(), 0, "off: the braziers inside are not its candles (the Colossus's arena)")
	t.near(float(room.call(&"lift_share")), 0.0, 0.001, "off and none listed: their light shows only in their own circles")
	var listed: Array[NodePath] = [room.get_path_to(fires[0]), room.get_path_to(fires[1])]
	room.set(&"candles", listed)
	fires[1].call(&"put_out")
	t.near(float(room.call(&"lift_share")), 0.0, 0.001, "off: one of two listed lifts nothing")
	fires[1].call(&"light")
	t.near(float(room.call(&"lift_share")), 1.0, 0.001, "off: both listed lift it all")
	(made[2] as Node).free()


func test_a_candles_light_comes_from_the_data_by_kind(t: TestContext) -> void:
	var holder := Node2D.new()
	t.tree.root.add_child(holder)
	var candle := Node2D.new()
	candle.set_script(CandleScript)
	holder.add_child(candle)
	t.near(float(candle.call(&"light_radius_px")), _number("abilities.lantern.candle.lightRadiusPx", 0.0), 0.001, "a candle's light")
	var brazier := BRAZIER.instantiate() as Node2D
	holder.add_child(brazier)
	t.equal(str(brazier.get(&"light_kind")), "brazier", "the brazier scene is a brazier's light")
	t.near(float(brazier.call(&"light_radius_px")), _number("abilities.lantern.candle.brazierLightRadiusPx", 0.0), 0.001, "a brazier's light")
	t.check(float(brazier.call(&"light_radius_px")) > float(candle.call(&"light_radius_px")), "a brazier lights more than a candle")
	brazier.set(&"light_radius", 150.0)
	t.near(float(brazier.call(&"light_radius_px")), 150.0, 0.001, "its own `light_radius` wins (the Colossus's rings)")
	holder.free()


# --- helpers ----------------------------------------------------------------------------------------

## A dark room of ROOM_SIZE at the origin of a fresh holder and a cold brazier at each of `at` (from
## the room's corner). Returns [room, braziers, holder].
func _room(t: TestContext, at: Array, lifts := true) -> Array:
	var holder := Node2D.new()
	holder.position = Vector2(-20000, -20000)
	t.tree.root.add_child(holder)
	var room := Node2D.new()
	room.set_script(DarkRoom)
	room.set(&"size", ROOM_SIZE)
	room.set(&"lifts_by_candles", lifts)
	holder.add_child(room)
	var fires: Array = []
	for spot: Vector2 in at:
		var brazier := BRAZIER.instantiate() as Node2D
		brazier.set(&"burn_ms", -1.0)
		brazier.position = spot
		holder.add_child(brazier)
		fires.append(brazier)
	return [room, fires, holder]


func _number(path: String, fallback: float) -> float:
	var constants := Services.constants()
	var raw: Variant = constants.value(path) if constants != null else null
	return float(raw) if (raw is float or raw is int) else fallback
