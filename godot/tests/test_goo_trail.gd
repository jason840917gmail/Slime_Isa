extends RefCounted
## Goo Trail (game/player/goo_trail.gd; abilities spec 12): once learned, walking drops a smear
## every 30 px and enemies near a fresh smear are slowed.

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")


func test_trail_drops_marks_only_when_learned(t: TestContext) -> void:
	var trail: Node = null
	for node: Node in t.world().world_root.get_children():
		if String(node.name) == "GooTrail":
			trail = node
	if not t.check(trail != null, "no GooTrail in the world"):
		return
	t.press(&"move_right")
	await t.steps(20)
	t.equal(trail.fresh_points(Services.now_ms()).size(), 0, "smears without the passive")
	Services.run().learn_ability("goo-trail")
	await t.steps(30)
	t.release_all()
	var count: int = trail.fresh_points(Services.now_ms()).size()
	t.between(float(count), 2.0, 4.0, "smears after 0.5 s of walking at 200 px/s (one per 30 px)")
