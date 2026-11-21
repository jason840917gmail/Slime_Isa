extends RefCounted
## Gloop Forest in Release 1 (docs/story/07-decisions-archive.md, 2026-11-19, plan step A8): the
## Silk gate to the Crystal Caverns, three web walls (`object.web-wall`, "side") across the web lane
## in chunk F4 (`web-lane/web-lane-1..3` at x 1536, 1680, 1824, y 1752): solid to a walk without the
## Silk skin, passed with it.
## Rewritten 2026-11-20: the quests A Harder Pick and Beyond the Verdant Gate are retired, with their
## tests (the reinforced pickaxe on the iron nodes, the weavers and fangs counted).

const TestContext := preload("res://tests/lib/test_context.gd")
const Services := preload("res://game/shared/services.gd")
const WebWallScript := preload("res://game/scripts/web_wall.gd")

const MAP_ID := "gloop-forest-f4"
const WALLS := ["web-lane/web-lane-1", "web-lane/web-lane-2", "web-lane/web-lane-3"]


func test_web_walls_close_the_web_lane_to_the_caverns_without_the_silk_skin(t: TestContext) -> void:
	var root := t.world().world_root
	var walls: Array[WebWallScript] = []
	for path: String in WALLS:
		var wall := root.get_node_or_null(path) as WebWallScript
		t.check(wall != null, "no web wall %s in F4" % path)
		if wall != null:
			walls.append(wall)
			t.equal(wall.orientation, "side", "%s's orientation" % path)
			t.check(not wall.is_cut(), "%s starts cut" % path)
	if walls.size() != WALLS.size():
		return
	# Walking east up the lane from west of the first wall stops at its face.
	var first := walls[0]
	var face := first.global_position.x - first.thickness / 2.0
	t.teleport_player(Vector2(face - 90.0, first.global_position.y - 27.56))
	await t.steps(3)
	t.press(&"move_right")
	await t.sim_wait(1200.0)
	t.release_all()
	t.check(t.player().get_centre().x < face, "the walk went through the lane's first web wall (%.1f, its face at %.1f)"
		% [t.player().get_centre().x, face])
