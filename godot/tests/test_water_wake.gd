extends RefCounted
## Water at the feet (docs/godot/specs/water.md "Wading", game/world/water_wake.gd).
## - The player in shallow water shows the wading splash; on land, nothing.
## - The splash animates: its frame changes while the slime walks through the water.
## - A body in the air (the jump) shows nothing until it lands in the water again.
## - Enemies splash too.
##
## level-1's lake, row 49: land at x = 1..6, shallow water at x = 7..11.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const WaterWake := preload("res://game/world/water_wake.gd")

const MAP_ID := "level-1"
const CELL := 64.0
const ROW := 49
const SHALLOW := Vector2i(8, ROW)
const LAND := Vector2i(4, ROW)


func test_the_player_splashes_in_shallow_water_only(t: TestContext) -> void:
	var wake := _wake(t)
	if not t.check(wake != null, "no water wake on the ground"):
		return
	var body := t.player_body()
	t.check(body.has_node(^"WaterWakeBack") and body.has_node(^"WaterWakeFront"), "the player has its wake sprites")
	t.equal(body.get_child(0).name, &"WaterWakeBack", "the ring's back half is drawn first, behind the art")
	t.teleport_player(_centre(SHALLOW))
	await t.steps(3)
	t.equal(wake.row_of(body), WaterWake.WADE_ROW, "wading splash in shallow water")
	t.teleport_player(_centre(LAND))
	await t.steps(3)
	t.equal(wake.row_of(body), WaterWake.NO_ROW, "nothing on land")


func test_the_splash_animates_while_walking(t: TestContext) -> void:
	var wake := _wake(t)
	var body := t.player_body()
	t.teleport_player(_centre(SHALLOW))
	await t.steps(2)
	var front := body.get_node(^"WaterWakeFront") as Sprite2D
	var columns := {}
	t.press(&"move_right")
	for i in 30:
		await t.steps(1)
		if wake.row_of(body) == WaterWake.WADE_ROW:
			columns[int(front.region_rect.position.x / WaterWake.CELL.x)] = true
	t.release_all()
	t.check(columns.size() >= 3, "the splash showed %d of its 4 frames in half a second of wading" % columns.size())


func test_no_splash_while_jumping(t: TestContext) -> void:
	var wake := _wake(t)
	var player := t.player()
	var body := t.player_body()
	Services.run().learn_ability("jump", true)
	t.teleport_player(_centre(SHALLOW))
	await t.steps(3)
	t.press(&"move_right")
	await t.steps(1)
	t.tap(&"jump")
	if not t.check(await t.until(func() -> bool: return player.is_airborne(), 200.0), "the jump did not start"):
		t.release_all()
		return
	t.release_all()
	await t.steps(2)
	t.equal(wake.row_of(body), WaterWake.NO_ROW, "no splash in the air")
	await t.until(func() -> bool: return not player.is_airborne(), 1500.0)
	await t.steps(2)
	t.equal(wake.row_of(body), WaterWake.WADE_ROW, "the splash is back on landing in the water")


func test_enemies_splash_too(t: TestContext) -> void:
	var wake := _wake(t)
	var enemy := t.spawn_worm(Vector2(200, 0), true)
	if not t.check(enemy != null, "no worm"):
		return
	await t.steps(2)
	t.place_worm(enemy, _centre(SHALLOW))
	await t.steps(3)
	t.equal(wake.row_of(enemy.body), WaterWake.WADE_ROW, "the worm wades")


func _wake(t: TestContext) -> WaterWake:
	return t.world().ground_layer.get_node_or_null(^"WaterWake") as WaterWake


func _centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
