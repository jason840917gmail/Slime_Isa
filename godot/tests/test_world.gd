extends RefCounted
## level-1 world, camera and a long smoke run (docs/godot/specs/world.md sections 1-4,
## runtime.md 6.9).
## - level-1 is 64 x 64 tiles of 64 px (4096 px square) and its ground layer is full: 4096 cells.
## - The player spawns with its centre on the `player-spawn` marker (640, 704), feet at +27.56.
## - The camera centres on the player at start and then follows it, keeping it inside the
##   deadzone (clamp(vp.x * 0.18, 128, 224) x clamp(vp.y * 0.14, 96, 160) screen px).
## - 600 physics frames of play log no engine or script error (the runner fails any test that
##   logs one; this test just plays long enough, walking around, to give them a chance).

const TestContext := preload("res://tests/lib/test_context.gd")
const FeetAnchor := preload("res://game/shared/feet_anchor.gd")

const TILE_SIZE := 64
const COLUMNS := 64
const ROWS := 64
const SPAWN_CENTRE := Vector2(640.0, 704.0)
const PLAYER_DEPTH_ANCHOR := Vector2(0.0, 27.56)


func test_level1_dimensions_tiles_and_spawn(t: TestContext) -> void:
	var world := t.world()
	t.equal(world.map_id(), "level-1", "map id")
	var dims := world.dimensions()
	t.equal(int(dims.get("tile_size", 0)), TILE_SIZE, "tile size")
	t.equal(int(dims.get("columns", 0)), COLUMNS, "columns")
	t.equal(int(dims.get("rows", 0)), ROWS, "rows")
	t.equal(world.world_rect(), Rect2(0, 0, TILE_SIZE * COLUMNS, TILE_SIZE * ROWS), "world rect")
	if not t.check(world.ground_layer != null, "no ground TileMapLayer"):
		return
	var cells := world.ground_layer.get_used_cells()
	t.equal(cells.size(), COLUMNS * ROWS, "ground cells")
	var used := world.ground_layer.get_used_rect()
	t.equal(used, Rect2i(0, 0, COLUMNS, ROWS), "ground used rect")
	t.equal(world.player_spawn_marker(), SPAWN_CENTRE, "spawn marker")
	t.near_vec(t.player().get_centre(), SPAWN_CENTRE, 0.01, "player centre at start")
	t.near_vec(t.player_body().global_position, SPAWN_CENTRE + PLAYER_DEPTH_ANCHOR, 0.01, "player feet at start")
	t.equal(world.camera_mode(), "follow", "camera mode")


func test_camera_follows_player(t: TestContext) -> void:
	var camera = t.world().camera
	if not t.check(camera != null, "no camera registered with WorldService"):
		return
	t.check(camera.is_current(), "the world camera is not the current camera")
	t.check(camera.following and camera.follow_target == t.player_body(), "the camera is not following the player body")
	await t.steps(2)
	var start: Vector2 = camera.center
	var view: Vector2 = camera.get_viewport().get_visible_rect().size
	t.note("headless viewport %s, deadzone %s" % [view, camera.get_deadzone_size()])
	t.near_vec(start, _clamped(camera, t.player().get_centre()), 1.0, "camera centre at start")
	# Walk right for 1.5 s (300 px), then let the damping settle.
	t.press(&"move_right")
	await t.sim_wait(1500.0)
	t.release(&"move_right")
	await t.steps(40)
	var target := t.player().get_centre()
	var half: Vector2 = camera.get_deadzone_size() / (2.0 * camera.target_zoom)
	# At integer zoom the camera floors its scroll like Phaser's roundPixels, so the damped
	# catch-up stops once a frame's step is under 1 px: up to 1 / (1 - exp(-12 * dt)) px (5.5 px
	# at 60 fps) past the deadzone edge when moving right or down (world_camera.gd center_on).
	var stall := 1.0 / (1.0 - exp(-12.0 / 60.0)) + 0.5
	var gap: Vector2 = target - camera.center
	t.check(absf(gap.x) <= half.x + stall and absf(gap.y) <= half.y + stall,
		"player centre %s left the deadzone (camera %s, half deadzone %s, stall allowance %.1f)" % [target, camera.center, half, stall])
	t.check(camera.center.x - start.x > 150.0, "the camera moved only %.1f px while the player walked %.1f px" % [
		camera.center.x - start.x, target.x - SPAWN_CENTRE.x])
	t.near(camera.global_position.x, camera.center.x, 0.001, "camera node x = centre x")


func test_no_errors_during_600_frames(t: TestContext) -> void:
	# Walk a square while the world runs (NPCs wander, the camera follows, the HUD updates).
	var legs: Array[StringName] = [&"move_right", &"move_up", &"move_left", &"move_down"]
	for frame in 600:
		var leg := legs[int(frame / 150.0) % legs.size()]
		if frame % 150 == 0:
			t.release_all()
			t.press(leg)
		await t.steps(1)
		if t.aborted:
			return
	t.release_all()
	t.check(not t.player().is_dead(), "the player died during the smoke run")


## Phaser centerOn + bounds clamp for `point` (world spec 4.5), at the camera's current zoom.
static func _clamped(camera: Object, point: Vector2) -> Vector2:
	var view: Vector2 = camera.get_viewport().get_visible_rect().size / maxf(camera.target_zoom, 0.000001)
	var bounds: Rect2 = camera.bounds
	var min_c := bounds.position + view * 0.5
	var max_c := Vector2(maxf(min_c.x, bounds.end.x - view.x * 0.5), maxf(min_c.y, bounds.end.y - view.y * 0.5))
	return Vector2(clampf(point.x, min_c.x, max_c.x), clampf(point.y, min_c.y, max_c.y))
