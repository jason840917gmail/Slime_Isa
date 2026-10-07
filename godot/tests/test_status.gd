extends RefCounted
## Player status effects (game/player/status_effects.gd; Phaser StatusEffects.ts, WorldScene
## applyWeb): a web roots the slime (no walking or jumping; it wears off), slow scales walking by
## 0.55, burn hurts every 500 ms.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")


func test_web_roots_then_wears_off(t: TestContext) -> void:
	var player := t.player()
	Services.run().learn_ability("jump")
	player.apply_web(900.0)
	t.check(player.is_rooted(), "not rooted after a web")
	t.press(&"move_right")
	await t.steps(3)
	t.near_vec(t.player_body().velocity, Vector2.ZERO, 0.01, "velocity while rooted")
	t.tap(&"jump")
	await t.steps(3)
	t.check(not player.is_ability_busy(), "a rooted slime jumped")
	await t.sim_wait(950.0)
	t.check(not player.is_rooted(), "still rooted after 900 ms")
	await t.steps(3)
	t.near(t.player_body().velocity.x, 200.0, 0.01, "walking again after the web")
	t.release_all()


func test_slow_and_burn(t: TestContext) -> void:
	var player := t.player()
	player.apply_status(&"slow")
	t.press(&"move_right")
	await t.steps(3)
	t.near(t.player_body().velocity.x, 110.0, 0.01, "walk speed while slowed (200 x 0.55)")
	t.release_all()
	var hp_before: int = player.get_hp()
	player.apply_status(&"burn")
	await t.sim_wait(1100.0)
	t.between(float(hp_before - player.get_hp()), 6.0, 6.0, "burn damage in about 1 s (3 per 500 ms tick)")
