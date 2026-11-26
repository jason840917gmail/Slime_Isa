extends RefCounted
## Water at the feet (docs/godot/specs/water.md "Wading", game/world/water_wake.gd).
## - The player in shallow water shows the wading splash; on land, nothing.
## - The splash animates: its frame changes while the slime walks through the water.
## - Enemies splash too.
## (A body in the air shows nothing either; the player's jump that test drove is gone: hidden since
## 2026-10-08, nothing teaches it and no key runs it, player.gd `record_landing`.)
##
## level-1's lake, in chunk world level-1-c5 (level-1 is cut into chunk worlds,
## docs/godot/WORLD_ATLAS.md), chunk row 15: shallow water at x = 10..13, land at x = 16..19.

const TestContext := preload("res://tests/lib/test_context.gd")
const WaterWake := preload("res://game/world/water_wake.gd")

const MAP_ID := "level-1-c5"
const CELL := 64.0
const ROW := 15
const SHALLOW := Vector2i(10, ROW)
const LAND := Vector2i(17, ROW)


func test_the_player_splashes_in_shallow_water_only(t: TestContext) -> void:
	var wake := _wake(t)
	if not t.check(wake != null, "no water wake on the ground"):
		return
	var body := t.player_body()
	t.check(body.has_node(^"WaterWakeBack") and body.has_node(^"WaterWakeFront"), "the player has its wake sprites")
	# The back half is drawn before the slime's art (behind it), the front half after it. (The
	# body-shapes mode's charge ring, ShapeChargeRing, is the body's first child since 2026-10-24:
	# BODY_SHAPES.md "shape_visuals.gd"; both lie behind the art.)
	var art: Node = t.player().visual
	while art != null and art.get_parent() != body:
		art = art.get_parent()
	if not t.check(art != null, "the slime's art is not under its body"):
		return
	var visual_index := art.get_index()
	t.check(body.get_node(^"WaterWakeBack").get_index() < visual_index,
		"the ring's back half is not drawn behind the art (index %d, the Visual's %d)" % [
			body.get_node(^"WaterWakeBack").get_index(), visual_index])
	t.check(body.get_node(^"WaterWakeFront").get_index() > visual_index,
		"the ring's front half is not drawn in front of the art (index %d, the Visual's %d)" % [
			body.get_node(^"WaterWakeFront").get_index(), visual_index])
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
