extends RefCounted
## Player status effects (game/player/status_effects.gd; Phaser StatusEffects.ts, WorldScene
## applyWeb): a web roots the slime (no walking or rolling; it wears off), slow scales walking by its
## `speed` (0.55), burn hurts every 500 ms. The walk is `character.player.movement.baseSpeed` under
## `movementSpeedCap` (player spec 4.3; 180 since 2026-11-18).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const StatusEffects := preload("res://game/player/status_effects.gd")


## A web roots the slime: no walking and no Roll (the jump this test pressed is gone: hidden since
## 2026-10-08, nothing teaches it and no key runs it, player.gd `record_landing`); it wears off.
func test_web_roots_then_wears_off(t: TestContext) -> void:
	var player := t.player()
	# The Roll is young Burr's lesson since 2026-11-19: lent here.
	Services.run().learn_session_ability("dodge")
	player.apply_web(900.0)
	t.check(player.is_rooted(), "not rooted after a web")
	t.press(&"move_right")
	await t.steps(3)
	t.near_vec(t.player_body().velocity, Vector2.ZERO, 0.01, "velocity while rooted")
	t.tap(&"dodge")
	await t.steps(3)
	t.check(not player.is_rolling(), "a rooted slime rolled")
	await t.sim_wait(950.0)
	t.check(not player.is_rooted(), "still rooted after 900 ms")
	await t.steps(3)
	t.near(t.player_body().velocity.x, _walk_speed(), 0.01, "walking again after the web")
	t.release_all()


func test_slow_and_burn(t: TestContext) -> void:
	var player := t.player()
	player.apply_status(&"slow")
	t.press(&"move_right")
	await t.steps(3)
	var slow := float(StatusEffects.DEFINITIONS[&"slow"]["speed"])
	t.near(t.player_body().velocity.x, _walk_speed() * slow, 0.01, "walk speed while slowed (the walk x %s)" % slow)
	t.release_all()
	var hp_before: int = player.get_hp()
	player.apply_status(&"burn")
	await t.sim_wait(1100.0)
	t.between(float(hp_before - player.get_hp()), 6.0, 6.0, "burn damage in about 1 s (3 per 500 ms tick)")


static func _walk_speed() -> float:
	var constants := Services.constants()
	return minf(constants.number("character.player.movement.movementSpeedCap"),
		constants.number("character.player.movement.baseSpeed"))
